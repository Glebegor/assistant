import AppKit

/// Opens a web page, an app, or a file/folder from the project folders.
struct OpenTool: AssistantTool {
    let access: FileAccess

    let name = "open"
    var displayName: String { L("Open apps, links and files") }
    let description = """
    Opens something on the user's Mac: a web address (https://…), an app by name (e.g. "Safari", "Notes"), \
    or a file or folder on the Mac. Use it when the user asks to open or show something.
    """
    var inputSchema: JSONValue {
        ["type": "object",
         "properties": ["target": ["type": "string", "description": "A URL, an app name, or a file/folder path."]],
         "required": ["target"]]
    }

    func alwaysAsks(_ input: JSONValue) -> Bool {
        guard let target = input["target"]?.string, target.contains("/"), !target.contains("://") else { return false }
        return access.isOutsideProject(target)
    }

    func describe(_ input: JSONValue) -> String { L("Open %@", input["target"]?.string ?? L("something")) }

    func run(_ input: JSONValue) async -> ToolOutput {
        do {
            let target = try input.requiredString("target").trimmingCharacters(in: .whitespaces)
            if let url = URL(string: target), let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) {
                return await open(url, label: target)
            }
            if target.hasPrefix("/") || target.hasPrefix("~") || target.contains("/") {
                let file = try access.resolve(target)
                guard FileManager.default.fileExists(atPath: file.path) else { return .error("\(target) doesn't exist.") }
                return await open(file, label: file.path)
            }
            guard let app = Self.application(named: target) else { return .error("No app named “\(target)” was found.") }
            return await open(app, label: app.deletingPathExtension().lastPathComponent)
        } catch {
            return .error(error.localizedDescription)
        }
    }

    @MainActor
    private func open(_ url: URL, label: String) -> ToolOutput {
        NSWorkspace.shared.open(url) ? ToolOutput(text: "Opened \(label).") : .error("Couldn't open \(label).")
    }

    private static func application(named name: String) -> URL? {
        let wanted = name.lowercased().replacingOccurrences(of: ".app", with: "")
        let folders = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                       NSHomeDirectory() + "/Applications"]
        for folder in folders {
            let apps = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
            if let app = apps.first(where: { $0.lowercased() == wanted + ".app" }) {
                return URL(filePath: folder).appending(path: app)
            }
        }
        return nil
    }
}

/// "Work with the whole Mac": file tools reach outside the project folders and Terminal
/// commands are available. Every such action still asks you first.
enum ComputerAccess {
    static let key = "tools.wholeMac"

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
}

/// The tools available in a project.
enum Toolbox {
    static func tools(for project: Project) -> [AssistantTool] {
        let wholeMac = ComputerAccess.isEnabled
        let access = FileAccess(folders: project.folders, anywhere: wholeMac)
        var tools: [AssistantTool] = [MemoryTool(root: ProjectStorage.memoryDirectory(of: project.id))]
        if access.base != nil {
            tools += [ListFilesTool(access: access), ReadFileTool(access: access),
                      SearchFilesTool(access: access), WriteFileTool(access: access),
                      CreateFolderTool(access: access), MoveFileTool(access: access), DeleteFileTool(access: access)]
        }
        if wholeMac { tools.append(RunCommandTool(access: access)) }
        tools.append(OpenTool(access: access))
        return tools
    }

    /// Every kind of tool, for Settings.
    static var catalog: [(name: String, displayName: String)] {
        [("memory", L("Project memory")),
         ("list_files", L("List files")),
         ("read_file", L("Read files")),
         ("search_files", L("Search files")),
         ("write_file", L("Write files")),
         ("create_folder", L("Create folders")),
         ("move_file", L("Move and copy files")),
         ("delete_file", L("Delete files")),
         ("run_command", L("Run Terminal commands")),
         ("open", L("Open apps, links and files"))]
    }

    /// Deleting and running commands ask every time.
    static func canAlwaysAllow(_ tool: String) -> Bool {
        !["delete_file", "run_command"].contains(tool)
    }

    static func displayName(of tool: String) -> String {
        catalog.first { $0.name == tool }?.displayName ?? tool
    }
}
