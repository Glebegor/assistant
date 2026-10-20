import AppKit
import Observation

/// Checks GitHub for a newer RightHand release, and installs it on request: downloads the zip,
/// signs the new app with your local certificate (so macOS keeps its permissions), replaces the
/// app in Applications and starts it again.
@Observable
@MainActor
final class Updater {
    static let shared = Updater()

    struct Release: Equatable {
        let version: String
        let notes: String
        let download: URL
        let page: URL
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading(Double)
        case installing
        case failed(String)
    }

    static let repository = "Glebegor/assistant"
    private static let skippedKey = "updates.skippedVersion"
    static let autoCheckKey = "updates.checkAutomatically"

    private(set) var state: State = .idle
    private(set) var lastChecked: Date?

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var notifiedVersion: String?

    static var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0" }
    static var checksAutomatically: Bool { UserDefaults.standard.object(forKey: autoCheckKey) as? Bool ?? true }

    var available: Release? { if case .available(let release) = state { release } else { nil } }

    /// Checks shortly after launch and then every six hours.
    func startChecking() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            Task { await self?.check(quietly: true) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.check(quietly: true) }
        }
    }

    /// `quietly`: the automatic check only speaks up when there is something new.
    func check(quietly: Bool = false) async {
        if quietly, !Self.checksAutomatically { return }
        switch state {
        case .checking, .downloading, .installing: return
        default: break
        }
        if !quietly { state = .checking }
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 20
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let json = JSONValue.parse(data), let tag = json["tag_name"]?.string else {
                throw ChatError(message: L("Couldn't read the latest release from GitHub."))
            }
            lastChecked = Date()
            let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let zip = (json["assets"]?.array ?? []).first { $0["name"]?.string?.hasSuffix(".zip") == true }
            guard Self.isNewer(version, than: Self.currentVersion),
                  let download = zip?["browser_download_url"]?.string.flatMap(URL.init(string:)) else {
                if !quietly || available == nil { state = .upToDate }
                return
            }
            if quietly, UserDefaults.standard.string(forKey: Self.skippedKey) == version { return }
            let release = Release(version: version, notes: json["body"]?.string ?? "", download: download,
                                  page: json["html_url"]?.string.flatMap(URL.init(string:)) ?? URL(string: "https://github.com/\(Self.repository)/releases")!)
            state = .available(release)
            if notifiedVersion != version {
                notifiedVersion = version
                Notifier.shared.notify(title: L("RightHand %@ is available", version),
                                       body: L("Install it from the ✋ menu or Settings → About."), playsSound: false)
            }
        } catch {
            if !quietly { state = .failed(error.localizedDescription) }
        }
    }

    func skip(_ release: Release) {
        UserDefaults.standard.set(release.version, forKey: Self.skippedKey)
        state = .upToDate
    }

    /// Asks with the release notes, then installs.
    func offer(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = L("RightHand %@ is available", release.version)
        alert.informativeText = L("You have %@. RightHand downloads the new version, replaces itself in Applications and starts again.", Self.currentVersion)
        if !release.notes.isEmpty {
            let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 180))
            text.string = release.notes
            text.isEditable = false
            text.font = .systemFont(ofSize: 12)
            let scroll = NSScrollView(frame: text.frame)
            scroll.documentView = text
            scroll.hasVerticalScroller = true
            scroll.borderType = .bezelBorder
            alert.accessoryView = scroll
        }
        alert.addButton(withTitle: L("Install and Restart"))
        alert.addButton(withTitle: L("Later"))
        alert.addButton(withTitle: L("Skip This Version"))
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn: Task { await install(release) }
        case .alertThirdButtonReturn: skip(release)
        default: break
        }
    }

    // MARK: Installing

    /// `target` and `relaunch` are only changed by tests.
    func install(_ release: Release, target: URL = Bundle.main.bundleURL, relaunch: Bool = true) async {
        state = .downloading(0)
        do {
            let folder = FileManager.default.temporaryDirectory.appending(path: "RightHand-update-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let zip = try await download(release.download, to: folder.appending(path: "RightHand.zip"))

            state = .installing
            try run("/usr/bin/ditto", ["-x", "-k", zip.path, folder.appending(path: "unzipped").path])
            guard let app = FileManager.default.enumerator(at: folder.appending(path: "unzipped"), includingPropertiesForKeys: nil)?
                    .compactMap({ $0 as? URL }).first(where: { $0.pathExtension == "app" }),
                  Bundle(url: app)?.bundleIdentifier == "com.hlibarseniuk.RightHand"
            else { throw ChatError(message: L("The download doesn't contain RightHand.")) }

            // Same signature as the app you have, so macOS keeps microphone, screen and file permissions.
            _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
            if (try? run("/usr/bin/security", ["find-certificate", "-c", "RightHand Local Signing"])) != nil {
                _ = try? run("/usr/bin/codesign", ["--force", "--deep", "--sign", "RightHand Local Signing", app.path])
            }

            _ = try FileManager.default.replaceItemAt(target, withItemAt: app, backupItemName: "RightHand-old.app",
                                                      options: .usingNewMetadataOnly)
            if relaunch { restart(target) } else { state = .idle }
        } catch {
            state = .failed(L("Couldn't install the update: %@", error.localizedDescription))
        }
    }

    private func download(_ url: URL, to destination: URL) async throws -> URL {
        // Show progress while it downloads.
        let watcher = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let task = self.downloading, case .downloading = self.state else { return }
                self.state = .downloading(task.progress.fractionCompleted)
            }
        }
        defer {
            watcher.invalidate()
            downloading = nil
        }
        return try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.downloadTask(with: url) { location, response, error in
                if let error { return continuation.resume(throwing: error) }
                guard let location, (response as? HTTPURLResponse)?.statusCode == 200 else {
                    return continuation.resume(throwing: ChatError(message: L("The download failed.")))
                }
                // The temporary file disappears when this returns: move it now.
                do {
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.moveItem(at: location, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            downloading = task
            task.resume()
        }
    }

    @ObservationIgnored private var downloading: URLSessionDownloadTask?

    @discardableResult
    private func run(_ tool: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ChatError(message: "\(URL(filePath: tool).lastPathComponent) failed") }
        return process.terminationStatus
    }

    private func restart(_ app: URL) {
        let relaunch = Process()
        relaunch.executableURL = URL(filePath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", app.path]
        try? relaunch.run()
        NSApp.terminate(nil)
    }

    /// "0.10.0" is newer than "0.9.2".
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ version: String) -> [Int] { version.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 } }
        let a = parts(candidate), b = parts(current)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }
}
