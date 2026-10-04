import SwiftUI

/// Aufgabe öffnen: Titel, frei planen (heute, morgen, Datum, irgendwann), eigene Schritte
/// mit Minuten zum Anpassen – und unten groß „Anfangen“ oder „Erledigt“.
struct TaskDetailSheet: View {
    let taskID: UUID
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var server = Server.shared
    @State private var title = ""
    @State private var newStep = ""
    @State private var newMinutes = 5
    @State private var pickingDate = false
    @State private var date = Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date()
    @State private var breaking = false
    @State private var editMode = EditMode.inactive
    @FocusState private var stepFocused: Bool

    private var task: TaskItem? { store.data.tasks.first { $0.id == taskID } }

    var body: some View {
        NavigationStack {
            Group {
                if let task {
                    content(task)
                } else {
                    EmptyState(symbol: "", title: "Aufgabe gelöscht", text: "")
                        .padding(20)
                }
            }
            .background(DS.surface.ignoresSafeArea())
            .navigationTitle("Aufgabe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { commitTitle(); dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if let task, task.steps.count > 1 {
                        Button(editMode == .active ? "Fertig sortiert" : "Sortieren") {
                            withAnimation { editMode = editMode == .active ? .inactive : .active }
                        }
                    }
                }
            }
            .environment(\.editMode, $editMode)
        }
        .onAppear {
            title = task?.title ?? ""
            if let due = task?.dueDay { date = due }
        }
        .onDisappear(perform: commitTitle)
        .presentationDetents([.large])
    }

    @ViewBuilder
    private func content(_ task: TaskItem) -> some View {
        List {
            Section {
                TextField("Aufgabe", text: $title, axis: .vertical)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(DS.ink)
                    .submitLabel(.done)
                    .onSubmit(commitTitle)
                if !task.steps.isEmpty {
                    let done = task.steps.filter(\.done).count
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(done) von \(task.steps.count) Schritten · noch ca. \(task.minutesLeft) Min")
                            .font(.system(size: 13)).foregroundStyle(DS.muted)
                        Track(fraction: Double(done) / Double(task.steps.count))
                    }
                    .padding(.vertical, 4)
                }
            }
            .dopaRow()

            Section {
                planChips(task)
                if pickingDate {
                    DatePicker("Datum", selection: $date,
                               in: (Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())...,
                               displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .onChange(of: date) { store.setPlan(task.id, .date($0)) }
                }
                if !task.someday {
                    Toggle(isOn: Binding(
                        get: { task.remindAt != nil },
                        set: { on in
                            UISelectionFeedbackGenerator().selectionChanged()
                            store.setTaskTime(task.id, on ? Timing.defaultTaskTime(day: task.dueDay, now: Date()) : nil)
                        })) {
                        Label("Uhrzeit mit Erinnerung", systemImage: "bell")
                    }
                    if let at = task.remindAt {
                        DatePicker("Um", selection: Binding(get: { at }, set: { store.setTaskTime(task.id, $0) }),
                                   in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    }
                }
            } header: {
                Text("Wann?")
            } footer: {
                if task.remindAt != nil {
                    Text("Zur Uhrzeit kommt eine Mitteilung (auch auf der Uhr) mit „Erledigt“ und „Später“.")
                }
            }
            .dopaRow()

            // Wo? – erinnern, wenn du an einem Ort ankommst
            Section {
                if store.data.spots.isEmpty {
                    NavigationLink { SpotsPage() } label: {
                        Label("Orte anlegen (Zuhause, Laden …)", systemImage: "mappin.and.ellipse")
                    }
                } else {
                    Picker(selection: Binding<UUID?>(
                        get: { task.spotID },
                        set: { id in
                            UISelectionFeedbackGenerator().selectionChanged()
                            store.setTaskSpot(task.id, id)
                        })) {
                        Text("Kein Ort").tag(UUID?.none)
                        ForEach(store.data.spots) { spot in
                            Label(spot.name, systemImage: spot.symbol).tag(UUID?.some(spot.id))
                        }
                    } label: {
                        Label("Erinnern bei", systemImage: "mappin.and.ellipse")
                    }
                }
            } header: {
                Text("Wo?")
            } footer: {
                if let spot = store.spot(task.spotID) {
                    Text("Kommst du bei „\(spot.name)“ an, meldet sich die Aufgabe – auch auf der Uhr.")
                }
            }
            .dopaRow()

            if task.steps.isEmpty {
                Section {
                    if task.showStep {
                        TextField("Winzigster erster Schritt", text: Binding(
                            get: { task.firstStep },
                            set: { store.setFirstStep(task.id, $0) }), axis: .vertical)
                        Button("Ausblenden") {
                            withAnimation(Motion.list) { store.setShowStep(task.id, false) }
                        }
                        .foregroundStyle(DS.muted)
                    } else {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(Motion.list) { store.setShowStep(task.id, true) }
                        } label: {
                            Label("Mini-Schritt zeigen", systemImage: "figure.walk")
                        }
                    }
                } header: {
                    Text("Mini-Schritt")
                } footer: {
                    Text(task.showStep ? "Steht dann auch in der Liste unter der Aufgabe."
                                       : "Erst wenn du willst: ein winziger erster Handgriff, damit Anfangen leichter wird.")
                }
                .dopaRow()
            }

            Section {
                ForEach(task.steps) { step in
                    StepRow(taskID: task.id, step: step)
                }
                .onDelete { offsets in
                    let ids = offsets.map { task.steps[$0].id }
                    for id in ids { store.deleteStep(task.id, id) }
                }
                .onMove { store.moveSteps(task.id, from: $0, to: $1) }

                HStack(spacing: 10) {
                    Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundStyle(DS.purpleMuted)
                    TextField("Schritt hinzufügen", text: $newStep)
                        .focused($stepFocused)
                        .submitLabel(.next)
                        .onSubmit(addStep)
                    MinuteStepper(minutes: $newMinutes)
                }
            } header: {
                HStack {
                    Text("Schritte")
                    Spacer()
                    let total = task.steps.reduce(0) { $0 + $1.minutes }
                    if total > 0 { Text("gesamt ca. \(total) Min") }
                }
            } footer: {
                Text(task.steps.isEmpty
                     ? "Kleine Schritte mit ungefähren Minuten – Dopa startet beim Anfangen den nächsten mit seiner Zeit."
                     : "Minuten mit − und + ändern, nach links wischen zum Löschen, „Sortieren“ oben rechts.")
            }
            .dopaRow()

            if server.isConnected && server.aiAvailable {
                Section {
                    Button { breaking = true } label: {
                        Label(task.steps.isEmpty ? "In Schritte zerlegen lassen" : "Neu zerlegen lassen", systemImage: "wand.and.stars")
                    }
                }
                .dopaRow()
            }

            Section {
                Button(role: .destructive) {
                    store.deleteTask(task.id)
                    dismiss()
                } label: {
                    Label("Aufgabe löschen", systemImage: "trash")
                }
            }
            .dopaRow()
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) { actions(task) }
        .sheet(isPresented: $breaking) { BreakdownSheet(task: task).environmentObject(store) }
    }

    // MARK: Planen

    private func planChips(_ task: TaskItem) -> some View {
        let plan = store.plan(of: task)
        let isDate: Bool = { if case .date = plan { return true } else { return false } }()
        return HStack(spacing: 6) {
            chip("Heute", selected: plan == .today) { pickingDate = false; store.setPlan(task.id, .today) }
            chip("Morgen", selected: plan == .tomorrow) { pickingDate = false; store.setPlan(task.id, .tomorrow) }
            chip(isDate ? DayLabel.text(for: task.dueDay ?? date) : "Datum", selected: isDate) {
                withAnimation(.easeOut(duration: 0.2)) { pickingDate.toggle() }
                if !isDate { store.setPlan(task.id, .date(date)) }
            }
            chip("Irgendwann", selected: plan == .someday) { pickingDate = false; store.setPlan(task.id, .someday) }
        }
        .padding(.vertical, 4)
    }

    private func chip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { action() }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(selected ? .white : Color(hex: 0xB9B0BF))
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(selected ? store.theme.accent : DS.field, in: Capsule())
                .overlay(Capsule().stroke(selected ? .clear : DS.chipBorder))
        }
        .buttonStyle(PressStyle())
    }

    // MARK: Unten: Erledigt / Anfangen

    private func actions(_ task: TaskItem) -> some View {
        let minutes = task.nextStepMinutes ?? 10
        return HStack(spacing: 10) {
            Button {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                store.setDone(task.id, true)
                dismiss()
            } label: {
                Label("Erledigt", systemImage: "checkmark")
            }
            .buttonStyle(SoftButtonStyle())

            if store.data.focus == nil {
                Button {
                    commitTitle()
                    store.quickStart(task)
                    dismiss()
                } label: {
                    Label("Anfangen · \(minutes) Min", systemImage: "play.fill")
                }
                .buttonStyle(SolidButtonStyle())
                .contextMenu {
                    ForEach([5, 10, 15, 25, 45], id: \.self) { m in
                        Button("\(m) Minuten") { store.quickStart(task, minutes: m); dismiss() }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(DS.surface.opacity(0.97).ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(DS.line).frame(height: 1) }
    }

    private func addStep() {
        let text = newStep.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            stepFocused = false
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { store.addStep(taskID, text, minutes: newMinutes) }
        newStep = ""
        DispatchQueue.main.async { stepFocused = true }
    }

    private func commitTitle() {
        guard let task, title.trimmingCharacters(in: .whitespacesAndNewlines) != task.title else { return }
        store.renameTask(taskID, title)
    }
}

/// Ein Schritt: abhaken, Text direkt ändern, Minuten antippen.
private struct StepRow: View {
    let taskID: UUID
    let step: SubStep
    @EnvironmentObject private var store: Store
    @State private var text = ""
    @State private var minutes = 5

    var body: some View {
        HStack(spacing: 10) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                store.toggleStep(taskID, step.id)
            } label: {
                CheckBox(done: step.done).scaleEffect(0.85)
            }
            .buttonStyle(.plain)
            TextField("Schritt", text: $text, axis: .vertical)
                .strikethrough(step.done)
                .foregroundStyle(step.done ? DS.muted : DS.ink)
                .onSubmit { store.updateStep(taskID, step.id, title: text) }
            MinuteStepper(minutes: $minutes)
        }
        .onAppear {
            text = step.title
            minutes = step.minutes
        }
        .onChange(of: minutes) { store.updateStep(taskID, step.id, minutes: $0) }
        .onDisappear {
            if text != step.title { store.updateStep(taskID, step.id, title: text) }
        }
    }
}

/// Minuten mit − und + (übliche Stufen: 1, 2, 3, 5, 10, 15 … 120) – ohne Ausklapp-Menü.
struct MinuteStepper: View {
    @Binding var minutes: Int

    private static let steps = [1, 2, 3, 5, 10, 15, 20, 25, 30, 45, 60, 90, 120]

    var body: some View {
        HStack(spacing: 0) {
            button("minus", enabled: minutes > Self.steps[0]) {
                minutes = Self.steps.last { $0 < minutes } ?? Self.steps[0]
            }
            Text("\(minutes) Min")
                .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                .foregroundStyle(DS.purpleMuted)
                .frame(minWidth: 50)
            button("plus", enabled: minutes < Self.steps[Self.steps.count - 1]) {
                minutes = Self.steps.first { $0 > minutes } ?? Self.steps[Self.steps.count - 1]
            }
        }
        .frame(height: 32)
        .background(Color(hex: 0x2A1A34), in: Capsule())
    }

    private func button(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(enabled ? DS.purpleMuted : DS.faint)
                .frame(width: 30, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
