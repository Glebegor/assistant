import AppKit

/// Opens the notch panel when the mouse touches the camera area and closes it when the mouse leaves.
///
/// The window always has the expanded size; while closed it ignores the mouse, so it never
/// blocks the menu bar. SwiftUI animates the black shape between notch size and panel size.
@MainActor
final class NotchController {
    static let expandedSize = CGSize(width: 560, height: 230)
    /// How long the mouse may stay outside the open panel before it closes.
    private static let closeDelay: TimeInterval = 0.35

    private let model = NotchModel()
    private let panel = NotchPanel()
    private var screen: NSScreen?
    private var mouseMonitor: Any?
    private var exitPoller: Timer?
    private var mouseOutsideSince: Date?

    init(pomodoro: PomodoroTimer, openSettings: @escaping () -> Void) {
        panel.contentView = FirstClickHostingView(
            rootView: NotchRootView(model: model, pomodoro: pomodoro, openSettings: openSettings)
        )
        move(to: NSScreen.main ?? NSScreen.screens[0])
        panel.orderFrontRegardless()

        // Fires for mouse moves in other apps — exactly the case while the panel is closed.
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkHoverZone() }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let current = NSScreen.screens.first { $0 == self.screen } ?? NSScreen.main ?? NSScreen.screens[0]
                self.move(to: current)
            }
        }
    }

    /// Opens the panel and keeps it open (used from the menu bar).
    func showPinned() {
        model.isPinned = true
        expand(on: screen ?? NSScreen.main ?? NSScreen.screens[0])
    }

    private func checkHoverZone() {
        guard !model.isExpanded else { return }
        let mouse = NSEvent.mouseLocation
        if let hovered = NSScreen.screens.first(where: { NotchGeometry(screen: $0).hoverZone(on: $0).contains(mouse) }) {
            expand(on: hovered)
        }
    }

    private func expand(on screen: NSScreen) {
        if screen != self.screen { move(to: screen) }
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
        model.isExpanded = true
        startExitPolling()
    }

    private func collapse() {
        stopExitPolling()
        model.isExpanded = false
        model.isPinned = false
        panel.ignoresMouseEvents = true
    }

    private func move(to screen: NSScreen) {
        self.screen = screen
        model.geometry = NotchGeometry(screen: screen)
        let size = Self.expandedSize
        panel.setFrame(NSRect(x: screen.frame.midX - size.width / 2,
                              y: screen.frame.maxY - size.height,
                              width: size.width,
                              height: size.height),
                       display: true)
    }

    // While the panel is open the mouse is over our own window, so the global monitor
    // goes quiet; a light poll detects when the mouse leaves.
    private func startExitPolling() {
        guard exitPoller == nil else { return }
        mouseOutsideSince = nil
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
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
        guard !model.isPinned else { mouseOutsideSince = nil; return }
        if panel.frame.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation) {
            mouseOutsideSince = nil
        } else if let since = mouseOutsideSince {
            if Date().timeIntervalSince(since) > Self.closeDelay { collapse() }
        } else {
            mouseOutsideSince = Date()
        }
    }
}
