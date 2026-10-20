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
        static let listenLanguages = "voice.listenLanguages"
        static let wakeWord = "voice.wakeWord"
        static let enabled = "voice.enabled"
    }

    /// "" = pick the best installed voice for the language of each answer.
    static var voiceID: String { UserDefaults.standard.string(forKey: Key.voiceID) ?? "" }
    /// 0.5 is normal speed.
    static var rate: Float { UserDefaults.standard.object(forKey: Key.rate) as? Float ?? 0.52 }
    /// Ellipse as a whole: shortcut, wake word, record buttons.
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: Key.enabled) as? Bool ?? true }
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
    @ObservationIgnored private lazy var delegate = Delegate { [weak self] in self?.finished($0) }
    @ObservationIgnored private var onFinish: (() -> Void)?

    func toggle(_ text: String) {
        if currentText == text { stop() } else { speak(text) }
    }

    /// Speaks `text`; `onFinish` runs when it has been read to the end (not when stopped).
    /// Mixed-language answers ("Задача “Vytvoření predikce financí” …") are read part by part,
    /// each in a voice of its own language.
    func speak(_ text: String, onFinish: (() -> Void)? = nil) {
        stop()
        let parts = Self.parts(of: Self.plainText(text))
        guard !parts.isEmpty else { onFinish?(); return }
        synthesizer.delegate = delegate
        currentText = text
        self.onFinish = onFinish
        var last: AVSpeechUtterance?
        for part in parts {
            let utterance = AVSpeechUtterance(string: part.text)
            utterance.voice = Self.voice(for: part.language)
            utterance.rate = VoiceSettings.rate
            synthesizer.speak(utterance)
            last = utterance
        }
        lastUtterance = last
    }

    func stop() {
        onFinish = nil
        lastUtterance = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        currentText = nil
    }

    @ObservationIgnored private var lastUtterance: AVSpeechUtterance?

    private func finished(_ utterance: AVSpeechUtterance) {
        guard utterance === lastUtterance else { return }
        lastUtterance = nil
        currentText = nil
        let done = onFinish
        onFinish = nil
        done?()
    }

    /// The voice chosen in Settings for its own language; otherwise the best one for `language`.
    private static func voice(for language: String) -> AVSpeechSynthesisVoice? {
        if !VoiceSettings.voiceID.isEmpty, let chosen = AVSpeechSynthesisVoice(identifier: VoiceSettings.voiceID),
           chosen.language.hasPrefix(language) {
            return chosen
        }
        return VoiceSettings.bestVoice(for: language)
    }

    /// Splits text into runs of one language. Cyrillic is Russian or Ukrainian (decided for the
    /// whole text), Latin is English or Czech per run; a few Latin words inside Cyrillic text
    /// ("ClickUp", "on hold") stay with the surrounding voice, which reads them well enough.
    nonisolated static func parts(of text: String) -> [(text: String, language: String)] {
        enum Script { case cyrillic, latin, neutral }
        func script(_ scalar: Unicode.Scalar) -> Script {
            guard CharacterSet.letters.contains(scalar) else { return .neutral }
            return (0x0400...0x052F).contains(scalar.value) ? .cyrillic : .latin
        }
        func detect(_ text: String, among languages: [String]) -> String {
            let recognizer = NLLanguageRecognizer()
            recognizer.languageConstraints = languages.map { NLLanguage($0) }
            recognizer.processString(text)
            return recognizer.dominantLanguage?.rawValue ?? languages[0]
        }

        // Runs of one script; spaces, digits and punctuation join the run they're in.
        var runs: [(text: String, script: Script)] = []
        for character in text {
            let kind = character.unicodeScalars.first.map(script) ?? .neutral
            if kind == .neutral || runs.last?.script == kind || runs.isEmpty {
                if runs.isEmpty { runs.append((String(character), kind)) } else { runs[runs.count - 1].text.append(character) }
                if runs[runs.count - 1].script == .neutral, kind != .neutral { runs[runs.count - 1].script = kind }
            } else {
                runs.append((String(character), kind))
            }
        }

        let cyrillic = runs.filter { $0.script == .cyrillic }.map(\.text).joined(separator: " ")
        let cyrillicLanguage = cyrillic.isEmpty ? nil : detect(cyrillic, among: ["ru", "uk"])
        let main = cyrillicLanguage ?? detect(text, among: ["en", "cs", "uk", "ru"])
        let czechLetters = CharacterSet(charactersIn: "áčďéěíňóřšťúůýžÁČĎÉĚÍŇÓŘŠŤÚŮÝŽ")

        var parts: [(text: String, language: String)] = []
        for run in runs {
            var language = main
            if run.script == .latin {
                let words = run.text.split(whereSeparator: { !$0.isLetter }).count
                let looksCzech = run.text.unicodeScalars.contains { czechLetters.contains($0) }
                if cyrillicLanguage == nil {
                    language = looksCzech ? "cs" : detect(run.text, among: ["en", "cs"])
                } else if looksCzech || words >= 3 {
                    language = looksCzech ? "cs" : detect(run.text, among: ["en", "cs"])
                }
            }
            if let last = parts.last, last.language == language {
                parts[parts.count - 1].text += run.text
            } else {
                parts.append((run.text, language))
            }
        }
        return parts.map { ($0.text.trimmingCharacters(in: .whitespaces), $0.language) }.filter { $0.text.contains(where: \.isLetter) }
    }

    /// Markdown symbols and links would be read out loud; drop them.
    nonisolated static func plainText(_ markdown: String) -> String {
        var text = markdown
        text = text.replacingOccurrences(of: "```[\\s\\S]*?```", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: "https?://\\S+", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "[*_`#>|]+", with: "", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private final class Delegate: NSObject, AVSpeechSynthesizerDelegate {
        let onFinish: @MainActor (AVSpeechUtterance) -> Void
        init(onFinish: @escaping @MainActor (AVSpeechUtterance) -> Void) { self.onFinish = onFinish }
        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
            nonisolated(unsafe) let utterance = utterance
            Task { @MainActor in onFinish(utterance) }
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
