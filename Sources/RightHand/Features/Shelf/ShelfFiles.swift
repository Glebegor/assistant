import Foundation

/// The real folder on disk that holds copies of everything attached to the Shelf
/// (~/RightHand Shelf by default). Each Shelf folder is a subfolder with the same name.
enum ShelfFiles {
    static var rootDirectory: URL {
        URL(filePath: ShelfSettings.filesDirectory, directoryHint: .isDirectory)
    }

    static func directory(for folder: ShelfFolder?) -> URL {
        guard let folder else { return rootDirectory }
        return rootDirectory.appending(path: directoryName(for: folder.name), directoryHint: .isDirectory)
    }

    /// Folder names may contain characters that are not allowed in file names.
    static func directoryName(for folderName: String) -> String {
        folderName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }

    static func isInsideRoot(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(rootDirectory.standardizedFileURL.path + "/")
    }

    /// Copies a file or folder into `directory` and returns the copy.
    /// On the same disk APFS makes this an instant clone that takes no extra space.
    static func copy(_ source: URL, into directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = uniqueURL(for: source.lastPathComponent, in: directory)
        try FileManager.default.copyItem(at: source, to: target)
        return target
    }

    /// Moves a file into `directory`; returns the new location, or nil if it failed.
    static func move(_ url: URL, into directory: URL) -> URL? {
        guard url.deletingLastPathComponent().standardizedFileURL != directory.standardizedFileURL else { return url }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = uniqueURL(for: url.lastPathComponent, in: directory)
        return (try? FileManager.default.moveItem(at: url, to: target)) != nil ? target : nil
    }

    static func trash(_ url: URL) {
        try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    /// "Report.pdf" → "Report 2.pdf" → "Report 3.pdf" … until the name is free.
    static func uniqueURL(for name: String, in directory: URL) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = directory.appending(path: name)
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appending(path: ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)")
            number += 1
        }
        return candidate
    }
}
