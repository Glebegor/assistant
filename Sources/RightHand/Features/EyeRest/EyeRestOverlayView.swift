import SwiftUI

/// Full-screen content shown during an eye break.
struct EyeRestOverlayView: View {
    let controller: EyeRestController

    private var progress: Double {
        guard controller.restDuration > 0 else { return 0 }
        return 1 - Double(controller.restRemaining) / Double(controller.restDuration)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
            VStack(spacing: 28) {
                Image(systemName: "eye")
                    .font(.system(size: 52, weight: .light))
                    .symbolEffect(.pulse, options: .repeating)
                VStack(spacing: 10) {
                    Text("Rest your eyes")
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                    Text("Look at something at least 6 m (20 ft) away and blink a few times.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))
                }
                ZStack {
                    Circle().stroke(.white.opacity(0.15), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(.teal, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: progress)
                    Text("\(controller.restRemaining)")
                        .font(.system(size: 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.default, value: controller.restRemaining)
                }
                .frame(width: 120, height: 120)
                HStack(spacing: 10) {
                    Button("Postpone \(EyeRestSettings.postponeMinutes) min", systemImage: "clock.arrow.circlepath") {
                        controller.postpone()
                    }
                    .buttonStyle(.notchPill())
                    Button("Pause 1 hour", systemImage: "pause.fill") { controller.pause() }
                        .buttonStyle(.notchPill())
                    Button("Skip", systemImage: "xmark") { controller.skip() }
                        .buttonStyle(.notchPill())
                        .keyboardShortcut(.cancelAction) // Esc
                    Button("Turn Off", systemImage: "eye.slash") { controller.setEnabled(false) }
                        .buttonStyle(.notchPill())
                        .help("Stop eye breaks until you turn them on again (menu bar or Settings → Eye Rest)")
                }
            }
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(40)
        }
        .environment(\.colorScheme, .dark)
    }
}
