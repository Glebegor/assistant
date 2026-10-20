import AppKit
import Observation
import WhisperKit

/// Reviews recorded meetings on request: local Whisper writes the transcript (you and the others
/// on separate tracks), then Claude or ChatGPT — only the text is sent — writes the review:
/// summary and decisions, tasks, and an assessment of the meeting. Both are saved next to the video.
@Observable
@MainActor
final class MeetingAnalyzer {
    enum Status: Equatable {
        case queued
        case downloadingModel(Double)
        case loadingModel
        case transcribing(Double)
        case reviewing
        case failed(String)
    }

    /// Recordings being analysed (finished ones have a review file instead).
    private(set) var jobs: [URL: Status] = [:]
    /// Bumped when a review is saved, so lists refresh.
    private(set) var revision = 0

    @ObservationIgnored private var queue: [URL] = []
    @ObservationIgnored private var worker: Task<Void, Never>?

    static func reviewURL(for recording: URL) -> URL { recording.deletingPathExtension().appendingPathExtension("review.md") }
    static func transcriptURL(for recording: URL) -> URL { recording.deletingPathExtension().appendingPathExtension("transcript.txt") }

    func hasReview(_ recording: URL) -> Bool {
        _ = revision
        return FileManager.default.fileExists(atPath: Self.reviewURL(for: recording).path)
    }

    func analyze(_ recording: URL) {
        guard jobs[recording] == nil || isFailed(recording) else { return }
        jobs[recording] = .queued
        queue.append(recording)
        if worker == nil { worker = Task { await work() } }
    }

    func cancel(_ recording: URL) {
        queue.removeAll { $0 == recording }
        if queue.isEmpty, jobs[recording] != nil { worker?.cancel() }
        jobs[recording] = nil
    }

    private func isFailed(_ recording: URL) -> Bool {
        if case .failed = jobs[recording] { true } else { false }
    }

    // MARK: Work

    private func work() async {
        var whisper: WhisperKit?
        while !queue.isEmpty, !Task.isCancelled {
            let recording = queue.removeFirst()
            do {
                if whisper == nil {
                    whisper = try await MeetingTranscriber.loadModel { [weak self] progress in
                        Task { @MainActor in
                            guard let self, self.jobs[recording] != nil else { return }
                            switch progress {
                            case .downloadingModel(let value): self.jobs[recording] = .downloadingModel(value)
                            case .loadingModel: self.jobs[recording] = .loadingModel
                            case .transcribing(let value): self.jobs[recording] = .transcribing(value)
                            }
                        }
                    }
                }
                jobs[recording] = .transcribing(0)
                let utterances = try await MeetingTranscriber.transcribe(recording, with: whisper!) { [weak self] value in
                    Task { @MainActor in if self?.jobs[recording] != nil { self?.jobs[recording] = .transcribing(value) } }
                }
                guard !utterances.isEmpty else { throw ChatError(message: L("No speech was found in this recording.")) }
                let transcript = MeetingTranscriber.text(of: utterances, me: L("Me"), others: L("Others"))
                try transcript.write(to: Self.transcriptURL(for: recording), atomically: true, encoding: .utf8)

                jobs[recording] = .reviewing
                let review = try await MeetingReviewer.review(transcript: transcript, utterances: utterances, recording: recording)
                try review.write(to: Self.reviewURL(for: recording), atomically: true, encoding: .utf8)
                jobs[recording] = nil
                revision += 1
                Notifier.shared.notify(title: L("Meeting review is ready"), body: recording.deletingPathExtension().lastPathComponent)
            } catch is CancellationError {
                jobs[recording] = nil
            } catch {
                jobs[recording] = .failed(error.localizedDescription)
            }
        }
        // The model takes ~1 GB of memory; it's loaded again next time.
        whisper = nil
        worker = nil
    }
}

/// Writes the meeting review with the AI chosen in Settings (Claude or ChatGPT).
enum MeetingReviewer {
    static func review(transcript: String, utterances: [Utterance], recording: URL) async throws -> String {
        let provider = ChatSettings.provider
        guard let apiKey = Keychain.read(provider.keychainAccount) else {
            throw ChatError(message: L("Add your %@ API key in Settings → Assistant.", provider.title))
        }
        let language = mainLanguage(of: utterances)
        let minutes = Int((utterances.last?.end ?? 0) / 60)
        let date = (try? recording.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()

        let system = """
        You review recorded meetings for the user. You get a transcript with timestamps; "\(L("Me"))" is the user \
        (their microphone) and "\(L("Others"))" are the other participants (the computer sound). The transcript comes \
        from automatic speech recognition, so it has mistakes: read through them. \(AboutMe.text.isEmpty ? "" : "About the user: \(AboutMe.text)")
        """
        let request = """
        Write a review of this meeting in \(Locale(identifier: "en").localizedString(forLanguageCode: language) ?? language). \
        Use Markdown with exactly these sections, and refer to moments as [hh:mm:ss]:

        # A short title for the meeting
        One line: date \(date.formatted(date: .long, time: .shortened)), about \(minutes) minutes, participants if they are clear.

        ## Summary
        5–8 sentences: what the meeting was about and how it went.

        ## Decisions
        Bullet list of what was decided (or "No decisions were made.").

        ## Tasks
        Bullet list: **who** — what — deadline if mentioned — [time]. Only tasks actually agreed on.

        ## Open questions
        What stayed unclear or needs follow-up.

        ## Assessment
        - Score: n/10 for how productive it was.
        - What went well.
        - What didn't: going in circles, missing agenda, unclear owners, running over time…
        - Was the goal reached?
        - 2–3 concrete tips for the next meeting.

        Transcript:

        \(transcript)
        """

        var chat = ProjectChat(projectID: UUID(), provider: provider, model: ChatSettings.model(for: provider),
                               system: system, contextFingerprint: "")
        let client: ModelClient = provider == .claude ? ClaudeClient() : OpenAIClient()
        chat.messages = client.userMessages(text: request, contextUpdate: nil)
        let turn = try await client.turn(system: system, chat: chat, tools: [], apiKey: apiKey) { _ in }
        chat.messages.append(turn.message)
        let answer = ChatDisplayItem.items(for: chat).reversed().lazy.compactMap { item -> String? in
            if case .assistant(_, let text) = item { return text } else { return nil }
        }.first
        guard let answer, !answer.isEmpty else { throw ChatError(message: L("No answer came back.")) }
        return answer
    }

    /// The language most of the meeting was spoken in.
    static func mainLanguage(of utterances: [Utterance]) -> String {
        var weight: [String: Int] = [:]
        for utterance in utterances { weight[utterance.language ?? "en", default: 0] += utterance.text.count }
        return weight.max { $0.value < $1.value }?.key ?? "en"
    }
}
