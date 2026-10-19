import AVFoundation
import Observation
import SwiftUI

/// ElevenLabs settings: the API key is in the Keychain, voice and model in UserDefaults.
enum VoiceSettings {
    static let keychainAccount = "elevenlabs-api-key"
    static let keysURL = URL(string: "https://elevenlabs.io/app/settings/api-keys")!

    enum Key {
        static let voiceID = "voice.voiceID"
        static let model = "voice.model"
    }

    enum Default {
        static let voiceID = "EXAVITQu4vr4xnSDxMaL" // Sarah
        static let model = "eleven_multilingual_v2"
    }

    /// Multilingual v2 speaks Ukrainian, English and ~30 more languages; Flash is faster and cheaper.
    static let models: [(id: String, name: String)] = [
        ("eleven_multilingual_v2", "Multilingual v2 (best quality)"),
        ("eleven_flash_v2_5", "Flash v2.5 (fast, cheaper)"),
    ]

    static var voiceID: String { UserDefaults.standard.string(forKey: Key.voiceID) ?? Default.voiceID }
    static var model: String { UserDefaults.standard.string(forKey: Key.model) ?? Default.model }
}

/// Reads AI answers aloud with ElevenLabs.
@Observable
@MainActor
final class SpeechPlayer {
    static let shared = SpeechPlayer()

    /// The text being spoken (or loaded) right now.
    private(set) var currentText: String?
    private(set) var isLoading = false
    var errorMessage: String?

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var delegate: Delegate?
    @ObservationIgnored private var task: Task<Void, Never>?

    private static let maxCharacters = 5_000

    var hasKey: Bool { Keychain.read(VoiceSettings.keychainAccount) != nil }

    func toggle(_ text: String) {
        if currentText == text { stop() } else { speak(text) }
    }

    func speak(_ text: String) {
        stop()
        guard let apiKey = Keychain.read(VoiceSettings.keychainAccount) else {
            errorMessage = L("Add your %@ API key in Settings → Assistant.", "ElevenLabs")
            return
        }
        currentText = text
        isLoading = true
        errorMessage = nil
        let spoken = String(Self.plainText(text).prefix(Self.maxCharacters))
        task = Task {
            do {
                let audio = try await ElevenLabs.speech(for: spoken, voiceID: VoiceSettings.voiceID,
                                                        model: VoiceSettings.model, apiKey: apiKey)
                try Task.checkCancellation()
                play(audio)
            } catch is CancellationError {
            } catch {
                errorMessage = error.localizedDescription
                currentText = nil
            }
            isLoading = false
        }
    }

    func stop() {
        task?.cancel()
        player?.stop()
        player = nil
        currentText = nil
        isLoading = false
    }

    private func play(_ audio: Data) {
        guard let player = try? AVAudioPlayer(data: audio) else {
            errorMessage = L("Couldn't play the audio.")
            currentText = nil
            return
        }
        let delegate = Delegate { [weak self] in self?.currentText = nil }
        player.delegate = delegate
        self.delegate = delegate
        self.player = player
        player.play()
    }

    /// Markdown symbols would be read out loud; drop them.
    private static func plainText(_ markdown: String) -> String {
        var text = markdown
        text = text.replacingOccurrences(of: "```[\\s\\S]*?```", with: " (code) ", options: .regularExpression)
        text = text.replacingOccurrences(of: "[*_`#>]+", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\[([^\\]]+)\\]\\([^)]+\\)", with: "$1", options: .regularExpression)
        return text
    }

    private final class Delegate: NSObject, AVAudioPlayerDelegate {
        let onFinish: @MainActor () -> Void
        init(onFinish: @escaping @MainActor () -> Void) { self.onFinish = onFinish }
        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            Task { @MainActor in onFinish() }
        }
    }
}

/// ElevenLabs text-to-speech API.
enum ElevenLabs {
    struct Voice: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
    }

    static func speech(for text: String, voiceID: String, model: String, apiKey: String) async throws -> Data {
        var components = URLComponents(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceID)")!
        components.queryItems = [URLQueryItem(name: "output_format", value: "mp3_44100_128")]
        var request = URLRequest(url: components.url!, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONValue.object(["text": .string(text), "model_id": .string(model)]).encoded()
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data)
        return data
    }

    static func voices(apiKey: String) async throws -> [Voice] {
        var request = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/voices")!)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        let (data, response) = try await URLSession.shared.data(for: request)
        try check(response, data)
        return (JSONValue.parse(data)?["voices"]?.array ?? []).compactMap { voice in
            guard let id = voice["voice_id"]?.string, let name = voice["name"]?.string else { return nil }
            return Voice(id: id, name: name.components(separatedBy: " - ").first ?? name)
        }
    }

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let status = (response as? HTTPURLResponse)?.statusCode, status != 200 else { return }
        let detail = JSONValue.parse(data)?["detail"]
        let message = detail?["message"]?.string ?? detail?.string
        throw ChatError(message: status == 401 ? L("The ElevenLabs API key was rejected.") : L("ElevenLabs error %lld%@", status, message.map { ": \($0)" } ?? ""))
    }
}

/// ▶︎ / ■ button that reads a text aloud.
struct SpeakButton: View {
    let text: String
    private var player: SpeechPlayer { .shared }

    var body: some View {
        let isCurrent = player.currentText == text
        Button(isCurrent ? "Stop Reading" : "Read Aloud",
               systemImage: isCurrent ? (player.isLoading ? "hourglass" : "stop.fill") : "speaker.wave.2") {
            player.toggle(text)
        }
        .help(player.hasKey ? (isCurrent ? "Stop" : "Read aloud with ElevenLabs") : "Add an ElevenLabs API key in Settings → Assistant")
    }
}
