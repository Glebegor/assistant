import AppKit
import SwiftUI

/// Assistant tab: chat with Claude or ChatGPT, which can use tools on the Mac (asking first).
struct ChatView: View {
    let store: ChatStore
    let voice: VoiceAssistant
    let openSettings: () -> Void
    let openProjects: () -> Void
    @State private var draft = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            toolbar
            ChatTabStrip(store: store)
            if !store.hasKey {
                missingKey
            } else if store.isEmpty {
                PlaceholderView(systemImage: "sparkles",
                                title: L("Ask %@ anything", store.provider.title),
                                message: "Return sends, Shift-Return adds a new line.")
            } else {
                conversation
            }
            if let approval = store.engine.pendingApproval {
                NotchApprovalCard(approval: approval, provider: store.engine.chat.provider, engine: store.engine)
            }
            inputBar
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("Provider", selection: Binding(get: { store.provider }, set: { store.provider = $0 })) {
                ForEach(ChatProvider.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(store.isSending)
            // The model for new chats; an empty chat switches right away.
            Menu {
                ForEach(ModelCatalog.shared.list(for: store.provider)) { model in
                    Button { store.chooseModel(model.id) } label: {
                        if model.id == store.engine.chat.model { Label(model.name, systemImage: "checkmark") } else { Text(model.name) }
                    }
                }
                // Claude and the newest GPT come with the Copilot subscription, not GitHub Models.
                if store.provider == .copilot, !CopilotAuth.isSignedIn {
                    Divider()
                    Button("Claude, GPT-5.x and more: sign in with Copilot…", systemImage: "person.crop.circle.badge.plus") {
                        UserDefaults.standard.set(SettingsPage.assistant.rawValue, forKey: "settings.page")
                        openSettings()
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(store.modelName)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(store.isSending)
            .help("Model")
            Spacer()
            Button("Projects", systemImage: "rectangle.stack") { openProjects() }
                .buttonStyle(.notchPill())
                .labelStyle(.iconOnly)
                .help("Open the Projects window for long work")
            Button("New Chat", systemImage: "plus") {
                store.newChat()
                isInputFocused = true
            }
            .buttonStyle(.notchPill())
            .labelStyle(.iconOnly)
            .disabled(store.isEmpty)
            .help("New chat in a new tab")
        }
    }

    private var missingKey: some View {
        VStack(spacing: 10) {
            Image(systemName: "key.fill").font(.system(size: 28)).foregroundStyle(.secondary)
            Text("Add your \(store.provider.title) API key").font(.headline)
            Text("Keys are stored securely in your Mac's Keychain.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Open Settings", action: openSettings)
                .buttonStyle(.notchPill(prominent: true, tint: .white))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var conversation: some View {
        let engine = store.engine
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(engine.display) { NotchMessageRow(item: $0, modelName: store.modelName) }
                    if engine.isRunning {
                        if !engine.streamingText.isEmpty {
                            NotchMessageRow(item: .assistant(id: "streaming", text: engine.streamingText), modelName: store.modelName)
                        }
                        if let activity = engine.activity, engine.pendingApproval == nil {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text(activity).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .font(.callout)
                        }
                    }
                    if let error = engine.errorMessage {
                        Label(error, systemImage: "xmark.octagon.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.never)
            .onChange(of: engine.streamingText) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: engine.chat.messages.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: engine.activity) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if voice.phase == .listening || voice.phase == .transcribing {
                // While recording, the field shows what you're saying.
                HStack(spacing: 8) {
                    Image(systemName: "waveform").foregroundStyle(.cyan).symbolEffect(.variableColor.iterative, isActive: voice.phase == .listening)
                    Text(voice.transcript.isEmpty ? L("Listening…") : voice.transcript)
                        .foregroundStyle(voice.transcript.isEmpty ? .secondary : .primary)
                        .lineLimit(1...5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.cyan.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                messageField
            }
            if voice.isEnabled {
            Button(voice.phase == .listening ? "Send Recording" : "Record", systemImage: micSymbol) { voice.toggle() }
                .help(voice.phase == .listening ? L("Stop recording and send (%@)", Shortcut.voice.displayName)
                                               : L("Speak your message (%@)", Shortcut.voice.displayName))
                .iconButton(color: voice.phase == .listening ? .red : .white)
                .disabled(!store.hasKey || voice.phase == .transcribing)
            }
            sendOrStop
        }
    }

    private var micSymbol: String {
        switch voice.phase {
        case .listening: "stop.circle.fill"
        case .transcribing: "ellipsis.circle.fill"
        default: "mic.circle.fill"
        }
    }

    private var messageField: some View {
            TextField("Message \(store.provider.title)…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .onSubmit(send)
                .shiftReturnAddsNewLine()
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .disabled(!store.hasKey)
    }

    @ViewBuilder
    private var sendOrStop: some View {
            if store.isSending {
                Button("Stop", systemImage: "stop.circle.fill", action: store.stop)
                    .help("Stop the answer")
                    .iconButton()
            } else {
                Button("Send", systemImage: "arrow.up.circle.fill", action: send)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.hasKey)
                    .help("Send (Return)")
                    .iconButton()
            }
    }

    private func send() {
        guard !store.isSending else { return }
        store.send(draft)
        draft = ""
        isInputFocused = true
    }
}

private extension View {
    func iconButton(color: Color = .white) -> some View {
        labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.system(size: 26))
            .foregroundStyle(color)
    }
}

/// The open chats as tabs. Each keeps its conversation, also after restarting; × closes one.
private struct ChatTabStrip: View {
    let store: ChatStore

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(store.tabs, id: \.chat.id) { tab in
                        ChatTab(engine: tab, isSelected: tab.chat.id == store.selectedID,
                                select: { store.select(tab.chat.id) },
                                close: { store.close(tab.chat.id) })
                            .id(tab.chat.id)
                    }
                }
            }
            .scrollIndicators(.never)
            .onChange(of: store.selectedID) { _, id in withAnimation { proxy.scrollTo(id) } }
            .onAppear { proxy.scrollTo(store.selectedID) }
        }
        .frame(height: 24)
    }
}

private struct ChatTab: View {
    let engine: ConversationEngine
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 5) {
            if engine.isRunning {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: engine.chat.provider.systemImage)
                    .font(.system(size: 9))
                    .foregroundStyle(engine.pendingApproval != nil ? .orange : .secondary)
            }
            Text(engine.chat.messages.isEmpty ? L("New chat") : engine.chat.title)
                .lineLimit(1)
                .frame(maxWidth: 120, alignment: .leading)
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(isHovered || isSelected ? 1 : 0)
            .help("Close tab")
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(.white.opacity(isSelected ? 0.16 : (isHovered ? 0.08 : 0.04)), in: Capsule())
        .contentShape(Capsule())
        .onTapGesture(perform: select)
        .onHover { isHovered = $0 }
    }
}

/// "Claude wants to: Run a command" with the command, and Deny / Always Allow / Allow Once.
struct NotchApprovalCard: View {
    let approval: ToolApproval
    let provider: ChatProvider
    let engine: ConversationEngine
    /// "Claude", "ChatGPT", or "Ellipse" for a spoken request.
    var who: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
                Text("\(who ?? provider.title) wants to: \(approval.action)")
                    .fontWeight(.medium)
                    .lineLimit(2)
                Spacer(minLength: 4)
            }
            if let detail = approval.detail {
                ScrollView {
                    Text(verbatim: detail)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 70)
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
                .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack(spacing: 8) {
                Spacer()
                Button("Deny") { engine.resolveApproval(.deny) }
                    .buttonStyle(.notchPill())
                if approval.canAlwaysAllow {
                    Button("Always Allow") { engine.resolveApproval(.alwaysAllow) }
                        .buttonStyle(.notchPill())
                        .help("Don't ask again for “\(approval.toolDisplayName)” (change it in Settings → Assistant)")
                }
                Button("For This Chat") { engine.resolveApproval(.allowForChat) }
                    .buttonStyle(.notchPill())
                    .help("Allow “\(approval.toolDisplayName)” without asking until you start a new chat")
                Button("Allow Once") { engine.resolveApproval(.allowOnce) }
                    .buttonStyle(.notchPill(prominent: true, tint: .white))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .font(.callout)
        .padding(10)
        .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// One question, answer or tool step in the conversation.
private struct NotchMessageRow: View {
    let item: ChatDisplayItem
    let modelName: String
    @State private var isHovered = false
    @State private var showsDetails = false

    var body: some View {
        switch item {
        case .user(_, let text):
            HStack {
                Spacer(minLength: 60)
                Text(text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.85), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        case .assistant(_, let text):
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(modelName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if isHovered, !text.isEmpty {
                        Button("Copy", systemImage: "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        }
                        .help("Copy answer")
                        SpeakButton(text: text)
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundStyle(.secondary)
                MarkdownView(text: text, compact: true)
            }
            .padding(.trailing, 40)
            .onHover { isHovered = $0 }
        case .tool(_, let name, let input, let result, let isError):
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    showsDetails.toggle()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: result == nil ? "gearshape" : (isError ? "xmark.circle.fill" : "checkmark.circle.fill"))
                            .foregroundStyle(result == nil ? Color.secondary : (isError ? Color.orange : Color.green))
                        Text(verbatim: Toolbox.displayName(of: name)).fontWeight(.medium)
                        Text(verbatim: Self.shortInput(input)).foregroundStyle(.secondary).lineLimit(1)
                        Image(systemName: showsDetails ? "chevron.up" : "chevron.down").font(.caption2).foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
                .buttonStyle(.plain)
                if showsDetails {
                    Text(verbatim: result.map { String($0.prefix(3000)) } ?? input)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        case .summarized, .projectUpdated:
            EmptyView()
        }
    }

    /// The most telling part of the input: the command, path or query.
    private static func shortInput(_ input: String) -> String {
        guard let object = JSONValue.parse(input)?.object else { return "" }
        for key in ["command", "path", "from", "query", "target"] {
            if let value = object[key]?.string { return value }
        }
        return ""
    }

}
