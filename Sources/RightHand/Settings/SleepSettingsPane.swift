import SwiftUI

/// Settings → Sleep: when to go to bed and how early to be reminded.
struct SleepSettingsPane: View {
    @AppStorage(SleepSettings.Key.enabled) private var enabled = true
    @AppStorage(SleepSettings.Key.bedtime) private var bedtime = 23 * 60
    @AppStorage(SleepSettings.Key.windDown) private var windDown = 30
    @AppStorage(SleepSettings.Key.usesWeekendBedtime) private var usesWeekend = false
    @AppStorage(SleepSettings.Key.weekendBedtime) private var weekendBedtime = 24 * 60

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $enabled) {
                    SettingsRowLabel("Sleep reminder", subtitle: L("A note before bedtime, then a card in the notch until you say good night."),
                                     systemImage: "moon.stars", color: .indigo)
                }
                Group {
                    LabeledContent {
                        DatePicker("", selection: time($bedtime), displayedComponents: .hourAndMinute).labelsHidden()
                    } label: {
                        SettingsRowLabel("Bedtime", systemImage: "bed.double", color: .indigo)
                    }
                    SettingsStepperRow(title: "Remind before", systemImage: "bell", color: .indigo,
                                       value: $windDown, range: 0...90, step: 5, unit: "min")
                    Toggle(isOn: $usesWeekend) {
                        SettingsRowLabel("Later on weekends", subtitle: L("Friday and Saturday nights"), systemImage: "sparkles", color: .indigo)
                    }
                    if usesWeekend {
                        LabeledContent {
                            DatePicker("", selection: time($weekendBedtime), displayedComponents: .hourAndMinute).labelsHidden()
                        } label: {
                            SettingsRowLabel("Weekend bedtime", systemImage: "moon.zzz", color: .indigo)
                        }
                    }
                }
                .disabled(!enabled)
            } footer: {
                SettingsFooter("“15 more minutes” brings the card back later; “Good night” ends the reminders until tomorrow evening. While you record the screen only a notification is shown.")
            }
        }
        .formStyle(.grouped)
    }

    /// Minutes after midnight as a time for the picker (after midnight counts as the next day, e.g. 00:30 = 24:30).
    private func time(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding {
            Calendar.current.startOfDay(for: Date()).addingTimeInterval(TimeInterval((minutes.wrappedValue % (24 * 60)) * 60))
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            var value = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            if value < 5 * 60 { value += 24 * 60 } // 00:30 is after midnight, not this morning
            minutes.wrappedValue = value
        }
    }
}
