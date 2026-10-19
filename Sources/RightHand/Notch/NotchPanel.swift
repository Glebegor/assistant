import AppKit
import SwiftUI

/// Borderless transparent window that sits over the menu bar, around the camera notch.
final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3) // above the menu bar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    // Needed later for typing in the chat field.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // You type in the panel without RightHand becoming the active app, so the Edit menu
    // doesn't see ⌘C/⌘V/…; send them to the text field directly.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, let shortcut = EditShortcut.matching(event),
           NSApp.sendAction(shortcut.action, to: firstResponder, from: self) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // Allow placing the window over the menu bar instead of being pushed below it.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Hosting view that reacts to the first click even when RightHand is not the active app.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
