import Foundation

/// Talks to ChatGPT (OpenAI Chat Completions API, streaming).
enum OpenAIService {
    private static let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    /// Request body for the conversation so far. `history` already ends with the new question.
    @MainActor
    static func body(history: [ChatMessage], model: String) throws -> Data {
        let messages: [[String: Any]] = [["role": "system", "content": ChatSettings.systemPrompt]]
            + history.map { ["role": $0.role == .user ? "user" : "assistant", "content": $0.text] }
        let body: [String: Any] = ["model": model, "stream": true, "messages": messages]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    static func stream(body: Data, apiKey: String) -> AsyncThrowingStream<ChatEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: endpoint, timeoutInterval: 600)
                    request.httpMethod = "POST"
                    request.httpBody = body
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

                    var declined = false
                    for try await data in try await ServerSentEvents.lines(for: request) {
                        guard let data else { continue }
                        if data == "[DONE]" { break }
                        guard let event = ServerSentEvents.json(data),
                              let choice = (event["choices"] as? [[String: Any]])?.first
                        else { continue }
                        if let text = (choice["delta"] as? [String: Any])?["content"] as? String, !text.isEmpty {
                            continuation.yield(.text(text))
                        }
                        if choice["finish_reason"] as? String == "content_filter" { declined = true }
                    }
                    continuation.yield(.finished(claudeContent: nil, declined: declined))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
