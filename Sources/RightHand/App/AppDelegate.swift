import AppKit

/// Creates the long-lived pieces of the app and wires them together.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let pomodoro = PomodoroTimer()
    private let shelf = ShelfStore()
    private let chat = ChatStore()
    private let projects = ProjectStore()
    private var projectsWindow: ProjectsWindowController?
    private let settingsWindow = SettingsWindowController()
    private var eyeRest: EyeRestController?
    private var blocker: URLBlocker?
    private var notch: NotchController?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifier.shared.requestAuthorization()

        let settings = settingsWindow
        let eyeRest = EyeRestController(pomodoro: pomodoro)
        self.eyeRest = eyeRest
        blocker = URLBlocker(pomodoro: pomodoro)
        let projectsWindow = ProjectsWindowController(store: projects, openSettings: { settings.show() })
        self.projectsWindow = projectsWindow
        let notch = NotchController(pomodoro: pomodoro, shelf: shelf, chat: chat,
                                    openSettings: { settings.show() }, openProjects: { projectsWindow.show() })
        self.notch = notch
        statusItem = StatusItemController(
            pomodoro: pomodoro,
            eyeRest: eyeRest,
            showPanel: { notch.showPinned() },
            openProjects: { projectsWindow.show() },
            openSettings: { settings.show() }
        )
    }
}
