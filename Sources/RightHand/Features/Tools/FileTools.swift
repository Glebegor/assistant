import Foundation

/// Where a project's tools may touch files: the project folders, or the whole Mac when
/// "Work with the whole Mac" is on (paths outside the project folders then always ask first).
struct FileAccess: Sendable {
    let roots: [URL]
    let anywhere: Bool

    init(folders: [String], anywhere: Bool = false) {
        roots = folders.map { URL(filePath: ($0 as NSString).expandingTildeInPath, directoryHint: .isDirectory) }
        self.anywhere = anywhere
    }

    /// Relative paths start here: the first project folder, or the home folder.
    var base: URL? { roots.first ?? (anywhere ? URL(filePath: NSHomeDirectory(), directoryHint: .isDirectory) : nil) }

    /// Absolute, `~/…`, or relative to the first folder.
    func resolve(_ path: String) throws -> URL {
        guard let base else { throw ToolError("No folders are added to this project. Ask the user to add one in the project settings.") }
        let expanded = (path as NSString).expandingTildeInPath
        let target = Self.canonicalPath(expanded.hasPrefix("/") ? URL(filePath: expanded) : base.appending(path: expanded))
        guard anywhere || isInsideProject(target) else {
            throw ToolError("\(path) is outside the project folders: \(roots.map(\.path).joined(separator: ", ")).")
        }
        return URL(filePath: target)
    }

    /// Whether a path is inside one of the project folders.
    func isInsideProject(_ canonical: String) -> Bool {
        roots.contains { Self.isInside(canonical, Self.canonicalPath($0)) }
    }

    /// True when `path` can't be checked or points outside the project folders.
    func isOutsideProject(_ path: String?) -> Bool {
        guard let path, let url = try? resolve(path) else { return true }
        return !isInsideProject(url.path)
    }

    /// The real location of a path: `.` and `..` removed and symlinks resolved, also for files
    /// that don't exist yet (resolved through their closest existing folder).
    static func canonicalPath(_ url: URL) -> String {
        var parts: [String] = []
        for part in url.path.split(separator: "/") where part != "." {
            if part == ".." { _ = parts.popLast() } else { parts.append(String(part)) }
        }
        var existing = "/" + parts.joined(separator: "/")
        var missing: [String] = []
        while existing != "/", !FileManager.default.fileExists(atPath: existing) {
            missing.insert((existing as NSString).lastPathComponent, at: 0)
            existing = (existing as NSString).deletingLastPathComponent
        }
        let resolved = URL(filePath: existing).resolvingSymlinksInPath().path
        return missing.isEmpty ? resolved : (resolved == "/" ? "" : resolved) + "/" + missing.joined(separator: "/")
    }

    static func isInside(_ path: String, _ folder: String) -> Bool {
        path == folder || path.hasPrefix(folder.hasSuffix("/") ? folder : folder + "/")
    }

    /// Folders and files that are never worth listing or searching.
    static func isSkipped(_ name: String) -> Bool {
        name.hasPrefix(".") || ["node_modules", "build", "DerivedData", "Pods"].contains(name)
    }
}

struct ListFilesTool: AssistantTool {
    let access: FileAccess

    let name = "list_files"
    var displayName: String { L("List files") }
    let description = """
    Lists files and folders on the user's Mac (the project folders, or anywhere when the user allows it). \
    Call this to explore a folder before reading or searching files in it.
    """
    var inputSchema: JSONValue {
        ["type": "object",
         "properties": [
             "path": ["type": "string", "description": "Folder to list (absolute, ~/…, or relative to the first project folder). Defaults to the first project folder."],
             "depth": ["type": "integer", "description": "How many levels deep, 1–3. Default 1."],
         ]]
    }

    func alwaysAsks(_ input: JSONValue) -> Bool { access.isOutsideProject(input["path"]?.string ?? access.roots.first?.path) }

    func describe(_ input: JSONValue) -> String { L("List %@", input["path"]?.string ?? L("the project folder")) }

    func run(_ input: JSONValue) async -> ToolOutput {
        do {
            let folder = try access.resolve(input["path"]?.string ?? access.base?.path ?? "")
            let depth = min(3, max(1, input["depth"]?.int ?? 1))
            var lines: [String] = []
            list(folder, prefix: "", depth: depth, into: &lines)
            if lines.count >= 400 { lines.append("… (more entries not shown)") }
            return ToolOutput(text: "\(folder.path):\n" + (lines.isEmpty ? "(empty)" : lines.joined(separator: "\n")))
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private func list(_ folder: URL, prefix: String, depth: Int, into lines: inout [String]) {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        let children = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? [])
            .filter { !FileAccess.isSkipped($0.lastPathComponent) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        for child in children where lines.count < 400 {
            let values = try? child.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                lines.append("\(prefix)\(child.lastPathComponent)/")
                if depth > 1 { list(child, prefix: prefix + "  ", depth: depth - 1, into: &lines) }
            } else {
                let size = ByteCountFormatter.string(fromByteCount: Int64(values?.fileSize ?? 0), countStyle: .file)
                lines.append("\(prefix)\(child.lastPathComponent) (\(size))")
            }
        }
    }
}

struct ReadFileTool: AssistantTool {
    let access: FileAccess
    private static let maxCharacters = 60_000

    let name = "read_file"
    var displayName: String { L("Read files") }
    let description = """
    Reads a text file (code, notes, Markdown, PDF text, …) from the user's Mac, with line numbers. \
    Call this whenever the answer depends on what a file contains. For long files, read a range of lines.
    """
    var inputSchema: JSONValue {
        ["type": "object",
         "properties": [
             "path": ["type": "string", "description": "File path (absolute, ~/…, or relative to the first project folder)."],
             "start_line": ["type": "integer", "description": "First line to read (1-based). Optional."],
             "end_line": ["type": "integer", "description": "Last line to read. Optional."],
         ],
         "required": ["path"]]
    }

    func alwaysAsks(_ input: JSONValue) -> Bool { access.isOutsideProject(input["path"]?.string ?? access.roots.first?.path) }

    func describe(_ input: JSONValue) -> String { L("Read %@", input["path"]?.string ?? L("a file")) }

    func run(_ input: JSONValue) async -> ToolOutput {
        do {
            let url = try access.resolve(try input.requiredString("path"))
            guard let text = ProjectContext.text(of: url) else { return .error("\(url.lastPathComponent) is not a text file or can't be read.") }
            let lines = text.components(separatedBy: "\n")
            let first = max(1, input["start_line"]?.int ?? 1)
            let last = min(lines.count, input["end_line"]?.int ?? lines.count)
            guard first <= last else { return .error("The file has \(lines.count) lines.") }
            var output = ""
            for number in first...last {
                let line = String(format: "%6d\t", number) + lines[number - 1] + "\n"
                if output.count + line.count > Self.maxCharacters {
                    output += "… (stopped at line \(number - 1) of \(lines.count); read the rest with start_line)\n"
                    break
                }
                output += line
            }
            return ToolOutput(text: "\(url.path) (\(lines.count) lines):\n" + output)
        } catch {
            return .error(error.localizedDescription)
        }
    }
}

struct SearchFilesTool: AssistantTool {
    let access: FileAccess

    let name = "search_files"
    var displayName: String { L("Search files") }
    let description = """
    Searches a folder (by default the project folders) for files whose name or text contains the query (case-insensitive). \
    Call this to find where something is mentioned or which file to read.
    """
    var inputSchema: JSONValue {
        ["type": "object",
         "properties": [
             "query": ["type": "string", "description": "Text to look for."],
             "path": ["type": "string", "description": "Folder to search in. Defaults to all project folders."],
         ],
         "required": ["query"]]
    }

    func alwaysAsks(_ input: JSONValue) -> Bool { access.isOutsideProject(input["path"]?.string ?? access.roots.first?.path) }

    func describe(_ input: JSONValue) -> String { L("Search files for “%@”", input["query"]?.string ?? "") }

    func run(_ input: JSONValue) async -> ToolOutput {
        do {
            let query = try input.requiredString("query").lowercased()
            let folders = try input["path"]?.string.map { [try access.resolve($0)] } ?? (access.roots.isEmpty ? [try access.resolve(".")] : access.roots)
            var results: [String] = []
            var scanned = 0
            for folder in folders {
                let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey])
                while let url = enumerator?.nextObject() as? URL, results.count < 60, scanned < 5_000 {
                    if FileAccess.isSkipped(url.lastPathComponent) {
                        enumerator?.skipDescendants()
                        continue
                    }
                    let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                    guard values?.isDirectory != true else { continue }
                    scanned += 1
                    if url.lastPathComponent.lowercased().contains(query) {
                        results.append("\(url.path)  (file name)")
                    }
                    guard (values?.fileSize ?? 0) < 1_000_000, url.pathExtension.lowercased() != "pdf",
                          let text = ProjectContext.text(of: url) else { continue }
                    for (index, line) in text.components(separatedBy: "\n").enumerated() where line.lowercased().contains(query) {
                        results.append("\(url.path):\(index + 1): \(line.trimmingCharacters(in: .whitespaces).prefix(200))")
                        if results.count >= 60 { break }
                    }
                }
            }
            return ToolOutput(text: results.isEmpty ? "No matches for “\(query)”." : results.joined(separator: "\n"))
        } catch {
            return .error(error.localizedDescription)
        }
    }
}

struct WriteFileTool: AssistantTool {
    let access: FileAccess

    let name = "write_file"
    var displayName: String { L("Write files") }
    let description = """
    Creates or overwrites a text file with the given content. \
    Use it when the user asks you to save, create or change a file. Read the file first when changing it.
    """
    var inputSchema: JSONValue {
        ["type": "object",
         "properties": [
             "path": ["type": "string", "description": "File path (absolute, ~/…, or relative to the first project folder)."],
             "content": ["type": "string", "description": "The full new content of the file."],
         ],
         "required": ["path", "content"]]
    }

    func alwaysAsks(_ input: JSONValue) -> Bool { access.isOutsideProject(input["path"]?.string) }

    func detail(_ input: JSONValue) -> String? {
        input["content"]?.string.map { $0.count > 2_000 ? String($0.prefix(2_000)) + "\n…" : $0 }
    }

    func describe(_ input: JSONValue) -> String {
        let path = input["path"]?.string ?? L("a file")
        let exists = (try? access.resolve(path)).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        return exists ? L("Overwrite %@", path) : L("Create %@", path)
    }

    func run(_ input: JSONValue) async -> ToolOutput {
        do {
            let url = try access.resolve(try input.requiredString("path"))
            let content = input["content"]?.string ?? ""
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: url.path) {
                // Keep the old version recoverable.
                try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
            }
            try content.write(to: url, atomically: true, encoding: .utf8)
            return ToolOutput(text: "Saved \(url.path) (\(content.count) characters).")
        } catch {
            return .error(error.localizedDescription)
        }
    }
}

/// Changes part of a text file: replaces one exact piece of text with another.
struct EditFileTool: AssistantTool {
    let access: FileAccess

    let name = "edit_file"
    var displayName: String { L("Edit files") }
    let description = """
    Changes part of a text file: replaces `old_text` with `new_text`. `old_text` must appear in the file \
    exactly once (include a few surrounding lines to make it unique). Read the file first. \
    Prefer this over write_file for small changes to existing files.
    """
    var inputSchema: JSONValue {
        ["type": "object",
         "properties": [
             "path": ["type": "string", "description": "File path (absolute, ~/…, or relative to the first project folder)."],
             "old_text": ["type": "string", "description": "The exact text to replace, copied from the file."],
             "new_text": ["type": "string", "description": "The text to put in its place (empty to remove it)."],
         ],
         "required": ["path", "old_text", "new_text"]]
    }

    func alwaysAsks(_ input: JSONValue) -> Bool { access.isOutsideProject(input["path"]?.string) }

    func describe(_ input: JSONValue) -> String { L("Edit %@", input["path"]?.string ?? L("a file")) }

    func detail(_ input: JSONValue) -> String? {
        func lines(_ text: String?, _ mark: String) -> String {
            let text = text ?? ""
            let shown = text.count > 1_000 ? String(text.prefix(1_000)) + "\n…" : text
            return shown.components(separatedBy: "\n").map { mark + $0 }.joined(separator: "\n")
        }
        return lines(input["old_text"]?.string, "- ") + "\n" + lines(input["new_text"]?.string, "+ ")
    }

    func run(_ input: JSONValue) async -> ToolOutput {
        do {
            let url = try access.resolve(try input.requiredString("path"))
            let old = try input.requiredString("old_text")
            let new = input["new_text"]?.string ?? ""
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return .error("\(url.path) is not a UTF-8 text file or doesn't exist.") }
            let count = text.components(separatedBy: old).count - 1
            guard count == 1 else {
                return .error(count == 0 ? "old_text was not found in \(url.path). Read the file and copy the text exactly."
                                         : "old_text appears \(count) times in \(url.path). Include more surrounding text so it is unique.")
            }
            try text.replacingOccurrences(of: old, with: new).write(to: url, atomically: true, encoding: .utf8)
            return ToolOutput(text: "Edited \(url.path).")
        } catch {
            return .error(error.localizedDescription)
        }
    }
}
