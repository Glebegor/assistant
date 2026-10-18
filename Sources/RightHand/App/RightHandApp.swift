import AppKit

/// Entry point. We start AppKit by hand (instead of a SwiftUI `App`) because
/// RightHand has no regular windows: it lives in the notch and the menu bar.
@main
@MainActor
enum RightHandApp {
    // NSApplication keeps only a weak reference to its delegate, so we hold it here.
    private static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory) // no Dock icon
        app.delegate = delegate
        app.run()
    }
}
