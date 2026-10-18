import Foundation

/// Everything the Shelf saves to disk.
struct ShelfData: Codable {
    var items: [ShelfItem] = []
    var folders: [ShelfFolder] = []
}

/// Saves the Shelf to disk so it survives restarts.
enum ShelfPersistence {
    static let imagesDirectory = AppPaths.makeDirectory(AppPaths.support.appending(path: "ShelfImages", directoryHint: .isDirectory))
    private static let itemsFile = AppPaths.support.appending(path: "shelf.json")

    static func load() -> ShelfData {
        guard let json = try? Data(contentsOf: itemsFile) else { return ShelfData() }
        let decoder = JSONDecoder()
        var data = (try? decoder.decode(ShelfData.self, from: json))
            // Files saved before folders existed contain only the item list.
            ?? (try? decoder.decode([ShelfItem].self, from: json)).map { ShelfData(items: $0) }
            ?? ShelfData()

        let folderIDs = Set(data.folders.map(\.id))
        data.items = data.items.compactMap(refresh).map { item in
            var item = item
            if let folderID = item.folderID, !folderIDs.contains(folderID) { item.folderID = nil }
            return item
        }
        return data
    }

    static func save(_ data: ShelfData) {
        guard let json = try? JSONEncoder().encode(data) else { return }
        try? json.write(to: itemsFile, options: .atomic)
    }

    /// Removes the file RightHand made for this item: copies go to the Trash,
    /// clipboard images are deleted. Linked files are never touched.
    static func deleteStoredFile(of item: ShelfItem) {
        guard item.ownsFile, let url = item.fileURL else { return }
        switch item.content {
        case .file: ShelfFiles.trash(url)
        case .image: try? FileManager.default.removeItem(at: url)
        case .text: break
        }
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
