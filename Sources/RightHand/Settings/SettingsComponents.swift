import SwiftUI

/// Row title with a quiet icon and an optional grey explanation under the title.
/// (`color` is kept for callers; the minimal style draws every icon in one soft tone.)
struct SettingsRowLabel: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let color: Color

    init(_ title: String, subtitle: String? = nil, systemImage: String, color: Color) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                if let subtitle {
                    Text(LocalizedStringKey(subtitle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Theme.neon.opacity(0.85))
                .frame(width: 22, height: 22)
        }
    }
}

/// Row with an icon, a value and a stepper on the right, e.g. "Focus  25 min ⌃⌄".
struct SettingsStepperRow: View {
    let title: String
    let systemImage: String
    let color: Color
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    let unit: String

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                Text(verbatim: "\(value) \(L(unit))")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Stepper(title, value: $value, in: range, step: step)
                    .labelsHidden()
            }
        } label: {
            SettingsRowLabel(title, systemImage: systemImage, color: color)
        }
    }
}

/// Picker of macOS sounds that plays the sound when you choose it, plus a ▶ button.
struct SettingsSoundRow: View {
    let title: String
    let systemImage: String
    let color: Color
    @Binding var selection: String

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                Picker(title, selection: $selection) {
                    Text("None").tag("")
                    Divider()
                    ForEach(PomodoroSound.available, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .onChange(of: selection) { _, name in PomodoroSound.play(name) }
                Button("Play", systemImage: "play.circle.fill") { PomodoroSound.play(selection) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .font(.title3)
                    .disabled(selection.isEmpty)
                    .help("Play sound")
            }
        } label: {
            SettingsRowLabel(title, systemImage: systemImage, color: color)
        }
    }
}

/// Explanation text under a section, aligned with the rows.
struct SettingsFooter: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(LocalizedStringKey(text))
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
