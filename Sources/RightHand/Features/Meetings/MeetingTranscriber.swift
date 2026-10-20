import AVFoundation
import Foundation
import WhisperKit

/// One stretch of speech in a meeting.
struct Utterance: Codable, Sendable {
    enum Speaker: String, Codable, Sendable { case me, others }
    var start: Double
    var end: Double
    var speaker: Speaker
    var text: String
    var language: String?
}

/// Turns a recording's two audio tracks into a timed transcript with local Whisper.
/// Your microphone track is "me", the computer sound is "others". Nothing leaves the Mac.
enum MeetingTranscriber {
    /// Multilingual, ~632 MB, fast on Apple silicon; good for English, Ukrainian, Russian and Czech.
    static let modelVariant = "openai_whisper-large-v3-v20240930_turbo_632MB"
    static let languages = ["en", "uk", "ru", "cs"]
    static var modelsFolder: URL { AppPaths.makeDirectory(AppPaths.support.appending(path: "Models", directoryHint: .isDirectory)) }

    /// Ten minutes at a time keeps memory low even for a four-hour recording.
    private static let chunkSeconds = 600.0
    private static let sampleRate = 16_000.0

    enum Progress: Sendable {
        case downloadingModel(Double)
        case loadingModel
        case transcribing(Double)
    }

    // MARK: Model

    /// Downloads the model once (into Application Support, not Documents) and loads it.
    static func loadModel(progress: @escaping @Sendable (Progress) -> Void) async throws -> WhisperKit {
        let folder = try await WhisperKit.download(variant: modelVariant, downloadBase: modelsFolder) { value in
            progress(.downloadingModel(value.fractionCompleted))
        }
        progress(.loadingModel)
        let config = WhisperKitConfig(model: modelVariant, downloadBase: modelsFolder, modelFolder: folder.path,
                                      verbose: false, logLevel: .error, prewarm: false, load: true, download: false)
        return try await WhisperKit(config)
    }

    static var isModelDownloaded: Bool {
        FileManager.default.enumerator(at: modelsFolder, includingPropertiesForKeys: nil)?
            .contains { ($0 as? URL)?.lastPathComponent == modelVariant } ?? false
    }

    // MARK: Transcribing

    static func transcribe(_ recording: URL, with whisper: WhisperKit,
                           progress: @escaping @Sendable (Double) -> Void) async throws -> [Utterance] {
        let asset = AVURLAsset(url: recording)
        let duration = try await asset.load(.duration).seconds
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw ChatError(message: L("This recording has no sound.")) }

        var utterances: [Utterance] = []
        for (index, track) in tracks.enumerated() {
            let speaker = try await Self.speaker(of: track, index: index)
            utterances += try await transcribe(track: track, of: asset, speaker: speaker, whisper: whisper) { done in
                progress((Double(index) + min(1, done / max(duration, 1))) / Double(tracks.count))
            }
        }
        return removeEcho(from: utterances).sorted { $0.start < $1.start }
    }

    /// The track named "My voice" is you; anything else is the computer sound.
    private static func speaker(of track: AVAssetTrack, index: Int) async throws -> Utterance.Speaker {
        let names = try await track.load(.metadata).filter { $0.identifier == .quickTimeUserDataTrackName }
        let name = try await names.first?.load(.stringValue)
        if let name { return name == "My voice" ? .me : .others }
        return index == 0 ? .me : .others
    }

    private static func transcribe(track: AVAssetTrack, of asset: AVAsset, speaker: Utterance.Speaker, whisper: WhisperKit,
                                   progress: (Double) -> Void) async throws -> [Utterance] {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ])
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? ChatError(message: L("Couldn't read the recording.")) }

        var utterances: [Utterance] = []
        // Samples not processed yet, starting at `pendingStart` seconds.
        var pending: [Float] = []
        var pendingStart = 0.0
        let chunkLength = Int(chunkSeconds * sampleRate)

        /// Transcribes the phrases in `pending`; one still running at the end waits for more audio.
        func process(final: Bool) async throws {
            let phrases = Self.phrases(in: pending)
            var keepFrom = pending.count
            for phrase in phrases {
                if !final, phrase.upperBound >= pending.count - Int(0.5 * sampleRate) {
                    keepFrom = phrase.lowerBound
                    break
                }
                let piece = Array(pending[phrase])
                let language = try await detectLanguage(of: piece, with: whisper)
                let options = DecodingOptions(task: .transcribe, language: language, temperature: 0, usePrefillPrompt: true,
                                              detectLanguage: false, skipSpecialTokens: true, withoutTimestamps: false)
                let offset = pendingStart + Double(phrase.lowerBound) / sampleRate
                let results = try await whisper.transcribe(audioArray: piece, decodeOptions: options)
                for segment in results.flatMap(\.segments) where isRealSpeech(segment) {
                    utterances.append(Utterance(start: offset + Double(segment.start), end: offset + Double(segment.end),
                                                speaker: speaker, text: clean(segment.text), language: language))
                }
            }
            pendingStart += Double(keepFrom) / sampleRate
            pending.removeFirst(keepFrom)
        }

        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var samples = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            samples.withUnsafeMutableBytes { _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
            pending += samples
            if pending.count >= chunkLength {
                try await process(final: false)
                progress(pendingStart)
            }
        }
        try await process(final: true)
        progress(pendingStart + Double(pending.count) / sampleRate)
        return utterances
    }

    /// Phrases: stretches of sound separated by pauses (30 ms frames louder than the background),
    /// at most 28 seconds each so Whisper hears each in one go.
    static func phrases(in samples: [Float]) -> [Range<Int>] {
        let frame = Int(0.03 * sampleRate)
        guard samples.count >= frame else { return [] }
        var levels: [Float] = []
        var index = 0
        while index + frame <= samples.count {
            var sum: Float = 0
            for i in stride(from: index, to: index + frame, by: 4) { sum += samples[i] * samples[i] }
            levels.append(sqrt(sum / Float(frame / 4)))
            index += frame
        }
        // Background noise: a quiet percentile; speech is clearly above it.
        let sorted = levels.sorted()
        let noise = sorted[Int(Double(sorted.count) * 0.2)]
        let threshold = max(0.008, noise * 3)
        let maxGap = Int(0.6 / 0.03), minLength = Int(0.35 / 0.03), maxLength = Int(28 / 0.03), pad = Int(0.2 / 0.03)

        var ranges: [Range<Int>] = [] // in frames
        var start: Int?, lastLoud = 0
        for (i, level) in levels.enumerated() {
            if level > threshold {
                if start == nil { start = i }
                lastLoud = i
            }
            if let begin = start, i - lastLoud > maxGap || i - begin >= maxLength || i == levels.count - 1 {
                if lastLoud - begin >= minLength { ranges.append(begin..<(lastLoud + 1)) }
                start = nil
            }
        }
        return ranges.map { range in
            max(0, (range.lowerBound - pad) * frame)..<min(samples.count, (range.upperBound + pad) * frame)
        }
    }

    /// The language of a phrase, among English, Ukrainian, Russian and Czech.
    private static func detectLanguage(of samples: [Float], with whisper: WhisperKit) async throws -> String? {
        guard samples.count > Int(0.5 * sampleRate) else { return nil }
        let detected = try await whisper.detectLangauge(audioArray: Array(samples.prefix(Int(30 * sampleRate))))
        return languages.max { (detected.langProbs[$0] ?? -.infinity) < (detected.langProbs[$1] ?? -.infinity) }
    }

    /// Whisper sometimes "hears" stock phrases in silence; those are dropped.
    private static let hallucinations = ["thank you for watching", "thanks for watching", "subtitles by", "subscribe",
                                         "продолжение следует", "редактор субтитров", "дякую за перегляд", "субтитри",
                                         "titulky", "děkuji za pozornost"]

    private static func isRealSpeech(_ segment: TranscriptionSegment) -> Bool {
        let text = clean(segment.text).lowercased()
        guard text.count > 1, segment.noSpeechProb < 0.6 || segment.avgLogprob > -0.7 else { return false }
        return !hallucinations.contains { text.contains($0) && text.count < $0.count + 15 }
    }

    private static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: "<\\|[^|]*\\|>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Without headphones the microphone also hears the speakers: a "me" line that repeats what the
    /// others said at the same moment is an echo and is dropped.
    static func removeEcho(from utterances: [Utterance]) -> [Utterance] {
        let others = utterances.filter { $0.speaker == .others }
        return utterances.filter { mine in
            guard mine.speaker == .me else { return true }
            return !others.contains { other in
                let overlap = min(mine.end, other.end) - max(mine.start, other.start)
                return overlap > 0.5 * (mine.end - mine.start) && similarity(mine.text, other.text) > 0.5
            }
        }
    }

    static func similarity(_ a: String, _ b: String) -> Double {
        func words(_ text: String) -> Set<String> {
            Set(text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        }
        let first = words(a), second = words(b)
        guard !first.isEmpty, !second.isEmpty else { return 0 }
        return Double(first.intersection(second).count) / Double(first.union(second).count)
    }

    /// "[00:12:04] Me: …" — one line per utterance.
    static func text(of utterances: [Utterance], me: String, others: String) -> String {
        utterances.map { "[\(timestamp($0.start))] \($0.speaker == .me ? me : others): \($0.text)" }.joined(separator: "\n")
    }

    static func timestamp(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }
}
