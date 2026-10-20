import SwiftUI

/// Record tab: which screen, which sound, start/stop, and the latest recordings.
struct RecorderView: View {
    let recorder: ScreenRecorder
    @State private var recordings: [URL] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if recorder.state == .idle {
                setup
            } else {
                progress
            }
            if let error = recorder.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange).lineLimit(3)
            }
            Divider().overlay(.white.opacity(0.1))
            recent
        }
        .task { await recorder.loadDisplays(); reloadRecordings() }
        .onChange(of: recorder.state) { _, _ in reloadRecordings() }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Picker("Screen", selection: Binding(get: { recorder.selectedDisplayID }, set: { recorder.selectedDisplayID = $0 })) {
                    ForEach(recorder.displays) { Text(verbatim: $0.name).tag($0.id) }
                }
                .labelsHidden()
                .fixedSize()
                switchPill("My voice", systemImage: recorder.recordsMicrophone ? "mic.fill" : "mic.slash", isOn: recorder.recordsMicrophone) {
                    recorder.recordsMicrophone.toggle()
                }
                switchPill("Computer sound", systemImage: recorder.recordsSystemAudio ? "speaker.wave.3.fill" : "speaker.slash.fill",
                           isOn: recorder.recordsSystemAudio) {
                    recorder.recordsSystemAudio.toggle()
                }
                Spacer()
            }
            HStack {
                Button { recorder.toggle() } label: {
                    Label("Start Recording", systemImage: "record.circle.fill")
                }
                .buttonStyle(.notchPill(prominent: true, tint: .red))
                .disabled(recorder.displays.isEmpty)
                Text(L("Up to %lld hours · about 1.5 GB per hour · voice and computer sound on separate tracks", Int(ScreenRecorder.maxDuration / 3600)))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }

    private func switchPill(_ title: LocalizedStringKey, systemImage: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: systemImage) }
            .buttonStyle(.notchPill(prominent: isOn, tint: .white))
            .help(isOn ? "Recorded on its own track" : "Not recorded")
    }

    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack(spacing: 14) {
                Circle().fill(.red).frame(width: 12, height: 12)
                    .opacity(recorder.state == .recording ? 1 : 0.4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.duration(recorder.elapsed)).font(.title2.monospacedDigit().weight(.semibold))
                    Text(L("%@ · stops at %lld:00:00", ByteCountFormatter.string(fromByteCount: recorder.fileSize, countStyle: .file),
                           Int(ScreenRecorder.maxDuration / 3600)))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { recorder.toggle() } label: {
                    Label(recorder.state == .stopping ? L("Saving…") : L("Stop"), systemImage: "stop.fill")
                }
                .buttonStyle(.notchPill(prominent: true, tint: .white))
                .disabled(recorder.state != .recording)
            }
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Recordings").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button("Open Folder") { recorder.showInFinder() }
                    .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
            }
            if recordings.isEmpty {
                Text("No recordings yet.").font(.caption).foregroundStyle(.tertiary)
            }
            ForEach(recordings.prefix(3), id: \.self) { url in
                Button { recorder.showInFinder(url) } label: {
                    HStack {
                        Image(systemName: "film").foregroundStyle(.secondary)
                        Text(verbatim: url.deletingPathExtension().lastPathComponent).lineLimit(1)
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0), countStyle: .file))
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func reloadRecordings() {
        let files = (try? FileManager.default.contentsOfDirectory(at: ScreenRecorder.folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        recordings = files.filter { $0.pathExtension == "mov" }
            .sorted { ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
                > ((try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
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
