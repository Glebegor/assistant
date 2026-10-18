import AppKit
import SwiftUI

/// Settings → Blocking: which sites are blocked during focus sessions.
struct BlockerSettingsPane: View {
    @AppStorage(BlockerSettings.Key.enabled) private var enabled = BlockerSettings.Default.enabled
    @AppStorage(BlockerSettings.Key.rules) private var rulesText = BlockerSettings.Default.rules
    @State private var newRule = ""

    private static let suggestions = ["youtube.com", "x.com", "reddit.com", "facebook.com", "netflix.com", "twitch.tv"]

    private var rules: [String] {
        rulesText.split(whereSeparator: \.isNewline).map(String.init).filter { BlockRule($0) != nil }
    }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $enabled) {
                    SettingsRowLabel("Block distracting sites during focus",
                                     subtitle: "Only while a Pomodoro focus session is running. Breaks are free.",
                                     systemImage: "hand.raised.fill", color: .red)
                }
            }

            Section {
                ForEach(rules, id: \.self) { rule in
                    HStack {
                        Image(systemName: rule.contains("/") ? "link" : "globe")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        Text(rule)
                        Spacer()
                        Button("Remove", systemImage: "minus.circle.fill") { remove(rule) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                            .help("Remove")
                    }
                }
                HStack {
                    TextField("Add a site", text: $newRule, prompt: Text("e.g. instagram.com or youtube.com/shorts"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .onSubmit(addNewRule)
                    Button("Add", action: addNewRule)
                        .disabled(BlockRule(newRule) == nil)
                    let unused = Self.suggestions.filter { !rules.contains($0) }
                    Menu("Quick Add") {
                        ForEach(unused, id: \.self) { site in
                            Button(site) { add(site) }
                        }
                    }
                    .fixedSize()
                    .disabled(unused.isEmpty)
                }
            } header: {
                Text("Blocked sites")
            } footer: {
                SettingsFooter("""
                instagram.com blocks the whole site and its subdomains. \
                youtube.com/shorts blocks only addresses that start with it. \
                * matches anything, e.g. reddit.com/r/*/comments.
                """)
            }
            .disabled(!enabled)

            Section {
                LabeledContent {
                    Button("Permissions…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                    }
                    .help("Open Privacy & Security → Automation")
                } label: {
                    SettingsRowLabel("Safari, Chrome, Arc, Brave, Edge, Vivaldi",
                                     subtitle: "The first time, macOS asks to let RightHand control each browser. Click OK.",
                                     systemImage: "safari.fill", color: .blue)
                }
            } header: {
                Text("Browsers")
            } footer: {
                SettingsFooter("Firefox doesn't let other apps see its address bar, so it isn't blocked yet.")
            }
        }
        .formStyle(.grouped)
    }

    private func addNewRule() {
        guard BlockRule(newRule) != nil else { return }
        add(newRule.trimmingCharacters(in: .whitespaces))
        newRule = ""
    }

    private func add(_ rule: String) {
        guard !rules.contains(rule) else { return }
        rulesText = (rules + [rule]).joined(separator: "\n")
    }

    private func remove(_ rule: String) {
        rulesText = rules.filter { $0 != rule }.joined(separator: "\n")
    }
}
