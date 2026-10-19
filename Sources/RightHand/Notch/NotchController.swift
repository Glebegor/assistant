import AppKit

/// Shows a black notch at the top of every screen. When the mouse touches one, its panel
/// opens (and the panel on any other screen closes); it closes again when the mouse leaves.
///
/// Each window always has the expanded size; while closed it ignores the mouse, so it never
/// blocks the menu bar. SwiftUI animates the black shape between notch size and panel size.
@MainActor
final class NotchController {
    /// How long the mouse may stay outside the open panel before it closes.
    private static let closeDelay: TimeInterval = 0.1
    /// Length of the close animation in `NotchRootView`.
    private static let closeAnimationDuration: TimeInterval = 0.4

    /// The notch window on one screen.
    private struct ScreenNotch {
        let screen: NSScreen
        let panel: NotchPanel
        let model: NotchModel
        /// Notices drags and hovering over the closed notch.
        let catcher: NotchDropCatcher
    }

    private let pomodoro: PomodoroTimer
    private let shelf: ShelfStore
    private let chat: ChatStore
    private let tasks: TaskStore
    private let openSettings: () -> Void
    private let openProjects: () -> Void

    private var notches: [ScreenNotch] = []
    private var expanded: ScreenNotch?
    /// Tab to show when a panel opens, so switching screens keeps the same tab.
    private var lastTab: NotchTab = .pomodoro
    private var mouseMonitor: Any?
    private var clickMonitor: Any?
    private var exitPoller: Timer?
    private var mouseOutsideSince: Date?

    init(pomodoro: PomodoroTimer, shelf: ShelfStore, tasks: TaskStore, chat: ChatStore,
         openSettings: @escaping () -> Void, openProjects: @escaping () -> Void) {
        self.pomodoro = pomodoro
        self.shelf = shelf
        self.chat = chat
        self.tasks = tasks
        self.openSettings = openSettings
        self.openProjects = openProjects
        chat.onApprovalNeeded = { [weak self] in self?.showChat() }
        rebuildNotches()

        // Fires for mouse moves in other apps — exactly the case while the mouse is not over an open panel.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkHoverZones() }
        }
        // A click outside the open panel closes it (also when it's kept open for typing).
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.closeAfterOutsideClick() }
        }

        // Monitors plugged in, unplugged or rearranged.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuildNotches() }
        }

        // Entering/leaving full screen switches Spaces; switching apps can reveal a full-screen window.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleFullScreenCheck() }
            }
        }
    }

    /// Hides the closed notch on screens where an app is in full screen.
    private func updateFullScreenState() {
        let fullScreen = FullScreenDetector.fullScreenDisplays()
        for notch in notches {
            notch.model.hidesWhenCollapsed = notch.screen.displayID.map(fullScreen.contains) ?? false
            updateCatcher(of: notch)
        }
    }

    /// Checks now and again after the Space switch animation, when the window list has settled.
    private func scheduleFullScreenCheck() {
        updateFullScreenState()
        for delay in [0.4, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.updateFullScreenState()
            }
        }
    }

    /// Opens the panel on the screen with the mouse and keeps it open (used from the menu bar).
    func showPinned() {
        let mouse = NSEvent.mouseLocation
        guard let notch = notches.first(where: { $0.screen.frame.contains(mouse) }) ?? notches.first else { return }
        expand(notch)
        notch.model.isPinned = true
    }

    /// Opens the Assistant tab, e.g. when the AI asks for permission while the panel is closed.
    func showChat() {
        if let notch = expanded {
            notch.model.selectedTab = .chat
            return
        }
        showPinned()
        expanded?.model.selectedTab = .chat
    }

    private func rebuildNotches() {
        collapse()
        notches.forEach {
            $0.panel.close()
            $0.catcher.close()
        }
        notches = NSScreen.screens.map(makeNotch)
        updateFullScreenState()
    }

    private func makeNotch(on screen: NSScreen) -> ScreenNotch {
        let model = NotchModel(geometry: NotchGeometry(screen: screen))
        let panel = NotchPanel()
        panel.contentView = FirstClickHostingView(
            rootView: NotchRootView(model: model, pomodoro: pomodoro, shelf: shelf, tasks: tasks, chat: chat,
                                   openSettings: openSettings, openProjects: openProjects)
        )
        let size = NotchTab.maxPanelSize
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2,
                              y: screen.frame.maxY - size.height,
                              width: size.width,
                              height: size.height),
                       display: true)
        panel.orderFrontRegardless()

        let catcher = NotchDropCatcher()
        catcher.setFrame(model.geometry.hoverZone(on: screen), display: false)
        let notch = ScreenNotch(screen: screen, panel: panel, model: model, catcher: catcher)
        catcher.onActivate = { [weak self, weak panel] in
            guard let self, let match = self.notches.first(where: { $0.panel === panel }) else { return }
            // A drag from another app is almost always meant for the Shelf.
            let isDragging = NSEvent.pressedMouseButtons != 0
            self.expand(match)
            if isDragging { match.model.selectedTab = .shelf }
        }
        updateCatcher(of: notch)
        return notch
    }

    private func checkHoverZones() {
        let mouse = NSEvent.mouseLocation
        guard let hovered = notches.first(where: { $0.model.geometry.hoverZone(on: $0.screen).contains(mouse) }),
              hovered.panel !== expanded?.panel
        else { return }
        expand(hovered)
    }

    private func expand(_ notch: ScreenNotch) {
        if notch.panel !== expanded?.panel {
            collapse()
            notch.model.selectedTab = lastTab
        }
        expanded = notch
        notch.panel.ignoresMouseEvents = false
        notch.panel.orderFrontRegardless()
        notch.model.isExpanded = true
        updateCatcher(of: notch)
        startExitPolling()
    }

    private func collapse() {
        stopExitPolling()
        guard let notch = expanded else { return }
        lastTab = notch.model.selectedTab
        notch.model.isExpanded = false
        notch.model.isPinned = false
        notch.panel.ignoresMouseEvents = true
        expanded = nil
        updateCatcher(of: notch)
        returnKeyboardFocus(from: notch)
    }

    /// The catcher sits over the closed notch only: not while the panel is open, and not
    /// over full-screen apps (where it would block clicks at the top of the screen).
    private func updateCatcher(of notch: ScreenNotch) {
        if notch.model.isExpanded || notch.model.hidesWhenCollapsed {
            notch.catcher.orderOut(nil)
        } else {
            notch.catcher.orderFrontRegardless()
        }
    }

    /// After typing in the panel (e.g. a folder name) it holds the keyboard. Once it has
    /// closed, hide and re-show it so the keyboard goes back to the app you were using.
    private func returnKeyboardFocus(from notch: ScreenNotch) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeAnimationDuration) { [weak self] in
            guard let self, notch.panel.isKeyWindow, notch.panel !== self.expanded?.panel else { return }
            notch.panel.orderOut(nil)
            notch.panel.orderFrontRegardless()
        }
    }

    // While a panel is open the mouse is over our own window, so the global monitor
    // goes quiet; a light poll detects when the mouse leaves.
    private func startExitPolling() {
        guard exitPoller == nil else { return }
        mouseOutsideSince = nil
        let timer = Timer(timeInterval: 0.025, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkMouseLeft() }
        }
        RunLoop.main.add(timer, forMode: .common)
        exitPoller = timer
    }

    private func stopExitPolling() {
        exitPoller?.invalidate()
        exitPoller = nil
    }

    private func checkMouseLeft() {
        guard let notch = expanded, !notch.model.isPinned, !isTyping(in: notch) else { mouseOutsideSince = nil; return }
        // Stay open while a mouse button is held, so dragging files in or out isn't interrupted.
        if NSEvent.pressedMouseButtons != 0 || visibleFrame(of: notch).insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation) {
            mouseOutsideSince = nil
        } else if let since = mouseOutsideSince {
            if Date().timeIntervalSince(since) > Self.closeDelay { collapse() }
        } else {
            mouseOutsideSince = Date()
        }
    }

    /// Screen area of the open panel on its current tab (the window itself is bigger).
    private func visibleFrame(of notch: ScreenNotch) -> NSRect {
        let size = notch.model.selectedTab.panelSize
        let window = notch.panel.frame
        return NSRect(x: window.midX - size.width / 2, y: window.maxY - size.height,
                      width: size.width, height: size.height)
    }

    /// While you type in the chat the panel stays open even if the mouse leaves; a click outside closes it.
    private func isTyping(in notch: ScreenNotch) -> Bool {
        notch.model.selectedTab == .chat && notch.panel.isKeyWindow
    }

    private func closeAfterOutsideClick() {
        guard let notch = expanded, !notch.model.isPinned,
              !visibleFrame(of: notch).contains(NSEvent.mouseLocation)
        else { return }
        collapse()
    }
}
