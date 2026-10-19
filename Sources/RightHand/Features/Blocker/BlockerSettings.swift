import Foundation

/// Site blocking preferences stored in UserDefaults (edited in Settings → Blocking).
enum BlockerSettings {
    enum Key {
        static let enabled = "blocker.enabled"
        static let rules = "blocker.rules"
    }

    enum Default {
        static let enabled = true
        /// One rule per line.
        static let rules = """
        youtube.com/shorts
        instagram.com
        tiktok.com
        """
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.enabled: Default.enabled,
            Key.rules: Default.rules,
        ])
    }

    static var enabled: Bool { UserDefaults.standard.bool(forKey: Key.enabled) }
    static var rules: [BlockRule] { BlockRule.parse(UserDefaults.standard.string(forKey: Key.rules) ?? Default.rules) }
}
