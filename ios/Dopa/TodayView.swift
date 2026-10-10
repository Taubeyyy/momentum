import SwiftUI

/// „Heute“ – aufgeräumt für ADHS: oben ein Satz von Dot, darunter genau eine
/// „Jetzt“-Karte mit der nächsten Aktion, dann Gewohnheiten, Als Nächstes und drei Aufgaben.
/// Jeder Block ist eine ruhige Karte; alles Seltene liegt eine Ebene tiefer.
struct TodayView: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var health = Health.shared
    @State private var opened: TaskItem?
    @State private var showMorning = false
    @State private var showEvening = false

    var body: some View {
        NavigationStack {
            DopaScreen(eyebrow: DateText.today(), title: "Heute", tab: .today) {
                VStack(spacing: 14) {
                    UpdateBanner()
                    DotGreeting()

                    if let run = store.data.focus {
                        FocusCard(run: run,
                                  onDone: { store.stopFocus(completed: true); haptic() },
                                  onExtend: { store.extendFocus(minutes: store.data.reminders.extendMinutes) },
                                  onStop: { store.stopFocus(completed: false) })
                            .transition(.scale(scale: 0.96).combined(with: .opacity))
                    } else {
                        NowCard(onMorning: { showMorning = true }, onEvening: { showEvening = true })
                            .transition(.opacity)
                    }

                    CheckInCard()

                    // Gewohnheiten ohne eigenen Kasten – eine ruhige Reihe
                    if !store.data.habits.isEmpty {
                        HabitStrip(embedded: true)
                    }

                    // Termine und Aufgaben in einer Karte statt zwei
                    todayCard
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: store.data.focus != nil)
            .navigationDestination(isPresented: $showMorning) { MorningRunView() }
            .navigationDestination(isPresented: $showEvening) { EveningRunView() }
            .sheet(item: $opened) { task in
                TaskDetailSheet(taskID: task.id).environmentObject(store)
            }
        }
    }

    // MARK: Heute noch (Termine + Aufgaben in einer Karte)

    private var todayCard: some View {
        let now = Date()
        let next: [Anchor] = Array(store.todayAnchors().filter { $0.time > now.addingTimeInterval(-5 * 60) }.prefix(3))
        let open = store.todayTasks
        return Card(title: "Heute noch", symbol: "list.bullet") {
            Button(open.count > 3 ? "Alle \(open.count)" : "Alle") { Router.shared.open("aufgaben") }
                .buttonStyle(PillButtonStyle())
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                if !next.isEmpty {
                    upNext(next, now: now)
                    Divider().overlay(DS.line).padding(.vertical, 4)
                }
                tasks
            }
        }
    }

    private func upNext(_ next: [Anchor], now: Date) -> some View {
        VStack(spacing: 0) {
                    ForEach(Array(next.enumerated()), id: \.offset) { i, anchor in
                        if i > 0 { Divider().overlay(DS.line) }
                        HStack(spacing: 12) {
                            Text(ClockTime.string(ClockTime.minutes(of: anchor.time)))
                                .font(.system(size: 14, weight: .bold, design: .rounded)).monospacedDigit()
                                .foregroundStyle(DS.purpleMuted)
                                .frame(width: 50, alignment: .leading)
                            Text(anchor.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.ink).lineLimit(1)
                            Spacer(minLength: 0)
                            Text(anchor.time > now ? "in \(DurationText.until(anchor.time, from: now))" : "jetzt")
                                .font(.system(size: 12)).foregroundStyle(DS.muted)
                        }
                        .frame(minHeight: 46)
                    }
        }
    }

    // MARK: Aufgaben (die ersten drei)

    @ViewBuilder
    private var tasks: some View {
        let open = store.todayTasks
        let one = store.theOne()
        let first: [TaskItem] = one.flatMap { o in open.first { $0.id == o.id } }.map { [$0] } ?? []
        let rest: [TaskItem] = open.filter { $0.id != one?.id }
        let ordered: [TaskItem] = Array((first + rest).prefix(3))
            if ordered.isEmpty {
                Text(store.doneToday.isEmpty ? "Noch nichts für heute geplant." : "Alles für heute erledigt. Der Rest des Tages gehört dir.")
                    .font(.system(size: 14)).foregroundStyle(DS.muted)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(ordered.enumerated()), id: \.element.id) { i, task in
                        if i > 0 { Divider().overlay(DS.line) }
                        TaskLine(task: task, done: false, isOne: task.id == one?.id, lined: false,
                                 onCheck: {
                                     haptic()
                                     withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { store.setDone(task.id, true) }
                                 },
                                 onOpen: { opened = task })
                    }
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: ordered.map(\.id))
            }
    }

    private func haptic() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

/// Ein Satz von Dot passend zur Tageszeit – ohne Kasten, nur Avatar und Text.
struct DotGreeting: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var server = Server.shared
    @ObservedObject private var health = Health.shared

    /// Leise Zeile von der Uhr: „6:40 Std Schlaf · 3.214 Schritte“ – nur mit „Schlaf & Bewegung“ an.
    /// Seit Build 61 aus: „Heute“ war zu voll. Dot kennt Schlaf/Schritte trotzdem, die Zahlen stehen unter Mehr → Schlaf.
    private let showWatchLine = false

    private var bodyLine: String? {
        guard store.data.reminders.sleepOn else { return nil }
        var parts: [String] = []
        if let sleep = health.sleepLastNight { parts.append("\(Timing.hoursText(sleep)) Schlaf") }
        if let steps = health.stepsToday { parts.append("\(Timing.thousands(steps)) Schritte") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Antippen öffnet das Gespräch mit Dot – nur, wenn der Server mit KI da ist.
    var body: some View {
        if server.isConnected && server.aiAvailable {
            NavigationLink { DotChatPage() } label: {
                HStack(spacing: 8) {
                    greeting
                    Image(systemName: "bubble.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.faint)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .contextMenu { quickMenu }
            .accessibilityHint("Mit \(store.dotName) reden – lange drücken für Schnellstart")
        } else {
            greeting
                .contextMenu { timerButton }
        }
    }

    /// Lange drücken: direkt mit einer Frage ins Gespräch springen oder einen kurzen Timer starten.
    @ViewBuilder private var quickMenu: some View {
        Button { ask("Was soll ich jetzt machen? Eine Sache.") } label: {
            Label("Was jetzt?", systemImage: "sparkles")
        }
        Button { ask("Ich komm nicht in die Gänge. Gib mir einen winzigen ersten Schritt.") } label: {
            Label("Hilf mir anfangen", systemImage: "figure.walk")
        }
        Button { ask("Plan mir locker den Rest vom Tag, mit Pausen.") } label: {
            Label("Rest vom Tag planen", systemImage: "calendar.day.timeline.left")
        }
        timerButton
    }

    @ViewBuilder private var timerButton: some View {
        if store.data.focus == nil {
            Button {
                store.startFocus(taskID: nil, title: "Fokus", step: "", minutes: 10)
                Toaster.shared.show("10 Minuten laufen – \(store.dotName) passt auf")
            } label: {
                Label("10 Minuten Fokus", systemImage: "timer")
            }
        }
    }

    private func ask(_ text: String) {
        Router.shared.showMore(.dot)
        Task { await store.sendToDot(text) }
    }

    private var greeting: some View {
        TimelineView(.everyMinute) { context in
            let phase = store.phase(at: context.date)
            HStack(alignment: .center, spacing: 12) {
                DotView(level: store.level, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.title(phase))
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(DS.purpleMuted)
                    Text(store.dotLine(phase, at: context.date))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(DS.ink)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if showWatchLine, let watchText = bodyLine {
                        Text(watchText)
                            .font(.system(size: 12)).foregroundStyle(DS.muted).monospacedDigit()
                            .padding(.top, 2)
                            .transition(.opacity)
                    }
                }
                Spacer(minLength: 0)
            }
            .animation(.easeInOut(duration: 0.35), value: phase)
        }
    }

    static func title(_ phase: DayPhase) -> String {
        switch phase {
        case .morning: "Guten Morgen"
        case .day: "Hey"
        case .evening: "Guten Abend"
        case .night: "Spät geworden"
        }
    }
}

/// Die eine Karte mit dem, was jetzt dran ist – je nach Tageszeit.
/// Morgen: Termine, das Eine, Checkliste. Tag: nächster Fixpunkt, Essen, das Eine.
/// Abend: Rückblick ohne Bewertung, morgen das Eine, Abendroutine. Nacht: nur das Nötigste.
struct NowCard: View {
    @EnvironmentObject private var store: Store
    let onMorning: () -> Void
    let onEvening: () -> Void
    @State private var oneText = ""
    @FocusState private var oneFocused: Bool

    var body: some View {
        TimelineView(.everyMinute) { context in
            let phase = store.phase(at: context.date)
            Card(title: Self.title(phase), symbol: Self.symbol(phase)) {
                VStack(alignment: .leading, spacing: 14) {
                    content(phase, now: context.date)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: phase)
        }
    }

    static func title(_ phase: DayPhase) -> String {
        switch phase {
        case .morning: "Dein Morgen"
        case .day: "Jetzt"
        case .evening: "Dein Abend"
        case .night: "Runterfahren"
        }
    }

    static func symbol(_ phase: DayPhase) -> String {
        switch phase {
        case .morning: "sunrise"
        case .day: "bolt"
        case .evening: "sunset"
        case .night: "moon"
        }
    }

    @ViewBuilder
    private func content(_ phase: DayPhase, now: Date) -> some View {
        switch phase {
        case .morning:
            let facts = store.briefingFacts(for: now).filter { !$0.hasPrefix("Das Eine") }
            if !facts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(facts, id: \.self) { line in fact(line, symbol: "circle.fill", small: true) }
                }
            }
            oneBlock(for: now, prompt: "Was ist heute das Eine?")
            let m = store.morning
            if !m.isDone && !m.steps.isEmpty {
                Button(action: onMorning) {
                    Label(m.untimed && m.startedAt == nil ? "Morgen-Routine starten – ohne Uhr"
                          : "Morgen-Checkliste · \(m.checked.count)/\(m.steps.count)", systemImage: "sunrise")
                }
                .buttonStyle(SoftButtonStyle())
            }
        case .day:
            if let next = store.todayAnchors().first(where: { $0.time > now }) {
                fact("\(ClockTime.string(ClockTime.minutes(of: next.time))) \(next.title) · in \(DurationText.until(next.time, from: now))",
                     symbol: "clock")
            }
            if store.mealsToday == 0 && Calendar.current.component(.hour, from: now) >= 12 {
                HStack {
                    fact("Schon was gegessen heute?", symbol: "fork.knife")
                    Spacer()
                    Button("Gegessen") {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        store.mealEaten()
                    }
                    .buttonStyle(PillButtonStyle(prominent: true))
                }
            }
            oneBlock(for: now, prompt: "Was ist heute das Eine?")
        case .evening:
            let stats = store.reviewLine
            if !stats.isEmpty { fact("Heute: \(stats)", symbol: "checkmark.circle") }
            tomorrowBlock
            let e = store.evening
            if !e.isDone {
                Button(action: onEvening) {
                    Label("Abendroutine · \(e.checked.count)/\(e.steps.count)", systemImage: "moon")
                }
                .buttonStyle(SoftButtonStyle())
            }
        case .night:
            tomorrowBlock
            if !store.evening.isDone {
                Button(action: onEvening) { Label("Abendroutine – nur das Nötigste", systemImage: "moon") }
                    .buttonStyle(SoftButtonStyle())
            }
        }
    }

    /// Das Eine für heute: groß, mit genau einer Aktion – oder festlegen.
    @ViewBuilder
    private func oneBlock(for day: Date, prompt: String) -> some View {
        if let one = store.theOne(on: day) {
            if one.doneAt != nil {
                fact("Das Eine ist erledigt: \(one.title)", symbol: "checkmark.seal")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DAS EINE").font(.system(size: 10, weight: .heavy)).tracking(0.7).foregroundStyle(DS.faint)
                        Text(one.title).font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(DS.ink)
                        if !one.nextStep.isEmpty {
                            Text(one.nextStepMinutes.map { "\(one.nextStep) · \($0) Min" } ?? one.nextStep)
                                .font(.system(size: 13)).foregroundStyle(DS.muted)
                        }
                    }
                    if store.data.focus == nil {
                        Button { store.quickStart(one) } label: {
                            Label("Anfangen", systemImage: "play.fill")
                        }
                        .buttonStyle(SolidButtonStyle())
                    }
                }
            }
        } else {
            oneField(prompt: prompt) { store.setTheOne($0, for: day) }
        }
    }

    @ViewBuilder
    private var tomorrowBlock: some View {
        let target = store.reviewTargetDay
        if let one = store.theOne(on: target) {
            fact("Morgen das Eine: \(one.title)", symbol: "arrow.right.circle")
        } else {
            oneField(prompt: "Was ist morgen das Eine?") { store.setTheOne($0, for: target) }
        }
    }

    private func oneField(prompt: String, onSet: @escaping (String) -> Void) -> some View {
        CaptureField(placeholder: prompt, text: $oneText, focus: $oneFocused) {
            let text = oneText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { onSet(text) }
            oneText = ""
            oneFocused = false
        }
    }

    private func fact(_ text: String, symbol: String, small: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: small ? 5 : 12, weight: .semibold))
                .foregroundStyle(DS.purpleMuted)
                .frame(width: 14)
            Text(text).font(.system(size: 14)).foregroundStyle(Color(hex: 0xC5BDCA))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
