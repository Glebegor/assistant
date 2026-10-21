import AppKit
import Observation

enum PomodoroPhase {
    case focus, shortBreak, longBreak

    var title: String {
        switch self {
        case .focus: L("Focus")
        case .shortBreak: L("Short Break")
        case .longBreak: L("Long Break")
        }
    }
}

/// The Pomodoro state machine: focus → break → focus → … → long break.
/// `@Observable` makes SwiftUI views and the menu bar refresh when its properties change.
@Observable
@MainActor
final class PomodoroTimer {
    private(set) var phase: PomodoroPhase = .focus
    private(set) var phaseDuration: TimeInterval
    private(set) var remaining: TimeInterval
    private(set) var isRunning = false
    /// Focus sessions finished since launch.
    private(set) var completedFocusSessions = 0

    // The end time is stored instead of counting ticks, so the timer stays exact after sleep.
    @ObservationIgnored private var endDate: Date?
    @ObservationIgnored private var ticker: Timer?
    /// True until the current phase is started; used to apply new settings right away.
    @ObservationIgnored private var isFresh = true

    init() {
        PomodoroSettings.registerDefaults()
        let duration = PomodoroSettings.duration(for: .focus)
        phaseDuration = duration
        remaining = duration

        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.settingsChanged() }
        }
    }

    var progress: Double { phaseDuration > 0 ? 1 - remaining / phaseDuration : 0 }

    /// Paused in the middle of a phase (as opposed to not started yet).
    var isPaused: Bool { !isRunning && remaining < phaseDuration }

    var sessionsBeforeLongBreak: Int { PomodoroSettings.sessionsBeforeLongBreak }
    var sessionInCycle: Int { completedFocusSessions % sessionsBeforeLongBreak }

    var formattedRemaining: String {
        let total = Int(remaining.rounded(.up))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    func toggle() { isRunning ? pause() : start() }

    func start() {
        guard !isRunning else { return }
        isFresh = false
        endDate = Date().addingTimeInterval(remaining)
        isRunning = true
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common) // .common keeps it ticking while menus are open
        ticker = timer
    }

    func pause() {
        guard isRunning else { return }
        tick()
        stop()
    }

    func reset() {
        stop()
        remaining = phaseDuration
        isFresh = true
    }

    func skip() { advance(completed: false) }

    private func tick() {
        guard let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining <= 0 { advance(completed: true) }
    }

    private func stop() {
        ticker?.invalidate()
        ticker = nil
        endDate = nil
        isRunning = false
    }

    private func advance(completed: Bool) {
        let finished = phase
        let finishedMinutes = Int((phaseDuration / 60).rounded())
        stop()
        if completed, finished == .focus { ActivityLog.shared.focusFinished(minutes: finishedMinutes) }

        switch finished {
        case .focus:
            if completed { completedFocusSessions += 1 }
            let longBreakDue = completed && sessionInCycle == 0
            phase = longBreakDue ? .longBreak : .shortBreak
        case .shortBreak, .longBreak:
            phase = .focus
        }
        phaseDuration = PomodoroSettings.duration(for: phase)
        remaining = phaseDuration
        isFresh = true

        guard completed else { return }
        PomodoroSound.playEnd(of: finished)
        Notifier.shared.notify(
            title: finished == .focus ? L("Focus session done") : L("Break is over"),
            body: finished != .focus ? L("Ready to focus again?")
                : (phase == .longBreak ? L("Time for a long break.") : L("Time for a short break.")),
            playsSound: false // the Pomodoro sound above is enough
        )
        if PomodoroSettings.autoStartNext { start() }
    }

    private func settingsChanged() {
        guard isFresh, !isRunning else { return }
        let newDuration = PomodoroSettings.duration(for: phase)
        guard newDuration != phaseDuration else { return }
        phaseDuration = newDuration
        remaining = newDuration
    }
}
