import AppKit
import SwiftUI

/// Calendar tab: the day as a timeline, all-day events above it and the next meeting with a Join button.
struct CalendarView: View {
    let store: CalendarStore
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if !store.isConnected {
                message("Connect Google to see your calendar", detail: "Settings → Services → Google.", button: "Open Settings", action: openSettings)
            } else if !store.hasAccess {
                message("Allow RightHand to read your calendar", detail: "Google asks once in the browser. In Google Cloud, enable the “Google Calendar API” for your project.",
                        button: "Allow Calendar", action: store.allowAccess)
            } else {
                if let next = store.next, Calendar.current.isDateInToday(store.day) { NextMeeting(event: next) }
                if !store.allDay.isEmpty { allDayRow }
                Timeline(store: store)
            }
            if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange).lineLimit(2)
            }
        }
        .onAppear { store.refreshIfStale() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(store.day.formatted(.dateTime.weekday(.wide))).font(.headline)
                Text(store.day.formatted(.dateTime.day().month(.wide))).font(.caption).foregroundStyle(.secondary)
            }
            if store.isLoading { ProgressView().controlSize(.mini).padding(.leading, 4) }
            Spacer()
            if !Calendar.current.isDateInToday(store.day) {
                Button("Today") { store.show(Date()) }.buttonStyle(.notchPill())
            }
            Button("Previous Day", systemImage: "chevron.left") { store.move(days: -1) }
                .buttonStyle(.notchPill()).labelStyle(.iconOnly)
            Button("Next Day", systemImage: "chevron.right") { store.move(days: 1) }
                .buttonStyle(.notchPill()).labelStyle(.iconOnly)
        }
    }

    private var allDayRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(store.allDay) { event in
                    Text(verbatim: event.title)
                        .font(.caption.weight(.medium)).lineLimit(1)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(event.swiftUIColor.opacity(0.28), in: Capsule())
                        .onTapGesture { if let url = event.pageURL { NSWorkspace.shared.open(url) } }
                }
            }
        }
        .scrollIndicators(.never)
    }

    private func message(_ title: LocalizedStringKey, detail: LocalizedStringKey, button: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar").font(.system(size: 26)).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(button, action: action).buttonStyle(.notchPill(prominent: true, tint: .white))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// "Next: Standup · in 12 min" with Join.
private struct NextMeeting: View {
    let event: CalendarEvent

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            let now = Date()
            HStack(spacing: 10) {
                Circle().fill(Theme.neon).frame(width: 7, height: 7).neonGlow(radius: 4)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: event.title).font(.callout.weight(.semibold)).lineLimit(1)
                    Text(event.start <= now ? L("Now · until %@", event.end.formatted(date: .omitted, time: .shortened))
                                            : L("In %@ · %@", Self.until(event.start, from: now), event.start.formatted(date: .omitted, time: .shortened)))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let join = event.joinURL {
                    Button { NSWorkspace.shared.open(join) } label: { Label("Join", systemImage: "video.fill") }
                        .buttonStyle(.notchPill(prominent: true, tint: .white))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Theme.neonSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.neon.opacity(0.35)))
        }
    }

    static func until(_ date: Date, from now: Date) -> String {
        let minutes = max(1, Int(date.timeIntervalSince(now) / 60))
        return minutes < 60 ? L("%lld min", minutes) : L("%lld h %lld min", minutes / 60, minutes % 60)
    }
}

/// The hours of the day with the events placed on them; overlapping events share the width.
private struct Timeline: View {
    let store: CalendarStore
    private let hourHeight: CGFloat = 44
    private let gutter: CGFloat = 40

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    hours
                    GeometryReader { geometry in
                        let width = geometry.size.width - gutter - 4
                        ForEach(layout(store.timed)) { placed in
                            EventBlock(event: placed.event)
                                .frame(width: max(20, width / CGFloat(placed.columns) - 3),
                                       height: max(18, height(of: placed.event)))
                                .offset(x: gutter + width / CGFloat(placed.columns) * CGFloat(placed.column), y: y(of: placed.event.start))
                        }
                        if Calendar.current.isDateInToday(store.day) { nowLine(width: geometry.size.width) }
                    }
                }
                .frame(height: hourHeight * 24)
            }
            .scrollIndicators(.never)
            .onAppear { scroll(proxy) }
            .onChange(of: store.day) { _, _ in scroll(proxy) }
        }
    }

    private var hours: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { hour in
                HStack(alignment: .top, spacing: 6) {
                    Text(verbatim: String(format: "%02d:00", hour))
                        .font(.system(size: 9.5).monospacedDigit()).foregroundStyle(.tertiary)
                        .frame(width: gutter - 6, alignment: .trailing)
                        .offset(y: -5)
                    Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                }
                .frame(height: hourHeight, alignment: .top)
                .id(hour)
            }
        }
    }

    private func nowLine(width: CGFloat) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            HStack(spacing: 0) {
                Circle().fill(Theme.neon).frame(width: 7, height: 7)
                Rectangle().fill(Theme.neon).frame(height: 1.5)
            }
            .neonGlow(radius: 4)
            .frame(width: width - gutter + 4)
            .offset(x: gutter - 4, y: y(of: Date()) - 3.5)
        }
    }

    private func y(of date: Date) -> CGFloat {
        CGFloat(max(0, date.timeIntervalSince(store.day)) / 3600) * hourHeight
    }

    private func height(of event: CalendarEvent) -> CGFloat {
        let end = min(event.end, store.day.addingTimeInterval(24 * 3600))
        return CGFloat(end.timeIntervalSince(max(event.start, store.day)) / 3600) * hourHeight - 2
    }

    /// Starts an hour before now (or the first event), so the interesting part is in view.
    private func scroll(_ proxy: ScrollViewProxy) {
        let anchor = Calendar.current.isDateInToday(store.day) ? Date() : (store.timed.first?.start ?? store.day.addingTimeInterval(8 * 3600))
        let hour = max(0, Calendar.current.component(.hour, from: anchor) - 1)
        DispatchQueue.main.async { proxy.scrollTo(min(hour, 18), anchor: .top) }
    }

    struct Placed: Identifiable {
        let event: CalendarEvent
        let column: Int
        let columns: Int
        var id: String { event.id }
    }

    /// Side by side for events that overlap.
    private func layout(_ events: [CalendarEvent]) -> [Placed] {
        var result: [Placed] = []
        var group: [CalendarEvent] = []
        var groupEnd = Date.distantPast
        func flush() {
            var columnEnds: [Date] = []
            var columnOf: [String: Int] = [:]
            for event in group {
                if let free = columnEnds.firstIndex(where: { $0 <= event.start }) {
                    columnEnds[free] = event.end; columnOf[event.id] = free
                } else {
                    columnEnds.append(event.end); columnOf[event.id] = columnEnds.count - 1
                }
            }
            result += group.map { Placed(event: $0, column: columnOf[$0.id] ?? 0, columns: max(1, columnEnds.count)) }
            group = []
        }
        for event in events.sorted(by: { $0.start < $1.start }) {
            if event.start >= groupEnd { flush(); groupEnd = event.end } else { groupEnd = max(groupEnd, event.end) }
            group.append(event)
        }
        flush()
        return result
    }
}

private struct EventBlock: View {
    let event: CalendarEvent
    @State private var isHovered = false

    var body: some View {
        let color = event.swiftUIColor
        let past = event.end < Date()
        HStack(alignment: .top, spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: event.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(2)
                Text(verbatim: "\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            if event.joinURL != nil, isHovered {
                Image(systemName: "video.fill").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3).padding(.trailing, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color.opacity(isHovered ? 0.34 : 0.22), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .opacity(past ? 0.55 : 1)
        .clipped()
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { if let url = event.joinURL ?? event.pageURL { NSWorkspace.shared.open(url) } }
        .help(event.joinURL != nil ? "Join the call" : "Open in Google Calendar")
    }
}

extension CalendarEvent {
    var swiftUIColor: SwiftUI.Color { SwiftUI.Color(red: color.red, green: color.green, blue: color.blue) }
}
