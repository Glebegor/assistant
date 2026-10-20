import AppKit
import SwiftUI

/// Settings → Assistant: API keys (stored in the Keychain) and models.
struct AssistantSettingsPane: View {
    @AppStorage(ChatSettings.Key.claudeModel) private var claudeModel = ChatSettings.Default.claudeModel
    @AppStorage(ChatSettings.Key.openAIModel) private var openAIModel = ChatSettings.Default.openAIModel
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

            VoiceSettingsSection()

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
                SettingsFooter("API keys are stored in your Mac's Keychain and are only sent to Anthropic or OpenAI. Using these APIs is billed by them.")
            }
        }
        .formStyle(.grouped)
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

/// Talking to the AI with a shortcut, and reading answers aloud with the Mac's own voices.
private struct VoiceSettingsSection: View {
    @AppStorage(VoiceSettings.Key.voiceID) private var voiceID = ""
    @AppStorage(VoiceSettings.Key.rate) private var rate = 0.52
    @AppStorage(VoiceSettings.Key.speakVoiceAnswers) private var speakAnswers = true
    @State private var languages = VoiceRecognizer.languages
    @State private var shortcut = Shortcut.voice
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var shortcutMessage: String?

    var body: some View {
        Section {
            LabeledContent {
                Button(isRecording ? L("Press keys…") : shortcut.displayName) { isRecording ? stopRecording() : startRecording() }
                    .monospaced()
                    .keyboardShortcut(isRecording ? .cancelAction : nil)
            } label: {
                SettingsRowLabel("Talk to Ellipse", subtitle: shortcutMessage ?? L("%@. Press once to talk, again to send. Esc cancels.", shortcut.spokenName),
                                 systemImage: "mic.fill", color: shortcutMessage == nil ? .blue : .orange)
            }
            VStack(alignment: .leading, spacing: 8) {
                SettingsRowLabel("Listen in", subtitle: L("Only the languages you speak. Fewer languages are recognized faster and better."),
                                 systemImage: "waveform", color: .teal)
                HStack(spacing: 14) {
                    ForEach([("en", "English"), ("uk", "Українська"), ("cs", "Čeština"), ("ru", "Русский")], id: \.0) { code, name in
                        Toggle(isOn: Binding(
                            get: { languages.contains(code) },
                            set: { on in
                                var next = languages.filter { $0 != code }
                                if on { next.append(code) }
                                // At least one language stays on.
                                guard !next.isEmpty else { NSSound.beep(); return }
                                VoiceRecognizer.languages = VoiceRecognizer.automaticLanguages.filter(next.contains)
                                languages = VoiceRecognizer.languages
                            }
                        )) { Text(verbatim: name) }
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(.leading, 30)
            }
            Toggle(isOn: $speakAnswers) {
                SettingsRowLabel("Read voice answers aloud", systemImage: "speaker.wave.2.fill", color: .indigo)
            }
            LabeledContent {
                HStack {
                    Picker("Voice", selection: $voiceID) {
                        Text("Automatic (best for the language)").tag("")
                        ForEach(VoiceSettings.voices, id: \.identifier) { voice in
                            Text(verbatim: "\(voice.name) — \(Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language)"
                                 + (voice.quality == .premium ? " ★★" : voice.quality == .enhanced ? " ★" : ""))
                                .tag(voice.identifier)
                        }
                    }
                    .labelsHidden().fixedSize()
                    Button("Try", systemImage: "play.circle.fill") {
                        SpeechPlayer.shared.speak(L("Hi! I'm RightHand, your right hand on the Mac."))
                    }
                    .labelStyle(.iconOnly).buttonStyle(.borderless).font(.title3)
                }
            } label: {
                SettingsRowLabel("Voice", systemImage: "person.wave.2.fill", color: .purple)
            }
            LabeledContent {
                Slider(value: $rate, in: 0.35...0.65).frame(width: 160)
            } label: {
                SettingsRowLabel("Speed", systemImage: "hare.fill", color: .orange)
            }
        } header: {
            Text("Ellipse — voice assistant")
        } footer: {
            SettingsFooter("Speech is made by your Mac, offline and free. Nicer voices (★) can be downloaded in System Settings → Accessibility → Spoken Content → System Voice → Manage Voices.")
        }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        isRecording = true
        NotificationCenter.default.post(name: VoiceAssistant.pauseShortcutNotification, object: true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stopRecording(); return nil } // Esc
            guard let new = Shortcut(event: event) else {
                NSSound.beep()
                shortcutMessage = L("Use ⌘, ⌥ or ⌃ together with a key.")
                return nil
            }
            guard !new.isReservedBySystem else {
                NSSound.beep()
                shortcutMessage = L("%@ is used by macOS (for example Spotlight). Choose another.", new.displayName)
                return nil
            }
            shortcutMessage = nil
            shortcut = new
            Shortcut.voice = new
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        NotificationCenter.default.post(name: VoiceAssistant.pauseShortcutNotification, object: false)
    }
}
