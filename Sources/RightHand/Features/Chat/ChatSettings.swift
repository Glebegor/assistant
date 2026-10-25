import Foundation

/// Which AI answers in the Assistant tab.
enum ChatProvider: String, CaseIterable, Identifiable, Codable, Sendable {
    case claude, openAI, copilot, gemini

    var id: Self { self }

    var title: String {
        switch self {
        case .claude: "Claude"
        case .openAI: "ChatGPT"
        case .copilot: "Copilot"
        case .gemini: "Gemini"
        }
    }

    /// Talks the OpenAI Chat Completions API (ChatGPT, and Copilot through GitHub Models).
    var usesChatCompletions: Bool { self != .claude }

    var systemImage: String {
        switch self {
        case .claude: "sparkle"
        case .openAI: "bubble.left.and.bubble.right.fill"
        case .copilot: "chevron.left.forwardslash.chevron.right"
        case .gemini: "diamond.fill"
        }
    }

    /// Keychain entry that holds this provider's API key. Copilot: the subscription sign-in
    /// when you signed in, otherwise the GitHub Models token.
    var keychainAccount: String {
        switch self {
        case .claude: "anthropic-api-key"
        case .openAI: "openai-api-key"
        case .copilot: CopilotAuth.isSignedIn ? CopilotAuth.oauthAccount : Self.gitHubModelsAccount
        case .gemini: "gemini-api-key"
        }
    }

    static let gitHubModelsAccount = "github-models-token"

    var keysURL: URL {
        switch self {
        case .claude: URL(string: "https://console.anthropic.com/settings/keys")!
        case .openAI: URL(string: "https://platform.openai.com/api-keys")!
        case .copilot: URL(string: "https://github.com/settings/personal-access-tokens/new")!
        case .gemini: URL(string: "https://aistudio.google.com/apikey")!
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
        static let geminiModel = "chat.geminiModel"
    }

    /// GitHub Models that can use tools (Copilot), as "publisher/model".
    /// Used until the list is loaded from GitHub.
    static let copilotModels: [(id: String, name: String)] = [
        ("openai/gpt-5", "GPT-5"),
        ("openai/gpt-5-mini", "GPT-5 mini"),
        ("openai/gpt-5-nano", "GPT-5 nano"),
        ("openai/gpt-4.1", "GPT-4.1"),
        ("openai/gpt-4.1-mini", "GPT-4.1 mini"),
        ("openai/gpt-4o", "GPT-4o"),
        ("openai/o3", "o3"),
        ("openai/o4-mini", "o4-mini"),
        ("xai/grok-3", "Grok 3"),
        ("xai/grok-3-mini", "Grok 3 mini"),
        ("meta/llama-4-maverick-17b-128e-instruct-fp8", "Llama 4 Maverick"),
        ("deepseek/deepseek-v3-0324", "DeepSeek V3"),
        ("mistral-ai/mistral-medium-2505", "Mistral Medium"),
        ("mistral-ai/codestral-2501", "Codestral"),
    ]

    static let claudeModels: [(id: String, name: String)] = [
        ("claude-fable-5-1", "Claude Fable 5.1"),
        ("claude-opus-5-5", "Claude Opus 5.5"),
        ("claude-sonnet-5-5", "Claude Sonnet 5.5"),
        ("claude-haiku-5-5", "Claude Haiku 5.5"),
        ("claude-opus-5", "Claude Opus 5"),
        ("claude-sonnet-5", "Claude Sonnet 5"),
        ("claude-opus-4-8", "Claude Opus 4.8"),
        ("claude-sonnet-4-6", "Claude Sonnet 4.6"),
    ]

    enum Default {
        static let provider = ChatProvider.claude.rawValue
        static let claudeModel = "claude-opus-5-5"
        static let openAIModel = "gpt-5"
        static let copilotModel = "openai/gpt-4.1"
        static let geminiModel = "gemini-2.5-pro"
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.provider: Default.provider,
            Key.claudeModel: Default.claudeModel,
            Key.openAIModel: Default.openAIModel,
            Key.copilotModel: Default.copilotModel,
            Key.geminiModel: Default.geminiModel,
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
        case .gemini: (key, fallback) = (Key.geminiModel, Default.geminiModel)
        }
        let value = UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespaces) ?? ""
        return provider == .copilot ? copilotModel(value.isEmpty ? fallback : value) : (value.isEmpty ? fallback : value)
    }

    /// GitHub Models names models "openai/gpt-4.1", the Copilot subscription just "gpt-4.1".
    static func copilotModel(_ id: String) -> String {
        CopilotAuth.isSignedIn ? String(id.split(separator: "/").last ?? Substring(id)) : id
    }

    @MainActor
    static func modelName(for provider: ChatProvider) -> String {
        ModelCatalog.shared.name(of: model(for: provider), provider: provider)
    }

    /// The model setting of a provider (Settings and the notch's model menu write it).
    static func modelKey(for provider: ChatProvider) -> String {
        switch provider {
        case .claude: Key.claudeModel
        case .openAI: Key.openAIModel
        case .copilot: Key.copilotModel
        case .gemini: Key.geminiModel
        }
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
