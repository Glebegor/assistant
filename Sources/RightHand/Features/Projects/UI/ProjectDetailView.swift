import AppKit
import SwiftUI

/// A project's settings: name, instructions, attached files, folders and memory.
struct ProjectDetailView: View {
    let store: ProjectStore
    @State var project: Project
    let onNewChat: (ChatProvider) -> Void
    let onDelete: () -> Void

    @State private var confirmDelete = false
    @State private var openMemoryFile: URL?

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $project.name)
                    .font(.title3)
                HStack {
                    ForEach(ChatProvider.allCases) { provider in
                        Button("New \(provider.title) Chat", systemImage: "square.and.pencil") { onNewChat(provider) }
                    }
                }
            }

            Section {
                TextEditor(text: $project.instructions)
                    .font(.body)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
            } header: {
                Text("Instructions")
            } footer: {
                SettingsFooter("How the AI should work in this project, e.g. “Help me with my thesis. Answer in Ukrainian, briefly.”")
            }

            filesSection
            foldersSection
            memorySection

            Section {
                Button("Delete Project…", role: .destructive) { confirmDelete = true }
            }
        }
        .formStyle(.grouped)
        .onChange(of: project) { _, project in store.update(project) }
        .confirmationDialog("Delete “\(project.name)”?", isPresented: $confirmDelete) {
            Button("Delete Project", role: .destructive, action: onDelete)
        } message: {
            Text("Its chats, files and memory are moved to the Trash.")
        }
        .sheet(item: $openMemoryFile) { url in
            MemoryFileSheet(url: url)
        }
    }

    private var filesSection: some View {
        Section {
            let files = store.attachedFiles(of: project)
            ForEach(files, id: \.self) { file in
                HStack {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: file.path)).resizable().frame(width: 18, height: 18)
                    Text(file.lastPathComponent).lineLimit(1)
                    Spacer()
                    Button("Remove", systemImage: "minus.circle.fill") { store.removeAttachedFile(file) }
                        .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.red)
                }
                .contextMenu { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) } }
            }
            Button("Add Files…", systemImage: "plus") { pickFiles() }
        } header: {
            Text("Files")
        } footer: {
            SettingsFooter("Copied into the project. The text of these files is part of every new chat (PDF, Markdown, code, notes…).")
        }
        .dropDestination(for: URL.self) { urls, _ in
            store.attach(urls.filter(\.isFileURL), to: project)
            return true
        }
    }

    private var foldersSection: some View {
        Section {
            ForEach(project.folders, id: \.self) { folder in
                HStack {
                    Image(systemName: "folder.fill").foregroundStyle(.blue)
                    Text((folder as NSString).abbreviatingWithTildeInPath).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Remove", systemImage: "minus.circle.fill") { project.folders.removeAll { $0 == folder } }
                        .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.red)
                }
            }
            Button("Add Folder…", systemImage: "plus") { pickFolder() }
        } header: {
            Text("Folders on your Mac")
        } footer: {
            SettingsFooter("The AI can list, search, read and write files in these folders. It asks before every action unless you allow a tool for good.")
        }
    }

    private var memorySection: some View {
        Section {
            let files = store.memoryFiles(of: project)
            if files.isEmpty {
                Text("Nothing yet. The AI writes notes here as you work.").foregroundStyle(.secondary)
            }
            ForEach(files, id: \.self) { file in
                HStack {
                    Image(systemName: "note.text").foregroundStyle(.orange)
                    Button(file.lastPathComponent) { openMemoryFile = file }.buttonStyle(.link)
                    Spacer()
                    Button("Delete", systemImage: "trash") { store.deleteMemoryFile(file) }
                        .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.secondary)
                }
            }
        } header: {
            HStack {
                Text("Memory")
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") { store.refreshFiles() }
                    .labelStyle(.iconOnly).buttonStyle(.borderless)
            }
        } footer: {
            SettingsFooter("Notes the AI keeps about this project, shared by all its chats.")
        }
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { store.attach(panel.urls, to: project) }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = L("Add Folder")
        if panel.runModal() == .OK, let url = panel.url, !project.folders.contains(url.path) {
            project.folders.append(url.path)
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// Shows one memory note.
private struct MemoryFileSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(url.lastPathComponent).font(.headline)
            ScrollView {
                Text((try? String(contentsOf: url, encoding: .utf8)) ?? "")
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 420)
    }
}
