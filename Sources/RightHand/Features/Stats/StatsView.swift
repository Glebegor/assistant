import Charts
import SwiftUI

/// The week at a glance in the Pomodoro tab: focus time, sessions, tasks, meetings, and focus per day.
struct StatsView: View {
    let stats: WeekStats
    let close: () -> Void
    @State private var selectedDay: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(spacing: 8) {
                tile("Focus", value: WeekStats.duration(stats.focusMinutes), detail: changeText, systemImage: "timer")
                tile("Sessions", value: "\(stats.sessions)", detail: streakText, systemImage: "circle.circle")
                tile("Tasks done", value: "\(stats.tasks)", detail: L("Notion and ClickUp"), systemImage: "checkmark.circle")
                tile("Meetings", value: "\(stats.meetings)", detail: meetingDetail, systemImage: "person.2")
            }
            chart
        }
        .task { await stats.load() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(stats.isThisWeek ? "This week" : "Week").font(.headline)
                Text(verbatim: range).font(.caption).foregroundStyle(.secondary)
            }
            if stats.isLoading { ProgressView().controlSize(.mini).padding(.leading, 4) }
            Spacer()
            Button("Previous Week", systemImage: "chevron.left") { stats.move(weeks: -1) }
                .buttonStyle(.notchPill()).labelStyle(.iconOnly)
            Button("Next Week", systemImage: "chevron.right") { stats.move(weeks: 1) }
                .buttonStyle(.notchPill()).labelStyle(.iconOnly)
                .disabled(stats.isThisWeek)
            Button("Timer", systemImage: "timer", action: close)
                .buttonStyle(.notchPill()).labelStyle(.iconOnly)
                .help("Back to the timer")
        }
    }

    private var range: String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: stats.weekStart)!
        return "\(stats.weekStart.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated)))"
    }

    private var changeText: String {
        guard let change = stats.change else { return L("this week") }
        return change >= 0 ? L("+%lld%% vs last week", change) : L("%lld%% vs last week", change)
    }

    private var streakText: String {
        stats.streak > 0 ? L("%lld days in a row", stats.streak) : L("finished focus sessions")
    }

    private var meetingDetail: String {
        stats.meetingMinutes > 0 ? WeekStats.duration(stats.meetingMinutes) : (stats.hasCalendar ? L("from your calendar") : L("recordings only"))
    }

    private func tile(_ title: LocalizedStringKey, value: String, detail: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: systemImage).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
            Text(verbatim: value).font(.system(size: 19, weight: .semibold, design: .rounded)).monospacedDigit().lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(verbatim: detail).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Focus per day

    private var chart: some View {
        let days = stats.days
        let top = max(60, (days.map(\.focusMinutes).max() ?? 0) + 15)
        return Chart(days) { day in
            let name = day.day.formatted(.dateTime.weekday(.abbreviated))
            let isToday = Calendar.current.isDateInToday(day.day)
            BarMark(x: .value("Day", name), y: .value("Focus minutes", day.focusMinutes), width: .ratio(0.42))
                .cornerRadius(4)
                .foregroundStyle(Theme.neon.opacity(selectedDay == nil || selectedDay == name ? (isToday ? 1 : 0.7) : 0.3))
            if selectedDay == name {
                RuleMark(x: .value("Day", name))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        tooltip(day)
                    }
            }
        }
        .chartXSelection(value: $selectedDay)
        .chartYAxis {
            AxisMarks(position: .leading, values: .stride(by: top > 180 ? 60 : 30)) { value in
                AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                AxisValueLabel {
                    if let minutes = value.as(Int.self) {
                        Text(verbatim: Self.axisLabel(minutes)).font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel().font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .chartYScale(domain: 0...top)
        .frame(height: 120)
    }

    /// "30 min", "1 h", "1,5 h".
    private static func axisLabel(_ minutes: Int) -> String {
        if minutes == 0 { return "0" }
        if minutes < 60 { return L("%lld min", minutes) }
        let hours = Double(minutes) / 60
        return minutes % 60 == 0 ? L("%lld h", minutes / 60) : L("%@ h", hours.formatted(.number.precision(.fractionLength(1))))
    }

    private func tooltip(_ day: DayStats) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(day.day.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))).font(.caption.weight(.semibold))
            Text(verbatim: L("Focus %@ · %lld sessions", WeekStats.duration(day.focusMinutes), day.sessions))
            Text(verbatim: L("%lld tasks · %lld meetings", day.tasks, max(day.meetings, day.recordings)))
        }
        .font(.caption2)
        .foregroundStyle(.white)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.white.opacity(0.1)))
    }
}
