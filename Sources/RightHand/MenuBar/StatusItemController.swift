import AppKit

/// Menu bar icon: shows the Pomodoro countdown and a menu with quick controls.
@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let pomodoro: PomodoroTimer
    private let showPanel: () -> Void
    private let takeEyeBreak: () -> Void
    private let openSettings: () -> Void
    private let toggleTimerItem = NSMenuItem(title: "", action: #selector(toggleTimer), keyEquivalent: "")

    init(pomodoro: PomodoroTimer, showPanel: @escaping () -> Void, takeEyeBreak: @escaping () -> Void,
         openSettings: @escaping () -> Void) {
        self.pomodoro = pomodoro
        self.showPanel = showPanel
        self.takeEyeBreak = takeEyeBreak
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
        menu.addItem(toggleTimerItem)
        menu.addItem(NSMenuItem(title: "Reset Timer", action: #selector(resetTimer), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Skip Phase", action: #selector(skipPhase), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Show Panel", action: #selector(showPanelAction), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Take an Eye Break", action: #selector(takeEyeBreakAction), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettingsAction), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit RightHand", action: #selector(quit), keyEquivalent: "q"))
        for menuItem in menu.items { menuItem.target = self }
        return menu
    }

    private func render() {
        let showsTime = pomodoro.isRunning || pomodoro.isPaused
        item.button?.title = showsTime ? " \(pomodoro.formattedRemaining)" : ""
        toggleTimerItem.title = pomodoro.isRunning
            ? "Pause \(pomodoro.phase.title)"
            : "\(pomodoro.isPaused ? "Resume" : "Start") \(pomodoro.phase.title)"
    }

    @objc private func toggleTimer() { pomodoro.toggle() }
    @objc private func resetTimer() { pomodoro.reset() }
    @objc private func skipPhase() { pomodoro.skip() }
    @objc private func showPanelAction() { showPanel() }
    @objc private func takeEyeBreakAction() { takeEyeBreak() }
    @objc private func openSettingsAction() { openSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}
