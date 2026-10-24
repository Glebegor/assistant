import Foundation
import Observation

/// Something you want to do (or stop doing) regularly.
struct Habit: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        /// Done or not.
        case check
        /// A number to reach: 8 glasses of water, 20 push-ups.
        case count
        /// A bad habit: every day without a slip counts.
        case avoid
        var id: Self { self }
    }

    enum Schedule: Codable, Hashable {
        case daily
        /// Calendar weekdays, 1 = Sunday … 7 = Saturday.
        case weekdays(Set<Int>)
        /// Any days, this many times a week.
        case timesPerWeek(Int)
    }

    var id = UUID()
    var name: String
    var emoji: String = "✅"
    var kind: Kind = .check
    /// For `count`: the number to reach each day.
    var target: Int = 1
    var schedule: Schedule = .daily
    /// Minutes after midnight for the reminder; nil = no reminder.
    var reminderMinutes: Int?
    var created = Date()

    var dailyTarget: Int { kind == .count ? max(1, target) : 1 }
}

/// Your habits and what you did each day, in ~/Library/Application Support/RightHand/habits.json.
@Observable
@MainActor
final class HabitStore {
    static let shared = HabitStore()

    private struct File: Codable {
        var habits: [Habit]
        /// "2026-10-24" → habit → value (times done; for `avoid`, 1 means you slipped that day).
        var log: [String: [UUID: Int]]
    }

    private(set) var habits: [Habit] = []
    private(set) var log: [String: [UUID: Int]] = [:]
    private static var url: URL { AppPaths.support.appending(path: "habits.json") }

    init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: Self.url), let file = try? decoder.decode(File.self, from: data) {
            habits = file.habits
            log = file.log
        }
    }

    // MARK: Editing

    func save(_ habit: Habit) {
        if let index = habits.firstIndex(where: { $0.id == habit.id }) { habits[index] = habit } else { habits.append(habit) }
        write()
    }

    func delete(_ id: UUID) {
        habits.removeAll { $0.id == id }
        for day in log.keys { log[day]?[id] = nil }
        write()
    }

    // MARK: Marking

    func value(_ habit: Habit, on day: Date = Date()) -> Int { log[Self.key(day)]?[habit.id] ?? 0 }

    /// Check: done/undone. Count: one more (back to 0 after the target). Avoid: slipped/not.
    func tap(_ habit: Habit, on day: Date = Date()) {
        let current = value(habit, on: day)
        switch habit.kind {
        case .check, .avoid: set(habit, current > 0 ? 0 : 1, on: day)
        case .count: set(habit, current >= habit.dailyTarget ? 0 : current + 1, on: day)
        }
    }

    func decrement(_ habit: Habit, on day: Date = Date()) {
        set(habit, max(0, value(habit, on: day) - 1), on: day)
    }

    func set(_ habit: Habit, _ value: Int, on day: Date = Date()) {
        let key = Self.key(day)
        var entries = log[key] ?? [:]
        entries[habit.id] = value > 0 ? value : nil
        log[key] = entries.isEmpty ? nil : entries
        write()
    }

    // MARK: Reading

    /// Whether the habit is expected on that day (times-a-week habits can be done any day).
    func isDue(_ habit: Habit, on day: Date) -> Bool {
        guard Calendar.current.startOfDay(for: day) >= Calendar.current.startOfDay(for: habit.created) else { return false }
        if case .weekdays(let days) = habit.schedule { return days.contains(Calendar.current.component(.weekday, from: day)) }
        return true
    }

    /// Done that day (for `avoid`: no slip).
    func isDone(_ habit: Habit, on day: Date) -> Bool {
        habit.kind == .avoid ? value(habit, on: day) == 0 : value(habit, on: day) >= habit.dailyTarget
    }

    /// Today's habits: due ones, plus times-a-week ones still short of their goal (or done today).
    var today: [Habit] {
        let now = Date()
        return habits.filter { habit in
            guard isDue(habit, on: now) else { return false }
            if case .timesPerWeek(let times) = habit.schedule {
                return doneDays(habit, inWeekOf: now) < times || value(habit, on: now) > 0
            }
            return true
        }
    }

    func doneDays(_ habit: Habit, inWeekOf day: Date) -> Int {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: day) else { return 0 }
        return days(from: week.start, to: min(week.end.addingTimeInterval(-1), Date())).filter { value(habit, on: $0) >= habit.dailyTarget }.count
    }

    // MARK: Analysis

    struct Stats {
        var current: Int
        var best: Int
        /// "days" or "weeks".
        var unit: Habit.StreakUnit
        /// Share of due days (or weeks) done in the period, 0…1; nil when nothing was due yet.
        var rate7: Double?
        var rate30: Double?
        var total: Int
    }

    func stats(_ habit: Habit) -> Stats {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        if case .timesPerWeek(let times) = habit.schedule {
            // Streaks of weeks that reached the goal; this week counts once it's reached.
            var weeks: [Bool] = []
            var start = calendar.dateInterval(of: .weekOfYear, for: habit.created)?.start ?? habit.created
            while start <= today {
                weeks.append(doneDays(habit, inWeekOf: start) >= times)
                start = calendar.date(byAdding: .weekOfYear, value: 1, to: start)!
            }
            let finished = weeks.last == true ? weeks : Array(weeks.dropLast())
            return Stats(current: finished.reversed().prefix { $0 }.count, best: Self.longestRun(weeks), unit: .weeks,
                         rate7: rate(habit, days: 7, perWeek: times), rate30: rate(habit, days: 30, perWeek: times),
                         total: totalDone(habit))
        }
        let due = days(from: habit.created, to: today).filter { isDue(habit, on: $0) }
        let results = due.map { isDone(habit, on: $0) }
        // Today isn't over: it doesn't break the streak yet.
        let counted = results.last == false && due.last.map(calendar.isDateInToday) == true ? Array(results.dropLast()) : results
        return Stats(current: counted.reversed().prefix { $0 }.count, best: Self.longestRun(results), unit: .days,
                     rate7: rate(habit, days: 7), rate30: rate(habit, days: 30), total: totalDone(habit))
    }

    /// Level 0…1 of each day, for the heat map (nil: not due or before the habit existed).
    func level(_ habit: Habit, on day: Date) -> Double? {
        guard day <= Date(), isDue(habit, on: day) else { return nil }
        switch habit.kind {
        case .avoid: return Calendar.current.isDateInToday(day) && value(habit, on: day) == 0 ? nil : (isDone(habit, on: day) ? 1 : 0)
        case .check: return value(habit, on: day) > 0 ? 1 : 0
        case .count: return min(1, Double(value(habit, on: day)) / Double(habit.dailyTarget))
        }
    }

    /// For every habit: how much of the due days were done, per day (for the overview heat map).
    func overallLevel(on day: Date) -> Double? {
        let levels = habits.compactMap { level($0, on: day) }
        return levels.isEmpty ? nil : levels.reduce(0, +) / Double(levels.count)
    }

    private func rate(_ habit: Habit, days count: Int, perWeek: Int? = nil) -> Double? {
        let today = Calendar.current.startOfDay(for: Date())
        let start = max(Calendar.current.startOfDay(for: habit.created), Calendar.current.date(byAdding: .day, value: -(count - 1), to: today)!)
        let range = days(from: start, to: today)
        if let perWeek {
            let done = range.filter { value(habit, on: $0) >= habit.dailyTarget }.count
            let expected = Double(perWeek) * Double(range.count) / 7
            return expected > 0 ? min(1, Double(done) / expected) : nil
        }
        // Today counts only once done, so the morning doesn't look like a failure.
        let due = range.filter { isDue(habit, on: $0) && (!Calendar.current.isDateInToday($0) || isDone(habit, on: $0)) }
        guard !due.isEmpty else { return nil }
        return Double(due.filter { isDone(habit, on: $0) }.count) / Double(due.count)
    }

    private func totalDone(_ habit: Habit) -> Int {
        days(from: habit.created, to: Date()).filter { isDue(habit, on: $0) && isDone(habit, on: $0) }.count
    }

    func days(from start: Date, to end: Date) -> [Date] {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: start)
        var result: [Date] = []
        while day <= end {
            result.append(day)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return result
    }

    private static func longestRun(_ values: [Bool]) -> Int {
        var best = 0, run = 0
        for value in values {
            run = value ? run + 1 : 0
            best = max(best, run)
        }
        return best
    }

    static func key(_ day: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private func write() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(File(habits: habits, log: log)).write(to: Self.url, options: .atomic)
    }
}

extension Habit {
    enum StreakUnit { case days, weeks }

    /// "Every day", "Mon, Wed, Fri", "3× a week".
    var scheduleText: String {
        switch schedule {
        case .daily: return L("Every day")
        case .weekdays(let days):
            let symbols = Calendar.current.shortWeekdaySymbols
            let order = (0..<7).map { (Calendar.current.firstWeekday - 1 + $0) % 7 + 1 }
            return order.filter(days.contains).map { symbols[$0 - 1] }.joined(separator: ", ")
        case .timesPerWeek(let times): return L("%lld× a week", times)
        }
    }

    var reminderText: String? {
        reminderMinutes.map { String(format: "%02d:%02d", $0 / 60, $0 % 60) }
    }
}
