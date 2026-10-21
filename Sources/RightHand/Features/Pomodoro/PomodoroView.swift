import SwiftUI

/// Pomodoro tab inside the notch panel.
struct PomodoroView: View {
    let timer: PomodoroTimer
    var showStats: () -> Void = {}

    var body: some View {
        HStack(spacing: 32) {
            ring
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(timer.phase.title)
                        .font(.title3.weight(.semibold))
                    sessionDots
                }
                HStack(spacing: 8) {
                    Button(timer.isRunning ? "Pause" : (timer.isPaused ? "Resume" : "Start"),
                           systemImage: timer.isRunning ? "pause.fill" : "play.fill") { timer.toggle() }
                        .buttonStyle(.notchPill(prominent: true, tint: timer.phase.color))
                    Button("Reset", systemImage: "arrow.counterclockwise") { timer.reset() }
                        .buttonStyle(.notchPill())
                        .labelStyle(.iconOnly)
                        .help("Reset")
                    Button("Skip", systemImage: "forward.end.fill") { timer.skip() }
                        .buttonStyle(.notchPill())
                        .labelStyle(.iconOnly)
                        .help("Skip to next phase")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            Button("Statistics", systemImage: "chart.bar.fill", action: showStats)
                .buttonStyle(.notchPill())
                .labelStyle(.iconOnly)
                .help("This week: focus, tasks and meetings")
        }
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.1), lineWidth: 8)
            Circle()
                .trim(from: 0, to: timer.progress)
                .stroke(timer.phase.color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: timer.progress)
            Text(timer.formattedRemaining)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(width: 130, height: 130)
    }

    private var sessionDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<timer.sessionsBeforeLongBreak, id: \.self) { index in
                Circle()
                    .fill(index < timer.sessionInCycle ? PomodoroPhase.focus.color : .white.opacity(0.2))
                    .frame(width: 7, height: 7)
            }
            Text("\(timer.completedFocusSessions) done")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
        }
    }
}

extension PomodoroPhase {
    var color: Color {
        switch self {
        case .focus: .orange
        case .shortBreak: .green
        case .longBreak: .teal
        }
    }
}
