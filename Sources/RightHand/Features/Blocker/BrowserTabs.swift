import AppKit

/// Browsers whose current tab address RightHand can read and change via AppleScript.
/// (Firefox doesn't support this; it's covered by the hosts file instead.)
enum Browser: CaseIterable, Sendable {
    case safari, chrome, arc, brave, edge, vivaldi

    var bundleID: String {
        switch self {
        case .safari: "com.apple.Safari"
        case .chrome: "com.google.Chrome"
        case .arc: "company.thebrowser.Browser"
        case .brave: "com.brave.Browser"
        case .edge: "com.microsoft.edgemac"
        case .vivaldi: "com.vivaldi.Vivaldi"
        }
    }

    /// Safari calls the visible tab "current tab", Chromium browsers "active tab".
    fileprivate var tabName: String { self == .safari ? "current tab" : "active tab" }

    @MainActor static var running: [Browser] {
        allCases.filter { !NSRunningApplication.runningApplications(withBundleIdentifier: $0.bundleID).isEmpty }
    }
}

struct BrowserTab: Sendable {
    let browser: Browser
    let windowID: Int
    let url: URL
}

/// Runs the browser AppleScripts on one background queue, so a slow browser never freezes the app.
/// The first time, macOS asks whether RightHand may control each browser.
final class BrowserTabs: @unchecked Sendable {
    let queue = DispatchQueue(label: "RightHand.BrowserTabs")
    /// Compiled "list the tabs" scripts, only touched on `queue`.
    private var listScripts: [Browser: NSAppleScript] = [:]

    /// The visible tab of every window of a running browser. Call on `queue`.
    func visibleTabs(of browser: Browser) -> [BrowserTab] {
        let script = listScripts[browser] ?? {
            let script = NSAppleScript(source: """
            with timeout of 2 seconds
                tell application id "\(browser.bundleID)"
                    set out to {}
                    repeat with w in windows
                        try
                            set end of out to ((id of w) as text) & " " & (URL of \(browser.tabName) of w)
                        end try
                    end repeat
                    return out
                end tell
            end timeout
            """)!
            listScripts[browser] = script
            return script
        }()

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard error == nil, result.numberOfItems > 0 else { return [] }
        return (1...result.numberOfItems).compactMap { index in
            guard let line = result.atIndex(index)?.stringValue,
                  let space = line.firstIndex(of: " "),
                  let windowID = Int(line[..<space]),
                  let url = URL(string: String(line[line.index(after: space)...]))
            else { return nil }
            return BrowserTab(browser: browser, windowID: windowID, url: url)
        }
    }

    /// Loads `url` in the tab instead of what it shows now. Call on `queue`.
    func open(_ url: URL, in tab: BrowserTab) {
        let address = url.absoluteString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = NSAppleScript(source: """
        with timeout of 2 seconds
            tell application id "\(tab.browser.bundleID)"
                set URL of \(tab.browser.tabName) of window id \(tab.windowID) to "\(address)"
            end tell
        end timeout
        """)
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
    }
}
