import Foundation

/// Talks to the Claude API (Anthropic Messages API over HTTP; there is no official Swift SDK).
enum ClaudeService {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    /// Request body for the conversation so far. `history` already ends with the new question.
    @MainActor
    static func body(history: [ChatMessage], model: String) throws -> Data {
        let messages: [[String: Any]] = history.map { message in
            if message.role == .user {
                return ["role": "user", "content": message.text]
            }
            // Claude's own replies go back exactly as they came; other answers as plain text.
            if message.provider == .claude, let raw = message.claudeContent,
               let blocks = try? JSONSerialization.jsonObject(with: raw) {
                return ["role": "assistant", "content": blocks]
            }
            return ["role": "assistant", "content": message.text]
        }
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 64000,
            "stream": true,
            "system": ChatSettings.systemPrompt,
            "messages": messages,
            "output_config": ["effort": "medium"],
            // Cache the conversation so each new message only pays for what's new.
            "cache_control": ["type": "ephemeral"],
        ]
        if usesFallbacks(model) {
            // If a safety check declines, the API retries on Anthropic's recommended model.
            body["fallbacks"] = "default"
        }
        // Sorted keys keep earlier turns byte-identical between requests.
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    /// Server-side fallback exists for Opus and Sonnet, not for Haiku.
    private static func usesFallbacks(_ model: String) -> Bool {
        !model.contains("haiku")
    }

    static func stream(body: Data, model: String, apiKey: String,
                       endpoint: URL = endpoint) -> AsyncThrowingStream<ChatEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: endpoint, timeoutInterval: 600)
                    request.httpMethod = "POST"
                    request.httpBody = body
                    request.setValue("application/json", forHTTPHeaderField: "content-type")
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    if usesFallbacks(model) {
                        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
                    }

                    // Content blocks by index, rebuilt from the stream so they can be sent back.
                    var blocks: [Int: [String: Any]] = [:]
                    var stopReason: String?

                    for try await data in try await ServerSentEvents.lines(for: request) {
                        guard let data, let event = ServerSentEvents.json(data),
                              let type = event["type"] as? String else { continue }
                        switch type {
                        case "content_block_start":
                            if let index = event["index"] as? Int, let block = event["content_block"] as? [String: Any] {
                                blocks[index] = block
                            }
                        case "content_block_delta":
                            guard let index = event["index"] as? Int, let delta = event["delta"] as? [String: Any],
                                  var block = blocks[index] else { continue }
                            switch delta["type"] as? String {
                            case "text_delta":
                                let text = delta["text"] as? String ?? ""
                                block["text"] = (block["text"] as? String ?? "") + text
                                continuation.yield(.text(text))
                            case "thinking_delta":
                                block["thinking"] = (block["thinking"] as? String ?? "") + (delta["thinking"] as? String ?? "")
                            case "signature_delta":
                                block["signature"] = delta["signature"]
                            default:
                                break
                            }
                            blocks[index] = block
                        case "message_delta":
                            if let reason = (event["delta"] as? [String: Any])?["stop_reason"] as? String {
                                stopReason = reason
                            }
                        case "error":
                            let message = (event["error"] as? [String: Any])?["message"] as? String
                            throw ChatError(message: message ?? "Claude returned an error.")
                        default:
                            break
                        }
                    }

                    let content = replayable(blocks.sorted { $0.key < $1.key }.map(\.value))
                    let raw = try JSONSerialization.data(withJSONObject: content, options: [.sortedKeys])
                    continuation.yield(.finished(claudeContent: raw, declined: stopReason == "refusal"))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// When a declined answer was continued by a fallback model, only the text before the
    /// last `fallback` marker may be sent back; everything after it is kept as is.
    static func replayable(_ blocks: [[String: Any]]) -> [[String: Any]] {
        guard let boundary = blocks.lastIndex(where: { $0["type"] as? String == "fallback" }) else { return blocks }
        let before = blocks[..<boundary].filter { $0["type"] as? String == "text" }
        return before + blocks[blocks.index(after: boundary)...]
    }
}
