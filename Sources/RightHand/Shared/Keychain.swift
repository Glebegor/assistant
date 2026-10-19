import Foundation
import Security

/// Stores secrets (API keys) in the macOS Keychain instead of plain files or UserDefaults.
enum Keychain {
    private static let service = "com.hlibarseniuk.RightHand"

    /// Posted after a key is saved or removed, so the chat knows which providers are ready.
    static let didChangeNotification = Notification.Name("RightHand.KeychainDidChange")

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String, for account: String) {
        delete(account, notify: false)
        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
        ]
        SecItemAdd(item as CFDictionary, nil)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    static func delete(_ account: String, notify: Bool = true) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        if notify { NotificationCenter.default.post(name: didChangeNotification, object: nil) }
    }
}
