import SwiftUI

/// Morgen-Checkliste anpassen: Schritte, Minuten, Abfahrtszeit.
/// Gespeichert wird beim Verlassen, damit nicht jeder Tastendruck neu plant.
struct MorningEditView: View {
    @EnvironmentObject private var store: Store
    @State private var steps: [RoutineStep]
    @State private var leaveAt: Int
    @State private var days: [Int]
    @ObservedObject private var theme = Store.shared

    private let weekdays: [(number: Int, name: String)] = [(2, "Mo"), (3, "Di"), (4, "Mi"), (5, "Do"), (6, "Fr"), (7, "Sa"), (1, "So")]

    init(morning: Morning) {
        _steps = State(initialValue: morning.steps)
        _leaveAt = State(initialValue: morning.leaveAt)
        _days = State(initialValue: morning.days)
    }

    private var total: Int { steps.reduce(0) { $0 + $1.minutes } }

    var body: some View {
        List {
            Section {
                TimeRow(label: "Los um", minutes: $leaveAt)
                HStack {
                    Text("Aufstehen")
                    Spacer()
                    Text("\(ClockTime.string(leaveAt - total)) (\(total) Min vorher)")
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("An den gewählten Tagen kommt die Erinnerung zur Aufstehzeit. An den anderen (z. B. Wochenende) startest du sie, wann du willst – ohne Uhr. Später dran? Im Lauf oben rechts auf die Uhr.")
            }
            .dopaRow()

            Section("Tage") {
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
                        .background(on ? theme.theme.accent : DS.field, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                    steps = Morning.defaultSteps
                    leaveAt = 7 * 60 + 35
                }
            }
            .dopaRow()
        }
        .scrollDismissesKeyboard(.interactively)
        .dopaBackground()
        .navigationTitle("Checkliste")
        .toolbar(.visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .onDisappear { store.updateMorningPlan(steps: steps, leaveAt: leaveAt, days: days.sorted()) }
    }
}
