import Foundation
import Observation

/// The conversation in the Assistant tab. It runs on the same engine as project chats, so the
/// AI can use tools on the Mac (files, Terminal commands, opening apps), asking you first.
@Observable
@MainActor
final class ChatStore {
    /// The notch chat is a built-in project without folders; its memory is kept between chats.
    nonisolated static let projectID = UUID(uuidString: "00000000-0000-0000-0000-00000000A551")!
    private static let project = Project(id: projectID, name: "Assistant")

    private(set) var engine: ConversationEngine
    /// Providers that have an API key in the Keychain.
    private(set) var configuredProviders: Set<ChatProvider> = []
    /// Called when the AI asks for permission, so the panel can open and show the question.
    @ObservationIgnored var onApprovalNeeded: (() -> Void)?

    var provider: ChatProvider {
        didSet {
            ChatSettings.provider = provider
            if engine.chat.provider != provider { newChat() }
        }
    }

    /// Bumped when Settings change, so the model name shown in the chat refreshes.
    private var settingsRevision = 0

    init() {
        ChatSettings.registerDefaults()
        let provider = ChatSettings.provider
        self.provider = provider
        engine = Self.makeEngine(provider: provider)
        reloadKeys()
        engine.onApprovalNeeded = { [weak self] in self?.onApprovalNeeded?() }
        NotificationCenter.default.addObserver(forName: Keychain.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadKeys() }
        }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsRevision += 1 }
        }
    }

    var hasKey: Bool { configuredProviders.contains(provider) }
    var isSending: Bool { engine.isRunning }
    var isEmpty: Bool { engine.chat.messages.isEmpty }
    var modelName: String {
        _ = settingsRevision
        return ChatSettings.modelName(for: provider)
    }

    func send(_ text: String) {
        // A model chosen in Settings applies from the next new chat; an empty chat picks it up now.
        if isEmpty, engine.chat.model != ChatSettings.model(for: provider) { newChat() }
        engine.send(text)
    }

    /// Stops the answer or the tool that is running; what arrived so far is kept.
    func stop() {
        engine.stop()
    }

    func newChat() {
        engine.stop()
        engine = Self.makeEngine(provider: provider)
        engine.onApprovalNeeded = { [weak self] in self?.onApprovalNeeded?() }
    }

    func reloadKeys() {
        configuredProviders = Set(ChatProvider.allCases.filter { Keychain.read($0.keychainAccount) != nil })
    }

    private static func makeEngine(provider: ChatProvider) -> ConversationEngine {
        let chat = ProjectChat(projectID: projectID, provider: provider, model: ChatSettings.model(for: provider),
                               system: ProjectContext.systemPrompt(for: project, provider: provider),
                               contextFingerprint: ProjectContext.fingerprint(of: project))
        // The notch chat lives only until you start a new one, so nothing is saved.
        return ConversationEngine(chat: chat, project: { project }, onSave: { _ in })
    }
}
