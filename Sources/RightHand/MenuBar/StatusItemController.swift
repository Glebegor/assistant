import AppKit

/// Menu bar icon: shows the Pomodoro countdown and a menu with quick controls.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let pomodoro: PomodoroTimer
    private let eyeRest: EyeRestController
    private let showPanel: () -> Void
    private let openProjects: () -> Void
    private let voice: VoiceAssistant
    private let recorder: ScreenRecorder
    private let recordItem = NSMenuItem(title: "", action: #selector(record), keyEquivalent: "")
    private let updateItem = NSMenuItem(title: "", action: #selector(update), keyEquivalent: "")
    private let talkItem = NSMenuItem(title: "", action: #selector(talk), keyEquivalent: "")
    private let openSettings: () -> Void
    private let toggleTimerItem = NSMenuItem(title: "", action: #selector(toggleTimer), keyEquivalent: "")
    private let eyeRestEnabledItem = NSMenuItem(title: L("Eye Rest Reminders"), action: #selector(toggleEyeRest), keyEquivalent: "")
    private let eyeRestPauseItem = NSMenuItem(title: "", action: #selector(pauseOrResumeEyeRest), keyEquivalent: "")
    private let eyeBreakNowItem = NSMenuItem(title: L("Take an Eye Break Now"), action: #selector(takeEyeBreak), keyEquivalent: "")

    init(pomodoro: PomodoroTimer, eyeRest: EyeRestController, voice: VoiceAssistant, recorder: ScreenRecorder,
         showPanel: @escaping () -> Void, openProjects: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.pomodoro = pomodoro
        self.eyeRest = eyeRest
        self.showPanel = showPanel
        self.openProjects = openProjects
        self.voice = voice
        self.recorder = recorder
        self.openSettings = openSettings
        super.init()

        if let button = item.button {
            button.image = NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: "RightHand")
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }
        item.menu = makeMenu()

        observeChanges { [weak self] in self?.render() }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(toggleTimerItem)
        menu.addItem(NSMenuItem(title: L("Reset Timer"), action: #selector(resetTimer), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L("Skip Phase"), action: #selector(skipPhase), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(eyeRestEnabledItem)
        menu.addItem(eyeRestPauseItem)
        menu.addItem(eyeBreakNowItem)
        menu.addItem(.separator())
        talkItem.target = self
        menu.addItem(talkItem)
        recordItem.target = self
        menu.addItem(recordItem)
        menu.addItem(NSMenuItem(title: L("Show Panel"), action: #selector(showPanelAction), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L("Projects…"), action: #selector(openProjectsAction), keyEquivalent: "p"))
        menu.addItem(NSMenuItem(title: L("Settings…"), action: #selector(openSettingsAction), keyEquivalent: ","))
        updateItem.target = self
        menu.addItem(updateItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("Quit RightHand"), action: #selector(quit), keyEquivalent: "q"))
        for menuItem in menu.items { menuItem.target = self }
        return menu
    }

    private func render() {
        let showsTime = pomodoro.isRunning || pomodoro.isPaused
        item.button?.title = showsTime ? " \(pomodoro.formattedRemaining)" : ""
        toggleTimerItem.title = pomodoro.isRunning ? L("Pause %@", pomodoro.phase.title)
            : (pomodoro.isPaused ? L("Resume %@", pomodoro.phase.title) : L("Start %@", pomodoro.phase.title))
    }

    // Eye rest items are refreshed each time the menu opens.
    func menuNeedsUpdate(_ menu: NSMenu) {
        talkItem.isHidden = !voice.isEnabled
        switch Updater.shared.state {
        case .available(let release): updateItem.title = L("Update to %@…", release.version)
        case .downloading(let value): updateItem.title = L("Downloading update… %lld%%", Int(value * 100))
        case .installing: updateItem.title = L("Installing update…")
        case .checking: updateItem.title = L("Checking for updates…")
        default: updateItem.title = L("Check for Updates…")
        }
        recordItem.title = recorder.isRecording ? L("Stop Screen Recording (%@)", RecorderView.duration(recorder.elapsed)) : L("Record Screen")
        talkItem.title = voice.phase == .listening ? L("Stop Recording and Send") : L("Talk to %@ (%@)", VoiceAssistant.name, Shortcut.voice.displayName)

        let enabled = EyeRestSettings.enabled
        eyeRestEnabledItem.state = enabled ? .on : .off

        eyeRestPauseItem.isHidden = !enabled
        eyeBreakNowItem.isHidden = !enabled
        if let pausedUntil = eyeRest.pausedUntil, eyeRest.isPaused {
            let time = pausedUntil.formatted(date: .omitted, time: .shortened)
            eyeRestPauseItem.title = L("Resume Eye Rest (paused until %@)", time)
        } else {
            eyeRestPauseItem.title = L("Pause Eye Rest for 1 Hour")
        }
    }

    @objc private func toggleTimer() { pomodoro.toggle() }
    @objc private func resetTimer() { pomodoro.reset() }
    @objc private func skipPhase() { pomodoro.skip() }
    @objc private func toggleEyeRest() { eyeRest.setEnabled(!EyeRestSettings.enabled) }
    @objc private func pauseOrResumeEyeRest() { eyeRest.isPaused ? eyeRest.resume() : eyeRest.pause() }
    @objc private func takeEyeBreak() { eyeRest.takeBreakNow() }
    @objc private func showPanelAction() { showPanel() }
    @objc private func openProjectsAction() { openProjects() }
    @objc private func talk() { voice.toggle() }
    @objc private func update() {
        let updater = Updater.shared
        if let release = updater.available { return updater.offer(release) }
        Task {
            await updater.check()
            switch updater.state {
            case .available(let release): updater.offer(release)
            case .upToDate: Notifier.shared.notify(title: L("RightHand is up to date"), body: L("Version %@", Updater.currentVersion), playsSound: false)
            case .failed(let message): Notifier.shared.notify(title: L("Couldn't check for updates"), body: message, playsSound: false)
            default: break
            }
        }
    }
    @objc private func record() {
        // Start uses the screen and sound chosen in the Record tab.
        if !recorder.isRecording, recorder.displays.isEmpty { Task { await recorder.loadDisplays(); recorder.toggle() } } else { recorder.toggle() }
    }
    @objc private func openSettingsAction() { openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}
