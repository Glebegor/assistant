import Foundation

/// Reminds you of a habit at its time, unless it's already done today. Checked every 30 seconds,
/// so a reminder missed while the Mac slept comes when it wakes (the same day).
@MainActor
final class HabitReminders {
    private let store: HabitStore
    private var timer: Timer?
    /// "2026-10-24 <habit id>" of reminders already shown.
    private var shown: Set<String> = []

    init(store: HabitStore = .shared) {
        self.store = store
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func check() {
        let now = Date()
        let calendar = Calendar.current
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let today = HabitStore.key(now)
        shown = shown.filter { $0.hasPrefix(today) }
        for habit in store.today {
            // A bad habit is reminded of while you're holding on, the others until they're done.
            let pending = habit.kind == .avoid ? store.value(habit, on: now) == 0 : !store.isDone(habit, on: now)
            guard let time = habit.reminderMinutes, minutes >= time, pending else { continue }
            let id = "\(today) \(habit.id)"
            guard shown.insert(id).inserted else { continue }
            // Only for the next hour after its time (not at midnight for a morning habit you skipped).
            guard minutes - time < 60 else { continue }
            let body: String = switch habit.kind {
            case .avoid: L("Still holding on? Keep the streak going.")
            case .count: L("%lld of %lld so far today.", store.value(habit, on: now), habit.dailyTarget)
            case .check: L("Not done yet today.")
            }
            Notifier.shared.notify(title: "\(habit.emoji) \(habit.name)", body: body)
        }
    }
}
