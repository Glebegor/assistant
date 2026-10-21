import AVFoundation
import SwiftUI

/// Record tab: a big record button, the three sources (screen, your voice, computer sound),
/// and the latest recordings.
struct RecorderView: View {
    let recorder: ScreenRecorder
    let analyzer: MeetingAnalyzer
    let openReview: (URL) -> Void
    @State private var recordings: [Recording] = []
    @State private var microphoneRevision = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                RecordButton(recorder: recorder)
                if recorder.state == .idle {
                    sources
                } else {
                    progress
                }
            }
            if let error = recorder.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange).lineLimit(2)
            }
            recent
        }
        .padding(.top, 4)
        .task {
            await recorder.loadDisplays()
            await reloadRecordings()
        }
        .onChange(of: recorder.state) { _, state in
            if state == .idle { Task { await reloadRecordings() } }
        }
    }

    // MARK: Sources

    private var sources: some View {
        HStack(spacing: 8) {
            SourceTile(title: "Screen", detail: selectedDisplayName, systemImage: "display", isOn: true, tint: .blue) {
                Menu {
                    ForEach(recorder.displays) { display in
                        Button { recorder.selectedDisplayID = display.id } label: {
                            if display.id == recorder.selectedDisplayID { Label(display.name, systemImage: "checkmark") } else { Text(display.name) }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.bold))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .disabled(recorder.displays.count < 2)
            }
            Button { recorder.recordsMicrophone.toggle() } label: {
                SourceTile(title: "My voice", detail: recorder.recordsMicrophone ? Microphones.selectedName : L("Off"),
                           systemImage: recorder.recordsMicrophone ? "mic.fill" : "mic.slash.fill",
                           isOn: recorder.recordsMicrophone, tint: .cyan) {
                    Menu {
                        Button { Microphones.selectedID = ""; microphoneRevision += 1 } label: {
                            if Microphones.selectedID.isEmpty { Label("Mac default", systemImage: "checkmark") } else { Text("Mac default") }
                        }
                        Divider()
                        ForEach(Microphones.all) { device in
                            Button { Microphones.selectedID = device.id; microphoneRevision += 1 } label: {
                                if device.id == Microphones.selectedID { Label(device.name, systemImage: "checkmark") } else { Text(device.name) }
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.bold))
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Choose the microphone")
                }
                .id(microphoneRevision)
            }
            .buttonStyle(.plain)
            .help("Your microphone, on its own track")
            Button { recorder.recordsSystemAudio.toggle() } label: {
                SourceTile(title: "Computer sound", detail: recorder.recordsSystemAudio ? L("Own track") : L("Off"),
                           systemImage: recorder.recordsSystemAudio ? "speaker.wave.2.fill" : "speaker.slash.fill",
                           isOn: recorder.recordsSystemAudio, tint: .purple) { EmptyView() }
            }
            .buttonStyle(.plain)
            .help("What you hear: the other people in a call, videos…, on its own track")
        }
    }

    private var selectedDisplayName: String {
        recorder.displays.first { $0.id == recorder.selectedDisplayID }?.name ?? L("Main screen")
    }

    // MARK: Recording

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let fraction = min(1, recorder.elapsed / ScreenRecorder.maxDuration)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Self.duration(recorder.elapsed))
                        .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: recorder.fileSize, countStyle: .file))
                        .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                }
                // How much of the 4-hour limit is used.
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.12))
                        Capsule().fill(.red.gradient).frame(width: max(6, geometry.size.width * fraction))
                    }
                }
                .frame(height: 6)
                HStack(spacing: 10) {
                    if recorder.recordsMicrophone { Label("My voice", systemImage: "mic.fill") }
                    if recorder.recordsSystemAudio { Label("Computer sound", systemImage: "speaker.wave.2.fill") }
                    Spacer()
                    Text(recorder.state == .stopping ? L("Saving…") : L("Stops by itself at %lld:00:00", Int(ScreenRecorder.maxDuration / 3600)))
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Recordings

    private var recent: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Recent").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { recorder.showInFinder() } label: {
                    Label("Open Folder", systemImage: "folder").labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            }
            if recordings.isEmpty {
                Text("Your recordings will appear here. They're saved in Movies → RightHand Recordings.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .padding(.vertical, 6)
            } else {
                ForEach(recordings.prefix(2)) { recording in
                    RecordingRow(recording: recording, analyzer: analyzer, openReview: openReview) { recorder.showInFinder(recording.url) }
                }
            }
        }
        .padding(10)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func reloadRecordings() async {
        let keys: [URLResourceKey] = [.creationDateKey, .fileSizeKey]
        let files = ((try? FileManager.default.contentsOfDirectory(at: ScreenRecorder.folder, includingPropertiesForKeys: keys)) ?? [])
            .filter { $0.pathExtension == "mov" }
        var list: [Recording] = []
        for url in files {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let duration = (try? await AVURLAsset(url: url).load(.duration).seconds) ?? 0
            list.append(Recording(url: url, date: values?.creationDate ?? .distantPast,
                                  size: Int64(values?.fileSize ?? 0), duration: duration.isFinite ? duration : 0))
        }
        recordings = list.sorted { $0.date > $1.date }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
    }
}

struct Recording: Identifiable {
    let url: URL
    let date: Date
    let size: Int64
    let duration: TimeInterval
    var id: URL { url }
}

/// The round record button: a red dot to start, a red square to stop.
private struct RecordButton: View {
    let recorder: ScreenRecorder
    @State private var isHovered = false

    var body: some View {
        let isActive = recorder.state != .idle
        Button { recorder.toggle() } label: {
            ZStack {
                Circle().strokeBorder(.white.opacity(isHovered ? 0.9 : 0.6), lineWidth: 3)
                if isActive {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.red).frame(width: 26, height: 26)
                } else {
                    Circle().fill(.red.gradient).padding(7)
                }
                if recorder.state == .starting || recorder.state == .stopping {
                    ProgressView().controlSize(.small).tint(.white)
                }
            }
            .frame(width: 64, height: 64)
            .contentShape(Circle())
            .scaleEffect(isHovered ? 1.04 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: isActive)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .disabled(recorder.state == .starting || recorder.state == .stopping || (!isActive && recorder.displays.isEmpty))
        .help(isActive ? "Stop recording" : "Start recording")
    }
}

/// One source: an icon, a name and what it does; lit when it's recorded.
private struct SourceTile<Accessory: View>: View {
    let title: LocalizedStringKey
    let detail: String
    let systemImage: String
    let isOn: Bool
    let tint: Color
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isOn ? tint : .secondary)
                    .frame(width: 22, height: 22)
                Spacer(minLength: 0)
                accessory()
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.semibold)).lineLimit(1)
                Text(verbatim: detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 70)
        .background(isOn ? tint.opacity(0.16) : .white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(isOn ? tint.opacity(0.45) : .white.opacity(0.08)))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct RecordingRow: View {
    let recording: Recording
    let analyzer: MeetingAnalyzer
    let openReview: (URL) -> Void
    let reveal: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: reveal) {
            HStack(spacing: 8) {
                Image(systemName: "film.fill").foregroundStyle(.secondary)
                Text(recording.date.formatted(.relative(presentation: .named)).capitalized(with: .current))
                    .lineLimit(1)
                Text(recording.date.formatted(date: .omitted, time: .shortened)).foregroundStyle(.secondary)
                Spacer()
                Text(RecorderView.duration(recording.duration)).monospacedDigit().foregroundStyle(.secondary)
                Text(ByteCountFormatter.string(fromByteCount: recording.size, countStyle: .file))
                    .monospacedDigit().foregroundStyle(.secondary).frame(width: 64, alignment: .trailing)
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).opacity(isHovered ? 1 : 0)
                analysis
            }
            .font(.caption)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Show in Finder")
    }

    /// Analyze → progress → Review.
    @ViewBuilder
    private var analysis: some View {
        if let status = analyzer.jobs[recording.url] {
            HStack(spacing: 5) {
                if case .failed = status {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                } else {
                    ProgressView().controlSize(.mini)
                }
                Text(AnalysisStatusView.title(of: status)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(width: 150, alignment: .trailing)
            .onTapGesture { openReview(recording.url) }
            .help(status == .reviewing ? "" : "Open")
        } else if analyzer.hasReview(recording.url) {
            Button { openReview(recording.url) } label: { Label("Review", systemImage: "doc.text.magnifyingglass") }
                .buttonStyle(.notchPill(prominent: true, tint: .white))
                .help("Open the meeting review")
        } else {
            AnalyzeMenu(analyzer: analyzer, recording: recording.url) { openReview(recording.url) }
                .font(.caption)
        }
    }
}

/// The red dot and running time on the closed notch while recording.
struct RecordingIndicator: View {
    let recorder: ScreenRecorder

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            HStack(spacing: 6) {
                Circle().fill(.red).frame(width: 8, height: 8)
                    .opacity(Int(timeline.date.timeIntervalSinceReferenceDate) % 2 == 0 ? 1 : 0.45)
                Text(RecorderView.duration(recorder.elapsed))
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
            }
        }
    }
}
