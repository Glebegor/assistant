import AppKit
import SwiftUI

/// Settings → Shelf: what is added automatically and where files are kept.
struct ShelfSettingsPane: View {
    @AppStorage(ShelfSettings.Key.captureScreenshots) private var captureScreenshots = ShelfSettings.Default.captureScreenshots
    @AppStorage(ShelfSettings.Key.clipboardHistory) private var clipboardHistory = ShelfSettings.Default.clipboardHistory
    @AppStorage(ShelfSettings.Key.filesDirectory) private var filesDirectory = ShelfSettings.Default.filesDirectory

    var body: some View {
        Form {
            Section("Add automatically") {
                Toggle(isOn: $captureScreenshots) {
                    SettingsRowLabel("Screenshots",
                                     subtitle: "New screenshots (⌘⇧3, ⌘⇧4, ⌘⇧5) appear on the Shelf.",
                                     systemImage: "camera.viewfinder", color: .blue)
                }
                Toggle(isOn: $clipboardHistory) {
                    SettingsRowLabel("Clipboard history",
                                     subtitle: "Keeps the last \(ShelfSettings.maxClipboardItems) copied items. Passwords from password managers are skipped.",
                                     systemImage: "doc.on.clipboard.fill", color: .indigo)
                }
            }

            Section {
                LabeledContent {
                    HStack(spacing: 8) {
                        Button("Change…", action: chooseFilesDirectory)
                        Button("Show in Finder", action: showFilesDirectory)
                    }
                } label: {
                    SettingsRowLabel("Files folder",
                                     subtitle: (filesDirectory as NSString).abbreviatingWithTildeInPath,
                                     systemImage: "folder.fill", color: .cyan)
                }
            } header: {
                Text("Files")
            } footer: {
                SettingsFooter("Files you drop and new screenshots are copied into this folder. Each Shelf folder is a subfolder. Your originals stay where they are.")
            }
        }
        .formStyle(.grouped)
    }

    private var filesDirectoryURL: URL { URL(filePath: filesDirectory, directoryHint: .isDirectory) }

    private func showFilesDirectory() {
        try? FileManager.default.createDirectory(at: filesDirectoryURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(filesDirectoryURL)
    }

    private func chooseFilesDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        panel.directoryURL = filesDirectoryURL
        if panel.runModal() == .OK, let url = panel.url {
            filesDirectory = url.path
        }
    }
}
