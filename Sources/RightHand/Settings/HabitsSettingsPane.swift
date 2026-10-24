import SwiftUI

/// Settings → Habits: add, change, reorder and remove habits, and when to be reminded.
struct HabitsSettingsPane: View {
    private var store: HabitStore { .shared }
    @State private var editing: Habit?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if store.habits.isEmpty {
                    empty
                } else {
                    VStack(spacing: 6) {
                        ForEach(store.habits) { habit in
                            HabitSettingsRow(habit: habit, stats: store.stats(habit)) { editing = habit }
                        }
                    }
                    Button("Add Habit", systemImage: "plus") { editing = Habit(name: "") }
                        .buttonStyle(NeonButtonStyle())
                }
                Text("Habits show at the top of the Tasks tab. Click one to mark it; right-click a counted habit to take one back.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
        .sheet(item: $editing) { habit in
            HabitEditor(habit: habit, isNew: !store.habits.contains { $0.id == habit.id }) { editing = nil }
        }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            HStack(spacing: -6) {
                ForEach(["💧", "📚", "🏃", "🚭"], id: \.self) { emoji in
                    HabitRing(emoji: emoji, progress: 0.7, tint: emoji == "🚭" ? Habit(name: "", kind: .avoid).tint : Theme.neon, size: 40, lineWidth: 3)
                        .background(Circle().fill(Color(red: 0.06, green: 0.07, blue: 0.09)))
                }
            }
            Text("No habits yet").font(.system(size: 17, weight: .semibold))
            Text("Something to do every day, a number to reach, a few times a week, or a bad habit to quit.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
            Button("Add Habit", systemImage: "plus") { editing = Habit(name: "") }
                .buttonStyle(NeonButtonStyle())
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .themeCard()
    }
}

private struct HabitSettingsRow: View {
    let habit: Habit
    let stats: HabitStore.Stats
    let edit: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: edit) {
            HStack(spacing: 12) {
                HabitRing(emoji: habit.emoji, progress: stats.rate30 ?? 0, tint: habit.tint, size: 36, lineWidth: 3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: habit.name).font(.system(size: 13.5, weight: .semibold))
                    HStack(spacing: 6) {
                        chip(habit.scheduleText)
                        if habit.kind == .count { chip(L("goal %lld", habit.dailyTarget)) }
                        if habit.kind == .avoid { chip(L("quitting")) }
                        if let time = habit.reminderText { chip("⏰ \(time)") }
                    }
                }
                Spacer()
                if stats.current > 0 {
                    Label("\(stats.current)", systemImage: "flame.fill")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.orange)
                }
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color.white.opacity(isHovered ? 0.06 : 0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(isHovered ? Theme.neon.opacity(0.35) : Theme.cardStroke))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }

    private func chip(_ text: String) -> some View {
        Text(verbatim: text).font(.system(size: 10.5)).foregroundStyle(.secondary)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Color.white.opacity(0.06), in: Capsule())
    }
}

/// Add or change one habit.
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
    @FocusState private var nameFocused: Bool
    private var store: HabitStore { .shared }

    private static let emojis = ["✅", "💧", "📚", "🏃", "🧘", "💪", "🥗", "😴", "✍️", "🎯", "🧠", "🦷",
                                 "💊", "🚶", "🎸", "🌱", "🚭", "🍬", "📵", "🍺", "☕️", "🍔", "🎮", "💸"]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Name with the chosen emoji
            HStack(spacing: 12) {
                HabitRing(emoji: habit.emoji, progress: 1, tint: habit.tint, size: 46, lineWidth: 3)
                TextField("Name", text: $habit.name, prompt: Text("Drink water, read, no sugar…"))
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .semibold))
                    .focused($nameFocused)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(30), spacing: 4), count: 12), spacing: 4) {
                ForEach(Self.emojis, id: \.self) { emoji in
                    Button { habit.emoji = emoji } label: {
                        Text(verbatim: emoji).font(.system(size: 16))
                            .frame(width: 30, height: 30)
                            .background(habit.emoji == emoji ? Theme.neonSoft : Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 7))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(habit.emoji == emoji ? Theme.neon.opacity(0.5) : .clear))
                    }
                    .buttonStyle(.plain)
                }
            }

            section("Kind") {
                HStack(spacing: 8) {
                    kindCard(.check, "checkmark.circle", "Do it", "yes / no")
                    kindCard(.count, "number.circle", "Reach a number", "e.g. 8 glasses")
                    kindCard(.avoid, "nosign", "Quit", "a bad habit")
                }
                if habit.kind == .count {
                    Stepper(value: $habit.target, in: 1...1000) {
                        Text(L("Goal: %lld a day", habit.target)).font(.system(size: 13))
                    }
                }
            }

            section("When") {
                Picker("", selection: $scheduleKind) {
                    Text("Every day").tag(0)
                    Text("Some weekdays").tag(1)
                    if habit.kind != .avoid { Text("Times a week").tag(2) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if scheduleKind == 1 {
                    HStack(spacing: 6) {
                        ForEach(weekdayOrder, id: \.self) { day in
                            let on = weekdays.contains(day)
                            Button {
                                if on { weekdays.remove(day) } else { weekdays.insert(day) }
                            } label: {
                                Text(verbatim: Calendar.current.veryShortWeekdaySymbols[day - 1])
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(width: 32, height: 32)
                                    .foregroundStyle(on ? .black : .secondary)
                                    .background(on ? Theme.neon : Color.white.opacity(0.06), in: Circle())
                                    .shadow(color: on ? Theme.neon.opacity(0.4) : .clear, radius: 5)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if scheduleKind == 2 {
                    Stepper(value: $timesPerWeek, in: 1...7) { Text(L("%lld× a week", timesPerWeek)).font(.system(size: 13)) }
                }
                HStack {
                    Toggle(isOn: $reminds) { Label("Remind me", systemImage: "bell").font(.system(size: 13)) }
                        .toggleStyle(.switch)
                    Spacer()
                    if reminds {
                        DatePicker("", selection: Binding(
                            get: { Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval(reminder * 60)) },
                            set: { reminder = Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0) }
                        ), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    }
                }
            }

            Spacer(minLength: 0)
            HStack {
                if !isNew {
                    Button("Delete", systemImage: "trash") { confirmsDelete = true }
                        .buttonStyle(GhostButtonStyle(tint: .red))
                }
                Spacer()
                Button("Cancel", action: done).buttonStyle(GhostButtonStyle()).keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save") { save() }
                    .buttonStyle(NeonButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(habit.name.trimmingCharacters(in: .whitespaces).isEmpty || (scheduleKind == 1 && weekdays.isEmpty))
            }
        }
        .padding(24)
        .frame(width: 480, height: 560)
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
        .tint(Theme.neon)
        .onAppear {
            load()
            nameFocused = isNew
        }
        .onChange(of: habit.kind) { _, kind in
            if kind == .avoid, scheduleKind == 2 { scheduleKind = 0 }
        }
        .confirmationDialog(L("Delete “%@” and its history?", habit.name), isPresented: $confirmsDelete) {
            Button("Delete", role: .destructive) {
                store.delete(habit.id)
                done()
            }
        }
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ThemeCaption(title)
            content()
        }
    }

    private func kindCard(_ kind: Habit.Kind, _ systemImage: String, _ title: LocalizedStringKey, _ subtitle: LocalizedStringKey) -> some View {
        let on = habit.kind == kind
        let tint = Habit(name: "", kind: kind).tint
        return Button { habit.kind = kind } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 16, weight: .medium)).foregroundStyle(on ? tint : .secondary)
                Text(title).font(.system(size: 12.5, weight: .semibold))
                Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(on ? tint.opacity(0.12) : Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? tint.opacity(0.55) : Theme.cardStroke))
            .shadow(color: on ? tint.opacity(0.2) : .clear, radius: 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        if habit.emoji.isEmpty { habit.emoji = habit.kind == .avoid ? "🚫" : "✅" }
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
