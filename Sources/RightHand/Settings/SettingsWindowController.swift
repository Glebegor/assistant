import AppKit
import SwiftUI

/// The Settings window: a native toolbar with one tab per pane.
@MainActor
final class SettingsWindowController {
    static let paneWidth: CGFloat = 500

    private var window: NSWindow?

    func show() {
        if window == nil { window = makeWindow() }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let tabs = SettingsTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(pane(PomodoroSettingsPane(), title: "Pomodoro", systemImage: "timer"))
        tabs.addTabViewItem(pane(EyeRestSettingsPane(), title: "Eye Rest", systemImage: "eye"))
        tabs.addTabViewItem(pane(ShelfSettingsPane(), title: "Shelf", systemImage: "tray.full"))
        tabs.addTabViewItem(pane(BlockerSettingsPane(), title: "Blocking", systemImage: "hand.raised"))
        tabs.addTabViewItem(pane(AboutPane(), title: "About", systemImage: "info.circle"))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        tabs.fitWindowToSelectedPane(animated: false)
        window.center()
        return window
    }

    private func pane(_ content: some View, title: String, systemImage: String) -> NSTabViewItem {
        let controller = NSHostingController(rootView: content.frame(width: Self.paneWidth).fixedSize())
        controller.title = title
        let item = NSTabViewItem(viewController: controller)
        item.label = title
        item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        return item
    }
}

/// Resizes the window to each pane's height when you switch tabs (top edge stays in place).
final class SettingsTabViewController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        fitWindowToSelectedPane(animated: true)
    }

    func fitWindowToSelectedPane(animated: Bool) {
        guard let window = view.window ?? tabViewItems.first?.viewController?.view.window,
              let pane = tabViewItems[safe: selectedTabViewItemIndex]?.viewController?.view
        else { return }
        let contentSize = pane.fittingSize
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true, animate: animated && window.isVisible)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
