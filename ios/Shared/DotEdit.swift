import Foundation

/// Was Dot an der App ändern darf (Vorschlag „edit“ – angewendet erst nach dem Tipp).
/// Felder des Vorschlags: `key` = was, `title` = welches Ding (Aufgabe, Gewohnheit …), `step` = neuer Text/Wert,
/// `time` = Uhrzeit, `day` = Tag, `minutes` = Minuten/Anzahl, `items` = Liste (Tage, Zeiten, Schritte).
/// Nur Foundation – läuft in der App und in den Logik-Tests.
enum DotEdit: String, CaseIterable {
    // Routinen
    case morningLeave = "morning.leave"         // time
    case morningDays = "morning.days"           // items: ["Mo", "Di", …] oder ["werktags"]
    case morningAdd = "morning.add"             // step = Schritt, minutes
    case morningRemove = "morning.remove"       // step = Schritt
    case eveningBed = "evening.bed"             // time
    case eveningDays = "evening.days"
    case eveningAdd = "evening.add"
    case eveningRemove = "evening.remove"
    // Erinnerungen
    case mealTimes = "meals.times"              // items: ["12:30", "18:00"]
    case nudgeWindow = "nudges.window"          // items: ["16:00", "23:00"], minutes = alle X Min
    case reminderTime = "reminder.time"         // title = Erinnerung, time
    case reminderDelete = "reminder.delete"     // title
    // Gewohnheiten
    case habitAdd = "habit.add"                 // step = Name, time = Erinnerung (optional), minutes = pro Tag
    case habitRemove = "habit.remove"           // title
    case habitTime = "habit.time"               // title, time ("" = ohne Erinnerung)
    // Aufgaben & Einkauf
    case taskRename = "task.rename"             // title = alt, step = neu
    case taskDelete = "task.delete"             // title
    case taskPlan = "task.plan"                 // title, day (-1 = irgendwann)
    case taskTime = "task.time"                 // title, time, day
    case shopRemove = "shop.remove"             // title
    // Timer
    case timerPresets = "timer.presets"         // items: ["5", "15", "25", "45"]
    case snooze = "snooze"                      // minutes
    // Look
    case theme = "theme"                        // step = Name der Farbe
    case dotName = "dot.name"                   // step = neuer Name
    // Löschen auf Wunsch
    case memoDelete = "memo.delete"             // title = Text der Notiz
    case chatClear = "chat.clear"               // das Gespräch mit Dot leeren
    case shopClear = "shop.clear"               // ganze Einkaufsliste leeren

    /// Wochentage aus Wörtern: „Mo“, „Montag“, „werktags“, „Wochenende“, „täglich“ → 1 = So … 7 = Sa.
    static func weekdays(_ items: [String]) -> [Int] {
        let names: [(String, Int)] = [("so", 1), ("mo", 2), ("di", 3), ("mi", 4), ("do", 5), ("fr", 6), ("sa", 7)]
        var days = Set<Int>()
        for raw in items {
            let word = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if word.hasPrefix("werktag") || word == "mo-fr" || word == "mo–fr" { days.formUnion(2...6); continue }
            if word.hasPrefix("wochenende") { days.formUnion([1, 7]); continue }
            if word.hasPrefix("täglich") || word.hasPrefix("jeden tag") || word == "alle" { days.formUnion(1...7); continue }
            if let hit = names.first(where: { word.hasPrefix($0.0) }) { days.insert(hit.1) }
        }
        return days.sorted()
    }

    /// 2…6 → „Mo–Fr“, alle → „täglich“, sonst „Mo, Mi, Fr“ (Woche ab Montag).
    static func weekdayText(_ days: [Int]) -> String {
        let set = Set(days)
        if set == Set(1...7) { return "täglich" }
        if set == Set(2...6) { return "Mo–Fr" }
        if set == [1, 7] { return "am Wochenende" }
        let names = [2: "Mo", 3: "Di", 4: "Mi", 5: "Do", 6: "Fr", 7: "Sa", 1: "So"]
        return [2, 3, 4, 5, 6, 7, 1].filter { set.contains($0) }.compactMap { names[$0] }.joined(separator: ", ")
    }

    /// Knopf-Text, z. B. „Morgens los um 7:45“ oder „„Mails“ → „Mails beantworten““.
    static func label(_ a: DotAction, now: Date = Date()) -> String {
        guard let edit = DotEdit(rawValue: a.key) else { return "Einstellung ändern" }
        let clock: String = a.time.map { DotChat.clock($0) } ?? "?"
        let list: String = a.items.joined(separator: ", ")
        switch edit {
        case .morningLeave: return "Morgens los um \(clock)"
        case .morningDays: return "Morgen-Check \(weekdayText(weekdays(a.items)))"
        case .morningAdd: return "Morgen-Check: + \(a.step)" + (a.minutes > 0 ? " (\(a.minutes) Min)" : "")
        case .morningRemove: return "Morgen-Check: − \(a.step)"
        case .eveningBed: return "Bettzeit \(clock)"
        case .eveningDays: return "Abendroutine \(weekdayText(weekdays(a.items)))"
        case .eveningAdd: return "Abendroutine: + \(a.step)" + (a.minutes > 0 ? " (\(a.minutes) Min)" : "")
        case .eveningRemove: return "Abendroutine: − \(a.step)"
        case .mealTimes: return "Essens-Erinnerung um \(list)"
        case .nudgeWindow:
            let window: String = a.items.count >= 2 ? "\(a.items[0])–\(a.items[1])" : list
            return "Stupser \(window)" + (a.minutes > 0 ? ", alle \(a.minutes) Min" : "")
        case .reminderTime: return "Erinnerung „\(a.title)“ um \(clock)"
        case .reminderDelete: return "Erinnerung löschen · \(a.title)"
        case .habitAdd: return "Gewohnheit: + \(a.step)" + (a.time.map { " (\(DotChat.clock($0)))" } ?? "")
        case .habitRemove: return "Gewohnheit: − \(a.title)"
        case .habitTime: return a.time == nil ? "„\(a.title)“ ohne Erinnerung" : "„\(a.title)“ um \(clock)"
        case .taskRename: return "„\(a.title)“ → „\(a.step)“"
        case .taskDelete: return "Aufgabe löschen · \(a.title)"
        case .taskPlan:
            let when: String = a.day < 0 ? "irgendwann" : a.day == 0 ? "heute" : a.day == 1 ? "morgen"
                : DotChat.dayLabel(a.day, from: now)
            return "„\(a.title)“ auf \(when)"
        case .taskTime: return "„\(a.title)“\(DotChat.dayWord(max(0, a.day), prefix: " ")) um \(clock)"
        case .shopRemove: return "Von der Einkaufsliste · \(a.title)"
        case .timerPresets: return "Timer-Knöpfe \(list) Min"
        case .snooze: return "„Später“ = \(a.minutes) Min"
        case .theme: return "Farbe: \(a.step)"
        case .dotName: return "Dot heißt jetzt \(a.step)"
        case .memoDelete: return "Notiz löschen · \(a.title)"
        case .chatClear: return "Unser Gespräch leeren"
        case .shopClear: return "Einkaufsliste leeren"
        }
    }
}
