import SwiftUI

/// „Hilf mir anfangen“: erster Schritt ist schon vorgeschlagen,
/// ein Tipp auf die Minuten startet sofort.
struct StartSheet: View {
    let fixedTitle: String?                         // nil = freier Timer, Titel wird abgefragt
    var taskID: UUID?                               // für Unterschritte
    let onStart: (_ title: String, _ step: String, _ minutes: Int) -> Void
    @EnvironmentObject private var store: Store

    @State private var title = ""
    @State private var step: String
    @State private var autoStep: String             // zuletzt automatisch vorgeschlagen
    @AppStorage("lastMinutes") private var lastMinutes = 5
    @AppStorage("customMinutes") private var customMinutes = 15

    /// Deine Timer-Knöpfe (Einstellungen), höchstens vier, kürzeste zuerst.
    private var presets: [Int] {
        let list = Array(store.data.reminders.timerPresets.sorted().prefix(4))
        return list.isEmpty ? [2, 5, 10, 25] : list
    }
    @ObservedObject private var server = Server.shared
    @State private var asking = false
    @State private var aiError: String?
    @Environment(\.dismiss) private var dismiss

    init(fixedTitle: String?, initialStep: String, taskID: UUID? = nil,
         onStart: @escaping (_ title: String, _ step: String, _ minutes: Int) -> Void) {
        self.fixedTitle = fixedTitle
        self.taskID = taskID
        self.onStart = onStart
        let suggested = initialStep.isEmpty ? Smart.firstStep(for: fixedTitle ?? "") : initialStep
        _step = State(initialValue: suggested)
        _autoStep = State(initialValue: suggested)
    }

    var body: some View {
        NavigationStack {
            Form {
                if fixedTitle == nil {
                    Section("Woran?") {
                        TextField("z. B. Zimmer aufräumen", text: $title)
                            .onChange(of: title) { newTitle in
                                // Vorschlag mitziehen, solange du ihn nicht selbst geändert hast
                                guard step == autoStep else { return }
                                autoStep = Smart.firstStep(for: newTitle)
                                step = autoStep
                            }
                    }
                    .dopaRow()
                }

                if let task = store.data.tasks.first(where: { $0.id == taskID }), !task.steps.isEmpty {
                    Section {
                        ForEach(task.steps) { sub in
                            Button {
                                store.toggleStep(task.id, sub.id)
                                if !sub.done, let next = store.data.tasks.first(where: { $0.id == task.id })?.nextStep {
                                    step = next
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    CheckBox(done: sub.done)
                                    Text(sub.title).strikethrough(sub.done).foregroundStyle(DS.ink)
                                    Spacer()
                                    Text("\(sub.minutes) Min").font(.caption).foregroundStyle(DS.muted)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Schritte \(task.steps.filter(\.done).count)/\(task.steps.count)")
                    }
                    .dopaRow()
                }

                Section {
                    TextField("Erster Schritt", text: $step, axis: .vertical)
                    Menu {
                        ForEach(Smart.stepOptions(for: fixedTitle ?? title), id: \.self) { option in
                            Button(option) { step = option }
                        }
                    } label: {
                        Label("Anderer Schritt", systemImage: "shuffle")
                    }
                    if server.isConnected && server.aiAvailable {
                        Button(action: askAI) {
                            HStack {
                                Label("Vorschlag von der KI", systemImage: "wand.and.stars")
                                if asking { Spacer(); ProgressView() }
                            }
                        }
                        .disabled(asking || (fixedTitle ?? title).trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("Winzigster erster Schritt")
                } footer: {
                    Text(aiError ?? "Danach darfst du aufhören – oder weitermachen.")
                }
                .dopaRow()

                Section {
                    HStack(spacing: 8) {
                        ForEach(presets, id: \.self) { minutes in
                            durationButton(minutes)
                        }
                    }
                    HStack(spacing: 12) {
                        Stepper(value: $customMinutes, in: 1...180, step: customMinutes < 10 ? 1 : 5) {
                            Text("Eigene: \(customMinutes) Min").monospacedDigit()
                        }
                        Button("Los") { start(customMinutes) }
                            .buttonStyle(.borderedProminent)
                    }
                } header: {
                    Text("Los für …")
                } footer: {
                    Text("Die vier Knöpfe stellst du unter Plan → Zahnrad → Benachrichtigungen ein.")
                }
                .dopaRow()
            }
            .scrollDismissesKeyboard(.interactively)
            .dopaBackground()
            .navigationTitle(fixedTitle ?? "Timer starten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Ein Tipp = Timer läuft. Die zuletzt genutzte Dauer ist hervorgehoben.
    @ViewBuilder
    private func durationButton(_ minutes: Int) -> some View {
        let label = VStack(spacing: 0) {
            Text("\(minutes)").font(.title2.bold())
            Text("Min").font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)

        if minutes == lastMinutes {
            Button { start(minutes) } label: { label }
                .buttonStyle(.borderedProminent)
        } else {
            Button { start(minutes) } label: { label }
                .buttonStyle(.bordered)
        }
    }

    private func askAI() {
        asking = true
        aiError = nil
        Task {
            do {
                step = try await server.firstStep(for: fixedTitle ?? title)
            } catch {
                aiError = error.localizedDescription
            }
            asking = false
        }
    }

    private func start(_ minutes: Int) {
        lastMinutes = minutes
        let name = (fixedTitle ?? title).trimmingCharacters(in: .whitespacesAndNewlines)
        onStart(name.isEmpty ? "Fokus" : name,
                step.trimmingCharacters(in: .whitespacesAndNewlines),
                minutes)
        dismiss()
    }
}
