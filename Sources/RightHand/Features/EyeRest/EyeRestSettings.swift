import Foundation

/// Eye rest preferences stored in UserDefaults (edited in Settings → Eye Rest).
enum EyeRestSettings {
    enum Key {
        static let enabled = "eyeRest.enabled"
        static let intervalMinutes = "eyeRest.intervalMinutes"
        static let breakSeconds = "eyeRest.breakSeconds"
        static let pauseDuringPomodoroBreaks = "eyeRest.pauseDuringPomodoroBreaks"
        static let endSound = "eyeRest.endSound"
        /// "Pause 1 hour" is remembered, so restarting RightHand doesn't end the pause.
        static let pausedUntil = "eyeRest.pausedUntil"
    }

    // The 20-20-20 rule: every 20 minutes, look 20 feet away for 20 seconds.
    enum Default {
        static let enabled = true
        static let intervalMinutes = 20
        static let breakSeconds = 20
        static let pauseDuringPomodoroBreaks = true
        static let endSound = "Tink"
    }

    /// Being away from the Mac this long counts as an eye break.
    static let awayResetSeconds: TimeInterval = 120
    static let postponeMinutes = 5
    /// "Pause for 1 hour" in the menu bar and on the break screen.
    static let pauseDuration: TimeInterval = 60 * 60

    private static var defaults: UserDefaults { .standard }

    static func registerDefaults() {
        defaults.register(defaults: [
            Key.enabled: Default.enabled,
            Key.intervalMinutes: Default.intervalMinutes,
            Key.breakSeconds: Default.breakSeconds,
            Key.pauseDuringPomodoroBreaks: Default.pauseDuringPomodoroBreaks,
            Key.endSound: Default.endSound,
        ])
    }

    static var enabled: Bool { defaults.bool(forKey: Key.enabled) }
    static var interval: TimeInterval { TimeInterval(max(1, defaults.integer(forKey: Key.intervalMinutes)) * 60) }
    static var breakSeconds: Int { max(5, defaults.integer(forKey: Key.breakSeconds)) }
    static var pauseDuringPomodoroBreaks: Bool { defaults.bool(forKey: Key.pauseDuringPomodoroBreaks) }
    static var endSound: String { defaults.string(forKey: Key.endSound) ?? Default.endSound }
}
