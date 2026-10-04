import Foundation

/// Gespräch mit Dot: Verlauf, Vorschläge zum Antippen und was Dot direkt anlegen darf.
/// Nur Foundation – läuft in der App und in den Logik-Tests.

/// Etwas, das Dot vorschlägt und das mit einem Tipp angelegt wird. Nie automatisch.
struct DotAction: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case task, reminder, shop, memo, focus
        case done, tomorrow             // bestehende Aufgabe abhaken / auf morgen schieben
        case steps                      // Schritte an eine bestehende Aufgabe hängen
        case schedule                   // mehrere Termine auf einmal (z. B. Wochenplan vom Foto)
    }

    var id = UUID()
    var kind: Kind
    var title: String
    var step = ""               // erster Schritt (Aufgabe) oder Text der Mitteilung (Erinnerung)
    var minutes = 0             // Timer-Länge
    var time: Int?              // Erinnerung: Minuten seit Mitternacht
    var day = 0                 // 0 = heute, 1 = morgen …
    var done = false            // schon angetippt
    var items: [String] = []    // Schritte (bei „steps“ und bei neuen Aufgaben)
    var entries: [PlanEntry] = [] // Termine (bei „schedule“)
    var place = ""                // Ort (bei Aufgaben): erinnern beim Ankommen

    init(kind: Kind, title: String, step: String = "", minutes: Int = 0, time: Int? = nil, day: Int = 0,
         items: [String] = [], entries: [PlanEntry] = [], place: String = "") {
        self.kind = kind
        self.title = title
        self.step = step
        self.minutes = minutes
        self.time = time
        self.day = day
        self.items = items
        self.entries = entries
        self.place = place
    }

    private var entryCount: String { entries.count == 1 ? "1 Termin" : "\(entries.count) Termine" }

    private var stepCount: String { items.count == 1 ? "1 Schritt" : "\(items.count) Schritte" }

    /// Beschriftung des Knopfs, z. B. „Erinnerung morgen 14:30 · Oma anrufen“.
    var label: String {
        let when: String = DotChat.dayWord(day, prefix: " ")
        switch kind {
        case .task:
            let clock: String = time.map { " " + DotChat.clock($0) } ?? ""
            let extra: String = items.isEmpty ? "" : " (\(stepCount))"
            let at: String = place.isEmpty ? "" : " · bei \(place)"
            return "Aufgabe\(when)\(clock) · \(title)\(extra)\(at)"
        case .steps:
            return "\(stepCount) zu „\(title)“"
        case .schedule:
            return "\(title) eintragen · \(entryCount)"
        case .reminder:
            let clock: String = time.map { " " + DotChat.clock($0) } ?? ""
            return "Erinnerung\(when)\(clock) · \(title)"
        case .shop:
            return "Einkauf · \(title)"
        case .memo:
            return "Merken · \(title)"
        case .focus:
            return "Timer \(max(1, minutes)) Min · \(title)"
        case .done:
            return "Abhaken · \(title)"
        case .tomorrow:
            return "Auf morgen · \(title)"
        }
    }

    var symbol: String {
        switch kind {
        case .task: "checklist"
        case .reminder: "bell"
        case .shop: "bag"
        case .memo: "note.text"
        case .focus: "timer"
        case .done: "checkmark.circle"
        case .tomorrow: "arrow.turn.up.right"
        case .steps: "list.bullet.indent"
        case .schedule: "calendar.badge.plus"
        }
    }

    /// Done-Text nach dem Antippen.
    var doneLabel: String {
        switch kind {
        case .task: "Aufgabe angelegt"
        case .reminder: "Erinnerung steht"
        case .shop: "Auf der Einkaufsliste"
        case .memo: "Gemerkt"
        case .focus: "Timer läuft"
        case .done: "Erledigt: \(title)"
        case .tomorrow: "Liegt jetzt bei morgen"
        case .steps: "Schritte stehen bei „\(title)“"
        case .schedule: "\(entryCount) stehen im Plan"
        }
    }
}

/// Ein Termin aus einem Plan (z. B. vom Foto): Tag ab heute, Uhrzeit, Dauer.
struct PlanEntry: Codable, Hashable {     // nicht „DotEntry“ – den Namen hat das Dot-Widget
    var title: String
    var day: Int                // 0 = heute … 13
    var time: Int               // Minuten seit Mitternacht
    var minutes = 60            // Dauer

    init(title: String, day: Int, time: Int, minutes: Int = 60) {
        self.title = title
        self.day = day
        self.time = time
        self.minutes = minutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        day = (try? c.decodeIfPresent(Int.self, forKey: .day)) ?? 0
        time = (try? c.decodeIfPresent(Int.self, forKey: .time)) ?? 9 * 60
        minutes = (try? c.decodeIfPresent(Int.self, forKey: .minutes)) ?? 60
    }

    /// „bis 10:30“ für die Mitteilung.
    var untilText: String { "bis \(DotChat.clock(time + minutes))" }
}

struct DotMessage: Codable, Identifiable, Hashable {
    var id = UUID()
    var fromDot: Bool
    var text: String
    var at = Date()
    var actions: [DotAction] = []
    var suggestions: [String] = []      // Antworten zum Antippen (nur bei der letzten Dot-Nachricht sichtbar)
    var failed = false                  // Server nicht erreichbar – „Nochmal“ anbieten
    var hasPhoto = false                // mit Foto geschickt (das Bild selbst wird nicht gespeichert)

    init(fromDot: Bool, text: String, actions: [DotAction] = [], suggestions: [String] = [], failed: Bool = false,
         hasPhoto: Bool = false) {
        self.fromDot = fromDot
        self.text = text
        self.actions = actions
        self.suggestions = suggestions
        self.failed = failed
        self.hasPhoto = hasPhoto
    }
}

// Tolerant dekodieren: neue Felder dürfen in alten Dateien fehlen.
extension DotAction {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        kind = (try? c.decodeIfPresent(Kind.self, forKey: .kind)) ?? .memo
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        step = (try? c.decodeIfPresent(String.self, forKey: .step)) ?? ""
        minutes = (try? c.decodeIfPresent(Int.self, forKey: .minutes)) ?? 0
        time = (try? c.decodeIfPresent(Int.self, forKey: .time)) ?? nil
        day = (try? c.decodeIfPresent(Int.self, forKey: .day)) ?? 0
        done = (try? c.decodeIfPresent(Bool.self, forKey: .done)) ?? false
        items = (try? c.decodeIfPresent([String].self, forKey: .items)) ?? []
        entries = (try? c.decodeIfPresent([PlanEntry].self, forKey: .entries)) ?? []
        place = (try? c.decodeIfPresent(String.self, forKey: .place)) ?? ""
    }
}

extension DotMessage {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        fromDot = (try? c.decodeIfPresent(Bool.self, forKey: .fromDot)) ?? true
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
        at = (try? c.decodeIfPresent(Date.self, forKey: .at)) ?? Date()
        actions = (try? c.decodeIfPresent([DotAction].self, forKey: .actions)) ?? []
        suggestions = (try? c.decodeIfPresent([String].self, forKey: .suggestions)) ?? []
        failed = (try? c.decodeIfPresent(Bool.self, forKey: .failed)) ?? false
        hasPhoto = (try? c.decodeIfPresent(Bool.self, forKey: .hasPhoto)) ?? false
    }
}

enum DotChat {
    /// So viele Nachrichten bleiben gespeichert.
    static let keep = 60
    /// So viele gehen als Verlauf an die KI.
    static let sendCount = 12

    /// Ältestes zuerst raus, damit dopa.json klein bleibt.
    static func trimmed(_ messages: [DotMessage]) -> [DotMessage] {
        messages.count > keep ? Array(messages.suffix(keep)) : messages
    }

    /// Verlauf für den Server: ohne Fehlversuche, nur die letzten Nachrichten, jede gekürzt.
    static func history(_ messages: [DotMessage]) -> [(fromDot: Bool, text: String)] {
        messages.filter { !$0.failed && !$0.text.isEmpty }
            .suffix(sendCount)
            .map { (fromDot: $0.fromDot, text: String($0.text.prefix(800))) }
    }

    /// „14:30“ / „9:05“ / „14 Uhr“ → Minuten seit Mitternacht.
    static func parseTime(_ text: String) -> Int? {
        let t = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " Uhr", with: "")
        let parts = t.split(separator: ":").map(String.init)
        guard let h = Int(parts.first ?? ""), (0...23).contains(h) else { return nil }
        let m = parts.count > 1 ? Int(parts[1]) : 0
        guard let m, (0...59).contains(m), parts.count <= 2 else { return nil }
        return h * 60 + m
    }

    static func clock(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    static func dayWord(_ day: Int, prefix: String = "") -> String {
        switch day {
        case 0: ""
        case 1: prefix + "morgen"
        case 2: prefix + "übermorgen"
        default: prefix + "in \(day) Tagen"
        }
    }

    /// Neue Schritte ohne Doppelte (auch nicht untereinander), Groß/klein egal, Reihenfolge bleibt.
    static func newSteps(_ items: [String], existing: [String]) -> [String] {
        var seen: Set<String> = Set(existing.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        var out: [String] = []
        for item in items {
            let title = item.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = title.lowercased()
            guard !title.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(title)
        }
        return out
    }

    /// Tag ab heute als „Mo 6.10.“ (für die Vorschau eines Plans).
    static func dayLabel(_ day: Int, from now: Date, calendar: Calendar = .current) -> String {
        let target = calendar.date(byAdding: .day, value: day, to: calendar.startOfDay(for: now)) ?? now
        let names = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
        let c = calendar.dateComponents([.weekday, .day, .month], from: target)
        return "\(names[((c.weekday ?? 1) - 1) % 7]) \(c.day ?? 0).\(c.month ?? 0)."
    }

    /// „morgen 7:10“ → Datum mit Uhrzeit.
    static func date(day: Int, time: Int, from now: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: now)
        let target = calendar.date(byAdding: .day, value: day, to: start) ?? start
        return calendar.date(bySettingHour: time / 60, minute: time % 60, second: 0, of: target) ?? target
    }

    /// Erinnerung ohne Tag, deren Uhrzeit heute schon vorbei ist → morgen.
    static func reminderDay(time: Int, day: Int, nowMinutes: Int) -> Int {
        day == 0 && time <= nowMinutes ? 1 : day
    }

    /// Welche offene Aufgabe Dot meint: erst genau (ohne Groß/klein), dann „enthält“ in eine Richtung.
    /// Mehrdeutig oder nichts gefunden → nil, dann lieber nichts anfassen.
    static func match(_ title: String, in titles: [String]) -> Int? {
        let want = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !want.isEmpty else { return nil }
        let lower = titles.map { $0.lowercased() }
        if let exact = lower.firstIndex(of: want) { return exact }
        let hits = lower.indices.filter { lower[$0].contains(want) || want.contains(lower[$0]) }
        return hits.count == 1 ? hits[0] : nil
    }

    /// Ort zum Namen: „zhs“, „daheim“, „zu hause“ finden „Zuhause“; sonst wie bei Aufgaben (genau, dann Teil).
    static func matchSpot(_ place: String, in names: [String]) -> Int? {
        let home: Set<String> = ["zhs", "zuhause", "zu hause", "daheim", "home", "heim", "wohnung"]
        let want = place.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if home.contains(want), let i = names.firstIndex(where: { home.contains($0.lowercased()) }) { return i }
        return match(place, in: names)
    }

    /// Einstiege, wenn das Gespräch leer ist – passend zur Tageszeit und Lage.
    static func starters(hour: Int, mood: Int?, openTasks: Int, focusRunning: Bool) -> [String] {
        var list: [String] = []
        if let mood, mood <= 2 { list.append("Heute geht wenig. Was reicht?") }
        if focusRunning {
            list.append("Ich bin abgelenkt")
        } else if openTasks > 0 {
            list.append("Was mach ich jetzt?")
            list.append("Ich komm nicht in die Gänge")
        }
        switch hour {
        case 4..<11: list.append("Plan mir den Vormittag")
        case 11..<18: list.append("Hilf mir, den Rest des Tages zu sortieren")
        case 18..<23: list.append("Was steht morgen an?")
        default: list.append("Ich kann nicht schlafen")
        }
        list.append("Ich hab zu viel im Kopf")
        list.append("Wo hab ich … hingelegt?")
        return Array(list.prefix(4))
    }
}
