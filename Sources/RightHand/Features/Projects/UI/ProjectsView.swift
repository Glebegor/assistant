import SwiftUI

extension ChatProvider {
    /// The colour each AI has in RightHand's windows.
    var tint: Color {
        switch self {
        case .claude: Color(red: 0.95, green: 0.55, blue: 0.33)
        case .openAI: Color(red: 0.30, green: 0.80, blue: 0.62)
        case .copilot: Color(red: 0.75, green: 0.76, blue: 0.82)
        case .gemini: Color(red: 0.45, green: 0.58, blue: 1.0)
        }
    }
}

/// Projects in RightHand's dark style: projects and their chats on the left, the open chat or
/// the project's overview on the right.
struct ProjectsView: View {
    let store: ProjectStore
    let openSettings: () -> Void

    enum Selection: Hashable {
        case project(UUID)
        case chat(UUID)
    }

    @State private var selection: Selection?
    @State private var collapsed: Set<UUID> = []
    @State private var renaming: ProjectChat?
    @State private var newTitle = ""

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.hairline).frame(width: 1)
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background)
        .foregroundStyle(.white)
        .tint(Theme.neon)
        .environment(\.colorScheme, .dark)
        .onAppear {
            if selection == nil, let first = store.projects.first { selection = .project(first.id) }
        }
        .alert("Rename chat", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $newTitle)
            Button("Rename") { if let chat = renaming { store.rename(chat, to: newTitle) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "square.stack.3d.up.fill").foregroundStyle(Theme.neon).neonGlow(radius: 6)
                Text("Projects").font(.system(size: 15, weight: .semibold))
                Spacer()
                IconButton(title: "New project", systemImage: "plus") {
                    let project = store.createProject(name: L("New Project"))
                    selection = .project(project.id)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 38)
            .padding(.bottom, 14)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(store.projects) { project in
                        projectGroup(project)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.never)
        }
        .frame(width: 260)
        .background(Color.black.opacity(0.18))
    }

    @ViewBuilder
    private func projectGroup(_ project: Project) -> some View {
        let chats = store.chats(in: project.id)
        let isOpen = !collapsed.contains(project.id)
        SidebarRow(isSelected: selection == .project(project.id)) {
            selection = .project(project.id)
        } content: { isHovered in
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    if isOpen { collapsed.insert(project.id) } else { collapsed.remove(project.id) }
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .frame(width: 12, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            Image(systemName: "folder.fill")
                .font(.system(size: 12))
                .foregroundStyle(selection == .project(project.id) ? Theme.neon : .secondary)
            Text(verbatim: project.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 4)
            if isHovered {
                newChatMenu(for: project)
            } else if !chats.isEmpty {
                Text(verbatim: "\(chats.count)").font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
            }
        }
        .padding(.top, 6)

        if isOpen {
            ForEach(chats) { chat in
                SidebarRow(isSelected: selection == .chat(chat.id)) {
                    selection = .chat(chat.id)
                } content: { _ in
                    Circle().fill(chat.provider.tint).frame(width: 6, height: 6)
                        .shadow(color: chat.provider.tint.opacity(0.6), radius: 3)
                    Text(verbatim: chat.title).font(.system(size: 12.5)).lineLimit(1)
                        .foregroundStyle(selection == .chat(chat.id) ? .primary : .secondary)
                    Spacer(minLength: 4)
                    Text(chat.updatedAt, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                        .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
                .padding(.leading, 22)
                .contextMenu {
                    Button("Rename…") { newTitle = chat.title; renaming = chat }
                    Divider()
                    Button("Delete Chat", role: .destructive) {
                        if selection == .chat(chat.id) { selection = .project(project.id) }
                        store.delete(chat)
                    }
                }
            }
        }
    }

    private func newChatMenu(for project: Project) -> some View {
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

    // MARK: Detail

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
        VStack(spacing: 14) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.neon)
                .neonGlow(radius: 12)
            Text("Choose a project or chat").font(.system(size: 20, weight: .semibold))
            Text("Projects keep instructions, files and memory for long work with Claude or ChatGPT.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
            Button("New Project", systemImage: "plus") {
                selection = .project(store.createProject(name: L("New Project")).id)
            }
            .buttonStyle(NeonButtonStyle())
            .padding(.top, 6)
        }
    }
}

/// A row of the sidebar: soft neon when selected, a faint light on hover.
private struct SidebarRow<Content: View>: View {
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let content: (_ isHovered: Bool) -> Content
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) { content(isHovered) }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Theme.neonSoft : (isHovered ? Color.white.opacity(0.05) : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? Theme.neon.opacity(0.4) : .clear, lineWidth: 1))
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .onHover { isHovered = $0 }
    }
}

/// A filled neon button for the main action.
struct NeonButtonStyle: ButtonStyle {
    var tint: Color = Theme.neon

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .foregroundStyle(.black)
            .background(tint, in: Capsule())
            .shadow(color: tint.opacity(0.45), radius: 10)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

/// A quiet outlined button.
struct GhostButtonStyle: ButtonStyle {
    var tint: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(tint)
            .background(tint.opacity(configuration.isPressed ? 0.16 : 0.07), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.22)))
            .contentShape(Capsule())
    }
}
