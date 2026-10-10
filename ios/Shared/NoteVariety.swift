import Foundation

/// Damit Mitteilungen sich nicht abnutzen (Feedback #49/#50), auch wenn die App tagelang zu bleibt:
/// Tägliche Erinnerungen bekommen – wenn Platz ist – je Wochentag einen eigenen Text.
/// iOS hält nur 64 geplante Mitteilungen; was darüber liegt, wird still verworfen. Deshalb mit Budget.
/// Nur Foundation – läuft auch in den Logik-Tests.
enum NoteVariety {
    /// Unter 64 bleiben, mit Luft für Snooze & Co.
    static let budget = 58

    /// Wie viele der `slots` täglichen Uhrzeiten (wichtigste zuerst) sieben Wochentags-Varianten bekommen,
    /// wenn neben ihnen noch `fixed` andere Mitteilungen geplant sind. Jede Variante kostet 6 Plätze extra.
    static func weeklyCount(slots: Int, fixed: Int, budget: Int = budget) -> Int {
        let free = budget - fixed - slots
        guard slots > 0, free >= 6 else { return 0 }
        return min(slots, free / 6)
    }

    /// `count` Texte aus dem Pool: gemischt, jeder kommt erst wieder, wenn alle dran waren,
    /// und nie zweimal direkt hintereinander.
    static func deal<G: RandomNumberGenerator>(_ pool: [String], count: Int, using rng: inout G) -> [String] {
        let unique = Array(Set(pool.filter { !$0.isEmpty })).sorted()
        guard !unique.isEmpty, count > 0 else { return [] }
        var result: [String] = []
        var deck: [String] = []
        while result.count < count {
            if deck.isEmpty {
                deck = unique.shuffled(using: &rng)
                // Übergang zwischen zwei Durchgängen: nicht derselbe Text zweimal
                if unique.count > 1, let last = result.last, deck.last == last { deck.swapAt(0, deck.count - 1) }
            }
            result.append(deck.removeLast())
        }
        return result
    }

    static func deal(_ pool: [String], count: Int) -> [String] {
        var rng = SystemRandomNumberGenerator()
        return deal(pool, count: count, using: &rng)
    }

    /// Sanfter Stupser, wenn die App länger zu war: 2 und 5 Tage nach dem letzten Öffnen, jeweils am frühen Abend
    /// (morgens ist eh schwer). Bei jedem Öffnen neu geplant – kommt also nur, wenn wirklich Pause war.
    static func comebackDates(lastActive: Date, now: Date, minutes: Int = 18 * 60 + 30,
                              calendar: Calendar = .current) -> [Date] {
        [2, 5].compactMap { days -> Date? in
            guard let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: lastActive)),
                  let at = calendar.date(byAdding: .minute, value: minutes, to: day) else { return nil }
            return at > now ? at : nil
        }
    }

    /// Länger weg gewesen? (fürs Willkommen ohne Vorwurf)
    static func isComeback(lastActive: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let lastActive else { return false }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: lastActive),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        return days >= 2
    }
}
