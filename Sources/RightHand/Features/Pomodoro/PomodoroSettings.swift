import Foundation

/// Pomodoro preferences stored in UserDefaults (edited in the Settings window).
enum PomodoroSettings {
    enum Key {
        static let focusMinutes = "pomodoro.focusMinutes"
        static let shortBreakMinutes = "pomodoro.shortBreakMinutes"
        static let longBreakMinutes = "pomodoro.longBreakMinutes"
        static let sessionsBeforeLongBreak = "pomodoro.sessionsBeforeLongBreak"
        static let autoStartNext = "pomodoro.autoStartNext"
        static let focusEndSound = "pomodoro.focusEndSound"
        static let breakEndSound = "pomodoro.breakEndSound"
        static let soundVolume = "pomodoro.soundVolume"
    }

    enum Default {
        static let focusMinutes = 25
        static let shortBreakMinutes = 5
        static let longBreakMinutes = 15
        static let sessionsBeforeLongBreak = 4
        static let autoStartNext = false
        static let focusEndSound = "Glass"
        static let breakEndSound = "Hero"
        static let soundVolume = 0.8
    }

    private static var defaults: UserDefaults { .standard }

    static func registerDefaults() {
        defaults.register(defaults: [
            Key.focusMinutes: Default.focusMinutes,
            Key.shortBreakMinutes: Default.shortBreakMinutes,
            Key.longBreakMinutes: Default.longBreakMinutes,
            Key.sessionsBeforeLongBreak: Default.sessionsBeforeLongBreak,
            Key.autoStartNext: Default.autoStartNext,
            Key.focusEndSound: Default.focusEndSound,
            Key.breakEndSound: Default.breakEndSound,
            Key.soundVolume: Default.soundVolume,
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
    /// Sound names; empty = no sound.
    static var focusEndSound: String { defaults.string(forKey: Key.focusEndSound) ?? Default.focusEndSound }
    static var breakEndSound: String { defaults.string(forKey: Key.breakEndSound) ?? Default.breakEndSound }
    /// 0…1, relative to the system volume.
    static var soundVolume: Float { Float(defaults.double(forKey: Key.soundVolume)) }
}
