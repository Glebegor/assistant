import AppKit
import Observation

/// The conversations in the Assistant tab, one per tab. They run on the same engine as project
/// chats, so the AI can use tools on the Mac (asking you first), and they are saved to disk:
/// after quitting RightHand or restarting the Mac every tab comes back with its whole context.
/// A tab is only removed when you close it.
@Observable
@MainActor
final class ChatStore {
    /// The notch chat is a built-in project without folders; its memory is kept between chats.
    nonisolated static let projectID = UUID(uuidString: "00000000-0000-0000-0000-00000000A551")!
    private static let project = Project(id: projectID, name: "Assistant")
    private static let selectedKey = "chat.selectedTab"

    /// Open tabs, oldest first.
    private(set) var tabs: [ConversationEngine] = []
    private(set) var selectedID: UUID
    /// Providers that have an API key in the Keychain.
    private(set) var configuredProviders: Set<ChatProvider> = []
    /// Called when the AI asks for permission, so the panel can open and show the question.
    @ObservationIgnored var onApprovalNeeded: (() -> Void)?
    /// The screen to ask on (the one the mouse was on when the question came).
    private(set) var approvalDisplayID: CGDirectDisplayID?
    /// The screen the last message was sent from; its notch glows while the AI works.
    private(set) var workingDisplayID: CGDirectDisplayID?

    /// Claude or ChatGPT is thinking or using tools in one of the tabs.
    var isWorking: Bool { tabs.contains { $0.isRunning } }

    /// The chat waiting for your permission, if any — the one you're looking at first.
    var waitingForApproval: ConversationEngine? {
        engine.pendingApproval != nil ? engine : tabs.first { $0.pendingApproval != nil }
    }

    /// Bumped when Settings change, so the model name shown in the chat refreshes.
    private var settingsRevision = 0

    init() {
        ChatSettings.registerDefaults()
        let saved = ProjectStorage.loadChats(of: Self.projectID)
            .filter { !$0.messages.isEmpty }
            .sorted { $0.createdAt < $1.createdAt }
        let first = saved.isEmpty ? [Self.newChat(provider: ChatSettings.provider)] : saved
        selectedID = first.last!.id
        tabs = first.map(makeEngine)
        if let id = UserDefaults.standard.string(forKey: Self.selectedKey).flatMap(UUID.init(uuidString:)),
           tabs.contains(where: { $0.chat.id == id }) {
            selectedID = id
        }
        reloadKeys()
        NotificationCenter.default.addObserver(forName: Keychain.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadKeys() }
        }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsRevision += 1 }
        }
    }

    /// The tab you are looking at. `tabs` is never empty; the fallback is only for safety.
    var engine: ConversationEngine {
        tabs.first { $0.chat.id == selectedID } ?? tabs.first ?? fallback
    }

    @ObservationIgnored private lazy var fallback = makeEngine(Self.newChat(provider: ChatSettings.provider))

    var provider: ChatProvider {
        get { engine.chat.provider }
        set { switchProvider(to: newValue) }
    }

    var hasKey: Bool { configuredProviders.contains(provider) }
    var isSending: Bool { engine.isRunning }
    var isEmpty: Bool { engine.chat.messages.isEmpty }
    var modelName: String {
        _ = settingsRevision
        return (ChatSettings.claudeModels + ChatSettings.copilotModels).first { $0.id == engine.chat.model }?.name ?? engine.chat.model
    }

    func send(_ text: String) {
        workingDisplayID = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }?.displayID
        // A model chosen in Settings applies to new chats; an empty one picks it up now.
        if isEmpty, engine.chat.model != ChatSettings.model(for: provider) { replaceSelected(with: provider) }
        engine.send(text)
    }

    /// Stops the answer or the tool that is running; what arrived so far is kept.
    func stop() {
        engine.stop()
    }

    /// Opens a new tab (or reuses the current one if it's still empty).
    func newChat() {
        guard !isEmpty else { return }
        let engine = makeEngine(Self.newChat(provider: provider))
        tabs.append(engine)
        select(engine.chat.id)
    }

    func select(_ id: UUID) {
        selectedID = id
        UserDefaults.standard.set(id.uuidString, forKey: Self.selectedKey)
    }

    /// Closes a tab and deletes its saved conversation.
    func close(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.chat.id == id }) else { return }
        let closing = tabs[index]
        // Build the new list first and swap it in at once: the view redraws as soon as `tabs`
        // changes and must never see it empty (that crashed RightHand when closing the last tab).
        var remaining = tabs
        remaining.remove(at: index)
        if remaining.isEmpty { remaining = [makeEngine(Self.newChat(provider: closing.chat.provider))] }
        if selectedID == id { select(remaining[min(index, remaining.count - 1)].chat.id) }
        tabs = remaining
        closing.stop()
        if !closing.chat.messages.isEmpty { ProjectStorage.delete(closing.chat) }
    }

    func reloadKeys() {
        configuredProviders = Set(ChatProvider.allCases.filter { Keychain.read($0.keychainAccount) != nil })
    }

    // MARK: Private

    /// An empty tab just changes its provider; otherwise go to (or open) a tab of that provider.
    private func switchProvider(to provider: ChatProvider) {
        ChatSettings.provider = provider
        guard provider != engine.chat.provider else { return }
        if isEmpty {
            replaceSelected(with: provider)
        } else if let tab = tabs.last(where: { $0.chat.provider == provider && $0.chat.messages.isEmpty }) {
            select(tab.chat.id)
        } else {
            let engine = makeEngine(Self.newChat(provider: provider))
            tabs.append(engine)
            select(engine.chat.id)
        }
    }

    private func replaceSelected(with provider: ChatProvider) {
        guard let index = tabs.firstIndex(where: { $0.chat.id == selectedID }) else { return }
        tabs[index].stop()
        tabs[index] = makeEngine(Self.newChat(provider: provider))
        select(tabs[index].chat.id)
    }

    private func makeEngine(_ chat: ProjectChat) -> ConversationEngine {
        let engine = ConversationEngine(chat: chat, project: { Self.project }, onSave: { chat in
            // Empty tabs aren't written; they disappear on restart.
            if !chat.messages.isEmpty { ProjectStorage.save(chat) }
        })
        engine.onApprovalNeeded = { [weak self] in
            self?.approvalDisplayID = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }?.displayID
            self?.onApprovalNeeded?()
        }
        return engine
    }

    private static func newChat(provider: ChatProvider) -> ProjectChat {
        ProjectChat(projectID: projectID, provider: provider, model: ChatSettings.model(for: provider),
                    system: ProjectContext.systemPrompt(for: project, provider: provider),
                    contextFingerprint: ProjectContext.fingerprint(of: project))
    }
}
