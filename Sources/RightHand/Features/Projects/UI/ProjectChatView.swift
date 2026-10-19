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
            conversation
            Divider()
            VStack(spacing: 10) {
                if let approval = engine.pendingApproval { ApprovalCard(approval: approval, provider: engine.chat.provider, engine: engine) }
                if let error = engine.errorMessage { errorBanner(error) }
                inputBar
            }
            .padding(16)
        }
        .navigationTitle(engine.chat.title)
        .navigationSubtitle(ChatSettings.claudeModels.first { $0.id == engine.chat.model }?.name ?? engine.chat.model)
        .onAppear { isInputFocused = true }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if engine.chat.messages.isEmpty {
                        ContentUnavailableView("Start the conversation", systemImage: "sparkles",
                                               description: Text("The project's instructions, files and memory are already part of this chat."))
                            .padding(.top, 80)
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
                                Text(activity).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(20)
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
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            if engine.isRunning {
                Button("Stop", systemImage: "stop.circle.fill", action: engine.stop)
                    .labelStyle(.iconOnly).buttonStyle(.plain).font(.system(size: 28))
                    .help("Stop")
            } else {
                Button("Send", systemImage: "arrow.up.circle.fill", action: send)
                    .labelStyle(.iconOnly).buttonStyle(.plain).font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Send (Return)")
            }
        }
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
                .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
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
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .foregroundStyle(.white)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        case .assistant(_, let text):
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.markdown(text))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
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

    private static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
