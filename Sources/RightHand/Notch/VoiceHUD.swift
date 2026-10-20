import SwiftUI

/// What the closed notch shows while you talk to the AI: it grows into a small card under the
/// camera with the words you're saying, what the AI is doing, then its answer.
struct VoiceHUD: View {
    let voice: VoiceAssistant
    /// Height of the camera area at the top of the card.
    let topInset: CGFloat

    static func size(for phase: VoiceAssistant.Phase, collapsed: CGSize) -> CGSize {
        let width = max(collapsed.width + 160, 420)
        switch phase {
        case .idle: return collapsed
        case .answer: return CGSize(width: width + 60, height: collapsed.height + 92)
        case .failed: return CGSize(width: width, height: collapsed.height + 62)
        default: return CGSize(width: width, height: collapsed.height + 56)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: topInset)
            HStack(alignment: .center, spacing: 12) {
                icon.frame(width: 34)
                VStack(alignment: .leading, spacing: 3) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 18)
            .frame(maxHeight: .infinity)
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var icon: some View {
        switch voice.phase {
        case .listening: LevelBars(level: voice.level)
        case .transcribing, .working: ProgressView().controlSize(.small).tint(.white)
        case .answer: Image(systemName: "sparkles").font(.title3).foregroundStyle(.cyan)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").font(.title3).foregroundStyle(.orange)
        case .idle: EmptyView()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch voice.phase {
        case .listening:
            Text(voice.transcript.isEmpty ? L("Listening…") : voice.transcript)
                .lineLimit(1).truncationMode(.head)
                .foregroundStyle(voice.transcript.isEmpty ? .secondary : .primary)
            Text(L("%@ to send · Esc to cancel", Shortcut.voice.displayName)).font(.caption2).foregroundStyle(.secondary)
        case .transcribing:
            Text("Recognizing…").foregroundStyle(.secondary)
        case .working:
            Text(voice.activeEngine?.activity ?? L("Thinking…")).lineLimit(1)
            Text(verbatim: voice.transcript).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
        case .answer(let text):
            Text(SpeechPlayer.plainText(text)).font(.callout).lineLimit(3)
        case .failed(let message):
            Text(message).font(.callout).lineLimit(2)
        case .idle:
            EmptyView()
        }
    }
}

/// Five bars that move with your voice.
private struct LevelBars: View {
    let level: Float

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            bars(at: timeline.date.timeIntervalSinceReferenceDate)
        }
    }

    private func bars(at time: TimeInterval) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<5, id: \.self) { index in
                Capsule().fill(.cyan.gradient).frame(width: 3, height: height(of: index, at: time))
            }
        }
        .frame(height: 24)
    }

    private func height(of bar: Int, at time: TimeInterval) -> CGFloat {
        let wave = CGFloat((sin(time * 7 + Double(bar) * 1.3) + 1) / 2)
        return 4 + 18 * CGFloat(level) * (0.45 + 0.55 * wave)
    }
}

/// The blue light around the notch while you talk; it slowly turns and breathes with your voice.
struct NotchGlow: View {
    let size: CGSize
    let radius: CGFloat
    let level: Float
    /// Calmer while the AI works, livelier while listening.
    let isListening: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            glow(at: timeline.date.timeIntervalSinceReferenceDate)
        }
        .allowsHitTesting(false)
    }

    private func glow(at time: TimeInterval) -> some View {
        let speed: Double = isListening ? 140 : 70
        let angle = Angle.degrees((time * speed).truncatingRemainder(dividingBy: 360))
        let calm = CGFloat((sin(time * 2.4) + 1) / 2) * 0.5
        let breathe: CGFloat = isListening ? CGFloat(level) : calm
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: radius, bottomTrailingRadius: radius, style: .continuous)
        let colors: [Color] = [.blue, .cyan, Color(red: 0.45, green: 0.35, blue: 1), .blue, .cyan, .blue]
        let gradient = AngularGradient(colors: colors, center: .center, angle: angle)
        let outerWidth: CGFloat = 10 + 14 * breathe
        let outerBlur: CGFloat = 16 + 10 * breathe
        let rimWidth: CGFloat = 3 + 3 * breathe
        return ZStack {
            shape.stroke(gradient, lineWidth: outerWidth).blur(radius: outerBlur).opacity(0.85)
            shape.stroke(gradient, lineWidth: rimWidth).blur(radius: 4)
            shape.stroke(gradient, lineWidth: 1.5)
        }
        .frame(width: size.width, height: size.height)
    }
}

