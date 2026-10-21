import SwiftUI

/// Sidebar with projects and their chats; the selected chat or project on the right.
struct ProjectsView: View {
    let store: ProjectStore
    let openSettings: () -> Void

    enum Selection: Hashable {
        case project(UUID)
        case chat(UUID)
    }

    @State private var selection: Selection?
    @State private var renaming: ProjectChat?
    @State private var newTitle = ""

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            detail
        }
        .onAppear {
            if selection == nil, let first = store.projects.first { selection = .project(first.id) }
        }
        .alert("Rename chat", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $newTitle)
            Button("Rename") { if let chat = renaming { store.rename(chat, to: newTitle) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            ForEach(store.projects) { project in
                Section {
                    Label("Overview", systemImage: "folder")
                        .tag(Selection.project(project.id))
                    ForEach(store.chats(in: project.id)) { chat in
                        Label(chat.title, systemImage: chat.provider.systemImage)
                            .lineLimit(1)
                            .tag(Selection.chat(chat.id))
                            .contextMenu {
                                Button("Rename…") { newTitle = chat.title; renaming = chat }
                                Divider()
                                Button("Delete Chat", role: .destructive) {
                                    if selection == .chat(chat.id) { selection = .project(project.id) }
                                    store.delete(chat)
                                }
                            }
                    }
                } header: {
                    HStack {
                        Text(project.name)
                        Spacer()
                        newChatMenu(for: project, compact: true)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem {
                Button("New Project", systemImage: "folder.badge.plus") {
                    let project = store.createProject(name: L("New Project"))
                    selection = .project(project.id)
                }
                .help("New project")
            }
        }
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .chat(let id):
            if let engine = store.engine(for: id) {
                ProjectChatView(engine: engine, openSettings: openSettings).id(id)
            } else {
                emptyDetail
            }
        case .project(let id):
            if let project = store.project(id) {
                ProjectDetailView(store: store, project: project) { provider in
                    selection = .chat(store.newChat(in: project, provider: provider).id)
                } onDelete: {
                    store.delete(project)
                    selection = store.projects.first.map { .project($0.id) }
                }
                .id(id)
            } else {
                emptyDetail
            }
        case nil:
            emptyDetail
        }
    }

    private var emptyDetail: some View {
        ContentUnavailableView("Choose a project or chat", systemImage: "sparkles",
                               description: Text("Projects keep instructions, files and memory for long work with Claude or ChatGPT."))
    }

    private func newChatMenu(for project: Project, compact: Bool) -> some View {
        Menu {
            ForEach(ChatProvider.allCases) { provider in
                Button("New \(provider.title) Chat") {
                    selection = .chat(store.newChat(in: project, provider: provider).id)
                }
            }
        } label: {
            Image(systemName: "square.and.pencil")
        } primaryAction: {
            selection = .chat(store.newChat(in: project).id)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("New chat in \(project.name)")
    }
}
