import Foundation

/// Folders where RightHand keeps its own data.
enum AppPaths {
    /// ~/Library/Application Support/RightHand
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return makeDirectory(base.appending(path: "RightHand", directoryHint: .isDirectory))
    }()

    @discardableResult
    static func makeDirectory(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
