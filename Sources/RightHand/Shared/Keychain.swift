import Foundation

/// Stores secrets (API keys, tokens) in the macOS Keychain instead of plain files or UserDefaults.
///
/// Items are read and written through Apple's `/usr/bin/security` tool. When an app without an Apple
/// developer certificate reads the Keychain itself, macOS ties each permission to that exact build,
/// so every update asked "RightHand wants to use your confidential information" again for every key.
/// `security` is Apple-signed, so its access stays valid and nothing is asked.
enum Keychain {
    private static let service = "com.hlibarseniuk.RightHand"
    private static let tool = URL(filePath: "/usr/bin/security")

    /// Posted after a key is saved or removed, so the chat knows which providers are ready.
    static let didChangeNotification = Notification.Name("RightHand.KeychainDidChange")

    /// Values already read (nil = no such item), so the tool runs once per key per launch.
    nonisolated(unsafe) private static var cache: [String: String?] = [:]
    private static let lock = NSLock()

    static func read(_ account: String) -> String? {
        if let cached = lock.withLock({ cache[account] }) { return cached }
        let result = run(["find-generic-password", "-s", service, "-a", account, "-w"])
        let value = result.status == 0 ? result.output.trimmingCharacters(in: .newlines) : nil
        lock.withLock { cache[account] = .some(value?.isEmpty == false ? value : nil) }
        return value?.isEmpty == false ? value : nil
    }

    static func save(_ value: String, for account: String) {
        // -U replaces an existing item.
        _ = run(["add-generic-password", "-U", "-s", service, "-a", account, "-w", value])
        lock.withLock { cache[account] = .some(value) }
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    static func delete(_ account: String, notify: Bool = true) {
        _ = run(["delete-generic-password", "-s", service, "-a", account])
        lock.withLock { cache[account] = .some(nil) }
        if notify { NotificationCenter.default.post(name: didChangeNotification, object: nil) }
    }

    private static func run(_ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return (-1, "")
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
