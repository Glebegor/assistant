import SwiftUI

/// Settings → Pomodoro: timer lengths and alert sounds.
struct PomodoroSettingsPane: View {
    @AppStorage(PomodoroSettings.Key.focusMinutes) private var focusMinutes = PomodoroSettings.Default.focusMinutes
    @AppStorage(PomodoroSettings.Key.shortBreakMinutes) private var shortBreakMinutes = PomodoroSettings.Default.shortBreakMinutes
    @AppStorage(PomodoroSettings.Key.longBreakMinutes) private var longBreakMinutes = PomodoroSettings.Default.longBreakMinutes
    @AppStorage(PomodoroSettings.Key.sessionsBeforeLongBreak) private var sessionsBeforeLongBreak = PomodoroSettings.Default.sessionsBeforeLongBreak
    @AppStorage(PomodoroSettings.Key.autoStartNext) private var autoStartNext = PomodoroSettings.Default.autoStartNext
    @AppStorage(PomodoroSettings.Key.focusEndSound) private var focusEndSound = PomodoroSettings.Default.focusEndSound
    @AppStorage(PomodoroSettings.Key.breakEndSound) private var breakEndSound = PomodoroSettings.Default.breakEndSound
    @AppStorage(PomodoroSettings.Key.soundVolume) private var soundVolume = PomodoroSettings.Default.soundVolume

    var body: some View {
        Form {
            Section("Timer") {
                SettingsStepperRow(title: "Focus", systemImage: "brain.head.profile", color: .orange,
                                   value: $focusMinutes, range: 1...120, unit: "min")
                SettingsStepperRow(title: "Short break", systemImage: "cup.and.saucer.fill", color: .green,
                                   value: $shortBreakMinutes, range: 1...60, unit: "min")
                SettingsStepperRow(title: "Long break", systemImage: "figure.walk", color: .teal,
                                   value: $longBreakMinutes, range: 1...90, unit: "min")
                SettingsStepperRow(title: "Long break after", systemImage: "repeat", color: .purple,
                                   value: $sessionsBeforeLongBreak, range: 2...10, unit: "sessions")
                Toggle(isOn: $autoStartNext) {
                    SettingsRowLabel("Start next phase automatically",
                                     subtitle: "Breaks and focus sessions follow each other without pressing Start.",
                                     systemImage: "forward.fill", color: .blue)
                }
            }

            Section("Sounds") {
                SettingsSoundRow(title: "Focus finished", systemImage: "bell.fill", color: .red, selection: $focusEndSound)
                SettingsSoundRow(title: "Break finished", systemImage: "bell.badge.fill", color: .pink, selection: $breakEndSound)
                LabeledContent {
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        Slider(value: $soundVolume, in: 0...1) { editing in
                            if !editing { PomodoroSound.play(focusEndSound) }
                        }
                        .frame(width: 160)
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                    }
                } label: {
                    SettingsRowLabel("Volume", systemImage: "speaker.wave.2.fill", color: .gray)
                }
            }
        }
        .formStyle(.grouped)
    }
}
