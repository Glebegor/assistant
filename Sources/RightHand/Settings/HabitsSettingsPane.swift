import SwiftUI

/// Settings → Habits: add, change, reorder and remove habits, and when to be reminded.
struct HabitsSettingsPane: View {
    private var store: HabitStore { .shared }
    @State private var editing: Habit?

    var body: some View {
        Form {
            Section {
                if store.habits.isEmpty {
                    Text("No habits yet. Add one: something to do every day, a number to reach, a few times a week, or a bad habit to quit.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                List {
                    ForEach(store.habits) { habit in
                        HStack(spacing: 10) {
                            Text(verbatim: habit.emoji).font(.title3)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: habit.name)
                                Text(verbatim: subtitle(habit)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Edit") { editing = habit }
                        }
                        .padding(.vertical, 2)
                    }
                    .onMove { store.move(from: $0, to: $1) }
                }
                .frame(minHeight: CGFloat(max(1, store.habits.count)) * 44)
                .scrollContentBackground(.hidden)
                Button("Add Habit", systemImage: "plus") { editing = Habit(name: "") }
            } header: {
                Text("Habits")
            } footer: {
                SettingsFooter("They show at the top of the Tasks tab. Click a habit to mark it; right-click a counted one to take one back. Drag to reorder.")
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { habit in
            HabitEditor(habit: habit, isNew: !store.habits.contains { $0.id == habit.id }) { editing = nil }
        }
    }

    private func subtitle(_ habit: Habit) -> String {
        var parts = [habit.scheduleText]
        if habit.kind == .count { parts.append(L("goal %lld", habit.dailyTarget)) }
        if habit.kind == .avoid { parts.append(L("quitting")) }
        if let time = habit.reminderText { parts.append("⏰ \(time)") }
        return parts.joined(separator: " · ")
    }
}

private struct HabitEditor: View {
    @State var habit: Habit
    let isNew: Bool
    let done: () -> Void
    @State private var scheduleKind = 0
    @State private var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var timesPerWeek = 3
    @State private var reminds = false
    @State private var reminder = 9 * 60
    @State private var confirmsDelete = false
    private var store: HabitStore { .shared }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack {
                        TextField("Emoji", text: $habit.emoji).frame(width: 60)
                        TextField("Name", text: $habit.name, prompt: Text("Drink water, read, no sugar…"))
                    }
                    Picker("Kind", selection: $habit.kind) {
                        Text("Do it (yes / no)").tag(Habit.Kind.check)
                        Text("Reach a number").tag(Habit.Kind.count)
                        Text("Quit a bad habit").tag(Habit.Kind.avoid)
                    }
                    if habit.kind == .count {
                        Stepper(value: $habit.target, in: 1...1000) { Text(L("Goal: %lld a day", habit.target)) }
                    }
                }
                Section("When") {
                    Picker("Schedule", selection: $scheduleKind) {
                        Text("Every day").tag(0)
                        Text("Some weekdays").tag(1)
                        if habit.kind != .avoid { Text("Times a week").tag(2) }
                    }
                    .pickerStyle(.segmented)
                    if scheduleKind == 1 {
                        HStack(spacing: 4) {
                            ForEach(weekdayOrder, id: \.self) { day in
                                let on = weekdays.contains(day)
                                Button(Calendar.current.veryShortWeekdaySymbols[day - 1]) {
                                    if on { weekdays.remove(day) } else { weekdays.insert(day) }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(on ? Theme.neon : .gray.opacity(0.4))
                            }
                        }
                    }
                    if scheduleKind == 2 {
                        Stepper(value: $timesPerWeek, in: 1...7) { Text(L("%lld× a week", timesPerWeek)) }
                    }
                    Toggle("Remind me", isOn: $reminds)
                    if reminds {
                        DatePicker("At", selection: Binding(
                            get: { Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(reminder * 60)) },
                            set: { reminder = Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0) }
                        ), displayedComponents: .hourAndMinute)
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                if !isNew {
                    Button("Delete", role: .destructive) { confirmsDelete = true }
                }
                Spacer()
                Button("Cancel", action: done).keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(habit.name.trimmingCharacters(in: .whitespaces).isEmpty || (scheduleKind == 1 && weekdays.isEmpty))
            }
            .padding(16)
        }
        .frame(width: 460, height: 470)
        .onAppear(perform: load)
        .onChange(of: habit.kind) { _, kind in if kind == .avoid, scheduleKind == 2 { scheduleKind = 0 } }
        .confirmationDialog(L("Delete “%@” and its history?", habit.name), isPresented: $confirmsDelete) {
            Button("Delete", role: .destructive) {
                store.delete(habit.id)
                done()
            }
        }
    }

    private var weekdayOrder: [Int] { (0..<7).map { (Calendar.current.firstWeekday - 1 + $0) % 7 + 1 } }

    private func load() {
        switch habit.schedule {
        case .daily: scheduleKind = 0
        case .weekdays(let days): scheduleKind = 1; weekdays = days
        case .timesPerWeek(let times): scheduleKind = 2; timesPerWeek = times
        }
        reminds = habit.reminderMinutes != nil
        reminder = habit.reminderMinutes ?? 9 * 60
    }

    private func save() {
        habit.name = habit.name.trimmingCharacters(in: .whitespaces)
        if habit.emoji.trimmingCharacters(in: .whitespaces).isEmpty { habit.emoji = habit.kind == .avoid ? "🚫" : "✅" }
        habit.emoji = String(habit.emoji.trimmingCharacters(in: .whitespaces).prefix(2))
        habit.schedule = switch scheduleKind {
        case 1: .weekdays(weekdays)
        case 2: .timesPerWeek(timesPerWeek)
        default: .daily
        }
        habit.reminderMinutes = reminds ? reminder : nil
        store.save(habit)
        done()
    }
}
