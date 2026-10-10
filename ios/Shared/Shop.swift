import Foundation

/// Gänge im Supermarkt – die Liste wird in dieser Reihenfolge sortiert,
/// damit du nicht dreimal durch den Laden läufst.
enum ShopCategory: String, Codable, CaseIterable, Identifiable {
    case produce, bakery, dairy, meat, frozen, pantry, snacks, drinks, household, other

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .produce: "🥦"
        case .bakery: "🥖"
        case .dairy: "🥛"
        case .meat: "🍗"
        case .frozen: "🧊"
        case .pantry: "🍝"
        case .snacks: "🍫"
        case .drinks: "🥤"
        case .household: "🧴"
        case .other: "🛒"
        }
    }

    var label: String {
        switch self {
        case .produce: "Obst & Gemüse"
        case .bakery: "Brot"
        case .dairy: "Kühlregal"
        case .meat: "Fleisch & Fisch"
        case .frozen: "Tiefkühl"
        case .pantry: "Vorrat"
        case .snacks: "Snacks"
        case .drinks: "Getränke"
        case .household: "Drogerie & Haushalt"
        case .other: "Sonstiges"
        }
    }

    /// Reihenfolge der Prüfung ≠ Reihenfolge im Laden: Spezielles zuerst
    /// („Kartoffelchips“ sind Snacks, nicht Gemüse; „Erdnussbutter“ ist Vorrat, nicht Kühlregal).
    private static let rules: [(ShopCategory, [String])] = [
        (.household, ["klopapier", "toilettenpapier", "zahnpasta", "zahnbürste", "shampoo", "duschgel", "deo",
                      "spülmittel", "waschmittel", "müllbeutel", "küchenrolle", "taschentücher", "seife",
                      "schwamm", "rasier", "handcreme", "batterie", "tabs", "reiniger"]),
        (.drinks, ["wasser", "cola", "saft", "energy", "monster", "redbull", "red bull", "bier", "tee", "kaffee",
                   "eistee", "sprudel", "limo", "fanta", "sprite", "club-mate", "clubmate", "smoothie"]),
        (.snacks, ["chips", "schoko", "riegel", "kekse", "gummi", "süßigkeit", "nüsse", "cashew", "studentenfutter", "popcorn",
                   "cracker", "haribo", "kinder", "twix", "snickers", "brezel"]),
        (.frozen, ["tk", "tiefkühl", "pizza", "pommes", "eis", "fischstäbchen", "gefroren", "nuggets"]),
        (.pantry, ["nudeln", "pasta", "spaghetti", "reis", "mehl", "zucker", "salz", "öl", "olivenöl", "soße", "sauce",
                   "ketchup", "mayo", "senf", "konserve", "dose", "müsli", "cornflakes", "haferflocken",
                   "tomatenmark", "gewürz", "honig", "marmelade", "nutella", "erdnussbutter", "brühe", "linsen"]),
        (.meat, ["hähnchen", "huhn", "fleisch", "hack", "wurst", "salami", "schinken", "würstchen", "fisch",
                 "lachs", "steak", "schnitzel", "aufschnitt", "döner"]),
        (.dairy, ["milch", "joghurt", "jogurt", "käse", "butter", "quark", "sahne", "eier", "skyr", "pudding",
                  "margarine", "frischkäse", "mozzarella", "feta", "ei"]),
        (.bakery, ["brot", "brötchen", "toast", "baguette", "croissant", "wraps", "tortilla", "brezn"]),
        (.produce, ["apfel", "äpfel", "banane", "tomate", "gurke", "salat", "kartoffel", "zwiebel", "paprika",
                    "möhre", "karotte", "obst", "gemüse", "zitrone", "avocado", "beeren", "trauben",
                    "knoblauch", "pilze", "champignon", "brokkoli", "zucchini", "mais", "orange", "mandarine"]),
    ]

    /// Kurze Stichwörter (≤ 3 Zeichen) nur als ganzes Wort – sonst wäre „Reis“ Tiefkühl („eis“).
    static func detect(_ name: String) -> ShopCategory {
        let lower = name.lowercased()
        let words = Set(lower.split(whereSeparator: { !$0.isLetter }).map(String.init))
        for (category, keywords) in rules {
            for keyword in keywords {
                if keyword.count <= 3 ? words.contains(keyword) : lower.contains(keyword) {
                    return category
                }
            }
        }
        return .other
    }
}

/// Eigene Preise: pro Stück gemerkt („2x Milch“ für 2,18 € → Milch 1,09 €), beim nächsten Mal × Menge.
enum PriceBook {
    /// Wie viele Stück? „2x Milch“, „2 x Milch“, „3 Äpfel“ → 2, 2, 3. Größen („1 kg Mehl“, „500 g“) zählen als 1.
    static func count(_ name: String) -> Int {
        let words: [String] = name.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = words.first, words.count > 1 else { return 1 }
        let sizes: Set<String> = ["kg", "g", "l", "ml", "gramm", "liter"]
        var n: Int?
        if first.hasSuffix("x"), let value = Int(first.dropLast()) {
            n = value
        } else if let value = Int(first), !sizes.contains(words[1]) {
            n = value
        }
        return min(50, max(1, n ?? 1))
    }

    /// Preis pro Stück aus einem eingetragenen Gesamtpreis.
    static func unitPrice(total: Double, name: String) -> Double {
        (total / Double(count(name)) * 100).rounded() / 100
    }

    /// Eigener Preis für einen Eintrag: Stückpreis × Menge, sonst nil.
    static func price(for name: String, own: [String: Double]) -> Double? {
        guard let unit = own[ShopText.key(name)] else { return nil }
        return (unit * Double(count(name)) * 100).rounded() / 100
    }
}

enum ShopText {
    /// „2x Milch“, „1 kg Mehl“ → „milch“, „mehl“ – damit die Kauf-Statistik zusammenpasst.
    static func key(_ name: String) -> String {
        var words = name.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
        let amount = #/^\d+([.,]\d+)?(x|kg|g|l|ml|stk|st|pck)?$/#
        let units: Set<String> = ["x", "kg", "g", "l", "ml", "stk", "stück", "pck", "packung", "flasche", "flaschen"]
        while let first = words.first, words.count > 1, first.wholeMatch(of: amount) != nil || units.contains(first) {
            words.removeFirst()
        }
        return words.joined(separator: " ")
    }

    /// „Milch, Brot und Eier“ → ["Milch", "Brot", "Eier"].
    /// Diktiert/Siri kommt oft ohne Komma („Milch Brot Eier“): Sind alle Wörter bekannte Sachen,
    /// wird an Leerzeichen getrennt – „Rote Paprika“ bleibt zusammen, weil „rote“ nichts Eigenes ist.
    static func split(_ input: String, known: Set<String> = []) -> [String] {
        input
            .replacingOccurrences(of: " und ", with: ",")
            .replacingOccurrences(of: " Und ", with: ",")
            .replacingOccurrences(of: "\n", with: ",")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .flatMap { part -> [String] in
                let words = part.split(separator: " ").map(String.init)
                guard words.count >= 2,
                      words.allSatisfy({ ShopCategory.detect($0) != .other || known.contains(key($0)) }) else { return [part] }
                return words
            }
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
    }

    /// Gang-Reihenfolge aus dem Abhaken lernen: Die Gänge, in denen du diesmal etwas geholt hast,
    /// nehmen ihre bisherigen Plätze in der neuen Reihenfolge ein; alle anderen bleiben, wo sie sind.
    static func learnOrder(current: [ShopCategory], seen: [ShopCategory]) -> [ShopCategory] {
        var unique: [ShopCategory] = []
        for c in seen where !unique.contains(c) { unique.append(c) }
        let slots = current.indices.filter { unique.contains(current[$0]) }
        guard slots.count == unique.count else { return current }
        var result = current
        for (slot, category) in zip(slots, unique) { result[slot] = category }
        return result
    }
}
