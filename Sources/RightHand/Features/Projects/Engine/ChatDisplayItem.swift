import Foundation

/// What the chat window shows, read from the saved conversation (Claude or ChatGPT format).
enum ChatDisplayItem: Identifiable {
    case user(id: String, text: String)
    case assistant(id: String, text: String)
    case tool(id: String, name: String, input: String, result: String?, isError: Bool)
    /// Older messages were summarized to keep the chat within limits.
    case summarized(id: String)
    case projectUpdated(id: String)

    var id: String {
        switch self {
        case .user(let id, _), .assistant(let id, _), .tool(let id, _, _, _, _), .summarized(let id), .projectUpdated(let id): id
        }
    }

    static func items(for chat: ProjectChat) -> [ChatDisplayItem] {
        var items: [ChatDisplayItem] = []
        var toolIndex: [String: Int] = [:] // tool call id → position in `items`

        for (number, message) in chat.messages.enumerated() {
            let id = "\(number)"
            let role = message["role"]?.string
            if chat.provider.usesChatCompletions, number == chat.contextStart, number > 0 {
                items.append(.summarized(id: "\(id)-summary"))
            }

            switch (role, message["content"]) {
            case ("system", _):
                items.append(.projectUpdated(id: id))

            case ("user", .string(let text)?):
                items.append(.user(id: id, text: text))

            case ("user", .array(let blocks)?): // Claude: tool results (or text blocks)
                for (index, block) in blocks.enumerated() {
                    if block["type"]?.string == "tool_result", let callID = block["tool_use_id"]?.string, let position = toolIndex[callID],
                       case .tool(let toolID, let name, let input, _, _) = items[position] {
                        items[position] = .tool(id: toolID, name: name, input: input,
                                                result: resultText(block["content"]), isError: block["is_error"]?.bool ?? false)
                    } else if block["type"]?.string == "text", let text = block["text"]?.string {
                        items.append(.user(id: "\(id)-\(index)", text: text))
                    }
                }

            case ("assistant", .array(let blocks)?): // Claude
                var text = ""
                for (index, block) in blocks.enumerated() {
                    switch block["type"]?.string {
                    case "text":
                        text += block["text"]?.string ?? ""
                    case "compaction":
                        items.append(.summarized(id: "\(id)-\(index)"))
                    case "tool_use":
                        if !text.isEmpty { items.append(.assistant(id: "\(id)-t\(index)", text: text)); text = "" }
                        let callID = block["id"]?.string ?? "\(id)-\(index)"
                        toolIndex[callID] = items.count
                        items.append(.tool(id: callID, name: block["name"]?.string ?? "tool",
                                           input: block["input"]?.jsonString ?? "", result: nil, isError: false))
                    default:
                        break
                    }
                }
                if !text.isEmpty { items.append(.assistant(id: id, text: text)) }

            case ("assistant", let content): // ChatGPT
                if let text = content?.string, !text.isEmpty { items.append(.assistant(id: id, text: text)) }
                for (index, call) in (message["tool_calls"]?.array ?? []).enumerated() {
                    let callID = call["id"]?.string ?? "\(id)-\(index)"
                    toolIndex[callID] = items.count
                    items.append(.tool(id: callID, name: call["function"]?["name"]?.string ?? "tool",
                                       input: call["function"]?["arguments"]?.string ?? "", result: nil, isError: false))
                }

            case ("tool", let content): // ChatGPT tool result
                if let callID = message["tool_call_id"]?.string, let position = toolIndex[callID],
                   case .tool(let toolID, let name, let input, _, _) = items[position] {
                    let text = content?.string ?? ""
                    items[position] = .tool(id: toolID, name: name, input: input, result: text, isError: text.hasPrefix("Error: "))
                }

            default:
                break
            }
        }
        return items
    }

    private static func resultText(_ content: JSONValue?) -> String {
        switch content {
        case .string(let text)?: text
        case .array(let blocks)?: blocks.compactMap { $0["text"]?.string }.joined(separator: "\n")
        default: ""
        }
    }
}
