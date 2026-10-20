import AppKit
import Observation
import SwiftUI

/// Reminds you to rest your eyes: every few minutes all screens dim with a short countdown.
@Observable
@MainActor
final class EyeRestController {
    private(set) var isResting = false
    private(set) var restDuration = EyeRestSettings.Default.breakSeconds
    private(set) var restRemaining = 0
    /// When the next eye break starts; nil while paused.
    private(set) var nextBreak: Date?
    /// Eye breaks are paused until this time (from "Pause for 1 hour"); kept across restarts.
    private(set) var pausedUntil: Date? = UserDefaults.standard.object(forKey: EyeRestSettings.Key.pausedUntil) as? Date {
        didSet { UserDefaults.standard.set(pausedUntil, forKey: EyeRestSettings.Key.pausedUntil) }
    }

    var isPaused: Bool { pausedUntil.map { $0 > Date() } ?? false }

    @ObservationIgnored private let pomodoro: PomodoroTimer
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var overlays: [NSPanel] = []

    init(pomodoro: PomodoroTimer) {
        self.pomodoro = pomodoro
        EyeRestSettings.registerDefaults()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer

        // Sleeping or locking the screen means you're not looking at it: start counting again.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.nextBreak = nil }
            }
        }
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        }
    }

    // MARK: Actions

    func takeBreakNow() {
        guard !isResting else { return }
        startRest()
    }

    func skip() { finishRest(completed: false) }

    func postpone() {
        finishRest(completed: false)
        nextBreak = Date().addingTimeInterval(TimeInterval(EyeRestSettings.postponeMinutes * 60))
    }

    /// Stops eye breaks for a while (ends a running break too).
    func pause(for duration: TimeInterval = EyeRestSettings.pauseDuration) {
        finishRest(completed: false)
        pausedUntil = Date().addingTimeInterval(duration)
        nextBreak = nil
    }

    func resume() {
        pausedUntil = nil
    }

    /// Turns eye rest reminders on or off (the same switch as in Settings).
    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: EyeRestSettings.Key.enabled)
        if !enabled { finishRest(completed: false) }
        pausedUntil = nil
    }

    // MARK: Scheduling

    private func tick() {
        if isResting {
            restRemaining -= 1
            if restRemaining <= 0 { finishRest(completed: true) }
            return
        }
        if let pausedUntil, pausedUntil <= Date() { self.pausedUntil = nil }
        guard EyeRestSettings.enabled, !isPaused, !isPausedForPomodoroBreak, !isAway else {
            nextBreak = nil
            return
        }
        guard let nextBreak else {
            nextBreak = Date().addingTimeInterval(EyeRestSettings.interval)
            return
        }
        if Date() >= nextBreak { startRest() }
    }

    /// A Pomodoro break is already a rest for the eyes.
    private var isPausedForPomodoroBreak: Bool {
        EyeRestSettings.pauseDuringPomodoroBreaks && pomodoro.isRunning && pomodoro.phase != .focus
    }

    /// No mouse or keyboard input for a while (reading the idle time needs no permission).
    private var isAway: Bool {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState,
                                                           eventType: CGEventType(rawValue: ~0)!)
        return idle >= EyeRestSettings.awayResetSeconds
    }

    private func settingsChanged() {
        guard !isResting, let nextBreak else { return }
        // A shorter interval takes effect right away.
        let latest = Date().addingTimeInterval(EyeRestSettings.interval)
        if nextBreak > latest { self.nextBreak = latest }
    }

    private func startRest() {
        restDuration = EyeRestSettings.breakSeconds
        restRemaining = restDuration
        isResting = true
        nextBreak = nil
        showOverlays()
    }

    private func finishRest(completed: Bool) {
        guard isResting else { return }
        isResting = false
        nextBreak = EyeRestSettings.enabled ? Date().addingTimeInterval(EyeRestSettings.interval) : nil
        hideOverlays()
        if completed { PomodoroSound.play(EyeRestSettings.endSound) }
    }

    // MARK: Overlay windows

    private func showOverlays() {
        hideOverlays(animated: false)
        let mouse = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            let panel = EyeRestPanel(screen: screen, content: EyeRestOverlayView(controller: self))
            panel.alphaValue = 0
            if screen.frame.contains(mouse) {
                panel.makeKeyAndOrderFront(nil) // so Esc works
            } else {
                panel.orderFrontRegardless()
            }
            overlays.append(panel)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.6
            overlays.forEach { $0.animator().alphaValue = 1 }
        }
    }

    private func hideOverlays(animated: Bool = true) {
        let panels = overlays
        overlays.removeAll()
        guard animated else {
            panels.forEach { $0.orderOut(nil) }
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4
            panels.forEach { $0.animator().alphaValue = 0 }
        } completionHandler: {
            panels.forEach { $0.orderOut(nil) }
        }
    }
}

/// Borderless window that covers a whole screen, above everything, with a blurred background.
private final class EyeRestPanel: NSPanel {
    init(screen: NSScreen, content: some View) {
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        setFrame(screen.frame, display: false)

        let blur = NSVisualEffectView()
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        let hosting = FirstClickHostingView(rootView: content)
        hosting.frame = blur.bounds
        hosting.autoresizingMask = [.width, .height]
        blur.addSubview(hosting)
        contentView = blur
    }

    override var canBecomeKey: Bool { true }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
