import Foundation

/// Tagesbegleiter: Dot plant einmal am Tag, was er dir wann sagt.
/// Gemeinsam für App, Widget und Logik-Tests – deshalb nur Foundation.

/// Welcher Teil des Tages gerade ist. Abend beginnt eine Stunde vor der Abendroutine,
/// Nacht ab der Schlafenszeit bis 4 Uhr früh.
enum DayPhase: String, Codable, CaseIterable {
    case morning, day, evening, night

    static func at(_ minutes: Int, eveningStart: Int, bed: Int) -> DayPhase {
        let m = ((minutes % 1440) + 1440) % 1440
        // Schlafenszeit nach Mitternacht (z. B. 0:30) zählt bis dahin noch zum Abend
        if bed < 4 * 60 {
            if m >= bed && m < 4 * 60 { return .night }
        } else if m >= bed || m < 4 * 60 {
            return .night
        }
        if m < 4 * 60 { return .evening }               // nach Mitternacht, aber vor einer späten Schlafenszeit
        if m < 11 * 60 { return .morning }
        let evening = max(11 * 60, eveningStart - 60)
        return m >= evening ? .evening : .day
    }
}

/// Was Gemini einmal am Tag für Dot schreibt. Leer = eingebaute Texte.
struct CompanionScript: Codable, Hashable {
    var day: String
    var briefing = ""
    var midday = ""
    var afternoon = ""
    var evening = ""
    var night = ""
    var nudges: [String] = []
    var meals: [String] = []

    func line(for phase: DayPhase, minutes: Int) -> String {
        switch phase {
        case .morning: briefing
        case .day: minutes < 15 * 60 ? midday : afternoon
        case .evening: evening
        case .night: night
        }
    }
}

/// Ein Fixpunkt im Tag fürs Widget („14:30 Zahnarzt“).
struct Anchor: Codable, Hashable {
    var time: Date
    var title: String
}

/// Alles, was das Dot-Widget braucht – die App schreibt es, das Widget liest es.
struct WidgetDay: Codable {
    var day: String
    var dotName: String
    var level: Int
    var anchors: [Anchor]
    var lines: [String: String]         // DayPhase.rawValue → Satz von Dot
    var eveningStart: Int
    var bed: Int
    var theOne: String?

    static let key = "widgetDay"
}

/// Eingebaute Sätze, falls Gemini nicht da ist. Pro Tag fest ausgewählt, damit sie nicht ständig springen.
enum CompanionText {
    static let morning = [
        "Langsam ankommen. Erst Wasser, dann alles andere.",
        "Ein Ding nach dem anderen. Das Eine reicht für heute.",
        "Morgen-Kopf darf noch laden. Kleine Schritte zählen voll.",
        "Guter Tag zum Anfangen – mit etwas Winzigem.",
    ]
    static let day = [
        "Kurzer Check: Wasser, Essen, wo stehst du?",
        "Du musst nicht alles schaffen. Nur das Nächste.",
        "Falls du tief drin bist: alles gut. Nur kurz hochschauen.",
        "Zehn Minuten an einer Sache sind ein echter Anfang.",
    ]
    static let evening = [
        "Der Tag wird leiser. Was geschafft ist, ist geschafft.",
        "Runterfahren. Morgen-Ich freut sich über zwei Minuten Vorbereitung.",
        "Kein Rückblick mit Note – nur kurz: Was war heute gut?",
    ]
    static let night = [
        "Spät geworden. Morgen-Ich sagt danke für jede Minute Schlaf.",
        "Handy ans Kabel, Licht aus. Der Rest kann bis morgen warten.",
        "Nichts muss mehr passieren heute.",
    ]

    static func line(_ phase: DayPhase, day: String) -> String {
        let pool: [String]
        switch phase {
        case .morning: pool = Self.morning
        case .day: pool = Self.day
        case .evening: pool = Self.evening
        case .night: pool = Self.night
        }
        let seed = day.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return pool[abs(seed) % pool.count]
    }
}
