import AppKit
import AVFoundation
import NaturalLanguage
import Speech

/// Records from the microphone and turns speech into text with Apple's recognizer (on the Mac
/// itself when the language supports it). Apple's recognizer listens for one language at a time,
/// so in Automatic mode the same recording goes to English, Ukrainian, Czech and Russian at once
/// and the transcript that reads most like real text in its language wins.
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

    /// Languages Automatic listens for.
    nonisolated static let automaticLanguages = ["en", "uk", "cs", "ru"]
    private static let regions = ["en": "en-US", "uk": "uk-UA", "cs": "cs-CZ", "ru": "ru-RU"]

    var onPartial: ((String) -> Void)?
    /// 0…1, about 20 times a second.
    var onLevel: ((Float) -> Void)?

    /// One language being recognized.
    private final class Channel {
        let language: String
        let request = SFSpeechAudioBufferRecognitionRequest()
        var task: SFSpeechRecognitionTask?
        var transcript = ""
        var confidence: Float = 0
        var isDone = false

        init(language: String) { self.language = language }
    }

    private let audio = AVAudioEngine()
    private var channels: [Channel] = []
    private var finalResult: CheckedContinuation<String, Never>?

    /// The languages switched on in Settings (all four by default). With one, nothing has to be guessed.
    static var languages: [String] {
        get {
            if let saved = UserDefaults.standard.string(forKey: VoiceSettings.Key.listenLanguages) {
                let languages = automaticLanguages.filter { saved.split(separator: ",").map(String.init).contains($0) }
                return languages.isEmpty ? automaticLanguages : languages
            }
            // Earlier versions had one "Listen in" choice.
            let single = UserDefaults.standard.string(forKey: VoiceSettings.Key.listenLanguage) ?? ""
            return single.isEmpty ? automaticLanguages : [single]
        }
        set { UserDefaults.standard.set(newValue.joined(separator: ","), forKey: VoiceSettings.Key.listenLanguages) }
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
        channels = []
        for language in Self.languages {
            let locale = Locale(identifier: Self.regions[language] ?? language)
            guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else { continue }
            let channel = Channel(language: language)
            channel.request.shouldReportPartialResults = true
            channel.request.addsPunctuation = true
            if recognizer.supportsOnDeviceRecognition { channel.request.requiresOnDeviceRecognition = true }
            channel.task = recognizer.recognitionTask(with: channel.request) { [weak self, weak channel] result, error in
                let text = result?.bestTranscription.formattedString
                let segments = result?.bestTranscription.segments ?? []
                let isFinal = result?.isFinal ?? false
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, let channel else { return }
                        if let text {
                            channel.transcript = text
                            if isFinal, !segments.isEmpty {
                                channel.confidence = segments.map(\.confidence).reduce(0, +) / Float(segments.count)
                            }
                            self.onPartial?(self.best()?.transcript ?? text)
                        }
                        if isFinal || error != nil {
                            channel.isDone = true
                            if self.channels.allSatisfy(\.isDone) { self.deliver() }
                        }
                    }
                }
            }
            channels.append(channel)
        }
        guard !channels.isEmpty else {
            throw Failure.unavailable(Self.languages.map { Locale.current.localizedString(forLanguageCode: $0) ?? $0 }.joined(separator: ", "))
        }

        let requests = channels.map(\.request)
        let input = audio.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        nonisolated(unsafe) var lastLevel = Date.distantPast
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            for request in requests { request.append(buffer) }
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
    }

    /// Stops recording and returns what was said (waits at most 2.5 seconds for the final texts).
    func finish() async -> String {
        stopAudio()
        channels.forEach { $0.request.endAudio() }
        return await withCheckedContinuation { continuation in
            finalResult = continuation
            if channels.allSatisfy(\.isDone) { return deliver() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in self?.deliver() }
        }
    }

    func cancel() {
        stopAudio()
        channels.forEach { $0.task?.cancel() }
        deliver()
        channels = []
    }

    private func stopAudio() {
        if audio.isRunning { audio.stop() }
        audio.inputNode.removeTap(onBus: 0)
    }

    private func deliver() {
        guard let continuation = finalResult else { return }
        finalResult = nil
        let text = best()?.transcript ?? ""
        channels.forEach { $0.task?.finish() }
        channels = []
        continuation.resume(returning: text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The transcript that is most clearly in its own language.
    private func best() -> Channel? {
        let heard = channels.filter { !$0.transcript.isEmpty }
        let mostWords = heard.map { Self.wordCount($0.transcript) }.max() ?? 1
        return heard.max {
            Self.score(transcript: $0.transcript, language: $0.language, confidence: $0.confidence, mostWords: mostWords)
                < Self.score(transcript: $1.transcript, language: $1.language, confidence: $1.confidence, mostWords: mostWords)
        }
    }

    nonisolated static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).count
    }

    /// How likely `transcript` is real speech in `language` (higher is better). Signals:
    /// - how many words it heard compared with the other languages: a recognizer that doesn't know
    ///   the language you speak catches far fewer words (the strongest signal);
    /// - the share of words in that language's spelling dictionary;
    /// - how much the text reads like the language;
    /// - the recognizer's own confidence (on-device recognizers often report none: then it doesn't count).
    static func score(transcript: String, language: String, confidence: Float, mostWords: Int) -> Double {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = automaticLanguages.map { NLLanguage($0) }
        recognizer.processString(transcript)
        let probability = recognizer.languageHypotheses(withMaximum: 4)[NLLanguage(language)] ?? 0
        let coverage = Double(wordCount(transcript)) / Double(max(1, mostWords))
        let sureness = confidence > 0 ? Double(confidence) : 0.6
        return 0.4 * coverage + 0.3 * knownWords(in: transcript, language: language) + 0.15 * probability + 0.15 * sureness
    }

    /// Share of words (2+ letters) the system dictionary of `language` knows.
    static func knownWords(in text: String, language: String) -> Double {
        let words = text.components(separatedBy: CharacterSet.letters.inverted).filter { $0.count >= 2 }
        guard !words.isEmpty else { return 0 }
        let checker = NSSpellChecker.shared
        let known = words.filter { word in
            checker.checkSpelling(of: word, startingAt: 0, language: language, wrap: false, inSpellDocumentWithTag: 0, wordCount: nil).location == NSNotFound
        }
        return Double(known.count) / Double(words.count)
    }
}
