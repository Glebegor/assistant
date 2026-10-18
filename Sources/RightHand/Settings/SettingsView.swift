import AppKit
import SwiftUI

struct SettingsView: View {
    @AppStorage(PomodoroSettings.Key.focusMinutes) private var focusMinutes = PomodoroSettings.Default.focusMinutes
    @AppStorage(PomodoroSettings.Key.shortBreakMinutes) private var shortBreakMinutes = PomodoroSettings.Default.shortBreakMinutes
    @AppStorage(PomodoroSettings.Key.longBreakMinutes) private var longBreakMinutes = PomodoroSettings.Default.longBreakMinutes
    @AppStorage(PomodoroSettings.Key.sessionsBeforeLongBreak) private var sessionsBeforeLongBreak = PomodoroSettings.Default.sessionsBeforeLongBreak
    @AppStorage(PomodoroSettings.Key.autoStartNext) private var autoStartNext = PomodoroSettings.Default.autoStartNext

    var body: some View {
        Form {
            Section("Pomodoro") {
                Stepper("Focus: \(focusMinutes) min", value: $focusMinutes, in: 1...120)
                Stepper("Short break: \(shortBreakMinutes) min", value: $shortBreakMinutes, in: 1...60)
                Stepper("Long break: \(longBreakMinutes) min", value: $longBreakMinutes, in: 1...90)
                Stepper("Long break after \(sessionsBeforeLongBreak) sessions", value: $sessionsBeforeLongBreak, in: 2...10)
                Toggle("Start next phase automatically", isOn: $autoStartNext)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }
}

/// Plain window hosting `SettingsView`, opened from the menu bar or the notch panel.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "RightHand Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
