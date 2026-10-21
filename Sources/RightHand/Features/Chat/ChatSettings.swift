import Foundation

/// Which AI answers in the Assistant tab.
enum ChatProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case claude, openAI, copilot

    var id: Self { self }

    var title: String {
        switch self {
        case .claude: "Claude"
        case .openAI: "ChatGPT"
        case .copilot: "Copilot"
        }
    }

    /// Talks the OpenAI Chat Completions API (ChatGPT, and Copilot through GitHub Models).
    var usesChatCompletions: Bool { self != .claude }

    var systemImage: String {
        switch self {
        case .claude: "sparkle"
        case .openAI: "bubble.left.and.bubble.right.fill"
        case .copilot: "chevron.left.forwardslash.chevron.right"
        }
    }

    /// Keychain entry that holds this provider's API key.
    var keychainAccount: String {
        switch self {
        case .claude: "anthropic-api-key"
        case .openAI: "openai-api-key"
        case .copilot: "github-models-token"
        }
    }

    var keysURL: URL {
        switch self {
        case .claude: URL(string: "https://console.anthropic.com/settings/keys")!
        case .openAI: URL(string: "https://platform.openai.com/api-keys")!
        case .copilot: URL(string: "https://github.com/settings/personal-access-tokens/new")!
        }
    }
}

/// Assistant preferences stored in UserDefaults (API keys are in the Keychain).
enum ChatSettings {
    enum Key {
        static let provider = "chat.provider"
        static let claudeModel = "chat.claudeModel"
        static let openAIModel = "chat.openAIModel"
        static let copilotModel = "chat.copilotModel"
    }

    /// GitHub Models that can use tools (Copilot), as "publisher/model".
    static let copilotModels: [(id: String, name: String)] = [
        ("openai/gpt-4.1", "GPT-4.1"),
        ("openai/gpt-4.1-mini", "GPT-4.1 mini"),
        ("openai/gpt-4o", "GPT-4o"),
        ("openai/o4-mini", "o4-mini"),
        ("mistral-ai/mistral-medium-2505", "Mistral Medium"),
    ]

    static let claudeModels: [(id: String, name: String)] = [
        ("claude-opus-5-5", "Claude Opus 5.5"),
        ("claude-sonnet-5-5", "Claude Sonnet 5.5"),
        ("claude-haiku-5-5", "Claude Haiku 5.5"),
    ]

    enum Default {
        static let provider = ChatProvider.claude.rawValue
        static let claudeModel = "claude-opus-5-5"
        static let openAIModel = "gpt-5"
        static let copilotModel = "openai/gpt-4.1"
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.provider: Default.provider,
            Key.claudeModel: Default.claudeModel,
            Key.openAIModel: Default.openAIModel,
            Key.copilotModel: Default.copilotModel,
        ])
    }

    static var provider: ChatProvider {
        get { ChatProvider(rawValue: UserDefaults.standard.string(forKey: Key.provider) ?? "") ?? .claude }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.provider) }
    }

    static func model(for provider: ChatProvider) -> String {
        let key, fallback: String
        switch provider {
        case .claude: (key, fallback) = (Key.claudeModel, Default.claudeModel)
        case .openAI: (key, fallback) = (Key.openAIModel, Default.openAIModel)
        case .copilot: (key, fallback) = (Key.copilotModel, Default.copilotModel)
        }
        let value = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespaces) ?? ""
        return value.isEmpty ? fallback : value
    }

    static func modelName(for provider: ChatProvider) -> String {
        let id = model(for: provider)
        return (claudeModels + copilotModels).first { $0.id == id }?.name ?? id
    }

    /// Fixed for the whole conversation (Claude requires earlier parts of a chat to stay unchanged).
    static let systemPrompt = """
    You are RightHand, a helpful assistant that lives in the notch of the user's Mac. \
    Answer clearly and concisely. Use Markdown for code and short lists.
    """
}

/// What you wrote about yourself in Settings → Assistant; every chat starts with it.
enum AboutMe {
    static let key = "assistant.aboutMe"

    static var text: String {
        (UserDefaults.standard.string(forKey: key) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
