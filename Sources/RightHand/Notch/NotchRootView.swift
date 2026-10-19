import SwiftUI

/// The black shape hanging from the notch, and the panel content when it is open.
struct NotchRootView: View {
    let model: NotchModel
    let pomodoro: PomodoroTimer
    let shelf: ShelfStore
    let chat: ChatStore
    let openSettings: () -> Void
    let openProjects: () -> Void
    @State private var isDropTargeted = false

    var body: some View {
        let size = model.isExpanded ? model.selectedTab.panelSize : model.geometry.collapsedSize
        let radius: CGFloat = model.isExpanded ? 26 : 10
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)

        ZStack(alignment: .top) {
            shape
                .fill(.black)
                .opacity(model.isExpanded || !model.hidesWhenCollapsed ? 1 : 0)
            if model.isExpanded {
                content
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: model.isExpanded)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: model.selectedTab)
        .animation(.easeInOut(duration: 0.2), value: model.hidesWhenCollapsed)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch model.selectedTab {
                case .pomodoro: PomodoroView(timer: pomodoro)
                case .shelf: ShelfView(store: shelf)
                case .chat: ChatView(store: chat, openSettings: openSettings, openProjects: openProjects)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .foregroundStyle(.white)
        // Anything dragged onto the panel goes to the Shelf.
        .onDrop(of: ShelfStore.dropTypes, isTargeted: $isDropTargeted) { providers in
            shelf.addDropped(providers, into: shelf.openFolderID)
        }
        .onChange(of: isDropTargeted) { _, targeted in
            if targeted { model.selectedTab = .shelf }
        }
        .overlay {
            if isDropTargeted {
                UnevenRoundedRectangle(bottomLeadingRadius: 26, bottomTrailingRadius: 26, style: .continuous)
                    .strokeBorder(.white.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [6]))
            }
        }
    }

    /// Top row: tabs on the left of the camera, actions on the right.
    private var header: some View {
        HStack(spacing: 4) {
            ForEach(NotchTab.allCases) { tab in
                headerButton(tab.systemImage, help: tab.title, isOn: model.selectedTab == tab) {
                    model.selectedTab = tab
                }
            }
            Spacer(minLength: model.geometry.collapsedSize.width)
            headerButton(model.isPinned ? "pin.fill" : "pin",
                         help: model.isPinned ? "Unpin panel" : "Keep panel open",
                         isOn: model.isPinned) {
                model.isPinned.toggle()
            }
            headerButton("gearshape", help: "Settings", isOn: false, action: openSettings)
        }
        .padding(.horizontal, 16)
        .frame(height: max(model.geometry.collapsedSize.height, 32))
    }

    private func headerButton(_ systemImage: String, help: String, isOn: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 24)
                .background(isOn ? .white.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text(LocalizedStringKey(help)))
    }
}
