import AppKit
import SwiftUI

/// Settings → Assistant: API keys (stored in the Keychain) and models.
struct AssistantSettingsPane: View {
    @AppStorage(ChatSettings.Key.claudeModel) private var claudeModel = ChatSettings.Default.claudeModel
    @AppStorage(ChatSettings.Key.openAIModel) private var openAIModel = ChatSettings.Default.openAIModel

    var body: some View {
        Form {
            Section {
                APIKeyRow(provider: .claude, color: .orange, systemImage: "sparkle")
                LabeledContent {
                    Picker("Model", selection: $claudeModel) {
                        ForEach(ChatSettings.claudeModels, id: \.id) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                    .fixedSize()
                } label: {
                    SettingsRowLabel("Model", subtitle: "Opus is the smartest, Haiku the fastest and cheapest.",
                                     systemImage: "cpu", color: .brown)
                }
            } header: {
                Text("Claude")
            }

            Section {
                APIKeyRow(provider: .openAI, color: .green, systemImage: "bubble.left.and.bubble.right.fill")
                LabeledContent {
                    TextField("Model", text: $openAIModel, prompt: Text(ChatSettings.Default.openAIModel))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .frame(width: 160)
                } label: {
                    SettingsRowLabel("Model", subtitle: "Any model name from your OpenAI account, e.g. gpt-5.",
                                     systemImage: "cpu", color: .mint)
                }
            } header: {
                Text("ChatGPT")
            } footer: {
                SettingsFooter("API keys are stored in your Mac's Keychain and are only sent to Anthropic or OpenAI. Using the API is billed by them per message.")
            }
        }
        .formStyle(.grouped)
    }
}

/// Shows whether a key is saved; lets you paste a new one or remove it.
private struct APIKeyRow: View {
    let provider: ChatProvider
    let color: Color
    let systemImage: String
    @State private var isSaved = false
    @State private var draft = ""

    var body: some View {
        LabeledContent {
            if isSaved {
                HStack(spacing: 8) {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Button("Remove") {
                        Keychain.delete(provider.keychainAccount)
                        refresh()
                    }
                }
            } else {
                HStack(spacing: 8) {
                    SecureField("API key", text: $draft, prompt: Text("Paste key"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .frame(width: 160)
                        .onSubmit(save)
                    Button("Save", action: save)
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        } label: {
            SettingsRowLabel("API key", subtitle: "Get one at \(provider.keysURL.host() ?? "")",
                             systemImage: "key.fill", color: color)
                .onTapGesture { NSWorkspace.shared.open(provider.keysURL) }
                .help("Open \(provider.keysURL.absoluteString)")
        }
        .onAppear(perform: refresh)
    }

    private func save() {
        let key = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        Keychain.save(key, for: provider.keychainAccount)
        draft = ""
        refresh()
    }

    private func refresh() {
        isSaved = Keychain.read(provider.keychainAccount) != nil
    }
}
