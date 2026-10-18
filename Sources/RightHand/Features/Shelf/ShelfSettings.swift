import Foundation

/// Shelf preferences stored in UserDefaults (edited in the Settings window).
enum ShelfSettings {
    enum Key {
        static let captureScreenshots = "shelf.captureScreenshots"
        static let clipboardHistory = "shelf.clipboardHistory"
    }

    enum Default {
        static let captureScreenshots = true
        static let clipboardHistory = true
    }

    /// How many clipboard entries are kept; older ones are removed.
    static let maxClipboardItems = 50

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.captureScreenshots: Default.captureScreenshots,
            Key.clipboardHistory: Default.clipboardHistory,
        ])
    }

    static var captureScreenshots: Bool { UserDefaults.standard.bool(forKey: Key.captureScreenshots) }
    static var clipboardHistory: Bool { UserDefaults.standard.bool(forKey: Key.clipboardHistory) }
}
