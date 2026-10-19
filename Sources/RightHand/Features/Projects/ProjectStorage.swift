import Foundation

/// Where projects live on disk:
/// ~/Library/Application Support/RightHand/Projects/<id>/
///   project.json, files/ (attached files), memory/ (the AI's notes), chats/<chat id>.json
enum ProjectStorage {
    static let root = AppPaths.makeDirectory(AppPaths.support.appending(path: "Projects", directoryHint: .isDirectory))

    static func directory(of projectID: UUID) -> URL {
        root.appending(path: projectID.uuidString, directoryHint: .isDirectory)
    }

    static func filesDirectory(of projectID: UUID) -> URL {
        AppPaths.makeDirectory(directory(of: projectID).appending(path: "files", directoryHint: .isDirectory))
    }

    static func memoryDirectory(of projectID: UUID) -> URL {
        AppPaths.makeDirectory(directory(of: projectID).appending(path: "memory", directoryHint: .isDirectory))
    }

    private static func chatsDirectory(of projectID: UUID) -> URL {
        AppPaths.makeDirectory(directory(of: projectID).appending(path: "chats", directoryHint: .isDirectory))
    }

    // MARK: Loading

    static func loadProjects() -> [Project] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { folder in
            guard let data = try? Data(contentsOf: folder.appending(path: "project.json")) else { return nil }
            return try? decoder.decode(Project.self, from: data)
        }
        .sorted { $0.createdAt < $1.createdAt }
    }

    static func loadChats(of projectID: UUID) -> [ProjectChat] {
        let files = (try? FileManager.default.contentsOfDirectory(at: chatsDirectory(of: projectID), includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { (try? Data(contentsOf: $0)).flatMap { try? decoder.decode(ProjectChat.self, from: $0) } }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: Saving

    static func save(_ project: Project) {
        AppPaths.makeDirectory(directory(of: project.id))
        write(project, to: directory(of: project.id).appending(path: "project.json"))
    }

    static func save(_ chat: ProjectChat) {
        write(chat, to: chatsDirectory(of: chat.projectID).appending(path: "\(chat.id.uuidString).json"))
    }

    static func delete(_ chat: ProjectChat) {
        try? FileManager.default.trashItem(at: chatsDirectory(of: chat.projectID).appending(path: "\(chat.id.uuidString).json"),
                                           resultingItemURL: nil)
    }

    /// Moves the whole project (chats, files, memory) to the Trash.
    static func delete(_ project: Project) {
        try? FileManager.default.trashItem(at: directory(of: project.id), resultingItemURL: nil)
    }

    // MARK: Private

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static func write(_ value: some Encodable, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
