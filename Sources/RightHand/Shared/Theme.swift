import SwiftUI

/// RightHand's window style: dark and quiet, thin cards, and a touch of blue neon on what's active.
enum Theme {
    static let neon = Color(red: 0.36, green: 0.66, blue: 1.0)
    static let neonSoft = Color(red: 0.36, green: 0.66, blue: 1.0).opacity(0.14)
    static let violet = Color(red: 0.62, green: 0.52, blue: 1.0)
    static let cardFill = Color.white.opacity(0.035)
    static let cardStroke = Color.white.opacity(0.07)
    static let hairline = Color.white.opacity(0.06)

    /// Near-black with a faint blue light from the top.
    static var background: some View {
        ZStack {
            Color(red: 0.045, green: 0.05, blue: 0.065)
            RadialGradient(colors: [neon.opacity(0.10), .clear], center: .top, startRadius: 0, endRadius: 520)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// A thin rounded card.
    func themeCard(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.cardStroke))
    }

    /// The little bit of neon: a soft blue glow.
    func neonGlow(_ isOn: Bool = true, radius: CGFloat = 8) -> some View {
        shadow(color: isOn ? Theme.neon.opacity(0.55) : .clear, radius: radius)
    }
}

/// Small uppercase label above a group.
struct ThemeCaption: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.8)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}

/// Text tabs with a thin neon line under the selected one.
struct NeonTabs<Value: Hashable>: View {
    let tabs: [(value: Value, title: LocalizedStringKey)]
    @Binding var selection: Value
    @Namespace private var underline

    var body: some View {
        HStack(spacing: 22) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { _, tab in
                let isOn = tab.value == selection
                Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = tab.value } } label: {
                    VStack(spacing: 6) {
                        Text(tab.title)
                            .font(.system(size: 13, weight: isOn ? .semibold : .regular))
                            .foregroundStyle(isOn ? .primary : .secondary)
                        ZStack {
                            Capsule().fill(.clear).frame(height: 2)
                            if isOn {
                                Capsule().fill(Theme.neon).frame(height: 2).neonGlow(radius: 4)
                                    .matchedGeometryEffect(id: "line", in: underline)
                            }
                        }
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A quiet round icon button for toolbars.
struct IconButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(isHovered ? 0.09 : 0.0), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovered ? .primary : .secondary)
        .onHover { isHovered = $0 }
        .help(title)
    }
}
