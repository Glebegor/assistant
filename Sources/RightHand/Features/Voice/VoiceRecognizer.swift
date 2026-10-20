import AVFoundation
import Speech

/// Records from the microphone and turns speech into text with Apple's recognizer, on the Mac
/// itself when the language supports it. Partial text and the voice level arrive while you speak.
@MainActor
final class VoiceRecognizer {
    enum Failure: LocalizedError {
        case microphoneDenied, recognitionDenied, unavailable(String)

        var errorDescription: String? {
            switch self {
            case .microphoneDenied: L("Allow the microphone for RightHand in System Settings → Privacy & Security → Microphone.")
            case .recognitionDenied: L("Allow speech recognition for RightHand in System Settings → Privacy & Security → Speech Recognition.")
            case .unavailable(let language): L("Speech recognition isn't available for %@.", language)
            }
        }
    }

    var onPartial: ((String) -> Void)?
    /// 0…1, about 20 times a second.
    var onLevel: ((Float) -> Void)?

    private let audio = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var transcript = ""
    private var finalResult: CheckedContinuation<String, Never>?

    /// The language to listen in: chosen in Settings, or the app's language.
    static var locale: Locale {
        let chosen = UserDefaults.standard.string(forKey: VoiceSettings.Key.listenLanguage) ?? ""
        let code = chosen.isEmpty ? AppLanguage.current : chosen
        let regions = ["en": "en-US", "uk": "uk-UA", "cs": "cs-CZ", "ru": "ru-RU"]
        return Locale(identifier: regions[code] ?? code)
    }

    static func requestPermissions() async throws {
        let microphone = await AVCaptureDevice.requestAccess(for: .audio)
        guard microphone else { throw Failure.microphoneDenied }
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard status == .authorized else { throw Failure.recognitionDenied }
    }

    func start() throws {
        let locale = Self.locale
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw Failure.unavailable(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)
        }
        transcript = ""
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        self.request = request

        let input = audio.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        var lastLevel = Date.distantPast
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            request.append(buffer)
            guard Date().timeIntervalSince(lastLevel) > 0.05, let samples = buffer.floatChannelData?[0] else { return }
            lastLevel = Date()
            var sum: Float = 0
            for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
            let rms = sqrt(sum / Float(max(1, buffer.frameLength)))
            let level = min(1, max(0, (20 * log10(max(rms, 0.000_01)) + 50) / 40)) // -50…-10 dB → 0…1
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.onLevel?(level) } }
        }
        audio.prepare()
        try audio.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if let text { self.transcript = text; self.onPartial?(text) }
                    if isFinal || error != nil { self.deliver() }
                }
            }
        }
    }

    /// Stops recording and returns what was said (waits at most 2 seconds for the final text).
    func finish() async -> String {
        stopAudio()
        request?.endAudio()
        return await withCheckedContinuation { continuation in
            finalResult = continuation
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.deliver() }
        }
    }

    func cancel() {
        stopAudio()
        task?.cancel()
        task = nil
        request = nil
        deliver()
    }

    private func stopAudio() {
        if audio.isRunning { audio.stop() }
        audio.inputNode.removeTap(onBus: 0)
    }

    private func deliver() {
        guard let continuation = finalResult else { return }
        finalResult = nil
        task?.finish()
        task = nil
        request = nil
        continuation.resume(returning: transcript.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
