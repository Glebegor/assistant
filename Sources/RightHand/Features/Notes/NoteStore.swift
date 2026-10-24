import Foundation
import Observation

/// One note: plain text, its first line is the title.
struct Note: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var text = ""
    var created = Date()
    var updated = Date()

    var title: String {
        let first = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let title = first.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "#").union(.whitespaces))
        return title.isEmpty ? L("New note") : String(title.prefix(80))
    }

    /// Opens this note in the notch (righthand://note/<id>), from the chat or any app.
    var link: URL { URL(string: "\(NotesFile.scheme)://note/\(id.uuidString)")! }
}

/// The notes file: ~/Library/Application Support/RightHand/notes.json. Read from anywhere
/// (the AI's tools), written by the store.
enum NotesFile {
    static let scheme = "righthand"
    static var url: URL { AppPaths.support.appending(path: "notes.json") }

    static func load() -> [Note] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? Data(contentsOf: url)).flatMap { try? decoder.decode([Note].self, from: $0) } ?? []
    }

    static func save(_ notes: [Note]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted]
        try? encoder.encode(notes).write(to: url, options: .atomic)
    }

    /// The note id in a righthand://note/<id> link.
    static func noteID(in url: URL) -> UUID? {
        guard url.scheme == scheme, url.host() == "note" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
}

/// Your notes in the Notes tab, newest changes first.
@Observable
@MainActor
final class NoteStore {
    private(set) var notes: [Note] = []
    var selectedID: UUID?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init() {
        notes = NotesFile.load().sorted { $0.updated > $1.updated }
        selectedID = notes.first?.id
    }

    var selected: Note? { notes.first { $0.id == selectedID } }

    func filtered(_ query: String) -> [Note] {
        let query = query.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? notes : notes.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    @discardableResult
    func create() -> Note {
        // Reuse an empty note instead of piling them up.
        if let empty = notes.first(where: { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            selectedID = empty.id
            return empty
        }
        let note = Note()
        notes.insert(note, at: 0)
        selectedID = note.id
        save(now: true)
        return note
    }

    func update(_ id: UUID, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].text != text else { return }
        notes[index].text = text
        notes[index].updated = Date()
        save()
    }

    func delete(_ id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes.remove(at: index)
        if selectedID == id { selectedID = notes.first?.id }
        save(now: true)
    }

    /// Saves shortly after you stop typing.
    private func save(now: Bool = false) {
        saveTask?.cancel()
        let notes = notes
        saveTask = Task {
            if !now { try? await Task.sleep(for: .seconds(0.6)) }
            guard !Task.isCancelled else { return }
            NotesFile.save(notes)
        }
    }

    /// Writes pending changes right away (when quitting).
    func flush() {
        saveTask?.cancel()
        NotesFile.save(notes)
    }
}

// MARK: AI tools

private extension Note {
    var aiSummary: String {
        "- \(title) — id \(id.uuidString), updated \(updated.formatted(.iso8601.year().month().day())), link \(link.absoluteString)"
    }
}

struct NotesListTool: AssistantTool {
    let name = "notes_list"
    var displayName: String { L("Search notes") }
    let description = """
    Lists or searches the user's notes in RightHand (the Notes tab). `query` searches the text; empty lists all, \
    newest first. Returns title, id, date and a righthand:// link; share the link as a Markdown link \
    ([title](link)) so the user can click it to open the note.
    """
    var inputSchema: JSONValue {
        ["type": "object", "properties": ["query": ["type": "string", "description": "Words to look for. Empty lists all notes."]]]
    }

    func describe(_ input: JSONValue) -> String {
        let query = input["query"]?.string ?? ""
        return query.isEmpty ? L("List your notes") : L("Search notes for “%@”", query)
    }

    func run(_ input: JSONValue) async -> ToolOutput {
        let query = (input["query"]?.string ?? "").trimmingCharacters(in: .whitespaces)
        let words = query.split(separator: " ").map(String.init)
        let notes = NotesFile.load().sorted { $0.updated > $1.updated }
            .filter { note in words.allSatisfy { note.text.localizedCaseInsensitiveContains($0) } }
        guard !notes.isEmpty else { return ToolOutput(text: query.isEmpty ? "The user has no notes." : "No notes match “\(query)”.") }
        return ToolOutput(text: notes.prefix(100).map(\.aiSummary).joined(separator: "\n"))
    }
}

struct NotesReadTool: AssistantTool {
    let name = "notes_read"
    var displayName: String { L("Read notes") }
    let description = "Reads the whole text of one of the user's RightHand notes, by the id from notes_list."
    var inputSchema: JSONValue {
        ["type": "object", "properties": ["id": ["type": "string", "description": "The note id."]], "required": ["id"]]
    }

    func describe(_ input: JSONValue) -> String {
        let id = input["id"]?.string.flatMap(UUID.init(uuidString:))
        let title = NotesFile.load().first { $0.id == id }?.title
        return L("Read note “%@”", title ?? input["id"]?.string ?? "")
    }

    func run(_ input: JSONValue) async -> ToolOutput {
        guard let id = input["id"]?.string.flatMap(UUID.init(uuidString:)),
              let note = NotesFile.load().first(where: { $0.id == id }) else {
            return .error("No note with this id. Use notes_list to find it.")
        }
        return ToolOutput(text: "\(note.aiSummary)\n\n\(String(note.text.prefix(60_000)))")
    }
}
