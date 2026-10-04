import SwiftUI

/// Wofür es Punkte gibt. Kleine, sofortige Belohnungen – und nie Abzug fürs Nicht-Tun.
enum XPKind {
    case taskDone, focusStarted, focusMinutes(Int), memo, mealEaten
    case morningStep, morningDone, shopBought, wishParked, wishDropped, wishKept
    case habitTick, habitDone, eveningStep, eveningDone, billPaid, spendLogged, shopDone

    var amount: Int {
        switch self {
        case .taskDone: 10
        case .focusStarted: 5
        case .focusMinutes(let m): min(max(m, 0), 60)
        case .memo: 2
        case .mealEaten: 3
        case .morningStep: 2
        case .morningDone: 15
        case .shopBought: 1
        case .wishParked: 2
        case .wishDropped: 10
        case .wishKept: 3
        case .habitTick: 2
        case .habitDone: 5
        case .eveningStep: 2
        case .eveningDone: 15
        case .billPaid: 5
        case .spendLogged: 2
        case .shopDone: 10
        }
    }

    var reason: String {
        switch self {
        case .taskDone: "Aufgabe erledigt"
        case .focusStarted: "Angefangen"
        case .focusMinutes(let m): "\(m) Min Fokus"
        case .memo: "Gemerkt"
        case .mealEaten: "Gegessen"
        case .morningStep: "Morgen-Schritt"
        case .morningDone: "Morgen geschafft"
        case .shopBought: "Eingekauft"
        case .wishParked: "Wunsch geparkt"
        case .wishDropped: "Nicht gekauft"
        case .wishKept: "Entschieden"
        case .habitTick: "Abgehakt"
        case .habitDone: "Tagesziel"
        case .eveningStep: "Abend-Schritt"
        case .eveningDone: "Abend geschafft"
        case .billPaid: "Rate bezahlt"
        case .spendLogged: "Ausgabe notiert"
        case .shopDone: "Einkauf erledigt"
        }
    }

    /// Welche Wochen-Quest das voranbringt, und um wie viel.
    var quest: (key: String, amount: Int)? {
        switch self {
        case .taskDone: ("done", 1)
        case .focusStarted: ("start", 1)
        case .focusMinutes(let m): ("focus", m)
        case .memo: ("memo", 1)
        case .mealEaten: ("meal", 1)
        case .morningDone: ("morning", 1)
        case .shopBought: ("shop", 1)
        case .wishParked: ("park", 1)
        default: nil
        }
    }

    /// Nur bei „großen“ Momenten gibt's die Chance auf einen Glückstreffer.
    var canBeLucky: Bool {
        switch self {
        case .taskDone, .morningDone, .wishDropped, .eveningDone, .billPaid, .shopDone: true
        default: false
        }
    }
}

struct Award: Equatable, Identifiable {
    let id = UUID()
    let amount: Int
    let reason: String
    let lucky: Bool
    let newLevel: Int?          // gesetzt, wenn das ein Level-Up war
    let quest: String?          // Titel einer gerade geschafften Wochen-Quest
}

enum Level {
    /// XP, die man für Level `level` braucht: 0, 40, 120, 240, 400, 600 …
    static func threshold(_ level: Int) -> Int { 20 * (level - 1) * level }

    static func level(for xp: Int) -> Int {
        var level = 1
        while threshold(level + 1) <= xp { level += 1 }
        return level
    }

    /// Fortschritt innerhalb des aktuellen Levels.
    static func progress(_ xp: Int) -> (have: Int, need: Int) {
        let level = level(for: xp)
        let start = threshold(level)
        return (xp - start, threshold(level + 1) - start)
    }

    static func title(_ level: Int) -> String {
        let titles = ["Funke", "Glimmen", "Flamme", "Lagerfeuer", "Leuchtfeuer", "Komet",
                      "Sternschnuppe", "Supernova", "Nebel", "Galaxie"]
        return titles[min(level - 1, titles.count - 1)]
    }

    static func emoji(_ level: Int) -> String {
        let emojis = ["✨", "🕯️", "🔥", "🏕️", "🗼", "☄️", "🌠", "💥", "🌌", "🪐"]
        return emojis[min(level - 1, emojis.count - 1)]
    }
}

struct Quest: Identifiable {
    let key: String
    let title: String
    let target: Int
    var id: String { key }

    static let pool = [
        Quest(key: "start", title: "3× „Anfangen“ benutzen", target: 3),
        Quest(key: "focus", title: "60 Minuten Fokus", target: 60),
        Quest(key: "memo", title: "5 Sachen merken", target: 5),
        Quest(key: "morning", title: "Morgen-Checkliste 2× fertig", target: 2),
        Quest(key: "done", title: "5 Aufgaben erledigen", target: 5),
        Quest(key: "shop", title: "10 Sachen einkaufen", target: 10),
        Quest(key: "park", title: "1 Spontankauf parken", target: 1),
        Quest(key: "meal", title: "4× „Gegessen“ tippen", target: 4),
    ]

    static let reward = 40

    /// Jede Woche drei andere – fest pro Woche, damit sie nicht beim Öffnen wechseln.
    static func forWeek(_ week: String) -> [Quest] {
        var seed = week.unicodeScalars.reduce(UInt64(1469598103934665603)) { ($0 ^ UInt64($1.value)) &* 1099511628211 }
        var remaining = pool
        var picked: [Quest] = []
        while picked.count < 3, !remaining.isEmpty {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            picked.append(remaining.remove(at: Int(seed >> 33) % remaining.count))
        }
        return picked
    }

    static func weekKey(_ date: Date = Date()) -> String {
        let cal = Calendar(identifier: .iso8601)
        let c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%d-W%02d", c.yearForWeekOfYear ?? 0, c.weekOfYear ?? 0)
    }

    static func dayKey(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// Farben zum Freischalten. Hintergrund je nach Hell/Dunkel.
struct Theme: Identifiable {
    let id: String
    let name: String
    let level: Int
    let accent: Color
    let dark: [Color]
    let light: [Color]

    func background(_ scheme: ColorScheme) -> [Color] { scheme == .dark ? dark : light }

    private static func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }

    static let all: [Theme] = [
        Theme(id: "lila", name: "Lila", level: 1, accent: rgb(0.62, 0.42, 1.0),
              dark: [rgb(0.13, 0.05, 0.26), rgb(0.03, 0.01, 0.08)],
              light: [rgb(0.95, 0.92, 1.0), rgb(1, 1, 1)]),
        Theme(id: "mitternacht", name: "Mitternacht", level: 2, accent: rgb(0.45, 0.55, 1.0),
              dark: [rgb(0.05, 0.07, 0.24), rgb(0.01, 0.01, 0.07)],
              light: [rgb(0.92, 0.94, 1.0), rgb(1, 1, 1)]),
        Theme(id: "neon", name: "Neon", level: 3, accent: rgb(0.22, 0.92, 0.62),
              dark: [rgb(0.02, 0.15, 0.12), rgb(0.0, 0.03, 0.03)],
              light: [rgb(0.91, 1.0, 0.96), rgb(1, 1, 1)]),
        Theme(id: "sunset", name: "Sunset", level: 5, accent: rgb(1.0, 0.52, 0.38),
              dark: [rgb(0.24, 0.07, 0.12), rgb(0.05, 0.01, 0.03)],
              light: [rgb(1.0, 0.94, 0.91), rgb(1, 1, 1)]),
        Theme(id: "gold", name: "Gold", level: 8, accent: rgb(1.0, 0.8, 0.28),
              dark: [rgb(0.18, 0.12, 0.02), rgb(0.04, 0.03, 0.0)],
              light: [rgb(1.0, 0.98, 0.89), rgb(1, 1, 1)]),
        Theme(id: "aurora", name: "Aurora", level: 12, accent: rgb(0.45, 0.95, 0.92),
              dark: [rgb(0.04, 0.16, 0.24), rgb(0.12, 0.02, 0.2)],
              light: [rgb(0.9, 0.98, 1.0), rgb(0.97, 0.93, 1.0)]),
    ]

    static func named(_ id: String) -> Theme { all.first { $0.id == id } ?? all[0] }
}
