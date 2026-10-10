import SwiftUI

/// Dots Verkleidung des Tages (`Outfit.today`), über den Körper gelegt.
/// Koordinaten relativ zur Kugel (`orb` = Durchmesser, Mitte = 0/0): Augen bei y −0,05, Mund bei +0,16.
struct DotOutfitView: View {
    let outfit: DotOutfit
    let orb: CGFloat
    var accent: Color = DS.purpleMuted

    var body: some View {
        ZStack {
            switch outfit {
            case .none: EmptyView()
            case .witchHat: witchHat
            case .santaHat: santaHat
            case .partyHat: partyHat
            case .beanie: beanie
            case .scarf: scarf
            case .flowers: flowers
            case .sunglasses: sunglasses
            case .headphones: headphones
            case .bowtie: bowtie
            }
        }
        .frame(width: orb, height: orb)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Kopf

    private var witchHat: some View {
        ZStack {
            Ellipse()
                .fill(Color(hex: 0x241433))
                .frame(width: orb * 0.82, height: orb * 0.17)
                .offset(y: -orb * 0.40)
            ZStack {
                HatCone(bend: 0.22)
                    .fill(LinearGradient(colors: [Color(hex: 0x4A2A78), Color(hex: 0x241433)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: orb * 0.48, height: orb * 0.52)
                    .offset(y: -orb * 0.67)
                Capsule()
                    .fill(Color(hex: 0xF59E0B))
                    .frame(width: orb * 0.45, height: orb * 0.07)
                    .offset(y: -orb * 0.46)
            }
            .frame(width: orb, height: orb)
            .rotationEffect(.degrees(-6), anchor: UnitPoint(x: 0.5, y: 0.1))
        }
    }

    private var santaHat: some View {
        ZStack {
            ZStack {
                HatCone(bend: 0.35)
                    .fill(LinearGradient(colors: [Color(hex: 0xE5484D), Color(hex: 0xB42328)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: orb * 0.6, height: orb * 0.44)
                    .offset(y: -orb * 0.6)
                Circle()
                    .fill(Color(hex: 0xF7F3FA))
                    .frame(width: orb * 0.14, height: orb * 0.14)
                    .offset(x: orb * 0.12, y: -orb * 0.82)
            }
            .frame(width: orb, height: orb)
            .rotationEffect(.degrees(10), anchor: UnitPoint(x: 0.5, y: 0.1))
            Capsule()
                .fill(Color(hex: 0xF7F3FA))
                .frame(width: orb * 0.66, height: orb * 0.13)
                .offset(y: -orb * 0.39)
        }
    }

    private var partyHat: some View {
        ZStack {
            HatCone(bend: 0)
                .fill(LinearGradient(colors: [Color(hex: 0xFF7AB6), Color(hex: 0xFBBF24)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: orb * 0.34, height: orb * 0.42)
                .offset(y: -orb * 0.6)
            Circle().fill(Color.white.opacity(0.85))
                .frame(width: orb * 0.05, height: orb * 0.05)
                .offset(x: -orb * 0.04, y: -orb * 0.55)
            Circle().fill(Color.white.opacity(0.85))
                .frame(width: orb * 0.05, height: orb * 0.05)
                .offset(x: orb * 0.05, y: -orb * 0.66)
            Circle()
                .fill(Color(hex: 0xFBBF24))
                .frame(width: orb * 0.12, height: orb * 0.12)
                .offset(y: -orb * 0.82)
        }
        .frame(width: orb, height: orb)
        .rotationEffect(.degrees(-12), anchor: UnitPoint(x: 0.5, y: 0.1))
    }

    private var beanie: some View {
        let wool = Color(hex: 0x2F8F8B)
        return ZStack {
            Ellipse()
                .fill(LinearGradient(colors: [wool.opacity(0.95), Color(hex: 0x1E5F5C)], startPoint: .top, endPoint: .bottom))
                .frame(width: orb * 0.86, height: orb * 0.46)
                .offset(y: -orb * 0.38)
            Capsule()
                .fill(Color(hex: 0x226E6A))
                .frame(width: orb * 0.92, height: orb * 0.13)
                .offset(y: -orb * 0.22)
            Circle()
                .fill(Color(hex: 0xEAF7F6))
                .frame(width: orb * 0.18, height: orb * 0.18)
                .offset(y: -orb * 0.63)
        }
    }

    private var flowers: some View {
        let colors: [Color] = [Color(hex: 0xFF9BC8), Color(hex: 0xFDE68A), Color(hex: 0xF7F3FA),
                               Color(hex: 0xC4B5FD), Color(hex: 0xFF9BC8)]
        return ZStack {
            ForEach(0..<5, id: \.self) { i in
                let angle = (-150 + Double(i) * 30) * Double.pi / 180
                ZStack {
                    Circle().fill(colors[i]).frame(width: orb * 0.14, height: orb * 0.14)
                    Circle().fill(Color(hex: 0xF59E0B)).frame(width: orb * 0.05, height: orb * 0.05)
                }
                .offset(x: CGFloat(cos(angle)) * orb * 0.47, y: CGFloat(sin(angle)) * orb * 0.47)
            }
        }
    }

    private var headphones: some View {
        let dark = Color(hex: 0x2B2633)
        return ZStack {
            Circle()
                .trim(from: 0.56, to: 0.94)
                .stroke(dark, style: StrokeStyle(lineWidth: orb * 0.07, lineCap: .round))
                .frame(width: orb * 1.1, height: orb * 1.1)
            ForEach([-1.0, 1.0], id: \.self) { side in
                ZStack {
                    Capsule().fill(dark).frame(width: orb * 0.17, height: orb * 0.3)
                    Capsule().fill(accent).frame(width: orb * 0.07, height: orb * 0.18)
                }
                .offset(x: CGFloat(side) * orb * 0.52, y: -orb * 0.02)
            }
        }
    }

    // MARK: Gesicht und Hals

    private var sunglasses: some View {
        ZStack {
            ForEach([-1.0, 1.0], id: \.self) { side in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: orb * 0.06, style: .continuous)
                        .fill(Color(hex: 0x111018).opacity(0.95))
                    Capsule()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: orb * 0.07, height: orb * 0.025)
                        .rotationEffect(.degrees(-20))
                        .offset(x: orb * 0.04, y: orb * 0.03)
                }
                .frame(width: orb * 0.25, height: orb * 0.16)
                .offset(x: CGFloat(side) * orb * 0.15, y: -orb * 0.05)
            }
            Capsule()
                .fill(Color(hex: 0x111018))
                .frame(width: orb * 0.09, height: orb * 0.03)
                .offset(y: -orb * 0.08)
        }
    }

    private var scarf: some View {
        let red = Color(hex: 0xC2410C)
        return ZStack {
            RoundedRectangle(cornerRadius: orb * 0.05, style: .continuous)
                .fill(Color(hex: 0x9A3412))
                .frame(width: orb * 0.14, height: orb * 0.28)
                .rotationEffect(.degrees(8))
                .offset(x: orb * 0.2, y: orb * 0.46)
            Capsule()
                .fill(LinearGradient(colors: [red, Color(hex: 0x9A3412)], startPoint: .top, endPoint: .bottom))
                .frame(width: orb * 0.84, height: orb * 0.16)
                .offset(y: orb * 0.34)
            HStack(spacing: orb * 0.1) {
                ForEach(0..<4, id: \.self) { _ in
                    Capsule().fill(Color(hex: 0xFDBA74).opacity(0.7)).frame(width: orb * 0.03, height: orb * 0.12)
                }
            }
            .offset(y: orb * 0.34)
        }
    }

    private var bowtie: some View {
        let color = Color(hex: 0xE11D48)
        return ZStack {
            BowWing().fill(color)
                .frame(width: orb * 0.15, height: orb * 0.14)
                .offset(x: -orb * 0.08, y: orb * 0.36)
            BowWing().fill(color)
                .frame(width: orb * 0.15, height: orb * 0.14)
                .scaleEffect(x: -1, y: 1)
                .offset(x: orb * 0.08, y: orb * 0.36)
            Circle().fill(Color(hex: 0x9F1239))
                .frame(width: orb * 0.07, height: orb * 0.07)
                .offset(y: orb * 0.36)
        }
    }
}

/// Spitzer Hut, Spitze leicht zur Seite geknickt (`bend` 0 = gerade).
struct HatCone: Shape {
    var bend: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let tip = CGPoint(x: rect.midX + rect.width * bend, y: rect.minY)
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addQuadCurve(to: tip, control: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.minY + rect.height * 0.35))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                       control: CGPoint(x: rect.maxX - rect.width * 0.15, y: rect.minY + rect.height * 0.45))
        p.closeSubpath()
        return p
    }
}

/// Ein Flügel der Fliege: Dreieck mit runder Außenkante, Spitze zur Mitte (rechts).
struct BowWing: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY), control: CGPoint(x: rect.minX - rect.width * 0.2, y: rect.midY))
        p.closeSubpath()
        return p
    }
}
