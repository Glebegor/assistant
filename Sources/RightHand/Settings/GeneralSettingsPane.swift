import SwiftUI

/// Settings → General: interface language.
struct GeneralSettingsPane: View {
    @State private var language = AppLanguage.selected
    /// The language RightHand started with; a different choice needs a restart.
    private let startedWith = AppLanguage.selected

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Picker("Language", selection: $language) {
                        ForEach(AppLanguage.allCases) { Text(verbatim: $0.name).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: language) { _, language in AppLanguage.selected = language }
                } label: {
                    SettingsRowLabel("Language", systemImage: "globe", color: .blue)
                }
                if language != startedWith {
                    HStack {
                        Text("Restart RightHand to switch the language.").foregroundStyle(.secondary)
                        Spacer()
                        Button("Restart Now") { AppLanguage.restartApp() }
                            .keyboardShortcut(.defaultAction)
                    }
                }
            } footer: {
                SettingsFooter("Changes the language of RightHand's menus, settings and panel. The AI answers in the language you write to it.")
            }
        }
        .formStyle(.grouped)
    }
}
