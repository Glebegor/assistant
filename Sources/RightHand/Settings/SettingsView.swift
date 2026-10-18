import AppKit
import SwiftUI

struct SettingsView: View {
    @AppStorage(PomodoroSettings.Key.focusMinutes) private var focusMinutes = PomodoroSettings.Default.focusMinutes
    @AppStorage(PomodoroSettings.Key.shortBreakMinutes) private var shortBreakMinutes = PomodoroSettings.Default.shortBreakMinutes
    @AppStorage(PomodoroSettings.Key.longBreakMinutes) private var longBreakMinutes = PomodoroSettings.Default.longBreakMinutes
    @AppStorage(PomodoroSettings.Key.sessionsBeforeLongBreak) private var sessionsBeforeLongBreak = PomodoroSettings.Default.sessionsBeforeLongBreak
    @AppStorage(PomodoroSettings.Key.autoStartNext) private var autoStartNext = PomodoroSettings.Default.autoStartNext
    @AppStorage(PomodoroSettings.Key.focusEndSound) private var focusEndSound = PomodoroSettings.Default.focusEndSound
    @AppStorage(PomodoroSettings.Key.breakEndSound) private var breakEndSound = PomodoroSettings.Default.breakEndSound
    @AppStorage(PomodoroSettings.Key.soundVolume) private var soundVolume = PomodoroSettings.Default.soundVolume
    @AppStorage(ShelfSettings.Key.captureScreenshots) private var captureScreenshots = ShelfSettings.Default.captureScreenshots
    @AppStorage(ShelfSettings.Key.clipboardHistory) private var clipboardHistory = ShelfSettings.Default.clipboardHistory
    @AppStorage(ShelfSettings.Key.filesDirectory) private var filesDirectory = ShelfSettings.Default.filesDirectory

    var body: some View {
        Form {
            Section("Pomodoro") {
                Stepper("Focus: \(focusMinutes) min", value: $focusMinutes, in: 1...120)
                Stepper("Short break: \(shortBreakMinutes) min", value: $shortBreakMinutes, in: 1...60)
                Stepper("Long break: \(longBreakMinutes) min", value: $longBreakMinutes, in: 1...90)
                Stepper("Long break after \(sessionsBeforeLongBreak) sessions", value: $sessionsBeforeLongBreak, in: 2...10)
                Toggle("Start next phase automatically", isOn: $autoStartNext)
            }
            Section("Pomodoro sounds") {
                soundPicker("Focus finished", selection: $focusEndSound)
                soundPicker("Break finished", selection: $breakEndSound)
                LabeledContent("Volume") {
                    HStack {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        Slider(value: $soundVolume, in: 0...1) { editing in
                            if !editing { PomodoroSound.play(focusEndSound) }
                        }
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                    }
                    .frame(width: 220)
                }
            }
            Section {
                Toggle("Add new screenshots automatically", isOn: $captureScreenshots)
                Toggle("Keep clipboard history", isOn: $clipboardHistory)
                LabeledContent("Files folder") {
                    HStack {
                        Text((filesDirectory as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Change…", action: chooseFilesDirectory)
                        Button("Show") {
                            let url = URL(filePath: filesDirectory, directoryHint: .isDirectory)
                            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            } header: {
                Text("Shelf")
            } footer: {
                Text("""
                Dropped files and screenshots are copied into the files folder; Shelf folders are its subfolders. \
                Keeps the last \(ShelfSettings.maxClipboardItems) copied items. Passwords from password managers are skipped.
                """)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize()
    }

    /// Picker of macOS sounds that plays the sound when you choose it.
    private func soundPicker(_ title: String, selection: Binding<String>) -> some View {
        HStack {
            Picker(title, selection: selection) {
                Text("None").tag("")
                Divider()
                ForEach(PomodoroSound.available, id: \.self) { Text($0).tag($0) }
            }
            .onChange(of: selection.wrappedValue) { _, name in PomodoroSound.play(name) }
            Button("Play", systemImage: "play.fill") { PomodoroSound.play(selection.wrappedValue) }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(selection.wrappedValue.isEmpty)
                .help("Play sound")
        }
    }

    private func chooseFilesDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        panel.directoryURL = URL(filePath: filesDirectory)
        if panel.runModal() == .OK, let url = panel.url {
            filesDirectory = url.path
        }
    }
}

/// Plain window hosting `SettingsView`, opened from the menu bar or the notch panel.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "RightHand Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
