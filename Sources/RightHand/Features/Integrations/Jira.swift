import Foundation

/// Jira Cloud, connected with your email and an API token (id.atlassian.com → Security → API tokens).
enum JiraSettings {
    static let siteKey = "jira.site"
    static let emailKey = "jira.email"
    static let nameKey = "jira.name"
    static let showInTasksKey = "jira.showInTasks"
    static let tokenAccount = "jira-token"
    static let tokenURL = URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!

    static var site: URL? {
        guard var text = UserDefaults.standard.string(forKey: siteKey)?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if !text.hasPrefix("http") { text = "https://" + text }
        return URL(string: text.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    }
    static var email: String? { UserDefaults.standard.string(forKey: emailKey) }
    static var isConnected: Bool { site != nil && email != nil && Keychain.read(tokenAccount) != nil }
    static var showsInTasks: Bool { UserDefaults.standard.object(forKey: showInTasksKey) as? Bool ?? true }

    static var client: JiraClient? {
        guard let site, let email, let token = Keychain.read(tokenAccount) else { return nil }
        return JiraClient(site: site, email: email, token: token)
    }
}

struct JiraClient: Sendable {
    let site: URL
    let email: String
    let token: String

    static let fields: [JSONValue] = ["summary", "status", "priority", "duedate", "assignee", "project", "issuetype"]

    func myself() async throws -> String {
        let me = try await request("GET", "rest/api/3/myself")
        return me["displayName"]?.string ?? me["emailAddress"]?.string ?? "Jira"
    }

    func search(_ jql: String, limit: Int = 50, fields: [JSONValue] = JiraClient.fields) async throws -> [JSONValue] {
        let response = try await request("POST", "rest/api/3/search/jql",
                                         body: ["jql": .string(jql), "maxResults": .int(limit), "fields": .array(fields)])
        return response["issues"]?.array ?? []
    }

    func issue(_ key: String) async throws -> JSONValue {
        try await request("GET", "rest/api/3/issue/\(key)?fields=summary,status,priority,duedate,assignee,reporter,description,comment,project,issuetype,labels,created,updated")
    }

    /// Moves an issue to its "done" status (any transition into the Done category).
    func complete(_ key: String) async throws {
        let transitions = try await request("GET", "rest/api/3/issue/\(key)/transitions")["transitions"]?.array ?? []
        guard let done = transitions.first(where: { $0["to"]?["statusCategory"]?["key"]?.string == "done" })?["id"]?.string else {
            throw ChatError(message: L("This Jira issue can't be moved to Done from here."))
        }
        _ = try await request("POST", "rest/api/3/issue/\(key)/transitions", body: ["transition": ["id": .string(done)]])
    }

    func browseURL(_ key: String) -> URL { site.appending(path: "browse/\(key)") }

    func request(_ method: String, _ path: String, body: JSONValue? = nil) async throws -> JSONValue {
        var request = URLRequest(url: URL(string: path, relativeTo: site.appending(path: ""))!)
        request.httpMethod = method
        request.setValue("Basic " + Data("\(email):\(token)".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try body.encoded()
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = JSONValue.parse(data) ?? .null
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if http.statusCode == 401 || http.statusCode == 403 {
                throw ChatError(message: L("Jira rejected the email or token. Check them in Settings → Services."))
            }
            let message = (json["errorMessages"]?.array?.compactMap(\.string).first) ?? json["message"]?.string
            throw ChatError(message: "Jira: " + (message ?? L("Error %lld.", http.statusCode)))
        }
        return json
    }

    // MARK: Reading issues

    static func taskItem(_ issue: JSONValue, client: JiraClient) -> TaskItem? {
        guard let key = issue["key"]?.string, let fields = issue["fields"] else { return nil }
        let priority = fields["priority"]?["name"]?.string
        let level: TaskItem.Priority = switch priority?.lowercased() {
        case "highest", "high", "critical", "blocker": .high
        case "medium": .medium
        case "low", "lowest", "minor", "trivial": .low
        default: .none
        }
        let due = fields["duedate"]?.string.flatMap(NotionSchema.parseDate)
        return TaskItem(id: key, title: "\(key) · \(fields["summary"]?.string ?? "")", url: client.browseURL(key), source: .jira,
                        databaseID: key, databaseName: fields["project"]?["name"]?.string ?? "Jira",
                        due: due, dueHasTime: false, priorityName: priority, priorityLevel: level,
                        assigneeIDs: [], canComplete: true)
    }

    static func summary(_ issue: JSONValue, client: JiraClient) -> String {
        let key = issue["key"]?.string ?? "?"
        let fields = issue["fields"]
        var parts = ["\(key): \(fields?["summary"]?.string ?? "")"]
        if let type = fields?["issuetype"]?["name"]?.string { parts.append(type) }
        if let status = fields?["status"]?["name"]?.string { parts.append("status: \(status)") }
        if let priority = fields?["priority"]?["name"]?.string { parts.append("priority: \(priority)") }
        parts.append("assignee: " + (fields?["assignee"]?["displayName"]?.string ?? "unassigned"))
        if let due = fields?["duedate"]?.string { parts.append("due: \(due)") }
        parts.append(client.browseURL(key).absoluteString)
        return "- " + parts.joined(separator: "; ")
    }

    /// Plain text of Atlassian Document Format (descriptions, comments).
    static func text(_ document: JSONValue?) -> String {
        guard let document else { return "" }
        if let text = document.string { return text }
        var out = ""
        func walk(_ node: JSONValue) {
            let type = node["type"]?.string ?? ""
            if type == "text", let text = node["text"]?.string { out += text }
            if type == "hardBreak" { out += "\n" }
            if type == "listItem" { out += "- " }
            for child in node["content"]?.array ?? [] { walk(child) }
            if ["paragraph", "heading", "listItem", "codeBlock", "blockquote"].contains(type) { out += "\n" }
        }
        walk(document)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: AI tools

struct JiraSearchTool: AssistantTool {
    let name = "jira_search"
    var displayName: String { L("Search Jira") }
    let description = """
    Searches the user's Jira issues. `query` is words to look for, or a JQL query (e.g. \
    "project = WEB AND sprint in openSprints()"). By default only issues that aren't done. \
    Returns key, summary, type, status, priority, assignee, due date and link.
    """
    var inputSchema: JSONValue {
        ["type": "object",
         "properties": [
             "query": ["type": "string", "description": "Words or JQL. Empty lists recent issues."],
             "only_mine": ["type": "boolean", "description": "Only issues assigned to the user. Default false."],
             "include_done": ["type": "boolean", "description": "Also finished issues. Default false."],
         ]]
    }

    func describe(_ input: JSONValue) -> String { L("Search Jira for “%@”", input["query"]?.string ?? "") }

    /// Words become a text search; JQL is used as it is (with its ORDER BY kept at the end).
    static func jql(query: String, onlyMine: Bool, includeDone: Bool) -> String {
        let query = query.trimmingCharacters(in: .whitespaces)
        let looksLikeJQL = query.range(of: "(=|~|!=| in | is |order by)", options: [.regularExpression, .caseInsensitive]) != nil
        var conditions: [String] = []
        var order = "ORDER BY updated DESC"
        if looksLikeJQL {
            if let range = query.range(of: "(?i)order by.*$", options: .regularExpression) { order = String(query[range]) }
            let condition = query.replacingOccurrences(of: "(?i)\\s*order by.*$", with: "", options: .regularExpression)
            if !condition.isEmpty { conditions.append("(\(condition))") }
        } else if !query.isEmpty {
            conditions.append("text ~ \"\(query.replacingOccurrences(of: "\"", with: "\\\""))\"")
        }
        if onlyMine { conditions.append("assignee = currentUser()") }
        if !includeDone { conditions.append("statusCategory != Done") }
        return (conditions.isEmpty ? "" : conditions.joined(separator: " AND ") + " ") + order
    }

    func run(_ input: JSONValue) async -> ToolOutput {
        guard let client = JiraSettings.client else { return .error("Jira isn't connected. Ask the user to connect it in Settings → Services.") }
        let jql = Self.jql(query: input["query"]?.string ?? "", onlyMine: input["only_mine"]?.bool == true,
                           includeDone: input["include_done"]?.bool == true)
        do {
            let issues = try await client.search(jql, limit: 50)
            return ToolOutput(text: issues.isEmpty ? "No issues found (JQL: \(jql))." : issues.map { JiraClient.summary($0, client: client) }.joined(separator: "\n"))
        } catch {
            return .error(error.localizedDescription)
        }
    }
}

struct JiraReadIssueTool: AssistantTool {
    let name = "jira_read_issue"
    var displayName: String { L("Read Jira issues") }
    let description = "Reads one Jira issue by key (e.g. WEB-123): details, description and the latest comments."
    var inputSchema: JSONValue {
        ["type": "object", "properties": ["key": ["type": "string", "description": "Issue key, e.g. WEB-123."]], "required": ["key"]]
    }

    func describe(_ input: JSONValue) -> String { L("Read Jira issue %@", input["key"]?.string ?? "") }

    func run(_ input: JSONValue) async -> ToolOutput {
        guard let client = JiraSettings.client else { return .error("Jira isn't connected.") }
        do {
            let key = try input.requiredString("key").uppercased()
            let issue = try await client.issue(key)
            let fields = issue["fields"]
            var text = JiraClient.summary(issue, client: client)
            if let reporter = fields?["reporter"]?["displayName"]?.string { text += "\nreporter: \(reporter)" }
            if let labels = fields?["labels"]?.array?.compactMap(\.string), !labels.isEmpty { text += "\nlabels: " + labels.joined(separator: ", ") }
            text += "\n\nDescription:\n" + JiraClient.text(fields?["description"])
            let comments = (fields?["comment"]?["comments"]?.array ?? []).suffix(10)
            if !comments.isEmpty {
                text += "\n\nComments:\n" + comments.map { comment in
                    "- \(comment["author"]?["displayName"]?.string ?? "?") (\(comment["created"]?.string?.prefix(10) ?? "")): " + JiraClient.text(comment["body"])
                }.joined(separator: "\n")
            }
            return ToolOutput(text: String(text.prefix(40_000)))
        } catch {
            return .error(error.localizedDescription)
        }
    }
}
