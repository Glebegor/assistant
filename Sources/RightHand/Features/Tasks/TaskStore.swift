import Foundation
import Observation
import os

/// A task from Notion or ClickUp.
struct TaskItem: Identifiable, Hashable, Sendable {
    enum Source: Sendable { case notion, clickUp }
    enum Priority: Int, Comparable, Sendable {
        case high, medium, low, none
        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    let id: String
    var title: String
    var url: URL?
    var source: Source
    var databaseID: String
    var databaseName: String
    var due: Date?
    /// False for a whole day ("Oct 19"), true for a moment ("Oct 19, 10:00").
    var dueHasTime: Bool
    var priorityName: String?
    var priorityLevel: Priority
    var assigneeIDs: [String]
    var canComplete: Bool

    func isOverdue(now: Date = Date()) -> Bool {
        guard let due else { return false }
        return dueHasTime ? due < now : due < Calendar.current.startOfDay(for: now)
    }

    func isDueToday(now: Date = Date()) -> Bool {
        due.map { Calendar.current.isDate($0, inSameDayAs: now) } ?? false
    }

    /// Overdue first, then high priority, then by due date (no date last), then by priority.
    static func ordered(_ tasks: [TaskItem], now: Date = Date()) -> [TaskItem] {
        tasks.sorted { a, b in
            let keyA = (a.isOverdue(now: now) ? 0 : 1, a.priorityLevel == .high ? 0 : 1)
            let keyB = (b.isOverdue(now: now) ? 0 : 1, b.priorityLevel == .high ? 0 : 1)
            if keyA != keyB { return keyA < keyB }
            if a.due != b.due { return (a.due ?? .distantFuture) < (b.due ?? .distantFuture) }
            if a.priorityLevel != b.priorityLevel { return a.priorityLevel < b.priorityLevel }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }
}

/// One Notion workspace connected with an integration token (kept in the Keychain).
struct NotionConnection: Codable, Identifiable, Hashable {
    var id = UUID()
    var workspaceName: String
    /// Databases the integration can see; tasks are read from the enabled ones.
    var databases: [NotionDatabaseInfo] = []
    var enabledDatabaseIDs: Set<String> = []
    var people: [NotionPerson] = []
    /// You in this workspace: tasks assigned to someone else are hidden.
    var meID: String?

    var keychainAccount: String { "notion-token-\(id.uuidString)" }
}

enum TasksSettings {
    static let connectionsKey = "tasks.notion.connections"
    static let integrationsURL = URL(string: "https://www.notion.so/profile/integrations")!

    static var connections: [NotionConnection] {
        get {
            UserDefaults.standard.data(forKey: connectionsKey)
                .flatMap { try? JSONDecoder().decode([NotionConnection].self, from: $0) } ?? []
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: connectionsKey)
        }
    }
}

/// The Tasks tab: open tasks assigned to you or to nobody, from the Notion databases you chose and ClickUp.
@Observable
@MainActor
final class TaskStore {
    private(set) var tasks: [TaskItem] = []
    private(set) var isLoading = false
    private(set) var lastRefresh: Date?
    var errorMessage: String?
    /// Tasks being marked done right now (shown ticked while Notion saves it).
    private(set) var completing: Set<String> = []

    @ObservationIgnored private var schemas: [String: NotionSchema] = [:]
    private static let log = Logger(subsystem: "com.hlibarseniuk.RightHand", category: "tasks")
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    var isConfigured: Bool {
        TasksSettings.connections.contains { !$0.enabledDatabaseIDs.isEmpty } || (ClickUpSettings.isConnected && ClickUpSettings.showsInTasks)
    }

    /// Refreshes when the tab is shown and the list is older than a minute.
    func refreshIfStale() {
        guard lastRefresh.map({ Date().timeIntervalSince($0) > 60 }) ?? true else { return }
        refresh()
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        refreshTask = Task {
            defer { isLoading = false }
            var loaded: [TaskItem] = []
            var failures: [String] = []
            for connection in TasksSettings.connections {
                guard let token = Keychain.read(connection.keychainAccount) else { continue }
                let client = NotionClient(token: token)
                for database in connection.databases where connection.enabledDatabaseIDs.contains(database.id) {
                    do {
                        let schema = try await client.schema(of: database.id)
                        schemas[database.id] = schema
                        let pages = try await client.openPages(in: database.id, schema: schema)
                        loaded += pages.compactMap { schema.task(from: $0, database: database) }
                            .filter { $0.assigneeIDs.isEmpty || connection.meID == nil || $0.assigneeIDs.contains(connection.meID!) }
                    } catch {
                        failures.append("\(database.fullName): \(error.localizedDescription)")
                    }
                }
            }
            if ClickUpSettings.showsInTasks, let token = ClickUpSettings.token {
                do {
                    loaded += try await Self.clickUpTasks(ClickUpClient(token: token))
                } catch {
                    failures.append("ClickUp: \(error.localizedDescription)")
                }
            }
            tasks = TaskItem.ordered(loaded)
            errorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
            lastRefresh = Date()
        }
    }

    /// Open ClickUp tasks assigned to you or to nobody.
    private static func clickUpTasks(_ client: ClickUpClient) async throws -> [TaskItem] {
        let me = String(try await client.me().id)
        var items: [TaskItem] = []
        for workspace in try await client.workspaces() {
            items += try await client.tasks(in: workspace.id).compactMap(ClickUpClient.taskItem)
                .filter { $0.assigneeIDs.isEmpty || $0.assigneeIDs.contains(me) }
        }
        return items
    }

    /// Marks a task done in Notion or ClickUp; it disappears from the list once saved.
    func complete(_ task: TaskItem) {
        Self.log.info("Mark done: \(task.title, privacy: .private) (\(String(describing: task.source)))")
        if task.source == .clickUp { return completeInClickUp(task) }
        guard !completing.contains(task.id) else { return }
        guard let connection = TasksSettings.connections.first(where: { $0.databases.contains { $0.id == task.databaseID } }),
              let token = Keychain.read(connection.keychainAccount)
        else { return fail(L("Notion isn't connected for this database. Check Settings → Services.")) }
        completing.insert(task.id)
        errorMessage = nil
        Task {
            do {
                let client = NotionClient(token: token)
                // Read the database again if needed, so a done status is always found.
                let schema: NotionSchema
                if let cached = schemas[task.databaseID] { schema = cached } else { schema = try await client.schema(of: task.databaseID) }
                guard let update = schema.doneUpdate else {
                    throw ChatError(message: L("This database has no status or checkbox to mark it done"))
                }
                try await client.update(page: task.id, properties: update)
                Self.log.info("Marked done in Notion")
                ActivityLog.shared.taskDone(source: "notion")
                try? await Task.sleep(for: .milliseconds(500))
                tasks.removeAll { $0.id == task.id }
            } catch {
                fail(error.localizedDescription)
            }
            completing.remove(task.id)
        }
    }

    private func fail(_ message: String) {
        Self.log.error("Mark done failed: \(message, privacy: .public)")
        errorMessage = message
    }

    private func completeInClickUp(_ task: TaskItem) {
        guard !completing.contains(task.id) else { return }
        guard let token = ClickUpSettings.token else { return fail(L("ClickUp isn't connected. Check Settings → Services.")) }
        completing.insert(task.id)
        errorMessage = nil
        Task {
            do {
                let client = ClickUpClient(token: token)
                guard let done = try await client.doneStatus(ofList: task.databaseID) else {
                    throw ChatError(message: L("This ClickUp list has no done status."))
                }
                _ = try await client.updateTask(task.id, fields: ["status": .string(done)])
                Self.log.info("Marked done in ClickUp")
                ActivityLog.shared.taskDone(source: "clickup")
                try? await Task.sleep(for: .milliseconds(500))
                tasks.removeAll { $0.id == task.id }
            } catch {
                fail(error.localizedDescription)
            }
            completing.remove(task.id)
        }
    }
}
