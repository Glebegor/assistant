import Foundation

/// Reports new screenshots (⌘⇧3, ⌘⇧4, ⌘⇧5) using Spotlight, which tags them as screen captures.
/// This works wherever macOS saves screenshots, not only on the Desktop.
@MainActor
final class ScreenshotWatcher {
    var onScreenshot: ((URL) -> Void)?

    private let query = NSMetadataQuery()

    init() {
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture = 1")
        query.searchScopes = [NSMetadataQueryUserHomeScope]

        // Fires only for changes after the first search, so old screenshots are ignored.
        NotificationCenter.default.addObserver(
            forName: .NSMetadataQueryDidUpdate, object: query, queue: .main
        ) { [weak self] notification in
            let added = notification.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem] ?? []
            let paths = added.compactMap { $0.value(forAttribute: NSMetadataItemPathKey) as? String }
            MainActor.assumeIsolated {
                for path in paths { self?.onScreenshot?(URL(filePath: path)) }
            }
        }
    }

    func setEnabled(_ enabled: Bool) {
        if enabled, !query.isStarted {
            query.start()
        } else if !enabled, query.isStarted {
            query.stop()
        }
    }
}
