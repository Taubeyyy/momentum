import Foundation

/// Wofür das Geld weg ist – grob genug, dass Eintragen nie Nachdenken braucht.
enum SpendKind: String, Codable, CaseIterable, Identifiable {
    case food, groceries, transport, fun, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .food: "Essen"
        case .groceries: "Einkauf"
        case .transport: "Unterwegs"
        case .fun: "Spaß"
        case .other: "Sonstiges"
        }
    }

    var symbol: String {
        switch self {
        case .food: "fork.knife"
        case .groceries: "cart"
        case .transport: "tram"
        case .fun: "gamecontroller"
        case .other: "circle.grid.2x2"
        }
    }

    private static let rules: [(SpendKind, [String])] = [
        (.groceries, ["lidl", "aldi", "rewe", "edeka", "kaufland", "netto", "penny", "dm", "rossmann",
                      "einkauf", "supermarkt", "lebensmittel", "drogerie"]),
        (.food, ["döner", "doener", "pizza", "burger", "mcdonalds", "mcdonald", "mcd", "mäcces", "kfc", "subway",
                 "kebab", "bäcker", "baecker", "kaffee", "coffee", "mensa", "imbiss", "lieferando", "wolt",
                 "essen", "snack", "pommes", "sushi", "nudelbox", "brötchen", "getränk", "energy"]),
        (.transport, ["bahn", "ticket", "tanken", "sprit", "bus", "uber", "taxi", "deutschlandticket",
                      "parken", "fahrkarte", "zug", "flix", "roller", "bolt"]),
        (.fun, ["kino", "steam", "game", "spiel", "playstation", "xbox", "nintendo", "robux", "skin",
                "battle pass", "konzert", "party", "bar", "club", "zalando", "shein", "klamotten",
                "amazon", "temu", "geschenk", "vbucks", "v-bucks", "spotify", "netflix", "twitch"]),
    ]

    /// Kurze Stichwörter (≤ 3 Zeichen) nur als ganzes Wort – sonst wäre „Busch“ Unterwegs.
    static func detect(_ title: String) -> SpendKind {
        let lower = title.lowercased()
        let words = Set(lower.split(whereSeparator: { !$0.isLetter }).map(String.init))
        for (kind, keywords) in rules {
            for keyword in keywords where keyword.count <= 3 ? words.contains(keyword) : lower.contains(keyword) {
                return kind
            }
        }
        return .other
    }
}

/// Rechnungen für den Geld-Überblick – ohne UI, damit die Logik-Tests sie prüfen können.
enum MoneyMath {
    struct Month: Equatable {
        var income: Double
        var fixed: Double
        var debts: Double           // Raten dieses Monats: schon bezahlt + noch offen (Überfälliges zählt mit)
        var extra: Double = 0       // einmalige Einnahmen aus dem Tagebuch („+20 Oma“)
        var spent: Double = 0       // Ausgaben aus dem Tagebuch

        /// Was nach festen Kosten und Raten zum Ausgeben da ist.
        var free: Double { income + extra - fixed - debts }
        /// Davon noch übrig, nach dem, was schon ausgegeben ist.
        var left: Double { free - spent }
    }

    /// „4,50 Döner“, „Döner 4.50€“, „+20 Oma“, „20 € von Oma bekommen“ → Betrag, Titel, Einnahme?
    static func parseEntry(_ text: String) -> (amount: Double, title: String, income: Bool)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: #"([+-]?)\s*(\d{1,5}(?:[.,]\d{1,2})?)\s*(?:€|euro|eur)?"#,
                                                   options: .caseInsensitive),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let numberRange = Range(match.range(at: 2), in: trimmed),
              let whole = Range(match.range, in: trimmed) else { return nil }
        let amount = parse(String(trimmed[numberRange]))
        guard amount > 0 else { return nil }
        let sign = Range(match.range(at: 1), in: trimmed).map { String(trimmed[$0]) } ?? ""
        var title = trimmed
        title.removeSubrange(whole)
        title = title.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let lower = title.lowercased()
        let incomeWords = ["bekommen", "gekriegt", "verdient", "lohn", "gehalt", "taschengeld", "zurückbekommen",
                           "zurück bekommen", "erstattet", "geschenkt bekommen"]
        let income = sign == "+" || incomeWords.contains { lower.contains($0) }
        if title.isEmpty { title = income ? "Einnahme" : "Ausgabe" }
        return (amount, title.prefix(1).uppercased() + title.dropFirst(), income)
    }

    /// „12 Bahn, 3 Kaffee und 4,50 Döner“ → drei Einträge. Nur Komma mit Leerzeichen danach trennt,
    /// sonst wäre „4,50“ kaputt.
    static func splitEntries(_ text: String) -> [String] {
        guard let pattern = try? NSRegularExpression(pattern: #",\s+|\s+und\s+|\n"#, options: .caseInsensitive) else {
            return [text]
        }
        let range = NSRange(text.startIndex..., in: text)
        let marked = pattern.stringByReplacingMatches(in: text, range: range, withTemplate: "|")
        return marked.split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Ausgaben pro Tag für die Woche von `weekStart` (Mo) an – sieben Werte.
    static func week(_ entries: [Spend], weekStart: Date) -> [Double] {
        let cal = Calendar.current
        return (0..<7).map { offset in
            guard let day = cal.date(byAdding: .day, value: offset, to: weekStart) else { return 0 }
            return entries.filter { !$0.income && cal.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.amount }
        }
    }

    /// Ausgaben dieses Monats nach Art, größte zuerst.
    static func byKind(_ entries: [Spend]) -> [(kind: SpendKind, amount: Double)] {
        Dictionary(grouping: entries.filter { !$0.income }, by: \.kind)
            .map { (kind: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.amount > $1.amount }
    }

    static func monthKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    static func month(_ items: [MoneyItem], payments: [Payment], entries: [Spend] = [], now: Date = Date()) -> Month {
        let cal = Calendar.current
        let key = monthKey(now)
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        let monthEnd = cal.date(byAdding: .month, value: 1, to: monthStart) ?? now

        let income = items.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount }
        let fixed = items.filter { $0.kind == .fixed }.reduce(0) { $0 + $1.amount }
        let paid = payments.filter { monthKey($0.date) == key }.reduce(0) { $0 + $1.amount }
        var open = 0.0
        for item in items where item.kind == .debt {
            guard var due = item.due else { continue }
            var count = 0
            while due < monthEnd && count < item.remaining {
                count += 1
                due = cal.date(byAdding: .month, value: 1, to: due) ?? monthEnd
            }
            open += Double(count) * item.amount
        }
        let thisMonth = entries.filter { monthKey($0.date) == key }
        let extra = thisMonth.filter(\.income).reduce(0) { $0 + $1.amount }
        let spent = thisMonth.filter { !$0.income }.reduce(0) { $0 + $1.amount }
        return Month(income: income, fixed: fixed, debts: paid + open, extra: extra, spent: spent)
    }

    /// Nach „Bezahlt“: eine Rate weniger, nächste einen Monat später. nil = abbezahlt.
    static func afterPayment(_ item: MoneyItem) -> MoneyItem? {
        guard item.remaining > 1 else { return nil }
        var next = item
        next.remaining -= 1
        next.due = item.due.flatMap { Calendar.current.date(byAdding: .month, value: 1, to: $0) }
        return next
    }

    /// Gekoppeltes Spaß-Budget: Anteil vom Freien, auf 5 € abgerundet, nie negativ.
    static func linkedBudget(free: Double, share: Double) -> Double {
        guard free > 0, share > 0 else { return 0 }
        return (free * share / 5).rounded(.down) * 5
    }

    /// Alles, was insgesamt noch offen ist.
    static func openTotal(_ items: [MoneyItem]) -> Double {
        items.filter { $0.kind == .debt }.reduce(0) { $0 + $1.amount * Double($1.remaining) }
    }

    /// Tage bis zur Fälligkeit (0 = heute, negativ = überfällig).
    static func daysUntil(_ date: Date, now: Date = Date()) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
    }

    /// „heute fällig“, „morgen fällig“, „seit 3 Tagen offen“, „fällig 5.10.“
    static func dueText(_ date: Date, now: Date = Date()) -> String {
        let days = daysUntil(date, now: now)
        switch days {
        case ..<(-1): return "seit \(-days) Tagen offen"
        case -1: return "seit gestern offen"
        case 0: return "heute fällig"
        case 1: return "morgen fällig"
        case 2...6: return "in \(days) Tagen fällig"
        default:
            let c = Calendar.current.dateComponents([.day, .month], from: date)
            return "fällig \(c.day ?? 0).\(c.month ?? 0)."
        }
    }

    static func euro(_ value: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.numberStyle = .currency
        f.currencyCode = "EUR"
        f.maximumFractionDigits = value.rounded() == value ? 0 : 2
        f.minimumFractionDigits = f.maximumFractionDigits
        return f.string(from: NSNumber(value: value)) ?? "\(value) €"
    }

    /// „12,50“ / „12.5“ / „12 €“ → 12.5
    static func parse(_ text: String) -> Double {
        let cleaned = text.replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespaces)
        return Double(cleaned) ?? 0
    }
}
