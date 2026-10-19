import CryptoKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

/// Builds what the AI always knows in a project: instructions, attached files, folders.
enum ProjectContext {
    private static let maxCharactersPerFile = 60_000
    private static let maxCharactersTotal = 200_000

    /// System prompt for a new chat in `project`.
    static func systemPrompt(for project: Project, provider: ChatProvider) -> String {
        var parts = ["""
        You are RightHand, an assistant on the user's Mac, working in the project "\(project.name)". \
        Answer clearly and concisely. Use Markdown for code and short lists.
        """]

        let instructions = project.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !instructions.isEmpty {
            parts.append("# Project instructions\n\n\(instructions)")
        }

        let files = attachedFiles(of: project)
        if !files.isEmpty {
            parts.append("# Project files\n\nThe user attached these files to the project:\n\n" + fileContents(files))
        }

        if !project.folders.isEmpty {
            parts.append("""
            # Folders on the user's Mac

            You can work with files in these folders using your tools (list, search, read, write). \
            Look things up with the tools instead of guessing what a file contains.

            \(project.folders.map { "- \($0)" }.joined(separator: "\n"))
            """)
        }

        parts.append(provider == .claude
            ? "# Memory\n\nUse your memory tool to keep notes about this project (decisions, progress, preferences) so later chats can continue the work."
            : "# Memory\n\nUse the `memory` tool to keep notes about this project (decisions, progress, preferences) so later chats can continue the work. Check your memory at the start of a task.")
        return parts.joined(separator: "\n\n")
    }

    /// Changes whenever something the system prompt is built from changes.
    static func fingerprint(of project: Project) -> String {
        var text = project.name + "\n" + project.instructions + "\n" + project.folders.joined(separator: "\n")
        for file in attachedFiles(of: project) {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            text += "\n\(file.lastPathComponent)@\(modified.timeIntervalSince1970)"
        }
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func attachedFiles(of project: Project) -> [URL] {
        let folder = ProjectStorage.filesDirectory(of: project.id)
        return ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey],
                                                              options: .skipsHiddenFiles)) ?? [])
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Plain text of a file, or nil for images and other binary files.
    static func text(of url: URL) -> String? {
        let type = UTType(filenameExtension: url.pathExtension)
        if type?.conforms(to: .pdf) == true {
            return PDFDocument(url: url)?.string
        }
        guard let data = try? Data(contentsOf: url), data.count < 20_000_000 else { return nil }
        if type?.conforms(to: .text) == true || type?.conforms(to: .sourceCode) == true || type == nil {
            return String(data: data, encoding: .utf8)
        }
        // Unknown extension: treat it as text if it decodes as UTF-8 and has no NUL bytes.
        return data.contains(0) ? nil : String(data: data, encoding: .utf8)
    }

    private static func fileContents(_ files: [URL]) -> String {
        var budget = maxCharactersTotal
        return files.map { file in
            let name = file.lastPathComponent
            guard budget > 0, let text = text(of: file) else {
                return "<file name=\"\(name)\">(not included: \(budget > 0 ? "not a text file" : "too much text"))</file>"
            }
            var excerpt = String(text.prefix(min(maxCharactersPerFile, budget)))
            budget -= excerpt.count
            if excerpt.count < text.count { excerpt += "\n… (shortened)" }
            return "<file name=\"\(name)\">\n\(excerpt)\n</file>"
        }
        .joined(separator: "\n\n")
    }
}
