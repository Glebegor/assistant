import Foundation

/// Shelf preferences stored in UserDefaults (edited in the Settings window).
enum ShelfSettings {
    enum Key {
        static let captureScreenshots = "shelf.captureScreenshots"
        static let clipboardHistory = "shelf.clipboardHistory"
        static let filesDirectory = "shelf.filesDirectory"
    }

    enum Default {
        static let captureScreenshots = true
        static let clipboardHistory = true
        // In the home folder (not Documents/Desktop), so macOS doesn't ask for folder access.
        static let filesDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "RightHand Shelf", directoryHint: .isDirectory).path
    }

    /// How many clipboard entries are kept; older ones are removed.
    static let maxClipboardItems = 50

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.captureScreenshots: Default.captureScreenshots,
            Key.clipboardHistory: Default.clipboardHistory,
            Key.filesDirectory: Default.filesDirectory,
        ])
    }

    static var filesDirectory: String { UserDefaults.standard.string(forKey: Key.filesDirectory) ?? Default.filesDirectory }

    static var captureScreenshots: Bool { UserDefaults.standard.bool(forKey: Key.captureScreenshots) }
    static var clipboardHistory: Bool { UserDefaults.standard.bool(forKey: Key.clipboardHistory) }
}
