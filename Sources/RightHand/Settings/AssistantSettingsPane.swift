import AppKit
import SwiftUI

/// Settings → Assistant: API keys (stored in the Keychain) and models.
struct AssistantSettingsPane: View {
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
                SettingsFooter("Who you are, what you work on, how you like answers, links (GitHub, LinkedIn, website…). Every AI reads this at the start of every chat.")
            }

            ProviderSection(provider: .claude, color: .orange,
                            subtitle: "Fable and Opus are the smartest, Haiku the fastest and cheapest.")
            ProviderSection(provider: .openAI, color: .green, subtitle: "The models your OpenAI account can use.")
            ProviderSection(provider: .gemini, color: .blue, subtitle: "Google's models.",
                            footer: "Create a free key in Google AI Studio and paste it as the API key.")
            ProviderSection(provider: .copilot, color: .gray, subtitle: "The models of your Copilot subscription, or of GitHub Models.",
                            footer: "Sign in with your Copilot subscription for the same models as in VS Code (Claude, the newest GPT). This uses the API of the Copilot editor plugins, which GitHub doesn't offer to other apps: it may stop working, and GitHub could limit the account. Without signing in, Copilot uses GitHub Models: create a fine-grained GitHub token with the “Models: read” permission and paste it as the API key.")

            MeetingAISection()

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
/// Settings → Ellipse.
struct EllipseSettingsPane: View {
    var body: some View {
        Form { VoiceSettingsSection() }.formStyle(.grouped)
    }
}

private struct VoiceSettingsSection: View {
    @AppStorage(VoiceSettings.Key.voiceID) private var voiceID = ""
    @AppStorage(VoiceSettings.Key.rate) private var rate = 0.52
    @AppStorage(VoiceSettings.Key.speakVoiceAnswers) private var speakAnswers = true
    @AppStorage(VoiceSettings.Key.wakeWord) private var wakeWord = true
    @State private var languages = VoiceRecognizer.languages
    @State private var shortcut = Shortcut.voice
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var shortcutMessage: String?
    @AppStorage(VoiceSettings.Key.enabled) private var enabled = true
    @AppStorage(Microphones.key) private var microphone = ""
    @State private var microphones = Microphones.all

    var body: some View {
        Section {
            Toggle(isOn: $enabled) {
                SettingsRowLabel("Turn on Ellipse", subtitle: L("Off: no shortcut, no wake word, no microphone, no record buttons."),
                                 systemImage: "power", color: .green)
            }
            Group {
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
            LabeledContent {
                Picker("Microphone", selection: $microphone) {
                    Text("Mac default").tag("")
                    ForEach(microphones) { Text(verbatim: $0.name).tag($0.id) }
                }
                .labelsHidden().fixedSize()
                .onAppear { microphones = Microphones.all }
            } label: {
                SettingsRowLabel("Microphone", subtitle: L("For Ellipse and the “My voice” track of recordings"),
                                 systemImage: "mic", color: .blue)
            }
            Toggle(isOn: $wakeWord) {
                SettingsRowLabel("Wake word “Hey Ellipse”",
                                 subtitle: L("Say “Hey Ellipse” (or “Эй, Эллипс”), then your request; it's sent when you pause. Listens on your Mac only; the microphone indicator stays on."),
                                 systemImage: "ear.fill", color: .cyan)
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
            }
            .disabled(!enabled)
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

/// One AI: its key and its model (the list comes from the provider, so new models appear by themselves).
private struct ProviderSection: View {
    let provider: ChatProvider
    let color: Color
    let subtitle: String
    var footer: String?
    @AppStorage private var model: String
    private var catalog: ModelCatalog { .shared }

    init(provider: ChatProvider, color: Color, subtitle: String, footer: String? = nil) {
        self.provider = provider
        self.color = color
        self.subtitle = subtitle
        self.footer = footer
        _model = AppStorage(wrappedValue: ChatSettings.model(for: provider), ChatSettings.modelKey(for: provider))
    }

    var body: some View {
        Section {
            if provider == .copilot {
                CopilotSubscriptionRow(color: color) { model = ChatSettings.model(for: .copilot) }
                APIKeyRow(account: ChatProvider.gitHubModelsAccount, keysURL: provider.keysURL, color: color, systemImage: provider.systemImage)
            } else {
                APIKeyRow(account: provider.keychainAccount, keysURL: provider.keysURL, color: color, systemImage: provider.systemImage)
            }
            LabeledContent {
                HStack(spacing: 6) {
                    Picker("Model", selection: $model) {
                        ForEach(catalog.list(for: provider)) { Text(verbatim: $0.name).tag($0.id) }
                        if !catalog.list(for: provider).contains(where: { $0.id == model }) { Text(verbatim: model).tag(model) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await catalog.refresh(provider) } }
                        .labelStyle(.iconOnly).buttonStyle(.borderless)
                        .disabled(catalog.loading.contains(provider))
                        .help("Load the models your key can use")
                }
            } label: {
                SettingsRowLabel("Model", subtitle: subtitle, systemImage: "cpu", color: color)
            }
        } header: {
            Text(verbatim: provider == .copilot ? "GitHub Copilot" : provider.title)
        } footer: {
            if let footer { SettingsFooter(footer) }
        }
        .task { await catalog.refresh(provider) }
    }
}

/// Signing in to the Copilot subscription with a code entered on github.com.
private struct CopilotSubscriptionRow: View {
    let color: Color
    /// Called after signing in or out (the model names change).
    let onChange: () -> Void
    @State private var isSignedIn = CopilotAuth.isSignedIn
    @State private var code: CopilotAuth.DeviceCode?
    @State private var error: String?
    @State private var signIn: Task<Void, Never>?

    var body: some View {
        LabeledContent {
            if isSignedIn {
                Button("Sign Out") {
                    CopilotAuth.signOut()
                    changed()
                }
            } else if let code {
                HStack(spacing: 8) {
                    Text(verbatim: code.userCode)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .textSelection(.enabled)
                    Button("Open GitHub") { NSWorkspace.shared.open(code.verificationURL) }
                    Button("Cancel") { signIn?.cancel(); self.code = nil }
                }
            } else {
                Button("Sign In") { start() }
            }
        } label: {
            SettingsRowLabel("Copilot subscription",
                             subtitle: error ?? (isSignedIn ? L("Signed in — Copilot uses your subscription's models.")
                                 : code != nil ? L("Enter this code on GitHub (it's copied).") : L("Optional: the models you have in VS Code.")),
                             systemImage: "person.crop.circle.badge.checkmark", color: color)
        }
    }

    private func start() {
        error = nil
        signIn = Task {
            do {
                let code = try await CopilotAuth.startSignIn()
                self.code = code
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(code.userCode, forType: .string)
                NSWorkspace.shared.open(code.verificationURL)
                try await CopilotAuth.finishSignIn(code)
                self.code = nil
                changed()
            } catch is CancellationError {
            } catch {
                self.code = nil
                self.error = error.localizedDescription
            }
        }
    }

    private func changed() {
        isSignedIn = CopilotAuth.isSignedIn
        UserDefaults.standard.set(ModelCatalog.builtIn(.copilot).first?.id, forKey: ChatSettings.Key.copilotModel)
        ModelCatalog.shared.reset(.copilot)
        onChange()
    }
}

/// The AI and model that write meeting reviews.
private struct MeetingAISection: View {
    @AppStorage(MeetingAISettings.providerKey) private var provider = ""
    @AppStorage(MeetingAISettings.modelKey) private var model = ""
    private var catalog: ModelCatalog { .shared }

    var body: some View {
        Section {
            LabeledContent {
                Picker("AI", selection: $provider) {
                    Text("Same as the chat").tag("")
                    Divider()
                    ForEach(ChatProvider.allCases) { Text(verbatim: $0 == .copilot ? "GitHub Copilot" : $0.title).tag($0.rawValue) }
                }
                .labelsHidden()
                .fixedSize()
            } label: {
                SettingsRowLabel("Analyze meetings with", subtitle: "Reviews of your recordings: summary, timeline, tasks and assessment.",
                                 systemImage: "waveform.badge.magnifyingglass", color: .purple)
            }
            if let chosen = ChatProvider(rawValue: provider) {
                LabeledContent {
                    Picker("Model", selection: $model) {
                        ForEach(catalog.list(for: chosen)) { Text(verbatim: $0.name).tag($0.id) }
                        if !catalog.list(for: chosen).contains(where: { $0.id == model }) { Text(verbatim: model).tag(model) }
                    }
                    .labelsHidden()
                    .fixedSize()
                } label: {
                    SettingsRowLabel("Model", systemImage: "cpu", color: .purple)
                }
            }
        } header: {
            Text("Meeting analysis")
        } footer: {
            SettingsFooter("A long meeting is a big text: a strong model with a large context (Claude Opus or Sonnet, GPT-5, Gemini Pro) writes a much better review. GitHub Models has small limits.")
        }
        .onChange(of: provider) { _, new in
            // Start from the model that AI uses in the chat.
            model = ChatProvider(rawValue: new).map { ChatSettings.model(for: $0) } ?? ""
        }
    }
}
