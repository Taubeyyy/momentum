import SwiftUI

/// „Dot zieht für dich“: Stapel antippen → Karten mischen → eine dreht sich um.
/// Auf der Karte: eine deiner Aufgaben plus ein kleiner Dreh („nur 5 Minuten“). „Los“ startet den Timer.
/// Höchstens drei Karten – die dritte gilt. Selten liegt eine Pausen-Karte dazwischen.
struct DrawSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Card: Equatable {
        case task(TaskItem, DrawTwist)
        case joker
    }

    @State private var draws = 0
    @State private var drawn: Set<UUID> = []
    @State private var card: Card?
    @State private var flipped = false
    @State private var shuffling = false
    @State private var shuffleStep = 0

    private var openTasks: [TaskItem] { store.openTasks }
    private var canDrawAgain: Bool {
        if case .joker = card { return true }
        return draws < Draw.maxDraws && openTasks.contains { !drawn.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                Spacer(minLength: 8)
                if openTasks.isEmpty {
                    EmptyState(symbol: "", title: "Keine Karten im Stapel",
                               text: "Schreib erst eine Sache in deine Aufgaben – dann zieht \(store.dotName) für dich.")
                } else {
                    deck
                        .frame(height: 300)
                    caption
                    buttons
                }
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.surface.ignoresSafeArea())
            .navigationTitle("\(store.dotName) zieht")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } }
            }
        }
    }

    // MARK: Stapel und Karte

    private var deck: some View {
        ZStack {
            // verdeckte Karten dahinter – wackeln beim Mischen
            ForEach(0..<3, id: \.self) { i in
                CardBack(accent: store.theme.accent)
                    .frame(width: 210, height: 280)
                    .rotationEffect(.degrees(backAngle(i)))
                    .offset(x: backOffset(i), y: CGFloat(i) * -3)
                    .animation(.spring(response: 0.22, dampingFraction: 0.55), value: shuffleStep)
                    .opacity(card == nil || i < 2 ? 1 : 0)
            }
            if let card {
                ZStack {
                    CardBack(accent: store.theme.accent)
                        .rotation3DEffect(.degrees(flipped ? 90 : 0), axis: (x: 0, y: 1, z: 0))
                        .opacity(flipped ? 0 : 1)
                        .animation(.easeIn(duration: 0.16), value: flipped)
                    front(card)
                        .rotation3DEffect(.degrees(flipped ? 0 : -90), axis: (x: 0, y: 1, z: 0))
                        .opacity(flipped ? 1 : 0)
                        .animation(.spring(response: 0.34, dampingFraction: 0.78).delay(flipped ? 0.15 : 0), value: flipped)
                }
                .frame(width: 236, height: 300)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if card == nil && !shuffling { drawCard() } }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(card == nil ? "Karte ziehen" : "Gezogene Karte")
    }

    private func backAngle(_ i: Int) -> Double {
        let base: [Double] = [-7, 5, 0]
        guard shuffling else { return base[i] }
        let swing: [Double] = shuffleStep % 2 == 0 ? [-14, 12, -4] : [9, -11, 5]
        return swing[i]
    }

    private func backOffset(_ i: Int) -> CGFloat {
        guard shuffling else { return CGFloat(i - 1) * 6 }
        let swing: [CGFloat] = shuffleStep % 2 == 0 ? [-34, 30, 0] : [26, -30, 4]
        return swing[i]
    }

    @ViewBuilder
    private func front(_ card: Card) -> some View {
        switch card {
        case .task(let task, let twist):
            CardFront(eyebrow: "KARTE \(draws) VON \(Draw.maxDraws)", symbol: "sparkles",
                      title: task.title, text: twist.text, minutes: twist.minutes, accent: store.theme.accent)
        case .joker:
            CardFront(eyebrow: "JOKER", symbol: "cup.and.saucer.fill",
                      title: "Pausen-Karte", text: Draw.joker.text, minutes: Draw.joker.minutes, accent: store.theme.accent)
        }
    }

    // MARK: Text und Knöpfe

    private var caption: some View {
        Text(card == nil ? "Tipp auf den Stapel." : Draw.line(draw: draws))
            .font(.system(size: 14))
            .foregroundStyle(DS.muted)
            .multilineTextAlignment(.center)
            .animation(.easeInOut(duration: 0.2), value: draws)
    }

    @ViewBuilder
    private var buttons: some View {
        VStack(spacing: 10) {
            if card == nil {
                Button(action: drawCard) {
                    Label("Karte ziehen", systemImage: "rectangle.on.rectangle.angled")
                }
                .buttonStyle(SolidButtonStyle())
                .disabled(shuffling)
            } else if flipped {
                Button(action: start) {
                    Text(startLabel)
                }
                .buttonStyle(SolidButtonStyle())
                if canDrawAgain {
                    Button("Andere Karte") { redraw() }
                        .buttonStyle(PillButtonStyle())
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: flipped)
    }

    private var startLabel: String {
        switch card {
        case .task(_, let twist): return "Los · \(twist.minutes) Min"
        case .joker: return "Pause · \(Draw.joker.minutes) Min"
        case nil: return "Los"
        }
    }

    // MARK: Ablauf

    private func drawCard() {
        guard !shuffling else { return }
        shuffling = true
        Task { @MainActor in
            if !reduceMotion {
                for _ in 0..<4 {
                    shuffleStep += 1
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    try? await Task.sleep(nanoseconds: 140_000_000)
                }
            }
            shuffling = false
            draws += 1
            card = nextCard()
            try? await Task.sleep(nanoseconds: 120_000_000)
            flipped = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func nextCard() -> Card? {
        if Draw.isJoker(draw: draws, roll: Double.random(in: 0..<1)) { return .joker }
        guard let task = Draw.pick(openTasks, excluding: drawn, now: Date(), roll: Double.random(in: 0..<1)) else { return nil }
        drawn.insert(task.id)
        let hour = Calendar.current.component(.hour, from: Date())
        return .task(task, Draw.twist(energy: store.todayCheckIn?.energy, hour: hour, roll: Double.random(in: 0..<1)))
    }

    private func redraw() {
        // Joker zählt nicht als Karte
        if case .joker = card { draws -= 1 }
        flipped = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            withAnimation(.easeOut(duration: 0.2)) { card = nil }
            drawCard()
        }
    }

    private func start() {
        switch card {
        case .task(let task, let twist):
            store.startFocus(taskID: task.id, title: task.title, step: twist.text, minutes: twist.minutes)
            Toaster.shared.show("\(twist.minutes) Minuten: \(task.title)")
        case .joker:
            store.startFocus(taskID: nil, title: "Pause", step: "Nichts tun. Wasser, strecken.", minutes: Draw.joker.minutes)
            Toaster.shared.show("Pause läuft")
        case nil:
            return
        }
        dismiss()
    }
}

/// Rückseite: ruhiges Muster in der Themenfarbe mit Dot-Punkt in der Mitte.
private struct CardBack: View {
    let accent: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(LinearGradient(colors: [accent.opacity(0.95), Color(hex: 0x2E1656)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1.5)
                    .padding(10)
            )
            .overlay(
                ZStack {
                    Circle().stroke(Color.white.opacity(0.25), lineWidth: 2).frame(width: 74, height: 74)
                    Circle().fill(Color.white.opacity(0.9)).frame(width: 30, height: 30)
                }
            )
            .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
    }
}

/// Vorderseite: Aufgabe groß, darunter der Dreh und die Minuten.
private struct CardFront: View {
    let eyebrow: String
    let symbol: String
    let title: String
    let text: String
    let minutes: Int
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(eyebrow)
                    .font(.system(size: 10, weight: .heavy)).tracking(0.8)
                    .foregroundStyle(DS.purpleMuted)
                Spacer(minLength: 0)
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
            }
            Spacer(minLength: 0)
            Text(title)
                .font(.system(size: 24, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(DS.ink)
                .lineLimit(4)
                .minimumScaleFactor(0.7)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(DS.muted)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text("\(minutes) Min")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(accent, in: Capsule())
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(DS.raised, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(accent.opacity(0.5), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
    }
}
