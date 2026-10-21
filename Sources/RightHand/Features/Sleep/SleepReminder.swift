import AppKit
import Observation
import SwiftUI

/// Sleep reminder settings (Settings → Sleep).
enum SleepSettings {
    enum Key {
        static let enabled = "sleep.enabled"
        static let bedtime = "sleep.bedtime" // minutes after midnight
        static let windDown = "sleep.windDown" // minutes before bedtime
        static let weekendBedtime = "sleep.weekendBedtime" // minutes after midnight, Friday and Saturday nights
        static let usesWeekendBedtime = "sleep.usesWeekendBedtime"
    }

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: Key.enabled) as? Bool ?? true }
    static var bedtime: Int { UserDefaults.standard.object(forKey: Key.bedtime) as? Int ?? 23 * 60 }
    static var windDown: Int { UserDefaults.standard.object(forKey: Key.windDown) as? Int ?? 30 }
    static var usesWeekendBedtime: Bool { UserDefaults.standard.bool(forKey: Key.usesWeekendBedtime) }
    static var weekendBedtime: Int { UserDefaults.standard.object(forKey: Key.weekendBedtime) as? Int ?? 24 * 60 }

    /// "23:00".
    static func time(_ minutes: Int) -> String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }
}

/// Reminds you to go to bed: a gentle note before bedtime, then a card in the notch at bedtime that
/// comes back every 15 minutes until you say good night.
@Observable
@MainActor
final class SleepReminder {
    enum Phase: Equatable {
        case none
        /// "Bedtime in 30 minutes".
        case windDown(minutesLeft: Int)
        /// It's bedtime (or later).
        case bedtime(minutesLate: Int)
    }

    private(set) var phase: Phase = .none
    /// The screen to show the card on (the one with the mouse).
    private(set) var displayID: CGDirectDisplayID?

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var snoozedUntil: Date?
    /// Nights already ended with "Good night" (by the date the night started).
    @ObservationIgnored private var doneNight: Date?
    @ObservationIgnored private var windDownShownFor: Date?
    @ObservationIgnored var isSuppressed: () -> Bool = { false }

    static let snoozeMinutes = 15

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.tick() }
    }

    var isVisible: Bool { phase != .none }

    func goodNight() {
        doneNight = currentNight()?.start
        phase = .none
    }

    func snooze() {
        snoozedUntil = Date().addingTimeInterval(TimeInterval(Self.snoozeMinutes * 60))
        phase = .none
    }

    func dismissWindDown() {
        windDownShownFor = currentNight()?.start
        phase = .none
    }

    // MARK: Timing

    /// Tonight's bedtime window: from wind-down until 5 a.m. (bedtime may be after midnight).
    private func currentNight(now: Date = Date()) -> (start: Date, bedtime: Date, end: Date)? {
        let calendar = Calendar.current
        // The "evening" this moment belongs to: before 5 a.m. it's still last night.
        let evening = calendar.startOfDay(for: now.addingTimeInterval(-5 * 3600))
        let weekday = calendar.component(.weekday, from: evening) // 6 = Friday, 7 = Saturday
        let minutes = SleepSettings.usesWeekendBedtime && (weekday == 6 || weekday == 7) ? SleepSettings.weekendBedtime : SleepSettings.bedtime
        let bedtime = evening.addingTimeInterval(TimeInterval(minutes * 60))
        let start = bedtime.addingTimeInterval(-TimeInterval(SleepSettings.windDown * 60))
        let end = evening.addingTimeInterval(29 * 3600) // 5 a.m. the next morning
        return (start, bedtime, end)
    }

    private func tick() {
        guard SleepSettings.isEnabled, let night = currentNight() else { return clear() }
        let now = Date()
        guard now >= night.start, now < night.end, doneNight != night.start else { return clear() }
        if let snoozedUntil, now < snoozedUntil { return clear() }

        let next: Phase
        if now < night.bedtime {
            guard windDownShownFor != night.start else { return clear() }
            next = .windDown(minutesLeft: max(1, Int(night.bedtime.timeIntervalSince(now) / 60)))
        } else {
            next = .bedtime(minutesLate: Int(now.timeIntervalSince(night.bedtime) / 60))
        }
        let appearing = phase == .none
        if appearing {
            displayID = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }?.displayID
            notify(next)
            // The early note only shows for a moment; the bedtime card stays until you answer it.
            if case .windDown = next {
                let night = night.start
                DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
                    guard let self, case .windDown = self.phase else { return }
                    self.windDownShownFor = night
                    self.phase = .none
                }
            }
        }
        // While recording a meeting the card would cover it: only the notification is shown.
        phase = isSuppressed() ? .none : next
        if isSuppressed(), case .windDown = next { windDownShownFor = night.start }
        if isSuppressed(), case .bedtime = next { snoozedUntil = now.addingTimeInterval(TimeInterval(Self.snoozeMinutes * 60)) }
    }

    private func clear() {
        if phase != .none { phase = .none }
    }

    private func notify(_ phase: Phase) {
        switch phase {
        case .windDown(let left):
            Notifier.shared.notify(title: L("Bedtime in %lld min", left), body: L("Time to wind down: finish what you're doing."), playsSound: false)
        case .bedtime:
            Notifier.shared.notify(title: L("Time to sleep"), body: L("Close the laptop and get some rest. Good night!"))
        case .none:
            break
        }
    }
}

/// The sleep card hanging from the closed notch.
struct SleepCard: View {
    let reminder: SleepReminder
    let topInset: CGFloat

    static func size(for phase: SleepReminder.Phase, collapsed: CGSize) -> CGSize {
        switch phase {
        case .none: collapsed
        case .windDown: CGSize(width: max(collapsed.width + 220, 420), height: collapsed.height + 54)
        case .bedtime: CGSize(width: max(collapsed.width + 300, 480), height: collapsed.height + 74)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: topInset)
            HStack(spacing: 12) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color(red: 0.62, green: 0.6, blue: 1))
                    .shadow(color: Color(red: 0.55, green: 0.5, blue: 1).opacity(0.6), radius: 6)
                VStack(alignment: .leading, spacing: 2) {
                    switch reminder.phase {
                    case .windDown(let left):
                        Text(L("Bedtime in %lld min", left)).font(.callout.weight(.semibold))
                        Text("Time to wind down.").font(.caption).foregroundStyle(.secondary)
                    case .bedtime(let late):
                        Text("Time to sleep").font(.callout.weight(.semibold))
                        Text(late > 1 ? L("%lld min past your bedtime", late) : L("Close the laptop and get some rest."))
                            .font(.caption).foregroundStyle(.secondary)
                    case .none:
                        EmptyView()
                    }
                }
                Spacer(minLength: 8)
                if case .bedtime = reminder.phase {
                    Button(L("%lld more min", SleepReminder.snoozeMinutes)) { reminder.snooze() }
                        .buttonStyle(.notchPill())
                    Button("Good night") { reminder.goodNight() }
                        .buttonStyle(.notchPill(prominent: true, tint: .white))
                } else {
                    Button("OK") { reminder.dismissWindDown() }.buttonStyle(.notchPill())
                }
            }
            .padding(.horizontal, 18)
            .frame(maxHeight: .infinity)
        }
        .foregroundStyle(.white)
    }
}
