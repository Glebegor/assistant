import AppKit

/// Menu bar icon: shows the Pomodoro countdown and a menu with quick controls.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let pomodoro: PomodoroTimer
    private let eyeRest: EyeRestController
    private let showPanel: () -> Void
    private let openProjects: () -> Void
    private let openSettings: () -> Void
    private let toggleTimerItem = NSMenuItem(title: "", action: #selector(toggleTimer), keyEquivalent: "")
    private let eyeRestEnabledItem = NSMenuItem(title: L("Eye Rest Reminders"), action: #selector(toggleEyeRest), keyEquivalent: "")
    private let eyeRestPauseItem = NSMenuItem(title: "", action: #selector(pauseOrResumeEyeRest), keyEquivalent: "")
    private let eyeBreakNowItem = NSMenuItem(title: L("Take an Eye Break Now"), action: #selector(takeEyeBreak), keyEquivalent: "")

    init(pomodoro: PomodoroTimer, eyeRest: EyeRestController,
         showPanel: @escaping () -> Void, openProjects: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.pomodoro = pomodoro
        self.eyeRest = eyeRest
        self.showPanel = showPanel
        self.openProjects = openProjects
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
        menu.addItem(NSMenuItem(title: L("Show Panel"), action: #selector(showPanelAction), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L("Projects…"), action: #selector(openProjectsAction), keyEquivalent: "p"))
        menu.addItem(NSMenuItem(title: L("Settings…"), action: #selector(openSettingsAction), keyEquivalent: ","))
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
    @objc private func openSettingsAction() { openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}
