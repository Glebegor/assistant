import AppKit

/// Blocks the sites from Settings → Blocking while a Pomodoro focus session runs:
/// a browser tab that shows a blocked address is switched to the block page.
@MainActor
final class URLBlocker {
    private let pomodoro: PomodoroTimer
    private let tabs = BrowserTabs()
    private var rules: [BlockRule] = []
    private var timer: Timer?
    private var isChecking = false

    init(pomodoro: PomodoroTimer) {
        self.pomodoro = pomodoro
        BlockerSettings.registerDefaults()
        rules = BlockerSettings.rules
        BlockPage.install()

        observeChanges { [weak self] in self?.update() }
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.rules = BlockerSettings.rules
                self.update()
            }
        }
    }

    /// Starts or stops checking tabs. Reading the Pomodoro state here makes
    /// `observeChanges` call this again whenever a focus session starts or ends.
    private func update() {
        let active = BlockerSettings.enabled && !rules.isEmpty && pomodoro.isRunning && pomodoro.phase == .focus
        if active, timer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkTabs() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
            checkTabs()
        } else if !active {
            timer?.invalidate()
            timer = nil
        }
    }

    private func checkTabs() {
        let browsers = Browser.running // only running browsers, so we never launch one
        guard !isChecking, !browsers.isEmpty else { return }
        isChecking = true
        let rules = rules
        let focusEnds = Date().addingTimeInterval(pomodoro.remaining)
        let tabs = tabs

        tabs.queue.async {
            for browser in browsers {
                for tab in tabs.visibleTabs(of: browser) where ["http", "https"].contains(tab.url.scheme) {
                    guard rules.contains(where: { $0.matches(tab.url) }) else { continue }
                    tabs.open(BlockPage.url(blocking: tab.url, focusEnds: focusEnds), in: tab)
                }
            }
            Task { @MainActor [weak self] in self?.isChecking = false }
        }
    }
}
