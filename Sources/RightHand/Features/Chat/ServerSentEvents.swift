import Foundation

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
        case 401: return L("The API key was rejected. Check it in Settings → Assistant.")
        case 429: return message ?? L("Too many requests or no credit left. Try again later.")
        default: return message.map { L("Error %lld: %@", status, $0) } ?? L("Error %lld.", status)
        }
    }
}
