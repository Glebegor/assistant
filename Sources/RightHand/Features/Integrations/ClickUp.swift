import Foundation

/// ClickUp, connected with a personal API token ("pk_…", ClickUp → Settings → Apps).
enum ClickUpSettings {
    static let keychainAccount = "clickup-token"
    static let tokenURL = URL(string: "https://app.clickup.com/settings/apps")!
    static let showInTasksKey = "clickup.showInTasks"

    static var token: String? { Keychain.read(keychainAccount) }
    static var isConnected: Bool { token != nil }
    static var showsInTasks: Bool { UserDefaults.standard.object(forKey: showInTasksKey) as? Bool ?? true }
}

struct ClickUpClient: Sendable {
    let token: String
    var baseURL = URL(string: "https://api.clickup.com/api/v2/")!

    struct Workspace: Sendable { let id: String; let name: String }

    func me() async throws -> (id: Int, name: String) {
        let user = try await request("GET", "user")["user"]
        return (user?["id"]?.int ?? 0, user?["username"]?.string ?? user?["email"]?.string ?? "ClickUp")
    }

    func workspaces() async throws -> [Workspace] {
        (try await request("GET", "team")["teams"]?.array ?? []).compactMap { team in
            team["id"]?.string.map { Workspace(id: $0, name: team["name"]?.string ?? "ClickUp") }
        }
    }

    /// Open tasks in a workspace (most recently updated first), at most `limit`.
    func tasks(in workspaceID: String, includeClosed: Bool = false, assignee: Int? = nil, limit: Int = 300) async throws -> [JSONValue] {
        var tasks: [JSONValue] = []
        var page = 0
        while tasks.count < limit {
            var path = "team/\(workspaceID)/task?page=\(page)&subtasks=true&include_closed=\(includeClosed)&order_by=updated"
            if let assignee { path += "&assignees[]=\(assignee)" }
            let response = try await request("GET", path)
            let batch = response["tasks"]?.array ?? []
            // ClickUp's include_closed only hides "closed" statuses; "done" ones (e.g. "complete") are finished too.
            tasks += includeClosed ? batch : batch.filter { !Self.isFinished($0) }
            if batch.count < 100 || response["last_page"]?.bool == true { break }
            page += 1
        }
        return Array(tasks.prefix(limit))
    }

    func task(_ id: String) async throws -> JSONValue {
        try await request("GET", "task/\(id)?include_subtasks=true&include_markdown_description=true")
    }

    func updateTask(_ id: String, fields: JSONValue) async throws -> JSONValue {
        try await request("PUT", "task/\(id)", body: fields)
    }

    func comment(on id: String, text: String) async throws {
        _ = try await request("POST", "task/\(id)/comment", body: ["comment_text": .string(text), "notify_all": false])
    }

    /// The status that means "done" in a task's list.
    func doneStatus(ofList listID: String) async throws -> String? {
        let statuses = try await request("GET", "list/\(listID)")["statuses"]?.array ?? []
        let done = statuses.first { $0["type"]?.string == "done" } ?? statuses.first { $0["type"]?.string == "closed" }
        return done?["status"]?.string
    }

    func request(_ method: String, _ path: String, body: JSONValue? = nil) async throws -> JSONValue {
        var request = URLRequest(url: URL(string: path, relativeTo: baseURL)!)
        request.httpMethod = method
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try body.encoded()
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = JSONValue.parse(data) ?? .null
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if http.statusCode == 401 { throw ChatError(message: L("ClickUp rejected the token. Check it in Settings → Services.")) }
            throw ChatError(message: "ClickUp: " + (json["err"]?.string ?? L("Error %lld.", http.statusCode)))
        }
        return json
    }

    // MARK: Reading tasks

    /// Status type "done" (e.g. "complete") or "closed" (e.g. "cancelled").
    static func isFinished(_ task: JSONValue) -> Bool {
        ["done", "closed"].contains(task["status"]?["type"]?.string ?? "")
    }

    /// A ClickUp task for the Tasks tab.
    static func taskItem(_ task: JSONValue) -> TaskItem? {
        guard let id = task["id"]?.string else { return nil }
        let due = task["due_date"]?.string.flatMap(Double.init).map { Date(timeIntervalSince1970: $0 / 1000) }
        let priority = task["priority"]?["priority"]?.string
        let level: TaskItem.Priority = switch priority {
        case "urgent", "high": .high
        case "normal": .medium
        case "low": .low
        default: .none
        }
        return TaskItem(id: id, title: task["name"]?.string ?? L("Untitled"), url: task["url"]?.string.flatMap(URL.init(string:)),
                        source: .clickUp, databaseID: task["list"]?["id"]?.string ?? "", databaseName: task["list"]?["name"]?.string ?? "ClickUp",
                        due: due, dueHasTime: task["due_date_time"]?.bool ?? false,
                        priorityName: priority?.capitalized, priorityLevel: level,
                        assigneeIDs: (task["assignees"]?.array ?? []).compactMap { $0["id"]?.int.map(String.init) },
                        canComplete: true)
    }

    /// One line per task for the AI.
    static func summary(_ task: JSONValue) -> String {
        var parts = ["\(task["name"]?.string ?? "?") (id: \(task["id"]?.string ?? ""))"]
        if let status = task["status"]?["status"]?.string { parts.append("status: \(status)") }
        if let priority = task["priority"]?["priority"]?.string { parts.append("priority: \(priority)") }
        if let due = task["due_date"]?.string.flatMap(Double.init) {
            parts.append("due: " + Date(timeIntervalSince1970: due / 1000).formatted(.iso8601.year().month().day()))
        }
        let people = (task["assignees"]?.array ?? []).compactMap { $0["username"]?.string }
        if !people.isEmpty { parts.append("assignees: " + people.joined(separator: ", ")) }
        if let list = task["list"]?["name"]?.string { parts.append("list: \(list)") }
        if let url = task["url"]?.string { parts.append(url) }
        return "- " + parts.joined(separator: "; ")
    }
}

// MARK: AI tools

struct ClickUpFindTasksTool: AssistantTool {
    let name = "clickup_find_tasks"
    var displayName: String { L("Search ClickUp tasks") }
    let description = """
    Lists the user's ClickUp tasks (open ones by default, newest updates first) with status, priority, due date, \
    assignees, list and ID. Optionally filters by words in the task name or only tasks assigned to the user.
    """
    var inputSchema: JSONValue {
        ["type": "object",
         "properties": [
             "query": ["type": "string", "description": "Words in the task name. Optional."],
             "only_mine": ["type": "boolean", "description": "Only tasks assigned to the user. Default false."],
             "include_closed": ["type": "boolean", "description": "Also finished tasks. Default false."],
         ]]
    }

    func describe(_ input: JSONValue) -> String {
        input["query"]?.string.map { L("Search ClickUp for “%@”", $0) } ?? L("List ClickUp tasks")
    }

    func run(_ input: JSONValue) async -> ToolOutput {
        guard let token = ClickUpSettings.token else { return .error("ClickUp isn't connected. Ask the user to connect it in Settings → Services.") }
        let client = ClickUpClient(token: token)
        do {
            let me = input["only_mine"]?.bool == true ? try await client.me().id : nil
            let query = input["query"]?.string?.lowercased() ?? ""
            var lines: [String] = []
            for workspace in try await client.workspaces() {
                let tasks = try await client.tasks(in: workspace.id, includeClosed: input["include_closed"]?.bool == true, assignee: me)
                let matching = tasks.filter { query.isEmpty || ($0["name"]?.string?.lowercased().contains(query) ?? false) }
                lines += matching.prefix(80).map(ClickUpClient.summary)
            }
            return ToolOutput(text: lines.isEmpty ? "No tasks found." : lines.joined(separator: "\n"))
        } catch {
            return .error(error.localizedDescription)
        }
    }
}

struct ClickUpReadTaskTool: AssistantTool {
    let name = "clickup_read_task"
    var displayName: String { L("Read ClickUp tasks") }
    let description = "Reads one ClickUp task: description, status, priority, dates, assignees, subtasks and checklists."
    var inputSchema: JSONValue {
        ["type": "object", "properties": ["task_id": ["type": "string"]], "required": ["task_id"]]
    }

    func describe(_ input: JSONValue) -> String { L("Read a ClickUp task") }

    func run(_ input: JSONValue) async -> ToolOutput {
        guard let token = ClickUpSettings.token else { return .error("ClickUp isn't connected.") }
        do {
            let task = try await ClickUpClient(token: token).task(try input.requiredString("task_id"))
            var text = ClickUpClient.summary(task) + "\n\n"
            text += task["markdown_description"]?.string ?? task["text_content"]?.string ?? ""
            for checklist in task["checklists"]?.array ?? [] {
                text += "\n\nChecklist \(checklist["name"]?.string ?? ""):\n"
                text += (checklist["items"]?.array ?? []).map { ($0["resolved"]?.bool == true ? "[x] " : "[ ] ") + ($0["name"]?.string ?? "") }
                    .joined(separator: "\n")
            }
            let subtasks = task["subtasks"]?.array ?? []
            if !subtasks.isEmpty { text += "\n\nSubtasks:\n" + subtasks.map(ClickUpClient.summary).joined(separator: "\n") }
            return ToolOutput(text: String(text.prefix(40_000)))
        } catch {
            return .error(error.localizedDescription)
        }
    }
}

struct ClickUpUpdateTaskTool: AssistantTool {
    let name = "clickup_update_task"
    var displayName: String { L("Change ClickUp tasks") }
    let description = """
    Changes a ClickUp task: name, status (a status name from its list), done, priority (urgent/high/normal/low), \
    due date, or adds a comment. Only the fields you give are changed.
    """
    var inputSchema: JSONValue {
        ["type": "object",
         "properties": [
             "task_id": ["type": "string"],
             "name": ["type": "string"],
             "status": ["type": "string", "description": "Status name, e.g. \"in progress\"."],
             "done": ["type": "boolean", "description": "true moves the task to its list's done status."],
             "priority": ["type": "string", "enum": ["urgent", "high", "normal", "low", "none"]],
             "due": ["type": "string", "description": "YYYY-MM-DD or YYYY-MM-DDTHH:MM (local time). Empty string clears it."],
             "comment": ["type": "string", "description": "A comment to add to the task."],
         ],
         "required": ["task_id"]]
    }

    func describe(_ input: JSONValue) -> String {
        var changes: [String] = []
        if let name = input["name"]?.string { changes.append(L("title “%@”", name)) }
        if let status = input["status"]?.string { changes.append(L("status “%@”", status)) }
        if input["done"]?.bool == true { changes.append(L("mark done")) }
        if let priority = input["priority"]?.string { changes.append(L("priority “%@”", priority)) }
        if let due = input["due"]?.string { changes.append(due.isEmpty ? L("remove due date") : L("due %@", due)) }
        if input["comment"]?.string != nil { changes.append(L("add comment")) }
        return L("Change a ClickUp task: %@", changes.joined(separator: ", "))
    }

    func detail(_ input: JSONValue) -> String? { input["comment"]?.string }

    func run(_ input: JSONValue) async -> ToolOutput {
        guard let token = ClickUpSettings.token else { return .error("ClickUp isn't connected.") }
        let client = ClickUpClient(token: token)
        do {
            let id = try input.requiredString("task_id")
            var fields: [String: JSONValue] = [:]
            if let name = input["name"]?.string { fields["name"] = .string(name) }
            if let status = input["status"]?.string { fields["status"] = .string(status) }
            if input["done"]?.bool == true {
                let task = try await client.task(id)
                guard let listID = task["list"]?["id"]?.string, let done = try await client.doneStatus(ofList: listID) else {
                    return .error("Couldn't find a done status in this task's list.")
                }
                fields["status"] = .string(done)
            }
            if let priority = input["priority"]?.string {
                fields["priority"] = ["urgent": 1, "high": 2, "normal": 3, "low": 4][priority].map(JSONValue.int) ?? .null
            }
            if let due = input["due"]?.string {
                if due.isEmpty {
                    fields["due_date"] = .null
                } else if let date = Self.parse(due) {
                    fields["due_date"] = .int(Int(date.date.timeIntervalSince1970 * 1000))
                    fields["due_date_time"] = .bool(date.hasTime)
                } else {
                    return .error("Use YYYY-MM-DD or YYYY-MM-DDTHH:MM for due.")
                }
            }
            if !fields.isEmpty { _ = try await client.updateTask(id, fields: .object(fields)) }
            if let comment = input["comment"]?.string, !comment.isEmpty { try await client.comment(on: id, text: comment) }
            return ToolOutput(text: "Updated ClickUp task \(id).")
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private static func parse(_ text: String) -> (date: Date, hasTime: Bool)? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for (format, hasTime) in [("yyyy-MM-dd'T'HH:mm", true), ("yyyy-MM-dd", false)] {
            formatter.dateFormat = format
            if let date = formatter.date(from: String(text.prefix(hasTime ? 16 : 10))) {
                // A whole day is due at its end, as ClickUp shows it.
                return (hasTime ? date : date.addingTimeInterval(23 * 3600 + 59 * 60), hasTime)
            }
        }
        return nil
    }
}
