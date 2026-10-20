import AppKit
import SwiftUI

/// Settings → About: icon, version and links.
struct AboutPane: View {
    private static let repository = URL(string: "https://github.com/Glebegor/assistant")!

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return L("Version %@ (%@)", short, build)
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
            VStack(spacing: 4) {
                Text("RightHand")
                    .font(.title.weight(.semibold))
                Text(verbatim: version)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Text("Your right hand on the Mac: Pomodoro, Shelf and an AI assistant in the notch.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 320)
            HStack(spacing: 10) {
                Link(destination: Self.repository) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: Self.repository.appending(path: "releases")) {
                    Label("Releases", systemImage: "arrow.down.circle")
                }
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
            UpdateCard().frame(maxWidth: 420).padding(.top, 14)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}

/// Settings → About: is there a newer version, and install it.
private struct UpdateCard: View {
    private var updater: Updater { .shared }
    @AppStorage(Updater.autoCheckKey) private var checkAutomatically = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundStyle(Theme.neon).font(.system(size: 16))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title).font(.system(size: 13, weight: .semibold))
                    if let subtitle { Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                action
            }
            if case .downloading(let value) = updater.state {
                ProgressView(value: value).tint(Theme.neon)
            }
            Toggle("Check for updates automatically", isOn: $checkAutomatically)
                .toggleStyle(.checkbox).font(.caption).foregroundStyle(.secondary)
        }
        .themeCard(padding: 14)
    }

    private var icon: String {
        switch updater.state {
        case .available: "arrow.down.circle.fill"
        case .failed: "exclamationmark.triangle"
        case .upToDate: "checkmark.circle"
        default: "arrow.triangle.2.circlepath"
        }
    }

    private var title: String {
        switch updater.state {
        case .available(let release): L("RightHand %@ is available", release.version)
        case .downloading: L("Downloading update…")
        case .installing: L("Installing update…")
        case .checking: L("Checking for updates…")
        case .upToDate: L("RightHand is up to date")
        case .failed(let message): message
        case .idle: L("Updates")
        }
    }

    private var subtitle: String? {
        switch updater.state {
        case .available: L("You have %@.", Updater.currentVersion)
        case .upToDate, .idle: updater.lastChecked.map { L("Checked %@", $0.formatted(.relative(presentation: .named))) }
        default: nil
        }
    }

    @ViewBuilder
    private var action: some View {
        switch updater.state {
        case .available(let release):
            Button("Install") { updater.offer(release) }.buttonStyle(.borderedProminent).tint(Theme.neon)
        case .downloading, .installing, .checking:
            ProgressView().controlSize(.small)
        default:
            Button("Check Now") { Task { await updater.check() } }
        }
    }
}
