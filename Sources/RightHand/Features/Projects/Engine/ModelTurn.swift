import Foundation

/// One request to the AI and its streamed reply.
struct ModelTurn: Sendable {
    /// The assistant message to append to the conversation, in the provider's format.
    var message: JSONValue
    /// "end_turn", "tool_use", "max_tokens", "refusal", … (OpenAI's finish reasons are mapped to these).
    var stopReason: String?
    var toolCalls: [ToolCall]
    /// Claude summarized older messages in this reply (compaction).
    var compacted = false
}

struct ToolCall: Sendable, Identifiable {
    let id: String
    let name: String
    /// nil when the AI sent arguments that aren't valid JSON.
    let input: JSONValue?
    let rawInput: String
}

/// Events while a reply streams in.
enum TurnEvent: Sendable {
    case text(String)
    case usingTool(String)
    case compacting
}

/// Streams one reply. Implemented for Claude and ChatGPT.
protocol ModelClient: Sendable {
    func turn(system: String, chat: ProjectChat, tools: [AssistantTool], apiKey: String,
              onEvent: @escaping @Sendable (TurnEvent) -> Void) async throws -> ModelTurn

    /// Messages that carry the results of `calls` back to the AI.
    func toolResultMessages(_ results: [(call: ToolCall, output: ToolOutput)]) -> [JSONValue]

    /// A message with the user's text (and, when the project changed, a context update).
    func userMessages(text: String, contextUpdate: String?) -> [JSONValue]
}
