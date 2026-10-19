import Foundation

/// Talks to the Notion API with an internal integration token ("ntn_…").
/// Notion only shows the integration the databases you connected to it (••• → Connections).
struct NotionClient: Sendable {
    let token: String
    var baseURL = URL(string: "https://api.notion.com/v1/")!
    private static let version = "2022-06-28"

    /// Name of the workspace the token belongs to.
    func workspaceName() async throws -> String {
        let me = try await request("GET", "users/me")
        return me["bot"]?["workspace_name"]?.string ?? "Notion"
    }

    /// People in the workspace (to pick who "me" is).
    func people() async throws -> [NotionPerson] {
        let response = try await request("GET", "users?page_size=100")
        return (response["results"]?.array ?? []).compactMap { user in
            guard user["type"]?.string == "person", let id = user["id"]?.string else { return nil }
            return NotionPerson(id: id, name: user["name"]?.string ?? "?")
        }
    }

    /// Databases shared with the integration, named "Parent page / Database".
    func databases() async throws -> [NotionDatabaseInfo] {
        var found: [JSONValue] = []
        var cursor: String?
        repeat {
            var body: [String: JSONValue] = ["filter": ["property": "object", "value": "database"], "page_size": 100]
            if let cursor { body["start_cursor"] = .string(cursor) }
            let response = try await request("POST", "search", body: .object(body))
            found += response["results"]?.array ?? []
            cursor = response["has_more"]?.bool == true ? response["next_cursor"]?.string : nil
        } while cursor != nil && found.count < 500

        var pageTitles: [String: String?] = [:] // parent id → page title, shared by databases on one page
        var result: [NotionDatabaseInfo] = []
        for database in found {
            guard let id = database["id"]?.string else { continue }
            let title = Self.plainText(database["title"]).trimmingCharacters(in: .whitespaces).nonEmpty ?? L("Untitled")
            var parent: String?
            if let parentID = database["parent"]?["page_id"]?.string ?? database["parent"]?["block_id"]?.string {
                if let cached = pageTitles[parentID] {
                    parent = cached
                } else {
                    parent = try? await pageTitle(containing: parentID)
                    pageTitles[parentID] = parent
                }
            }
            result.append(NotionDatabaseInfo(id: id, title: title, parentTitle: parent))
        }
        return result
    }

    /// Title of the page a block sits on. A board placed in a page (or in its columns) has the
    /// block as parent, so walk up until the page.
    private func pageTitle(containing id: String) async throws -> String? {
        var current = id
        for _ in 0..<6 {
            if let title = try? await pageTitle(current) { return title }
            let block = try await request("GET", "blocks/\(current)")
            let parent = block["parent"]
            guard let next = parent?["page_id"]?.string ?? parent?["block_id"]?.string else { return nil }
            current = next
        }
        return nil
    }

    func schema(of databaseID: String) async throws -> NotionSchema {
        NotionSchema(properties: try await request("GET", "databases/\(databaseID)")["properties"]?.object ?? [:])
    }

    /// Pages that aren't done yet (at most 300).
    func openPages(in databaseID: String, schema: NotionSchema) async throws -> [JSONValue] {
        var pages: [JSONValue] = []
        var cursor: String?
        repeat {
            var body: [String: JSONValue] = ["page_size": 100]
            if let filter = schema.notDoneFilter { body["filter"] = filter }
            if let cursor { body["start_cursor"] = .string(cursor) }
            let response = try await request("POST", "databases/\(databaseID)/query", body: .object(body))
            pages += response["results"]?.array ?? []
            cursor = response["has_more"]?.bool == true ? response["next_cursor"]?.string : nil
        } while cursor != nil && pages.count < 300
        return pages
    }

    func update(page pageID: String, properties: JSONValue) async throws {
        _ = try await request("PATCH", "pages/\(pageID)", body: ["properties": properties])
    }

    private func pageTitle(_ pageID: String) async throws -> String? {
        let page = try await request("GET", "pages/\(pageID)")
        for (_, property) in page["properties"]?.object ?? [:] where property["type"]?.string == "title" {
            return Self.plainText(property["title"]).nonEmpty
        }
        return nil
    }

    // MARK: HTTP

    func request(_ method: String, _ path: String, body: JSONValue? = nil) async throws -> JSONValue {
        var request = URLRequest(url: URL(string: path, relativeTo: baseURL)!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.version, forHTTPHeaderField: "Notion-Version")
        request.timeoutInterval = 30
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try body.encoded()
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = JSONValue.parse(data) ?? .null
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            switch http.statusCode {
            case 401: throw ChatError(message: L("Notion rejected the token. Check it in Settings → Tasks."))
            case 404: throw ChatError(message: L("Notion can't find this database. Connect it to your integration (••• → Connections)."))
            case 429: throw ChatError(message: L("Notion is busy. Try again in a minute."))
            default: throw ChatError(message: json["message"]?.string.map { "Notion: \($0)" } ?? L("Error %lld.", http.statusCode))
            }
        }
        return json
    }

    static func plainText(_ richText: JSONValue?) -> String {
        (richText?.array ?? []).compactMap { $0["plain_text"]?.string }.joined()
    }
}

struct NotionPerson: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
}

struct NotionDatabaseInfo: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let parentTitle: String?

    /// "Personal Home / tasks".
    var fullName: String { parentTitle.map { "\($0) / \(title)" } ?? title }
    /// What a task shows to tell databases apart: the parent page, or the database name.
    var shortName: String { parentTitle ?? title }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
