import AppKit
import Observation

/// All projects and their chats; everything is saved to disk right away.
@Observable
@MainActor
final class ProjectStore {
    private(set) var projects: [Project] = []
    private(set) var chats: [UUID: [ProjectChat]] = [:]
    /// Bumped when attached files or memory change, so lists refresh.
    private(set) var filesRevision = 0

    /// One engine per opened chat, so an answer keeps streaming when you switch chats.
    @ObservationIgnored private var engines: [UUID: ConversationEngine] = [:]

    init() {
        ChatSettings.registerDefaults()
        projects = ProjectStorage.loadProjects()
        for project in projects { chats[project.id] = ProjectStorage.loadChats(of: project.id) }
        if projects.isEmpty { createProject(name: "General") }
    }

    // MARK: Projects

    @discardableResult
    func createProject(name: String) -> Project {
        let project = Project(name: name)
        projects.append(project)
        chats[project.id] = []
        ProjectStorage.save(project)
        return project
    }

    func project(_ id: UUID) -> Project? { projects.first { $0.id == id } }

    func update(_ project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }), projects[index] != project else { return }
        projects[index] = project
        ProjectStorage.save(project)
    }

    func delete(_ project: Project) {
        for chat in chats[project.id] ?? [] { engines[chat.id]?.stop() }
        projects.removeAll { $0.id == project.id }
        chats[project.id] = nil
        ProjectStorage.delete(project)
    }

    // MARK: Chats

    func chats(in projectID: UUID) -> [ProjectChat] { chats[projectID] ?? [] }

    @discardableResult
    func newChat(in project: Project, provider: ChatProvider = ChatSettings.provider) -> ProjectChat {
        let chat = ProjectChat(projectID: project.id, provider: provider, model: ChatSettings.model(for: provider),
                               system: ProjectContext.systemPrompt(for: project, provider: provider),
                               contextFingerprint: ProjectContext.fingerprint(of: project))
        chats[project.id, default: []].insert(chat, at: 0)
        ProjectStorage.save(chat)
        return chat
    }

    func engine(for chatID: UUID) -> ConversationEngine? {
        if let engine = engines[chatID] { return engine }
        guard let chat = chats.values.joined().first(where: { $0.id == chatID }) else { return nil }
        let engine = ConversationEngine(
            chat: chat,
            project: { [weak self] in self?.project(chat.projectID) },
            onSave: { [weak self] chat in self?.saveChat(chat) }
        )
        engines[chatID] = engine
        return engine
    }

    func rename(_ chat: ProjectChat, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, var current = chats[chat.projectID]?.first(where: { $0.id == chat.id }) else { return }
        current.title = title
        saveChat(current)
    }

    func delete(_ chat: ProjectChat) {
        engines[chat.id]?.stop()
        engines[chat.id] = nil
        chats[chat.projectID]?.removeAll { $0.id == chat.id }
        ProjectStorage.delete(chat)
    }

    private func saveChat(_ chat: ProjectChat) {
        if let index = chats[chat.projectID]?.firstIndex(where: { $0.id == chat.id }) {
            chats[chat.projectID]?[index] = chat
        }
        ProjectStorage.save(chat)
    }

    // MARK: Files, folders, memory

    func attachedFiles(of project: Project) -> [URL] {
        _ = filesRevision
        return ProjectContext.attachedFiles(of: project)
    }

    /// Copies files into the project (the originals stay where they are).
    func attach(_ urls: [URL], to project: Project) {
        let folder = ProjectStorage.filesDirectory(of: project.id)
        for url in urls {
            try? FileManager.default.copyItem(at: url, to: ShelfFiles.uniqueURL(for: url.lastPathComponent, in: folder))
        }
        filesRevision += 1
    }

    func removeAttachedFile(_ url: URL) {
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        filesRevision += 1
    }

    func memoryFiles(of project: Project) -> [URL] {
        _ = filesRevision
        let root = ProjectStorage.memoryDirectory(of: project.id)
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
        return (enumerator?.allObjects as? [URL] ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true }
            .sorted { $0.path < $1.path }
    }

    func deleteMemoryFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
        filesRevision += 1
    }

    func refreshFiles() { filesRevision += 1 }
}
