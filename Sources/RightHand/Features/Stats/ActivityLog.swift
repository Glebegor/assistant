import Foundation
import Observation

/// What you did, for the weekly statistics: finished focus sessions and tasks ticked off in the
/// notch. Kept in ~/Library/Application Support/RightHand/activity.json (meetings come from the
/// calendar and the recordings folder, so they aren't stored here).
@Observable
@MainActor
final class ActivityLog {
    static let shared = ActivityLog()

    struct Record: Codable, Hashable {
        enum Kind: String, Codable { case focus, task }
        var kind: Kind
        var date: Date
        /// Focus sessions: how long they were.
        var minutes: Int?
        /// Tasks: "notion" or "clickup".
        var source: String?
    }

    private(set) var records: [Record] = []
    private static var file: URL { AppPaths.support.appending(path: "activity.json") }

    init() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        records = (try? Data(contentsOf: Self.file)).flatMap { try? decoder.decode([Record].self, from: $0) } ?? []
    }

    func focusFinished(minutes: Int) {
        append(Record(kind: .focus, date: Date(), minutes: minutes))
    }

    func taskDone(source: String) {
        append(Record(kind: .task, date: Date(), source: source))
    }

    private func append(_ record: Record) {
        records.append(record)
        // A year is plenty for weekly statistics.
        let yearAgo = Date().addingTimeInterval(-366 * 86400)
        records.removeAll { $0.date < yearAgo }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(records).write(to: Self.file, options: .atomic)
    }
}
