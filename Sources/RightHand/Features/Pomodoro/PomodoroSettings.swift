import Foundation

/// Pomodoro preferences stored in UserDefaults (edited in the Settings window).
enum PomodoroSettings {
    enum Key {
        static let focusMinutes = "pomodoro.focusMinutes"
        static let shortBreakMinutes = "pomodoro.shortBreakMinutes"
        static let longBreakMinutes = "pomodoro.longBreakMinutes"
        static let sessionsBeforeLongBreak = "pomodoro.sessionsBeforeLongBreak"
        static let autoStartNext = "pomodoro.autoStartNext"
    }

    enum Default {
        static let focusMinutes = 25
        static let shortBreakMinutes = 5
        static let longBreakMinutes = 15
        static let sessionsBeforeLongBreak = 4
        static let autoStartNext = false
    }

    private static var defaults: UserDefaults { .standard }

    static func registerDefaults() {
        defaults.register(defaults: [
            Key.focusMinutes: Default.focusMinutes,
            Key.shortBreakMinutes: Default.shortBreakMinutes,
            Key.longBreakMinutes: Default.longBreakMinutes,
            Key.sessionsBeforeLongBreak: Default.sessionsBeforeLongBreak,
            Key.autoStartNext: Default.autoStartNext,
        ])
    }

    static func duration(for phase: PomodoroPhase) -> TimeInterval {
        let minutes = switch phase {
        case .focus: defaults.integer(forKey: Key.focusMinutes)
        case .shortBreak: defaults.integer(forKey: Key.shortBreakMinutes)
        case .longBreak: defaults.integer(forKey: Key.longBreakMinutes)
        }
        return TimeInterval(max(1, minutes) * 60)
    }

    static var sessionsBeforeLongBreak: Int { max(1, defaults.integer(forKey: Key.sessionsBeforeLongBreak)) }
    static var autoStartNext: Bool { defaults.bool(forKey: Key.autoStartNext) }
}
