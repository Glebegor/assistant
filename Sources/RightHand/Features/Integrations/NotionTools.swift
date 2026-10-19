import Foundation

/// The AI's Notion tools: search, read pages and databases, change tasks. They use the Notion
/// workspaces connected in Settings → Services (the same integration tokens as the Tasks tab).
enum NotionAccess {
    static var clients: [NotionClient] {
        TasksSettings.connections.compactMap { Keychain.read($0.keychainAccount).map { NotionClient(token: $0) } }
    }

    static var isConnected: Bool { !TasksSettings.connections.isEmpty }

    /// Runs `body` with the first workspace that can see the page (each token sees only its own).
    static func withClient<T>(for id: String, _ body: (NotionClient) async throws -> T) async throws -> T {
        var lastError: Error = ToolError("Notion isn't connected. Ask the user to connect it in Settings → Services.")
        for client in clients {
            do { return try await body(client) } catch { lastError = error }
        }
        throw lastError
    }

    /// Accepts a page ID with or without dashes, or a notion.so link.
    static func pageID(_ text: String) -> String {
        let hex = text.split(separator: "?").first.map(String.init) ?? text
        if let match = hex.range(of: "[0-9a-fA-F]{32}", options: .regularExpression) { return String(hex[match]) }
        return text.trimmingCharacters(in: .whitespaces)
    }
}

/// Plain text of Notion properties and blocks, for the AI to read.
enum NotionText {
    static func property(_ value: JSONValue) -> String {
        let type = value["type"]?.string ?? ""
        let content = value[type]
        switch type {
        case "title", "rich_text":
            return NotionClient.plainText(content)
        case "number":
            return content?.int.map(String.init) ?? content.flatMap { if case .double(let d) = $0 { String(d) } else { nil } } ?? ""
        case "select", "status":
            return content?["name"]?.string ?? ""
        case "multi_select":
            return (content?.array ?? []).compactMap { $0["name"]?.string }.joined(separator: ", ")
        case "date":
            guard let start = content?["start"]?.string else { return "" }
            return content?["end"]?.string.map { "\(start) → \($0)" } ?? start
        case "people":
            return (content?.array ?? []).compactMap { $0["name"]?.string ?? $0["id"]?.string }.joined(separator: ", ")
        case "checkbox":
            return content?.bool == true ? "yes" : "no"
        case "url", "email", "phone_number", "created_time", "last_edited_time":
            return content?.string ?? ""
        case "formula":
            guard let formula = content, let kind = formula["type"]?.string else { return "" }
            if kind == "date" { return formula["date"]?["start"]?.string ?? "" }
            return formula[kind].map { $0.string ?? ($0.bool.map { $0 ? "yes" : "no" }) ?? $0.jsonString } ?? ""
        case "relation":
            return (content?.array ?? []).compactMap { $0["id"]?.string }.joined(separator: ", ")
        case "unique_id":
            return [content?["prefix"]?.string, content?["number"]?.int.map(String.init)].compactMap { $0 }.joined(separator: "-")
        case "files":
            return (content?.array ?? []).compactMap { $0["name"]?.string }.joined(separator: ", ")
        default:
            return ""
        }
    }

    static func properties(of page: JSONValue) -> [String] {
        (page["properties"]?.object ?? [:]).sorted { $0.key < $1.key }.compactMap { name, value in
            let text = property(value)
            return text.isEmpty ? nil : "\(name): \(text)"
        }
    }

    static func title(of item: JSONValue) -> String {
        if item["object"]?.string == "database" { return NotionClient.plainText(item["title"]) }
        for (_, value) in item["properties"]?.object ?? [:] where value["type"]?.string == "title" {
            return NotionClient.plainText(value["title"])
        }
        return ""
    }

    static func block(_ block: JSONValue) -> String? {
        guard let type = block["type"]?.string else { return nil }
        let content = block[type]
        let text = NotionClient.plainText(content?["rich_text"])
        switch type {
        case "heading_1": return "# " + text
        case "heading_2": return "## " + text
        case "heading_3": return "### " + text
        case "bulleted_list_item", "toggle": return "- " + text
        case "numbered_list_item": return "1. " + text
        case "to_do": return (content?["checked"]?.bool == true ? "[x] " : "[ ] ") + text
        case "quote", "callout": return "> " + text
        case "code": return "```\n" + text + "\n```"
        case "paragraph": return text
        case "child_page": return "[page: \(content?["title"]?.string ?? "")] id=\(block["id"]?.string ?? "")"
        case "child_database": return "[database: \(content?["title"]?.string ?? "")] id=\(block["id"]?.string ?? "")"
        case "bookmark", "embed", "link_preview": return content?["url"]?.string
        case "divider": return "---"
        case "table_row":
            return (content?["cells"]?.array ?? []).map { NotionClient.plainText($0) }.joined(separator: " | ")
        default: return text.isEmpty ? nil : text
        }
    }
}

struct NotionSearchTool: AssistantTool {
    let name = "notion_search"
    var displayName: String { L("Search Notion") }
    let description = """
    Searches the user's Notion (pages and databases shared with RightHand) by title. Returns titles, IDs and links. \
    Use an empty query to list recently edited pages. Then read a page with notion_read_page or a database with notion_query_database.
    """
    var inputSchema: JSONValue {
        ["type": "object",
         "properties": [
             "query": ["type": "string", "description": "Words from the title. Empty lists recent pages."],
             "only": ["type": "string", "enum": ["page", "database"], "description": "Only pages or only databases. Optional."],
         ]]
    }

    func describe(_ input: JSONValue) -> String { L("Search Notion for “%@”", input["query"]?.string ?? "") }

    func run(_ input: JSONValue) async -> ToolOutput {
        let clients = NotionAccess.clients
        guard !clients.isEmpty else { return .error("Notion isn't connected. Ask the user to connect it in Settings → Services.") }
        var body: [String: JSONValue] = ["query": .string(input["query"]?.string ?? ""), "page_size": 25,
                                         "sort": ["direction": "descending", "timestamp": "last_edited_time"]]
        if let only = input["only"]?.string { body["filter"] = ["property": "object", "value": .string(only)] }
        var lines: [String] = []
        for client in clients {
            do {
                let response = try await client.request("POST", "search", body: .object(body))
                for item in response["results"]?.array ?? [] {
                    let kind = item["object"]?.string ?? "page"
                    let title = NotionText.title(of: item)
                    lines.append("- [\(kind)] \(title.isEmpty ? "Untitled" : title) — id: \(item["id"]?.string ?? "") — \(item["url"]?.string ?? "")"
                                 + " — edited \(item["last_edited_time"]?.string?.prefix(10) ?? "")")
                }
            } catch {
                lines.append("(\(error.localizedDescription))")
            }
        }
        return ToolOutput(text: lines.isEmpty ? "Nothing found." : lines.joined(separator: "\n"))
    }
}

struct NotionReadPageTool: AssistantTool {
    private static let maxCharacters = 40_000

    let name = "notion_read_page"
    var displayName: String { L("Read Notion pages") }
    let description = "Reads a Notion page: its properties (status, dates, people, …) and its content as text."
    var inputSchema: JSONValue {
        ["type": "object",
         "properties": ["page_id": ["type": "string", "description": "Page ID or notion.so link."]],
         "required": ["page_id"]]
    }

    func describe(_ input: JSONValue) -> String { L("Read a Notion page") }

    func run(_ input: JSONValue) async -> ToolOutput {
        do {
            let id = NotionAccess.pageID(try input.requiredString("page_id"))
            return try await NotionAccess.withClient(for: id) { client in
                let page = try await client.request("GET", "pages/\(id)")
                var text = "# \(NotionText.title(of: page))\n\(page["url"]?.string ?? "")\n\n"
                text += NotionText.properties(of: page).joined(separator: "\n") + "\n\n"
                text += try await content(of: id, client: client, depth: 0)
                if text.count > Self.maxCharacters { text = String(text.prefix(Self.maxCharacters)) + "\n… (page is longer)" }
                return ToolOutput(text: text)
            }
        } catch {
            return .error(error.localizedDescription)
        }
    }

    private func content(of blockID: String, client: NotionClient, depth: Int) async throws -> String {
        var lines: [String] = []
        var cursor: String?
        repeat {
            let path = "blocks/\(blockID)/children?page_size=100" + (cursor.map { "&start_cursor=\($0)" } ?? "")
            let response = try await client.request("GET", path)
            for block in response["results"]?.array ?? [] {
                if let line = NotionText.block(block) { lines.append(String(repeating: "  ", count: depth) + line) }
                let type = block["type"]?.string ?? ""
                if block["has_children"]?.bool == true, depth < 2, !["child_page", "child_database"].contains(type),
                   let child = block["id"]?.string {
                    lines.append(try await content(of: child, client: client, depth: depth + 1))
                }
            }
            cursor = response["has_more"]?.bool == true ? response["next_cursor"]?.string : nil
        } while cursor != nil && lines.count < 600
        return lines.joined(separator: "\n")
    }
}

struct NotionQueryDatabaseTool: AssistantTool {
    let name = "notion_query_database"
    var displayName: String { L("Read Notion databases") }
    let description = """
    Lists rows of a Notion database (e.g. a task board) with their properties and IDs. \
    By default only rows that aren't done; set include_done to see all.
    """
    var inputSchema: JSONValue {
        ["type": "object",
         "properties": [
             "database_id": ["type": "string", "description": "Database ID or notion.so link."],
             "include_done": ["type": "boolean", "description": "Also list finished rows. Default false."],
             "limit": ["type": "integer", "description": "At most this many rows, 1–200. Default 50."],
         ],
         "required": ["database_id"]]
    }

    func describe(_ input: JSONValue) -> String { L("Read a Notion database") }

    func run(_ input: JSONValue) async -> ToolOutput {
        do {
            let id = NotionAccess.pageID(try input.requiredString("database_id"))
            let limit = min(200, max(1, input["limit"]?.int ?? 50))
            return try await NotionAccess.withClient(for: id) { client in
                let schema = try await client.schema(of: id)
                var body: [String: JSONValue] = ["page_size": .int(min(100, limit))]
                if input["include_done"]?.bool != true, let filter = schema.notDoneFilter { body["filter"] = filter }
                let response = try await client.request("POST", "databases/\(id)/query", body: .object(body))
                let rows = (response["results"]?.array ?? []).prefix(limit).map { page in
                    "- \(NotionText.title(of: page)) (id: \(page["id"]?.string ?? ""))\n    "
                        + NotionText.properties(of: page).filter { !$0.hasPrefix((schema.title ?? "") + ":") }.joined(separator: "; ")
                }
                return ToolOutput(text: rows.isEmpty ? "No rows." : rows.joined(separator: "\n"))
            }
        } catch {
            return .error(error.localizedDescription)
        }
    }
}

struct NotionUpdateTaskTool: AssistantTool {
    let name = "notion_update_task"
    var displayName: String { L("Change Notion tasks") }
    let description = """
    Changes a page in a Notion database, usually a task: title, status, done, due date, priority, \
    or adds text at the end of the page. Only the fields you give are changed. \
    Status and priority must be option names that exist in the database (read it first if unsure).
    """
    var inputSchema: JSONValue {
        ["type": "object",
         "properties": [
             "page_id": ["type": "string", "description": "Page ID or notion.so link."],
             "title": ["type": "string"],
             "status": ["type": "string", "description": "Status option name, e.g. \"In progress\"."],
             "done": ["type": "boolean", "description": "true marks the task done."],
             "due": ["type": "string", "description": "YYYY-MM-DD, or YYYY-MM-DDTHH:MM with time. Empty string clears it."],
             "priority": ["type": "string", "description": "Priority option name, e.g. \"High\"."],
             "append_text": ["type": "string", "description": "Text to add at the end of the page."],
         ],
         "required": ["page_id"]]
    }

    func describe(_ input: JSONValue) -> String {
        var changes: [String] = []
        if let title = input["title"]?.string { changes.append(L("title “%@”", title)) }
        if let status = input["status"]?.string { changes.append(L("status “%@”", status)) }
        if input["done"]?.bool == true { changes.append(L("mark done")) }
        if let due = input["due"]?.string { changes.append(due.isEmpty ? L("remove due date") : L("due %@", due)) }
        if let priority = input["priority"]?.string { changes.append(L("priority “%@”", priority)) }
        if input["append_text"]?.string != nil { changes.append(L("add text")) }
        return L("Change a Notion task: %@", changes.joined(separator: ", "))
    }

    func detail(_ input: JSONValue) -> String? { input["append_text"]?.string }

    func run(_ input: JSONValue) async -> ToolOutput {
        do {
            let id = NotionAccess.pageID(try input.requiredString("page_id"))
            return try await NotionAccess.withClient(for: id) { client in
                let page = try await client.request("GET", "pages/\(id)")
                var properties: [String: JSONValue] = [:]
                if let databaseID = page["parent"]?["database_id"]?.string {
                    let schema = try await client.schema(of: databaseID)
                    let types = (page["properties"]?.object ?? [:]).mapValues { $0["type"]?.string ?? "" }
                    if let title = input["title"]?.string, let property = schema.title {
                        properties[property] = ["title": [["text": ["content": .string(title)]]]]
                    }
                    if input["done"]?.bool == true, let update = schema.doneUpdate?.object { properties.merge(update) { $1 } }
                    if let status = input["status"]?.string {
                        switch schema.done {
                        case .status(let property, _): properties[property] = ["status": ["name": .string(status)]]
                        case .select(let property, _): properties[property] = ["select": ["name": .string(status)]]
                        default: return .error("This database has no status property.")
                        }
                    }
                    if let due = input["due"]?.string {
                        guard let property = schema.due else { return .error("This database has no date property.") }
                        properties[property] = due.isEmpty ? ["date": .null] : ["date": ["start": .string(due)]]
                    }
                    if let priority = input["priority"]?.string {
                        guard let property = schema.priority else { return .error("This database has no priority property.") }
                        properties[property] = [types[property] == "status" ? "status" : "select": ["name": .string(priority)]]
                    }
                } else if let title = input["title"]?.string {
                    properties["title"] = ["title": [["text": ["content": .string(title)]]]]
                }
                if !properties.isEmpty { try await client.update(page: id, properties: .object(properties)) }
                if let text = input["append_text"]?.string, !text.isEmpty {
                    let paragraphs: [JSONValue] = text.components(separatedBy: "\n").map { line in
                        ["object": "block", "type": "paragraph",
                         "paragraph": ["rich_text": [["type": "text", "text": ["content": .string(String(line.prefix(2000)))]]]]]
                    }
                    _ = try await client.request("PATCH", "blocks/\(id)/children", body: ["children": .array(paragraphs)])
                }
                return ToolOutput(text: "Updated \(NotionText.title(of: page)) (\(page["url"]?.string ?? id)).")
            }
        } catch {
            return .error(error.localizedDescription)
        }
    }
}
