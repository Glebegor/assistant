import AppKit

/// Opens pages of System Settings → Privacy & Security.
enum PrivacySettings {
    static func openFilesAndFolders() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!)
    }
}
