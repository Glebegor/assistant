import AppKit
import SwiftUI

/// Settings → Assistant: API keys (stored in the Keychain) and models.
struct AssistantSettingsPane: View {
    @AppStorage(ChatSettings.Key.claudeModel) private var claudeModel = ChatSettings.Default.claudeModel
    @AppStorage(ChatSettings.Key.openAIModel) private var openAIModel = ChatSettings.Default.openAIModel
    @AppStorage(VoiceSettings.Key.voiceID) private var voiceID = VoiceSettings.Default.voiceID
    @AppStorage(VoiceSettings.Key.model) private var voiceModel = VoiceSettings.Default.model
    @State private var voices: [ElevenLabs.Voice] = []
    @State private var alwaysAllowed = ToolPermissions.alwaysAllowed
    @AppStorage(ComputerAccess.key) private var wholeMac = true
    @AppStorage(AboutMe.key) private var aboutMe = ""

    var body: some View {
        Form {
            Section {
                TextEditor(text: $aboutMe)
                    .font(.body)
                    .frame(minHeight: 110)
                    .scrollContentBackground(.hidden)
            } header: {
                Text("About me")
            } footer: {
                SettingsFooter("Who you are, what you work on, how you like answers, links (GitHub, LinkedIn, website…). Claude and ChatGPT read this at the start of every chat.")
            }

            Section {
                APIKeyRow(account: ChatProvider.claude.keychainAccount, keysURL: ChatProvider.claude.keysURL,
                          color: .orange, systemImage: "sparkle")
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
                APIKeyRow(account: ChatProvider.openAI.keychainAccount, keysURL: ChatProvider.openAI.keysURL,
                          color: .green, systemImage: "bubble.left.and.bubble.right.fill")
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
            }

            Section {
                APIKeyRow(account: VoiceSettings.keychainAccount, keysURL: VoiceSettings.keysURL,
                          color: .indigo, systemImage: "waveform")
                LabeledContent {
                    HStack {
                        Picker("Voice", selection: $voiceID) {
                            if !voices.contains(where: { $0.id == voiceID }) { Text("Sarah").tag(voiceID) }
                            ForEach(voices) { Text($0.name).tag($0.id) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        Button("Try", systemImage: "play.circle.fill") {
                            SpeechPlayer.shared.speak(L("Hi! I'm RightHand, your right hand on the Mac."))
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .font(.title3)
                    }
                } label: {
                    SettingsRowLabel("Voice", systemImage: "person.wave.2.fill", color: .purple)
                }
                LabeledContent {
                    Picker("Voice model", selection: $voiceModel) {
                        ForEach(VoiceSettings.models, id: \.id) { Text(LocalizedStringKey($0.name)).tag($0.id) }
                    }
                    .labelsHidden()
                    .fixedSize()
                } label: {
                    SettingsRowLabel("Voice model", systemImage: "cpu", color: .gray)
                }
            } header: {
                Text("ElevenLabs (read answers aloud)")
            }
            .task { await loadVoices() }

            Section {
                Toggle(isOn: $wholeMac) {
                    SettingsRowLabel("Work with the whole Mac", systemImage: "desktopcomputer", color: .gray)
                }
            } footer: {
                SettingsFooter("In projects, the AI can read, create, move and delete files anywhere on your Mac and run Terminal commands. It asks you before every action outside the project folders, and before every command and deletion. Deleted files go to the Trash.")
            }

            Section {
                ForEach(Toolbox.catalog, id: \.name) { tool in
                    if Toolbox.canAlwaysAllow(tool.name) {
                        Toggle(isOn: Binding(
                            get: { !alwaysAllowed.contains(tool.name) },
                            set: { ask in
                                ToolPermissions.setAlwaysAllowed(tool.name, !ask)
                                alwaysAllowed = ToolPermissions.alwaysAllowed
                            }
                        )) {
                            Text(verbatim: tool.displayName)
                        }
                    } else {
                        LabeledContent {
                            Text("Always asks").foregroundStyle(.secondary)
                        } label: {
                            Text(verbatim: tool.displayName)
                        }
                    }
                }
            } header: {
                Text("Ask before the AI uses a tool")
            } footer: {
                SettingsFooter("API keys are stored in your Mac's Keychain and are only sent to Anthropic, OpenAI or ElevenLabs. Using these APIs is billed by them.")
            }
        }
        .formStyle(.grouped)
    }

    private func loadVoices() async {
        guard let key = Keychain.read(VoiceSettings.keychainAccount),
              let list = try? await ElevenLabs.voices(apiKey: key) else { return }
        voices = list
    }
}

/// Shows whether a key is saved; lets you paste a new one or remove it.
private struct APIKeyRow: View {
    let account: String
    let keysURL: URL
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
                        Keychain.delete(account)
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
            SettingsRowLabel("API key", subtitle: L("Get one at %@", keysURL.host() ?? ""),
                             systemImage: "key.fill", color: color)
                .onTapGesture { NSWorkspace.shared.open(keysURL) }
                .help("Open \(keysURL.absoluteString)")
        }
        .onAppear(perform: refresh)
    }

    private func save() {
        let key = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        Keychain.save(key, for: account)
        draft = ""
        refresh()
    }

    private func refresh() {
        isSaved = Keychain.read(account) != nil
    }
}
