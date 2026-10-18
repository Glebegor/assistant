import SwiftUI

/// Chat tab: talk to Claude or ChatGPT, which can control the Mac (later milestone).
struct ChatView: View {
    var body: some View {
        PlaceholderView(
            systemImage: "sparkles",
            title: "Assistant",
            message: "Chat with Claude or ChatGPT and let it act on your Mac."
        )
    }
}
