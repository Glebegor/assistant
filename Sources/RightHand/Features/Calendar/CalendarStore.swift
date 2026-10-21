import AppKit
import Observation

/// An event in the Calendar tab.
struct CalendarEvent: Identifiable, Hashable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color
    let location: String?
    /// Google Meet, Zoom, Teams… link to join the call.
    let joinURL: URL?
    let pageURL: URL?
    /// Other people are invited, or there's a call link.
    var isMeeting: Bool = false

    struct Color: Hashable { let red, green, blue: Double }
}

/// Today's (or another day's) events from Google Calendar — the calendars Notion Calendar shows too.
@Observable
@MainActor
final class CalendarStore {
    private(set) var day = Calendar.current.startOfDay(for: Date())
    private(set) var events: [CalendarEvent] = []
    private(set) var isLoading = false
    private(set) var lastLoad: Date?
    var errorMessage: String?

    var isConnected: Bool { GoogleAuth.isConnected }
    var hasAccess: Bool { GoogleAuth.hasCalendarAccess }

    var allDay: [CalendarEvent] { events.filter(\.isAllDay) }
    var timed: [CalendarEvent] { events.filter { !$0.isAllDay } }

    /// The next (or current) meeting today.
    var next: CalendarEvent? {
        let now = Date()
        return timed.first { $0.end > now && Calendar.current.isDate($0.start, inSameDayAs: now) }
    }

    func show(_ day: Date) {
        self.day = Calendar.current.startOfDay(for: day)
        Task { await load() }
    }

    func move(days: Int) {
        show(Calendar.current.date(byAdding: .day, value: days, to: day) ?? day)
    }

    /// Reloads when the tab is shown and the list is older than two minutes (or the day changed).
    func refreshIfStale() {
        if !Calendar.current.isDateInToday(day), lastLoad.map({ Date().timeIntervalSince($0) > 3600 }) ?? true {
            day = Calendar.current.startOfDay(for: Date())
        }
        guard lastLoad.map({ Date().timeIntervalSince($0) > 120 }) ?? true else { return }
        Task { await load() }
    }

    func allowAccess() {
        Task {
            do {
                try await GoogleAuth.signInAgain()
                await load()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func load() async {
        guard hasAccess, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            events = try await Self.events(from: day, to: Calendar.current.date(byAdding: .day, value: 1, to: day)!)
            lastLoad = Date()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Events of the calendars shown in Google Calendar between two dates.
    static func events(from start: Date, to end: Date) async throws -> [CalendarEvent] {
        let calendars = try await GoogleAPI.json("https://www.googleapis.com/calendar/v3/users/me/calendarList?minAccessRole=reader")
        var loaded: [CalendarEvent] = []
        let iso = ISO8601DateFormatter()
        for calendar in calendars["items"]?.array ?? [] where calendar["selected"]?.bool ?? false || calendar["primary"]?.bool == true {
            guard let id = calendar["id"]?.string else { continue }
            let color = color(hex: calendar["backgroundColor"]?.string)
            let url = "https://www.googleapis.com/calendar/v3/calendars/\(GoogleAPI.query(id))/events?singleEvents=true&orderBy=startTime"
                + "&maxResults=250&timeMin=\(GoogleAPI.query(iso.string(from: start)))&timeMax=\(GoogleAPI.query(iso.string(from: end)))"
            let response = try await GoogleAPI.json(url)
            loaded += (response["items"]?.array ?? []).compactMap { event($0, color: color) }
        }
        // The same meeting can be in two calendars.
        var seen = Set<String>()
        return loaded.filter { seen.insert("\($0.title)|\($0.start)").inserted }.sorted { $0.start < $1.start }
    }

    // MARK: Reading Google's events

    private static func event(_ item: JSONValue, color: CalendarEvent.Color) -> CalendarEvent? {
        guard let id = item["id"]?.string, item["status"]?.string != "cancelled" else { return nil }
        // Hide invitations you declined.
        if (item["attendees"]?.array ?? []).contains(where: { $0["self"]?.bool == true && $0["responseStatus"]?.string == "declined" }) {
            return nil
        }
        let allDay = item["start"]?["date"]?.string != nil
        guard let start = date(item["start"]), let end = date(item["end"]) else { return nil }
        let video = item["hangoutLink"]?.string
            ?? (item["conferenceData"]?["entryPoints"]?.array ?? []).first { $0["entryPointType"]?.string == "video" }?["uri"]?.string
            ?? meetingLink(in: (item["location"]?.string ?? "") + " " + (item["description"]?.string ?? ""))
        var event = CalendarEvent(id: id, title: item["summary"]?.string ?? L("(No title)"), start: start, end: end, isAllDay: allDay,
                                  color: color, location: item["location"]?.string, joinURL: video.flatMap(URL.init(string:)),
                                  pageURL: item["htmlLink"]?.string.flatMap(URL.init(string:)))
        event.isMeeting = !allDay && (video != nil || (item["attendees"]?.array?.count ?? 0) > 1)
        return event
    }

    private static func date(_ value: JSONValue?) -> Date? {
        if let time = value?["dateTime"]?.string {
            let formatter = ISO8601DateFormatter()
            return formatter.date(from: time)
        }
        if let day = value?["date"]?.string {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: day)
        }
        return nil
    }

    /// A Zoom/Teams/Meet link written in the location or description.
    private static func meetingLink(in text: String) -> String? {
        let pattern = "https://[^\\s\"<>]*(zoom\\.us|teams\\.microsoft\\.com|meet\\.google\\.com|webex\\.com)[^\\s\"<>]*"
        return text.range(of: pattern, options: .regularExpression).map { String(text[$0]) }
    }

    private static func color(hex: String?) -> CalendarEvent.Color {
        guard let hex, hex.count == 7, let value = Int(hex.dropFirst(), radix: 16) else {
            return .init(red: 0.36, green: 0.66, blue: 1)
        }
        return .init(red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255, blue: Double(value & 0xff) / 255)
    }
}
