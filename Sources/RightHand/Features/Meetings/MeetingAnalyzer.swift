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
    /// "Analyze as lecture": the kind you chose; otherwise the AI recognizes it.
    @ObservationIgnored private var kinds: [URL: MeetingKind] = [:]
    @ObservationIgnored private var worker: Task<Void, Never>?

    nonisolated static func reviewURL(for recording: URL) -> URL { recording.deletingPathExtension().appendingPathExtension("review.md") }
    nonisolated static func transcriptURL(for recording: URL) -> URL { recording.deletingPathExtension().appendingPathExtension("transcript.txt") }
    nonisolated static func jsonURL(for recording: URL) -> URL { recording.deletingPathExtension().appendingPathExtension("review.json") }

    func hasReview(_ recording: URL) -> Bool {
        _ = revision
        return FileManager.default.fileExists(atPath: Self.reviewURL(for: recording).path)
    }

    func analyze(_ recording: URL, as kind: MeetingKind? = nil) {
        kinds[recording] = kind
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
                let review = try await MeetingReviewer.review(transcript: transcript, utterances: utterances, recording: recording,
                                                              kind: kinds[recording])
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
                try encoder.encode(review).write(to: Self.jsonURL(for: recording))
                try review.markdown.write(to: Self.reviewURL(for: recording), atomically: true, encoding: .utf8)
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

/// What kind of meeting a recording is; the review is written for it.
enum MeetingKind: String, Codable, CaseIterable, Identifiable {
    case lecture, teamMeeting, standup, oneOnOne, clientCall, interview, workshop, presentation, other

    var id: Self { self }

    var title: String {
        switch self {
        case .lecture: L("Lecture")
        case .teamMeeting: L("Team meeting")
        case .standup: L("Stand-up")
        case .oneOnOne: L("One-on-one")
        case .clientCall: L("Client call")
        case .interview: L("Interview")
        case .workshop: L("Workshop")
        case .presentation: L("Presentation")
        case .other: L("Meeting")
        }
    }

    var systemImage: String {
        switch self {
        case .lecture: "graduationcap"
        case .teamMeeting: "person.3"
        case .standup: "figure.stand"
        case .oneOnOne: "person.2"
        case .clientCall: "briefcase"
        case .interview: "person.crop.rectangle"
        case .workshop: "hammer"
        case .presentation: "rectangle.on.rectangle"
        case .other: "bubble.left.and.bubble.right"
        }
    }

    /// What the review should focus on for this kind.
    var guidance: String {
        switch self {
        case .lecture:
            "It's a lecture or class: keyPoints are the main ideas, definitions and formulas to learn; tasks are homework, assignments and deadlines the lecturer gave (owner = 'Me'); decisions are usually empty; the assessment rates how clear and useful the lecture was and gives study tips."
        case .teamMeeting:
            "It's a team meeting: focus on decisions, who owns which task and deadlines; keyPoints are the main topics."
        case .standup:
            "It's a stand-up: keyPoints are each person's progress and blockers; tasks are what each person does next; keep the summary short."
        case .oneOnOne:
            "It's a one-on-one: keyPoints are feedback, concerns and agreements; tasks are follow-ups."
        case .clientCall:
            "It's a call with a client: keyPoints are the client's needs, objections and what was promised; tasks are follow-ups with owners."
        case .interview:
            "It's an interview: keyPoints are the questions asked and the main answers; the assessment rates how it went for the user and gives tips."
        case .workshop:
            "It's a workshop or brainstorm: keyPoints are the ideas that came up and which ones were chosen; tasks are next steps."
        case .presentation:
            "It's a presentation or demo: keyPoints are what was presented and the feedback; tasks are follow-ups."
        case .other:
            "Write a general meeting review."
        }
    }
}

/// A meeting review as the AI writes it (JSON), shown as cards and saved as Markdown too.
struct MeetingReview: Codable {
    struct Task: Codable, Hashable {
        var owner: String
        var task: String
        var due: String?
        var time: String?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            owner = c.text(.owner) ?? "—"
            task = c.text(.task) ?? ""
            due = c.text(.due)
            time = c.text(.time)
        }
    }
    struct Assessment: Codable {
        var score: Int
        var wentWell: [String]
        var wentWrong: [String]
        var goalReached: String
        var tips: [String]

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            score = max(1, min(10, c.number(.score) ?? 5))
            wentWell = c.texts(.wentWell)
            wentWrong = c.texts(.wentWrong)
            goalReached = c.text(.goalReached) ?? ""
            tips = c.texts(.tips)
        }

        init() { (score, wentWell, wentWrong, goalReached, tips) = (5, [], [], "", []) }
    }

    struct Chapter: Codable, Hashable {
        var time: String
        var title: String
        var summary: String?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            time = c.text(.time) ?? "00:00:00"
            title = c.text(.title) ?? ""
            summary = c.text(.summary)
        }
    }

    var title: String
    /// MeetingKind raw value (missing in reviews made before kinds existed).
    var kind: String?
    var participants: [String]
    var summary: String
    /// The meeting in parts, with start times.
    var timeline: [Chapter]?
    /// Main ideas (a lecture's concepts, a team meeting's topics…).
    var keyPoints: [String]?
    var decisions: [String]
    var tasks: [Task]
    var openQuestions: [String]
    var assessment: Assessment

    /// Also when the model wrote "Team meeting" or "team_meeting" instead of "teamMeeting".
    var meetingKind: MeetingKind {
        let simple = { (text: String) in text.lowercased().filter(\.isLetter) }
        return kind.flatMap { kind in MeetingKind.allCases.first { simple($0.rawValue) == simple(kind) } } ?? .other
    }

    /// Forgiving: models sometimes leave a field out, write a number as text or null instead of a list.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = c.text(.title) ?? L("Meeting")
        kind = c.text(.kind)
        participants = c.texts(.participants)
        summary = c.text(.summary) ?? ""
        timeline = (try? c.decodeIfPresent([Chapter].self, forKey: .timeline)) ?? nil
        keyPoints = c.texts(.keyPoints)
        decisions = c.texts(.decisions)
        tasks = ((try? c.decodeIfPresent([Task].self, forKey: .tasks)) ?? nil) ?? []
        openQuestions = c.texts(.openQuestions)
        assessment = ((try? c.decodeIfPresent(Assessment.self, forKey: .assessment)) ?? nil) ?? Assessment()
    }

    static func load(for recording: URL) -> MeetingReview? {
        (try? Data(contentsOf: MeetingAnalyzer.jsonURL(for: recording))).flatMap { try? JSONDecoder().decode(MeetingReview.self, from: $0) }
    }

    /// The same review as a Markdown document (saved next to the video, and for Copy).
    var markdown: String {
        func list(_ items: [String]) -> String { items.isEmpty ? "—" : items.map { "- \($0)" }.joined(separator: "\n") }
        let taskLines = tasks.map { task in
            "- **\(task.owner)** — \(task.task)" + (task.due.map { " — \($0)" } ?? "") + (task.time.map { " — [\($0)]" } ?? "")
        }
        let chapters = (timeline ?? []).map { "- [\($0.time)] **\($0.title)**" + ($0.summary.map { " — \($0)" } ?? "") }
        return """
        # \(title)

        \(meetingKind.title) · \(participants.joined(separator: ", "))

        ## \(L("Summary"))
        \(summary)

        ## \(L("Timeline"))
        \(chapters.isEmpty ? "—" : chapters.joined(separator: "\n"))

        ## \(L("Key points"))
        \(list(keyPoints ?? []))

        ## \(L("Decisions"))
        \(list(decisions))

        ## \(L("Tasks"))
        \(taskLines.isEmpty ? "—" : taskLines.joined(separator: "\n"))

        ## \(L("Open questions"))
        \(list(openQuestions))

        ## \(L("Assessment")) — \(assessment.score)/10
        \(assessment.goalReached)

        **\(L("What went well"))**
        \(list(assessment.wentWell))

        **\(L("What didn't"))**
        \(list(assessment.wentWrong))

        **\(L("Next time"))**
        \(list(assessment.tips))
        """
    }
}

/// Writes the meeting review with the AI chosen in Settings (Claude or ChatGPT).
enum MeetingReviewer {
    static func review(transcript: String, utterances: [Utterance], recording: URL, kind: MeetingKind? = nil) async throws -> MeetingReview {
        let provider = ChatSettings.provider
        guard let apiKey = Keychain.read(provider.keychainAccount) else {
            throw ChatError(message: L("Add your %@ API key in Settings → Assistant.", provider.title))
        }
        let language = mainLanguage(of: utterances)
        let languageName = Locale(identifier: "en").localizedString(forLanguageCode: language) ?? language

        let system = """
        You review recorded meetings for the user. You get a transcript with timestamps; "\(L("Me"))" is the user \
        (their microphone) and "\(L("Others"))" are the other participants (the computer sound). The transcript comes \
        from automatic speech recognition, so it has mistakes: read through them. \(AboutMe.text.isEmpty ? "" : "About the user: \(AboutMe.text)")
        """
        let request = """
        Review this recording. Answer with only a JSON object (no Markdown, no code fence), all text in \(languageName).

        \(kind.map { "The user says this is a \($0.rawValue). \($0.guidance)" } ?? """
        First decide what kind of meeting it is — one of: \(MeetingKind.allCases.map(\.rawValue).joined(separator: ", ")) — \
        and write the review for that kind:
        \(MeetingKind.allCases.filter { $0 != .other }.map { "- \($0.rawValue): \($0.guidance)" }.joined(separator: "\n"))
        """)

        {
          "title": "a short title for the meeting",
          "kind": "\(kind?.rawValue ?? "one of the kinds above")",
          "participants": ["names if they are clear, else roles like 'Me', 'Client', 'Professor'"],
          "summary": "5–8 sentences: what it was about and how it went",
          "timeline": [{"time": "hh:mm:ss where this part starts", "title": "short name of the part", "summary": "one sentence"}],
          "keyPoints": ["the main ideas, as fits the kind"],
          "decisions": ["what was decided"],
          "tasks": [{"owner": "who", "task": "what", "due": "deadline or null", "time": "hh:mm:ss in the recording or null"}],
          "openQuestions": ["what stayed unclear or needs follow-up"],
          "assessment": {
            "score": 1-10 for how productive it was,
            "wentWell": ["…"],
            "wentWrong": ["going in circles, no agenda, unclear owners, running over time…"],
            "goalReached": "one sentence: was the goal reached?",
            "tips": ["2–3 concrete tips for the next meeting"]
          }
        }

        The timeline splits the whole recording into 4–12 parts in order, from the first minute to the end. \
        Only tasks actually agreed on (or assigned); empty lists are fine.

        Transcript:

        \(transcript)
        """

        var chat = ProjectChat(projectID: UUID(), provider: provider, model: ChatSettings.model(for: provider),
                               system: system, contextFingerprint: "")
        let client: ModelClient = provider == .claude ? ClaudeClient() : OpenAIClient(provider: provider)
        chat.messages = client.userMessages(text: request, contextUpdate: nil)
        let turn = try await client.turn(system: system, chat: chat, tools: [], apiKey: apiKey) { _ in }
        chat.messages.append(turn.message)
        let answer = ChatDisplayItem.items(for: chat).reversed().lazy.compactMap { item -> String? in
            if case .assistant(_, let text) = item { return text } else { return nil }
        }.first ?? ""
        do {
            return try parse(answer)
        } catch {
            // Kept next to the video, to see what the AI answered.
            try? answer.write(to: recording.deletingPathExtension().appendingPathExtension("review-answer.txt"), atomically: true, encoding: .utf8)
            if answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw ChatError(message: L("%@ sent an empty answer. Try Analyze Again or choose another model.", provider.title))
            }
            if turn.stopReason == "max_tokens" {
                throw ChatError(message: L("The review was cut off (the model's answer limit). Try Analyze Again or choose another model."))
            }
            throw error
        }
    }

    /// The JSON object in the answer (models sometimes wrap it in a code fence anyway).
    static func parse(_ answer: String) throws -> MeetingReview {
        guard let start = answer.firstIndex(of: "{"), let end = answer.lastIndex(of: "}"),
              let review = try? JSONDecoder().decode(MeetingReview.self, from: Data(answer[start...end].utf8)),
              !review.summary.isEmpty || !review.title.isEmpty
        else { throw ChatError(message: L("The review came back in an unexpected form. Try Analyze Again.")) }
        return review
    }

    /// The language most of the meeting was spoken in.
    static func mainLanguage(of utterances: [Utterance]) -> String {
        var weight: [String: Int] = [:]
        for utterance in utterances { weight[utterance.language ?? "en", default: 0] += utterance.text.count }
        return weight.max { $0.value < $1.value }?.key ?? "en"
    }
}

private extension KeyedDecodingContainer {
    /// Text, also from a number; nil for null, missing or empty.
    func text(_ key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value.isEmpty || value == "null" ? nil : value }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return String(format: "%g", value) }
        return nil
    }

    /// A list of texts; a single text becomes a list of one, objects are skipped.
    func texts(_ key: Key) -> [String] {
        if let values = try? decodeIfPresent([JSONValue].self, forKey: key) {
            return values.compactMap { $0.string ?? $0.int.map(String.init) }.filter { !$0.isEmpty }
        }
        return text(key).map { [$0] } ?? []
    }

    /// A whole number, also from "7", "7/10" or 7.5.
    func number(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return Int(value.rounded()) }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Double(value.prefix { $0.isNumber || $0 == "." }).map { Int($0.rounded()) }
        }
        return nil
    }
}
