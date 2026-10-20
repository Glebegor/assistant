import AppKit
import SwiftUI

/// A window with a meeting's review and transcript.
@MainActor
final class MeetingReviewWindowController: NSObject, NSWindowDelegate {
    private var windows: [URL: NSWindow] = [:]
    private let analyzer: MeetingAnalyzer

    init(analyzer: MeetingAnalyzer) {
        self.analyzer = analyzer
    }

    func show(_ recording: URL) {
        let window = windows[recording] ?? {
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: MeetingReviewView(recording: recording, analyzer: analyzer)
            ))
            window.title = recording.deletingPathExtension().lastPathComponent
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.appearance = NSAppearance(named: .darkAqua)
            window.isMovableByWindowBackground = true
            window.setContentSize(NSSize(width: 820, height: 760))
            window.minSize = NSSize(width: 520, height: 400)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            windows[recording] = window
            return window
        }()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closing = notification.object as? NSWindow else { return }
        windows = windows.filter { $0.value !== closing }
        AppWindows.leaveDockIfNoWindows(except: closing)
    }
}

enum AppWindows {
    /// RightHand shows a Dock icon while one of its normal windows is open.
    @MainActor
    static func leaveDockIfNoWindows(except closing: NSWindow) {
        let others = NSApp.windows.contains { $0 !== closing && $0.isVisible && $0.styleMask.contains(.titled) && !($0 is NSPanel) }
        if !others { NSApp.setActivationPolicy(.accessory) }
    }
}

struct MeetingReviewView: View {
    let recording: URL
    let analyzer: MeetingAnalyzer
    @State private var tab = 0
    @State private var review: MeetingReview?
    @State private var markdown = ""
    @State private var transcript = ""
    @State private var search = ""

    var body: some View {
        ZStack {
            Theme.background
            VStack(spacing: 0) {
                header
                Rectangle().fill(Theme.hairline).frame(height: 1)
                if let status = analyzer.jobs[recording] {
                    AnalysisStatusView(status: status).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        Group {
                            if tab == 0 {
                                if let review { ReviewCards(review: review) } else { MarkdownDocument(text: markdown) }
                            } else {
                                TranscriptView(text: transcript, search: search)
                            }
                        }
                        .textSelection(.enabled)
                        .frame(maxWidth: 760, alignment: .leading)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 26)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.never)
                }
            }
        }
        .foregroundStyle(.white)
        .onAppear(perform: load)
        .onChange(of: analyzer.revision) { _, _ in load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: review?.title ?? recording.deletingPathExtension().lastPathComponent)
                        .font(.system(size: 26, weight: .semibold))
                        .lineLimit(2)
                    Text(verbatim: meta).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if let score = review?.assessment.score { ScoreRing(score: score) }
            }
            HStack(spacing: 4) {
                NeonTabs(tabs: [(0, "Review"), (1, "Transcript")], selection: $tab)
                Spacer()
                if tab == 1 {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Search", text: $search).textFieldStyle(.plain).frame(width: 150)
                    }
                    .font(.callout)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.white.opacity(0.06), in: Capsule())
                    .padding(.trailing, 6)
                }
                IconButton(title: "Open Video", systemImage: "play.fill") { NSWorkspace.shared.open(recording) }
                IconButton(title: "Show in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([recording]) }
                IconButton(title: "Copy", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(tab == 0 ? (review?.markdown ?? markdown) : transcript, forType: .string)
                }
                if analyzer.jobs[recording] == nil {
                    IconButton(title: "Analyze Again", systemImage: "arrow.clockwise") { analyzer.analyze(recording) }
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 38)
        .padding(.bottom, 0)
    }

    private var meta: String {
        let values = try? recording.resourceValues(forKeys: [.creationDateKey])
        var parts = [(values?.creationDate ?? Date()).formatted(date: .long, time: .shortened)]
        if let people = review?.participants, !people.isEmpty { parts.append(people.joined(separator: ", ")) }
        return parts.joined(separator: "  ·  ")
    }

    private func load() {
        review = MeetingReview.load(for: recording)
        markdown = (try? String(contentsOf: MeetingAnalyzer.reviewURL(for: recording), encoding: .utf8)) ?? ""
        transcript = (try? String(contentsOf: MeetingAnalyzer.transcriptURL(for: recording), encoding: .utf8)) ?? ""
    }
}

/// The review as quiet cards: summary, decisions and questions, tasks, assessment.
private struct ReviewCards: View {
    let review: MeetingReview

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 10) {
                ThemeCaption("Summary")
                Text(verbatim: review.summary).font(.system(size: 15)).lineSpacing(5).foregroundStyle(.white.opacity(0.92))
            }

            HStack(alignment: .top, spacing: 14) {
                listCard("Decisions", items: review.decisions, icon: "checkmark", tint: Theme.neon)
                listCard("Open questions", items: review.openQuestions, icon: "questionmark", tint: Theme.violet)
            }

            VStack(alignment: .leading, spacing: 10) {
                ThemeCaption("Tasks")
                if review.tasks.isEmpty {
                    Text("No tasks were agreed on.").foregroundStyle(.secondary).themeCard()
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(review.tasks.enumerated()), id: \.offset) { index, task in
                            if index > 0 { Rectangle().fill(Theme.hairline).frame(height: 1) }
                            TaskLine(task: task).padding(.vertical, 10)
                        }
                    }
                    .themeCard(padding: 14)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ThemeCaption("Assessment")
                VStack(alignment: .leading, spacing: 16) {
                    Text(verbatim: review.assessment.goalReached).font(.system(size: 14, weight: .medium))
                    HStack(alignment: .top, spacing: 24) {
                        bullets("What went well", review.assessment.wentWell, dot: .green)
                        bullets("What didn't", review.assessment.wentWrong, dot: .orange)
                    }
                    if !review.assessment.tips.isEmpty {
                        Rectangle().fill(Theme.hairline).frame(height: 1)
                        bullets("Next time", review.assessment.tips, dot: Theme.neon)
                    }
                }
                .themeCard()
            }
        }
    }

    private func listCard(_ title: LocalizedStringKey, items: [String], icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ThemeCaption(title)
            VStack(alignment: .leading, spacing: 10) {
                if items.isEmpty { Text(verbatim: "—").foregroundStyle(.tertiary) }
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(tint)
                        Text(verbatim: item).font(.system(size: 13.5)).foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
            .themeCard(padding: 14)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func bullets(_ title: LocalizedStringKey, _ items: [String], dot: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            if items.isEmpty { Text(verbatim: "—").foregroundStyle(.tertiary) }
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(dot).frame(width: 5, height: 5).offset(y: -2)
                    Text(verbatim: item).font(.system(size: 13.5)).foregroundStyle(.white.opacity(0.88))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One task: who (a small initial), what, and when.
private struct TaskLine: View {
    let task: MeetingReview.Task

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(verbatim: String(task.owner.prefix(1)).uppercased())
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(Theme.neonSoft, in: Circle())
                .overlay(Circle().strokeBorder(Theme.neon.opacity(0.5), lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: task.task).font(.system(size: 13.5)).foregroundStyle(.white.opacity(0.92))
                Text(verbatim: task.owner).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let due = task.due, !due.isEmpty {
                Label { Text(verbatim: due) } icon: { Image(systemName: "calendar") }
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let time = task.time, !time.isEmpty {
                Text(verbatim: time).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.white.opacity(0.06), in: Capsule())
            }
        }
    }
}

/// The meeting's score in a thin neon ring.
private struct ScoreRing: View {
    let score: Int

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: 3)
            Circle().trim(from: 0, to: CGFloat(min(max(score, 0), 10)) / 10)
                .stroke(Theme.neon, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .neonGlow(radius: 5)
            VStack(spacing: -2) {
                Text(verbatim: "\(score)").font(.system(size: 20, weight: .semibold, design: .rounded))
                Text(verbatim: "/10").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 58, height: 58)
        .help("How productive the meeting was")
    }
}

/// Progress of an analysis: three steps and a thin neon ring.
struct AnalysisStatusView: View {
    let status: MeetingAnalyzer.Status

    var body: some View {
        VStack(spacing: 22) {
            if case .failed(let message) = status {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 30, weight: .light)).foregroundStyle(.orange)
                Text(message).multilineTextAlignment(.center).frame(maxWidth: 420)
            } else {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.07), lineWidth: 3)
                    if let fraction {
                        Circle().trim(from: 0, to: fraction)
                            .stroke(Theme.neon, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .neonGlow(radius: 6)
                            .animation(.easeInOut, value: fraction)
                        Text(verbatim: "\(Int(fraction * 100))%").font(.system(size: 18, weight: .medium, design: .rounded).monospacedDigit())
                    } else {
                        ProgressView().controlSize(.regular)
                    }
                }
                .frame(width: 92, height: 92)
                VStack(spacing: 6) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    Text(subtitle).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 400)
                }
                HStack(spacing: 18) {
                    step("Model", done: stepIndex > 0, active: stepIndex == 0)
                    step("Transcript", done: stepIndex > 1, active: stepIndex == 1)
                    step("Review", done: false, active: stepIndex == 2)
                }
            }
        }
        .padding(40)
    }

    private var stepIndex: Int {
        switch status {
        case .queued, .downloadingModel, .loadingModel: 0
        case .transcribing: 1
        case .reviewing: 2
        case .failed: 0
        }
    }

    private func step(_ title: LocalizedStringKey, done: Bool, active: Bool) -> some View {
        HStack(spacing: 6) {
            Circle().fill(done || active ? Theme.neon : Color.white.opacity(0.15)).frame(width: 6, height: 6)
                .neonGlow(active, radius: 4)
            Text(title).font(.caption).foregroundStyle(active ? .primary : .secondary)
        }
    }

    var fraction: Double? {
        switch status {
        case .downloadingModel(let value), .transcribing(let value): value
        default: nil
        }
    }

    var title: String { Self.title(of: status) }

    private var subtitle: String {
        switch status {
        case .downloadingModel: L("Only the first time: the speech model (630 MB) is downloaded to your Mac.")
        case .loadingModel: L("Preparing the speech model. The first time this takes a few minutes.")
        case .transcribing: L("Whisper listens on your Mac: about 15–20 minutes for a two-hour meeting.")
        case .reviewing: L("%@ is writing the review from the transcript.", ChatSettings.provider.title)
        default: ""
        }
    }

    static func title(of status: MeetingAnalyzer.Status) -> String {
        switch status {
        case .queued: L("Waiting…")
        case .downloadingModel(let value): L("Downloading speech model… %lld%%", Int(value * 100))
        case .loadingModel: L("Loading speech model…")
        case .transcribing(let value): L("Transcribing… %lld%%", Int(value * 100))
        case .reviewing: L("Writing the review…")
        case .failed: L("Failed")
        }
    }
}

/// Headings, bullet lists and paragraphs of a Markdown review, with bold and italics.
struct MarkdownDocument: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                lineView(line)
            }
        }
    }

    @ViewBuilder
    private func lineView(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("# ") {
            Text(inline(String(trimmed.dropFirst(2)))).font(.largeTitle.weight(.bold)).padding(.bottom, 2)
        } else if trimmed.hasPrefix("## ") {
            Text(inline(String(trimmed.dropFirst(3)))).font(.title2.weight(.semibold)).padding(.top, 12)
        } else if trimmed.hasPrefix("### ") {
            Text(inline(String(trimmed.dropFirst(4)))).font(.headline).padding(.top, 6)
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: "•").foregroundStyle(.secondary)
                Text(inline(String(trimmed.dropFirst(2))))
            }
            .padding(.leading, line.prefix { $0 == " " }.count >= 2 ? 20 : 4)
        } else if trimmed.isEmpty {
            Color.clear.frame(height: 2)
        } else {
            Text(inline(trimmed))
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

/// The transcript as a calm conversation: consecutive lines of one speaker are grouped.
private struct TranscriptView: View {
    let text: String
    let search: String

    private struct Turn: Identifiable {
        let id: Int
        let time: String
        let speaker: String
        var lines: [String]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if turns.isEmpty { Text(search.isEmpty ? "No transcript yet." : "Nothing found.").foregroundStyle(.secondary) }
            ForEach(turns) { turn in
                let isMe = turn.speaker == L("Me")
                HStack(alignment: .top, spacing: 14) {
                    Text(verbatim: turn.time).font(.system(size: 11).monospacedDigit()).foregroundStyle(.tertiary)
                        .frame(width: 56, alignment: .leading).padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Circle().fill(isMe ? Theme.neon : Theme.violet).frame(width: 6, height: 6)
                            Text(verbatim: turn.speaker).font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(isMe ? Theme.neon : Theme.violet)
                        }
                        Text(verbatim: turn.lines.joined(separator: " "))
                            .font(.system(size: 14)).lineSpacing(3).foregroundStyle(.white.opacity(0.9))
                    }
                }
            }
        }
    }

    private var turns: [Turn] {
        var result: [Turn] = []
        for line in text.components(separatedBy: "\n") where !line.isEmpty {
            if !search.isEmpty, !line.localizedCaseInsensitiveContains(search) { continue }
            let parts = Self.split(line)
            if search.isEmpty, let last = result.last, last.speaker == parts.speaker {
                result[result.count - 1].lines.append(parts.text)
            } else {
                result.append(Turn(id: result.count, time: parts.time, speaker: parts.speaker, lines: [parts.text]))
            }
        }
        return result
    }

    static func split(_ line: String) -> (time: String, speaker: String, text: String) {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return ("", "", line) }
        let time = String(line[line.index(after: line.startIndex)..<close])
        let rest = line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
        guard let colon = rest.firstIndex(of: ":") else { return (time, "", rest) }
        return (time, String(rest[..<colon]), rest[rest.index(after: colon)...].trimmingCharacters(in: .whitespaces))
    }
}
