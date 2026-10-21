import Foundation

/// ChatGPT with tools (function calling) and streaming (Chat Completions API). GitHub Copilot
/// (GitHub Models) speaks the same API at another address.
/// Long chats are shortened on our side: older messages are replaced by a summary.
struct OpenAIClient: ModelClient {
    static let openAIEndpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    static let gitHubModelsEndpoint = URL(string: "https://models.github.ai/inference/chat/completions")!
    static let geminiEndpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")!
    var endpoint = openAIEndpoint

    init(endpoint: URL = openAIEndpoint) { self.endpoint = endpoint }

    /// The client for a provider that speaks the Chat Completions API.
    init(provider: ChatProvider) {
        switch provider {
        case .copilot: self.init(endpoint: Self.gitHubModelsEndpoint)
        case .gemini: self.init(endpoint: Self.geminiEndpoint)
        default: self.init(endpoint: Self.openAIEndpoint)
        }
    }
    /// Roughly 80k tokens; above this the older part of the chat is summarized.
    static let summarizeAboveCharacters = 320_000

    func turn(system: String, chat: ProjectChat, tools: [AssistantTool], apiKey: String,
              onEvent: @escaping @Sendable (TurnEvent) -> Void) async throws -> ModelTurn {
        var body: [String: JSONValue] = [
            "model": .string(chat.model),
            "stream": true,
            "messages": .array(Self.context(system: system, chat: chat)),
        ]
        if !tools.isEmpty { body["tools"] = .array(tools.map(\.openAIDeclaration)) }

        var text = ""
        var calls: [Int: (id: String, name: String, arguments: String)] = [:]
        var finishReason: String?

        for try await data in try await ServerSentEvents.lines(for: request(body: body, apiKey: apiKey)) {
            guard let data else { continue }
            if data == "[DONE]" { break }
            guard let choice = JSONValue.parse(data)?["choices"]?.array?.first else { continue }
            let delta = choice["delta"]
            if let piece = delta?["content"]?.string, !piece.isEmpty {
                text += piece
                onEvent(.text(piece))
            }
            for call in delta?["tool_calls"]?.array ?? [] {
                let index = call["index"]?.int ?? 0
                var current = calls[index] ?? (id: "", name: "", arguments: "")
                if let id = call["id"]?.string { current.id = id }
                if let name = call["function"]?["name"]?.string {
                    current.name += name
                    onEvent(.usingTool(current.name))
                }
                current.arguments += call["function"]?["arguments"]?.string ?? ""
                calls[index] = current
            }
            if let reason = choice["finish_reason"]?.string { finishReason = reason }
        }

        let ordered = calls.keys.sorted().compactMap { calls[$0] }
        var message: [String: JSONValue] = ["role": "assistant", "content": text.isEmpty ? .null : .string(text)]
        if !ordered.isEmpty {
            message["tool_calls"] = .array(ordered.map { call in
                ["id": .string(call.id), "type": "function",
                 "function": ["name": .string(call.name), "arguments": .string(call.arguments)]]
            })
        }
        let stopReason: String? = switch finishReason {
        case "tool_calls": "tool_use"
        case "length": "max_tokens"
        case "content_filter": "refusal"
        case "stop": "end_turn"
        default: finishReason
        }
        return ModelTurn(
            message: .object(message),
            stopReason: stopReason,
            toolCalls: ordered.map { call in
                let input = call.arguments.isEmpty ? JSONValue.object([:]) : JSONValue.parse(call.arguments)
                return ToolCall(id: call.id, name: call.name, input: input?.object != nil ? input : nil, rawInput: call.arguments)
            }
        )
    }

    func toolResultMessages(_ results: [(call: ToolCall, output: ToolOutput)]) -> [JSONValue] {
        results.map { result in
            ["role": "tool", "tool_call_id": .string(result.call.id),
             "content": .string(result.output.isError ? "Error: \(result.output.text)" : result.output.text)]
        }
    }

    func userMessages(text: String, contextUpdate: String?) -> [JSONValue] {
        (contextUpdate.map { [["role": "system", "content": .string($0)]] } ?? [])
            + [["role": "user", "content": .string(text)]]
    }

    // MARK: Long chats

    /// When the chat is too long, returns where the AI's context should start and a summary of
    /// everything before it. The window keeps showing the whole chat.
    func shortened(_ chat: ProjectChat, system: String, apiKey: String) async throws -> (start: Int, summary: String)? {
        let visible = chat.messages[chat.contextStart...]
        let size = visible.reduce(0) { $0 + $1.jsonString.count }
        guard size > Self.summarizeAboveCharacters else { return nil }

        // Keep roughly the last quarter word for word, starting at a user message.
        var keepFrom = chat.messages.count
        var kept = 0
        for index in chat.messages.indices.reversed() where index > chat.contextStart {
            kept += chat.messages[index].jsonString.count
            if chat.messages[index]["role"]?.string == "user" { keepFrom = index }
            if kept > size / 4 { break }
        }
        guard keepFrom > chat.contextStart, keepFrom < chat.messages.count else { return nil }

        var older = chat
        older.messages = Array(chat.messages[..<keepFrom])
        let request: [String: JSONValue] = [
            "model": .string(chat.model),
            "messages": .array(Self.context(system: system, chat: older) + [[
                "role": "user",
                "content": """
                Summarize our conversation so far so we can continue it with only your summary. Keep every decision, \
                fact, file name, open question and the current state of the work. Write it as notes, not as a reply.
                """,
            ]]),
        ]
        let (data, response) = try await URLSession.shared.data(for: self.request(body: request, apiKey: apiKey))
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let summary = JSONValue.parse(data)?["choices"]?.array?.first?["message"]?["content"]?.string
        else { return nil }
        let previous = chat.summary.map { "\($0)\n\n" } ?? ""
        return (keepFrom, previous + summary)
    }

    // MARK: Private

    private static func context(system: String, chat: ProjectChat) -> [JSONValue] {
        var messages: [JSONValue] = [["role": "system", "content": .string(system)]]
        if let summary = chat.summary {
            messages.append(["role": "system", "content": .string("Summary of the earlier part of this conversation:\n\n\(summary)")])
        }
        return messages + chat.messages[min(chat.contextStart, chat.messages.count)...]
    }

    private func request(body: [String: JSONValue], apiKey: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 900)
        request.httpMethod = "POST"
        request.httpBody = try JSONValue.object(body).encoded()
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }
}
