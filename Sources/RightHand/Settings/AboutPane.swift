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
        }
        .padding(32)
        .frame(maxWidth: .infinity)
    }
}
