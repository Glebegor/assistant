import AppKit
import Observation

enum NotchTab: CaseIterable, Identifiable {
    case pomodoro, shelf, chat

    var id: Self { self }

    var title: String {
        switch self {
        case .pomodoro: L("Pomodoro")
        case .shelf: L("Shelf")
        case .chat: L("Assistant")
        }
    }

    var systemImage: String {
        switch self {
        case .pomodoro: "timer"
        case .shelf: "tray.full"
        case .chat: "sparkles"
        }
    }

    /// Size of the open panel on this tab.
    var panelSize: CGSize {
        switch self {
        case .pomodoro: CGSize(width: 560, height: 230)
        case .chat: CGSize(width: 600, height: 440)
        case .shelf: CGSize(width: 560, height: 325) // two rows: clipboard and files
        }
    }

    /// The notch window is this big so every tab fits; transparent parts let clicks through.
    static var maxPanelSize: CGSize {
        CGSize(width: allCases.map(\.panelSize.width).max()!, height: allCases.map(\.panelSize.height).max()!)
    }
}

/// Size of the camera notch on a screen. Screens without a notch get a black
/// "fake notch" of the same style in the middle of their menu bar.
struct NotchGeometry {
    /// Size of the black shape when the panel is closed.
    var collapsedSize: CGSize
    /// Area at the top of the screen that opens the panel when the mouse enters it.
    var hoverSize: CGSize

    init(screen: NSScreen) {
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            collapsedSize = CGSize(width: screen.frame.width - left.width - right.width,
                                   height: screen.safeAreaInsets.top)
        } else {
            let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
            collapsedSize = CGSize(width: 200,
                                   height: menuBarHeight > 0 ? menuBarHeight : NSStatusBar.system.thickness)
        }
        hoverSize = CGSize(width: collapsedSize.width + 20, height: collapsedSize.height)
    }

    func hoverZone(on screen: NSScreen) -> NSRect {
        NSRect(x: screen.frame.midX - hoverSize.width / 2,
               y: screen.frame.maxY - hoverSize.height,
               width: hoverSize.width,
               height: hoverSize.height)
    }
}

/// UI state of one notch window (there is one per screen), shared with its SwiftUI content.
@Observable
@MainActor
final class NotchModel {
    var isExpanded = false
    /// When pinned, the panel stays open after the mouse leaves.
    var isPinned = false
    var selectedTab: NotchTab = .pomodoro
    var geometry: NotchGeometry
    /// True while an app is in full screen on this screen: the closed notch is not drawn.
    var hidesWhenCollapsed = false

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }
}
