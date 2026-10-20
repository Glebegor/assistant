import AppKit
import SwiftUI

/// The Settings window: a quiet sidebar on the left, the chosen page on the right.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let tasks: TaskStore

    init(tasks: TaskStore) {
        self.tasks = tasks
    }

    func show() {
        if window == nil { window = makeWindow() }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsRootView(tasks: tasks)))
        window.title = L("Settings")
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.appearance = NSAppearance(named: .darkAqua)
        window.isMovableByWindowBackground = true
        window.setContentSize(NSSize(width: 900, height: 660))
        window.minSize = NSSize(width: 760, height: 480)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("RightHandSettings")
        if window.frame.origin == .zero { window.center() }
        return window
    }
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, assistant, ellipse, services, pomodoro, eyeRest, shelf, blocking, about

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .assistant: "Assistant"
        case .ellipse: "Ellipse"
        case .services: "Services"
        case .pomodoro: "Pomodoro"
        case .eyeRest: "Eye Rest"
        case .shelf: "Shelf"
        case .blocking: "Blocking"
        case .about: "About"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .general: "Language of RightHand."
        case .assistant: "Claude and ChatGPT, what they know about you and what they may do on your Mac."
        case .ellipse: "The voice assistant: shortcut, wake word, microphone, languages and voice."
        case .services: "Notion, ClickUp and Google for tasks and for the AI."
        case .pomodoro: "Focus and break lengths, sounds."
        case .eyeRest: "Short breaks for your eyes."
        case .shelf: "Clipboard history, files and screenshots."
        case .blocking: "Sites blocked during focus."
        case .about: "Version and links."
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .assistant: "sparkles"
        case .ellipse: "waveform"
        case .services: "square.stack.3d.up"
        case .pomodoro: "timer"
        case .eyeRest: "eye"
        case .shelf: "tray"
        case .blocking: "hand.raised"
        case .about: "info.circle"
        }
    }
}

struct SettingsRootView: View {
    let tasks: TaskStore
    @AppStorage("settings.page") private var page: SettingsPage = .general

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Theme.hairline).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(page.title).font(.system(size: 26, weight: .semibold))
                    Text(page.subtitle).font(.callout).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 28)
                .padding(.top, 34)
                .padding(.bottom, 6)
                pane
                    .scrollContentBackground(.hidden)
                    .tint(Theme.neon)
                    .id(page)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Theme.background)
        .foregroundStyle(.white)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill").foregroundStyle(Theme.neon).neonGlow(radius: 6)
                Text(verbatim: "RightHand").font(.system(size: 15, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.top, 40)
            .padding(.bottom, 18)
            ForEach(SettingsPage.allCases) { item in
                SidebarItem(page: item, isSelected: item == page) { page = item }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(width: 210)
        .background(Color.black.opacity(0.18))
    }

    @ViewBuilder
    private var pane: some View {
        switch page {
        case .general: GeneralSettingsPane()
        case .assistant: AssistantSettingsPane()
        case .ellipse: EllipseSettingsPane()
        case .services: TasksSettingsPane(store: tasks)
        case .pomodoro: PomodoroSettingsPane()
        case .eyeRest: EyeRestSettingsPane()
        case .shelf: ShelfSettingsPane()
        case .blocking: BlockerSettingsPane()
        case .about: AboutPane()
        }
    }
}

/// A sidebar row; the selected one gets the soft neon.
private struct SidebarItem: View {
    let page: SettingsPage
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: page.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? Theme.neon : .secondary)
                Text(page.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Theme.neonSoft : (isHovered ? Color.white.opacity(0.05) : .clear))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? Theme.neon.opacity(0.45) : .clear, lineWidth: 1))
                    .shadow(color: isSelected ? Theme.neon.opacity(0.25) : .clear, radius: 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
