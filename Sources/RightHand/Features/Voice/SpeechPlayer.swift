import AVFoundation
import NaturalLanguage
import Observation
import SwiftUI

/// Voice settings: reading answers aloud with the Mac's own voices (on the Mac, free, offline),
/// the shortcut for talking to the AI, and the language it listens in.
enum VoiceSettings {
    enum Key {
        static let voiceID = "voice.localVoice"
        static let rate = "voice.rate"
        static let speakVoiceAnswers = "voice.speakAnswers"
        static let shortcut = "voice.shortcut"
        static let listenLanguage = "voice.listenLanguage"
    }

    /// "" = pick the best installed voice for the language of each answer.
    static var voiceID: String { UserDefaults.standard.string(forKey: Key.voiceID) ?? "" }
    /// 0.5 is normal speed.
    static var rate: Float { UserDefaults.standard.object(forKey: Key.rate) as? Float ?? 0.52 }
    static var speakVoiceAnswers: Bool { UserDefaults.standard.object(forKey: Key.speakVoiceAnswers) as? Bool ?? true }

    /// Installed voices worth offering: no novelty voices (Bells, Bubbles, …).
    static var voices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.identifier.hasPrefix("com.apple.voice.") || $0.quality != .default }
            .sorted { ($0.language, $0.name) < ($1.language, $1.name) }
    }

    /// The best voice for a language: premium, then enhanced, then the standard one.
    static func bestVoice(for language: String) -> AVSpeechSynthesisVoice? {
        let candidates = voices.filter { $0.language.hasPrefix(language) }
        // The usual region first (en-US, not en-AU), at the same quality.
        let home = ["en": "en-US", "uk": "uk-UA", "cs": "cs-CZ", "ru": "ru-RU", "de": "de-DE", "es": "es-ES", "fr": "fr-FR"][language]
        func key(_ voice: AVSpeechSynthesisVoice) -> Int { rank(voice) * 2 + (voice.language == home ? 1 : 0) }
        return candidates.max { key($0) < key($1) } ?? AVSpeechSynthesisVoice(language: language)
    }

    private static func rank(_ voice: AVSpeechSynthesisVoice) -> Int {
        switch voice.quality {
        case .premium: 3
        case .enhanced: 2
        default: voice.identifier.hasPrefix("com.apple.voice.") ? 1 : 0
        }
    }
}

/// Reads AI answers aloud with the Mac's built-in speech (no internet, no API key).
@Observable
@MainActor
final class SpeechPlayer {
    static let shared = SpeechPlayer()

    /// The text being spoken right now.
    private(set) var currentText: String?
    /// Kept for the ▶︎ buttons; local speech starts at once.
    let isLoading = false

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private lazy var delegate = Delegate { [weak self] in self?.finished() }
    @ObservationIgnored private var onFinish: (() -> Void)?

    func toggle(_ text: String) {
        if currentText == text { stop() } else { speak(text) }
    }

    /// Speaks `text`; `onFinish` runs when it has been read to the end (not when stopped).
    func speak(_ text: String, onFinish: (() -> Void)? = nil) {
        stop()
        let spoken = Self.plainText(text)
        guard !spoken.isEmpty else { onFinish?(); return }
        synthesizer.delegate = delegate
        let utterance = AVSpeechUtterance(string: spoken)
        utterance.voice = Self.voice(for: spoken)
        utterance.rate = VoiceSettings.rate
        currentText = text
        self.onFinish = onFinish
        synthesizer.speak(utterance)
    }

    func stop() {
        onFinish = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        currentText = nil
    }

    private func finished() {
        currentText = nil
        let done = onFinish
        onFinish = nil
        done?()
    }

    private static func voice(for text: String) -> AVSpeechSynthesisVoice? {
        if !VoiceSettings.voiceID.isEmpty, let chosen = AVSpeechSynthesisVoice(identifier: VoiceSettings.voiceID) { return chosen }
        let language = NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue ?? AppLanguage.current
        return VoiceSettings.bestVoice(for: language)
    }

    /// Markdown symbols and links would be read out loud; drop them.
    static func plainText(_ markdown: String) -> String {
        var text = markdown
        text = text.replacingOccurrences(of: "```[\\s\\S]*?```", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: "https?://\\S+", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "[*_`#>|]+", with: "", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private final class Delegate: NSObject, AVSpeechSynthesizerDelegate {
        let onFinish: @MainActor () -> Void
        init(onFinish: @escaping @MainActor () -> Void) { self.onFinish = onFinish }
        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            Task { @MainActor in onFinish() }
        }
    }
}

/// ▶︎ / ■ button that reads a text aloud.
struct SpeakButton: View {
    let text: String
    private var player: SpeechPlayer { .shared }

    var body: some View {
        let isCurrent = player.currentText == text
        Button(isCurrent ? "Stop Reading" : "Read Aloud", systemImage: isCurrent ? "stop.fill" : "speaker.wave.2") {
            player.toggle(text)
        }
        .help(isCurrent ? "Stop" : "Read aloud")
    }
}
