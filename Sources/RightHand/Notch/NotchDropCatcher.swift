import AppKit
import UniformTypeIdentifiers

/// Small invisible window over the closed notch. While you drag something from another app,
/// macOS doesn't tell RightHand where the mouse is, so this window notices the drag (and plain
/// hovering) itself and asks for the panel to open.
final class NotchDropCatcher: NSPanel {
    var onActivate: (() -> Void)? {
        get { catcherView.onActivate }
        set { catcherView.onActivate = newValue }
    }

    private let catcherView = CatcherView()

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4) // above the notch panel
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        contentView = catcherView
        catcherView.registerForDraggedTypes(
            [.fileURL, .string, .png, .tiff, NSPasteboard.PasteboardType(UTType.shelfItem.identifier)]
                + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        )
    }

    override var canBecomeKey: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

private final class CatcherView: NSView {
    var onActivate: (() -> Void)?

    // Nearly transparent: fully transparent pixels would let the mouse and drags pass through.
    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0, alpha: 0.01).setFill()
        bounds.fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onActivate?() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onActivate?() // the panel opens on top; the drop then lands on the Shelf
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { false }
}
