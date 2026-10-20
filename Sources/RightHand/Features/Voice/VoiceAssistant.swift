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
    @ObservationIgnored private let wake = WakeWordListener()
    /// Started by "Hey Ellipse": the request is sent by itself when you stop talking.
    @ObservationIgnored private var sendsOnSilence = false
    @ObservationIgnored private var lastHeard = Date()
    @ObservationIgnored private var silenceWatch: Task<Void, Never>?

    init(chat: ChatStore) {
        self.chat = chat
        recognizer.onPartial = { [weak self] text in
            guard let self else { return }
            if text != self.transcript { self.lastHeard = Date() }
            self.transcript = text
        }
        wake.onWake = { [weak self] in self?.wakeUp() }
        recognizer.onLevel = { [weak self] in self?.level = $0 }
        registerShortcut()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.shortcutMayHaveChanged()
                self?.updateWakeWord()
            }
        }
        NotificationCenter.default.addObserver(forName: Self.pauseShortcutNotification, object: nil, queue: .main) { [weak self] note in
            let paused = note.object as? Bool ?? false
            MainActor.assumeIsolated { self?.pauseShortcut(paused) }
        }
        updateWakeWord()
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
            sendsOnSilence = false
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
        silenceWatch?.cancel()
        updateWakeWord()
    }

    /// While the Shortcut field in Settings records a new combination, the hotkey is off.
    func pauseShortcut(_ paused: Bool) {
        if paused { hotKey?.unregister(); hotKey = nil } else { registerShortcut() }
    }

    // MARK: Steps

    private func startListening() async {
        hideTask?.cancel()
        SpeechPlayer.shared.stop()
        wake.stop() // one listener at a time
        do {
            try await VoiceRecognizer.requestPermissions()
            transcript = ""
            displayID = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }?.displayID
            try recognizer.start()
            phase = .listening
            setEscape(enabled: true)
            NSSound(named: "Tink")?.play()
            if sendsOnSilence { watchForSilence() }
        } catch {
            show(.failed(error.localizedDescription))
        }
    }

    private func finishListening() async {
        setEscape(enabled: false)
        phase = .transcribing
        level = 0
        NSSound(named: "Pop")?.play()
        silenceWatch?.cancel()
        let text = Self.withoutWakeWord(await recognizer.finish())
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

    // MARK: Wake word

    /// "Hey Ellipse" was heard: listen for the request and send it when you pause.
    private func wakeUp() {
        guard phase == .idle else { return }
        displayID = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }?.displayID
        sendsOnSilence = true
        Task { await startListening() }
    }

    /// Sends after 1.5 seconds without new words; gives up after 8 seconds of silence.
    private func watchForSilence() {
        silenceWatch?.cancel()
        let started = Date()
        lastHeard = Date()
        silenceWatch = Task {
            while !Task.isCancelled, phase == .listening {
                try? await Task.sleep(for: .milliseconds(200))
                let quiet = Date().timeIntervalSince(lastHeard)
                if !transcript.isEmpty, quiet > 1.5 { await finishListening(); return }
                if transcript.isEmpty, Date().timeIntervalSince(started) > 8 { hide(); return }
            }
        }
    }

    /// Listens for the wake word whenever nothing else uses the microphone.
    private func updateWakeWord() {
        if WakeWordListener.isEnabled && phase == .idle {
            // A moment later, so the microphone is free after recording or speaking.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                guard let self, self.phase == .idle else { return }
                self.wake.start()
            }
        } else if !WakeWordListener.isEnabled {
            wake.stop()
        }
    }

    /// "Эллипс, сделай…" → "сделай…".
    nonisolated static func withoutWakeWord(_ text: String) -> String {
        let pattern = "^\\s*((эй|хей|ей|hey|hi)[\\s,]+)?(эллипс|элипс|еллипс|елипс|еліпс|ellipse|ellipsis|elips|eclipse)[\\s,.!?:]*"
        return text.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// The voice assistant's name.
    nonisolated static let name = "Ellipse"

    /// Who Ellipse is and how it works; part of every chat's instructions.
    nonisolated static let ellipsePrompt = """
    # Ellipse, the voice assistant

    Messages that start with \(voicePrefix.trimmingCharacters(in: .whitespaces)) were spoken. For those you are Ellipse, \
    RightHand's voice assistant: the user pressed a shortcut, spoke, and hears your answer read aloud by the Mac \
    while they keep working in other windows. They can't see a long answer, so act and report briefly.

    What Ellipse does:
    - Answers quick questions and explains things in a sentence or two.
    - Works on the Mac with your tools: opens apps, links and files; finds, reads, creates, edits, moves and \
      deletes files; runs Terminal commands.
    - Handles tasks in Notion and ClickUp: what's due or overdue, what to do next, marking tasks done, changing \
      status, priority or due date, adding notes to a task.
    - Reads Gmail and Google Drive when they are connected: finds and summarizes emails and documents, \
      creates Google Docs, uploads and downloads files.
    - Plans the day: combines open tasks, deadlines and priorities into what to do first.
    - Remembers things the user asks to keep (memory tool) and uses what they wrote about themselves.

    How Ellipse speaks:
    - In the language the user spoke, one to three short plain sentences. No Markdown, lists, tables, links, \
      emoji, code or file paths unless asked; say numbers, dates and times the way people say them.
    - Do the task first with the tools, then say what was done ("Done, I marked the report as finished."). \
      Don't describe how the user could do it themselves.
    - Many results: give the count and the two or three most important ones, and offer the rest.
    - The user approves risky actions on screen; don't ask for permission in words. If they decline, say so \
      briefly and don't retry.
    - If the request is unclear or the speech was misheard, ask one short question instead of guessing.
    - Never read secrets, API keys or whole long texts aloud.
    """

    /// Posted by the shortcut recorder in Settings (object: true = pause, false = resume).
    static let pauseShortcutNotification = Notification.Name("RightHand.PauseVoiceShortcut")
}
