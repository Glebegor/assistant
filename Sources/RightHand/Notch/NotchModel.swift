import AppKit
import Observation

enum NotchTab: CaseIterable, Identifiable {
    case pomodoro, shelf, chat

    var id: Self { self }

    var title: String {
        switch self {
        case .pomodoro: "Pomodoro"
        case .shelf: "Shelf"
        case .chat: "Assistant"
        }
    }

    var systemImage: String {
        switch self {
        case .pomodoro: "timer"
        case .shelf: "tray.full"
        case .chat: "sparkles"
        }
    }
}

/// Size of the camera notch on a screen. Screens without a notch get a thin strip at the top edge.
struct NotchGeometry {
    var hasNotch: Bool
    /// Size of the black shape when the panel is closed (the notch itself).
    var collapsedSize: CGSize
    /// Area at the top of the screen that opens the panel when the mouse enters it.
    var hoverSize: CGSize

    init(screen: NSScreen) {
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let size = CGSize(width: screen.frame.width - left.width - right.width,
                              height: screen.safeAreaInsets.top)
            hasNotch = true
            collapsedSize = size
            hoverSize = CGSize(width: size.width + 20, height: size.height)
        } else {
            hasNotch = false
            collapsedSize = CGSize(width: 200, height: 0)
            hoverSize = CGSize(width: 240, height: 4)
        }
    }

    func hoverZone(on screen: NSScreen) -> NSRect {
        NSRect(x: screen.frame.midX - hoverSize.width / 2,
               y: screen.frame.maxY - hoverSize.height,
               width: hoverSize.width,
               height: hoverSize.height)
    }
}

/// UI state shared between the notch window (AppKit) and its SwiftUI content.
@Observable
@MainActor
final class NotchModel {
    var isExpanded = false
    /// When pinned, the panel stays open after the mouse leaves.
    var isPinned = false
    var selectedTab: NotchTab = .pomodoro
    var geometry = NotchGeometry(screen: NSScreen.main ?? NSScreen.screens[0])
}
