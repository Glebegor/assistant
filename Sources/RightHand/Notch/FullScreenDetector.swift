import AppKit

/// Finds screens on which another app is showing a full-screen window.
/// macOS has no direct API for this, so we look for a normal window that covers the whole screen
/// (menu bar area included) — only full-screen windows do that. Reading window sizes needs no permission.
enum FullScreenDetector {
    static func fullScreenDisplays() -> Set<CGDirectDisplayID> {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]]
        else { return [] }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let windowBounds: [CGRect] = windows.compactMap { info in
            guard info[kCGWindowLayer as String] as? Int == 0,
                  info[kCGWindowOwnerPID as String] as? pid_t != ownPID,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary
            else { return nil }
            return CGRect(dictionaryRepresentation: bounds)
        }

        var result = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            let display = CGDisplayBounds(id) // same coordinate system as window bounds
            if windowBounds.contains(where: { $0.insetBy(dx: 1, dy: 1).contains(display.insetBy(dx: 2, dy: 2)) }) {
                result.insert(id)
            }
        }
        return result
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
