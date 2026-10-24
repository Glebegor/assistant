import AppKit
import SwiftUI

/// A project's overview: name, new chats, instructions, files, folders, memory and permissions,
/// as cards on the dark background.
struct ProjectDetailView: View {
    let store: ProjectStore
    @State var project: Project
    let onNewChat: (ChatProvider) -> Void
    let onDelete: () -> Void

    @State private var confirmDelete = false
    @State private var openMemoryFile: URL?
    @State private var allowedTools: [String] = []
    @State private var isDropTargeted = false

    var body: some View {
        let files = store.attachedFiles(of: project)
        let memory = store.memoryFiles(of: project)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(files: files.count)
                card("Instructions", systemImage: "text.quote",
                     footer: "How the AI should work in this project, e.g. “Help me with my thesis. Answer in Ukrainian, briefly.”") {
                    TextEditor(text: $project.instructions)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 110)
                        .padding(8)
                        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            if project.instructions.isEmpty {
                                Text("Write instructions for the AI…").font(.system(size: 13)).foregroundStyle(.tertiary)
                                    .padding(.horizontal, 13).padding(.vertical, 8).allowsHitTesting(false)
                            }
                        }
                }
                HStack(alignment: .top, spacing: 18) {
                    filesCard(files)
                    foldersCard
                }
                memoryCard(memory)
                if !allowedTools.isEmpty { permissionsCard }
                HStack {
                    Spacer()
                    Button("Delete Project…", systemImage: "trash") { confirmDelete = true }
                        .buttonStyle(GhostButtonStyle(tint: .red))
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 36)
            .padding(.bottom, 28)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.automatic)
        .onChange(of: project) { _, project in store.update(project) }
        .confirmationDialog("Delete “\(project.name)”?", isPresented: $confirmDelete) {
            Button("Delete Project", role: .destructive, action: onDelete)
        } message: {
            Text("Its chats, files and memory are moved to the Trash.")
        }
        .onAppear { allowedTools = ProjectPermissions.allowed(in: project.id) }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            allowedTools = ProjectPermissions.allowed(in: project.id)
        }
        .sheet(item: $openMemoryFile) { url in
            MemoryFileSheet(url: url)
        }
    }

    // MARK: Header

    private func header(files: Int) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Name", text: $project.name)
                .textFieldStyle(.plain)
                .font(.system(size: 28, weight: .semibold))
            HStack(spacing: 14) {
                stat("bubble.left.and.bubble.right", L("%lld chats", store.chats(in: project.id).count))
                stat("doc", L("%lld files", files))
                stat("folder", L("%lld folders", project.folders.count))
                stat("calendar", project.createdAt.formatted(date: .abbreviated, time: .omitted))
            }
            HStack(spacing: 8) {
                Text("New chat").font(.caption).foregroundStyle(.tertiary).padding(.trailing, 2)
                ForEach(ChatProvider.allCases) { provider in
                    Button { onNewChat(provider) } label: {
                        HStack(spacing: 6) {
                            Circle().fill(provider.tint).frame(width: 7, height: 7).shadow(color: provider.tint, radius: 3)
                            Text(verbatim: provider == .copilot ? "Copilot" : provider.title)
                        }
                    }
                    .buttonStyle(GhostButtonStyle())
                    .help("New \(provider.title) Chat")
                }
            }
        }
    }

    private func stat(_ systemImage: String, _ text: String) -> some View {
        Label(text, systemImage: systemImage).font(.caption).foregroundStyle(.secondary)
    }

    // MARK: Cards

    private func card<Content: View, Accessory: View>(_ title: LocalizedStringKey, systemImage: String, footer: LocalizedStringKey? = nil,
                                                      @ViewBuilder accessory: () -> Accessory = { EmptyView() },
                                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: systemImage).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.neon)
                ThemeCaption(title)
                Spacer()
                accessory()
            }
            content()
            if let footer {
                Text(footer).font(.caption).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .themeCard()
    }

    private func filesCard(_ files: [URL]) -> some View {
        card("Files", systemImage: "doc.on.doc", footer: "Copied into the project. Their text is part of every new chat.") {
            IconButton(title: "Add Files…", systemImage: "plus", action: pickFiles)
        } content: {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(files, id: \.self) { file in
                    ItemRow(icon: Image(nsImage: NSWorkspace.shared.icon(forFile: file.path)), title: file.lastPathComponent) {
                        store.removeAttachedFile(file)
                    }
                    .contextMenu { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) } }
                }
                dropZone(files.isEmpty ? "Drop files here" : "Drop more files")
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            store.attach(urls.filter(\.isFileURL), to: project)
            return true
        } isTargeted: { isDropTargeted = $0 }
    }

    private func dropZone(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(isDropTargeted ? Theme.neon : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isDropTargeted ? Theme.neon : .white.opacity(0.14), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            .onTapGesture(perform: pickFiles)
    }

    private var foldersCard: some View {
        card("Folders on your Mac", systemImage: "folder", footer: "The AI can read and write files here. It asks before every action.") {
            IconButton(title: "Add Folder…", systemImage: "plus", action: pickFolder)
        } content: {
            VStack(alignment: .leading, spacing: 4) {
                if project.folders.isEmpty {
                    Text("No folders yet.").font(.callout).foregroundStyle(.tertiary).padding(.vertical, 6)
                }
                ForEach(project.folders, id: \.self) { folder in
                    ItemRow(icon: Image(systemName: "folder.fill"), tint: Theme.neon,
                            title: (folder as NSString).abbreviatingWithTildeInPath, truncatesMiddle: true) {
                        project.folders.removeAll { $0 == folder }
                    }
                    .contextMenu { Button("Show in Finder") { NSWorkspace.shared.open(URL(fileURLWithPath: folder)) } }
                }
            }
        }
    }

    private func memoryCard(_ files: [URL]) -> some View {
        card("Memory", systemImage: "brain", footer: "Notes the AI keeps about this project, shared by all its chats.") {
            IconButton(title: "Refresh", systemImage: "arrow.clockwise") { store.refreshFiles() }
        } content: {
            if files.isEmpty {
                Text("Nothing yet. The AI writes notes here as you work.").font(.callout).foregroundStyle(.tertiary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(files, id: \.self) { file in
                        Button { openMemoryFile = file } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "note.text").foregroundStyle(Theme.violet)
                                Text(verbatim: file.deletingPathExtension().lastPathComponent).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .font(.system(size: 12.5))
                            .padding(.horizontal, 10).padding(.vertical, 8)
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu { Button("Delete", role: .destructive) { store.deleteMemoryFile(file) } }
                    }
                }
            }
        }
    }

    /// Tools allowed "For This Project": they run here without asking.
    private var permissionsCard: some View {
        card("Allowed without asking", systemImage: "checkmark.shield", footer: "In this project these tools run without asking, also outside the project folders.") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(allowedTools, id: \.self) { tool in
                    HStack {
                        Image(systemName: "checkmark.shield.fill").foregroundStyle(.green)
                        Text(verbatim: Toolbox.displayName(of: tool)).font(.system(size: 13))
                        Spacer()
                        Button("Ask Again") { ProjectPermissions.set(tool, allowed: false, in: project.id) }
                            .buttonStyle(GhostButtonStyle())
                    }
                    .padding(.vertical, 2)
                }
            }
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

/// A file or folder in a card, with a remove button on hover.
private struct ItemRow: View {
    let icon: Image
    var tint: Color = .white
    let title: String
    var truncatesMiddle = false
    let onRemove: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            icon.resizable().scaledToFit().frame(width: 16, height: 16).foregroundStyle(tint)
            Text(verbatim: title).font(.system(size: 12.5)).lineLimit(1).truncationMode(truncatesMiddle ? .middle : .tail)
            Spacer(minLength: 4)
            Button(action: onRemove) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .opacity(isHovered ? 1 : 0)
                .help("Remove")
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(Color.white.opacity(isHovered ? 0.06 : 0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { isHovered = $0 }
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
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
    }
}
