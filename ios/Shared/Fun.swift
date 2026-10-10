import Foundation

/// Kleine Dinge gegen Langeweile (Wunsch: „App wird langweilig“) – jedes für sich ruhig:
/// • `Draw`: Dot zieht eine Karte aus deinen Aufgaben, mit kleinem Dreh („nur 5 Minuten“).
/// • `Outfit`: Dot verkleidet sich je nach Jahreszeit und manchmal einfach so.
/// • `Surprise`: selten nach dem Abhaken etwas Unerwartetes (Konfetti, Witz, Fakt).
/// Nur Foundation – läuft auch in den Logik-Tests. Zufall kommt als `roll` (0..<1) rein, damit es testbar bleibt.

// MARK: - Dot zieht für dich

struct DrawTwist: Hashable {
    let text: String
    let minutes: Int
}

enum Draw {
    /// Nach drei Karten gilt die dritte – endloses Neu-Ziehen ist auch Aufschieben.
    static let maxDraws = 3

    static let twists: [DrawTwist] = [
        DrawTwist(text: "Nur 5 Minuten. Danach darfst du wirklich aufhören.", minutes: 5),
        DrawTwist(text: "Mit deinem Lieblingssong – fertig, wenn er vorbei ist.", minutes: 4),
        DrawTwist(text: "Erst den leichtesten Teil.", minutes: 10),
        DrawTwist(text: "10 Minuten, Handy in einen anderen Raum.", minutes: 10),
        DrawTwist(text: "Nur vorbereiten: alles hinlegen, was du dafür brauchst.", minutes: 5),
        DrawTwist(text: "Schlecht machen ist erlaubt. Hauptsache angefangen.", minutes: 10),
        DrawTwist(text: "Im Stehen. Klingt komisch, hilft oft.", minutes: 5),
        DrawTwist(text: "15 Minuten Wettrennen gegen die Uhr.", minutes: 15),
    ]

    /// Wenig Energie oder spät: nur die kurzen.
    static let gentle: [DrawTwist] = [
        DrawTwist(text: "Nur 2 Minuten. Wirklich nur zwei.", minutes: 2),
        DrawTwist(text: "Nur den allerersten Handgriff.", minutes: 3),
        DrawTwist(text: "Nur vorbereiten: alles hinlegen, was du dafür brauchst.", minutes: 5),
        DrawTwist(text: "Nur 5 Minuten. Danach darfst du wirklich aufhören.", minutes: 5),
    ]

    /// Joker statt Aufgabe – selten, nie bei der ersten Karte.
    static let joker = DrawTwist(text: "Pausen-Karte: 5 Minuten nichts. Wasser holen, strecken. Dann zieh nochmal.", minutes: 5)

    /// Gewicht einer Aufgabe: Heute geplantes und lange Liegendes kommt öfter.
    static func weight(_ task: TaskItem, now: Date, calendar: Calendar = .current) -> Double {
        var w = 1.0
        if let due = task.dueDay, calendar.isDate(due, inSameDayAs: now) { w += 2 }
        let age = calendar.dateComponents([.day], from: task.createdAt, to: now).day ?? 0
        w += min(3, Double(max(0, age)) / 3)
        if task.someday { w *= 0.5 }
        return w
    }

    /// Eine Karte ziehen (ohne die schon gezogenen). `roll` in 0..<1.
    static func pick(_ tasks: [TaskItem], excluding: Set<UUID>, now: Date, roll: Double,
                     calendar: Calendar = .current) -> TaskItem? {
        let pool = tasks.filter { $0.doneAt == nil && !excluding.contains($0.id) }
        guard !pool.isEmpty else { return nil }
        let weights: [Double] = pool.map { weight($0, now: now, calendar: calendar) }
        let total = weights.reduce(0, +)
        var target = min(max(roll, 0), 0.999_999) * total
        for (index, w) in weights.enumerated() {
            if target < w { return pool[index] }
            target -= w
        }
        return pool.last
    }

    /// Der kleine Dreh zur Karte. Wenig Energie, spät abends oder früh morgens → nur kurze.
    static func twist(energy: String?, hour: Int, roll: Double) -> DrawTwist {
        let soft = energy == "low" || hour >= 22 || hour < 7
        let list = soft ? gentle : twists
        let index = min(list.count - 1, Int(min(max(roll, 0), 0.999_999) * Double(list.count)))
        return list[index]
    }

    /// Joker? Nur ab der zweiten Karte, etwa jede achte.
    static func isJoker(draw: Int, roll: Double) -> Bool {
        draw >= 2 && roll < 0.125
    }

    /// Was Dot zur Karte sagt (je nach Zug).
    static func line(draw: Int) -> String {
        switch draw {
        case 1: return "Die hier hab ich für dich gezogen."
        case 2: return "Okay, neue Karte."
        default: return "Die dritte gilt. Klein anfangen reicht."
        }
    }
}

// MARK: - Verkleidungen

enum DotOutfit: String, CaseIterable {
    case none, witchHat, santaHat, partyHat, beanie, scarf, flowers, sunglasses, headphones, bowtie

    var name: String {
        switch self {
        case .none: return "Ohne"
        case .witchHat: return "Hexenhut"
        case .santaHat: return "Nikolausmütze"
        case .partyHat: return "Partyhut"
        case .beanie: return "Wollmütze"
        case .scarf: return "Schal"
        case .flowers: return "Blumenkranz"
        case .sunglasses: return "Sonnenbrille"
        case .headphones: return "Kopfhörer"
        case .bowtie: return "Fliege"
        }
    }

    /// Sitzt oben auf dem Kopf (dann kein Sprössling).
    var onHead: Bool {
        switch self {
        case .witchHat, .santaHat, .partyHat, .beanie, .flowers, .headphones: return true
        default: return false
        }
    }
}

enum Outfit {
    /// Fester Zufallswert pro Tag (0..<100) – derselbe Tag ergibt immer dasselbe Outfit.
    static func dayRoll(_ date: Date, salt: Int, calendar: Calendar = .current) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        var x = UInt64((c.year ?? 0) * 10_000 + (c.month ?? 0) * 100 + (c.day ?? 0) + salt * 7919)
        x = (x ^ (x >> 16)) &* 0x45d9f3b
        x = (x ^ (x >> 16)) &* 0x45d9f3b
        x = x ^ (x >> 16)
        return Int(x % 100)
    }

    /// Was Dot heute trägt. Feiertage fest, Jahreszeiten an manchen Tagen, sonst ab und zu eine Überraschung.
    static func today(_ date: Date, calendar: Calendar = .current) -> DotOutfit {
        let c = calendar.dateComponents([.month, .day], from: date)
        let month = c.month ?? 1
        let day = c.day ?? 1
        let roll = dayRoll(date, salt: 1, calendar: calendar)
        if month == 10 && day >= 24 { return .witchHat }
        if month == 12 && (day == 6 || (20...26).contains(day)) { return .santaHat }
        if (month == 12 && day == 31) || (month == 1 && day == 1) { return .partyHat }
        switch month {
        case 12, 1, 2: if roll < 50 { return .beanie }
        case 11: if roll < 45 { return .scarf }
        case 4, 5: if roll < 30 { return .flowers }
        case 6, 7, 8: if roll < 35 { return .sunglasses }
        default: break
        }
        // sonst: ab und zu einfach so
        let surprise = dayRoll(date, salt: 2, calendar: calendar)
        if surprise < 8 { return .headphones }
        if surprise < 14 { return .bowtie }
        return .none
    }
}

// MARK: - Überraschungen nach dem Abhaken

enum SurpriseKind: String, CaseIterable {
    case confetti, joke, fact, spin
}

enum Surprise {
    static let maxPerDay = 2
    static let chance = 0.2
    /// Mindestabstand – zwei kurz hintereinander wären keine Überraschung mehr.
    static let gap: TimeInterval = 30 * 60

    static func shouldShow(shownToday: Int, last: Date?, now: Date, roll: Double) -> Bool {
        guard shownToday < maxPerDay else { return false }
        if let last, now.timeIntervalSince(last) < gap { return false }
        return roll < chance
    }

    static func kind(roll: Double) -> SurpriseKind {
        let all = SurpriseKind.allCases
        return all[min(all.count - 1, Int(min(max(roll, 0), 0.999_999) * Double(all.count)))]
    }

    /// Text Nummer `n` aus der Liste – reihum, damit sich nichts wiederholt, bevor alle dran waren.
    static func text(_ kind: SurpriseKind, n: Int) -> String {
        let list: [String]
        switch kind {
        case .joke: list = jokes
        case .fact: list = facts
        case .confetti: list = cheers
        case .spin: list = spins
        }
        return list[((n % list.count) + list.count) % list.count]
    }

    static let jokes = [
        "Was macht ein Pirat am Computer? Er drückt die Enter-Taste.",
        "Treffen sich zwei Magnete. Sagt der eine: „Was soll ich heute bloß anziehen?“",
        "Warum können Geister so schlecht lügen? Weil man durch sie hindurchsieht.",
        "Was sitzt auf dem Baum und winkt? Ein Huhu.",
        "Wie nennt man einen Bumerang, der nicht zurückkommt? Stock.",
        "Was ist grün und klopft an die Tür? Ein Klopfsalat.",
        "Was ist orange und läuft durch den Wald? Eine Wanderine.",
        "Warum ist das Mathebuch so traurig? Es hat zu viele Probleme.",
        "Wie heißt ein Spanier ohne Auto? Carlos.",
        "Was ist braun, klebrig und läuft durch die Wüste? Ein Karamel.",
    ]

    static let facts = [
        "Oktopusse haben drei Herzen und blaues Blut.",
        "Honig wird nicht schlecht – in alten ägyptischen Gräbern fand man noch essbaren.",
        "Otter halten sich beim Schlafen an den Pfoten, damit sie nicht wegtreiben.",
        "Ein Tag auf der Venus dauert länger als ein Jahr auf der Venus.",
        "Kühe haben beste Freundinnen – getrennt sind sie messbar gestresster.",
        "Bananen sind botanisch Beeren, Erdbeeren nicht.",
        "Der Eiffelturm ist im Sommer bis zu 15 cm höher – Metall dehnt sich bei Wärme aus.",
        "Wombat-Kot ist würfelförmig.",
        "Seesterne haben kein Gehirn – und kommen trotzdem gut klar.",
        "In der Schweiz ist es verboten, nur ein einzelnes Meerschweinchen zu halten – sie wären zu einsam.",
    ]

    static let cheers = [
        "Einfach so. Weil du gerade was erledigt hast.",
        "Konfetti, ohne besonderen Grund.",
        "Kleine Feier zwischendurch.",
    ]

    static let spins = [
        "Ich musste kurz eine Runde drehen.",
        "Das war mir einen Salto wert.",
        "Huiii. Okay, weiter.",
    ]
}
