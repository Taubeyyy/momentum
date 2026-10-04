import SwiftUI

// Dot – der Punkt aus dem Logo als Assistent. Wächst mit dem Level, wird nie traurig.

/// Wachstumsstufen: Funke → Ring → Trabanten → zweiter Ring → Sternbild.
enum DotStage: Int {
    case spark = 0, ring, orbit, halo, constellation

    static func of(level: Int) -> DotStage {
        switch level {
        case ..<3: .spark
        case 3..<5: .ring
        case 5..<8: .orbit
        case 8..<12: .halo
        default: .constellation
        }
    }

    var name: String {
        switch self {
        case .spark: "Funke"
        case .ring: "Mit Ring"
        case .orbit: "Mit Trabanten"
        case .halo: "Doppelring"
        case .constellation: "Sternbild"
        }
    }
}

/// Was Dot gerade für ein Gesicht macht. `auto` folgt dem Check-in.
enum DotExpression {
    case auto, thinking, listening, happy
}

/// Dot als Figur: leuchtende Kugel in der Themenfarbe mit Gesicht – blinzelt, schaut umher,
/// lächelt passend zum Check-in. Ring, Trabanten, Doppelring und Sternbild wachsen mit dem Level.
/// Wird irgendwo in der App etwas geschafft (`Store.dotCheer`), hüpft jeder sichtbare Dot kurz mit Funken.
/// Animationen hängen nur an Dot selbst (nie per withAnimation an der Seite) – sonst wackelt alles mit.
struct DotView: View {
    let level: Int
    var size: CGFloat = 120
    var animated = true
    var expression: DotExpression = .auto
    var tappable = false                    // antippen = Dot freut sich kurz
    @ObservedObject private var store = Store.shared
    @State private var breathe = false
    @State private var spin = false
    @State private var blink = false
    @State private var lookX: CGFloat = 0
    @State private var hop = false
    @State private var joy = false
    @State private var burstAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var stage: DotStage { DotStage.of(level: level) }
    private var accent: Color { store.theme.accent }
    private var orb: CGFloat { size * 0.58 }
    private var moving: Bool { animated && !reduceMotion }
    private var thinking: Bool { expression == .thinking }
    private var happy: Bool { joy || expression == .happy }

    var body: some View {
        ZStack {
            // weicher Schein
            Circle()
                .fill(accent.opacity(0.3))
                .frame(width: orb * 1.2, height: orb * 1.2)
                .blur(radius: size * 0.09)
                .scaleEffect(breathe ? 1.08 : 0.94)
                .animation(moving ? .easeInOut(duration: 2.6).repeatForever(autoreverses: true) : nil, value: breathe)

            if stage.rawValue >= DotStage.ring.rawValue {
                Circle().stroke(accent.opacity(0.5), lineWidth: max(1, size * 0.016))
                    .frame(width: size * 0.8, height: size * 0.8)
            }
            if stage.rawValue >= DotStage.halo.rawValue {
                Circle().stroke(accent.opacity(0.22), lineWidth: max(1, size * 0.01))
                    .frame(width: size * 0.97, height: size * 0.97)
            }
            if stage.rawValue >= DotStage.orbit.rawValue {
                satellites(count: stage == .orbit ? 3 : 5, radius: stage == .orbit ? 0.4 : 0.47)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .animation(moving ? .linear(duration: 24).repeatForever(autoreverses: false) : nil, value: spin)
            }
            if stage == .constellation {
                constellation.opacity(0.6)
            }
            if thinking && moving {
                DotThinkingRing(size: size, color: accent)
            }
            if let burstAt {
                DotBurst(start: burstAt, size: size, color: accent)
            }

            // Körper (Arme dahinter, Sprössling obendrauf)
            ZStack {
                if size >= 22 { arms }
                Circle().fill(RadialGradient(
                    colors: [Color(hex: 0xF6F0FF), accent.opacity(0.95), accent, Color(hex: 0x2E1656)],
                    center: UnitPoint(x: 0.36, y: 0.3), startRadius: 0, endRadius: orb * 0.78))
                Ellipse()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: orb * 0.3, height: orb * 0.16)
                    .rotationEffect(.degrees(-24))
                    .offset(x: -orb * 0.17, y: -orb * 0.25)
                    .blur(radius: orb * 0.02)
                if size >= 22 { face }
                if size >= 22 && level >= 3 { sprout }
            }
            .frame(width: orb, height: orb)
            .shadow(color: accent.opacity(0.55), radius: size * 0.07)
            .scaleEffect(breathe ? 1.03 : 0.98)
            .animation(moving ? .easeInOut(duration: 2.6).repeatForever(autoreverses: true) : nil, value: breathe)
            // Hüpfer: kurz strecken und hoch, dann federnd zurück
            .scaleEffect(x: hop ? 0.92 : 1, y: hop ? 1.08 : 1, anchor: .bottom)
            .offset(y: hop ? -size * 0.1 : 0)
            .animation(.spring(response: 0.26, dampingFraction: 0.45), value: hop)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .simultaneousGesture(TapGesture().onEnded {
            cheer(burst: true)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }, including: tappable ? GestureMask.all : GestureMask.none)
        .onAppear {
            guard moving else { return }
            breathe = true
            spin = true
        }
        .onChange(of: store.dotCheer) { _ in
            if moving { cheer() }
        }
        .task {
            // ab und zu blinzeln oder umherschauen – unregelmäßig, wirkt lebendiger
            guard moving, size >= 22 else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64.random(in: 2_200_000_000...5_400_000_000))
                if Int.random(in: 0..<3) == 0 {
                    let looks: [CGFloat] = [-0.06, 0, 0, 0.06]
                    lookX = looks.randomElement() ?? 0
                } else {
                    blink = true
                    try? await Task.sleep(nanoseconds: 130_000_000)
                    blink = false
                }
            }
        }
        .accessibilityLabel("\(store.dotName), Stufe \(stage.name)")
    }

    /// Kurz freuen: hüpfen, Augen zu Bögen – Funken nur, wenn man Dot selbst antippt (sonst zu viel Trubel).
    private func cheer(burst: Bool = false) {
        guard !reduceMotion, size >= 20 else { return }
        hop = true
        joy = true
        if burst { burstAt = Date() }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 230_000_000)
            hop = false
            try? await Task.sleep(nanoseconds: 650_000_000)
            burstAt = nil
            try? await Task.sleep(nanoseconds: 800_000_000)
            joy = false
        }
    }

    /// Zwei kleine Ärmchen: hängen locker, beim Freuen gehen sie hoch und winken.
    private var arms: some View {
        let fill = LinearGradient(colors: [accent.opacity(0.95), Color(hex: 0x3B1E6E)], startPoint: .top, endPoint: .bottom)
        let w = orb * 0.17
        let h = orb * 0.36
        let lift: Double = happy ? 52 : 18
        return ZStack {
            Capsule().fill(fill)
                .frame(width: w, height: h)
                .rotationEffect(.degrees(lift), anchor: .top)
                .offset(x: -orb * 0.44, y: orb * 0.08)
            Capsule().fill(fill)
                .frame(width: w, height: h)
                .rotationEffect(.degrees(-lift), anchor: .top)
                .offset(x: orb * 0.44, y: orb * 0.08)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.45), value: happy)
    }

    /// Ab Level 3 wächst oben ein Sprössling – ab Level 8 mit zweitem Blatt.
    private var sprout: some View {
        let leaf = Color(hex: 0x7EE0A8)
        return ZStack {
            Capsule().fill(Color(hex: 0x5FBF86))
                .frame(width: orb * 0.04, height: orb * 0.16)
                .offset(y: -orb * 0.56)
            Ellipse().fill(leaf)
                .frame(width: orb * 0.2, height: orb * 0.1)
                .rotationEffect(.degrees(-28))
                .offset(x: orb * 0.09, y: -orb * 0.64)
            if level >= 8 {
                Ellipse().fill(leaf.opacity(0.85))
                    .frame(width: orb * 0.17, height: orb * 0.09)
                    .rotationEffect(.degrees(28))
                    .offset(x: -orb * 0.08, y: -orb * 0.61)
            }
        }
        .rotationEffect(.degrees(happy ? 8 : 0), anchor: .bottom)
        .animation(.spring(response: 0.35, dampingFraction: 0.4), value: happy)
    }

    /// Augen und Mund; der Mund folgt der heutigen Stimmung, beim Freuen werden die Augen zu Bögen.
    private var face: some View {
        let mood = store.todayCheckIn?.mood ?? 4
        let ink = Color(hex: 0x1B1226)
        let moodCurve: CGFloat = mood >= 4 ? 1 : mood == 3 ? 0.45 : 0.12
        let curve: CGFloat = happy ? 1.25 : thinking ? 0.15 : moodCurve
        let eyeX: CGFloat = thinking ? orb * 0.07 : lookX * orb
        let eyeY: CGFloat = thinking ? -orb * 0.1 : expression == .listening ? -orb * 0.03 : -orb * 0.05
        let eyeScale: CGFloat = blink ? 0.12 : (expression == .listening ? 1.15 : 1)
        let stroke = StrokeStyle(lineWidth: max(1, orb * 0.045), lineCap: .round)
        return ZStack {
            if happy {
                HStack(spacing: orb * 0.13) {
                    DotMouth(curve: 1).stroke(ink, style: stroke)
                        .frame(width: orb * 0.14, height: orb * 0.06).rotationEffect(.degrees(180))
                    DotMouth(curve: 1).stroke(ink, style: stroke)
                        .frame(width: orb * 0.14, height: orb * 0.06).rotationEffect(.degrees(180))
                }
                .offset(y: -orb * 0.07)
                .transition(.opacity)
                HStack(spacing: orb * 0.38) {
                    Circle().fill(Color(hex: 0xFF7AB6).opacity(0.5)).frame(width: orb * 0.12, height: orb * 0.08)
                    Circle().fill(Color(hex: 0xFF7AB6).opacity(0.5)).frame(width: orb * 0.12, height: orb * 0.08)
                }
                .offset(y: orb * 0.06)
                .transition(.opacity)
            } else {
                HStack(spacing: orb * 0.17) {
                    Capsule().fill(ink).frame(width: orb * 0.11, height: orb * 0.17)
                    Capsule().fill(ink).frame(width: orb * 0.11, height: orb * 0.17)
                }
                .scaleEffect(x: 1, y: eyeScale)
                .animation(.easeInOut(duration: 0.08), value: blink)
                .offset(x: eyeX, y: eyeY)
                .animation(.easeInOut(duration: 0.3), value: eyeX)
                .animation(.easeInOut(duration: 0.3), value: eyeY)
                .transition(.opacity)
            }
            DotMouth(curve: curve)
                .stroke(ink, style: stroke)
                .frame(width: orb * (happy ? 0.3 : 0.24), height: orb * 0.09)
                .offset(x: thinking ? orb * 0.05 : 0, y: orb * 0.16)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: curve)
        }
        .animation(.easeOut(duration: 0.18), value: happy)
    }

    private func satellites(count: Int, radius: CGFloat) -> some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                let angle = Double(i) / Double(count) * 2 * .pi
                Circle()
                    .fill(i == 0 ? Color(hex: 0xFAF8FC) : DS.purpleMuted)
                    .frame(width: size * 0.06, height: size * 0.06)
                    .offset(x: cos(angle) * size * radius, y: sin(angle) * size * radius)
            }
        }
    }

    private var constellation: some View {
        let points: [CGPoint] = [
            CGPoint(x: -0.42, y: -0.32), CGPoint(x: -0.12, y: -0.46), CGPoint(x: 0.32, y: -0.38),
            CGPoint(x: 0.46, y: 0.06), CGPoint(x: 0.24, y: 0.42), CGPoint(x: -0.32, y: 0.36),
        ]
        return ZStack {
            Path { p in
                for (i, pt) in points.enumerated() {
                    let q = CGPoint(x: size / 2 + pt.x * size, y: size / 2 + pt.y * size)
                    if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
                }
                p.closeSubpath()
            }
            .stroke(DS.purpleMuted.opacity(0.3), lineWidth: 1)
            ForEach(points.indices, id: \.self) { i in
                Circle().fill(Color(hex: 0xFAF8FC))
                    .frame(width: size * 0.035, height: size * 0.035)
                    .position(x: size / 2 + points[i].x * size, y: size / 2 + points[i].y * size)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Dots Mund: flacher Bogen, `curve` 0 = gerade, 1 = breites Lächeln.
struct DotMouth: Shape {
    var curve: CGFloat

    var animatableData: CGFloat {
        get { curve }
        set { curve = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.midX, y: rect.minY + rect.height * 2 * curve))
        return p
    }
}

/// Drei kleine Punkte kreisen um Dot, während er nachdenkt. Läuft über die Uhr (TimelineView),
/// nicht über repeatForever – so bewegt sich garantiert nur das hier.
struct DotThinkingRing: View {
    let size: CGFloat
    let color: Color

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    let angle = t * 3.4 + Double(i) * 0.55
                    Circle()
                        .fill(color.opacity(1 - Double(i) * 0.3))
                        .frame(width: size * (0.075 - CGFloat(i) * 0.015), height: size * (0.075 - CGFloat(i) * 0.015))
                        .offset(x: CGFloat(cos(-angle)) * size * 0.43, y: CGFloat(sin(-angle)) * size * 0.43)
                }
            }
            .frame(width: size, height: size)
        }
        .allowsHitTesting(false)
    }
}

/// Kleine Funken, die beim Freuen aus Dot herausfliegen und verblassen (ca. 0,75 s).
struct DotBurst: View {
    let start: Date
    let size: CGFloat
    let color: Color

    var body: some View {
        TimelineView(.animation) { context in
            let raw = min(1, max(0, context.date.timeIntervalSince(start) / 0.75))
            let p = CGFloat(1 - (1 - raw) * (1 - raw))          // schnell raus, sanft aus
            ZStack {
                ForEach(0..<8, id: \.self) { i in
                    let angle = Double(i) / 8 * 2 * .pi + 0.3
                    Circle()
                        .fill(i % 2 == 0 ? color : Color(hex: 0xFAF8FC))
                        .frame(width: size * 0.055, height: size * 0.055)
                        .scaleEffect(1 - 0.6 * p)
                        .offset(x: CGFloat(cos(angle)) * size * (0.28 + 0.3 * p),
                                y: CGFloat(sin(angle)) * size * (0.28 + 0.3 * p))
                        .opacity(Double(1 - p))
                }
            }
            .frame(width: size, height: size)
        }
        .allowsHitTesting(false)
    }
}

/// Drei hüpfende Punkte: „schreibt gerade“.
struct TypingDots: View {
    let color: Color

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    let wave = max(0, sin(t * 6.5 - Double(i) * 0.8))
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                        .offset(y: CGFloat(-wave * 4))
                        .opacity(0.4 + 0.6 * wave)
                }
            }
        }
    }
}

/// Was Dot mit welchem Level kann – jede Stufe bringt etwas Neues.
struct DotAbility: Identifiable {
    let level: Int
    let title: String
    let text: String
    var id: Int { level }

    static let all = [
        DotAbility(level: 1, title: "Morgen-Check-in", text: "Fragt kurz, wie es dir geht, und stellt „Was jetzt?“ darauf ein."),
        DotAbility(level: 2, title: "Tipp des Tages", text: "Jeden Tag ein kurzer, brauchbarer ADHS-Kniff."),
        DotAbility(level: 3, title: "Wochenrückblick", text: "Was du diese Woche geschafft hast – ehrlich, ohne Druck."),
        DotAbility(level: 5, title: "Muster erkennen", text: "Merkt, zu welcher Tageszeit du am meisten erledigst."),
        DotAbility(level: 8, title: "Doppelring", text: "Sieht schicker aus. Mehr nicht. Hast du dir verdient."),
        DotAbility(level: 12, title: "Sternbild", text: "Ganz ausgewachsen."),
    ]
}

/// Kopf des Gesprächs, solange es leer ist: Dot groß, Name (antippen = umbenennen), Level.
struct DotHeader: View {
    var expression: DotExpression = .auto
    @EnvironmentObject private var store: Store
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        let level = store.level
        VStack(spacing: 0) {
            DotView(level: level, size: 130, expression: expression, tappable: true)
                .padding(.top, 6)
            Button {
                newName = store.dotName
                renaming = true
            } label: {
                HStack(spacing: 6) {
                    Text(store.dotName).font(.system(size: 26, weight: .bold)).tracking(-0.8)
                    Image(systemName: "pencil").font(.system(size: 13, weight: .semibold)).foregroundStyle(DS.faint)
                }
                .foregroundStyle(DS.ink)
            }
            .buttonStyle(PressStyle())
            Text("Level \(level) · \(Level.title(level)) · \(DotStage.of(level: level).name)")
                .font(.system(size: 13)).foregroundStyle(DS.muted).padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .alert("Wie soll er heißen?", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Sichern") { store.renameDot(newName) }
            Button("Abbrechen", role: .cancel) {}
        }
    }
}

/// Rückblick und Muster – freigeschaltet ab Level 3 bzw. 5.
struct DotInsights: View {
    @EnvironmentObject private var store: Store

    private var weekDone: [TaskItem] {
        let cal = Calendar(identifier: .iso8601)
        let week = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return store.data.tasks.filter { t in
            t.doneAt.map { cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: $0) == week } ?? false
        }
    }

    /// Stunde mit den meisten erledigten Aufgaben (letzte 30 Tage).
    private var bestHours: String? {
        let since = Date().addingTimeInterval(-30 * 86_400)
        let hours = store.data.tasks.compactMap { $0.doneAt }.filter { $0 > since }
            .map { Calendar.current.component(.hour, from: $0) }
        guard hours.count >= 5 else { return nil }
        let blocks = Dictionary(grouping: hours) { $0 / 2 * 2 }   // 2-Stunden-Fenster
        guard let best = blocks.max(by: { $0.value.count < $1.value.count }) else { return nil }
        return "zwischen \(best.key) und \(best.key + 2) Uhr"
    }

    var body: some View {
        let level = store.level
        if level >= 3 {
            let focusWeek = store.data.focusLog.filter {
                Calendar(identifier: .iso8601).isDate($0.day, equalTo: Date(), toGranularity: .weekOfYear)
            }.reduce(0) { $0 + $1.minutes }
            insight(title: "Wochenrückblick",
                    text: weekDone.isEmpty && focusWeek == 0
                        ? "Diese Woche ist noch frisch. Ein erledigtes Ding reicht für einen Anfang."
                        : "\(weekDone.count) erledigt, \(focusWeek) Minuten Fokus, an \(store.activeDaysThisWeek) Tagen aktiv.")
        }
        if level >= 5 {
            insight(title: "Dein Muster",
                    text: bestHours.map { "Du erledigst das meiste \($0). Leg Schweres dorthin." }
                        ?? "Noch zu wenig Daten – ab ein paar erledigten Aufgaben sehe ich ein Muster.")
        }
    }

    private func insight(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased()).font(.system(size: 10, weight: .heavy)).tracking(0.7).foregroundStyle(DS.purpleMuted)
            Text(text).font(.system(size: 14)).foregroundStyle(DS.ink).lineSpacing(2)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Check-in + Tipp

/// Einmal am Tag oben in „Heute“: Stimmung + Energie, danach der Tipp des Tages.
struct CheckInCard: View {
    @EnvironmentObject private var store: Store
    @State private var mood: Int?

    private let moods = [(1, "Mies"), (2, "Naja"), (3, "Okay"), (4, "Gut"), (5, "Stark")]
    private let energies = [("low", "Wenig"), ("med", "Mittel"), ("high", "Viel")]

    var body: some View {
        if let checkin = store.todayCheckIn {
            // nach dem Check-in bleibt „Heute“ ruhig – kein Tipp-Kasten mehr (Build 61)
            EmptyView().id(checkin.day)
        } else {
            Panel(highlighted: true) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        DotView(level: store.level, size: 44,
                                expression: (mood ?? 0) >= 4 ? .happy : .auto)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(greeting).font(.system(size: 16, weight: .semibold)).foregroundStyle(DS.ink)
                            Text(mood == nil ? "Wie geht's dir gerade?" : "Und wie viel Energie ist da?")
                                .font(.system(size: 13)).foregroundStyle(DS.muted)
                        }
                    }
                    if mood == nil {
                        HStack(spacing: 6) {
                            ForEach(moods.indices, id: \.self) { i in
                                chip(moods[i].1) {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    withAnimation(.spring(response: 0.38, dampingFraction: 0.85)) { mood = moods[i].0 }
                                }
                            }
                        }
                        .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity)))
                    } else {
                        HStack(spacing: 6) {
                            ForEach(energies.indices, id: \.self) { i in
                                chip(energies[i].1) {
                                    withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                                        store.checkIn(mood: mood ?? 3, energy: energies[i].0)
                                    }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                }
                            }
                        }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .padding(14)
            }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 11 ? "Morgen" : hour < 17 ? "Hey" : "Abend"
        return "\(part)! Hier ist \(store.dotName)."
    }

    private func chip(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: 0xD8CFE0))
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(DS.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(DS.chipBorder))
        }
        .buttonStyle(PressStyle())
    }
}

struct TipCard: View {
    let mood: Int
    @EnvironmentObject private var store: Store
    @AppStorage("tipHiddenDay") private var hiddenDay = ""     // einmal weggetippt = für heute weg

    var body: some View {
        if hiddenDay != Quest.dayKey() {
            card
        }
    }

    private var card: some View {
        let tip = Tips.today(mood: store.shortNight ? 1 : mood)    // kurze Nacht laut Uhr: sanfte Tipps
        return HStack(alignment: .top, spacing: 12) {
            DotView(level: store.level, size: 34, animated: false)
            VStack(alignment: .leading, spacing: 4) {
                Text("TIPP VON \(store.dotName.uppercased())")
                    .font(.system(size: 10, weight: .heavy)).tracking(0.7).foregroundStyle(DS.purpleMuted)
                Text(tip).font(.system(size: 14)).foregroundStyle(DS.ink).lineSpacing(2)
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(.easeOut(duration: 0.2)) { hiddenDay = Quest.dayKey() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DS.faint)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Tipp für heute ausblenden")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DS.line))
    }
}

/// ADHS-Kniffe – kurz, konkret, ohne Kitsch. Einer pro Tag; an schlechten Tagen aus der sanften Liste.
enum Tips {
    static let general = [
        "Leg morgen früh Schlüssel, Handy und Tasche heute Abend an genau eine Stelle. Immer dieselbe.",
        "Wenn du nicht anfangen kannst: Mach die Aufgabe kleiner, nicht dich selbst härter.",
        "Stell den Timer auf 5 Minuten. Danach darfst du wirklich aufhören. Meistens willst du dann nicht.",
        "Langweiliges geht leichter mit Musik ohne Text oder braunem Rauschen.",
        "Schreib dir auf, wo du aufgehört hast, bevor du unterbrichst. Ein Satz reicht.",
        "Was weniger als 2 Minuten dauert: jetzt sofort, nicht auf die Liste.",
        "Iss etwas, bevor du dich an Schweres setzt. Ein leerer Kopf fokussiert schlecht.",
        "Body Doubling: Arbeite neben jemandem, auch per Videocall. Es hilft erstaunlich.",
        "Dein Zeitgefühl lügt. Schätz eine Dauer und rechne die Hälfte drauf.",
        "Leg das Handy beim Fokussieren in einen anderen Raum, nicht nur umgedreht hin.",
        "Eine Aufgabe, die seit Wochen liegt, braucht keinen Plan, sondern einen lächerlich kleinen ersten Schritt.",
        "Wenn alles gleich wichtig wirkt: Nimm das, was am schnellsten weg ist.",
        "Wecker für den Aufbruch, nicht für den Termin. Der Weg zählt mit.",
        "Hyperfokus ist okay. Stell vorher einen Wecker, damit du rauskommst.",
        "Unordnung im Zimmer: Nur eine Fläche frei machen. Nur den Schreibtisch.",
        "Antworte auf schwere Nachrichten erst mit einem Satz Entwurf in den Notizen. Abschicken kommt später.",
        "Merk dir Sachen nicht. Schreib sie in Dopa. Dein Kopf ist für Ideen, nicht fürs Lagern.",
        "Abends 2 Minuten: Was steht morgen an? Das spart morgens 20 Minuten Suchen.",
        "Wenn du festhängst: aufstehen, Wasser holen, zurückkommen. Bewegung startet den Kopf neu.",
        "Belohnung danach planen, nicht davor. Erst die 10 Minuten, dann das Video.",
        "Große Einkäufe: Liste nach Gängen. Dopa sortiert das schon für dich.",
        "Termine sofort eintragen, während du noch am Telefon bist.",
        "Wenn du etwas Spontanes kaufen willst: parken. In 48 Stunden siehst du es klarer.",
        "Gleiche Uhrzeit, gleicher Ablauf: Routinen sparen Entscheidungen, und Entscheidungen kosten Kraft.",
        "Fang mit dem Teil an, der dich am meisten interessiert. Reihenfolge ist überbewertet.",
    ]

    static let gentle = [
        "Heute ist ein Wenig-Energie-Tag. Eine Sache reicht. Eine kleine.",
        "Mies drauf ist kein Fehler. Trink was, iss was, dann sehen wir weiter.",
        "Du musst heute nichts aufholen. Nur das Nächste.",
        "Kritik fühlt sich bei ADHS oft größer an, als sie gemeint war. Lass sie kurz liegen, bevor du reagierst.",
        "Raus, fünf Minuten, ohne Ziel. Zählt auch.",
        "Schreib auf, was dich gerade belastet. Aufgeschrieben ist es nur noch halb so laut.",
    ]

    static func today(mood: Int) -> String {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        let list = mood <= 2 ? gentle : general
        return list[day % list.count]
    }
}
