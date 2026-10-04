import SwiftUI
import UniformTypeIdentifiers

/// Leiste in „Heute“: kleine tägliche Dinge mit einem Tipp abhaken.
struct HabitStrip: View {
    var embedded = false                    // in einer Karte: ohne eigene Kopfzeile, „Alle“ als Knopf am Ende
    @EnvironmentObject private var store: Store
    @State private var editing: Habit?
    @State private var confirmMed: Habit?
    @State private var showAll = false
    @State private var dragging: UUID?

    var body: some View {
        if !store.data.habits.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if !embedded {
                    HStack {
                        Text("HEUTE").font(.system(size: 10, weight: .heavy)).tracking(0.7).foregroundStyle(DS.faint)
                        Spacer()
                        Button("Alle") { showAll = true }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DS.purpleMuted)
                            .buttonStyle(PressStyle())
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(store.data.habits) { habit in
                            HabitChip(habit: habit,
                                      count: store.habitCount(habit.id),
                                      lastTick: store.lastTick(habit.id),
                                      onTap: { tap(habit) },
                                      onUndo: { store.untickHabit(habit.id) },
                                      onEdit: { editing = habit })
                                .opacity(dragging == habit.id ? 0.4 : 1)
                                .onDrag {
                                    dragging = habit.id
                                    return NSItemProvider(object: habit.id.uuidString as NSString)
                                }
                                .onDrop(of: [UTType.plainText],
                                        delegate: ReorderDrop(target: habit.id, dragging: $dragging) { store.reorderHabit($0, to: $1) })
                        }
                        if embedded {
                            Button { showAll = true } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: "ellipsis")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundStyle(DS.muted)
                                        .frame(width: 48, height: 48)
                                        .background(DS.field, in: Circle())
                                    Text("Alle").font(.system(size: 11, weight: .semibold)).foregroundStyle(DS.muted)
                                    Text(" ").font(.system(size: 10))
                                }
                                .frame(width: 60)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(PressStyle())
                        }
                    }
                }
            }
            .confirmationDialog(confirmText, isPresented: Binding(
                get: { confirmMed != nil }, set: { if !$0 { confirmMed = nil } }
            ), titleVisibility: .visible) {
                Button("Trotzdem eintragen") {
                    if let habit = confirmMed { store.tickHabit(habit.id) }
                }
                Button("Abbrechen", role: .cancel) {}
            }
            .sheet(item: $editing) { habit in
                HabitEditor(habit: habit).environmentObject(store)
            }
            .sheet(isPresented: $showAll) {
                NavigationStack {
                    HabitsPage()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("Fertig") { showAll = false } }
                        }
                }
                .environmentObject(store)
            }
        }
    }

    private var confirmText: String {
        guard let habit = confirmMed, let last = store.lastTick(habit.id) else { return "Schon eingetragen" }
        return "\(habit.title): heute schon um \(ClockTime.string(ClockTime.minutes(of: last))) eingetragen."
    }

    /// Tabletten schon genommen? Erst fragen – doppelt nehmen ist das Letzte, was du willst.
    private func tap(_ habit: Habit) {
        if habit.isMed && store.habitCount(habit.id) >= habit.perDay {
            confirmMed = habit
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        store.tickHabit(habit.id)
    }
}

/// Runder Knopf: Ring zeigt den Tagesfortschritt.
struct HabitChip: View {
    let habit: Habit
    let count: Int
    let lastTick: Date?
    let onTap: () -> Void
    let onUndo: () -> Void
    let onEdit: () -> Void
    @ObservedObject private var store = Store.shared

    private var done: Bool { count >= habit.perDay }

    private var subtitle: String {
        if habit.isMed {
            return lastTick.map { "um \(ClockTime.string(ClockTime.minutes(of: $0)))" } ?? "offen"
        }
        return "\(count)/\(habit.perDay)"
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                ZStack {
                    Circle().fill(done ? store.theme.accent : DS.field)
                    Circle().stroke(Color(hex: 0x352A3B), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: min(1, CGFloat(count) / CGFloat(max(1, habit.perDay))))
                        .stroke(store.theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: done && habit.perDay == 1 ? "checkmark" : habit.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(done ? .white : DS.purpleMuted)
                        .id(done && habit.perDay == 1)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
                .frame(width: 48, height: 48)
                .popOnChange(of: count, scale: 1.12)
                .pulseOnTrue(done, color: store.theme.accent, cornerRadius: 24)
                Text(habit.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.ink)
                    .lineLimit(1)
                RollingText(text: subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(DS.muted)
                    .monospacedDigit()
            }
            .frame(width: 72)
            .padding(.vertical, 4)
        }
        .buttonStyle(PressStyle())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: count)
        .contextMenu {
            Button(action: onUndo) { Label("Einen zurück", systemImage: "arrow.uturn.backward") }
                .disabled(count == 0)
            Button(action: onEdit) { Label("Bearbeiten", systemImage: "pencil") }
        }
        .accessibilityLabel("\(habit.title), \(subtitle)")
    }
}

/// Alle Gewohnheiten: Woche als Punkte (ohne Streak), bearbeiten, sortieren, neu.
struct HabitsPage: View {
    @EnvironmentObject private var store: Store
    @State private var editing: Habit?

    /// Mo–So der aktuellen Woche.
    private var week: [Date] {
        let cal = Calendar(identifier: .iso8601)
        let start = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        List {
            if !store.data.habits.isEmpty {
                Section {
                    HStack(spacing: 0) {
                        Text("").frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(week, id: \.self) { day in
                            Text(Self.weekday.string(from: day).uppercased())
                                .font(.system(size: 9, weight: .heavy))
                                .foregroundStyle(Calendar.current.isDateInToday(day) ? DS.purpleMuted : DS.faint)
                                .frame(width: 26)
                        }
                    }
                    ForEach(store.data.habits) { habit in
                        HStack(spacing: 0) {
                            Label(habit.title, systemImage: habit.symbol)
                                .font(.system(size: 14))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            ForEach(week, id: \.self) { day in
                                dot(store.habitCount(habit.id, on: day), of: habit.perDay, future: day > Date())
                                    .frame(width: 26)
                            }
                        }
                    }
                } header: {
                    Text("Diese Woche")
                } footer: {
                    Text("Kein Streak, keine roten Tage. Ein verpasster Tag ist einfach ein Tag.")
                }
                .dopaRow()
            }

            Section {
                ForEach(store.data.habits) { habit in
                    Button { editing = habit } label: {
                        HStack(spacing: 12) {
                            Image(systemName: habit.symbol).foregroundStyle(DS.purpleMuted).frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(habit.title).foregroundStyle(DS.ink)
                                Text(detail(habit)).font(.caption).foregroundStyle(DS.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(DS.faint)
                        }
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.map { store.data.habits[$0].id }
                    for id in ids { store.deleteHabit(id) }
                }
                .onMove { store.moveHabits(from: $0, to: $1) }

                Button {
                    editing = Habit(title: "", symbol: "checkmark")
                } label: {
                    Label("Neue Gewohnheit", systemImage: "plus")
                }
            } header: {
                Text("Deine Gewohnheiten")
            } footer: {
                Text("In „Heute“: gedrückt halten = Haken zurück oder bearbeiten; gedrückt halten und ziehen = Reihenfolge.")
            }
            .dopaRow()
        }
        .dopaBackground()
        .navigationTitle("Gewohnheiten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar { ToolbarItem(placement: .navigationBarLeading) { EditButton() } }
        .sheet(item: $editing) { habit in
            HabitEditor(habit: habit).environmentObject(store)
        }
    }

    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEEEE"
        return f
    }()

    private func detail(_ habit: Habit) -> String {
        var parts = [habit.perDay == 1 ? "1× am Tag" : "\(habit.perDay)× am Tag"]
        if habit.isMed { parts.append("Tablette") }
        if let at = habit.remindAt { parts.append("Erinnerung \(ClockTime.string(at))") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func dot(_ count: Int, of target: Int, future: Bool) -> some View {
        let fraction = min(1, Double(count) / Double(max(1, target)))
        Circle()
            .fill(fraction >= 1 ? store.theme.accent : fraction > 0 ? store.theme.accent.opacity(0.4) : Color(hex: 0x2A2530))
            .frame(width: 12, height: 12)
            .opacity(future ? 0.35 : 1)
    }
}

/// Gewohnheit anlegen oder ändern.
struct HabitEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var habit: Habit

    private static let symbols = ["drop", "pills", "figure.walk", "sparkles", "fork.knife", "bed.double",
                                  "book", "leaf", "sun.max", "heart", "music.note", "cup.and.saucer",
                                  "tshirt", "bolt", "brain.head.profile", "checkmark"]

    private var isNew: Bool { !store.data.habits.contains { $0.id == habit.id } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Was? z. B. Wasser, Tabletten, Kurz raus", text: $habit.title)
                    Stepper(habit.perDay == 1 ? "1× am Tag" : "\(habit.perDay)× am Tag", value: $habit.perDay, in: 1...12)
                }
                .dopaRow()

                Section("Symbol") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                        ForEach(Self.symbols, id: \.self) { symbol in
                            Button { habit.symbol = symbol } label: {
                                Image(systemName: symbol)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(habit.symbol == symbol ? .white : DS.purpleMuted)
                                    .frame(width: 44, height: 44)
                                    .background(habit.symbol == symbol ? store.theme.accent : DS.field,
                                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .dopaRow()

                Section {
                    Toggle("Ist ein Medikament", isOn: $habit.isMed)
                } footer: {
                    Text("Zeigt, um wie viel Uhr du es genommen hast, fragt nach, bevor du es doppelt einträgst, und legt es in „Notizen“ ab.")
                }
                .dopaRow()

                Section {
                    Toggle("Erinnern", isOn: Binding(
                        get: { habit.remindAt != nil },
                        set: { habit.remindAt = $0 ? (habit.remindAt ?? 8 * 60) : nil }))
                    if habit.remindAt != nil {
                        TimeRow(label: "Um", minutes: Binding(
                            get: { habit.remindAt ?? 8 * 60 },
                            set: { habit.remindAt = $0 }))
                    }
                } footer: {
                    Text("Mit Dranbleiben fragt Dopa nach deinen Dranbleiben-Zeiten nochmal, bis es abgehakt ist – direkt aus der Benachrichtigung.")
                }
                .dopaRow()

                Section {
                    Toggle("Mit Schritten abhaken", isOn: Binding(
                        get: { habit.stepGoal != nil },
                        set: { on in
                            habit.stepGoal = on ? (habit.stepGoal ?? 5000) : nil
                            if on { Task { @MainActor in _ = await Health.shared.requestAccess() } }
                        }))
                    if let goal = habit.stepGoal {
                        Stepper("Ab \(goal) Schritten", value: Binding(
                            get: { habit.stepGoal ?? 5000 },
                            set: { habit.stepGoal = $0 }), in: 500...30000, step: 500)
                    }
                } header: {
                    Text("Apple Watch")
                } footer: {
                    Text("Zählt die Uhr (über Health) so viele Schritte, hakt sich das von selbst ab – sobald du Dopa öffnest.")
                }
                .dopaRow()

                if !isNew {
                    Section {
                        Button("Gewohnheit löschen", role: .destructive) {
                            store.deleteHabit(habit.id)
                            dismiss()
                        }
                    }
                    .dopaRow()
                }
            }
            .dopaBackground()
            .navigationTitle(isNew ? "Neue Gewohnheit" : habit.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        habit.title = habit.title.trimmingCharacters(in: .whitespaces)
                        store.saveHabit(habit)
                        dismiss()
                    }
                    .disabled(habit.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
