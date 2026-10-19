import AppKit
import SwiftUI

/// The big Projects window. While it's open RightHand shows a Dock icon, so it's easy to switch to.
@MainActor
final class ProjectsWindowController: NSObject, NSWindowDelegate {
    private let store: ProjectStore
    private let openSettings: () -> Void
    private var window: NSWindow?

    init(store: ProjectStore, openSettings: @escaping () -> Void) {
        self.store = store
        self.openSettings = openSettings
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: ProjectsView(store: store, openSettings: openSettings)
            ))
            window.title = L("Projects")
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.setContentSize(NSSize(width: 1100, height: 720))
            window.minSize = NSSize(width: 760, height: 480)
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("RightHandProjects")
            window.delegate = self
            if window.frame.origin == .zero { window.center() }
            self.window = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // back to living only in the notch and menu bar
    }
}
