import Foundation

/// Schlafphasen aus Health (Apple Watch): erkennen, zusammenfassen, kurz erklären.
/// Nur Foundation – läuft in der App und in den Logik-Tests.

enum SleepStage: Int, CaseIterable, Hashable {
    case awake, rem, core, deep, unspecified

    /// Health-Werte (HKCategoryValueSleepAnalysis): 0 im Bett, 1 Schlaf ohne Phase, 2 wach, 3 Kern, 4 Tief, 5 REM.
    init?(healthValue: Int) {
        switch healthValue {
        case 1: self = .unspecified
        case 2: self = .awake
        case 3: self = .core
        case 4: self = .deep
        case 5: self = .rem
        default: return nil          // „im Bett“ zählt nicht als Schlaf
        }
    }

    var name: String {
        switch self {
        case .awake: "Wach"
        case .rem: "REM"
        case .core: "Kernschlaf"
        case .deep: "Tiefschlaf"
        case .unspecified: "Schlaf"
        }
    }

    var isAsleep: Bool { self != .awake }

    /// Was in der Phase passiert – kurz, ohne Medizin-Ton.
    var explanation: String {
        switch self {
        case .deep: "Der Körper repariert sich und lädt auf – vor allem in der ersten Nachthälfte. Fehlt er, fühlt man sich wie überfahren."
        case .rem: "Hier träumst du. Dein Kopf sortiert Gefühle und Gelerntes – kommt vor allem gegen Morgen."
        case .core: "Leichter Schlaf, der größte Teil jeder Nacht. Dass es so viel ist, ist völlig normal."
        case .awake: "Kurz wach zwischendurch ist normal – meistens merkst du es gar nicht."
        case .unspecified: "Die Uhr hat Schlaf erkannt, aber keine Phasen (z. B. ohne Uhr geschlafen)."
        }
    }

    /// Üblicher Anteil an der Schlafzeit (grob, Erwachsene) – nur zur Einordnung.
    var typicalShare: ClosedRange<Double>? {
        switch self {
        case .deep: return 0.12...0.23
        case .rem: return 0.18...0.27
        case .core: return 0.45...0.60
        default: return nil
        }
    }
}

struct SleepSegment: Hashable {
    var stage: SleepStage
    var start: Date
    var end: Date
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Eine Nacht: Abschnitte für die Grafik, Summen je Phase, Anfang und Ende.
struct SleepNight: Hashable {
    var segments: [SleepSegment]
    var totals: [SleepStage: TimeInterval]
    var asleep: TimeInterval
    var start: Date
    var end: Date

    /// Hat die Uhr Phasen geliefert? (Sonst nur „Schlaf“.)
    var hasStages: Bool { (totals[.deep] ?? 0) + (totals[.rem] ?? 0) + (totals[.core] ?? 0) > 0 }

    /// Anteil einer Phase an der Schlafzeit (0…1).
    func share(_ stage: SleepStage) -> Double {
        asleep > 0 ? (totals[stage] ?? 0) / asleep : 0
    }

    /// „üblich“, „etwas weniger als üblich“, „mehr als üblich“ – ohne Wertung.
    func note(_ stage: SleepStage) -> String? {
        guard let range = stage.typicalShare, asleep > 0 else { return nil }
        let s = share(stage)
        if s < range.lowerBound { return "etwas weniger als üblich" }
        if s > range.upperBound { return "mehr als üblich" }
        return "im üblichen Bereich"
    }

    /// Uhr und Handy melden oft doppelt: Gibt es echte Phasen, fliegt „Schlaf ohne Phase“ raus.
    /// Summen je Phase ohne Doppelzählung überlappender Stücke.
    static func build(_ raw: [SleepSegment]) -> SleepNight? {
        let valid = raw.filter { $0.end > $0.start }
        let staged = valid.contains { $0.stage == .deep || $0.stage == .rem || $0.stage == .core }
        let segments = valid.filter { !(staged && $0.stage == .unspecified) }.sorted { $0.start < $1.start }
        guard let first = segments.first else { return nil }
        var totals: [SleepStage: TimeInterval] = [:]
        for stage in SleepStage.allCases {
            let parts: [(start: Date, end: Date)] = segments.filter { $0.stage == stage }.map { (start: $0.start, end: $0.end) }
            let seconds = Timing.asleepSeconds(parts)
            if seconds > 0 { totals[stage] = seconds }
        }
        let asleep = SleepStage.allCases.filter(\.isAsleep).reduce(0.0) { $0 + (totals[$1] ?? 0) }
        let end = segments.map(\.end).max() ?? first.end
        return SleepNight(segments: segments, totals: totals, asleep: asleep, start: first.start, end: end)
    }

    /// Ein ruhiger Satz zur Nacht.
    var summary: String {
        if Timing.shortNight(asleep) { return "Kurze Nacht. Heute reicht weniger – kleine Schritte, Pausen sind eingeplant." }
        if asleep >= 8 * 3600 { return "Lange Nacht. Gute Grundlage für heute." }
        return "Solide Nacht."
    }
}
