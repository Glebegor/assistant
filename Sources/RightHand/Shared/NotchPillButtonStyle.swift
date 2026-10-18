import SwiftUI

/// Rounded button used inside the dark notch panel.
struct NotchPillButtonStyle: ButtonStyle {
    var prominent = false
    var tint: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(prominent ? .black : .white)
            .background(prominent ? tint : .white.opacity(0.12), in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == NotchPillButtonStyle {
    static func notchPill(prominent: Bool = false, tint: Color = .white) -> NotchPillButtonStyle {
        NotchPillButtonStyle(prominent: prominent, tint: tint)
    }
}
