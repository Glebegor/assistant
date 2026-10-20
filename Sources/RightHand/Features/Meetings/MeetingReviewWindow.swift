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
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 780, height: 720))
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
    @State private var review = ""
    @State private var transcript = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("", selection: $tab) {
                    Text("Review").tag(0)
                    Text("Transcript").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                Button("Open Video", systemImage: "play.rectangle") { NSWorkspace.shared.open(recording) }
                Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([recording]) }
                Button("Copy", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(tab == 0 ? review : transcript, forType: .string)
                }
                Button("Analyze Again", systemImage: "arrow.clockwise") { analyzer.analyze(recording) }
                    .disabled(analyzer.jobs[recording] != nil)
            }
            .labelStyle(.iconOnly)
            .padding(12)
            Divider()
            if let status = analyzer.jobs[recording] {
                AnalysisStatusView(status: status).padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Group {
                        if tab == 0 {
                            MarkdownDocument(text: review)
                        } else {
                            TranscriptView(text: transcript)
                        }
                    }
                    .textSelection(.enabled)
                    .frame(maxWidth: 720, alignment: .leading)
                    .padding(28)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: analyzer.revision) { _, _ in load() }
    }

    private func load() {
        review = (try? String(contentsOf: MeetingAnalyzer.reviewURL(for: recording), encoding: .utf8)) ?? ""
        transcript = (try? String(contentsOf: MeetingAnalyzer.transcriptURL(for: recording), encoding: .utf8)) ?? ""
    }
}

/// Progress of an analysis, in words.
struct AnalysisStatusView: View {
    let status: MeetingAnalyzer.Status

    var body: some View {
        VStack(spacing: 10) {
            switch status {
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(.orange)
                Text(message).multilineTextAlignment(.center)
            default:
                ProgressView(value: fraction).frame(width: 260)
                Text(title).font(.headline)
                Text(subtitle).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
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

/// "[00:12:04] Me: …" lines, with the speaker in colour.
private struct TranscriptView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                let parts = Self.split(line)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(verbatim: parts.time).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Text(verbatim: parts.speaker).fontWeight(.semibold)
                        .foregroundStyle(parts.speaker == L("Me") ? Color.cyan : Color.purple)
                        .frame(width: 90, alignment: .leading)
                    Text(verbatim: parts.text)
                }
            }
        }
    }

    static func split(_ line: String) -> (time: String, speaker: String, text: String) {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else { return ("", "", line) }
        let time = String(line[line.index(after: line.startIndex)..<close])
        let rest = line[line.index(after: close)...].trimmingCharacters(in: .whitespaces)
        guard let colon = rest.firstIndex(of: ":") else { return (time, "", rest) }
        return (time, String(rest[..<colon]), rest[rest.index(after: colon)...].trimmingCharacters(in: .whitespaces))
    }
}
