import AppKit
import SwiftUI

/// Notes tab: your notes on the left, the open one on the right. The first line is the title.
struct NotesView: View {
    let store: NoteStore
    @State private var query = ""
    @State private var copiedID: UUID?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            sidebar
                .frame(width: 170)
            editor
        }
        .padding(.top, 4)
    }

    // MARK: List

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                    TextField("Search", text: $query).textFieldStyle(.plain)
                }
                .font(.caption)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                Button { query = ""; store.create() } label: {
                    Image(systemName: "square.and.pencil").font(.system(size: 13, weight: .medium))
                        .frame(width: 26, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New note")
            }
            let notes = store.filtered(query)
            if notes.isEmpty {
                Text(query.isEmpty ? "No notes yet." : "Nothing found.")
                    .font(.caption).foregroundStyle(.tertiary).padding(.top, 4)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(notes) { note in row(note) }
                    }
                }
                .scrollIndicators(.never)
            }
        }
    }

    private func row(_ note: Note) -> some View {
        let isSelected = note.id == store.selectedID
        return Button { store.selectedID = note.id } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: note.title).font(.callout.weight(isSelected ? .semibold : .regular)).lineLimit(1)
                Text(note.updated, format: .relative(presentation: .named))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(isSelected ? Theme.neonSoft : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.neon.opacity(0.35), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Copy Link") { copyLink(note) }
            Button("Delete", role: .destructive) { store.delete(note.id) }
        }
    }

    // MARK: Editor

    @ViewBuilder
    private var editor: some View {
        if let note = store.selected {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(note.updated, format: .dateTime.day().month().hour().minute())
                        .font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                    Button { copyLink(note) } label: {
                        Label(copiedID == note.id ? "Copied" : "Copy Link",
                              systemImage: copiedID == note.id ? "checkmark" : "link")
                    }
                    .help("A righthand:// link that opens this note — paste it anywhere on your Mac")
                    Button { store.delete(note.id) } label: { Label("Delete", systemImage: "trash") }
                        .labelStyle(.iconOnly)
                        .help("Delete note")
                }
                .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)

                TextEditor(text: Binding(get: { note.text }, set: { store.update(note.id, text: $0) }))
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.automatic)
                    .padding(6)
                    .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .id(note.id)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "note.text").font(.system(size: 28)).foregroundStyle(Theme.neon.opacity(0.8))
                Text("Write down anything. The AI can read your notes and send you links to them.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("New Note", systemImage: "square.and.pencil") { store.create() }
                    .buttonStyle(.notchPill(prominent: true, tint: Theme.neon))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func copyLink(_ note: Note) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(note.link.absoluteString, forType: .string)
        copiedID = note.id
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copiedID == note.id { copiedID = nil }
        }
    }
}
