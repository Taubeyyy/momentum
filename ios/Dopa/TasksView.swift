import SwiftUI
import UniformTypeIdentifiers

/// „Aufgaben“ – aufgeräumt: oben eintippen, darunter eine schmale Werkzeug-Leiste,
/// dann nach Planung gruppiert (Heute · Morgen · Später · Irgendwann).
/// Antippen öffnet die Aufgabe (planen, Schritte mit Minuten, anfangen).
struct TasksView: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var router = Router.shared
    @ObservedObject private var server = Server.shared
    @State private var newTask = ""
    @State private var opened: TaskItem?
    @State private var freeStart = false
    @State private var showPlan = false
    @State private var showAudio = false
    @State private var showWords = false
    @State private var showWhatNow = false
    @State private var choosingPhoto = false
    @State private var photo: PickedImage?
    @State private var completing: Set<UUID> = []   // gerade abgehakt, rutscht gleich weg
    @State private var draggingTask: UUID?
    @AppStorage("reorderHintSeen") private var reorderHintSeen = false
    @FocusState private var inputFocused: Bool

    /// Das Eine für heute steht immer oben.
    private var todayList: [TaskItem] {
        let open = store.todayTasks
        guard let one = store.theOne(), let first = open.first(where: { $0.id == one.id }) else { return open }
        return [first] + open.filter { $0.id != one.id }
    }

    private var tomorrowList: [TaskItem] {
        store.upcomingTasks.filter { $0.dueDay.map(Calendar.current.isDateInTomorrow) ?? false }
    }

    private var laterList: [TaskItem] {
        store.upcomingTasks.filter { !($0.dueDay.map(Calendar.current.isDateInTomorrow) ?? false) }
    }

    var body: some View {
        NavigationStack {
            DopaScreen(eyebrow: DateText.today(), title: "Aufgaben", tab: .tasks) {
                DoSwitch()
                if let run = store.data.focus {
                    FocusPill(run: run) { Router.shared.go(.today) }
                        .padding(.bottom, 12)
                }

                CaptureField(placeholder: "Neue Aufgabe – Enter, nächste", text: $newTask, focus: $inputFocused, onSubmit: addTask)
                toolBar.padding(.top, 12)

                group("Heute", tasks: todayList, reorder: true) {
                    if todayList.isEmpty && store.doneToday.isEmpty {
                        EmptyState(symbol: "", title: "Noch nichts für heute",
                                   text: "Ein Wort reicht. Antippen öffnet die Aufgabe – dort planst du sie und legst Schritte mit Minuten an.")
                    }
                    doneRow
                }
                group("Morgen", tasks: tomorrowList)
                group("Später", tasks: laterList, showDate: true)
                somedayGroup
            }
            .sheet(item: $opened) { task in
                TaskDetailSheet(taskID: task.id).environmentObject(store)
            }
            .sheet(isPresented: $freeStart) {
                StartSheet(fixedTitle: nil, initialStep: "") { title, step, minutes in
                    store.startFocus(taskID: nil, title: title, step: step, minutes: minutes)
                }
                .environmentObject(store)
            }
            .sheet(isPresented: $showPlan) { PlanSheet().environmentObject(store) }
            .sheet(isPresented: $showWords) { WordsSheet() }
            .sheet(isPresented: $showAudio) { AudioDumpSheet().environmentObject(store) }
            .sheet(isPresented: $showWhatNow) {
                NavigationStack {
                    ScrollView {
                        WhatNowPanel(startsOpen: true) { task, step, minutes in
                            store.startFocus(taskID: task.id, title: task.title, step: step, minutes: minutes)
                            showWhatNow = false
                        }
                        .padding(20)
                    }
                    .background(DS.surface.ignoresSafeArea())
                    .navigationTitle("Was jetzt?")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Fertig") { showWhatNow = false } }
                    }
                }
                .environmentObject(store)
                .presentationDetents([.medium, .large])
            }
            .photoSource(isPresented: $choosingPhoto, title: "Brief, Zettel oder Whiteboard") { photo = PickedImage(image: $0) }
            .sheet(item: $photo) { picked in
                PhotoDumpSheet(image: picked.image).environmentObject(store)
            }
            .onAppear(perform: handleStartRequest)
            .onChange(of: router.startTask) { _ in handleStartRequest() }
        }
    }

    // MARK: Werkzeuge als schmale Leiste

    /// Eine laute Sache („Was jetzt?“), der Timer, alles Seltene im „Mehr“-Menü.
    private var toolBar: some View {
        HStack(spacing: 6) {
            tool("Was jetzt?", symbol: "sparkles", prominent: true) { showWhatNow = true }
            if store.data.focus == nil {
                tool("Timer", symbol: "timer") { freeStart = true }
            }
            if server.isConnected && server.aiAvailable {
                Menu {
                    Button { choosingPhoto = true } label: { Label("Aus einem Foto", systemImage: "camera") }
                    Button { showAudio = true } label: { Label("Erzählen (Audio)", systemImage: "mic") }
                    Button { showPlan = true } label: { Label("Plan aus Text", systemImage: "text.alignleft") }
                    Button { showWords = true } label: { Label("Worte finden", systemImage: "text.bubble") }
                } label: {
                    Label("Mehr", systemImage: "ellipsis.circle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xC5BDCA))
                        .padding(.horizontal, 13)
                        .frame(height: 36)
                        .background(DS.raised, in: Capsule())
                        .overlay(Capsule().stroke(DS.line))
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func tool(_ title: String, symbol: String, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(prominent ? .white : Color(hex: 0xC5BDCA))
                .padding(.horizontal, 13)
                .frame(height: 36)
                .background(prominent ? store.theme.accent : DS.raised, in: Capsule())
                .overlay(Capsule().stroke(prominent ? .clear : DS.line))
        }
        .buttonStyle(PressStyle())
    }

    // MARK: Gruppen

    @ViewBuilder
    private func group<Footer: View>(_ title: String, tasks: [TaskItem], reorder: Bool = false, showDate: Bool = false,
                                     @ViewBuilder footer: () -> Footer = { EmptyView() }) -> some View {
        if !tasks.isEmpty || title == "Heute" {
            SectionHeading(title: title) {
                if !tasks.isEmpty {
                    let minutes = tasks.reduce(0) { $0 + $1.minutesLeft }
                    HeadingCount(text: minutes > 0 ? "\(tasks.count) · ca. \(minutes) Min" : "\(tasks.count)")
                }
            }
            if !tasks.isEmpty {
                HairlineList {
                    ForEach(tasks) { task in
                        row(task, reorder: reorder, showDate: showDate)
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: tasks.map(\.id))
            }
            footer()
        }
    }

    @ViewBuilder
    private func row(_ task: TaskItem, reorder: Bool, showDate: Bool) -> some View {
        let line = TaskLine(task: task, done: completing.contains(task.id), isOne: task.id == store.theOne()?.id,
                            dateLabel: showDate ? task.dueDay.map { DayLabel.text(for: $0) } : nil,
                            onCheck: { complete(task) },
                            onOpen: { opened = task })
            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
            .contextMenu { menu(task) }
        if reorder {
            line
                .opacity(draggingTask == task.id ? 0.4 : 1)
                .onDrag {
                    draggingTask = task.id
                    reorderHintSeen = true
                    return NSItemProvider(object: task.id.uuidString as NSString)
                }
                .onDrop(of: [UTType.plainText],
                        delegate: ReorderDrop(target: task.id, dragging: $draggingTask) { store.reorderTask($0, to: $1) })
        } else {
            line
        }
    }

    @ViewBuilder
    private func menu(_ task: TaskItem) -> some View {
        Button { complete(task) } label: { Label("Erledigt", systemImage: "checkmark") }
        if store.data.focus == nil {
            Button { store.quickStart(task) } label: { Label("Anfangen", systemImage: "play") }
        }
        if task.id != store.theOne()?.id {
            Button { store.makeTheOne(task.id) } label: { Label("Das Eine für heute", systemImage: "star") }
        }
        if task.steps.isEmpty {
            Button {
                withAnimation(Motion.list) { store.setShowStep(task.id, !task.showStep) }
            } label: {
                Label(task.showStep ? "Mini-Schritt ausblenden" : "Mini-Schritt zeigen",
                      systemImage: task.showStep ? "eye.slash" : "figure.walk")
            }
        }
        Menu {
            Button("Heute") { withAnimation { store.setPlan(task.id, .today) } }
            Button("Morgen") { withAnimation { store.setPlan(task.id, .tomorrow) } }
            Button("Irgendwann") { withAnimation { store.setPlan(task.id, .someday) } }
        } label: {
            Label("Planen", systemImage: "calendar")
        }
        Button(role: .destructive) {
            withAnimation(.easeOut(duration: 0.2)) { store.deleteTask(task.id) }
        } label: { Label("Löschen", systemImage: "trash") }
    }

    /// „Erledigt heute“ – eingeklappt unter Heute.
    @ViewBuilder
    private var doneRow: some View {
        let done = store.doneToday
        if !done.isEmpty {
            Text("ERLEDIGT HEUTE · \(done.count)")
                .font(.system(size: 10, weight: .heavy)).tracking(0.7).foregroundStyle(DS.faint)
                .padding(.top, 16)
                .padding(.bottom, 4)
            HairlineList {
                ForEach(done) { task in
                    TaskLine(task: task, done: true,
                             onCheck: { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { store.setDone(task.id, false) } },
                             onOpen: { opened = task })
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .animation(Motion.list, value: done.map(\.id))
        }
        if todayList.count >= 2 && !reorderHintSeen {
            Text("Tipp: gedrückt halten und ziehen = eigene Reihenfolge.")
                .font(.system(size: 11)).foregroundStyle(DS.faint)
                .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var somedayGroup: some View {
        let someday = store.somedayTasks
        if !someday.isEmpty {
            SectionHeading(title: "Irgendwann") { HeadingCount(text: "\(someday.count)") }
            HairlineList {
                ForEach(someday) { task in row(task, reorder: false, showDate: false) }
            }
            .animation(Motion.list, value: someday.map(\.id))
        }
    }

    // MARK: Aktionen

    /// Vom „Als Nächstes“-Widget: direkt die Aufgabe öffnen.
    private func handleStartRequest() {
        guard let id = router.startTask else { return }
        router.startTask = nil
        guard let task = store.data.tasks.first(where: { $0.id == id && $0.doneAt == nil }) else { return }
        opened = task
    }

    /// Enter fügt hinzu und lässt die Tastatur offen; Enter auf leerem Feld schließt sie.
    private func addTask() {
        let text = newTask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            inputFocused = false
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { store.addTask(text) }
        newTask = ""
        DispatchQueue.main.async { inputFocused = true }
    }

    /// Häkchen sofort zeigen, Zeile erst kurz danach wegrutschen lassen – fühlt sich nach „geschafft“ an.
    private func complete(_ task: TaskItem) {
        guard !completing.contains(task.id) else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        completing.insert(task.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                store.setDone(task.id, true)
            }
            completing.remove(task.id)
        }
    }
}

/// Eine Aufgabe: Häkchen, Titel, erster Schritt, Pfeil. Zeile antippen = anfangen.
struct TaskLine: View {
    let task: TaskItem
    let done: Bool
    var isOne = false
    var dateLabel: String?
    var lined = true                        // in Karten ohne eigene Haarlinie
    let onCheck: () -> Void
    let onOpen: () -> Void

    /// „Morgen · 2/5 · Wäsche sortieren · 10 Min“
    private var subtitle: String? {
        var parts: [String] = []
        if let dateLabel { parts.append(dateLabel) }
        if let at = task.remindAt { parts.append("um \(Timing.clock(at))") }
        if let spot = Store.shared.spot(task.spotID) { parts.append("bei \(spot.name)") }
        if task.steps.isEmpty {
            // Mini-Schritt nur, wenn du ihn sehen willst (Aufgabe öffnen → „Mini-Schritt zeigen“)
            if task.showStep && !task.firstStep.isEmpty { parts.append(task.firstStep) }
        } else {
            parts.append("\(task.steps.filter(\.done).count)/\(task.steps.count)")
            if let minutes = task.nextStepMinutes { parts.append("\(task.nextStep) · \(minutes) Min") }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onCheck) {
                CheckBox(done: done)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, -9)
            .accessibilityLabel(done ? "Wieder öffnen" : "Als erledigt markieren")
            VStack(alignment: .leading, spacing: 4) {
                if isOne && !done {
                    Text("DAS EINE").font(.system(size: 9, weight: .heavy)).tracking(0.8).foregroundStyle(DS.purpleMuted)
                }
                Text(task.title)
                    .font(.system(size: 15, weight: .semibold))
                    .strikethrough(done)
                    .foregroundStyle(DS.ink)
                if !done, let subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(DS.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if !done {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: 0x615A65))
            }
        }
        .padding(.vertical, 6)
        .modifier(RowLine(lined: lined))
        .opacity(done ? 0.48 : 1)
        .animation(.easeOut(duration: 0.2), value: done)
        .onTapGesture(perform: onOpen)
    }
}

/// Haarlinie unter der Zeile – oder ohne, wenn die Zeile in einer Karte sitzt.
struct RowLine: ViewModifier {
    let lined: Bool

    func body(content: Content) -> some View {
        if lined {
            content.hairlineRow()
        } else {
            content.frame(maxWidth: .infinity, minHeight: 56, alignment: .leading).contentShape(Rectangle())
        }
    }
}

// MARK: - Was jetzt?

/// Klappt auf: Energie wählen → ein Vorschlag mit Begründung → „Los“.
/// Mit KI wählt Gemini, sonst eine der ältesten passenden Aufgaben.
struct WhatNowPanel: View {
    var startsOpen = false
    let onStart: (_ task: TaskItem, _ step: String, _ minutes: Int) -> Void
    @EnvironmentObject private var store: Store
    @ObservedObject private var server = Server.shared
    @State private var open = false
    @State private var energy: String?
    @State private var suggestion: Suggestion?
    @State private var busy = false
    @State private var error: String?

    struct Suggestion {
        let task: TaskItem
        let step: String
        let why: String
        let minutes: Int
    }

    private struct EnergyOption: Identifiable { let id: String; let label: String; let level: Int }
    private let energies = [
        EnergyOption(id: "low", label: "Wenig", level: 1),
        EnergyOption(id: "med", label: "Mittel", level: 2),
        EnergyOption(id: "high", label: "Viel", level: 3),
    ]

    var body: some View {
        panel.onAppear {
            // als eigenes Fenster: gleich offen, mit der Energie aus dem Check-in
            guard startsOpen, !open else { return }
            open = true
            if let checked = store.todayCheckIn?.energy { choose(checked) }
        }
    }

    private var panel: some View {
        Panel(highlighted: open) {
            VStack(spacing: 0) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { open.toggle() }
                    energy = nil
                    suggestion = nil
                    // Heute schon eingecheckt? Dann gleich passend vorschlagen.
                    if open, let checked = store.todayCheckIn?.energy { choose(checked) }
                } label: {
                    HStack(spacing: 12) {
                        Text("?")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(store.theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Was jetzt?").font(.system(size: 16, weight: .semibold)).foregroundStyle(DS.ink)
                            Text("Eine Aufgabe passend zu deiner Energie").font(.system(size: 12)).foregroundStyle(DS.muted)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x826E8D))
                            .rotationEffect(.degrees(open ? 90 : 0))
                    }
                    .padding(13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if open {
                    Rectangle().fill(DS.line).frame(height: 1)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Wie viel Energie ist gerade da?")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xC5BDCA))
                            .padding(.top, 14)
                        HStack(spacing: 7) {
                            ForEach(energies) { option in
                                EnergyButton(label: option.label, level: option.level,
                                             selected: energy == option.id) { choose(option.id) }
                            }
                        }
                        if busy {
                            HStack { Spacer(); ProgressView(); Spacer() }.padding(.vertical, 10)
                        }
                        if let error {
                            Text(error).font(.system(size: 12)).foregroundStyle(DS.muted)
                        }
                        if let s = suggestion {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(s.minutes) MIN.")
                                    .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                                    .foregroundStyle(DS.purpleMuted)
                                Text(s.task.title).font(.system(size: 17, weight: .semibold)).foregroundStyle(DS.ink)
                                Text(s.why).font(.system(size: 13)).foregroundStyle(DS.muted).lineSpacing(2)
                                if !s.step.isEmpty {
                                    Text(s.step).font(.system(size: 13, weight: .medium)).foregroundStyle(Color(hex: 0xC5BDCA))
                                }
                                Button {
                                    onStart(s.task, s.step, s.minutes)
                                    withAnimation { open = false }
                                } label: {
                                    HStack(spacing: 6) { Text("Los"); Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)) }
                                }
                                .buttonStyle(SolidButtonStyle())
                                .padding(.top, 6)
                            }
                            .padding(15)
                            .background(DS.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(DS.line))
                        }
                    }
                    .padding(.horizontal, 13)
                    .padding(.bottom, 14)
                }
            }
        }
    }

    private func choose(_ id: String) {
        energy = id
        suggestion = nil
        error = nil
        let tasks = store.openTasks
        guard !tasks.isEmpty else {
            error = "Keine offenen Aufgaben – schreib unten erst was rein."
            return
        }
        if server.isConnected && server.aiAvailable {
            busy = true
            Task {
                do {
                    let pick = try await server.whatNow(tasks: tasks, energy: id, focusToday: store.focusMinutesToday)
                    if let task = tasks.first(where: { $0.id.uuidString == pick.id }) {
                        suggestion = Suggestion(task: task, step: pick.first_move, why: pick.why, minutes: pick.minutes)
                    }
                } catch {
                    suggestion = localPick(id, tasks)
                }
                busy = false
            }
        } else {
            suggestion = localPick(id, tasks)
        }
    }

    /// Ohne KI: eine der ältesten Aufgaben, Dauer nach Energie.
    private func localPick(_ energy: String, _ tasks: [TaskItem]) -> Suggestion? {
        guard let task = tasks.sorted(by: { $0.createdAt < $1.createdAt }).prefix(3).randomElement() else { return nil }
        let (minutes, why) = switch energy {
        case "low": (5, "Nur der erste Schritt. Danach darfst du aufhören.")
        case "high": (25, "Du hast gerade Schwung – nutz ihn für etwas, das schon lange liegt.")
        default: (10, "Liegt schon eine Weile. Zehn Minuten reichen für einen echten Anfang.")
        }
        return Suggestion(task: task, step: task.firstStep, why: why, minutes: minutes)
    }
}

/// Energie-Knopf mit drei Balken.
private struct EnergyButton: View {
    let label: String
    let level: Int
    let selected: Bool
    let action: () -> Void
    @ObservedObject private var store = Store.shared

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(1...3, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1.5)
                            .frame(width: 3, height: CGFloat(i) * 5)
                            .opacity(i <= level ? 1 : 0.2)
                    }
                }
                .frame(height: 15)
                Text(label).font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(selected ? .white : Color(hex: 0xB9B0BF))
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(selected ? Color(hex: 0x211B2B) : DS.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(selected ? store.theme.accent : DS.chipBorder))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Laufender Timer

/// Kompakt in „Aufgaben“: Timer läuft – antippen = zu „Heute“, wo die große Karte ist.
struct FocusPill: View {
    let run: FocusRun
    let action: () -> Void
    @ObservedObject private var store = Store.shared

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                LiveDot(color: store.theme.accent)
                Text(run.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(DS.ink).lineLimit(1)
                Spacer(minLength: 0)
                Text(timerInterval: run.startedAt...max(run.startedAt, run.endsAt), countsDown: true)
                    .font(.system(size: 14, weight: .bold)).monospacedDigit()
                    .foregroundStyle(DS.purpleMuted)
                    .frame(width: 60, alignment: .trailing)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 46)
            .background(Color(hex: 0x1E1524), in: Capsule())
            .overlay(Capsule().stroke(Color(hex: 0x3A2C42)))
        }
        .buttonStyle(PressStyle())
    }
}

struct FocusCard: View {
    let run: FocusRun
    let onDone: () -> Void
    let onExtend: () -> Void
    let onStop: () -> Void
    @ObservedObject private var store = Store.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let timeUp = context.date >= run.endsAt
            let total = max(1, run.endsAt.timeIntervalSince(run.startedAt))
            let fraction = min(1, max(0, context.date.timeIntervalSince(run.startedAt) / total))
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    if !timeUp { LiveDot(color: store.theme.accent, size: 7) }
                    Text(timeUp ? "ZEIT IST UM" : "LÄUFT")
                        .font(.system(size: 11, weight: .heavy)).tracking(0.6)
                        .foregroundStyle(DS.purpleMuted)
                }
                Text(run.title).font(.system(size: 17, weight: .semibold))
                if !run.step.isEmpty {
                    Text(run.step).font(.system(size: 13)).foregroundStyle(DS.muted)
                }
                if timeUp {
                    Text("Weitermachen oder fertig – beides okay.")
                        .font(.system(size: 13)).foregroundStyle(DS.muted)
                } else {
                    Text(timerInterval: run.startedAt...run.endsAt, countsDown: true)
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(DS.ink)
                    Track(fraction: fraction)
                }
                HStack(spacing: 8) {
                    Button(action: onDone) { Text("Fertig") }
                        .buttonStyle(SolidButtonStyle())
                    Button("+\(store.data.reminders.extendMinutes) Min", action: onExtend)
                        .buttonStyle(SoftButtonStyle())
                    Button("Stopp", action: onStop)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.muted)
                        .frame(width: 64, height: 48)
                        .buttonStyle(.plain)
                }
                .padding(.top, 6)
            }
        }
        .accentCard()
    }
}

/// Datum für die Kopfzeile: „Mittwoch, 1. Oktober“.
enum DateText {
    static func today() -> String { day(Date()) }

    static func day(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEE, d. MMMM"
        return f.string(from: date)
    }
}
