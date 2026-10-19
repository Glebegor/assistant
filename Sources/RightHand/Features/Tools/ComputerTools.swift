import Foundation

/// Moves a file or folder to the Trash, so it can be put back from there.
struct DeleteFileTool: AssistantTool {
    let access: FileAccess

    let name = "delete_file"
    var displayName: String { L("Delete files") }
    let description = """
    Moves a file or folder on the user's Mac to the Trash (the user can put it back from there). \
    Use it only when the user asks to delete or clean up something.
    """
    var inputSchema: JSONValue {
        ["type": "object",
         "properties": ["path": ["type": "string", "description": "File or folder path (absolute, ~/…, or relative to the first project folder)."]],
         "required": ["path"]]
    }
    var canAlwaysAllow: Bool { false }

    func describe(_ input: JSONValue) -> String { L("Move %@ to the Trash", input["path"]?.string ?? L("a file")) }

    func run(_ input: JSONValue) async -> ToolOutput {
        do {
            let url = try access.resolve(try input.requiredString("path"))
            guard FileManager.default.fileExists(atPath: url.path) else { return .error("\(url.path) doesn't exist.") }
            let protected = ["/", NSHomeDirectory()] + access.roots.map { FileAccess.canonicalPath($0) }
            guard !protected.contains(url.path), url.pathComponents.count > 3 else {
                return .error("Refusing to delete \(url.path): it is a top-level or project folder.")
            }
            var trashed: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
            return ToolOutput(text: "Moved \(url.path) to the Trash.")
        } catch {
            return .error(error.localizedDescription)
        }
    }
}

/// Moves, renames or copies a file or folder.
struct MoveFileTool: AssistantTool {
    let access: FileAccess

    let name = "move_file"
    var displayName: String { L("Move and copy files") }
    let description = """
    Moves, renames or copies a file or folder on the user's Mac. If `to` is an existing folder, \
    the item goes inside it. Never overwrites: fails if the destination already exists.
    """
    var inputSchema: JSONValue {
        ["type": "object",
         "properties": [
             "from": ["type": "string", "description": "What to move or copy."],
             "to": ["type": "string", "description": "New path, or an existing folder to put it in."],
             "copy": ["type": "boolean", "description": "Copy instead of moving. Default false."],
         ],
         "required": ["from", "to"]]
    }

    func alwaysAsks(_ input: JSONValue) -> Bool {
        access.isOutsideProject(input["from"]?.string) || access.isOutsideProject(input["to"]?.string)
    }

    func describe(_ input: JSONValue) -> String {
        let from = input["from"]?.string ?? L("a file"), to = input["to"]?.string ?? "?"
        return input["copy"]?.bool == true ? L("Copy %@ to %@", from, to) : L("Move %@ to %@", from, to)
    }

    func run(_ input: JSONValue) async -> ToolOutput {
        do {
            let source = try access.resolve(try input.requiredString("from"))
            var destination = try access.resolve(try input.requiredString("to"))
            let files = FileManager.default
            guard files.fileExists(atPath: source.path) else { return .error("\(source.path) doesn't exist.") }
            var isFolder: ObjCBool = false
            if files.fileExists(atPath: destination.path, isDirectory: &isFolder), isFolder.boolValue {
                destination = destination.appending(path: source.lastPathComponent)
            }
            guard !files.fileExists(atPath: destination.path) else { return .error("\(destination.path) already exists.") }
            try files.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let copy = input["copy"]?.bool == true
            if copy { try files.copyItem(at: source, to: destination) } else { try files.moveItem(at: source, to: destination) }
            return ToolOutput(text: "\(copy ? "Copied" : "Moved") \(source.path) to \(destination.path).")
        } catch {
            return .error(error.localizedDescription)
        }
    }
}

struct CreateFolderTool: AssistantTool {
    let access: FileAccess

    let name = "create_folder"
    var displayName: String { L("Create folders") }
    let description = "Creates a folder (and any missing parent folders) on the user's Mac."
    var inputSchema: JSONValue {
        ["type": "object",
         "properties": ["path": ["type": "string", "description": "Folder path (absolute, ~/…, or relative to the first project folder)."]],
         "required": ["path"]]
    }

    func alwaysAsks(_ input: JSONValue) -> Bool { access.isOutsideProject(input["path"]?.string) }

    func describe(_ input: JSONValue) -> String { L("Create folder %@", input["path"]?.string ?? "") }

    func run(_ input: JSONValue) async -> ToolOutput {
        do {
            let url = try access.resolve(try input.requiredString("path"))
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return ToolOutput(text: "Created \(url.path).")
        } catch {
            return .error(error.localizedDescription)
        }
    }
}

/// Runs a shell command in Terminal's shell (zsh), after you have seen the exact command.
struct RunCommandTool: AssistantTool {
    let access: FileAccess
    private static let maxCharacters = 30_000

    let name = "run_command"
    var displayName: String { L("Run Terminal commands") }
    let description = """
    Runs a shell command on the user's Mac with zsh and returns its output and exit code. \
    The user sees the exact command and approves every run. Use it for things the other tools can't do \
    (git, build tools, scripts, system information). Commands can't be interactive: there is no input, \
    and they are stopped after the timeout. Prefer the file tools for reading and writing files.
    """
    var inputSchema: JSONValue {
        ["type": "object",
         "properties": [
             "command": ["type": "string", "description": "The command line to run, e.g. `git status`."],
             "directory": ["type": "string", "description": "Folder to run it in. Defaults to the first project folder or the home folder."],
             "timeout_seconds": ["type": "integer", "description": "Stop it after this many seconds, 1–600. Default 60."],
         ],
         "required": ["command"]]
    }
    var canAlwaysAllow: Bool { false }

    func describe(_ input: JSONValue) -> String {
        L("Run a command in %@", input["directory"]?.string ?? access.base?.path ?? "~")
    }

    func detail(_ input: JSONValue) -> String? { input["command"]?.string }

    func run(_ input: JSONValue) async -> ToolOutput {
        do {
            let command = try input.requiredString("command")
            let folder = try access.resolve(input["directory"]?.string ?? access.base?.path ?? NSHomeDirectory())
            let timeout = TimeInterval(min(600, max(1, input["timeout_seconds"]?.int ?? 60)))
            let result = try await ShellCommand.run(command, in: folder, timeout: timeout)
            var text = result.output.isEmpty ? "(no output)" : result.output
            if text.count > Self.maxCharacters {
                let half = Self.maxCharacters / 2
                text = String(text.prefix(half)) + "\n… (\(text.count - Self.maxCharacters) characters not shown) …\n" + String(text.suffix(half))
            }
            if result.timedOut { return .error("Stopped after \(Int(timeout)) seconds.\n" + text) }
            return ToolOutput(text: "Exit code \(result.status)\n" + text, isError: result.status != 0)
        } catch {
            return .error(error.localizedDescription)
        }
    }
}

/// Runs `zsh -l -c <command>` with no input, stopping it on timeout or when the chat is stopped.
enum ShellCommand {
    struct Result: Sendable {
        let output: String
        let status: Int32
        let timedOut: Bool
    }

    static func run(_ command: String, in folder: URL, timeout: TimeInterval) async throws -> Result {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isFolder), isFolder.boolValue else {
            throw ToolError("\(folder.path) is not a folder.")
        }
        // Output goes to a file, not a pipe, so a command that prints a lot (or leaves a
        // background process holding the pipe) can never block us.
        let log = FileManager.default.temporaryDirectory.appending(path: "righthand-command-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: log) }
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }

        let process = Process()
        process.executableURL = URL(filePath: "/bin/zsh")
        process.arguments = ["-l", "-c", command]
        process.currentDirectoryURL = folder
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = handle
        process.standardError = handle
        let box = ProcessBox(process)

        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: error)
                    return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { box.stop(timedOut: true) }
            }
        } onCancel: {
            box.stop(timedOut: false)
        }
        let data = (try? Data(contentsOf: log)) ?? Data()
        return Result(output: String(decoding: data, as: UTF8.self), status: status, timedOut: box.timedOut)
    }

    /// Lets the timeout and the Stop button end the process from other threads.
    private final class ProcessBox: @unchecked Sendable {
        private let process: Process
        private let lock = NSLock()
        private var didTimeOut = false

        init(_ process: Process) { self.process = process }

        var timedOut: Bool { lock.withLock { didTimeOut } }

        func stop(timedOut: Bool) {
            lock.withLock {
                guard process.isRunning else { return }
                if timedOut { didTimeOut = true }
                process.terminate()
            }
        }
    }
}
