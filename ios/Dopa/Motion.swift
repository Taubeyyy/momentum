import SwiftUI

// Bewegung & Rückmeldung aus dem zweiten Entwurf (Startbildschirm, Toast, Druck, Einblenden).

/// Knöpfe geben beim Drücken leicht nach.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Motion.press(configuration.isPressed), value: configuration.isPressed)
    }
}

/// Gemeinsame Kurven – überall gleich, damit sich die App wie aus einem Guss anfühlt.
enum Motion {
    /// Runter schnell, beim Loslassen leicht federnd zurück.
    static func press(_ pressed: Bool) -> Animation {
        pressed ? .easeOut(duration: 0.1) : .spring(response: 0.3, dampingFraction: 0.6)
    }
    /// Listen: Zeilen kommen und gehen.
    static let list = Animation.spring(response: 0.36, dampingFraction: 0.86)
    /// Kleine Bestätigungen (Häkchen, Zähler).
    static let pop = Animation.spring(response: 0.34, dampingFraction: 0.5)
}

/// Kurzes „Plopp“, wenn sich ein Wert ändert (Häkchen, Zähler, Tab). `when` filtert, z. B. nur beim Abhaken.
struct PopOnChange<Value: Equatable>: ViewModifier {
    let value: Value
    let scale: CGFloat
    let when: (Value) -> Bool
    @State private var popped = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(popped ? scale : 1)
            .animation(popped ? .easeOut(duration: 0.1) : Motion.pop, value: popped)
            .onChange(of: value) { newValue in
                guard !reduceMotion, when(newValue) else { return }
                popped = true
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 110_000_000)
                    popped = false
                }
            }
    }
}

/// Ein Ring läuft einmal nach außen und verblasst, sobald `active` wahr wird – „geschafft“.
struct PulseOnTrue: ViewModifier {
    let active: Bool
    let color: Color
    let cornerRadius: CGFloat
    @State private var startedAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay {
                if let startedAt {
                    TimelineView(.animation) { context in
                        let p = min(1, max(0, context.date.timeIntervalSince(startedAt) / 0.55))
                        let eased = 1 - (1 - p) * (1 - p)
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(color, lineWidth: 2)
                            .scaleEffect(CGFloat(1 + 0.6 * eased))
                            .opacity(0.8 * (1 - p))
                    }
                    .allowsHitTesting(false)
                }
            }
            .onChange(of: active) { now in
                guard now, !reduceMotion else { return }
                let start = Date()
                startedAt = start
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    if startedAt == start { startedAt = nil }
                }
            }
    }
}

/// Erscheint mit einem kleinen Federn (Toasts, Abzeichen).
struct PopIn: ViewModifier {
    var delay: Double = 0
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown || reduceMotion ? 1 : 0.4)
            .opacity(shown || reduceMotion ? 1 : 0)
            .animation(.spring(response: 0.4, dampingFraction: 0.55).delay(delay), value: shown)
            .onAppear { shown = true }
    }
}

extension View {
    func popOnChange<V: Equatable>(of value: V, scale: CGFloat = 1.18,
                                   when: @escaping (V) -> Bool = { _ in true }) -> some View {
        modifier(PopOnChange(value: value, scale: scale, when: when))
    }

    func pulseOnTrue(_ active: Bool, color: Color, cornerRadius: CGFloat = 8) -> some View {
        modifier(PulseOnTrue(active: active, color: color, cornerRadius: cornerRadius))
    }

    func popIn(delay: Double = 0) -> some View { modifier(PopIn(delay: delay)) }
}

/// Text, der beim Ändern nach oben wegrollt (Zähler wie „3 offen“).
struct RollingText: View {
    let text: String

    var body: some View {
        ZStack {
            Text(text)
                .id(text)
                .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                        removal: .move(edge: .top).combined(with: .opacity)))
        }
        .clipped()
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: text)
    }
}

/// Pulsierender Punkt für „läuft gerade“ (Timer).
struct LiveDot: View {
    let color: Color
    var size: CGFloat = 8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let wave = reduceMotion ? 0 : (sin(context.date.timeIntervalSinceReferenceDate * 2.4) + 1) / 2
            ZStack {
                Circle().fill(color.opacity(0.35))
                    .frame(width: size, height: size)
                    .scaleEffect(CGFloat(1 + wave * 0.9))
                    .opacity(1 - wave * 0.8)
                Circle().fill(color).frame(width: size, height: size)
            }
        }
        .frame(width: size * 2, height: size * 2)
    }
}

/// Häkchen als Linie – lässt sich „zeichnen“ (trim).
struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.55))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return p
    }
}

/// Kurze Bestätigung unten über der Tab-Leiste („Plan wurde übernommen“).
@MainActor
final class Toaster: ObservableObject {
    static let shared = Toaster()
    @Published private(set) var message: String?
    private var token = UUID()

    func show(_ text: String) {
        let id = UUID()
        token = id
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { message = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if token == id { withAnimation(.easeOut(duration: 0.2)) { message = nil } }
        }
    }
}

struct ConfirmToast: View {
    let message: String
    @ObservedObject private var store = Store.shared

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 27, height: 27)
                .background(store.theme.accent, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .popIn(delay: 0.06)
            Text(message).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: 0xE9E6EC))
        }
        .padding(.leading, 9)
        .padding(.trailing, 14)
        .padding(.vertical, 8)
        .background(Color(hex: 0x1F1E23, opacity: 0.96), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Color(hex: 0x3B3640)))
        .shadow(color: .black.opacity(0.35), radius: 18, y: 12)
    }
}

/// Startbildschirm: Logo, Name, ein Satz, Ladebalken – dann sanft weg.
struct SplashView: View {
    let onFinished: () -> Void
    @State private var dropped = false          // Dot fällt rein
    @State private var landed = false           // … landet: Funken, Ringe, Schein
    @State private var letters = false          // „dopa“ Buchstabe für Buchstabe
    @State private var tagline = false
    @State private var loaded = false
    @State private var leaving = false
    @State private var burstAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var store = Store.shared

    private let word: [String] = ["d", "o", "p", "a"]

    var body: some View {
        let accent = store.theme.accent
        ZStack {
            DS.surface.ignoresSafeArea()
            // weicher Schein, der beim Landen aufgeht
            RadialGradient(colors: [accent.opacity(0.28), .clear], center: .center,
                           startRadius: 0, endRadius: landed ? 340 : 60)
                .ignoresSafeArea()
                .opacity(landed ? 1 : 0)
                .offset(y: -40)
            // zwei Wellenringe beim Aufsetzen
            ForEach(0..<2, id: \.self) { i in
                Circle()
                    .stroke(accent.opacity(0.4), lineWidth: 1.5)
                    .frame(width: 140, height: 140)
                    .scaleEffect(landed ? 2.3 + CGFloat(i) * 0.7 : 0.7)
                    .opacity(landed ? 0 : (dropped ? 0.8 : 0))
                    .animation(.easeOut(duration: 1.1).delay(Double(i) * 0.14), value: landed)
                    .offset(y: -40)
            }
            VStack(spacing: 0) {
                ZStack {
                    if let burstAt { DotBurst(start: burstAt, size: 170, color: accent) }
                    DotView(level: store.level, size: 124, expression: landed ? .happy : .auto)
                        .offset(y: dropped ? 0 : -280)
                        .scaleEffect(x: dropped && !landed ? 0.92 : 1, y: dropped && !landed ? 1.08 : 1, anchor: .bottom)
                        .opacity(dropped ? 1 : 0)
                }
                HStack(spacing: 0) {
                    ForEach(Array(word.enumerated()), id: \.offset) { i, letter in
                        Text(letter)
                            .font(.system(size: 36, weight: .heavy, design: .rounded))
                            .foregroundStyle(DS.ink)
                            .offset(y: letters ? 0 : 16)
                            .opacity(letters ? 1 : 0)
                            .scaleEffect(letters ? 1 : 0.6)
                            .animation(.spring(response: 0.45, dampingFraction: 0.55).delay(Double(i) * 0.07), value: letters)
                    }
                }
                .tracking(-1)
                .padding(.top, 8)
                Text("Ein Schritt nach dem anderen.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0x8E8993))
                    .padding(.top, 6)
                    .opacity(tagline ? 1 : 0)
                    .offset(y: tagline ? 0 : 6)
            }
            .offset(y: -20)
            VStack {
                Spacer()
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: 0x28282E))
                    Capsule().fill(accent).frame(width: loaded ? 64 : 0)
                }
                .frame(width: 64, height: 3)
                .opacity(dropped ? 1 : 0)
                .padding(.bottom, 45)
            }
        }
        .scaleEffect(leaving ? 1.08 : 1)
        .opacity(leaving ? 0 : 1)
        .onAppear(perform: run)
    }

    /// Ablauf: fallen (0,05 s) → landen mit Funken (0,45 s) → Wort (0,5 s) → Satz → in die App (~1,8 s).
    private func run() {
        if reduceMotion {
            dropped = true
            landed = true
            letters = true
            tagline = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { leave() }
            return
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.62).delay(0.05)) { dropped = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            burstAt = Date()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { landed = true }
            letters = true
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.8)) { tagline = true }
        withAnimation(.easeInOut(duration: 1.1).delay(0.55)) { loaded = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.85) { leave() }
    }

    private func leave() {
        withAnimation(.easeIn(duration: 0.35)) { leaving = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onFinished() }
    }
}

/// Inhalt gleitet beim ersten Erscheinen sanft herein.
struct EnterAnimation: ViewModifier {
    var delay: Double = 0
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 7)
            .onAppear {
                withAnimation(.timingCurve(0.2, 0.7, 0.25, 1, duration: 0.32).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func enterAnimation(delay: Double = 0) -> some View { modifier(EnterAnimation(delay: delay)) }
}

/// Umsortieren durch Ziehen in einfachen Stapeln (ohne List): beim Drüberziehen sofort umstellen.
struct ReorderDrop: DropDelegate {
    let target: UUID
    @Binding var dragging: UUID?
    let move: (_ moving: UUID, _ target: UUID) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { move(dragging, target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}
