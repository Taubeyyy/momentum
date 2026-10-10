import SwiftUI

/// Seltene Überraschung nach dem Abhaken: Konfetti (jedes Mal andere Farben), ein Witz, ein Fakt
/// oder Dot schlägt einen Salto. Unten eine kleine Karte – antippen schließt, sonst geht sie von selbst.
struct SurpriseOverlay: View {
    let event: Store.SurpriseEvent
    let onClose: () -> Void
    @ObservedObject private var store = Store.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spun = false
    @State private var palette: [Color] = []
    @State private var startedAt = Date()

    private var eyebrow: String {
        switch event.kind {
        case .joke: return "WITZ VON \(store.dotName.uppercased())"
        case .fact: return "WUSSTEST DU?"
        case .confetti: return "ÜBERRASCHUNG"
        case .spin: return store.dotName.uppercased()
        }
    }

    /// Lesezeit: Witze und Fakten brauchen länger.
    private var duration: UInt64 {
        switch event.kind {
        case .joke, .fact: return 7_000_000_000
        default: return 3_800_000_000
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if event.kind == .confetti && !reduceMotion && !palette.isEmpty {
                ConfettiBurst(start: startedAt, colors: palette)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            card
                .padding(.horizontal, 16)
                .padding(.bottom, 96)
        }
        .onAppear {
            startedAt = Date()
            palette = Self.palettes.randomElement() ?? [store.theme.accent]
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            if event.kind == .spin { spun = true }
        }
        .task(id: event.id) {
            try? await Task.sleep(nanoseconds: duration)
            onClose()
        }
    }

    private var card: some View {
        HStack(alignment: .center, spacing: 12) {
            DotView(level: store.level, size: 48, expression: .happy)
                .rotationEffect(.degrees(spun && !reduceMotion ? 360 : 0))
                .animation(.spring(response: 0.7, dampingFraction: 0.7), value: spun)
            VStack(alignment: .leading, spacing: 3) {
                Text(eyebrow)
                    .font(.system(size: 10, weight: .heavy)).tracking(0.7)
                    .foregroundStyle(DS.purpleMuted)
                Text(event.text)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DS.ink)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(DS.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(DS.line))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
        .contentShape(Rectangle())
        .onTapGesture { onClose() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Schließen")
    }

    static let palettes: [[Color]] = [
        [Color(hex: 0xA78BFA), Color(hex: 0xF0ABFC), Color(hex: 0xFDE68A), Color(hex: 0xF7F3FA)],
        [Color(hex: 0x5EEAD4), Color(hex: 0x7DD3FC), Color(hex: 0xA7F3D0), Color(hex: 0xF7F3FA)],
        [Color(hex: 0xFDBA74), Color(hex: 0xFCD34D), Color(hex: 0xFB7185), Color(hex: 0xFFF7ED)],
        [Color(hex: 0xF9A8D4), Color(hex: 0xC4B5FD), Color(hex: 0x93C5FD), Color(hex: 0xFDF2F8)],
        [Color(hex: 0x86EFAC), Color(hex: 0xFDE047), Color(hex: 0x67E8F9), Color(hex: 0xF0FDF4)],
    ]
}

/// Konfetti von oben: fällt, dreht sich, wird am Ende durchsichtig (ca. 2,4 s). Über die Uhr gezeichnet.
struct ConfettiBurst: View {
    let start: Date
    let colors: [Color]
    private let count = 46
    private let length: Double = 2.4

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation) { context in
                let t: Double = context.date.timeIntervalSince(start)
                Canvas { gc, size in
                    guard t < length else { return }
                    for i in 0..<count {
                        let p = Self.particle(i)
                        let x = p.x * size.width + CGFloat(sin(t * p.wobble + p.phase)) * 18 + CGFloat(p.drift * t) * 30
                        let y = -20 + CGFloat(p.speed * t + 160 * t * t) - CGFloat(p.delay) * 60
                        let fade = t > length - 0.5 ? (length - t) / 0.5 : 1
                        var piece = gc
                        piece.opacity = max(0, fade)
                        piece.translateBy(x: x, y: y)
                        piece.rotate(by: .radians(t * p.spin + p.phase))
                        let rect = CGRect(x: -p.w / 2, y: -p.h / 2, width: p.w, height: p.h)
                        let shape = i % 3 == 0 ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1.5)
                        piece.fill(shape, with: .color(colors[i % max(1, colors.count)]))
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }

    private struct Particle {
        let x: CGFloat; let speed: Double; let wobble: Double; let phase: Double
        let drift: Double; let spin: Double; let w: CGFloat; let h: CGFloat; let delay: Double
    }

    /// Fester „Zufall“ je Teilchen – kein State nötig.
    private static func particle(_ i: Int) -> Particle {
        func r(_ salt: Int) -> Double {
            let v = sin(Double(i * 127 + salt * 311)) * 43_758.545_3
            return v - floor(v)
        }
        return Particle(x: CGFloat(r(1)), speed: 220 + r(2) * 260, wobble: 2 + r(3) * 4, phase: r(4) * 6.28,
                        drift: r(5) - 0.5, spin: 2 + r(6) * 6, w: CGFloat(6 + r(7) * 5), h: CGFloat(4 + r(8) * 8),
                        delay: r(9))
    }
}
