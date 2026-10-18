import AppKit

/// Notices when something new is copied. macOS has no "clipboard changed" event,
/// so we check the pasteboard's change counter twice a second (very cheap).
@MainActor
final class ClipboardWatcher {
    var onChange: ((NSPasteboard) -> Void)?

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount = NSPasteboard.general.changeCount
    private var timer: Timer?

    func setEnabled(_ enabled: Bool) {
        if enabled, timer == nil {
            lastChangeCount = pasteboard.changeCount // don't import what was copied before
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.check() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        } else if !enabled {
            timer?.invalidate()
            timer = nil
        }
    }

    /// Call after RightHand itself writes to the clipboard, so it isn't added back.
    func ignoreCurrentContents() {
        lastChangeCount = pasteboard.changeCount
    }

    private func check() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        onChange?(pasteboard)
    }
}
