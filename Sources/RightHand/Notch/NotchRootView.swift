import SwiftUI

/// The black shape hanging from the notch, and the panel content when it is open.
struct NotchRootView: View {
    let model: NotchModel
    let pomodoro: PomodoroTimer
    let shelf: ShelfStore
    let tasks: TaskStore
    let calendar: CalendarStore
    let notes: NoteStore
    let chat: ChatStore
    let voice: VoiceAssistant
    let recorder: ScreenRecorder
    let sleep: SleepReminder
    let analyzer: MeetingAnalyzer
    let openReview: (URL) -> Void
    let openSettings: () -> Void
    let openProjects: () -> Void
    @State private var isDropTargeted = false
    @State private var weekStats = WeekStats()

    /// The voice card shows on the closed notch of the screen you started talking on.
    private var showsVoice: Bool {
        voice.isVisible && VoiceHUD.expands(voice.phase) && !model.isExpanded && !showsApproval
            && (voice.displayID == nil || voice.displayID == model.displayID)
    }

    /// The Pomodoro dot left of the closed notch; it steps aside while the AI works, a card shows,
    /// the panel is open or an app is full screen there.
    private var showsPomodoro: Bool {
        !model.isExpanded && !model.hidesWhenCollapsed && !showsVoice && !showsApproval && !showsSleep && !voice.isVisible
            && !(chat.isWorking && (chat.workingDisplayID == nil || chat.workingDisplayID == model.displayID))
    }

    /// A permission question opens the closed notch into a small card with the buttons, on the
    /// screen you were on — not the whole panel.
    private var showsApproval: Bool {
        !model.isExpanded && chat.waitingForApproval != nil
            && (chat.approvalDisplayID == nil || chat.approvalDisplayID == model.displayID)
    }

    /// The bedtime card, on the screen that had the mouse when it came.
    private var showsSleep: Bool {
        sleep.isVisible && !model.isExpanded && !showsApproval && !showsVoice
            && (sleep.displayID == nil || sleep.displayID == model.displayID)
    }

    private var approvalSize: CGSize {
        let collapsed = model.geometry.collapsedSize
        let hasDetail = chat.waitingForApproval?.pendingApproval?.detail != nil
        return CGSize(width: max(collapsed.width + 300, 560), height: collapsed.height + (hasDetail ? 128 : 84))
    }

    var body: some View {
        let collapsed = model.geometry.collapsedSize
        let showsRecording = recorder.state != .idle && !model.isExpanded && !showsApproval && !showsVoice && !showsSleep
        let size = model.isExpanded ? model.panelSize
            : showsApproval ? approvalSize
            : showsSleep ? SleepCard.size(for: sleep.phase, collapsed: collapsed)
            : showsVoice ? VoiceHUD.size(for: voice.phase, collapsed: collapsed)
            // While recording, the closed notch grows a little to the right for the red dot and time.
            // and for the Pomodoro dot on the left.
            : showsRecording || showsPomodoro
                ? CGSize(width: collapsed.width + max(showsRecording ? 150 : 0, showsPomodoro ? 72 : 0), height: collapsed.height)
                : collapsed
        let radius: CGFloat = model.isExpanded ? 26 : (showsVoice || showsApproval || showsSleep ? 22 : 10)
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
                    .opacity(model.isExpanded || !model.hidesWhenCollapsed || showsVoice || showsApproval || showsRecording || showsSleep
                              || showsPomodoro ? 1 : 0)
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
                } else if showsSleep {
                    SleepCard(reminder: sleep, topInset: collapsed.height)
                        .transition(.opacity)
                }
                if showsPomodoro {
                    PomodoroDot(timer: pomodoro)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        .padding(.leading, 11)
                        .transition(.opacity)
                }
                if showsRecording {
                    RecordingIndicator(recorder: recorder)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .padding(.trailing, 14)
                        .transition(.opacity)
                } else if showsVoice && !model.isExpanded {
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
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: sleep.phase)
        .animation(.easeInOut(duration: 0.4), value: pomodoro.isRunning)
        .animation(.easeInOut(duration: 0.3), value: showsPomodoro)
        .animation(.easeInOut(duration: 0.4), value: pomodoro.phase)
        .animation(.easeInOut(duration: 0.3), value: glows)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: model.isExpanded)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: model.selectedTab)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: model.showsStats)
        .animation(.easeInOut(duration: 0.2), value: model.hidesWhenCollapsed)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch model.selectedTab {
                case .pomodoro:
                    if model.showsStats {
                        StatsView(stats: weekStats) { model.showsStats = false }
                    } else {
                        PomodoroView(timer: pomodoro) { model.showsStats = true }
                    }
                case .tasks: TasksView(store: tasks, openSettings: openSettings)
                case .calendar: CalendarView(store: calendar, openSettings: openSettings)
                case .notes: NotesView(store: notes)
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
        // The tabs sit on both sides of the camera, so none ends up under it.
        let tabs = NotchTab.allCases
        let left = Array(tabs.prefix((tabs.count + 2) / 2)), right = Array(tabs.dropFirst(left.count))
        return HStack(spacing: 4) {
            ForEach(left) { tabButton($0) }
            Spacer(minLength: model.geometry.collapsedSize.width + 12)
            ForEach(right) { tabButton($0) }
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

    private func tabButton(_ tab: NotchTab) -> some View {
        headerButton(tab.systemImage, help: tab.title, isOn: model.selectedTab == tab) {
            model.selectedTab = tab
        }
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

/// Left of the closed notch, a small arc-reactor HUD: orange while you work, green on a break,
/// blue when the timer isn't running. Rings spin up when it appears, an arc shows the time left,
/// and a pulse runs out when the phase changes. Still and dimmer while paused.
private struct PomodoroDot: View {
    let timer: PomodoroTimer
    @State private var booted = false
    @State private var spin = false
    @State private var breathe = false
    /// 0 → 1 as the pulse runs out (0 means none).
    @State private var ripple = 0.0

    private var isActive: Bool { timer.isRunning || timer.isPaused }
    private var state: String { isActive ? (timer.phase == .focus ? "focus" : "break") : "idle" }
    private var color: Color {
        switch state {
        case "focus": .orange
        case "break": .green
        default: Theme.neon
        }
    }
    private var fraction: Double {
        timer.phaseDuration > 0 ? max(0, min(1, timer.remaining / timer.phaseDuration)) : 0
    }
    /// Faster while you work, slow when idle.
    private var period: Double { timer.isRunning ? (timer.phase == .focus ? 3 : 5) : 9 }

    var body: some View {
        ZStack {
            // Outer segmented ring.
            Circle()
                .trim(from: 0, to: booted ? 1 : 0)
                .stroke(color.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [2.2, 1.6]))
                .frame(width: 20, height: 20)
                .rotationEffect(.degrees(spin ? 360 : 0))
            // Two scanner arcs turning the other way.
            ForEach(0..<2) { index in
                Circle()
                    .trim(from: 0, to: booted ? 0.2 : 0)
                    .stroke(color, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                    .frame(width: 15, height: 15)
                    .rotationEffect(.degrees(Double(index) * 180 + (spin ? -360 : 0) * 1.6))
            }
            .opacity(isActive ? 0.45 : 0.9)
            // Time left in the phase.
            if isActive {
                Circle()
                    .trim(from: 0, to: booted ? fraction : 0)
                    .stroke(color, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .frame(width: 15, height: 15)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(0.9), radius: 2)
            }
            // The core.
            Circle()
                .fill(RadialGradient(colors: [.white, color, color.opacity(0.6)], center: .center, startRadius: 0, endRadius: 4))
                .frame(width: 7, height: 7)
                .scaleEffect(booted ? (breathe ? 1.12 : 0.86) : 0.2)
                .shadow(color: color, radius: breathe ? 5 : 3)
            // Pulse when the phase changes.
            Circle()
                .stroke(color, lineWidth: 1.2)
                .frame(width: 8, height: 8)
                .scaleEffect(1 + ripple * 2)
                .opacity(ripple == 0 ? 0 : 1 - ripple)
        }
        .frame(width: 22, height: 22)
        .opacity(timer.isPaused ? 0.55 : 1)
        .animation(.easeInOut(duration: 0.5), value: color)
        .animation(.easeInOut(duration: 0.5), value: fraction)
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.7).delay(0.1)) { booted = true }
            startMotion()
        }
        .onChange(of: state) { pulse() }
        .onChange(of: timer.isRunning) { startMotion() }
        .help(isActive ? timer.phase.title : L("Pomodoro"))
        .allowsHitTesting(false)
    }

    /// Spins the rings and breathes the core; stands still while paused.
    private func startMotion() {
        var still = Transaction(animation: nil)
        still.disablesAnimations = true
        withTransaction(still) { spin = false; breathe = false }
        guard !timer.isPaused else { return }
        withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) { spin = true }
        withAnimation(.easeInOut(duration: timer.isRunning ? 1.2 : 2.4).repeatForever(autoreverses: true)) { breathe = true }
    }

    private func pulse() {
        var reset = Transaction(animation: nil)
        reset.disablesAnimations = true
        withTransaction(reset) { ripple = 0 }
        withAnimation(.easeOut(duration: 0.9)) { ripple = 1 }
        startMotion()
    }
}
