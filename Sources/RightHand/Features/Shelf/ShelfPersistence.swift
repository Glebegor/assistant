import Foundation

/// Saves the Shelf to disk so it survives restarts.
enum ShelfPersistence {
    static let imagesDirectory = AppPaths.makeDirectory(AppPaths.support.appending(path: "ShelfImages", directoryHint: .isDirectory))
    private static let itemsFile = AppPaths.support.appending(path: "shelf.json")

    static func load() -> [ShelfItem] {
        guard let data = try? Data(contentsOf: itemsFile),
              let items = try? JSONDecoder().decode([ShelfItem].self, from: data)
        else { return [] }
        return items.compactMap(refresh)
    }

    static func save(_ items: [ShelfItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: itemsFile, options: .atomic)
    }

    static func deleteStoredFile(of item: ShelfItem) {
        guard case .image = item.content, let url = item.fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Follows moved files and drops items whose file no longer exists.
    private static func refresh(_ item: ShelfItem) -> ShelfItem? {
        var item = item
        if case .file(let path, let bookmark?) = item.content {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: .withoutUI, bookmarkDataIsStale: &isStale),
               url.path != path {
                item.content = .file(path: url.path, bookmark: try? url.bookmarkData())
            }
        }
        if let url = item.fileURL, !FileManager.default.fileExists(atPath: url.path) { return nil }
        return item
    }
}
