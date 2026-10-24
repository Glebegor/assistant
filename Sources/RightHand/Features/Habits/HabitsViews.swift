import SwiftUI

/// Today's habits as a row of chips at the top of the Tasks tab. Click to mark one; right-click
/// a counted habit to take one back.
struct HabitsStrip: View {
    let store: HabitStore
    let showAnalysis: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            if store.habits.isEmpty {
                Button { openSettings() } label: {
                    Label("Add habits", systemImage: "plus.circle").font(.caption)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(store.today) { HabitChip(store: store, habit: $0) }
                        if store.today.isEmpty {
                            Text("No habits for today").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
                .scrollIndicators(.never)
                Button("Habit analysis", systemImage: "chart.xyaxis.line", action: showAnalysis)
                    .buttonStyle(.notchPill()).labelStyle(.iconOnly)
                    .help("Streaks, completion and a calendar of your habits")
                Button("Edit habits", systemImage: "slider.horizontal.3", action: openSettings)
                    .buttonStyle(.notchPill()).labelStyle(.iconOnly)
                    .help("Add, change and remind about habits")
            }
        }
    }
}

private struct HabitChip: View {
    let store: HabitStore
    let habit: Habit

    var body: some View {
        let value = store.value(habit)
        let done = habit.kind == .avoid ? value == 0 : value >= habit.dailyTarget
        let color: Color = habit.kind == .avoid ? (value > 0 ? .red : .green) : (done ? .green : Theme.neon)
        Button { store.tap(habit) } label: {
            HStack(spacing: 5) {
                Text(verbatim: habit.emoji)
                Text(verbatim: habit.name).lineLimit(1)
                switch habit.kind {
                case .count:
                    Text(verbatim: "\(value)/\(habit.dailyTarget)").monospacedDigit().foregroundStyle(.secondary)
                case .avoid:
                    let streak = store.stats(habit).current
                    Text(value > 0 ? L("slipped") : L("%lld d", streak)).foregroundStyle(.secondary)
                case .check:
                    Image(systemName: done ? "checkmark.circle.fill" : "circle").foregroundStyle(done ? .green : .secondary)
                }
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(color.opacity(done && habit.kind != .avoid ? 0.22 : 0.1), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(done ? 0.55 : 0.25), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(habit.kind == .avoid ? L("Click if you slipped today") : habit.kind == .count ? L("Click for one more") : L("Click when done"))
        .contextMenu {
            if habit.kind == .count {
                Button("One Less") { store.decrement(habit) }
                Button("Done for Today") { store.set(habit, habit.dailyTarget) }
            }
            Button("Reset Today") { store.set(habit, 0) }
        }
        .animation(.easeOut(duration: 0.2), value: value)
    }
}

/// Analysis inside the Tasks tab: every habit with its streaks, completion and a heat map of
/// the last 18 weeks.
struct HabitsAnalysisView: View {
    let store: HabitStore
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button(action: close) { Label("Tasks", systemImage: "chevron.left") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                Spacer()
                Text("Habits").font(.headline)
                Spacer()
                Color.clear.frame(width: 50, height: 1)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if store.habits.count > 1 {
                        HabitCard(title: L("All habits"), emoji: "✨", subtitle: nil, stats: nil) { store.overallLevel(on: $0) }
                    }
                    ForEach(store.habits) { habit in
                        HabitCard(title: habit.name, emoji: habit.emoji,
                                  subtitle: [habit.scheduleText, habit.kind == .count ? L("goal %lld", habit.dailyTarget) : nil,
                                             habit.kind == .avoid ? L("quitting") : nil].compactMap { $0 }.joined(separator: " · "),
                                  stats: store.stats(habit), color: habit.kind == .avoid ? .green : Theme.neon) { store.level(habit, on: $0) }
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }
}

private struct HabitCard: View {
    let title: String
    let emoji: String
    let subtitle: String?
    let stats: HabitStore.Stats?
    var color: Color = Theme.neon
    let level: (Date) -> Double?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(verbatim: emoji)
                    Text(verbatim: title).font(.callout.weight(.semibold)).lineLimit(1)
                }
                if let subtitle { Text(verbatim: subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1) }
                if let stats {
                    let unit = stats.unit == .weeks ? L("weeks") : L("days")
                    HStack(spacing: 12) {
                        metric("\(stats.current)", L("streak, %@", unit), highlight: stats.current > 0)
                        metric("\(stats.best)", L("best"))
                    }
                    HStack(spacing: 12) {
                        metric(percent(stats.rate7), L("7 days"))
                        metric(percent(stats.rate30), L("30 days"))
                    }
                }
            }
            .frame(width: 170, alignment: .leading)
            HeatMap(color: color, level: level)
        }
        .themeCard(padding: 10)
    }

    private func metric(_ value: String, _ label: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: value).font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(highlight ? color : .white)
            Text(verbatim: label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(minWidth: 70, alignment: .leading)
    }

    private func percent(_ rate: Double?) -> String { rate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—" }
}

/// Weeks as columns, days as rows, like GitHub's contributions: brighter = more done.
private struct HeatMap: View {
    let color: Color
    let level: (Date) -> Double?
    static let weeks = 18

    var body: some View {
        let calendar = Calendar.current
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? calendar.startOfDay(for: Date())
        let first = calendar.date(byAdding: .weekOfYear, value: -(Self.weeks - 1), to: thisWeek)!
        HStack(spacing: 3) {
            ForEach(0..<Self.weeks, id: \.self) { week in
                VStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { weekday in
                        let day = calendar.date(byAdding: .day, value: week * 7 + weekday, to: first)!
                        cell(day)
                    }
                }
            }
        }
    }

    private func cell(_ day: Date) -> some View {
        let value = level(day)
        let isToday = Calendar.current.isDateInToday(day)
        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(value.map { $0 > 0 ? color.opacity(0.25 + 0.75 * $0) : .white.opacity(0.08) } ?? .white.opacity(day > Date() ? 0 : 0.03))
            .frame(width: 10, height: 10)
            .overlay {
                if isToday { RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(.white.opacity(0.7), lineWidth: 1) }
            }
            .help(Text(day, format: .dateTime.weekday(.abbreviated).day().month()) + Text(value.map { " · \(Int(($0 * 100).rounded()))%" } ?? ""))
    }
}
