import Foundation
import PDFKit
import UniformTypeIdentifiers

/// Calls Google APIs with the signed-in account.
enum GoogleAPI {
    static func json(_ url: String, method: String = "GET", body: Data? = nil, contentType: String? = nil) async throws -> JSONValue {
        let (data, _) = try await data(url, method: method, body: body, contentType: contentType)
        return JSONValue.parse(data) ?? .null
    }

    static func data(_ url: String, method: String = "GET", body: Data? = nil, contentType: String? = nil) async throws -> (Data, String?) {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        request.setValue("Bearer \(try await GoogleAuth.accessToken())", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60
        if let body {
            request.httpBody = body
            request.setValue(contentType ?? "application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        if let http, !(200..<300).contains(http.statusCode) {
            let message = JSONValue.parse(data)?["error"]?["message"]?.string
            if http.statusCode == 401 { throw ChatError(message: L("Google sign-in expired. Sign in again in Settings → Services.")) }
            throw ChatError(message: "Google: " + (message ?? L("Error %lld.", http.statusCode)))
        }
        return (data, http?.value(forHTTPHeaderField: "Content-Type"))
    }

    static func query(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))) ?? text
    }

    /// One multipart/related body: JSON metadata + file content (Drive uploads).
    static func multipart(metadata: JSONValue, content: Data, contentType: String) throws -> (Data, String) {
        let boundary = "RightHand-\(UUID().uuidString)"
        var body = Data("--\(boundary)\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n".utf8)
        body += try metadata.encoded()
        body += Data("\r\n--\(boundary)\r\nContent-Type: \(contentType)\r\n\r\n".utf8)
        body += content
        body += Data("\r\n--\(boundary)--\r\n".utf8)
        return (body, "multipart/related; boundary=\(boundary)")
    }

    static let notConnected = ToolOutput.error("Google isn't connected. Ask the user to sign in in Settings → Services.")
}

// MARK: Gmail

struct GmailSearchTool: AssistantTool {
    let name = "gmail_search"
    var displayName: String { L("Search Gmail") }
    let description = """
    Searches the user's Gmail with Gmail search syntax (e.g. "from:jirka newer_than:7d", "is:unread", \
    "subject:invoice"). Returns sender, subject, date, a short snippet and the message ID for each email.
    """
    var inputSchema: JSONValue {
        ["type": "object",
         "properties": [
             "query": ["type": "string", "description": "Gmail search query. Empty for the latest emails."],
             "max_results": ["type": "integer", "description": "1–30, default 10."],
         ]]
    }

    func describe(_ input: JSONValue) -> String { L("Search Gmail for “%@”", input["query"]?.string ?? "") }

    func run(_ input: JSONValue) async -> ToolOutput {
        guard GoogleAuth.isConnected else { return GoogleAPI.notConnected }
        do {
            let limit = min(30, max(1, input["max_results"]?.int ?? 10))
            let list = try await GoogleAPI.json("https://gmail.googleapis.com/gmail/v1/users/me/messages?maxResults=\(limit)&q="
                                                + GoogleAPI.query(input["query"]?.string ?? ""))
            let ids = (list["messages"]?.array ?? []).compactMap { $0["id"]?.string }
            guard !ids.isEmpty else { return ToolOutput(text: "No emails found.") }
            let summaries = try await withThrowingTaskGroup(of: (Int, String).self) { group in
                for (index, id) in ids.enumerated() {
                    group.addTask {
                        let message = try await GoogleAPI.json("https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)?format=metadata"
                                                               + "&metadataHeaders=From&metadataHeaders=Subject&metadataHeaders=Date")
                        let headers = Gmail.headers(message)
                        let unread = (message["labelIds"]?.array ?? []).contains("UNREAD") ? " [unread]" : ""
                        return (index, "- \(headers["Date"] ?? "") — \(headers["From"] ?? "?") — \(headers["Subject"] ?? "(no subject)")\(unread)"
                                + "\n    \(message["snippet"]?.string ?? "") (id: \(id))")
                    }
                }
                var result: [(Int, String)] = []
                for try await item in group { result.append(item) }
                return result.sorted { $0.0 < $1.0 }.map(\.1)
            }
            return ToolOutput(text: summaries.joined(separator: "\n"))
        } catch {
            return .error(error.localizedDescription)
        }
    }
}

struct GmailReadTool: AssistantTool {
    let name = "gmail_read"
    var displayName: String { L("Read emails") }
    let description = "Reads one email from Gmail: sender, recipients, date, subject, the text and attachment names."
    var inputSchema: JSONValue {
        ["type": "object", "properties": ["message_id": ["type": "string"]], "required": ["message_id"]]
    }

    func describe(_ input: JSONValue) -> String { L("Read an email") }

    func run(_ input: JSONValue) async -> ToolOutput {
        guard GoogleAuth.isConnected else { return GoogleAPI.notConnected }
        do {
            let id = try input.requiredString("message_id")
            let message = try await GoogleAPI.json("https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)?format=full")
            let headers = Gmail.headers(message)
            var text = ["From", "To", "Cc", "Date", "Subject"].compactMap { key in headers[key].map { "\(key): \($0)" } }.joined(separator: "\n")
            text += "\n\n" + (Gmail.body(message["payload"]) ?? message["snippet"]?.string ?? "")
            let attachments = Gmail.attachments(message["payload"])
            if !attachments.isEmpty { text += "\n\nAttachments: " + attachments.joined(separator: ", ") }
            return ToolOutput(text: String(text.prefix(50_000)))
        } catch {
            return .error(error.localizedDescription)
        }
    }
}

enum Gmail {
    static func headers(_ message: JSONValue) -> [String: String] {
        Dictionary((message["payload"]?["headers"]?.array ?? []).compactMap { header in
            header["name"]?.string.flatMap { name in header["value"]?.string.map { (name, $0) } }
        }, uniquingKeysWith: { first, _ in first })
    }

    /// The plain text of an email (or its HTML turned into text).
    static func body(_ part: JSONValue?) -> String? {
        if let plain = find(part, mimeType: "text/plain") { return plain }
        return find(part, mimeType: "text/html").map(plainText(fromHTML:))
    }

    private static func find(_ part: JSONValue?, mimeType: String) -> String? {
        guard let part else { return nil }
        if part["mimeType"]?.string == mimeType, let data = part["body"]?["data"]?.string, let decoded = Data(base64URL: data) {
            return String(decoding: decoded, as: UTF8.self)
        }
        for child in part["parts"]?.array ?? [] {
            if let found = find(child, mimeType: mimeType) { return found }
        }
        return nil
    }

    static func attachments(_ part: JSONValue?) -> [String] {
        guard let part else { return [] }
        var names: [String] = []
        if let filename = part["filename"]?.string, !filename.isEmpty { names.append(filename) }
        for child in part["parts"]?.array ?? [] { names += attachments(child) }
        return names
    }

    static func plainText(fromHTML html: String) -> String {
        var text = html.replacingOccurrences(of: "(?is)<(script|style)[^>]*>.*?</\\1>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>|</p>|</div>|</tr>|</h[1-6]>|</li>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, character) in ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'"] {
            text = text.replacingOccurrences(of: entity, with: character)
        }
        return text.replacingOccurrences(of: "\n\\s*\n\\s*\n+", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: Drive

enum Drive {
    static let fields = "id,name,mimeType,modifiedTime,size,webViewLink,parents"
    static let folderType = "application/vnd.google-apps.folder"

    static func summary(_ file: JSONValue) -> String {
        let kind = (file["mimeType"]?.string ?? "").replacingOccurrences(of: "application/vnd.google-apps.", with: "google-")
        let size = file["size"]?.string.flatMap(Int64.init).map { ", " + ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? ""
        return "- \(file["name"]?.string ?? "?") (\(kind)\(size), modified \(file["modifiedTime"]?.string?.prefix(10) ?? "")) "
            + "id: \(file["id"]?.string ?? "") \(file["webViewLink"]?.string ?? "")"
    }

    /// Google Docs/Sheets/Slides are exported; other files are downloaded as they are.
    static func exportType(for mimeType: String, format: String?) -> (mime: String, ext: String)? {
        let formats: [String: (String, String)] = [
            "pdf": ("application/pdf", "pdf"),
            "docx": ("application/vnd.openxmlformats-officedocument.wordprocessingml.document", "docx"),
            "xlsx": ("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "xlsx"),
            "pptx": ("application/vnd.openxmlformats-officedocument.presentationml.presentation", "pptx"),
            "csv": ("text/csv", "csv"),
            "txt": ("text/plain", "txt"),
        ]
        guard mimeType.hasPrefix("application/vnd.google-apps.") else { return nil }
        if let format, let chosen = formats[format] { return chosen }
        switch mimeType {
        case "application/vnd.google-apps.spreadsheet": return formats["xlsx"]
        case "application/vnd.google-apps.presentation": return formats["pptx"]
        default: return formats["pdf"]
        }
    }
}

struct DriveSearchTool: AssistantTool {
    let name = "drive_search"
    var displayName: String { L("Search Google Drive") }
    let description = """
    Searches the user's Google Drive by file name and text. Returns name, type, date, ID and link. \
    Use folder_id to list one folder (find folders by searching with type "folder").
    """
    var inputSchema: JSONValue {
        ["type": "object",
         "properties": [
             "query": ["type": "string", "description": "Words in the name or text. Empty lists recent files."],
             "type": ["type": "string", "enum": ["any", "document", "spreadsheet", "presentation", "pdf", "folder"]],
             "folder_id": ["type": "string", "description": "Only files in this folder. Optional."],
         ]]
    }

    func describe(_ input: JSONValue) -> String { L("Search Google Drive for “%@”", input["query"]?.string ?? "") }

    func run(_ input: JSONValue) async -> ToolOutput {
        guard GoogleAuth.isConnected else { return GoogleAPI.notConnected }
        do {
            var conditions = ["trashed = false"]
            if let text = input["query"]?.string, !text.isEmpty {
                let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
                conditions.append("(name contains '\(escaped)' or fullText contains '\(escaped)')")
            }
            let types = ["document": "application/vnd.google-apps.document", "spreadsheet": "application/vnd.google-apps.spreadsheet",
                         "presentation": "application/vnd.google-apps.presentation", "pdf": "application/pdf", "folder": Drive.folderType]
            if let type = input["type"]?.string, let mime = types[type] { conditions.append("mimeType = '\(mime)'") }
            if let folder = input["folder_id"]?.string { conditions.append("'\(folder)' in parents") }
            let url = "https://www.googleapis.com/drive/v3/files?pageSize=30&orderBy=modifiedTime%20desc&fields=files(\(Drive.fields))&q="
                + GoogleAPI.query(conditions.joined(separator: " and "))
            let files = try await GoogleAPI.json(url)["files"]?.array ?? []
            return ToolOutput(text: files.isEmpty ? "No files found." : files.map(Drive.summary).joined(separator: "\n"))
        } catch {
            return .error(error.localizedDescription)
        }
    }
}

struct DriveReadTool: AssistantTool {
    let name = "drive_read"
    var displayName: String { L("Read Google Drive files") }
    let description = "Reads the text of a Google Drive file: Google Docs, Sheets (as CSV), Slides, PDFs and text files."
    var inputSchema: JSONValue {
        ["type": "object", "properties": ["file_id": ["type": "string"]], "required": ["file_id"]]
    }

    func describe(_ input: JSONValue) -> String { L("Read a Google Drive file") }

    func run(_ input: JSONValue) async -> ToolOutput {
        guard GoogleAuth.isConnected else { return GoogleAPI.notConnected }
        do {
            let id = try input.requiredString("file_id")
            let file = try await GoogleAPI.json("https://www.googleapis.com/drive/v3/files/\(id)?fields=\(Drive.fields)")
            let mime = file["mimeType"]?.string ?? ""
            let text: String
            switch mime {
            case "application/vnd.google-apps.document", "application/vnd.google-apps.presentation":
                text = String(decoding: try await GoogleAPI.data("https://www.googleapis.com/drive/v3/files/\(id)/export?mimeType=text/plain").0, as: UTF8.self)
            case "application/vnd.google-apps.spreadsheet":
                text = String(decoding: try await GoogleAPI.data("https://www.googleapis.com/drive/v3/files/\(id)/export?mimeType=text/csv").0, as: UTF8.self)
            case "application/pdf":
                let data = try await GoogleAPI.data("https://www.googleapis.com/drive/v3/files/\(id)?alt=media").0
                text = PDFDocument(data: data)?.string ?? ""
            case let type where type.hasPrefix("text/") || ["application/json", "application/xml"].contains(type):
                text = String(decoding: try await GoogleAPI.data("https://www.googleapis.com/drive/v3/files/\(id)?alt=media").0, as: UTF8.self)
            default:
                return .error("\(file["name"]?.string ?? id) (\(mime)) isn't a text file. Download it with drive_download instead.")
            }
            let header = "\(file["name"]?.string ?? "") — \(file["webViewLink"]?.string ?? "")\n\n"
            return ToolOutput(text: header + (text.count > 60_000 ? String(text.prefix(60_000)) + "\n… (file is longer)" : text))
        } catch {
            return .error(error.localizedDescription)
        }
    }
}

struct DriveCreateDocTool: AssistantTool {
    let name = "drive_create_doc"
    var displayName: String { L("Create Google Docs") }
    let description = "Creates a new Google Doc in the user's Drive with the given text (Markdown-like plain text)."
    var inputSchema: JSONValue {
        ["type": "object",
         "properties": [
             "name": ["type": "string"],
             "content": ["type": "string"],
             "folder_id": ["type": "string", "description": "Drive folder to put it in. Optional."],
         ],
         "required": ["name", "content"]]
    }

    func describe(_ input: JSONValue) -> String { L("Create Google Doc “%@”", input["name"]?.string ?? "") }

    func detail(_ input: JSONValue) -> String? {
        input["content"]?.string.map { $0.count > 1_500 ? String($0.prefix(1_500)) + "\n…" : $0 }
    }

    func run(_ input: JSONValue) async -> ToolOutput {
        guard GoogleAuth.isConnected else { return GoogleAPI.notConnected }
        do {
            var metadata: [String: JSONValue] = ["name": .string(try input.requiredString("name")),
                                                 "mimeType": "application/vnd.google-apps.document"]
            if let folder = input["folder_id"]?.string { metadata["parents"] = [.string(folder)] }
            let (body, type) = try GoogleAPI.multipart(metadata: .object(metadata), content: Data((input["content"]?.string ?? "").utf8),
                                                       contentType: "text/plain; charset=UTF-8")
            let file = try await GoogleAPI.json("https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=\(Drive.fields)", method: "POST",
                                                body: body, contentType: type)
            return ToolOutput(text: "Created " + Drive.summary(file))
        } catch {
            return .error(error.localizedDescription)
        }
    }
}

struct DriveUploadTool: AssistantTool {
    let access: FileAccess

    let name = "drive_upload"
    var displayName: String { L("Upload to Google Drive") }
    let description = "Uploads a file from the user's Mac to Google Drive (up to 100 MB)."
    var inputSchema: JSONValue {
        ["type": "object",
         "properties": [
             "path": ["type": "string", "description": "File on the Mac (absolute, ~/…, or relative to the first project folder)."],
             "folder_id": ["type": "string", "description": "Drive folder to put it in. Optional."],
             "name": ["type": "string", "description": "Name in Drive. Defaults to the file name."],
         ],
         "required": ["path"]]
    }

    func alwaysAsks(_ input: JSONValue) -> Bool { access.isOutsideProject(input["path"]?.string) }

    func describe(_ input: JSONValue) -> String { L("Upload %@ to Google Drive", input["path"]?.string ?? L("a file")) }

    func run(_ input: JSONValue) async -> ToolOutput {
        guard GoogleAuth.isConnected else { return GoogleAPI.notConnected }
        do {
            let url = try access.resolve(try input.requiredString("path"))
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size <= 100_000_000 else { return .error("\(url.lastPathComponent) is bigger than 100 MB.") }
            let content = try Data(contentsOf: url)
            var metadata: [String: JSONValue] = ["name": .string(input["name"]?.string ?? url.lastPathComponent)]
            if let folder = input["folder_id"]?.string { metadata["parents"] = [.string(folder)] }
            let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            let (body, contentType) = try GoogleAPI.multipart(metadata: .object(metadata), content: content, contentType: type)
            let file = try await GoogleAPI.json("https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=\(Drive.fields)", method: "POST",
                                                body: body, contentType: contentType)
            return ToolOutput(text: "Uploaded " + Drive.summary(file))
        } catch {
            return .error(error.localizedDescription)
        }
    }
}

struct DriveDownloadTool: AssistantTool {
    let access: FileAccess

    let name = "drive_download"
    var displayName: String { L("Download from Google Drive") }
    let description = """
    Saves a Google Drive file on the user's Mac. Google Docs, Sheets and Slides are converted \
    (format: pdf, docx, xlsx, pptx, csv or txt; default pdf for Docs, xlsx for Sheets, pptx for Slides).
    """
    var inputSchema: JSONValue {
        ["type": "object",
         "properties": [
             "file_id": ["type": "string"],
             "folder": ["type": "string", "description": "Folder on the Mac. Default ~/Downloads."],
             "format": ["type": "string", "enum": ["pdf", "docx", "xlsx", "pptx", "csv", "txt"]],
         ],
         "required": ["file_id"]]
    }

    func alwaysAsks(_ input: JSONValue) -> Bool { access.isOutsideProject(input["folder"]?.string ?? "~/Downloads") }

    func describe(_ input: JSONValue) -> String { L("Download a Google Drive file to %@", input["folder"]?.string ?? "~/Downloads") }

    func run(_ input: JSONValue) async -> ToolOutput {
        guard GoogleAuth.isConnected else { return GoogleAPI.notConnected }
        do {
            let id = try input.requiredString("file_id")
            let folder = try access.resolve(input["folder"]?.string ?? "~/Downloads")
            let file = try await GoogleAPI.json("https://www.googleapis.com/drive/v3/files/\(id)?fields=\(Drive.fields)")
            let mime = file["mimeType"]?.string ?? ""
            var name = (file["name"]?.string ?? id).replacingOccurrences(of: "/", with: "-")
            let data: Data
            if let export = Drive.exportType(for: mime, format: input["format"]?.string) {
                guard mime != Drive.folderType else { return .error("That's a folder; download the files in it one by one.") }
                data = try await GoogleAPI.data("https://www.googleapis.com/drive/v3/files/\(id)/export?mimeType=" + GoogleAPI.query(export.mime)).0
                name += "." + export.ext
            } else {
                data = try await GoogleAPI.data("https://www.googleapis.com/drive/v3/files/\(id)?alt=media").0
            }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var target = folder.appending(path: name)
            var number = 2
            while FileManager.default.fileExists(atPath: target.path) {
                let base = (name as NSString).deletingPathExtension, ext = (name as NSString).pathExtension
                target = folder.appending(path: "\(base) \(number)" + (ext.isEmpty ? "" : ".\(ext)"))
                number += 1
            }
            try data.write(to: target)
            return ToolOutput(text: "Saved \(target.path) (\(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))).")
        } catch {
            return .error(error.localizedDescription)
        }
    }
}
