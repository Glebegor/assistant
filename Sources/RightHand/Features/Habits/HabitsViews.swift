import SwiftUI

extension Habit {
    /// Green for a bad habit you're holding off, neon for the others.
    var tint: Color { kind == .avoid ? Color(red: 0.35, green: 0.85, blue: 0.55) : Theme.neon }
}

/// Today's habits at the top of the Tasks tab: a ring per habit that fills as you do it.
/// Click to mark one; right-click a counted habit to take one back.
struct HabitsStrip: View {
    let store: HabitStore
    let showAnalysis: () -> Void
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if store.habits.isEmpty {
                Button(action: openSettings) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                            .frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(Theme.neon.opacity(0.6), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2])))
                        Text("Add habits").font(.caption.weight(.medium))
                    }
                    .foregroundStyle(Theme.neon)
                }
                .buttonStyle(.plain)
                Spacer()
            } else {
                let today = store.today
                let done = today.filter { store.isDone($0, on: Date()) && ($0.kind == .avoid || store.value($0) > 0) }.count
                VStack(alignment: .leading, spacing: 0) {
                    Text("Habits").font(.caption.weight(.semibold))
                    Text(verbatim: "\(done)/\(today.count)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                .frame(width: 44, alignment: .leading)
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(today) { HabitChip(store: store, habit: $0) }
                        if today.isEmpty {
                            Text("Nothing for today").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
                .scrollIndicators(.never)
                Button("Habit analysis", systemImage: "chart.bar.xaxis", action: showAnalysis)
                    .buttonStyle(.notchPill()).labelStyle(.iconOnly)
                    .help("Streaks, completion and a calendar of your habits")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
    }
}

/// A ring with the emoji inside and the name and status beside it.
private struct HabitChip: View {
    let store: HabitStore
    let habit: Habit
    @State private var isHovered = false

    var body: some View {
        let value = store.value(habit)
        let slipped = habit.kind == .avoid && value > 0
        let progress: Double = switch habit.kind {
        case .avoid: slipped ? 0 : 1
        case .check: value > 0 ? 1 : 0
        case .count: min(1, Double(value) / Double(habit.dailyTarget))
        }
        let done = progress >= 1
        Button { store.tap(habit) } label: {
            HStack(spacing: 7) {
                HabitRing(emoji: habit.emoji, progress: progress, tint: slipped ? .red : habit.tint, size: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: habit.name).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                    Text(verbatim: status(value: value, slipped: slipped))
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(done && habit.kind != .avoid ? habit.tint : .secondary)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 3).padding(.trailing, 9).padding(.vertical, 3)
            .background(Color.white.opacity(isHovered ? 0.07 : 0), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(habit.kind == .avoid ? L("Click if you slipped today") : habit.kind == .count ? L("Click for one more") : L("Click when done"))
        .contextMenu {
            if habit.kind == .count {
                Button("One Less") { store.decrement(habit) }
                Button("Done for Today") { store.set(habit, habit.dailyTarget) }
            }
            Button("Reset Today") { store.set(habit, 0) }
        }
    }

    private func status(value: Int, slipped: Bool) -> String {
        switch habit.kind {
        case .count: "\(value)/\(habit.dailyTarget)"
        case .avoid: slipped ? L("slipped") : L("%lld d clean", store.stats(habit).current)
        case .check: value > 0 ? L("done") : L("to do")
        }
    }
}

/// A progress ring with an emoji in the middle; glows when full.
struct HabitRing: View {
    let emoji: String
    let progress: Double
    let tint: Color
    var size: CGFloat = 26
    var lineWidth: CGFloat = 2.5

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: progress >= 1 ? tint.opacity(0.7) : .clear, radius: 4)
            Text(verbatim: emoji).font(.system(size: size * 0.46))
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: progress)
    }
}

/// Analysis inside the Tasks tab: today at a glance, then every habit with its streaks,
/// completion and a heat map of the last 16 weeks.
struct HabitsAnalysisView: View {
    let store: HabitStore
    let close: () -> Void
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Button(action: close) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold))
                        .frame(width: 24, height: 24).background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Back to tasks")
                Text("Habits").font(.headline)
                Spacer()
                Button("Edit habits", systemImage: "slider.horizontal.3", action: openSettings)
                    .buttonStyle(.notchPill()).labelStyle(.iconOnly)
                    .help("Add, change and remind about habits")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    summary
                    ForEach(store.habits) { habit in
                        HabitRow(store: store, habit: habit)
                    }
                }
            }
            .scrollIndicators(.never)
        }
    }

    /// Today's rings, the average of the last 30 days and the longest streak running.
    private var summary: some View {
        let today = store.today
        let done = today.filter { store.isDone($0, on: Date()) && ($0.kind == .avoid || store.value($0) > 0) }.count
        let all = store.habits.map { store.stats($0) }
        let rates = all.compactMap(\.rate30)
        let average = rates.isEmpty ? nil : rates.reduce(0, +) / Double(rates.count)
        let best = zip(store.habits, all).max { $0.1.current < $1.1.current }
        return HStack(spacing: 8) {
            tile {
                HabitRing(emoji: "", progress: today.isEmpty ? 0 : Double(done) / Double(today.count), tint: Theme.neon, size: 34, lineWidth: 4)
                    .overlay(Text(verbatim: "\(done)").font(.system(size: 13, weight: .bold, design: .rounded)))
                caption(L("of %lld", today.count), L("Today"))
            }
            tile {
                Text(verbatim: average.map { "\(Int(($0 * 100).rounded()))%" } ?? "—")
                    .font(.system(size: 22, weight: .semibold, design: .rounded)).foregroundStyle(Theme.neon)
                caption(L("done on time"), L("30 days"))
            }
            tile {
                Text(verbatim: best.map { "\($0.1.current)" } ?? "0")
                    .font(.system(size: 22, weight: .semibold, design: .rounded)).foregroundStyle(.orange)
                    .shadow(color: .orange.opacity(0.5), radius: 6)
                caption(best.map { "\($0.0.emoji) \($0.0.name)" } ?? "—", L("Longest streak"))
            }
        }
    }

    private func tile(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 10) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
    }

    private func caption(_ value: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: title).font(.system(size: 10, weight: .semibold)).textCase(.uppercase).foregroundStyle(.secondary)
            Text(verbatim: value).font(.caption).lineLimit(1)
        }
    }
}

/// One habit: ring and name, streak and rates, and its heat map.
private struct HabitRow: View {
    let store: HabitStore
    let habit: Habit

    var body: some View {
        let stats = store.stats(habit)
        let unit = stats.unit == .weeks ? L("wk") : L("d")
        HStack(spacing: 12) {
            HabitRing(emoji: habit.emoji, progress: stats.rate30 ?? 0, tint: habit.tint, size: 34, lineWidth: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: habit.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                Text(verbatim: [habit.scheduleText, habit.kind == .count ? L("goal %lld", habit.dailyTarget) : nil,
                                habit.kind == .avoid ? L("quitting") : nil].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 10) {
                    metric("flame.fill", "\(stats.current) \(unit)", stats.current > 0 ? .orange : .secondary)
                    metric("trophy.fill", "\(stats.best) \(unit)", .secondary)
                    metric("checkmark.circle.fill", stats.rate30.map { "\(Int(($0 * 100).rounded()))%" } ?? "—", .secondary)
                }
            }
            .frame(width: 150, alignment: .leading)
            Spacer(minLength: 0)
            HeatMap(color: habit.tint) { store.level(habit, on: $0) }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.06)))
    }

    private func metric(_ systemImage: String, _ value: String, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: systemImage).font(.system(size: 8.5)).foregroundStyle(color)
            Text(verbatim: value).font(.system(size: 10.5, weight: .medium).monospacedDigit())
        }
    }
}

/// Weeks as columns, days as rows, like GitHub's contributions: brighter = more done.
private struct HeatMap: View {
    let color: Color
    let level: (Date) -> Double?
    static let weeks = 16

    var body: some View {
        let calendar = Calendar.current
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? calendar.startOfDay(for: Date())
        let first = calendar.date(byAdding: .weekOfYear, value: -(Self.weeks - 1), to: thisWeek)!
        HStack(spacing: 2.5) {
            ForEach(0..<Self.weeks, id: \.self) { week in
                VStack(spacing: 2.5) {
                    ForEach(0..<7, id: \.self) { weekday in
                        cell(calendar.date(byAdding: .day, value: week * 7 + weekday, to: first)!)
                    }
                }
            }
        }
    }

    private func cell(_ day: Date) -> some View {
        let value = level(day)
        let isFuture = day > Date()
        let fill: Color = if let value, value > 0 { color.opacity(0.3 + 0.7 * value) }
            else if value != nil { Color.white.opacity(0.09) }
            else { Color.white.opacity(isFuture ? 0 : 0.035) }
        return RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(fill)
            .frame(width: 7, height: 7)
            .overlay {
                if Calendar.current.isDateInToday(day) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous).strokeBorder(.white.opacity(0.8), lineWidth: 1)
                }
            }
            .help(Text(day, format: .dateTime.weekday(.abbreviated).day().month()) + Text(value.map { " · \(Int(($0 * 100).rounded()))%" } ?? ""))
    }
}
