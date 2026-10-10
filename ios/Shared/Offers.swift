import Foundation

/// Prospekte: Angebote aus einem Foto/Screenshot (z. B. kaufDA-App oder Papier) mit Preis und Gültigkeit.
/// Regional sind sie, weil sie aus deinen eigenen Prospekten kommen. Nur Foundation – auch in den Logik-Tests.

struct Offer: Codable, Hashable {
    var name: String
    var price = 0.0                 // 0 = kein Preis erkannt
    var unit = ""                   // „100 g“
    var note = ""                   // „-30 %“, „nur mit App“

    init(name: String, price: Double = 0, unit: String = "", note: String = "") {
        self.name = name
        self.price = price
        self.unit = unit
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        price = (try? c.decodeIfPresent(Double.self, forKey: .price)) ?? 0
        unit = (try? c.decodeIfPresent(String.self, forKey: .unit)) ?? ""
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
    }
}

struct Flyer: Codable, Identifiable, Hashable {
    var id = UUID()
    var store: String
    var validFrom: Date?
    var validTo: Date?
    var added = Date()
    var offers: [Offer]

    init(store: String, validFrom: Date? = nil, validTo: Date? = nil, added: Date = Date(), offers: [Offer]) {
        self.store = store
        self.validFrom = validFrom
        self.validTo = validTo
        self.added = added
        self.offers = offers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        store = (try? c.decodeIfPresent(String.self, forKey: .store)) ?? ""
        validFrom = (try? c.decodeIfPresent(Date.self, forKey: .validFrom)) ?? nil
        validTo = (try? c.decodeIfPresent(Date.self, forKey: .validTo)) ?? nil
        added = (try? c.decodeIfPresent(Date.self, forKey: .added)) ?? Date()
        offers = (try? c.decodeIfPresent([Offer].self, forKey: .offers)) ?? []
    }

    var storeName: String { store.isEmpty ? "Prospekt" : store }
}

enum Offers {
    /// Ohne erkanntes Enddatum bleibt ein Prospekt so lange stehen.
    static let keepDays = 10

    /// Noch gültig? Enddatum zählt bis Tagesende; ohne Datum: ab Einlesen `keepDays` Tage.
    static func isActive(_ flyer: Flyer, now: Date, calendar: Calendar = .current) -> Bool {
        let today = calendar.startOfDay(for: now)
        if let end = flyer.validTo { return calendar.startOfDay(for: end) >= today }
        let until = calendar.date(byAdding: .day, value: keepDays, to: calendar.startOfDay(for: flyer.added)) ?? flyer.added
        return until >= today
    }

    /// Gilt erst ab einem späteren Tag („ab Mo“)?
    static func isUpcoming(_ flyer: Flyer, now: Date, calendar: Calendar = .current) -> Bool {
        guard let start = flyer.validFrom else { return false }
        return calendar.startOfDay(for: start) > calendar.startOfDay(for: now)
    }

    static func active(_ flyers: [Flyer], now: Date) -> [Flyer] {
        flyers.filter { isActive($0, now: now) }
    }

    /// „bis Sa 11.10.“ / „ab Mo 13.10. · bis Sa 18.10.“ / „“
    static func validText(_ flyer: Flyer, now: Date, calendar: Calendar = .current) -> String {
        let days: (Date) -> Int = { date in
            calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        }
        var parts: [String] = []
        if isUpcoming(flyer, now: now), let start = flyer.validFrom {
            parts.append("ab \(DotChat.dayLabel(days(start), from: now))")
        }
        if let end = flyer.validTo { parts.append("bis \(DotChat.dayLabel(days(end), from: now))") }
        return parts.joined(separator: " · ")
    }

    /// Suche in allen gültigen Prospekten: alle Wörter müssen im Namen stecken. Günstigste zuerst.
    static func search(_ query: String, in flyers: [Flyer], now: Date) -> [(offer: Offer, flyer: Flyer)] {
        let words: [String] = query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        guard !words.isEmpty else { return [] }
        var hits: [(offer: Offer, flyer: Flyer)] = []
        for flyer in active(flyers, now: now) {
            for offer in flyer.offers {
                let name = offer.name.lowercased()
                if words.allSatisfy({ name.contains($0) }) { hits.append((offer: offer, flyer: flyer)) }
            }
        }
        return hits.sorted { ($0.offer.price == 0 ? .greatestFiniteMagnitude : $0.offer.price)
            < ($1.offer.price == 0 ? .greatestFiniteMagnitude : $1.offer.price) }
    }

    /// Angebot für einen Artikel der Einkaufsliste („2x Milch“ → Milch-Angebote), günstigstes zuerst.
    static func best(for item: String, in flyers: [Flyer], now: Date) -> (offer: Offer, flyer: Flyer)? {
        let key = ShopText.key(item)
        guard key.count >= 3 else { return nil }
        return search(key, in: flyers, now: now).first
    }

    /// Prospekt-Link aus geteiltem Text („Sieh dir mal diesen Kaufland-Prospekt … an! https://…“).
    /// kaufDA teilt einen Weiterleitungs-Link (adj.st) – dahinter steckt in `adjust_fallback` die Web-Ansicht.
    static func flyerURL(from text: String) -> URL? {
        let candidates: [String] = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            .filter { $0.hasPrefix("http://") || $0.hasPrefix("https://") }
        guard let raw = candidates.first, let url = URL(string: raw) else { return nil }
        if let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let fallback = parts.queryItems?.first(where: { $0.name == "adjust_fallback" })?.value,
           let target = URL(string: fallback), target.scheme == "https" {
            return target
        }
        return url.scheme == "https" ? url : nil
    }

    /// Seiten desselben Prospekts zusammenlegen: gleiche Angebote (Name, Groß/klein egal) nur einmal.
    static func merge(_ offers: [Offer], into existing: [Offer]) -> [Offer] {
        var seen = Set(existing.map { $0.name.lowercased() })
        var result = existing
        for offer in offers where !seen.contains(offer.name.lowercased()) {
            seen.insert(offer.name.lowercased())
            result.append(offer)
        }
        return result
    }

    /// „Lidl 0,99 € (100 g) · bis Sa 11.10.“
    static func dealText(_ hit: (offer: Offer, flyer: Flyer), now: Date) -> String {
        var s = hit.flyer.storeName
        if hit.offer.price > 0 { s += " " + MoneyMath.euro(hit.offer.price) }
        if !hit.offer.unit.isEmpty { s += " (\(hit.offer.unit))" }
        let valid = validText(hit.flyer, now: now)
        return valid.isEmpty ? s : s + " · " + valid
    }
}
