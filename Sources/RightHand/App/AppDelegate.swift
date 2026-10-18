import AppKit

/// Creates the long-lived pieces of the app and wires them together.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let pomodoro = PomodoroTimer()
    private let shelf = ShelfStore()
    private let settingsWindow = SettingsWindowController()
    private var notch: NotchController?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifier.shared.requestAuthorization()

        let settings = settingsWindow
        let notch = NotchController(pomodoro: pomodoro, shelf: shelf, openSettings: { settings.show() })
        self.notch = notch
        statusItem = StatusItemController(
            pomodoro: pomodoro,
            showPanel: { notch.showPinned() },
            openSettings: { settings.show() }
        )
    }
}
