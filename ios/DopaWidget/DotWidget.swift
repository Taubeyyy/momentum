import SwiftUI
import WidgetKit

/// Dot als Widget: ein Satz passend zur Tageszeit, der nächste Fixpunkt, das Eine.
/// Wechselt über den Tag von selbst (ein Eintrag pro Viertelstunde), ohne dass du die App öffnest.
struct DotEntry: TimelineEntry {
    let date: Date
    let name: String
    let level: Int
    let line: String
    let next: Anchor?
    let theOne: String?
}

struct DotProvider: TimelineProvider {
    func placeholder(in context: Context) -> DotEntry {
        DotEntry(date: .now, name: "Dot", level: 3, line: "Langsam ankommen. Erst Wasser, dann alles andere.",
                 next: Anchor(time: .now.addingTimeInterval(5400), title: "Zahnarzt"), theOne: "Bewerbung abschicken")
    }

    func getSnapshot(in context: Context, completion: @escaping (DotEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entries(from: .now, count: 1).first ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DotEntry>) -> Void) {
        // Bis Mitternacht alle 15 Minuten ein Eintrag – Satz und „Als Nächstes“ laufen von selbst weiter
        completion(Timeline(entries: entries(from: .now, count: 48), policy: .atEnd))
    }

    private func entries(from start: Date, count: Int) -> [DotEntry] {
        let raw = Shared.defaults?.data(forKey: WidgetDay.key)
        let day = raw.flatMap { try? JSONDecoder().decode(WidgetDay.self, from: $0) }
        return (0..<count).map { i in
            let date = start.addingTimeInterval(Double(i) * 900)
            // nach Mitternacht (oder ohne Daten aus der App): eingebaute Sätze, keine alten Fixpunkte
            guard let day, day.day == Self.dayKey(date) else {
                return DotEntry(date: date, name: day?.dotName ?? "Dot", level: day?.level ?? 1,
                                line: CompanionText.line(phase(date, day), day: Self.dayKey(date)), next: nil, theOne: nil)
            }
            let minutes = Self.minutes(date)
            let p = phase(date, day)
            let key = p == .day && minutes >= 15 * 60 ? "afternoon" : p.rawValue
            return DotEntry(date: date, name: day.dotName, level: day.level,
                            line: day.lines[key] ?? day.lines[p.rawValue] ?? CompanionText.line(p, day: day.day),
                            next: day.anchors.first { $0.time > date },
                            theOne: day.theOne)
        }
    }

    private func phase(_ date: Date, _ day: WidgetDay?) -> DayPhase {
        DayPhase.at(Self.minutes(date), eveningStart: day?.eveningStart ?? 22 * 60, bed: day?.bed ?? 23 * 60 + 30)
    }

    private static func minutes(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// Dot ohne Animation – dieselbe Kugel mit Gesicht wie in der App.
struct WidgetDot: View {
    let level: Int
    var size: CGFloat = 34

    private let accent = Color(red: 0.55, green: 0.36, blue: 0.96)

    var body: some View {
        let orb = size * 0.62
        ZStack {
            Circle().fill(accent.opacity(0.3)).frame(width: orb * 1.25, height: orb * 1.25).blur(radius: size * 0.08)
            if level >= 3 {
                Circle().stroke(accent.opacity(0.5), lineWidth: 1.2).frame(width: size * 0.86, height: size * 0.86)
            }
            ZStack {
                Circle().fill(RadialGradient(
                    colors: [Color(red: 0.96, green: 0.94, blue: 1), accent.opacity(0.95), accent, Color(red: 0.18, green: 0.09, blue: 0.34)],
                    center: UnitPoint(x: 0.36, y: 0.3), startRadius: 0, endRadius: orb * 0.78))
                HStack(spacing: orb * 0.17) {
                    Capsule().fill(Color(red: 0.1, green: 0.07, blue: 0.15)).frame(width: orb * 0.11, height: orb * 0.17)
                    Capsule().fill(Color(red: 0.1, green: 0.07, blue: 0.15)).frame(width: orb * 0.11, height: orb * 0.17)
                }
                .offset(y: -orb * 0.05)
            }
            .frame(width: orb, height: orb)
        }
        .frame(width: size, height: size)
    }
}

struct DotWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DotEntry

    var body: some View {
        content
            .widgetURL(URL(string: "dopa://jetzt"))
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            Text(entry.next.map { "\(time($0.time)) \($0.title)" } ?? entry.line)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name).font(.caption2.weight(.bold)).widgetAccentable()
                Text(entry.line).font(.caption).lineLimit(2)
                if let next = entry.next {
                    Text("\(time(next.time)) \(next.title)").font(.caption2).lineLimit(1).opacity(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .systemSmall:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    WidgetDot(level: entry.level, size: 26)
                    Text(entry.name).font(.caption.weight(.bold)).opacity(0.8)
                }
                Text(entry.line).font(.system(size: 13, weight: .semibold)).lineLimit(4)
                Spacer(minLength: 0)
                if let next = entry.next {
                    Text("\(time(next.time)) · \(next.title)").font(.caption2.weight(.semibold)).lineLimit(1).opacity(0.85)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetCard()
        default:
            HStack(alignment: .top, spacing: 12) {
                WidgetDot(level: entry.level, size: 40)
                VStack(alignment: .leading, spacing: 6) {
                    Text(entry.name.uppercased()).font(.system(size: 10, weight: .heavy)).opacity(0.7)
                    Text(entry.line).font(.system(size: 15, weight: .semibold)).lineLimit(3)
                    Spacer(minLength: 0)
                    HStack(spacing: 12) {
                        if let next = entry.next {
                            Label("\(time(next.time)) \(next.title)", systemImage: "clock")
                                .font(.caption.weight(.semibold)).lineLimit(1)
                        }
                        if let one = entry.theOne {
                            Label(one, systemImage: "star").font(.caption.weight(.semibold)).lineLimit(1)
                        }
                    }
                    .opacity(0.85)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetCard()
        }
    }

    private func time(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

struct DotWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DotWidget", provider: DotProvider()) { entry in
            DotWidgetView(entry: entry)
        }
        .configurationDisplayName("Dot")
        .description("Dein Begleiter: ein Satz zur Tageszeit und was als Nächstes kommt.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}
