import Foundation

/// Which properties of a task database hold the status, due date, priority and assignee.
/// Found from the property types and names, so any task database works without setup.
struct NotionSchema: Sendable {
    enum Done: Sendable {
        /// A Status property: done means any option in its "Complete" group.
        case status(property: String, doneOptions: [String])
        /// A Select used as status: done means an option like "Done".
        case select(property: String, doneOptions: [String])
        case checkbox(property: String)
    }

    var title: String?
    var done: Done?
    var due: String?
    var priority: String?
    /// Priority option names from most to least important, as ordered in Notion.
    var priorityOptions: [String] = []
    var assignee: String?

    init(properties: [String: JSONValue]) {
        let typed = properties.map { (name: $0.key, type: $0.value["type"]?.string ?? "", value: $0.value) }
            .sorted { $0.name < $1.name }
        func first(_ type: String, preferring words: [String]) -> (name: String, type: String, value: JSONValue)? {
            let ofType = typed.filter { $0.type == type }
            return ofType.first { Self.matches($0.name, words) } ?? ofType.first
        }

        title = typed.first { $0.type == "title" }?.name

        // Priority first, so a "Priority" status or select isn't mistaken for the task's status.
        if let property = typed.first(where: { ["select", "status"].contains($0.type) && Self.matches($0.name, Self.priorityWords) }) {
            priority = property.name
            priorityOptions = Self.optionNames(property.value[property.type])
        }

        let statusCandidates = typed.filter { $0.name != priority }
        if let status = statusCandidates.first(where: { $0.type == "status" }) {
            let schema = status.value["status"]
            let groups = schema?["groups"]?.array ?? []
            let completeIDs = Set(groups.filter { $0["name"]?.string?.lowercased() == "complete" }
                .flatMap { $0["option_ids"]?.array ?? [] }.compactMap(\.string))
            let options = schema?["options"]?.array ?? []
            var doneOptions = options.filter { completeIDs.contains($0["id"]?.string ?? "") }.compactMap { $0["name"]?.string }
            if doneOptions.isEmpty { doneOptions = Self.optionNames(schema).filter { Self.matches($0, Self.doneWords) } }
            done = .status(property: status.name, doneOptions: doneOptions)
        } else if let checkbox = first("checkbox", preferring: Self.doneWords) {
            done = .checkbox(property: checkbox.name)
        } else if let select = statusCandidates.first(where: { $0.type == "select" && Self.matches($0.name, Self.statusWords) }) {
            done = .select(property: select.name, doneOptions: Self.optionNames(select.value["select"]).filter { Self.matches($0, Self.doneWords) })
        }

        due = (typed.first { $0.type == "date" && Self.matches($0.name, Self.dueWords) }
            ?? first("date", preferring: ["date", "дата", "datum"]))?.name
        assignee = first("people", preferring: Self.assigneeWords)?.name
    }

    /// Query filter that leaves out finished tasks.
    var notDoneFilter: JSONValue? {
        switch done {
        case .status(let property, let options), .select(let property, let options):
            let kind = if case .status = done { "status" } else { "select" }
            let filters: [JSONValue] = options.map { ["property": .string(property), kind: ["does_not_equal": .string($0)]] }
            return filters.isEmpty ? nil : (filters.count == 1 ? filters[0] : ["and": .array(filters)])
        case .checkbox(let property):
            return ["property": .string(property), "checkbox": ["equals": false]]
        case nil:
            return nil
        }
    }

    /// Properties that mark a page as done, or nil when this database can't be marked done.
    var doneUpdate: JSONValue? {
        switch done {
        case .status(let property, let options):
            options.first.map { [property: ["status": ["name": .string($0)]]] }
        case .select(let property, let options):
            options.first.map { [property: ["select": ["name": .string($0)]]] }
        case .checkbox(let property):
            [property: ["checkbox": true]]
        case nil:
            nil
        }
    }

    // MARK: Reading a page

    func task(from page: JSONValue, database: NotionDatabaseInfo) -> TaskItem? {
        guard let id = page["id"]?.string, let properties = page["properties"] else { return nil }
        let name = title.map { NotionClient.plainText(properties[$0]?["title"]) } ?? ""

        var due: Date?, dueHasTime = false
        if let property = self.due, let start = properties[property]?["date"]?["start"]?.string {
            dueHasTime = start.contains("T")
            due = Self.parseDate(start)
        }

        var priorityName: String?
        if let property = priority, let value = properties[property] {
            priorityName = (value["select"] ?? value["status"])?["name"]?.string
        }

        let assignees = assignee.flatMap { properties[$0]?["people"]?.array }?.compactMap { $0["id"]?.string } ?? []
        return TaskItem(id: id, title: name.isEmpty ? L("Untitled") : name, url: page["url"]?.string.flatMap(URL.init(string:)),
                        source: .notion, databaseID: database.id, databaseName: database.shortName,
                        due: due, dueHasTime: dueHasTime, priorityName: priorityName,
                        priorityLevel: priorityName.map(level(of:)) ?? .none, assigneeIDs: assignees,
                        canComplete: doneUpdate != nil)
    }

    private func level(of option: String) -> TaskItem.Priority {
        if Self.matches(option, Self.highWords) { return .high }
        if Self.matches(option, Self.mediumWords) { return .medium }
        if Self.matches(option, Self.lowWords) { return .low }
        // Unknown names: use the order in Notion (first option = most important).
        guard let index = priorityOptions.firstIndex(of: option), priorityOptions.count > 1 else { return .medium }
        return index == 0 ? .high : (index == priorityOptions.count - 1 ? .low : .medium)
    }

    // MARK: Words

    private static let priorityWords = ["priorit", "приорит", "пріорит", "важн", "urgency", "importance"]
    private static let statusWords = ["status", "статус", "stav", "state", "stage"]
    private static let doneWords = ["done", "complete", "finished", "closed", "готово", "выполнено", "виконано", "завершено", "hotovo", "dokončen", "splněn"]
    private static let dueWords = ["due", "deadline", "срок", "дедлайн", "термін", "строк", "termín", "splatnost"]
    private static let assigneeWords = ["assign", "owner", "responsible", "исполн", "відповід", "викон", "ответств", "řešitel", "odpověd", "person"]
    private static let highWords = ["high", "urgent", "critical", "asap", "p0", "p1", "высок", "висок", "срочн", "терміново", "критич", "vysok", "urgentn", "🔥", "‼"]
    private static let mediumWords = ["medium", "normal", "mid", "p2", "средн", "серед", "střed", "norm"]
    private static let lowWords = ["low", "minor", "p3", "p4", "низк", "низьк", "nízk"]

    private static func matches(_ text: String, _ words: [String]) -> Bool {
        let text = text.lowercased()
        return words.contains { text.contains($0) }
    }

    private static func optionNames(_ schema: JSONValue?) -> [String] {
        (schema?["options"]?.array ?? []).compactMap { $0["name"]?.string }
    }

    /// "2026-10-19" (a day, local time) or "2026-10-19T10:00:00.000+02:00".
    static func parseDate(_ text: String) -> Date? {
        if text.count == 10 {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: text)
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: text) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: text)
    }
}
