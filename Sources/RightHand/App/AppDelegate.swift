import AppKit

/// Creates the long-lived pieces of the app and wires them together.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let pomodoro = PomodoroTimer()
    private let shelf = ShelfStore()
    private let chat = ChatStore()
    private let tasks = TaskStore()
    private let calendar = CalendarStore()
    private let notes = NoteStore()
    private lazy var voice = VoiceAssistant(chat: chat)
    private let recorder = ScreenRecorder()
    private let sleep = SleepReminder()
    private let analyzer = MeetingAnalyzer()
    private lazy var reviewWindows = MeetingReviewWindowController(analyzer: analyzer)
    private let projects = ProjectStore()
    private var projectsWindow: ProjectsWindowController?
    private lazy var settingsWindow = SettingsWindowController(tasks: tasks)
    private var eyeRest: EyeRestController?
    private var habitReminders: HabitReminders?
    private var blocker: URLBlocker?
    private var notch: NotchController?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Notifier.shared.requestAuthorization()
        Updater.shared.startChecking()
        ModelCatalog.shared.refreshAll()
        habitReminders = HabitReminders()

        let settings = settingsWindow
        let eyeRest = EyeRestController(pomodoro: pomodoro)
        let recorder = self.recorder
        eyeRest.holdsBreaks = { recorder.isRecording }
        sleep.isSuppressed = { recorder.isRecording }
        self.eyeRest = eyeRest
        blocker = URLBlocker(pomodoro: pomodoro)
        let projectsWindow = ProjectsWindowController(store: projects, openSettings: { settings.show() })
        self.projectsWindow = projectsWindow
        let notch = NotchController(pomodoro: pomodoro, shelf: shelf, tasks: tasks, calendar: calendar, notes: notes, chat: chat, voice: voice, recorder: recorder, sleep: sleep,
                                    analyzer: analyzer, openReview: { [weak self] in self?.reviewWindows.show($0) },
                                    openSettings: { settings.show() }, openProjects: { projectsWindow.show() })
        self.notch = notch
        statusItem = StatusItemController(
            pomodoro: pomodoro,
            eyeRest: eyeRest,
            voice: voice,
            recorder: recorder,
            showPanel: { notch.showPinned() },
            openProjects: { projectsWindow.show() },
            openSettings: { settings.show() }
        )
    }

    /// righthand://note/<id> links (from the chat, or pasted anywhere) open the note.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let id = NotesFile.noteID(in: url) { notch?.showNote(id) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        notes.flush()
    }
}
