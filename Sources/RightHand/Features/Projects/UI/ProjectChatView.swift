import AppKit
import SwiftUI

/// A project chat: messages, tool steps, permission questions and the input box.
struct ProjectChatView: View {
    let engine: ConversationEngine
    let openSettings: () -> Void
    @State private var draft = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.hairline).frame(height: 1)
            conversation
            VStack(spacing: 10) {
                if let approval = engine.pendingApproval { ApprovalCard(approval: approval, provider: engine.chat.provider, engine: engine) }
                if let error = engine.errorMessage { errorBanner(error) }
                inputBar
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
            .padding(.top, 6)
        }
        .onAppear { isInputFocused = true }
    }

    private var header: some View {
        let provider = engine.chat.provider
        return HStack(spacing: 10) {
            Circle().fill(provider.tint).frame(width: 8, height: 8).shadow(color: provider.tint, radius: 4)
            Text(verbatim: engine.chat.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            Text(verbatim: ModelCatalog.shared.name(of: engine.chat.model, provider: provider))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.white.opacity(0.06), in: Capsule())
            Spacer()
            if engine.isRunning {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 34)
        .padding(.bottom, 12)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if engine.chat.messages.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "sparkles").font(.system(size: 30, weight: .light))
                                .foregroundStyle(engine.chat.provider.tint).shadow(color: engine.chat.provider.tint.opacity(0.6), radius: 10)
                            Text("Start the conversation").font(.system(size: 18, weight: .semibold))
                            Text("The project's instructions, files and memory are already part of this chat.")
                                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 90)
                    }
                    ForEach(engine.display) { item in
                        ProjectMessageRow(item: item, provider: engine.chat.provider)
                    }
                    if engine.isRunning {
                        if !engine.streamingText.isEmpty {
                            ProjectMessageRow(item: .assistant(id: "streaming", text: engine.streamingText), provider: engine.chat.provider)
                        }
                        if let activity = engine.activity {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(activity).font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: engine.streamingText) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: engine.chat.messages.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message \(engine.chat.provider.title)…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...8)
                .focused($isInputFocused)
                .onSubmit(send)
                .shiftReturnAddsNewLine()
                .font(.system(size: 13.5))
                .padding(.vertical, 6)
            if engine.isRunning {
                Button("Stop", systemImage: "stop.fill", action: engine.stop)
                    .labelStyle(.iconOnly).buttonStyle(.plain)
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.12), in: Circle())
                    .help("Stop")
            } else {
                let isEmpty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Button("Send", systemImage: "arrow.up", action: send)
                    .labelStyle(.iconOnly).buttonStyle(.plain)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isEmpty ? Color.secondary : .black)
                    .frame(width: 30, height: 30)
                    .background(isEmpty ? Color.white.opacity(0.08) : Theme.neon, in: Circle())
                    .shadow(color: isEmpty ? .clear : Theme.neon.opacity(0.5), radius: 8)
                    .disabled(isEmpty)
                    .help("Send (Return)")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 7)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(isInputFocused ? Theme.neon.opacity(0.55) : Theme.cardStroke, lineWidth: 1)
        }
        .shadow(color: isInputFocused ? Theme.neon.opacity(0.18) : .clear, radius: 12)
        .animation(.easeOut(duration: 0.2), value: isInputFocused)
        .frame(maxWidth: 820)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack {
            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Spacer()
            if message.contains("Settings") { Button("Open Settings", action: openSettings) }
        }
        .font(.callout)
        .frame(maxWidth: 820)
    }

    private func send() {
        guard !engine.isRunning else { return }
        engine.send(draft)
        draft = ""
    }
}

/// "Claude wants to read README.md" with Deny / Allow Once / Always Allow.
private struct ApprovalCard: View {
    let approval: ToolApproval
    let provider: ChatProvider
    let engine: ConversationEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "hand.raised.fill").font(.title2).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(provider.title) wants to: \(approval.action)").fontWeight(.medium)
                    Text(approval.toolDisplayName).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Deny") { engine.resolveApproval(.deny) }
                if approval.canAlwaysAllow {
                    Button("Always Allow") { engine.resolveApproval(.alwaysAllow) }
                        .help("Don't ask again for “\(approval.toolDisplayName)” (change it in Settings → Assistant)")
                }
                Button("For This Chat") { engine.resolveApproval(.allowForChat) }
                .help("Allow “\(approval.toolDisplayName)” without asking until this chat ends or RightHand quits")
            if approval.canAllowForProject {
                Button("For This Project") { engine.resolveApproval(.allowForProject) }
                    .help("Allow “\(approval.toolDisplayName)” without asking in every chat of this project (undo it in the project's settings)")
            }
            Button("Allow Once") { engine.resolveApproval(.allowOnce) }
                    .keyboardShortcut(.defaultAction)
            }
            if let detail = approval.detail {
                ScrollView {
                    Text(verbatim: detail)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.orange.opacity(0.3)))
        .frame(maxWidth: 820)
    }
}

/// One message, tool step or notice.
struct ProjectMessageRow: View {
    let item: ChatDisplayItem
    let provider: ChatProvider
    @State private var showsDetails = false
    @State private var isHovered = false

    var body: some View {
        switch item {
        case .user(_, let text):
            HStack {
                Spacer(minLength: 80)
                Text(text)
                    .textSelection(.enabled)
                    .font(.system(size: 13.5))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .foregroundStyle(.white)
                    .background(Theme.neon.opacity(0.18), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.neon.opacity(0.35)))
            }
        case .assistant(_, let text):
            VStack(alignment: .leading, spacing: 4) {
                MarkdownView(text: text)
                HStack(spacing: 10) {
                    Button("Copy", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                    SpeakButton(text: text)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
                .opacity(isHovered ? 1 : 0)
            }
            .onHover { isHovered = $0 }
        case .tool(_, let name, let input, let result, let isError):
            VStack(alignment: .leading, spacing: 6) {
                Button {
                    showsDetails.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: result == nil ? "gearshape" : (isError ? "xmark.circle.fill" : "checkmark.circle.fill"))
                            .foregroundStyle(result == nil ? Color.secondary : (isError ? Color.orange : Color.green))
                        Text(Self.toolTitle(name)).fontWeight(.medium)
                        Text(Self.shortInput(input)).foregroundStyle(.secondary).lineLimit(1)
                        Image(systemName: showsDetails ? "chevron.up" : "chevron.down").font(.caption2).foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
                .buttonStyle(.plain)
                if showsDetails {
                    Text(result.map { String($0.prefix(4000)) } ?? input)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.cardStroke))
        case .summarized:
            notice("Earlier messages were summarized so the chat can keep going", systemImage: "arrow.down.right.and.arrow.up.left")
        case .projectUpdated:
            notice("Project instructions or files were updated", systemImage: "arrow.triangle.2.circlepath")
        }
    }

    private func notice(_ text: String, systemImage: String) -> some View {
        HStack {
            VStack { Divider() }
            Label(text, systemImage: systemImage).font(.caption).foregroundStyle(.secondary).fixedSize()
            VStack { Divider() }
        }
    }

    private static func toolTitle(_ name: String) -> String {
        Toolbox.displayName(of: name)
    }

    /// The most telling part of the input, e.g. the path or the query.
    private static func shortInput(_ input: String) -> String {
        guard let object = JSONValue.parse(input)?.object else { return "" }
        for key in ["command", "path", "from", "query", "target"] {
            if let value = object[key]?.string { return value }
        }
        return ""
    }

}
