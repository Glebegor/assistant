import Foundation

/// One thing kept on the Shelf: a file, a piece of text or a copied image.
struct ShelfItem: Identifiable, Codable, Equatable {
    enum Content: Codable, Equatable {
        /// A file that stays where it is; the bookmark lets us find it again after it is moved.
        case file(path: String, bookmark: Data?)
        case text(String)
        /// A copied image, saved by RightHand into `ShelfPersistence.imagesDirectory`.
        case image(fileName: String)
    }

    /// Where the item came from.
    enum Source: String, Codable {
        case dropped, screenshot, clipboard
    }

    var id = UUID()
    var content: Content
    var source: Source
    var dateAdded = Date()
    /// The Shelf folder this item is in; nil = top level.
    var folderID: UUID?

    /// File on disk for file and image items.
    var fileURL: URL? {
        switch content {
        case .file(let path, _): URL(filePath: path)
        case .image(let fileName): ShelfPersistence.imagesDirectory.appending(path: fileName)
        case .text: nil
        }
    }

    var title: String {
        switch content {
        case .file(let path, _):
            return URL(filePath: path).lastPathComponent
        case .text(let text):
            let firstLine = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
            return String(firstLine.trimmingCharacters(in: .whitespaces).prefix(80))
        case .image:
            return "Copied image"
        }
    }

    /// Two items with the same key are duplicates; the newer one replaces the older.
    var duplicateKey: String? {
        switch content {
        case .file(let path, _): "file:\(path)"
        case .text(let text): "text:\(text)"
        case .image: nil
        }
    }
}

/// A named group on the Shelf. Folders exist only inside RightHand; files on disk are not moved.
struct ShelfFolder: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var dateAdded = Date()
}
