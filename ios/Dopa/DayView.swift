import SwiftUI
import AppIntents

/// „Plan“ – schlank: Woche, schnell eine Erinnerung, kompakte Zeitleiste mit Jetzt-Linie.
/// Alles zum Einstellen (Routinen, Erinnerungsliste, Wecker, Kalender) hinter dem Zahnrad.
struct DayView: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var agenda = Agenda.shared
    let morningRequest: Int                     // ändert sich → Checkliste öffnen
    let eveningRequest: Int                     // ändert sich → Abendroutine öffnen
    @State private var handledRequest = 0
    @State private var handledEvening = 0
    @State private var showMorning = false
    @State private var showEvening = false
    @State private var showSettings = false
    @State private var editing: CustomReminder?
    @State private var openEvent: AgendaEvent?
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var quick = ""
    @FocusState private var quickFocused: Bool

    private var settings: ReminderSettings { store.data.reminders }
    private var isToday: Bool { Calendar.current.isDateInToday(selectedDay) }

    var body: some View {
        NavigationStack {
            DopaScreen(eyebrow: DateText.day(selectedDay), title: isToday ? "Plan" : DayLabel.text(for: selectedDay),
                       accessory: HeaderAccessory(symbol: "gearshape", label: "Routinen und Einstellungen") { showSettings = true },
                       tab: .tasks) {
                DoSwitch()
                CalendarPrompt()
                DateStrip(selected: $selectedDay).padding(.bottom, 14)
                if isToday {
                    routineRow.padding(.bottom, 14)
                }
                CaptureField(placeholder: "Erinnerung – z. B. „Tabletten um 8“",
                             text: $quick, focus: $quickFocused, onSubmit: quickAdd)
                    .padding(.bottom, 14)
                timeline
            }
            .navigationDestination(isPresented: $showSettings) { PlanSettingsPage() }
            .navigationDestination(isPresented: $showMorning) { MorningRunView() }
            .navigationDestination(isPresented: $showEvening) { EveningRunView() }
            .sheet(item: $editing) { reminder in
                ReminderEditor(reminder: reminder).environmentObject(store)
            }
            .sheet(item: $openEvent) { event in
                EventSheet(event: event).environmentObject(store)
            }
            .onAppear {
                // nach Mitternacht nicht auf gestern hängen bleiben
                let today = Calendar.current.startOfDay(for: Date())
                if selectedDay < today { selectedDay = today }
                handleRequest()
            }
            .onChange(of: morningRequest) { _ in handleRequest() }
            .onChange(of: eveningRequest) { _ in handleRequest() }
        }
    }

    // MARK: Zeitleiste

    private struct Entry: Identifiable {
        let id: String
        let minutes: Int                // zum Sortieren; nach Mitternacht über 1440
        let time: String
        let kicker: String
        let title: String
        let detail: String
        let faded: Bool
        var color: Color?
        var action: (() -> Void)?
    }

    /// Morgen und Abend: jederzeit startbar – an festen Tagen mit Uhr, sonst ohne.
    private var routineRow: some View {
        let m = store.morning
        let e = store.evening
        return HStack(spacing: 10) {
            routineButton(symbol: "sunrise.fill", title: "Morgen", done: m.isDone, checked: m.checked.count, total: m.steps.count,
                          detail: m.isDone ? "geschafft" : m.untimed ? "frei – jederzeit" : "los \(ClockTime.string(m.leaveToday))") {
                showMorning = true
            }
            routineButton(symbol: "moon.fill", title: "Abend", done: e.isDone, checked: e.checked.count, total: e.steps.count,
                          detail: e.isDone ? "geschafft" : e.untimed ? "frei – jederzeit" : "Bett \(ClockTime.string(e.bedTonight))") {
                showEvening = true
            }
        }
    }

    private func routineButton(symbol: String, title: String, done: Bool, checked: Int, total: Int,
                               detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().stroke(Color(hex: 0x352A3B), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: total == 0 ? 0 : CGFloat(checked) / CGFloat(total))
                        .stroke(store.theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 0.55, dampingFraction: 0.8), value: checked)
                    Image(systemName: done ? "checkmark" : symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(done ? store.theme.accent : DS.purpleMuted)
                        .id(done)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
                .frame(width: 38, height: 38)
                .animation(Motion.pop, value: done)
                .popOnChange(of: done, scale: 1.15, when: { $0 })
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.ink)
                    Text(detail).font(.system(size: 12)).foregroundStyle(DS.muted).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(DS.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(DS.line.opacity(0.8)))
        }
        .buttonStyle(PressStyle())
    }

    @ViewBuilder
    private var timeline: some View {
        let now = ClockTime.minutes(of: Date())
        let list = entries(now: now)
        let nextIndex = isToday ? (list.firstIndex { $0.minutes >= now && !$0.faded } ?? list.count) : -1

        dayChips
        Card(title: isToday ? "Zeitleiste" : DayLabel.text(for: selectedDay), symbol: "calendar") {
            if list.isEmpty {
                Text("Nichts angesetzt. Oben eine Erinnerung eintippen – mit Uhrzeit.")
                    .font(.system(size: 14)).foregroundStyle(DS.muted)
            } else {
                // Neuer Tag = neue Liste: Stationen bauen sich kurz nacheinander auf
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, entry in
                        if i == nextIndex { nowLine(now, isFirst: i == 0) }
                        entryView(entry, isFirst: i == 0 && nextIndex != 0,
                                  isLast: i == list.count - 1 && nextIndex != list.count)
                            .enterAnimation(delay: Double(min(i, 8)) * 0.035)
                    }
                    if nextIndex == list.count { nowLine(now, isFirst: false, isLast: true) }
                }
                .id(selectedDay)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: selectedDay)
        .animation(Motion.list, value: list.map(\.id))
    }

    private func entries(now: Int) -> [Entry] {
        let day = selectedDay
        let cal = store.data.calendar
        let dayStart = Calendar.current.startOfDay(for: day)
        var list: [Entry] = []

        // Morgen: an den gewählten Tagen, oder wenn heute schon angefangen
        let m = store.data.morning.forToday(day)
        let weekday = Calendar.current.component(.weekday, from: day)
        if m.days.contains(weekday) || m.startedAt != nil {
            let leave = m.untimed ? "ohne Uhr" : "los um \(ClockTime.string(m.leaveToday))"
            list.append(Entry(
                id: "morning", minutes: m.wakeToday, time: ClockTime.string(m.wakeToday), kicker: "Morgen",
                title: m.isDone ? "Morgen geschafft" : "Morgen-Checkliste",
                detail: m.isDone ? "Schon erledigt"
                    : m.startedAt != nil ? "\(m.checked.count) von \(m.steps.count) · \(leave)"
                    : "\(m.steps.count) Schritte · \(leave)",
                faded: isToday && (m.isDone || (!m.untimed && now > m.leaveToday + 60)),
                action: isToday ? { showMorning = true } : nil))
        }

        // Termine aus dem Kalender
        if cal.on {
            for e in agenda.events(on: day, hidden: cal.hidden) where !e.allDay {
                let startedBefore = e.start < dayStart
                let lead = e.lead(cal)
                var detail = startedBefore ? "seit gestern, bis \(clock(e.end))" : "\(clock(e.start))–\(clock(e.end))"
                if !e.location.isEmpty { detail += " · \(e.location)" }
                list.append(Entry(
                    id: e.id, minutes: startedBefore ? 0 : ClockTime.minutes(of: e.start),
                    time: startedBefore ? "0:00" : clock(e.start),
                    kicker: cal.leaveOn && lead > 0 && !startedBefore ? "Termin · los um \(clock(e.leaveAt(cal)))" : "Termin",
                    title: e.title, detail: detail, faded: e.end < Date(), color: e.color,
                    action: { openEvent = e }))
            }
        }

        // Eigene Erinnerungen
        for r in settings.custom where r.isDue(on: day) {
            let acked = store.isAcked(r.id, on: day)
            list.append(Entry(
                id: r.id.uuidString, minutes: r.minutes, time: ClockTime.string(r.minutes), kicker: "Erinnerung",
                title: r.title,
                detail: acked ? "Erledigt" : !r.detail.isEmpty ? r.detail : settings.persistOn ? "Dranbleiben aktiv" : "Einmalig",
                faded: acked || (isToday && r.minutes < now - 30),
                action: { editing = r }))
        }

        // Aufgaben mit Uhrzeit (antippen = Aufgabe öffnen)
        for t in store.data.tasks {
            guard let at = t.remindAt, Calendar.current.isDate(at, inSameDayAs: day) else { continue }
            let done = t.doneAt != nil
            let taskID = t.id.uuidString
            list.append(Entry(
                id: "task-\(taskID)", minutes: ClockTime.minutes(of: at), time: clock(at), kicker: "Aufgabe",
                title: t.title,
                detail: done ? "Erledigt" : t.showStep && !t.firstStep.isEmpty ? t.firstStep : "",
                faded: done,
                action: { Router.shared.open("anfangen", id: taskID) }))
        }

        // Gewohnheiten mit Uhrzeit
        for h in store.data.habits {
            guard let at = h.remindAt else { continue }
            let count = isToday ? store.habitCount(h.id) : 0
            let done = isToday && count >= h.perDay
            list.append(Entry(
                id: "habit-\(h.id.uuidString)", minutes: at, time: ClockTime.string(at),
                kicker: h.isMed ? "Tabletten" : "Gewohnheit", title: h.title,
                detail: done ? "Abgehakt" : !isToday ? "Täglich" : h.perDay > 1 ? "\(count)/\(h.perDay)" : "Noch offen",
                faded: done))
        }

        // Abend
        let ev = store.evening
        let evStart = ((ev.bedTonight - ev.totalMinutes) % 1440 + 1440) % 1440
        let sortAt = evStart < Evening.dayStartHour * 60 ? evStart + 1440 : evStart
        list.append(Entry(
            id: "evening", minutes: sortAt, time: ClockTime.string(evStart), kicker: "Abend",
            title: isToday && ev.isDone ? "Abend geschafft" : "Abendroutine",
            detail: isToday && ev.isDone ? "Gute Nacht"
                : isToday && !ev.checked.isEmpty ? "\(ev.checked.count) von \(ev.steps.count) · Bett um \(ClockTime.string(ev.bedTonight))"
                : "\(ev.steps.count) Schritte · Bett um \(ClockTime.string(ev.bedAt))",
            faded: isToday && ev.isDone,
            action: isToday ? { showEvening = true } : nil))

        return list.sorted { $0.minutes < $1.minutes }
    }

    /// Die Jetzt-Markierung auf der Linie.
    private func nowLine(_ now: Int, isFirst: Bool, isLast: Bool = false) -> some View {
        HStack(spacing: 0) {
            Text("Jetzt")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(store.theme.accent)
                .frame(width: 44, alignment: .leading)
            Color.clear.frame(width: 32)
            Rectangle().fill(store.theme.accent.opacity(0.6)).frame(height: 1.5)
            Text(ClockTime.string(now))
                .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                .foregroundStyle(store.theme.accent)
                .padding(.leading, 8)
        }
        .padding(.vertical, 10)
        .background(alignment: .topLeading) {
            TimelineRail(isFirst: isFirst, isLast: isLast, color: store.theme.accent, big: true, live: true)
        }
    }

    @ViewBuilder
    private func entryView(_ e: Entry, isFirst: Bool, isLast: Bool) -> some View {
        let row = PlanRow(time: e.time, kicker: e.kicker, title: e.title, detail: e.detail,
                          faded: e.faded, color: e.color, tappable: e.action != nil,
                          isFirst: isFirst, isLast: isLast)
        if let action = e.action {
            Button(action: action) { row }.buttonStyle(PressStyle())
        } else {
            row
        }
    }

    /// Ganztägiges und Geld für den gewählten Tag als Chips über der Zeitleiste.
    @ViewBuilder
    private var dayChips: some View {
        let cal = store.data.calendar
        let allDay = cal.on ? agenda.events(on: selectedDay, hidden: cal.hidden).filter(\.allDay) : []
        let money = moneyOn(selectedDay)
        if !allDay.isEmpty || !money.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(allDay) { e in
                        chip(symbol: "calendar", text: e.title, color: e.color) { openEvent = e }
                    }
                    ForEach(money) { item in
                        chip(symbol: "eurosign", text: moneyText(item),
                             color: item.kind == .debt ? Color(hex: 0xF5B94A) : DS.purpleMuted) { Router.shared.open("geld") }
                    }
                }
            }
            .padding(.bottom, 12)
        }
    }

    /// Heute: alles Offene bis heute (auch Überfälliges). Andere Tage: was genau dann fällig ist.
    private func moneyOn(_ day: Date) -> [MoneyItem] {
        let dayOfMonth = Calendar.current.component(.day, from: day)
        return store.data.money.filter { item in
            switch item.kind {
            case .debt:
                guard let due = item.due else { return false }
                let days = MoneyMath.daysUntil(due, now: day)
                return isToday ? days <= 0 : days == 0
            case .income, .fixed:
                return item.dayOfMonth == dayOfMonth
            }
        }
    }

    private func moneyText(_ item: MoneyItem) -> String {
        let amount = MoneyMath.euro(item.amount)
        switch item.kind {
        case .debt:
            let overdue = item.due.map { MoneyMath.daysUntil($0) < 0 } ?? false
            return "\(overdue ? "Offen" : "Fällig"): \(item.title) · \(amount)"
        case .fixed: return "Geht ab: \(item.title) · \(amount)"
        case .income: return "Kommt: \(item.title) · \(amount)"
        }
    }

    private func chip(symbol: String, text: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(color)
                Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: 0xD8CFE0)).lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(DS.field, in: Capsule())
            .overlay(Capsule().stroke(DS.chipBorder))
        }
        .buttonStyle(PressStyle())
    }

    private func clock(_ date: Date) -> String { ClockTime.string(ClockTime.minutes(of: date)) }

    // MARK: Schnell eine Erinnerung

    /// „Tabletten um 8“ → Erinnerung um 8:00. Ohne Uhrzeit geht der Editor auf.
    private func quickAdd() {
        let text = quick.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        quick = ""
        quickFocused = false
        if let parsed = ReminderParse.parse(text) {
            store.saveReminder(CustomReminder(title: parsed.title, minutes: parsed.minutes))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            Toaster.shared.show("Erinnerung um \(ClockTime.string(parsed.minutes)) steht")
        } else {
            editing = CustomReminder(title: text, minutes: ClockTime.minutes(of: Date().addingTimeInterval(3600)) / 60 * 60)
        }
    }

    private func handleRequest() {
        if morningRequest != handledRequest {
            handledRequest = morningRequest
            selectedDay = Calendar.current.startOfDay(for: Date())
            showMorning = true
        }
        if eveningRequest != handledEvening {
            handledEvening = eveningRequest
            selectedDay = Calendar.current.startOfDay(for: Date())
            showEvening = true
        }
    }
}

/// Eine Woche ab heute zum Antippen; ein Punkt heißt: da sind Termine.
private struct DateStrip: View {
    @Binding var selected: Date
    @ObservedObject private var store = Store.shared
    @ObservedObject private var agenda = Agenda.shared
    @Namespace private var namespace

    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEEEE"
        return f
    }()

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let settings = store.data.calendar
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { offset in
                let day = cal.date(byAdding: .day, value: offset, to: today) ?? today
                let isSelected = cal.isDate(day, inSameDayAs: selected)
                let busy = settings.on && !agenda.events(on: day, hidden: settings.hidden).isEmpty
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) { selected = day }
                } label: {
                    VStack(spacing: 4) {
                        Text(offset == 0 ? "HEUTE" : Self.weekday.string(from: day).uppercased())
                            .font(.system(size: 9, weight: .heavy))
                        Text("\(cal.component(.day, from: day))").font(.system(size: 16, weight: .semibold))
                        Circle()
                            .fill(busy ? (isSelected ? Color.white : DS.purpleMuted) : Color.clear)
                            .frame(width: 4, height: 4)
                    }
                    .foregroundStyle(isSelected ? .white : offset == 0 ? DS.purpleMuted : Color(hex: 0x77707C))
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(store.theme.accent)
                                .matchedGeometryEffect(id: "day", in: namespace)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }
        }
    }
}

/// Eine Station auf der Zeitleiste: Uhrzeit, Punkt auf der durchgehenden Linie, Titel, Details.
private struct PlanRow: View {
    let time: String
    let kicker: String
    let title: String
    let detail: String
    let faded: Bool
    var color: Color?
    var tappable = false
    var isFirst = false
    var isLast = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(time)
                .font(.system(size: 13, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(DS.purpleMuted)
                .frame(width: 44, alignment: .leading)
            Color.clear.frame(width: 32, height: 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.ink).lineLimit(2)
                Text(detail.isEmpty ? kicker : "\(kicker) · \(detail)")
                    .font(.system(size: 12)).foregroundStyle(DS.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
            if tappable {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(DS.faint)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(alignment: .topLeading) {
            TimelineRail(isFirst: isFirst, isLast: isLast, color: color ?? Color(hex: 0x8A7F94), big: false)
        }
        .opacity(faded ? 0.45 : 1)
    }
}

/// Die senkrechte Linie mit dem Punkt einer Station (Mitte der Spalte zwischen Uhrzeit und Text).
private struct TimelineRail: View {
    let isFirst: Bool
    let isLast: Bool
    let color: Color
    let big: Bool
    var live = false                    // Jetzt-Punkt: pulsiert sanft

    var body: some View {
        GeometryReader { geo in
            let x: CGFloat = 44 + 16
            let nodeY: CGFloat = 19
            Path { p in
                p.move(to: CGPoint(x: x, y: isFirst ? nodeY : 0))
                p.addLine(to: CGPoint(x: x, y: isLast ? nodeY : geo.size.height))
            }
            .stroke(Color(hex: 0x352E3B), lineWidth: 2)
            if live {
                LiveDot(color: color, size: 12)
                    .position(x: x, y: nodeY)
            }
            Circle()
                .fill(color)
                .frame(width: big ? 12 : 10, height: big ? 12 : 10)
                .overlay(Circle().stroke(DS.raised, lineWidth: 2.5))
                .position(x: x, y: nodeY)
        }
    }
}

private struct ReminderLine: View {
    let reminder: CustomReminder
    let dueToday: Bool
    let acked: Bool
    let persist: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void

    private var days: String {
        if reminder.weekdays.isEmpty { return "Täglich" }
        let names = [1: "So", 2: "Mo", 3: "Di", 4: "Mi", 5: "Do", 6: "Fr", 7: "Sa"]
        let order = [2, 3, 4, 5, 6, 7, 1]
        return order.filter { reminder.weekdays.contains($0) }.compactMap { names[$0] }.joined(separator: " ")
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(ClockTime.string(reminder.minutes))
                .font(.system(size: 12, weight: .bold)).monospacedDigit()
                .foregroundStyle(DS.purpleMuted)
                .frame(width: 46, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(reminder.title).font(.system(size: 15, weight: .semibold)).strikethrough(acked).foregroundStyle(DS.ink)
                Text("\(days) · \(persist ? "Dranbleiben aktiv" : "Einmalig")")
                    .font(.system(size: 12)).foregroundStyle(DS.muted)
            }
            Spacer(minLength: 0)
            if dueToday {
                Button(acked ? "Zurück" : "Erledigt", action: onToggle)
                    .buttonStyle(PillButtonStyle(prominent: !acked))
            }
        }
        .padding(.vertical, 8)
        .hairlineRow(minHeight: 70)
        .opacity(acked ? 0.48 : 1)
        .animation(.easeOut(duration: 0.2), value: acked)
        .onTapGesture(perform: onEdit)
    }
}

/// Eigene Erinnerung anlegen oder ändern.
private struct ReminderEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var reminder: CustomReminder

    private let days: [(number: Int, name: String)] = [(2, "Mo"), (3, "Di"), (4, "Mi"), (5, "Do"), (6, "Fr"), (7, "Sa"), (1, "So")]
    private var isNew: Bool { !store.data.reminders.custom.contains { $0.id == reminder.id } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Woran erinnern? z. B. Tabletten nehmen", text: $reminder.title)
                } footer: {
                    Text("")
                }
                .dopaRow()

                Section {
                    DatePicker("Uhrzeit",
                               selection: Binding(get: { ClockTime.date(reminder.minutes) },
                                                  set: { reminder.minutes = ClockTime.minutes(of: $0) }),
                               displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                } header: {
                    Text("Uhrzeit")
                } footer: {
                    Text("„Erledigt“ in der Benachrichtigung stoppt die Nachfragen für heute und landet in „Notizen“.")
                }
                .dopaRow()

                Section("Tage") {
                    HStack(spacing: 6) {
                        ForEach(days.indices, id: \.self) { i in
                            let day = days[i]
                            let on = reminder.weekdays.isEmpty || reminder.weekdays.contains(day.number)
                            Button(day.name) { toggleDay(day.number) }
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(on ? .white : DS.muted)
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(on ? store.theme.accent : DS.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .buttonStyle(.plain)
                        }
                    }
                }
                .dopaRow()

                if !isNew {
                    Section {
                        Button("Erinnerung löschen", role: .destructive) {
                            store.deleteReminder(reminder.id)
                            dismiss()
                        }
                    }
                    .dopaRow()
                }
            }
            .dopaBackground()
            .navigationTitle(isNew ? "Neue Erinnerung" : "Erinnerung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        reminder.title = reminder.title.trimmingCharacters(in: .whitespaces)
                        store.saveReminder(reminder)
                        dismiss()
                    }
                    .disabled(reminder.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Leer = jeden Tag. Erstes Antippen schaltet von „jeden Tag“ auf „alle außer diesem“.
    private func toggleDay(_ day: Int) {
        var set = Set(reminder.weekdays.isEmpty ? [1, 2, 3, 4, 5, 6, 7] : reminder.weekdays)
        if set.contains(day) { set.remove(day) } else { set.insert(day) }
        reminder.weekdays = set.count == 7 || set.isEmpty ? [] : Array(set).sorted()
    }
}

/// Hinter dem Zahnrad im Plan: Routinen, Erinnerungen, Kalender.
struct PlanSettingsPage: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var agenda = Agenda.shared

    var body: some View {
        List {
            Section("Routinen") {
                NavigationLink {
                    MorningEditView(morning: store.data.morning)
                } label: {
                    SettingsRow(icon: "sunrise.fill", color: .orange, title: "Morgen-Checkliste",
                                value: "los \(ClockTime.string(store.morning.leaveAt))")
                }
                NavigationLink {
                    EveningEditView(evening: store.data.evening)
                } label: {
                    SettingsRow(icon: "moon.fill", color: .indigo, title: "Abendroutine",
                                value: "Bett \(ClockTime.string(store.evening.bedAt))")
                }
                NavigationLink {
                    HabitsPage()
                } label: {
                    SettingsRow(icon: "drop.fill", color: .cyan, title: "Gewohnheiten & Tabletten",
                                value: "\(store.data.habits.count)")
                }
            }
            .dopaRow()

            Section {
                NavigationLink {
                    RemindersListPage()
                } label: {
                    SettingsRow(icon: "bell.fill", color: .red, title: "Eigene Erinnerungen",
                                value: "\(store.data.reminders.custom.count)")
                }
                Toggle(isOn: Binding(get: { store.data.reminders.persistOn },
                                     set: { on in var r = store.data.reminders; r.persistOn = on; store.updateReminders(r) })) {
                    SettingsRow(icon: "arrow.clockwise", color: .green, title: "Dranbleiben")
                }
                .tint(store.theme.accent)
                NavigationLink {
                    ReminderSettingsPage()
                } label: {
                    SettingsRow(icon: "bell.badge.fill", color: .pink, title: "Benachrichtigungen")
                }
            } header: {
                Text("Erinnerungen")
            } footer: {
                Text("Dranbleiben: nach 10 und 25 Min nochmal, bis du „Erledigt“ tippst.")
            }
            .dopaRow()

            Section("Kalender") {
                NavigationLink {
                    CalendarSettingsPage()
                } label: {
                    SettingsRow(icon: "calendar", color: .red, title: "Kalender",
                                value: agenda.authorized && store.data.calendar.on ? "an" : "aus")
                }
            }
            .dopaRow()
        }
        .dopaBackground()
        .navigationTitle("Plan einstellen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

/// Alle eigenen Erinnerungen: antippen ändert, wischen löscht, Plus legt an.
struct RemindersListPage: View {
    @EnvironmentObject private var store: Store
    @State private var editing: CustomReminder?

    private var settings: ReminderSettings { store.data.reminders }

    var body: some View {
        List {
            if settings.custom.isEmpty {
                Section {
                    Text("Noch keine. Im Plan oben einfach „Tabletten um 8“ eintippen – oder hier Plus.")
                        .font(.footnote).foregroundStyle(DS.muted)
                }
                .dopaRow()
            } else {
                Section {
                    ForEach(settings.custom) { r in
                        ReminderLine(reminder: r,
                                     dueToday: r.isDue(on: Date()),
                                     acked: store.isAcked(r.id),
                                     persist: settings.persistOn,
                                     onToggle: { store.isAcked(r.id) ? store.unackReminder(r.id) : store.ackReminder(r.id) },
                                     onEdit: { editing = r })
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { settings.custom[$0].id }
                        for id in ids { store.deleteReminder(id) }
                    }
                } footer: {
                    Text("Antippen ändert Zeit und Tage. Nach links wischen löscht.")
                }
                .dopaRow()
            }
        }
        .dopaBackground()
        .navigationTitle("Eigene Erinnerungen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = CustomReminder(title: "", minutes: ClockTime.minutes(of: Date().addingTimeInterval(3600)) / 60 * 60)
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editing) { reminder in
            ReminderEditor(reminder: reminder).environmentObject(store)
        }
    }
}

/// Unterseite mit den bisherigen Erinnerungs-Einstellungen und Siri.
struct ReminderSettingsPage: View {
    var body: some View {
        List {
            ReminderSettingsSection()
            Section {
                SiriTipView(intent: RememberIntent())
                SiriTipView(intent: FindIntent())
                SiriTipView(intent: StartIntent())
                SiriTipView(intent: AddShopIntent())
                ShortcutsLink()
            } header: {
                Text("Siri & Kurzbefehle")
            } footer: {
                Text("Geht auch ohne Entsperren: „Hey Siri, Dopa merken“ – Siri fragt dann, was.")
            }
            .dopaRow()
        }
        .dopaBackground()
        .navigationTitle("Wecker von außen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }
}

/// Einstellungen für die Erinnerungen. Jede Änderung plant sofort neu.
struct ReminderSettingsSection: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var health = Health.shared

    private var settings: Binding<ReminderSettings> {
        Binding(get: { store.data.reminders }, set: { store.updateReminders($0) })
    }

    private func valueRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(DS.muted).monospacedDigit()
        }
    }

    /// Einschalten fragt einmal nach Health und liest dann gleich den Schlaf.
    private var sleepBinding: Binding<Bool> {
        Binding(
            get: { store.data.reminders.sleepOn },
            set: { on in
                var s = store.data.reminders
                s.sleepOn = on
                store.updateReminders(s)
                guard on else { return }
                Task { @MainActor in
                    if await Health.shared.requestAccess() {
                        await store.refreshHealth()
                    } else {
                        Toaster.shared.show("Health ist gerade nicht erreichbar")
                    }
                }
            })
    }

    /// Binding per Index mit Grenzprüfung – ForEach über Indizes crasht sonst beim Löschen.
    private func mealTime(_ i: Int) -> Binding<Int> {
        Binding(
            get: { i < store.data.reminders.mealTimes.count ? store.data.reminders.mealTimes[i] : 0 },
            set: { newValue in
                var s = store.data.reminders
                guard i < s.mealTimes.count else { return }
                s.mealTimes[i] = newValue
                store.updateReminders(s)
            })
    }

    var body: some View {
        Section {
            Toggle(isOn: settings.briefingOn) {
                Label("Morgen-Überblick von Dot", systemImage: "sunrise")
            }
            Toggle(isOn: settings.reviewOn) {
                Label("Tagesrückblick am Abend", systemImage: "sunset")
            }
            Toggle(isOn: settings.spendAskOn) {
                Label("Abends nach Ausgaben fragen", systemImage: "eurosign")
            }
        } header: {
            Text("Begleiter")
        } footer: {
            Text("Zur Aufstehzeit: Termine, das Eine, Tabletten. Abends: was geschafft ist, und „Was ist morgen das Eine?“ – direkt in der Benachrichtigung beantworten.")
        }
        .dopaRow()

        Section {
            Toggle(isOn: settings.countdownOn) {
                Label("Losgeh-Countdown", systemImage: "figure.walk")
            }
            if settings.wrappedValue.countdownOn {
                MinutesListRow(label: "Vorher", list: settings.countdown, limit: 4)
            }
            Toggle(isOn: settings.halfwayOn) {
                Label("Timer: Tipper zur Halbzeit", systemImage: "timer")
            }
            Toggle(isOn: sleepBinding) {
                Label("Schlaf & Bewegung für Dot", systemImage: "heart.text.square")
            }
            if store.data.reminders.sleepOn {
                if let sleep = health.sleepLastNight {
                    valueRow("Letzte Nacht", Timing.hoursText(sleep))
                }
                if let average = health.sleepAverage {
                    valueRow("Schnitt 7 Nächte", Timing.hoursText(average))
                }
                if let steps = health.stepsToday {
                    valueRow("Schritte heute", Timing.thousands(steps))
                }
                if let exercise = health.exerciseToday {
                    valueRow("Bewegung heute", "\(exercise) Min")
                }
            }
        } header: {
            Text("Apple Watch & Losgehen")
        } footer: {
            Text("Countdown: vor der Losgehzeit und vor Terminen tippt dir die Uhr aufs Handgelenk – auch im Fokus-Modus. Schlaf & Bewegung: Dot sieht nur diese Zahlen und plant danach – nach kurzen Nächten kleinere Schritte, nach viel Sitzen mal eine Bewegungspause.")
        }
        .dopaRow()
        .task { await store.refreshHealth() }

        Section {
            MinutesListRow(label: "Timer-Knöpfe", list: settings.timerPresets, limit: 4)
            Stepper(value: settings.extendMinutes, in: 1...60) {
                Text("Timer verlängern: +\(store.data.reminders.extendMinutes) Min")
            }
            Stepper(value: settings.snoozeMinutes, in: 1...120) {
                Text("„Später“: \(store.data.reminders.snoozeMinutes) Min")
            }
            Stepper(value: settings.mealSnooze, in: 5...120, step: 5) {
                Text("Essen nochmal: \(store.data.reminders.mealSnooze) Min")
            }
            Toggle(isOn: settings.persistOn) {
                Text("Dranbleiben")
            }
            if settings.wrappedValue.persistOn {
                MinutesListRow(label: "Nochmal nach", list: settings.followUps, limit: 4)
            }
        } header: {
            Text("Eigene Zeiten")
        } footer: {
            Text("Mehrere Zeiten mit Komma, z. B. „15, 10, 5“. Die Knöpfe in den Mitteilungen (auch auf der Uhr) übernehmen deine Zeiten.")
        }
        .dopaRow()

        Section {
            Toggle(isOn: settings.mealsOn) {
                Label("Essen-Erinnerung", systemImage: "fork.knife")
            }
            if settings.wrappedValue.mealsOn {
                ForEach(Array(settings.wrappedValue.mealTimes.enumerated()), id: \.offset) { i, minutes in
                    TimeRow(label: Texts.mealTitle(minutes).replacingOccurrences(of: "?", with: ""),
                            minutes: mealTime(i))
                }
                .onDelete { offsets in settings.wrappedValue.mealTimes.remove(atOffsets: offsets) }
                Button("Uhrzeit hinzufügen") {
                    settings.wrappedValue.mealTimes.append(15 * 60)
                }
            }
        } footer: {
            Text("Mit „Gegessen ✔︎“ direkt in der Benachrichtigung – landet automatisch in „Notizen“.")
        }
        .dopaRow()

        Section {
            Toggle(isOn: settings.nudgeOn) {
                Label("Hyperfokus-Stupser", systemImage: "hand.tap")
            }
            if settings.wrappedValue.nudgeOn {
                TimeRow(label: "Von", minutes: settings.nudgeFrom)
                TimeRow(label: "Bis", minutes: settings.nudgeTo)
                Picker("Alle", selection: settings.nudgeEvery) {
                    ForEach([30, 45, 60, 90, 120], id: \.self) { Text("\($0) Min").tag($0) }
                }
            }
        } footer: {
            Text("Holt dich regelmäßig kurz raus – ohne dass du vorher etwas starten musst. In der Benachrichtigung kannst du dir direkt merken, wo du warst.")
        }
        .dopaRow()

        Section {
            Toggle(isOn: settings.morningOn) {
                Label("Morgen-Erinnerung (Mo–Fr)", systemImage: "sunrise")
            }
            Toggle(isOn: settings.eveningOn) {
                Label("Abendroutine (um \(ClockTime.string(store.evening.startAt)))", systemImage: "moon")
            }
        } footer: {
            Text("Die Texte wechseln jedes Mal, wenn du Dopa öffnest – damit du sie nicht automatisch wegwischst.")
        }
        .dopaRow()
    }
}

/// Mehrere Minuten als Text („10, 5“) – übernommen beim Fertig-Tippen oder Verlassen des Felds.
struct MinutesListRow: View {
    let label: String
    @Binding var list: [Int]
    var limit = 6
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
            Spacer(minLength: 8)
            TextField("z. B. 10, 5", text: $text)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(apply)
                .frame(maxWidth: 140)
            Text("Min").foregroundStyle(DS.muted)
        }
        .onAppear { text = Timing.listText(list) }
        .onChange(of: focused) { isFocused in
            if !isFocused { apply() }
        }
    }

    private func apply() {
        let parsed: [Int] = Array(Timing.parseList(text).prefix(limit))
        if !parsed.isEmpty && parsed != list { list = parsed }
        text = Timing.listText(parsed.isEmpty ? list : parsed)
    }
}

/// Uhrzeit-Auswahl, gebunden an „Minuten seit Mitternacht“.
struct TimeRow: View {
    let label: String
    @Binding var minutes: Int

    var body: some View {
        DatePicker(label,
                   selection: Binding(get: { ClockTime.date(minutes) },
                                      set: { minutes = ClockTime.minutes(of: $0) }),
                   displayedComponents: .hourAndMinute)
    }
}

/// Uhrzeit aus Freitext: „Tabletten um 8“, „Wäsche 18:30“, „Müll raus 7 Uhr“.
enum ReminderParse {
    private static let patterns = [
        #"\b(?:um\s+)?(\d{1,2})[:.](\d{2})(?:\s*uhr)?\b"#,   // 18:30, um 8.15
        #"\bum\s+(\d{1,2})(?:\s*uhr)?\b"#,                   // um 8, um 8 uhr
        #"\b(\d{1,2})\s*uhr\b"#,                             // 7 uhr
    ]

    static func parse(_ text: String) -> (title: String, minutes: Int)? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let hourRange = Range(match.range(at: 1), in: text),
                  let hour = Int(text[hourRange]), hour < 24 else { continue }
            var minute = 0
            if match.numberOfRanges > 2, let r = Range(match.range(at: 2), in: text), let m = Int(text[r]) {
                guard m < 60 else { continue }
                minute = m
            }
            guard let whole = Range(match.range, in: text) else { continue }
            var title = text
            title.removeSubrange(whole)
            title = title.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            guard !title.isEmpty else { return nil }
            return (title.prefix(1).uppercased() + title.dropFirst(), hour * 60 + minute)
        }
        return nil
    }
}
