import AppKit
import AVFoundation
import Observation
import ScreenCaptureKit

/// Records a screen with two separate audio tracks — your voice (microphone) and the Mac's sound
/// (the other people in a call) — for analysing meetings later. Sized for long recordings:
/// HEVC up to 1080p at ~3 Mbit/s, about 3 GB for two hours; stops by itself after four hours.
@Observable
@MainActor
final class ScreenRecorder: NSObject {
    enum State: Equatable {
        case idle, starting, recording, stopping
    }

    struct Display: Identifiable, Hashable {
        let id: CGDirectDisplayID
        let name: String
        let size: CGSize
    }

    static let maxDuration: TimeInterval = 4 * 3600
    static let folder: URL = {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
        return AppPaths.makeDirectory(movies.appending(path: "RightHand Recordings", directoryHint: .isDirectory))
    }()

    enum Key {
        static let display = "recorder.display"
        static let microphone = "recorder.microphone"
        static let systemAudio = "recorder.systemAudio"
    }

    private(set) var state: State = .idle
    private(set) var startedAt: Date?
    private(set) var fileSize: Int64 = 0
    private(set) var displays: [Display] = []
    private(set) var lastRecording: URL?
    var errorMessage: String?

    var selectedDisplayID: CGDirectDisplayID {
        didSet { UserDefaults.standard.set(Int(selectedDisplayID), forKey: Key.display) }
    }
    var recordsMicrophone: Bool {
        didSet { UserDefaults.standard.set(recordsMicrophone, forKey: Key.microphone) }
    }
    var recordsSystemAudio: Bool {
        didSet { UserDefaults.standard.set(recordsSystemAudio, forKey: Key.systemAudio) }
    }

    @ObservationIgnored private var stream: SCStream?
    @ObservationIgnored private var writer: RecordingWriter?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private let queue = DispatchQueue(label: "RightHand.ScreenRecorder")

    override init() {
        let defaults = UserDefaults.standard
        selectedDisplayID = CGDirectDisplayID(defaults.integer(forKey: Key.display))
        recordsMicrophone = defaults.object(forKey: Key.microphone) as? Bool ?? true
        recordsSystemAudio = defaults.object(forKey: Key.systemAudio) as? Bool ?? true
        super.init()
    }

    var isRecording: Bool { state == .recording }

    var elapsed: TimeInterval { startedAt.map { Date().timeIntervalSince($0) } ?? 0 }

    /// The screens you can record (asks for Screen Recording permission the first time).
    func loadDisplays() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            displays = content.displays.map { display in
                let name = NSScreen.screens.first { $0.displayID == display.displayID }?.localizedName ?? L("Display %lld", Int(display.displayID))
                return Display(id: display.displayID, name: name, size: CGSize(width: display.width, height: display.height))
            }
            if !displays.contains(where: { $0.id == selectedDisplayID }) {
                selectedDisplayID = NSScreen.main?.displayID ?? displays.first?.id ?? 0
            }
            errorMessage = nil
        } catch {
            errorMessage = L("Allow Screen Recording for RightHand in System Settings → Privacy & Security → Screen & System Audio Recording, then try again.")
        }
    }

    func toggle() {
        switch state {
        case .idle: Task { await start() }
        case .recording: Task { await stop() }
        case .starting, .stopping: break
        }
    }

    func start() async {
        guard state == .idle else { return }
        state = .starting
        errorMessage = nil
        do {
            if recordsMicrophone, !(await AVCaptureDevice.requestAccess(for: .audio)) {
                recordsMicrophone = false
            }
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == selectedDisplayID }) ?? content.displays.first else {
                throw ChatError(message: L("No screen to record."))
            }
            // RightHand's own windows (the notch) stay out of the video.
            let ownApp = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])

            let size = Self.videoSize(for: CGSize(width: display.width, height: display.height))
            let configuration = SCStreamConfiguration()
            configuration.width = Int(size.width)
            configuration.height = Int(size.height)
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(RecordingWriter.frameRate))
            configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            configuration.showsCursor = true
            configuration.queueDepth = 6
            configuration.capturesAudio = recordsSystemAudio
            configuration.excludesCurrentProcessAudio = true // not Ellipse's own voice
            configuration.sampleRate = 48_000
            configuration.channelCount = 2
            if #available(macOS 15, *) {
                configuration.captureMicrophone = recordsMicrophone
                if let microphone = Microphones.selected { configuration.microphoneCaptureDeviceID = microphone.id }
            } else {
                recordsMicrophone = false // the microphone track needs macOS 15
            }

            let url = Self.folder.appending(path: Self.fileName())
            let writer = try RecordingWriter(url: url, videoSize: size, microphone: recordsMicrophone,
                                             systemAudio: recordsSystemAudio, queue: queue)
            let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
            try stream.addStreamOutput(writer, type: .screen, sampleHandlerQueue: queue)
            if recordsSystemAudio { try stream.addStreamOutput(writer, type: .audio, sampleHandlerQueue: queue) }
            if #available(macOS 15, *), recordsMicrophone {
                try stream.addStreamOutput(writer, type: .microphone, sampleHandlerQueue: queue)
            }
            try await stream.startCapture()

            self.stream = stream
            self.writer = writer
            startedAt = Date()
            fileSize = 0
            state = .recording
            NSSound(named: "Tink")?.play()
            ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        } catch {
            state = .idle
            errorMessage = (error as? ChatError)?.message ?? L("Couldn't start recording: %@", error.localizedDescription)
        }
    }

    func stop() async {
        guard state == .recording, let stream, let writer else { return }
        state = .stopping
        ticker?.invalidate()
        ticker = nil
        try? await stream.stopCapture()
        let url = await writer.finish()
        self.stream = nil
        self.writer = nil
        startedAt = nil
        state = .idle
        if let url {
            lastRecording = url
            NSSound(named: "Pop")?.play()
            Notifier.shared.notify(title: L("Recording saved"), body: url.lastPathComponent, playsSound: false)
        } else {
            errorMessage = L("The recording couldn't be saved.")
        }
    }

    func showInFinder(_ url: URL? = nil) {
        if let url = url ?? lastRecording {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(Self.folder)
        }
    }

    private func tick() {
        if let url = writer?.url, let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            fileSize = Int64(size)
        }
        if elapsed >= Self.maxDuration { Task { await stop() } }
    }

    /// At most 1920 pixels wide (1080p), even sides; small screens keep their size.
    nonisolated static func videoSize(for display: CGSize) -> CGSize {
        let scale = min(1, 1920 / max(display.width, 1))
        func even(_ value: CGFloat) -> CGFloat { CGFloat(Int(value * scale) / 2 * 2) }
        return CGSize(width: even(display.width), height: even(display.height))
    }

    private static func fileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Recording \(formatter.string(from: Date())).mov"
    }
}

extension ScreenRecorder: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            guard self.state == .recording else { return }
            self.errorMessage = L("Recording stopped: %@", error.localizedDescription)
            await self.stop()
        }
    }
}

/// Writes the samples to a .mov file: one HEVC video track and up to two AAC audio tracks,
/// named "My voice" and "Computer sound". Used only on the recorder's queue.
final class RecordingWriter: NSObject, SCStreamOutput, @unchecked Sendable {
    static let frameRate = 20
    /// ~3 Mbit/s video + 64 kbit/s voice + 96 kbit/s computer sound: 2.5–3.3 GB for 2 hours.
    static let videoBitRate = 3_000_000

    let url: URL
    /// The queue the samples arrive on; all state below is only touched there.
    private let queue: DispatchQueue
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let microphone: AVAssetWriterInput?
    private let systemAudio: AVAssetWriterInput?
    private var sessionStarted = false
    private var finished = false

    init(url: URL, videoSize: CGSize, microphone recordsMicrophone: Bool, systemAudio recordsSystemAudio: Bool,
         queue: DispatchQueue) throws {
        self.url = url
        self.queue = queue
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        // Saves what's recorded so far every 10 seconds, so a crash doesn't lose the meeting.
        writer.movieFragmentInterval = CMTime(seconds: 10, preferredTimescale: 600)

        video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: Int(videoSize.width),
            AVVideoHeightKey: Int(videoSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: Self.videoBitRate,
                AVVideoExpectedSourceFrameRateKey: Self.frameRate,
                AVVideoMaxKeyFrameIntervalKey: Self.frameRate * 4,
            ],
        ])
        video.expectsMediaDataInRealTime = true
        writer.add(video)

        func audioInput(channels: Int, bitRate: Int, name: String) -> AVAssetWriterInput {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: bitRate,
            ])
            input.expectsMediaDataInRealTime = true
            let title = AVMutableMetadataItem()
            title.identifier = .quickTimeUserDataTrackName
            title.value = name as NSString
            input.metadata = [title]
            return input
        }
        microphone = recordsMicrophone ? audioInput(channels: 1, bitRate: 64_000, name: "My voice") : nil
        systemAudio = recordsSystemAudio ? audioInput(channels: 2, bitRate: 96_000, name: "Computer sound") : nil
        for input in [microphone, systemAudio].compactMap({ $0 }) { writer.add(input) }
        super.init()
        guard writer.startWriting() else { throw writer.error ?? ChatError(message: "Can't write \(url.lastPathComponent)") }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !finished, buffer.isValid, writer.status == .writing else { return }
        switch type {
        case .screen:
            // Only complete frames carry pixels (idle screens send "nothing changed" frames).
            guard let info = (CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]])?.first,
                  let raw = info[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete else { return }
            appendVideo(buffer)
        case .audio:
            appendAudio(buffer, microphone: false)
        default:
            appendAudio(buffer, microphone: true) // the microphone (macOS 15+)
        }
    }

    /// A complete screen frame. The file starts at the first one.
    func appendVideo(_ buffer: CMSampleBuffer) {
        guard !finished, writer.status == .writing else { return }
        if !sessionStarted {
            writer.startSession(atSourceTime: buffer.presentationTimeStamp)
            sessionStarted = true
        }
        if video.isReadyForMoreMediaData { video.append(buffer) }
    }

    func appendAudio(_ buffer: CMSampleBuffer, microphone fromMicrophone: Bool) {
        guard !finished, sessionStarted, writer.status == .writing, let input = fromMicrophone ? microphone : systemAudio,
              input.isReadyForMoreMediaData else { return }
        input.append(buffer)
    }

    /// Closes the file; nil if nothing could be saved.
    func finish() async -> URL? {
        let canFinish: Bool = await withCheckedContinuation { continuation in
            queue.async { [self] in
                finished = true
                continuation.resume(returning: sessionStarted)
            }
        }
        guard canFinish else {
            writer.cancelWriting()
            return nil
        }
        video.markAsFinished()
        microphone?.markAsFinished()
        systemAudio?.markAsFinished()
        await writer.finishWriting()
        return writer.status == .completed ? url : nil
    }
}
