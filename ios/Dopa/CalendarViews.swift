import SwiftUI

/// Kalender verbinden und einstellen: Losgehen-Vorlauf, Vorwarnung, welche Kalender.
struct CalendarSettingsPage: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var agenda = Agenda.shared

    private var settings: Binding<CalendarSettings> {
        Binding(get: { store.data.calendar }, set: { store.updateCalendar($0) })
    }

    var body: some View {
        List {
            Section {
                if agenda.authorized {
                    Toggle("Termine in Dopa zeigen", isOn: settings.on)
                } else if agenda.denied {
                    Text("Kalender-Zugriff ist aus.")
                    Button("In den Einstellungen erlauben") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                } else {
                    Button("Kalender verbinden") {
                        var s = store.data.calendar
                        s.on = true
                        store.updateCalendar(s)
                        Task { await agenda.requestAccess() }
                    }
                }
            } footer: {
                Text("Dopa liest nur. Es ändert nichts an deinen Terminen und schickt sie nirgendwohin.")
            }
            .dopaRow()

            if agenda.authorized && store.data.calendar.on {
                Section {
                    Toggle("Losgehen-Erinnerung", isOn: settings.leaveOn)
                    if store.data.calendar.leaveOn {
                        Stepper("Mit Ort: \(store.data.calendar.leadWithPlace) Min vorher",
                                value: settings.leadWithPlace, in: 5...120, step: 5)
                        Stepper(store.data.calendar.leadWithout == 0 ? "Ohne Ort: keine"
                                    : "Ohne Ort: \(store.data.calendar.leadWithout) Min vorher",
                                value: settings.leadWithout, in: 0...60, step: 5)
                        Toggle("Vorwarnung 15 Min davor", isOn: settings.warnOn)
                    }
                } header: {
                    Text("Rechtzeitig los")
                } footer: {
                    Text("Mit Ort rechnet Dopa Weg plus Puffer – lieber zehn Minuten zu früh als gehetzt. Einzelne Termine kannst du im Plan antippen und anpassen.")
                }
                .dopaRow()

                let calendars = agenda.calendars
                if !calendars.isEmpty {
                    Section("Kalender") {
                        ForEach(calendars) { cal in
                            Toggle(isOn: Binding(
                                get: { !store.data.calendar.hidden.contains(cal.id) },
                                set: { visible in
                                    var s = store.data.calendar
                                    s.hidden.removeAll { $0 == cal.id }
                                    if !visible { s.hidden.append(cal.id) }
                                    store.updateCalendar(s)
                                })) {
                                HStack(spacing: 10) {
                                    Circle().fill(cal.color).frame(width: 10, height: 10)
                                    Text(cal.title)
                                }
                            }
                        }
                    }
                    .dopaRow()
                }
            }
        }
        .dopaBackground()
        .navigationTitle("Kalender")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .onAppear { agenda.refresh() }
    }
}

/// Hinweis oben im Tag, solange der Kalender noch nicht verbunden ist.
struct CalendarPrompt: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var agenda = Agenda.shared

    var body: some View {
        if store.data.calendar.on && !agenda.authorized && !agenda.denied {
            Panel(highlighted: true) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "calendar")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(DS.purpleMuted)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Termine hier sehen?").font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.ink)
                            Text("Dopa zeigt deine Kalender-Termine im Plan und sagt dir, wann du losmusst.")
                                .font(.system(size: 12)).foregroundStyle(DS.muted).lineSpacing(2)
                        }
                    }
                    HStack(spacing: 8) {
                        Button("Verbinden") { Task { await agenda.requestAccess() } }
                            .buttonStyle(SolidButtonStyle())
                        Button("Nicht jetzt") {
                            var s = store.data.calendar
                            s.on = false
                            store.updateCalendar(s)
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.muted)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .buttonStyle(PressStyle())
                    }
                }
                .padding(14)
            }
            .padding(.bottom, 18)
        }
    }
}

/// Termin antippen: Details und eigene Losgehen-Zeit.
struct EventSheet: View {
    let event: AgendaEvent
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var lead = 0

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(event.title).font(.system(size: 20, weight: .bold)).foregroundStyle(DS.ink)
                        Text(event.allDay ? "\(DateText.day(event.start)) · ganztägig"
                             : "\(DateText.day(event.start)) · \(time(event.start))–\(time(event.end))")
                            .font(.system(size: 14)).foregroundStyle(DS.muted)
                        if !event.location.isEmpty {
                            Label(event.location, systemImage: "mappin.and.ellipse")
                                .font(.system(size: 14)).foregroundStyle(DS.ink)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .dopaRow()

                if !event.allDay {
                    Section {
                        Stepper(lead == 0 ? "Keine Erinnerung" : "\(lead) Min vorher", value: $lead, in: 0...180, step: 5)
                        if lead > 0 {
                            HStack {
                                Text("Losgehen um")
                                Spacer()
                                Text(time(event.start.addingTimeInterval(-Double(lead) * 60)))
                                    .foregroundStyle(DS.purpleMuted).monospacedDigit()
                            }
                        }
                    } header: {
                        Text("Losgehen-Erinnerung")
                    } footer: {
                        Text("Gilt für diesen Termin und seine Wiederholungen.")
                    }
                    .dopaRow()
                }
            }
            .dopaBackground()
            .navigationTitle("Termin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        let standard = event.location.isEmpty ? store.data.calendar.leadWithout : store.data.calendar.leadWithPlace
                        if !event.allDay && lead != event.lead(store.data.calendar) {
                            store.setEventLead(event.eventID, minutes: lead == standard ? nil : lead)
                        }
                        dismiss()
                    }
                }
            }
            .onAppear { lead = event.lead(store.data.calendar) }
        }
        .presentationDetents([.medium])
    }

    private func time(_ date: Date) -> String { ClockTime.string(ClockTime.minutes(of: date)) }
}

/// „40 Min“, „1:20 Std“
enum DurationText {
    static func until(_ date: Date, from now: Date = Date()) -> String {
        minutes(Int((date.timeIntervalSince(now) / 60).rounded(.up)))
    }

    static func minutes(_ value: Int) -> String {
        let m = max(0, value)
        if m < 60 { return "\(m) Min" }
        return String(format: "%d:%02d Std", m / 60, m % 60)
    }
}
