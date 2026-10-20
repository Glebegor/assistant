import SwiftUI

/// The black shape hanging from the notch, and the panel content when it is open.
struct NotchRootView: View {
    let model: NotchModel
    let pomodoro: PomodoroTimer
    let shelf: ShelfStore
    let tasks: TaskStore
    let chat: ChatStore
    let voice: VoiceAssistant
    let recorder: ScreenRecorder
    let analyzer: MeetingAnalyzer
    let openReview: (URL) -> Void
    let openSettings: () -> Void
    let openProjects: () -> Void
    @State private var isDropTargeted = false

    /// The voice card shows on the closed notch of the screen you started talking on.
    private var showsVoice: Bool {
        voice.isVisible && VoiceHUD.expands(voice.phase) && !model.isExpanded && !showsApproval
            && (voice.displayID == nil || voice.displayID == model.displayID)
    }

    /// A permission question opens the closed notch into a small card with the buttons, on the
    /// screen you were on — not the whole panel.
    private var showsApproval: Bool {
        !model.isExpanded && chat.waitingForApproval != nil
            && (chat.approvalDisplayID == nil || chat.approvalDisplayID == model.displayID)
    }

    private var approvalSize: CGSize {
        let collapsed = model.geometry.collapsedSize
        let hasDetail = chat.waitingForApproval?.pendingApproval?.detail != nil
        return CGSize(width: max(collapsed.width + 300, 560), height: collapsed.height + (hasDetail ? 128 : 84))
    }

    var body: some View {
        let collapsed = model.geometry.collapsedSize
        let showsRecording = recorder.state != .idle && !model.isExpanded && !showsApproval && !showsVoice
        let size = model.isExpanded ? model.selectedTab.panelSize
            : showsApproval ? approvalSize
            : showsVoice ? VoiceHUD.size(for: voice.phase, collapsed: collapsed)
            // While recording, the closed notch grows a little to the right for the red dot and time.
            : showsRecording ? CGSize(width: collapsed.width + 150, height: collapsed.height) : collapsed
        let radius: CGFloat = model.isExpanded ? 26 : (showsVoice || showsApproval ? 22 : 10)
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
        let voiceGlows = voice.isVisible && (voice.displayID == nil || voice.displayID == model.displayID)
            && (voice.phase == .listening || voice.phase == .transcribing || voice.phase == .working
                || (voice.phase.isAnswer && SpeechPlayer.shared.currentText != nil))
        // Also while Claude or ChatGPT thinks about a typed message (on the screen it was sent from).
        let chatGlows = chat.isWorking && (chat.workingDisplayID == nil || chat.workingDisplayID == model.displayID)
        let glows = voiceGlows || chatGlows

        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                shape
                    .fill(.black)
                    .opacity(model.isExpanded || !model.hidesWhenCollapsed || showsVoice || showsApproval || showsRecording ? 1 : 0)
                if model.isExpanded {
                    content
                        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
                } else if showsApproval, let engine = chat.waitingForApproval, let approval = engine.pendingApproval {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: model.geometry.collapsedSize.height + 6)
                        NotchApprovalCard(approval: approval, provider: engine.chat.provider, engine: engine,
                                          who: voice.activeEngine === engine ? VoiceAssistant.name : nil)
                            .padding(.horizontal, 14)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(.white)
                    .transition(.opacity)
                } else if showsRecording {
                    RecordingIndicator(recorder: recorder)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .padding(.trailing, 14)
                        .transition(.opacity)
                } else if showsVoice {
                    VoiceHUD(voice: voice, topInset: model.geometry.collapsedSize.height)
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
            // The open panel fills its window, so light outside it would be cut off at the edges:
            // there it glows along the inside of its border instead.
            .overlay {
                if glows && model.isExpanded {
                    NotchGlow(radius: radius, level: voice.level, isListening: voice.phase == .listening, inside: true)
                        .transition(.opacity)
                }
            }
            .clipShape(shape)
            // Behind the closed notch and outside the clip, so it grows, shrinks and rounds its
            // corners together with the notch in the same animation.
            .background {
                if glows && !model.isExpanded {
                    NotchGlow(radius: radius, level: voice.level, isListening: voice.phase == .listening)
                        .transition(.opacity)
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: voice.phase)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showsApproval)
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
                case .recorder: RecorderView(recorder: recorder, analyzer: analyzer, openReview: openReview)
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
