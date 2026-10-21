import AVFoundation
import Foundation
import Observation

/// One day of the week in the statistics.
struct DayStats: Identifiable, Hashable {
    let day: Date
    var focusMinutes = 0
    var sessions = 0
    var tasks = 0
    var meetings = 0
    var meetingMinutes = 0
    var recordings = 0
    var id: Date { day }
}

/// A week of focus, tasks and meetings: from the activity log, Google Calendar and your recordings.
@Observable
@MainActor
final class WeekStats {
    private(set) var weekStart: Date
    private(set) var days: [DayStats] = []
    private(set) var previousFocusMinutes = 0
    private(set) var streak = 0
    private(set) var isLoading = false
    /// Meetings need Google Calendar; without it they're counted from recordings only.
    private(set) var hasCalendar = false

    init() {
        weekStart = Self.startOfWeek(Date())
        rebuild(meetings: [])
    }

    var focusMinutes: Int { days.reduce(0) { $0 + $1.focusMinutes } }
    var sessions: Int { days.reduce(0) { $0 + $1.sessions } }
    var tasks: Int { days.reduce(0) { $0 + $1.tasks } }
    var meetings: Int { days.reduce(0) { $0 + max($1.meetings, $1.recordings) } }
    var meetingMinutes: Int { days.reduce(0) { $0 + $1.meetingMinutes } }
    var bestDay: DayStats? { days.filter { $0.focusMinutes > 0 }.max { $0.focusMinutes < $1.focusMinutes } }
    var isThisWeek: Bool { weekStart == Self.startOfWeek(Date()) }

    /// Change against the week before, in percent (nil when there's nothing to compare).
    var change: Int? {
        guard previousFocusMinutes > 0 else { return nil }
        return Int((Double(focusMinutes - previousFocusMinutes) / Double(previousFocusMinutes) * 100).rounded())
    }

    func move(weeks: Int) {
        weekStart = Calendar.current.date(byAdding: .weekOfYear, value: weeks, to: weekStart) ?? weekStart
        Task { await load() }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        rebuild(meetings: [])
        let end = Calendar.current.date(byAdding: .day, value: 7, to: weekStart)!
        let recordings = await Self.recordings(from: weekStart, to: end)
        var meetings: [CalendarEvent] = []
        hasCalendar = GoogleAuth.hasCalendarAccess
        if hasCalendar {
            meetings = ((try? await CalendarStore.events(from: weekStart, to: end)) ?? []).filter(\.isMeeting)
        }
        rebuild(meetings: meetings, recordings: recordings)
    }

    private func rebuild(meetings: [CalendarEvent], recordings: [Date] = []) {
        let calendar = Calendar.current
        let records = ActivityLog.shared.records
        days = (0..<7).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: weekStart)!
            var stats = DayStats(day: day)
            for record in records where calendar.isDate(record.date, inSameDayAs: day) {
                switch record.kind {
                case .focus:
                    stats.sessions += 1
                    stats.focusMinutes += record.minutes ?? 0
                case .task:
                    stats.tasks += 1
                }
            }
            for meeting in meetings where calendar.isDate(meeting.start, inSameDayAs: day) {
                stats.meetings += 1
                stats.meetingMinutes += Int(meeting.end.timeIntervalSince(meeting.start) / 60)
            }
            stats.recordings = recordings.filter { calendar.isDate($0, inSameDayAs: day) }.count
            return stats
        }
        let previousStart = calendar.date(byAdding: .weekOfYear, value: -1, to: weekStart)!
        previousFocusMinutes = records.filter { $0.kind == .focus && $0.date >= previousStart && $0.date < weekStart }
            .reduce(0) { $0 + ($1.minutes ?? 0) }
        streak = Self.streak(records)
    }

    /// Days in a row (up to today) with at least one finished focus session.
    private static func streak(_ records: [ActivityLog.Record]) -> Int {
        let calendar = Calendar.current
        let focusDays = Set(records.filter { $0.kind == .focus }.map { calendar.startOfDay(for: $0.date) })
        var day = calendar.startOfDay(for: Date())
        if !focusDays.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day)! } // today isn't over yet
        var count = 0
        while focusDays.contains(day) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    /// When the screen recordings of the week were made.
    private static func recordings(from start: Date, to end: Date) async -> [Date] {
        let files = (try? FileManager.default.contentsOfDirectory(at: ScreenRecorder.folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return files.filter { $0.pathExtension == "mov" }.compactMap { url in
            (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate).flatMap { $0 >= start && $0 < end ? $0 : nil }
        }
    }

    static func startOfWeek(_ date: Date) -> Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: date)?.start ?? Calendar.current.startOfDay(for: date)
    }

    /// "2 h 05 min", "45 min".
    static func duration(_ minutes: Int) -> String {
        minutes >= 60 ? L("%lld h %lld min", minutes / 60, minutes % 60) : L("%lld min", minutes)
    }
}
