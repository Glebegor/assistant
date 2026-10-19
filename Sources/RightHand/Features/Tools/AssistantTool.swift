import Foundation

/// Something the AI can do on the Mac (read a file, open an app, …). Every tool works with
/// both Claude and ChatGPT; new integrations (Notion, Google Drive, …) are added as more tools.
protocol AssistantTool: Sendable {
    var name: String { get }
    /// Shown to the AI: what the tool does and when to use it.
    var description: String { get }
    /// JSON Schema of the input.
    var inputSchema: JSONValue { get }
    /// Shown to you in Settings and when asking for permission.
    var displayName: String { get }

    /// What this call will do, in plain words ("Read README.md").
    func describe(_ input: JSONValue) -> String
    func run(_ input: JSONValue) async -> ToolOutput
}

extension AssistantTool {
    /// How the tool is declared to Claude. Anthropic's own tools (memory) override this.
    var claudeDeclaration: JSONValue {
        ["name": .string(name), "description": .string(description), "input_schema": inputSchema]
    }

    /// How the tool is declared to ChatGPT.
    var openAIDeclaration: JSONValue {
        ["type": "function",
         "function": ["name": .string(name), "description": .string(description), "parameters": inputSchema]]
    }
}

/// Anthropic's built-in memory tool is declared by type, not by schema.
protocol AnthropicDefinedTool: AssistantTool {
    var anthropicType: String { get }
}

struct ToolOutput: Sendable {
    var text: String
    var isError = false

    static func error(_ message: String) -> ToolOutput { ToolOutput(text: message, isError: true) }
}

struct ToolError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Which tools may run without asking. By default every action asks first.
enum ToolPermissions {
    static let key = "tools.alwaysAllowed"

    static var alwaysAllowed: Set<String> {
        Set((UserDefaults.standard.string(forKey: key) ?? "").split(separator: ",").map(String.init))
    }

    static func isAlwaysAllowed(_ tool: String) -> Bool { alwaysAllowed.contains(tool) }

    static func setAlwaysAllowed(_ tool: String, _ allowed: Bool) {
        var tools = alwaysAllowed
        if allowed { tools.insert(tool) } else { tools.remove(tool) }
        UserDefaults.standard.set(tools.sorted().joined(separator: ","), forKey: key)
    }
}

extension JSONValue {
    /// Reads a required string input field.
    func requiredString(_ key: String) throws -> String {
        guard let value = self[key]?.string, !value.isEmpty else { throw ToolError("Missing `\(key)`.") }
        return value
    }
}
