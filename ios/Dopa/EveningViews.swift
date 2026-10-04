import SwiftUI

/// Die laufende Abendroutine: Schritte abhaken, Schlafenszeit im Blick – ohne Hetze.
struct EveningRunView: View {
    @EnvironmentObject private var store: Store
    @State private var celebrated = false
    @State private var showTime = false

    var body: some View {
        let e = store.evening
        let bed = e.bedDate()

        List {
            Section {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    header(e, bed: bed, now: context.date)
                }
                .accentCard()
            }

            Section {
                ForEach(e.steps) { step in
                    let done = e.checked.contains(step.id)
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        store.toggleEveningStep(step.id)
                    } label: {
                        HStack(spacing: 12) {
                            CheckBox(done: done)
                            Text(step.title)
                                .strikethrough(done)
                                .foregroundStyle(done ? DS.muted : DS.ink)
                            Spacer()
                            Text("\(step.minutes) Min").font(.caption).foregroundStyle(DS.muted)
                        }
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("Nichts davon muss perfekt sein. Was heute Abend an seinem Platz liegt, musst du morgen früh nicht suchen.")
            }
            .dopaRow()

            if !e.checked.isEmpty {
                Section {
                    Button("Von vorn", role: .destructive) { store.resetEvening() }
                }
                .dopaRow()
            }
        }
        .dopaBackground()
        .navigationTitle("Abend")
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showTime = true } label: { Image(systemName: "clock") }
                    .accessibilityLabel("Heute andere Zeit")
                NavigationLink {
                    EveningEditView(evening: store.data.evening)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $showTime) {
            TodayTimeSheet(title: "Heute ins Bett um", isOverride: e.tonightBed != nil,
                           onSet: { store.setEveningBedTonight($0) }, minutes: e.bedTonight)
        }
        .onChange(of: e.checked.count) { count in
            if count == e.steps.count, count > 0, !celebrated {
                celebrated = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    @ViewBuilder
    private func header(_ e: Evening, bed: Date, now: Date) -> some View {
        let left = e.steps.filter { !e.checked.contains($0.id) }.reduce(0) { $0 + $1.minutes }
        let untilBed = Int(bed.timeIntervalSince(now) / 60)
        VStack(alignment: .leading, spacing: 10) {
            if e.isDone {
                Text("Fertig.")
                    .font(.system(size: 40, weight: .bold))
                Text("Alles für morgen liegt bereit. Gute Nacht.")
                    .foregroundStyle(DS.muted)
            } else if e.untimed {
                Text("Heute ohne Uhr")
                    .font(.system(size: 28, weight: .bold))
                Text("\(e.checked.count) von \(e.steps.count) · kein Countdown, nur abhaken.")
                    .foregroundStyle(DS.muted)
            } else if now < bed {
                Text("Bett um \(ClockTime.string(e.bedTonight))")
                    .font(.headline)
                Text(timerInterval: now...bed, countsDown: true)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("\(e.checked.count) von \(e.steps.count) · noch ca. \(left) Min")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.muted)
                if left > untilBed {
                    Text("Wird knapp. Lass was weg – das Wichtigste: Handy laden, Zähne.")
                        .font(.footnote)
                        .foregroundStyle(Color(hex: 0xF5B94A))
                }
            } else {
                Text("Eigentlich Schlafenszeit")
                    .font(.title2.bold())
                Text("Nur noch das Nötigste: Handy ans Kabel, Zähne, Licht aus.")
                    .foregroundStyle(DS.muted)
                Button("Heute später ins Bett?") { showTime = true }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DS.purpleMuted)
                    .buttonStyle(.plain)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 6)
    }
}

/// Abendroutine anpassen: Schritte, Minuten, Schlafenszeit.
struct EveningEditView: View {
    @EnvironmentObject private var store: Store
    @State private var steps: [RoutineStep]
    @State private var bedAt: Int
    @State private var days: [Int]

    private let weekdays: [(number: Int, name: String)] = [(2, "Mo"), (3, "Di"), (4, "Mi"), (5, "Do"), (6, "Fr"), (7, "Sa"), (1, "So")]

    init(evening: Evening) {
        _steps = State(initialValue: evening.steps)
        _bedAt = State(initialValue: evening.bedAt)
        _days = State(initialValue: evening.days)
    }

    private var total: Int { steps.reduce(0) { $0 + $1.minutes } }

    var body: some View {
        List {
            Section {
                TimeRow(label: "Ins Bett um", minutes: $bedAt)
                HStack {
                    Text("Anfangen")
                    Spacer()
                    Text("\(ClockTime.string(bedAt - total)) (\(total) Min vorher)")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("An den gewählten Abenden kommt die Erinnerung zur Anfangszeit. An den anderen startest du sie, wann du willst – ohne Uhr.")
            }
            .dopaRow()

            Section("Abende mit fester Zeit") {
                HStack(spacing: 6) {
                    ForEach(weekdays.indices, id: \.self) { i in
                        let day = weekdays[i]
                        let on = days.contains(day.number)
                        Button(day.name) {
                            if on { days.removeAll { $0 == day.number } } else { days.append(day.number) }
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(on ? .white : DS.muted)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(on ? store.theme.accent : DS.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .buttonStyle(.plain)
                    }
                }
            }
            .dopaRow()

            Section("Schritte") {
                ForEach($steps) { $step in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Schritt", text: $step.title)
                        Stepper("\(step.minutes) Min", value: $step.minutes, in: 1...30)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
                .onDelete { steps.remove(atOffsets: $0) }
                .onMove { steps.move(fromOffsets: $0, toOffset: $1) }

                Button {
                    steps.append(RoutineStep(title: "", minutes: 2))
                } label: {
                    Label("Schritt hinzufügen", systemImage: "plus")
                }
            }
            .dopaRow()

            Section {
                Button("Auf Standard zurücksetzen") {
                    steps = Evening.defaultSteps
                    bedAt = 23 * 60 + 30
                }
            }
            .dopaRow()
        }
        .scrollDismissesKeyboard(.interactively)
        .dopaBackground()
        .navigationTitle("Abendroutine")
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .onDisappear { store.updateEveningPlan(steps: steps, bedAt: bedAt, days: days.sorted()) }
    }
}
