import AppKit

/// Plays the Pomodoro alert sounds (the built-in macOS sounds from /System/Library/Sounds).
@MainActor
enum PomodoroSound {
    /// Names of the sounds that can be picked in Settings.
    static let available: [String] = {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        let names = files.map { ($0 as NSString).deletingPathExtension }.sorted()
        return names.isEmpty ? ["Glass", "Hero", "Ping"] : names
    }()

    // Keep a reference while it plays, otherwise the sound may stop early.
    private static var current: NSSound?

    /// Plays the sound chosen for the end of `phase`.
    static func playEnd(of phase: PomodoroPhase) {
        play(phase == .focus ? PomodoroSettings.focusEndSound : PomodoroSettings.breakEndSound)
    }

    /// Plays a sound by name at the volume from Settings; an empty name means no sound.
    static func play(_ name: String) {
        guard !name.isEmpty, let sound = NSSound(named: NSSound.Name(name)) else { return }
        current?.stop()
        sound.volume = PomodoroSettings.soundVolume
        sound.play()
        current = sound
    }
}
