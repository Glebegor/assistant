import AppKit
import Observation

/// Talking to the AI: press the shortcut, speak, press it again. The words go to the current
/// notch chat (same tools: Mac, Notion, ClickUp, Google…), the notch shows what's happening and
/// the answer, and the answer is read aloud with the Mac's own voice.
@Observable
@MainActor
final class VoiceAssistant {
    enum Phase: Equatable {
        case idle
        case listening
        /// Turning the recording into text.
        case transcribing
        /// The AI is working (thinking, using tools, writing).
        case working
        case answer(String)
        case failed(String)

        var isAnswer: Bool { if case .answer = self { true } else { false } }
    }

    private(set) var phase: Phase = .idle
    /// What you've said so far while listening.
    private(set) var transcript = ""
    /// 0…1, for the level bars.
    private(set) var level: Float = 0
    /// The screen the mouse was on when you started talking; the notch there shows the card.
    private(set) var displayID: CGDirectDisplayID?

    @ObservationIgnored private let chat: ChatStore
    @ObservationIgnored private let recognizer = VoiceRecognizer()
    @ObservationIgnored private var hotKey: HotKey?
    @ObservationIgnored private var escapeKey: HotKey?
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var engine: ConversationEngine?

    init(chat: ChatStore) {
        self.chat = chat
        recognizer.onPartial = { [weak self] in self?.transcript = $0 }
        recognizer.onLevel = { [weak self] in self?.level = $0 }
        registerShortcut()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.shortcutMayHaveChanged() }
        }
        NotificationCenter.default.addObserver(forName: Self.pauseShortcutNotification, object: nil, queue: .main) { [weak self] note in
            let paused = note.object as? Bool ?? false
            MainActor.assumeIsolated { self?.pauseShortcut(paused) }
        }
    }

    /// The engine answering the current voice request (for the notch's status line).
    var activeEngine: ConversationEngine? { engine }

    var isVisible: Bool { phase != .idle }

    /// The shortcut: start listening, or stop and send.
    func toggle() {
        switch phase {
        case .listening:
            Task { await finishListening() }
        case .transcribing:
            break
        case .working:
            // Pressing again while it works stops it.
            engine?.stop()
            hide()
        case .idle, .answer, .failed:
            displayID = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }?.displayID
            Task { await startListening() }
        }
    }

    func hide() {
        hideTask?.cancel()
        if phase == .listening { recognizer.cancel() }
        SpeechPlayer.shared.stop()
        setEscape(enabled: false)
        phase = .idle
        transcript = ""
        level = 0
    }

    /// While the Shortcut field in Settings records a new combination, the hotkey is off.
    func pauseShortcut(_ paused: Bool) {
        if paused { hotKey?.unregister(); hotKey = nil } else { registerShortcut() }
    }

    // MARK: Steps

    private func startListening() async {
        hideTask?.cancel()
        SpeechPlayer.shared.stop()
        do {
            try await VoiceRecognizer.requestPermissions()
            transcript = ""
            displayID = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }?.displayID
            try recognizer.start()
            phase = .listening
            setEscape(enabled: true)
            NSSound(named: "Tink")?.play()
        } catch {
            show(.failed(error.localizedDescription))
        }
    }

    private func finishListening() async {
        setEscape(enabled: false)
        phase = .transcribing
        level = 0
        NSSound(named: "Pop")?.play()
        let text = await recognizer.finish()
        guard !text.isEmpty else { return show(.failed(L("I didn't hear anything. Press the shortcut and speak."))) }
        transcript = text
        send(text)
    }

    private func send(_ text: String) {
        guard chat.hasKey else {
            return show(.failed(L("Add your %@ API key in Settings → Assistant.", chat.provider.title)))
        }
        // A busy tab keeps working; the voice request gets its own tab.
        if chat.isSending { chat.newChat() }
        let engine = chat.engine
        self.engine = engine
        phase = .working
        chat.send(Self.voicePrefix + text)
        Task { await waitForAnswer(engine) }
    }

    private func waitForAnswer(_ engine: ConversationEngine) async {
        var started = false
        while phase == .working {
            if engine.isRunning { started = true } else if started || engine.errorMessage != nil { break }
            try? await Task.sleep(for: .milliseconds(150))
        }
        guard phase == .working else { return }
        if let error = engine.errorMessage { return show(.failed(error)) }
        let answer = engine.display.reversed().lazy.compactMap { item -> String? in
            if case .assistant(_, let text) = item { return text } else { return nil }
        }.first ?? ""
        guard !answer.isEmpty else { return show(.failed(L("No answer came back."))) }
        phase = .answer(answer)
        if VoiceSettings.speakVoiceAnswers {
            SpeechPlayer.shared.speak(answer) { [weak self] in self?.hide(after: 0.3) }
        } else {
            hide(after: 0.5)
        }
    }

    private func show(_ phase: Phase) {
        setEscape(enabled: false)
        self.phase = phase
        hide(after: 6)
    }

    private func hide(after seconds: Double) {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            hide()
        }
    }

    // MARK: Shortcut

    @ObservationIgnored private var registered: Shortcut?

    private func registerShortcut() {
        hotKey?.unregister()
        let shortcut = Shortcut.voice
        registered = shortcut
        hotKey = HotKey(shortcut) { [weak self] in self?.toggle() }
    }

    private func shortcutMayHaveChanged() {
        guard hotKey != nil, Shortcut.voice != registered else { return }
        registerShortcut()
    }

    /// Esc cancels listening; it's only taken from other apps while listening.
    private func setEscape(enabled: Bool) {
        escapeKey?.unregister()
        escapeKey = enabled ? HotKey(Shortcut(keyCode: 53, modifiers: 0)) { [weak self] in self?.hide() } : nil
    }

    /// Marks spoken requests, so the AI answers briefly and in plain sentences (it's read aloud).
    nonisolated static let voicePrefix = "🎙 "

    /// Posted by the shortcut recorder in Settings (object: true = pause, false = resume).
    static let pauseShortcutNotification = Notification.Name("RightHand.PauseVoiceShortcut")
}
