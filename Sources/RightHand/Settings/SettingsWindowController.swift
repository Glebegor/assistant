import AppKit
import SwiftUI

/// The Settings window: a native toolbar with one tab per pane.
@MainActor
final class SettingsWindowController {
    static let paneWidth: CGFloat = 500

    private var window: NSWindow?
    private weak var tabs: SettingsTabViewController?
    private let tasks: TaskStore

    init(tasks: TaskStore) {
        self.tasks = tasks
    }

    func show() {
        if window == nil { window = makeWindow() }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let tabs = SettingsTabViewController()
        tabs.tabStyle = .toolbar
        self.tabs = tabs
        tabs.addTabViewItem(pane(GeneralSettingsPane(), title: "General", systemImage: "gearshape"))
        tabs.addTabViewItem(pane(PomodoroSettingsPane(), title: "Pomodoro", systemImage: "timer"))
        tabs.addTabViewItem(pane(EyeRestSettingsPane(), title: "Eye Rest", systemImage: "eye"))
        tabs.addTabViewItem(pane(TasksSettingsPane(store: tasks), title: "Tasks", systemImage: "checklist"))
        tabs.addTabViewItem(pane(ShelfSettingsPane(), title: "Shelf", systemImage: "tray.full"))
        tabs.addTabViewItem(pane(BlockerSettingsPane(), title: "Blocking", systemImage: "hand.raised"))
        tabs.addTabViewItem(pane(AssistantSettingsPane(), title: "Assistant", systemImage: "sparkles"))
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
        let root = SettingsPaneContainer(content: content, width: Self.paneWidth) { [weak self] in
            self?.tabs?.fitWindowToSelectedPane(animated: true)
        }
        let controller = NSHostingController(rootView: root)
        controller.title = L(title)
        let item = NSTabViewItem(viewController: controller)
        item.label = L(title)
        item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: title)
        return item
    }
}

/// A pane as tall as its content but never taller than the screen; the rest scrolls.
private struct SettingsPaneContainer<Content: View>: View {
    let content: Content
    let width: CGFloat
    /// Called when the content grows or shrinks (e.g. Notion databases loaded), to resize the window.
    let onHeightChange: @MainActor () -> Void

    /// Leaves room for the menu bar, the window's toolbar and a margin.
    private var maxHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 800) - 140
    }

    var body: some View {
        ScrollView {
            content
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { _ in
                    DispatchQueue.main.async { onHeightChange() }
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: width)
        .frame(maxHeight: maxHeight)
        .fixedSize(horizontal: false, vertical: true)
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
        // Keep the whole window on screen: move it up when it would reach below the Dock.
        if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
            frame.origin.y = min(max(frame.origin.y, visible.minY), visible.maxY - frame.height)
        }
        window.setFrame(frame, display: true, animate: animated && window.isVisible)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
