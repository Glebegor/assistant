import AppKit
import SwiftUI

/// Assistant tab: chat with Claude or ChatGPT.
struct ChatView: View {
    let store: ChatStore
    let openSettings: () -> Void
    @State private var draft = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            toolbar
            if !store.hasKey {
                missingKey
            } else if store.messages.isEmpty {
                PlaceholderView(systemImage: "sparkles",
                                title: "Ask \(store.provider.title) anything",
                                message: "Return sends, Option-Return adds a new line.")
            } else {
                conversation
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
            Text(store.modelName)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("New Chat", systemImage: "square.and.pencil") {
                store.newChat()
                isInputFocused = true
            }
            .buttonStyle(.notchPill())
            .labelStyle(.iconOnly)
            .disabled(store.messages.isEmpty)
            .help("New chat")
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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(store.messages) { MessageRow(message: $0) }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.never)
            .onChange(of: store.messages.last?.text) { _, _ in
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message \(store.provider.title)…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .onSubmit(send)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .disabled(!store.hasKey)
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
    }

    private func send() {
        guard !store.isSending else { return }
        store.send(draft)
        draft = ""
        isInputFocused = true
    }
}

private extension View {
    func iconButton() -> some View {
        labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.system(size: 26))
            .foregroundStyle(.white)
    }
}

/// One question or answer in the conversation.
private struct MessageRow: View {
    let message: ChatMessage
    @State private var isHovered = false

    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 60)
                Text(message.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor.opacity(0.85), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(message.modelName ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if isHovered, !message.text.isEmpty {
                        Button("Copy", systemImage: "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.text, forType: .string)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .help("Copy answer")
                    }
                }
                if message.text.isEmpty && message.isStreaming {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("Thinking…").foregroundStyle(.secondary)
                    }
                } else if !message.text.isEmpty {
                    Text(Self.markdown(message.text))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if message.isDeclined {
                    Label("\(message.provider?.title ?? "The AI") declined this request. Try rephrasing it.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let error = message.errorMessage {
                    Label(error, systemImage: "xmark.octagon.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(.trailing, 40)
            .onHover { isHovered = $0 }
        }
    }

    /// Bold, italics, `code` and links; line breaks are kept.
    private static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}
