import SwiftUI

/// The black shape hanging from the notch, and the panel content when it is open.
struct NotchRootView: View {
    let model: NotchModel
    let pomodoro: PomodoroTimer
    let shelf: ShelfStore
    let tasks: TaskStore
    let chat: ChatStore
    let voice: VoiceAssistant
    let openSettings: () -> Void
    let openProjects: () -> Void
    @State private var isDropTargeted = false

    /// The voice card shows on the closed notch of the screen you started talking on.
    private var showsVoice: Bool {
        voice.isVisible && VoiceHUD.expands(voice.phase) && !model.isExpanded
            && (voice.displayID == nil || voice.displayID == model.displayID)
    }

    var body: some View {
        let size = model.isExpanded ? model.selectedTab.panelSize
            : (showsVoice ? VoiceHUD.size(for: voice.phase, collapsed: model.geometry.collapsedSize) : model.geometry.collapsedSize)
        let radius: CGFloat = model.isExpanded ? 26 : (showsVoice ? 22 : 10)
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
        let glows = voice.isVisible && (voice.displayID == nil || voice.displayID == model.displayID)
            && (voice.phase == .listening || voice.phase == .transcribing || voice.phase == .working
                || (voice.phase.isAnswer && SpeechPlayer.shared.currentText != nil))

        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                shape
                    .fill(.black)
                    .opacity(model.isExpanded || !model.hidesWhenCollapsed || showsVoice ? 1 : 0)
                if model.isExpanded {
                    content
                        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
                } else if showsVoice {
                    VoiceHUD(voice: voice, topInset: model.geometry.collapsedSize.height)
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
            // Behind the shape and outside the clip, so it grows, shrinks and rounds its corners
            // together with the notch in the same animation.
            .background {
                if glows {
                    NotchGlow(radius: radius, level: voice.level, isListening: voice.phase == .listening)
                        .transition(.opacity)
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: voice.phase)
        .animation(.easeInOut(duration: 0.3), value: glows)
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
                case .tasks: TasksView(store: tasks, openSettings: openSettings)
                case .shelf: ShelfView(store: shelf)
                case .chat: ChatView(store: chat, voice: voice, openSettings: openSettings, openProjects: openProjects)
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
