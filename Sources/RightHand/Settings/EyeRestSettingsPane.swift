import SwiftUI

/// Settings → Eye Rest: how often and how long the eye breaks are.
struct EyeRestSettingsPane: View {
    @AppStorage(EyeRestSettings.Key.enabled) private var enabled = EyeRestSettings.Default.enabled
    @AppStorage(EyeRestSettings.Key.intervalMinutes) private var intervalMinutes = EyeRestSettings.Default.intervalMinutes
    @AppStorage(EyeRestSettings.Key.breakSeconds) private var breakSeconds = EyeRestSettings.Default.breakSeconds
    @AppStorage(EyeRestSettings.Key.pauseDuringPomodoroBreaks) private var pauseDuringPomodoroBreaks = EyeRestSettings.Default.pauseDuringPomodoroBreaks
    @AppStorage(EyeRestSettings.Key.endSound) private var endSound = EyeRestSettings.Default.endSound

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $enabled) {
                    SettingsRowLabel("Remind me to rest my eyes",
                                     subtitle: "The 20-20-20 rule: every 20 minutes, look 20 feet (6 m) away for 20 seconds.",
                                     systemImage: "eye.fill", color: .teal)
                }
            }

            Section {
                SettingsStepperRow(title: "Every", systemImage: "timer", color: .orange,
                                   value: $intervalMinutes, range: 5...120, step: 5, unit: "min")
                SettingsStepperRow(title: "Break length", systemImage: "hourglass", color: .blue,
                                   value: $breakSeconds, range: 10...120, step: 5, unit: "sec")
                Toggle(isOn: $pauseDuringPomodoroBreaks) {
                    SettingsRowLabel("Pause during Pomodoro breaks",
                                     subtitle: "A Pomodoro break already rests your eyes.",
                                     systemImage: "cup.and.saucer.fill", color: .green)
                }
                SettingsSoundRow(title: "Break finished", systemImage: "bell.fill", color: .pink, selection: $endSound)
            } header: {
                Text("Schedule")
            } footer: {
                SettingsFooter("The timer starts over when you're away from the Mac for 2 minutes or lock the screen. During a break press Esc to skip.")
            }
            .disabled(!enabled)
        }
        .formStyle(.grouped)
    }
}
