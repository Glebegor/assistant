import AppKit
import CryptoKit
import Foundation

/// Outlook mail through Microsoft Graph — work (Microsoft 365) and personal (outlook.com) accounts.
/// You register a free app in Microsoft Entra once (no secret needed), then sign in in the browser.
enum Outlook {
    static let clientIDKey = "outlook.clientID"
    static let emailKey = "outlook.email"
    static let refreshAccount = "outlook-refresh-token"
    static let registrationURL = URL(string: "https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade")!
    private static let authority = "https://login.microsoftonline.com/common/oauth2/v2.0"
    private static let scopes = "offline_access User.Read Mail.Read"

    static var clientID: String? { UserDefaults.standard.string(forKey: clientIDKey).flatMap { $0.isEmpty ? nil : $0 } }
    static var email: String? { UserDefaults.standard.string(forKey: emailKey) }
    static var isConnected: Bool { Keychain.read(refreshAccount) != nil && clientID != nil }

    private static let tokens = TokenCache()

    @MainActor
    static func signIn(clientID: String) async throws {
        let verifier = Data((0..<48).map { _ in UInt8.random(in: 0...255) }).base64URL
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL
        let state = UUID().uuidString
        let receiver = try await LoopbackReceiver.start()
        defer { receiver.stop() }
        // Microsoft accepts any port on localhost for desktop apps.
        let redirect = "http://localhost:\(receiver.port)"
        var components = URLComponents(string: "\(authority)/authorize")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_mode", value: "query"),
            .init(name: "scope", value: scopes),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
            .init(name: "prompt", value: "select_account"),
        ]
        NSWorkspace.shared.open(components.url!)

        let query = try await receiver.waitForQuery(timeout: 300)
        guard query["state"] == state else { throw ChatError(message: L("Microsoft sign-in failed. Try again.")) }
        if let error = query["error_description"] ?? query["error"] { throw ChatError(message: L("Microsoft sign-in was cancelled (%@).", error)) }
        guard let code = query["code"] else { throw ChatError(message: L("Microsoft sign-in failed. Try again.")) }

        let response = try await tokenRequest([
            "client_id": clientID, "grant_type": "authorization_code", "code": code,
            "redirect_uri": redirect, "code_verifier": verifier, "scope": scopes,
        ])
        guard let refresh = response["refresh_token"]?.string, let access = response["access_token"]?.string else {
            throw ChatError(message: response["error_description"]?.string ?? L("Microsoft sign-in failed. Try again."))
        }
        UserDefaults.standard.set(clientID, forKey: clientIDKey)
        Keychain.save(refresh, for: refreshAccount)
        await tokens.store(access, lifetime: TimeInterval(response["expires_in"]?.int ?? 3600))
        if let me = try? await graph("me?$select=mail,userPrincipalName") {
            UserDefaults.standard.set(me["mail"]?.string ?? me["userPrincipalName"]?.string, forKey: emailKey)
        }
    }

    static func signOut() async {
        Keychain.delete(refreshAccount)
        UserDefaults.standard.removeObject(forKey: emailKey)
        await tokens.clear()
    }

    static func accessToken() async throws -> String {
        if let token = await tokens.valid() { return token }
        guard let clientID, let refresh = Keychain.read(refreshAccount) else {
            throw ChatError(message: L("Outlook isn't connected. Sign in in Settings → Services."))
        }
        let response = try await tokenRequest(["client_id": clientID, "grant_type": "refresh_token", "refresh_token": refresh, "scope": scopes])
        guard let token = response["access_token"]?.string else {
            throw ChatError(message: L("Outlook sign-in expired. Sign in again in Settings → Services."))
        }
        // Microsoft gives a new refresh token each time; keep the newest.
        if let newRefresh = response["refresh_token"]?.string { Keychain.save(newRefresh, for: refreshAccount) }
        await tokens.store(token, lifetime: TimeInterval(response["expires_in"]?.int ?? 3600))
        return token
    }

    static func graph(_ path: String) async throws -> JSONValue {
        var request = URLRequest(url: URL(string: "https://graph.microsoft.com/v1.0/" + path)!)
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = JSONValue.parse(data) ?? .null
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            if http.statusCode == 401 { throw ChatError(message: L("Outlook sign-in expired. Sign in again in Settings → Services.")) }
            throw ChatError(message: "Outlook: " + (json["error"]?["message"]?.string ?? L("Error %lld.", http.statusCode)))
        }
        return json
    }

    private static func tokenRequest(_ fields: [String: String]) async throws -> JSONValue {
        var request = URLRequest(url: URL(string: "\(authority)/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = Data(fields.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        return JSONValue.parse(data) ?? .null
    }

    private actor TokenCache {
        private var token: String?
        private var expires = Date.distantPast
        func valid() -> String? { Date() < expires ? token : nil }
        func store(_ token: String, lifetime: TimeInterval) { self.token = token; expires = Date().addingTimeInterval(lifetime - 120) }
        func clear() { token = nil; expires = .distantPast }
    }

    static func query(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#\""))) ?? text
    }
}

// MARK: AI tools

struct OutlookSearchTool: AssistantTool {
    let name = "outlook_search"
    var displayName: String { L("Search Outlook mail") }
    let description = """
    Searches the user's Outlook mail (words, a sender, a subject…; empty for the latest emails). \
    Returns sender, subject, date, a short preview, whether it's unread, and the message ID.
    """
    var inputSchema: JSONValue {
        ["type": "object",
         "properties": [
             "query": ["type": "string", "description": "What to look for, e.g. \"invoice\" or \"from:jirka@firma.cz\". Optional."],
             "max_results": ["type": "integer", "description": "1–30, default 10."],
         ]]
    }

    func describe(_ input: JSONValue) -> String { L("Search Outlook for “%@”", input["query"]?.string ?? "") }

    func run(_ input: JSONValue) async -> ToolOutput {
        guard Outlook.isConnected else { return .error("Outlook isn't connected. Ask the user to sign in in Settings → Services.") }
        let limit = min(30, max(1, input["max_results"]?.int ?? 10))
        let query = (input["query"]?.string ?? "").trimmingCharacters(in: .whitespaces)
        var path = "me/messages?$top=\(limit)&$select=id,subject,from,receivedDateTime,bodyPreview,isRead"
        // $search finds by words; without it the newest come first.
        path += query.isEmpty ? "&$orderby=receivedDateTime%20desc" : "&$search=%22\(Outlook.query(query))%22"
        do {
            let messages = try await Outlook.graph(path)["value"]?.array ?? []
            guard !messages.isEmpty else { return ToolOutput(text: "No emails found.") }
            let lines = messages.map { message in
                let from = message["from"]?["emailAddress"]
                let sender = [from?["name"]?.string, from?["address"]?.string.map { "<\($0)>" }].compactMap { $0 }.joined(separator: " ")
                return "- \(message["receivedDateTime"]?.string?.prefix(16).replacingOccurrences(of: "T", with: " ") ?? "") — \(sender) — "
                    + "\(message["subject"]?.string ?? "(no subject)")\(message["isRead"]?.bool == false ? " [unread]" : "")\n"
                    + "    \(message["bodyPreview"]?.string?.prefix(200) ?? "") (id: \(message["id"]?.string ?? ""))"
            }
            return ToolOutput(text: lines.joined(separator: "\n"))
        } catch {
            return .error(error.localizedDescription)
        }
    }
}

struct OutlookReadTool: AssistantTool {
    let name = "outlook_read"
    var displayName: String { L("Read Outlook mail") }
    let description = "Reads one Outlook email: sender, recipients, date, subject, the text and attachment names."
    var inputSchema: JSONValue {
        ["type": "object", "properties": ["message_id": ["type": "string"]], "required": ["message_id"]]
    }

    func describe(_ input: JSONValue) -> String { L("Read an email") }

    func run(_ input: JSONValue) async -> ToolOutput {
        guard Outlook.isConnected else { return .error("Outlook isn't connected.") }
        do {
            let id = try input.requiredString("message_id")
            let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
            let message = try await Outlook.graph("me/messages/\(encoded)?$select=subject,from,toRecipients,ccRecipients,receivedDateTime,body,hasAttachments")
            func people(_ value: JSONValue?) -> String {
                (value?.array ?? []).compactMap { $0["emailAddress"]?["address"]?.string }.joined(separator: ", ")
            }
            var text = "From: \(message["from"]?["emailAddress"]?["name"]?.string ?? "") <\(message["from"]?["emailAddress"]?["address"]?.string ?? "")>\n"
            text += "To: \(people(message["toRecipients"]))\n"
            let cc = people(message["ccRecipients"])
            if !cc.isEmpty { text += "Cc: \(cc)\n" }
            text += "Date: \(message["receivedDateTime"]?.string ?? "")\nSubject: \(message["subject"]?.string ?? "")\n\n"
            let body = message["body"]?["content"]?.string ?? ""
            text += message["body"]?["contentType"]?.string == "html" ? Gmail.plainText(fromHTML: body) : body
            if message["hasAttachments"]?.bool == true {
                let attachments = (try? await Outlook.graph("me/messages/\(encoded)/attachments?$select=name"))?["value"]?.array ?? []
                let names = attachments.compactMap { $0["name"]?.string }
                if !names.isEmpty { text += "\n\nAttachments: " + names.joined(separator: ", ") }
            }
            return ToolOutput(text: String(text.prefix(50_000)))
        } catch {
            return .error(error.localizedDescription)
        }
    }
}
