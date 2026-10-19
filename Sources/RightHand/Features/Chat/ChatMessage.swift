import Foundation

struct ChatMessage: Identifiable {
    enum Role { case user, assistant }

    let id = UUID()
    let role: Role
    var text: String
    /// For assistant messages: who answered.
    var provider: ChatProvider?
    var modelName: String?
    var isStreaming = false
    /// Claude's reply exactly as received (JSON array of content blocks), sent back unchanged
    /// on the next turn. Claude checks that earlier turns of a chat were not edited.
    var claudeContent: Data?
    /// The AI declined to answer (safety check).
    var isDeclined = false
    var errorMessage: String?

    /// Whether this answer (and the question before it) is part of what the AI remembers.
    var belongsInHistory: Bool {
        role == .user || (!isDeclined && errorMessage == nil && !isStreaming && (!text.isEmpty || claudeContent != nil))
    }
}

/// Something that happened while an answer streamed in.
enum ChatEvent: Sendable {
    case text(String)
    case finished(claudeContent: Data?, declined: Bool)
}

struct ChatError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Reads Server-Sent Events ("data: {...}" lines) from a streaming HTTP response.
enum ServerSentEvents {
    static func lines(for request: URLRequest) async throws -> AsyncThrowingMapSequence<AsyncLineSequence<URLSession.AsyncBytes>, String?> {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            var body = Data()
            for try await byte in bytes { body.append(byte) }
            throw ChatError(message: errorMessage(status: http.statusCode, body: body))
        }
        return bytes.lines.map { line in
            line.hasPrefix("data:") ? String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces) : nil
        }
    }

    static func json(_ string: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(string.utf8))) as? [String: Any]
    }

    /// Both APIs return errors as {"error": {"message": "..."}}.
    private static func errorMessage(status: Int, body: Data) -> String {
        let message = ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any])
            .flatMap { $0["error"] as? [String: Any] }
            .flatMap { $0["message"] as? String }
        switch status {
        case 401: return "The API key was rejected. Check it in Settings → Assistant."
        case 429: return message ?? "Too many requests or no credit left. Try again later."
        default: return message.map { "Error \(status): \($0)" } ?? "Error \(status)."
        }
    }
}
