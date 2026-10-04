import Foundation

/// Eigene Zeiten (Timer, Countdown, Dranbleiben) und Schlaf-Rechnung.
/// Nur Foundation – läuft in der App und in den Logik-Tests.
enum Timing {
    /// „10, 5“ / „25 15 5“ → [25, 15, 5]: absteigend, ohne Doppelte, nur 1…max.
    static func parseList(_ text: String, max: Int = 180) -> [Int] {
        let numbers = text.split { !$0.isNumber }.compactMap { Int($0) }.filter { $0 >= 1 && $0 <= max }
        return Array(Set(numbers)).sorted(by: >)
    }

    static func listText(_ list: [Int]) -> String {
        list.map { String($0) }.joined(separator: ", ")
    }

    /// Countdown-Zeitpunkte vor dem Losgehen – nur die, die noch kommen.
    static func countdown(leave: Date, offsets: [Int], now: Date) -> [(minutes: Int, at: Date)] {
        offsets.filter { $0 > 0 }
            .map { (minutes: $0, at: leave.addingTimeInterval(-Double($0) * 60)) }
            .filter { $0.at > now }
    }

    /// Halbzeit nur bei Timern ab 4 Minuten – darunter nervt es nur.
    static func halfway(start: Date, end: Date) -> Date? {
        let total = end.timeIntervalSince(start)
        guard total >= 4 * 60 else { return nil }
        return start.addingTimeInterval(total / 2)
    }

    /// Schlaf: Uhr und Handy melden oft dieselbe Zeit doppelt – überlappende Abschnitte nur einmal zählen.
    static func asleepSeconds(_ intervals: [(start: Date, end: Date)]) -> TimeInterval {
        let sorted = intervals.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        var total: TimeInterval = 0
        var currentStart: Date?
        var currentEnd: Date?
        for i in sorted {
            if let s = currentStart, let e = currentEnd, i.start <= e {
                currentStart = s
                currentEnd = Swift.max(e, i.end)
            } else {
                if let s = currentStart, let e = currentEnd { total += e.timeIntervalSince(s) }
                currentStart = i.start
                currentEnd = i.end
            }
        }
        if let s = currentStart, let e = currentEnd { total += e.timeIntervalSince(s) }
        return total
    }

    /// Schlaf pro Nacht. Eine Nacht gehört zu dem Tag, an dem sie anfängt: Ende minus 12 Std → Tag
    /// (23–7 Uhr zählt zu gestern, ein Mittagsschlaf zu heute). Schlüssel = Tagesanfang.
    static func nightly(_ intervals: [(start: Date, end: Date)], calendar: Calendar = .current) -> [Date: TimeInterval] {
        let grouped = Dictionary(grouping: intervals) { calendar.startOfDay(for: $0.end.addingTimeInterval(-12 * 3600)) }
        return grouped.mapValues { asleepSeconds($0) }
    }

    /// Schnitt über die Nächte mit Daten (ohne die leeren).
    static func average(_ nights: [Date: TimeInterval]) -> TimeInterval? {
        let values = nights.values.filter { $0 > 0 }
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// 3214 → „3.214“
    static func thousands(_ n: Int) -> String {
        let digits = String(abs(n))
        var out = ""
        for (i, ch) in digits.enumerated() {
            if i > 0 && (digits.count - i) % 3 == 0 { out += "." }
            out.append(ch)
        }
        return (n < 0 ? "-" : "") + out
    }

    /// Eine Zeile für Dot: was die Uhr über Schlaf und Bewegung weiß. Nil, wenn nichts da ist.
    static func healthLine(sleep: TimeInterval?, average: TimeInterval?, bed: Date?, woke: Date?,
                           steps: Int?, exercise: Int?) -> String? {
        var parts: [String] = []
        if let sleep, sleep > 0 {
            var s = "letzte Nacht \(hoursText(sleep)) Schlaf"
            if let bed, let woke { s += " (\(clock(bed))–\(clock(woke)))" }
            if let average { s += ", Schnitt 7 Nächte \(hoursText(average))" }
            parts.append(s)
        }
        var move: [String] = []
        if let steps { move.append("\(thousands(steps)) Schritte") }
        if let exercise, exercise > 0 { move.append("\(exercise) Min Bewegung") }
        if !move.isEmpty { parts.append("heute bisher " + move.joined(separator: ", ")) }
        guard !parts.isEmpty else { return nil }
        let hint = shortNight(sleep) ? " – kurze Nacht: heute weniger, kleinere Schritte, Pausen einplanen." : ""
        return "Apple Watch: " + parts.joined(separator: "; ") + hint
    }

    /// „5:20 Std“
    static func hoursText(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        return "\(minutes / 60):" + String(format: "%02d", minutes % 60) + " Std"
    }

    /// Uhrzeit einer Aufgabe auf einen anderen Tag legen (z. B. „Morgen“ getippt) – die Uhrzeit bleibt.
    static func moveTime(_ time: Date, to day: Date, calendar: Calendar = .current) -> Date {
        let t = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: t.hour ?? 9, minute: t.minute ?? 0, second: 0, of: day) ?? day
    }

    /// Vorschlag, wenn du einer Aufgabe eine Uhrzeit gibst: heute die nächste volle Stunde, an anderen Tagen 9 Uhr.
    static func defaultTaskTime(day: Date?, now: Date, calendar: Calendar = .current) -> Date {
        if let day, !calendar.isDate(day, inSameDayAs: now), day > now {
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
        }
        let next = now.addingTimeInterval(3600)
        let hour = calendar.component(.hour, from: next)
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: next) ?? next
    }

    /// „14:30“
    static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// Kurze Nacht = unter 6 Stunden. Ohne Daten: nein.
    static func shortNight(_ seconds: TimeInterval?) -> Bool {
        guard let seconds, seconds > 0 else { return false }
        return seconds < 6 * 3600
    }
}
