import AppKit

/// Translated text for strings built in code (menus, notifications, messages).
/// SwiftUI `Text("…")` literals are translated automatically; translations live in
/// Support/Localization/<language>.lproj/Localizable.strings.
func L(_ key: String) -> String {
    Bundle.main.localizedString(forKey: key, value: key, table: nil)
}

/// Translated text with values, e.g. `L("Start %@", phase)`.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), locale: Locale.current, arguments: arguments)
}

/// The language RightHand's interface uses.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system = ""
    case english = "en"
    case ukrainian = "uk"
    case czech = "cs"
    case russian = "ru"

    var id: Self { self }

    /// Each language is shown in its own language, so you can always find yours.
    var name: String {
        switch self {
        case .system: L("Automatic (Mac language)")
        case .english: "English"
        case .ukrainian: "Українська"
        case .czech: "Čeština"
        case .russian: "Русский"
        }
    }

    /// The choice saved for RightHand (macOS reads it at launch).
    static var selected: AppLanguage {
        get {
            guard let code = (UserDefaults.standard.object(forKey: "AppleLanguages") as? [String])?.first,
                  UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?["AppleLanguages"] != nil
            else { return .system }
            return allCases.first { $0 != .system && code.hasPrefix($0.rawValue) } ?? .system
        }
        set {
            if newValue == .system {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set([newValue.rawValue], forKey: "AppleLanguages")
            }
        }
    }

    /// Language code the interface is using right now ("en", "uk", …).
    static var current: String {
        Bundle.main.preferredLocalizations.first ?? "en"
    }

    /// Quits and opens RightHand again, so a new language takes effect.
    @MainActor
    static func restartApp() {
        let path = Bundle.main.bundlePath
        let relaunch = Process()
        relaunch.executableURL = URL(filePath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", path]
        try? relaunch.run()
        NSApp.terminate(nil)
    }
}
