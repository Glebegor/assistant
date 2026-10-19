import Foundation
import ImageIO

/// Reports new screenshots (⌘⇧3, ⌘⇧4, ⌘⇧5) by watching the folder macOS saves them to.
/// Screenshots are recognised by the "Screenshot" comment macOS writes into the image,
/// which works in every system language. (Spotlight isn't used: it can lag or stop indexing.)
///
/// Reading the Desktop needs the user's permission (Privacy & Security → Files and Folders).
/// macOS asks the first time; until it's answered the folder can't be read, so all file
/// access happens on a background queue and never freezes the app.
final class ScreenshotWatcher: @unchecked Sendable {
    /// Called on the main thread for each new screenshot.
    var onScreenshot: (@MainActor (URL) -> Void)?
    /// Called on the main thread with false when macOS denies access to the folder.
    var onAccessChange: (@MainActor (Bool) -> Void)?

    private let queue = DispatchQueue(label: "RightHand.ScreenshotWatcher")
    // Only touched on `queue`:
    private var source: DispatchSourceFileSystemObject?
    private var watchedFolder: URL?
    private var known: Set<String>?

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff"]

    /// Where macOS saves screenshots (Screenshot app → Options → Save to); the Desktop by default.
    static var screenshotFolder: URL {
        let custom = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
        if let custom, !custom.isEmpty {
            return URL(filePath: (custom as NSString).expandingTildeInPath, directoryHint: .isDirectory)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: "Desktop", directoryHint: .isDirectory)
    }

    func setEnabled(_ enabled: Bool) {
        let folder = Self.screenshotFolder
        queue.async { [self] in
            if enabled {
                guard source == nil || folder != watchedFolder else { return }
                stop()
                start(watching: folder)
            } else {
                stop()
            }
        }
    }

    private func start(watching folder: URL) {
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        watchedFolder = folder
        known = contents(of: folder).map(Set.init)

        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: queue)
        source.setEventHandler { [weak self] in
            // macOS writes the screenshot in steps; look a moment later when the file is complete.
            self?.queue.asyncAfter(deadline: .now() + 0.7) { self?.scan() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    private func stop() {
        source?.cancel()
        source = nil
        watchedFolder = nil
        known = nil
    }

    private func scan() {
        guard let folder = watchedFolder, let names = contents(of: folder) else { return }
        guard let known else {
            // Access was just granted: everything there now is old.
            self.known = Set(names)
            return
        }
        let new = names.filter { !known.contains($0) }
        self.known = known.union(new)
        for name in new {
            let url = folder.appending(path: name)
            guard Self.isScreenshot(url) else { continue }
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.onScreenshot?(url) }
            }
        }
    }

    /// File names in the folder, or nil when macOS doesn't allow reading it.
    private func contents(of folder: URL) -> [String]? {
        do {
            let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { !$0.hasPrefix(".") }
            report(access: true)
            return names
        } catch {
            report(access: false)
            return nil
        }
    }

    private func report(access: Bool) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.onAccessChange?(access) }
        }
    }

    private static func isScreenshot(_ url: URL) -> Bool {
        guard imageExtensions.contains(url.pathExtension.lowercased()),
              let image = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [String: Any],
              let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
        else { return false }
        return exif[kCGImagePropertyExifUserComment as String] as? String == "Screenshot"
    }
}
