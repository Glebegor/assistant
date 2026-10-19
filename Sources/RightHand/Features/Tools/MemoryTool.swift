import Foundation

/// The project's memory: a folder of notes the AI writes for itself, shared by every chat in
/// the project. For Claude this is Anthropic's built-in memory tool (`/memories` paths);
/// ChatGPT gets the same commands as a regular function.
struct MemoryTool: AnthropicDefinedTool {
    let root: URL

    let name = "memory"
    let anthropicType = "memory_20250818"
    let displayName = "Project memory"
    let description = """
    Your persistent memory for this project: a directory of notes at /memories that survives between chats. \
    Check it at the start of a task, and record decisions, progress and the user's preferences as you work. \
    Commands: view (path, optional view_range [start, end]), create (path, file_text), \
    str_replace (path, old_str, new_str), insert (path, insert_line, insert_text), delete (path), rename (old_path, new_path).
    """
    var inputSchema: JSONValue {
        ["type": "object",
         "properties": [
             "command": ["type": "string", "enum": ["view", "create", "str_replace", "insert", "delete", "rename"]],
             "path": ["type": "string", "description": "A path under /memories"],
             "view_range": ["type": "array", "items": ["type": "integer"]],
             "file_text": ["type": "string"],
             "old_str": ["type": "string"],
             "new_str": ["type": "string"],
             "insert_line": ["type": "integer"],
             "insert_text": ["type": "string"],
             "old_path": ["type": "string"],
             "new_path": ["type": "string"],
         ],
         "required": ["command"]]
    }

    var claudeDeclaration: JSONValue { ["type": .string(anthropicType), "name": .string(name)] }

    func describe(_ input: JSONValue) -> String {
        let path = input["path"]?.string ?? input["old_path"]?.string ?? "/memories"
        switch input["command"]?.string {
        case "view": return "Read memory \(path)"
        case "create": return "Write memory note \(path)"
        case "str_replace", "insert": return "Edit memory note \(path)"
        case "delete": return "Delete memory \(path)"
        case "rename": return "Rename memory \(path)"
        default: return "Use project memory"
        }
    }

    func run(_ input: JSONValue) async -> ToolOutput {
        do {
            return try perform(input)
        } catch {
            return .error(error.localizedDescription)
        }
    }

    // MARK: Commands (return strings follow Anthropic's reference implementation)

    private func perform(_ input: JSONValue) throws -> ToolOutput {
        let files = FileManager.default
        switch input["command"]?.string {
        case "view":
            let path = input["path"]?.string ?? "/memories"
            let url = try resolve(path)
            var isDirectory: ObjCBool = false
            guard files.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
                return .error("The path \(path) does not exist. Please provide a valid path.")
            }
            if isDirectory.boolValue {
                return ToolOutput(text: "Here're the files and directories up to 2 levels deep in \(path), excluding hidden items and node_modules:\n"
                    + listing(of: url, as: path).joined(separator: "\n"))
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            var lines = text.components(separatedBy: "\n")
            if text.hasSuffix("\n") { lines.removeLast() }
            var first = 1
            if let range = input["view_range"]?.array?.compactMap(\.int), range.count == 2 {
                first = max(1, range[0])
                let last = range[1] == -1 ? lines.count : min(lines.count, range[1])
                lines = first <= last ? Array(lines[(first - 1)..<last]) : []
            }
            let numbered = lines.enumerated().map { String(format: "%6d\t", $0.offset + first) + $0.element }
            return ToolOutput(text: "Here's the content of \(path) with line numbers:\n" + numbered.joined(separator: "\n"))

        case "create":
            let path = try input.requiredString("path")
            let url = try resolve(path)
            try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (input["file_text"]?.string ?? "").write(to: url, atomically: true, encoding: .utf8)
            return ToolOutput(text: "File created successfully at: \(path)")

        case "str_replace":
            let path = try input.requiredString("path")
            let url = try resolve(path)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                return .error("Error: The path \(path) does not exist. Please provide a valid path.")
            }
            let old = try input.requiredString("old_str")
            let count = text.components(separatedBy: old).count - 1
            guard count == 1 else {
                return .error(count == 0
                    ? "No replacement was performed, old_str `\(old)` did not appear verbatim in \(path)."
                    : "No replacement was performed. Multiple occurrences of old_str `\(old)`. Please ensure it is unique")
            }
            try text.replacingOccurrences(of: old, with: input["new_str"]?.string ?? "").write(to: url, atomically: true, encoding: .utf8)
            return ToolOutput(text: "The memory file has been edited.")

        case "insert":
            let path = try input.requiredString("path")
            let url = try resolve(path)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                return .error("Error: The path \(path) does not exist")
            }
            var lines = text.components(separatedBy: "\n")
            let line = input["insert_line"]?.int ?? -1
            guard (0...lines.count).contains(line) else {
                return .error("Error: Invalid `insert_line` parameter: \(line). It should be within the range of lines of the file: [0, \(lines.count)]")
            }
            var inserted = input["insert_text"]?.string ?? ""
            if inserted.hasSuffix("\n") { inserted.removeLast() }
            lines.insert(inserted, at: line)
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return ToolOutput(text: "The file \(path) has been edited.")

        case "delete":
            let path = try input.requiredString("path")
            let url = try resolve(path)
            guard url.path != FileAccess.canonicalPath(root) else { return .error("Error: The /memories directory itself can't be deleted") }
            guard files.fileExists(atPath: url.path) else { return .error("Error: The path \(path) does not exist") }
            try files.removeItem(at: url)
            return ToolOutput(text: "Successfully deleted \(path)")

        case "rename":
            let oldPath = try input.requiredString("old_path"), newPath = try input.requiredString("new_path")
            let from = try resolve(oldPath), to = try resolve(newPath)
            guard from.path != FileAccess.canonicalPath(root) else { return .error("Error: The /memories directory itself can't be renamed") }
            guard files.fileExists(atPath: from.path) else { return .error("Error: The path \(oldPath) does not exist") }
            guard !files.fileExists(atPath: to.path) else { return .error("Error: The destination \(newPath) already exists") }
            try files.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try files.moveItem(at: from, to: to)
            return ToolOutput(text: "Successfully renamed \(oldPath) to \(newPath)")

        default:
            return .error("Error: unknown command \(input["command"]?.string ?? "")")
        }
    }

    /// Maps "/memories/…" onto the project's memory folder; refuses anything outside it.
    private func resolve(_ path: String) throws -> URL {
        guard path == "/memories" || path.hasPrefix("/memories/") else {
            throw ToolError("Error: Paths must start with /memories")
        }
        let relative = path.dropFirst("/memories".count).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let decoded = relative.removingPercentEncoding ?? relative
        guard !decoded.split(separator: "/").contains("..") else {
            throw ToolError("Error: Invalid path \(path)")
        }
        let url = URL(filePath: FileAccess.canonicalPath(relative.isEmpty ? root : root.appending(path: decoded)))
        guard FileAccess.isInside(url.path, FileAccess.canonicalPath(root)) else {
            throw ToolError("Error: Invalid path \(path)")
        }
        return url
    }

    private func listing(of directory: URL, as path: String, depth: Int = 0) -> [String] {
        var lines = depth == 0 ? ["\(size(of: directory))\t\(path)"] : []
        guard depth < 2 else { return lines }
        let children = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey],
                                                                     options: .skipsHiddenFiles)) ?? []
        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where child.lastPathComponent != "node_modules" {
            let childPath = path + "/" + child.lastPathComponent
            lines.append("\(size(of: child))\t\(childPath)")
            if (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                lines += listing(of: child, as: childPath, depth: depth + 1)
            }
        }
        return lines
    }

    private func size(of url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 4096
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            .replacingOccurrences(of: " ", with: "")
    }
}
