import Foundation

/// A project: instructions, files and folders that every chat in it knows about,
/// plus a memory the AI keeps for itself.
struct Project: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    /// How the AI should work in this project ("answer in Ukrainian, be brief", …).
    var instructions = ""
    /// Folders on the Mac the AI may list, search, read and write (always with your permission).
    var folders: [String] = []
    var createdAt = Date()
}

/// One saved conversation inside a project.
struct ProjectChat: Codable, Identifiable, Hashable {
    var id = UUID()
    var projectID: UUID
    var title = L("New chat")
    var provider: ChatProvider
    var model: String
    var createdAt = Date()
    var updatedAt = Date()
    /// System prompt, fixed when the chat starts (Claude checks that it never changes).
    var system: String
    /// Fingerprint of the project context `system` was built from; when the project changes,
    /// the update is sent as an extra system message instead of editing `system`.
    var contextFingerprint: String
    /// The conversation in the provider's own API format, append-only.
    var messages: [JSONValue] = []
    /// ChatGPT only: messages before this index were replaced by `summary` for the AI
    /// (they still show in the window).
    var contextStart = 0
    var summary: String?
}
