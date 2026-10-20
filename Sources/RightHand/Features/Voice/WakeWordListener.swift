import AVFoundation
import Speech

/// Listens for "Hey Ellipse" while the assistant is idle. Recognition runs on the Mac only (Russian or
/// English, whichever is switched on and supported on-device); nothing is sent anywhere.
@MainActor
final class WakeWordListener {
    var onWake: (() -> Void)?
    private(set) var isRunning = false

    private let audio = AVAudioEngine()
    /// The audio thread hands every buffer straight to the current request.
    private final class RequestBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: SFSpeechAudioBufferRecognitionRequest?
        var request: SFSpeechAudioBufferRecognitionRequest? {
            get { lock.withLock { value } }
            set { lock.withLock { value = newValue } }
        }
    }
    private let box = RequestBox()
    private var request: SFSpeechAudioBufferRecognitionRequest? {
        get { box.request }
        set { box.request = newValue }
    }
    private var task: SFSpeechRecognitionTask?
    private var restartTimer: Timer?

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: VoiceSettings.Key.wakeWord) as? Bool ?? true }

    /// The on-device recognizer to listen with: Russian first ("Эй, Эллипс"), then English ("Hey Ellipse").
    static var recognizer: SFSpeechRecognizer? {
        let order = ["ru": "ru-RU", "en": "en-US", "uk": "uk-UA", "cs": "cs-CZ"]
        for language in ["ru", "en", "uk", "cs"] where VoiceRecognizer.languages.contains(language) {
            if let recognizer = SFSpeechRecognizer(locale: Locale(identifier: order[language]!)), recognizer.supportsOnDeviceRecognition {
                return recognizer
            }
        }
        // None of the chosen languages works offline: use English on the Mac rather than stream audio all day.
        return SFSpeechRecognizer(locale: Locale(identifier: "en-US")).flatMap { $0.supportsOnDeviceRecognition ? $0 : nil }
    }

    /// The name as recognizers write it ("эллипс", "элипс", "еліпс", "ellipse", "ellipsis", "eclipse", …).
    nonisolated static func containsWakeWord(_ text: String) -> Bool {
        let lower = text.lowercased()
        return ["эллипс", "элипс", "еллипс", "елипс", "еліпс", "ellipse", "ellipsis", "elips", "eclipse", "a lips"]
            .contains { lower.contains($0) }
    }

    func start() {
        guard Self.isEnabled, !isRunning,
              SFSpeechRecognizer.authorizationStatus() == .authorized,
              AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
              let recognizer = Self.recognizer, recognizer.isAvailable
        else { return }
        let input = audio.inputNode
        input.removeTap(onBus: 0)
        let box = self.box
        input.installTap(onBus: 0, bufferSize: 2048, format: input.outputFormat(forBus: 0)) { buffer, _ in
            box.request?.append(buffer)
        }
        audio.prepare()
        do { try audio.start() } catch { return }
        isRunning = true
        beginRecognition(with: recognizer)
        // Long recognitions slow down and eventually stop: start a fresh one every minute.
        restartTimer = Timer.scheduledTimer(withTimeInterval: 55, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRunning, let recognizer = Self.recognizer else { return }
                self.beginRecognition(with: recognizer)
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        restartTimer?.invalidate()
        restartTimer = nil
        task?.cancel()
        task = nil
        request = nil
        if audio.isRunning { audio.stop() }
        audio.inputNode.removeTap(onBus: 0)
    }

    private func beginRecognition(with recognizer: SFSpeechRecognizer) {
        task?.cancel()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true
        request.taskHint = .search
        self.request = request
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString ?? ""
            let ended = error != nil || (result?.isFinal ?? false)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.isRunning, self.request === request else { return }
                    // Only the last few words, so an old mention doesn't count again.
                    if Self.containsWakeWord(String(text.suffix(30))) {
                        self.stop()
                        self.onWake?()
                    } else if ended {
                        // Silence ends a recognition; start listening again a moment later.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            guard self.isRunning, self.request === request, let recognizer = Self.recognizer else { return }
                            self.beginRecognition(with: recognizer)
                        }
                    }
                }
            }
        }
    }
}
