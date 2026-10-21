import Foundation

/// Claude with tools, streaming and automatic compaction of long chats (Messages API over HTTP).
struct ClaudeClient: ModelClient {
    /// Claude 5 models (Fable, Opus/Sonnet/Haiku 5.x).
    static func isModern(_ model: String) -> Bool {
        model.contains("fable") || model.range(of: "(opus|sonnet|haiku)-5", options: .regularExpression) != nil
    }

    var endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    func turn(system: String, chat: ProjectChat, tools: [AssistantTool], apiKey: String,
              onEvent: @escaping @Sendable (TurnEvent) -> Void) async throws -> ModelTurn {
        // Effort, compaction and fallbacks exist on the Claude 5 family; older models get a plain request.
        let isModern = Self.isModern(chat.model)
        let usesFallbacks = isModern && !chat.model.contains("haiku")
        var body: [String: JSONValue] = [
            "model": .string(chat.model),
            "max_tokens": isModern ? 64000 : 32000,
            "stream": true,
            "system": .string(system),
            "messages": .array(chat.messages),
            // Cache the conversation so each turn only pays for what's new.
            "cache_control": ["type": "ephemeral"],
        ]
        if isModern {
            body["output_config"] = ["effort": "medium"]
            // When the chat gets long (150k tokens), Claude summarizes the older part itself.
            body["context_management"] = ["edits": [["type": "compact_20260112"]]]
        }
        if !tools.isEmpty {
            body["tools"] = .array(tools.map { tool in
                // Our own tools stream their input as it's generated (it's validated before running).
                // Anthropic's built-in memory tool is declared as is.
                guard !(tool is AnthropicDefinedTool), case .object(var declaration) = tool.claudeDeclaration else {
                    return tool.claudeDeclaration
                }
                declaration["eager_input_streaming"] = true
                return .object(declaration)
            })
        }
        if usesFallbacks { body["fallbacks"] = "default" } // retry on another model if a safety check declines

        var request = URLRequest(url: endpoint, timeoutInterval: 900)
        request.httpMethod = "POST"
        request.httpBody = try JSONValue.object(body).encoded()
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let betas = (isModern ? ["compact-2026-01-12"] : []) + (usesFallbacks ? ["server-side-fallback-2026-07-01"] : [])
        if !betas.isEmpty { request.setValue(betas.joined(separator: ","), forHTTPHeaderField: "anthropic-beta") }

        var blocks: [Int: [String: JSONValue]] = [:]
        var partialInputs: [Int: String] = [:]
        var stopReason: String?
        var compacted = false

        for try await data in try await ServerSentEvents.lines(for: request) {
            guard let data, let event = JSONValue.parse(data), let type = event["type"]?.string else { continue }
            switch type {
            case "content_block_start":
                guard let index = event["index"]?.int, let block = event["content_block"]?.object else { continue }
                blocks[index] = block
                switch block["type"]?.string {
                case "tool_use": onEvent(.usingTool(block["name"]?.string ?? "tool"))
                case "compaction": compacted = true; onEvent(.compacting)
                default: break
                }
            case "content_block_delta":
                guard let index = event["index"]?.int, let delta = event["delta"], var block = blocks[index] else { continue }
                switch delta["type"]?.string {
                case "text_delta":
                    let text = delta["text"]?.string ?? ""
                    block["text"] = .string((block["text"]?.string ?? "") + text)
                    onEvent(.text(text))
                case "thinking_delta":
                    block["thinking"] = .string((block["thinking"]?.string ?? "") + (delta["thinking"]?.string ?? ""))
                case "signature_delta":
                    block["signature"] = delta["signature"]
                case "input_json_delta":
                    partialInputs[index, default: ""] += delta["partial_json"]?.string ?? ""
                case "compaction_delta":
                    block["content"] = delta["content"]
                default:
                    break
                }
                blocks[index] = block
            case "message_delta":
                if let reason = event["delta"]?["stop_reason"]?.string { stopReason = reason }
            case "error":
                throw ChatError(message: event["error"]?["message"]?.string ?? "Claude returned an error.")
            default:
                break
            }
        }

        // Tool inputs arrive as JSON text; parse them strictly.
        var toolCalls: [ToolCall] = []
        for index in blocks.keys.sorted() where blocks[index]?["type"]?.string == "tool_use" {
            let raw = partialInputs[index] ?? ""
            let input = raw.isEmpty ? JSONValue.object([:]) : JSONValue.parse(raw)
            blocks[index]?["input"] = input ?? .object([:])
            toolCalls.append(ToolCall(id: blocks[index]?["id"]?.string ?? "", name: blocks[index]?["name"]?.string ?? "",
                                      input: input?.object != nil ? input : nil, rawInput: raw))
        }

        let content = Self.replayable(blocks.keys.sorted().compactMap { blocks[$0] })
        let keptIDs = Set(content.compactMap { $0["type"]?.string == "tool_use" ? $0["id"]?.string : nil })
        return ModelTurn(message: ["role": "assistant", "content": .array(content.map(JSONValue.object))],
                         stopReason: stopReason,
                         toolCalls: toolCalls.filter { keptIDs.contains($0.id) },
                         compacted: compacted)
    }

    func toolResultMessages(_ results: [(call: ToolCall, output: ToolOutput)]) -> [JSONValue] {
        guard !results.isEmpty else { return [] }
        return [["role": "user", "content": .array(results.map { result in
            ["type": "tool_result", "tool_use_id": .string(result.call.id),
             "content": .string(result.output.text), "is_error": .bool(result.output.isError)]
        })]]
    }

    func userMessages(text: String, contextUpdate: String?) -> [JSONValue] {
        var messages: [JSONValue] = [["role": "user", "content": .string(text)]]
        if let contextUpdate {
            // Claude: a system message after the user's message, so the original system prompt stays unchanged.
            messages.append(["role": "system", "content": .string(contextUpdate)])
        }
        return messages
    }

    /// After a mid-answer fallback to another model, only text may be sent back from before
    /// the last `fallback` marker.
    private static func replayable(_ blocks: [[String: JSONValue]]) -> [[String: JSONValue]] {
        guard let boundary = blocks.lastIndex(where: { $0["type"]?.string == "fallback" }) else { return blocks }
        return blocks[..<boundary].filter { $0["type"]?.string == "text" } + blocks[blocks.index(after: boundary)...]
    }
}
