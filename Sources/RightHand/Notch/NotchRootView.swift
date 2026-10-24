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

    var body: some View {
        let isActive = timer.isRunning || timer.isPaused
        let fraction = isActive && timer.phaseDuration > 0 ? max(0, min(1, timer.remaining / timer.phaseDuration)) : 0
        ReactorView(state: !isActive ? .idle : timer.phase == .focus ? .focus : .rest,
                    fraction: fraction, isRunning: timer.isRunning, isPaused: timer.isPaused)
            .frame(width: 22, height: 22)
            .help(isActive ? timer.phase.title : L("Pomodoro"))
            .allowsHitTesting(false)
    }
}

/// The reactor drawn with Core Animation: the spinning and breathing run in the system's render
/// server, so they cost RightHand no CPU (SwiftUI animations would redraw every frame).
private struct ReactorView: NSViewRepresentable {
    enum State: Equatable { case idle, focus, rest }
    let state: State
    let fraction: Double
    let isRunning: Bool
    let isPaused: Bool

    func makeNSView(context: Context) -> ReactorLayerView { ReactorLayerView() }

    func updateNSView(_ view: ReactorLayerView, context: Context) {
        view.update(state: state, fraction: fraction, isRunning: isRunning, isPaused: isPaused)
    }
}

private final class ReactorLayerView: NSView {
    private let outer = CAShapeLayer()
    private let scanners = CAShapeLayer()
    private let progress = CAShapeLayer()
    private let core = CAShapeLayer()
    private let ripple = CAShapeLayer()
    private var state: ReactorView.State?
    private var motion: String?

    override init(frame: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        wantsLayer = true
        let root = layer!
        let center = CGPoint(x: 11, y: 11)
        func ring(_ radius: CGFloat) -> CGPath {
            CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2), transform: nil)
        }
        for shape in [outer, scanners, progress, core, ripple] {
            shape.frame = CGRect(x: 0, y: 0, width: 22, height: 22)
            shape.fillColor = nil
            shape.contentsScale = 2
            root.addSublayer(shape)
        }
        outer.path = ring(10)
        outer.lineWidth = 1
        outer.lineDashPattern = [2.2, 1.6]
        outer.opacity = 0.55

        // Two short arcs opposite each other.
        let arcs = CGMutablePath()
        arcs.addArc(center: center, radius: 7.5, startAngle: 0, endAngle: .pi * 0.4, clockwise: false)
        arcs.move(to: CGPoint(x: center.x - 7.5, y: center.y))
        arcs.addArc(center: center, radius: 7.5, startAngle: .pi, endAngle: .pi * 1.4, clockwise: false)
        scanners.path = arcs
        scanners.lineWidth = 1.4
        scanners.lineCap = .round

        // Starts at the top and runs clockwise.
        let top = CGMutablePath()
        top.addArc(center: center, radius: 7.5, startAngle: .pi / 2, endAngle: .pi / 2 - .pi * 2, clockwise: true)
        progress.path = top
        progress.lineWidth = 1.6
        progress.lineCap = .round
        progress.shadowOpacity = 0.9
        progress.shadowRadius = 2
        progress.shadowOffset = .zero

        core.path = ring(3.5)
        core.shadowOpacity = 1
        core.shadowRadius = 3
        core.shadowOffset = .zero

        ripple.path = ring(4)
        ripple.lineWidth = 1.2
        ripple.opacity = 0
    }

    required init?(coder: NSCoder) { nil }

    func update(state: ReactorView.State, fraction: Double, isRunning: Bool, isPaused: Bool) {
        let color: NSColor = switch state {
        case .focus: .systemOrange
        case .rest: .systemGreen
        case .idle: NSColor(red: 0.36, green: 0.66, blue: 1.0, alpha: 1)
        }
        let first = self.state == nil
        if self.state != state {
            CATransaction.begin()
            CATransaction.setAnimationDuration(first ? 0 : 0.5)
            for shape in [outer, scanners, progress, ripple] { shape.strokeColor = color.cgColor }
            core.fillColor = color.cgColor
            core.shadowColor = color.cgColor
            progress.shadowColor = color.cgColor
            CATransaction.commit()
            if first { boot() } else { pulse() }
            self.state = state
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        progress.strokeEnd = fraction
        progress.isHidden = state == .idle
        scanners.opacity = state == .idle ? 0.9 : 0.45
        layer?.opacity = isPaused ? 0.55 : 1
        CATransaction.commit()

        // Faster while you work, slow when idle, still while paused.
        let kind = isPaused ? "paused" : isRunning ? (state == .focus ? "focus" : "rest") : "idle"
        guard kind != motion else { return }
        motion = kind
        for shape in [outer, scanners, core] { shape.removeAnimation(forKey: "motion") }
        guard !isPaused else { return }
        let period: CFTimeInterval = isRunning ? (state == .focus ? 3 : 5) : 9
        outer.add(spin(period, clockwise: true), forKey: "motion")
        scanners.add(spin(period / 1.6, clockwise: false), forKey: "motion")
        let breathe = CABasicAnimation(keyPath: "transform.scale")
        breathe.fromValue = 0.86
        breathe.toValue = 1.12
        breathe.duration = isRunning ? 1.2 : 2.4
        breathe.autoreverses = true
        breathe.repeatCount = .infinity
        breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        core.add(breathe, forKey: "motion")
    }

    private func spin(_ period: CFTimeInterval, clockwise: Bool) -> CABasicAnimation {
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = clockwise ? -Double.pi * 2 : Double.pi * 2
        spin.duration = period
        spin.repeatCount = .infinity
        return spin
    }

    /// Rings draw in and the core lights up.
    private func boot() {
        for shape in [outer, scanners] {
            let draw = CABasicAnimation(keyPath: "strokeEnd")
            draw.fromValue = 0
            draw.toValue = 1
            draw.duration = 0.7
            draw.timingFunction = CAMediaTimingFunction(name: .easeOut)
            shape.add(draw, forKey: "boot")
        }
        let light = CASpringAnimation(keyPath: "transform.scale")
        light.fromValue = 0.2
        light.toValue = 1
        light.damping = 9
        light.duration = light.settlingDuration
        core.add(light, forKey: "boot")
    }

    /// A ring of light runs out from the core.
    private func pulse() {
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 1
        grow.toValue = 3
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [grow, fade]
        group.duration = 0.9
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ripple.add(group, forKey: "pulse")
    }

    /// Scale and rotation turn around the centre of the 22 pt view.
    override func layout() {
        super.layout()
        for shape in [outer, scanners, progress, core, ripple] {
            shape.bounds = CGRect(x: 0, y: 0, width: 22, height: 22)
            shape.position = CGPoint(x: bounds.midX, y: bounds.midY)
        }
    }
}
