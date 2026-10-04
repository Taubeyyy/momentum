import Foundation

/// Regelbasiertes „Mitdenken“ ohne KI und ohne Internet:
/// erkennt, was für eine Notiz das ist, und schlägt winzige erste Schritte vor.
enum MemoKind: String, Codable, CaseIterable, Identifiable {
    case place, done, agreement, note

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .place: "📍"
        case .done: "✔︎"
        case .agreement: "💬"
        case .note: "🧠"
        }
    }

    var label: String {
        switch self {
        case .place: "Ort"
        case .done: "Erledigt"
        case .agreement: "Absprache"
        case .note: "Notiz"
        }
    }

    /// „Herd ist aus“ → erledigt, „Schlüssel liegt auf der Kommode“ → Ort,
    /// „Frau M. sagt: Bastelsachen statt Malsachen“ → Absprache.
    static func detect(_ text: String) -> MemoKind {
        let t = " " + text.lowercased() + " "
        // „Hab den Schlüssel auf den Tisch gelegt“ ist ein Ort, kein Erledigt
        if Smart.containsAny(t, ["gelegt", "gestellt", "gehängt", "gesteckt", "verstaut", "gepackt "]) {
            return .place
        }
        if Smart.containsAny(t, [" hab ", " habe ", "erledigt", "gemacht", " ist aus ", " ist zu ", " sind aus ",
                                 "ausgemacht ", "zugemacht", "abgeschlossen", "genommen", "abgeschickt",
                                 "bezahlt", "gegessen", "gefüttert", "eingeworfen", "✔", "✅"]) {
            return .done
        }
        if Smart.containsAny(t, [" liegt ", " liegen ", " steht ", " stehen ", " hängt ", " steckt ",
                                 " ist im ", " ist in ", " ist auf ", " ist unter ", " ist bei ",
                                 " ist hinter ", " ist neben ", " sind im ", " sind in ", " sind auf "]) {
            return .place
        }
        if Smart.containsAny(t, [" sagt", " sagte", " meint", " soll ", " sollen ", " statt ",
                                 "vereinbart", "abgemacht", " treffen ", " nicht vergessen"]) {
            return .agreement
        }
        return .note
    }
}

enum Smart {
    static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }

    /// Stichwort → winziger erster Schritt. Reihenfolge zählt: Spezielles zuerst.
    private static let stepRules: [([String], String)] = [
        (["termin", "arzt", "zahnarzt"], "Nur die Nummer oder Website raussuchen"),
        (["anruf", "anrufen", "telefon"], "Nur die Nummer raussuchen"),
        (["rechnung", "bezahl", "überweis", "klarna", "paypal"], "Nur die App öffnen und den Betrag anschauen"),
        (["bewerb", "formular", "antrag", "brief", "unterlagen"], "Nur das Dokument öffnen und den Namen eintragen"),
        (["einkauf", "besorgen", "kaufen"], "Nur aufschreiben, was fehlt"),
        (["mail", "nachricht", "antwort", "schreib"], "Nur den ersten Satz schreiben – egal wie schlecht"),
        (["wäsche", "waesche"], "Nur die Wäsche in einen Korb werfen"),
        (["geschirr", "spül", "tasse", "teller", "küche"], "Nur die Tassen in die Küche bringen"),
        (["aufräum", "zimmer", "ordnung", "schreibtisch"], "Nur 5 Sachen an ihren Platz legen"),
        (["müll", "muell"], "Nur den Beutel zubinden"),
        (["lern", "hausaufgabe", "üben", "vokabel", "klausur", "prüfung", "referat"], "Nur das Heft oder Buch aufschlagen"),
        (["code", "coden", "programm", "bug", "fix", "server", "deploy", "script"], "Nur das Projekt öffnen und die letzte Änderung anschauen"),
        (["dusch", "zähne", "zaehne", "rasier"], "Nur ins Bad gehen"),
        (["sport", "training", "gym", "joggen", "laufen"], "Nur die Sportsachen anziehen"),
        (["kochen", " essen"], "Nur nachschauen, was da ist"),
        (["pack", "tasche", "koffer"], "Nur die Tasche hinlegen und aufmachen"),
        (["lesen", "buch"], "Nur eine Seite lesen"),
        (["video", "schneid", "edit"], "Nur das Projekt öffnen"),
    ]

    private static let generalSteps = [
        "Nur hinsetzen und es aufmachen",
        "Alles Nötige hinlegen",
        "Nur anschauen, was zu tun ist",
        "2 Minuten, dann darf ich aufhören",
    ]

    static func firstStep(for title: String) -> String {
        let t = " " + title.lowercased() + " "
        return stepRules.first { containsAny(t, $0.0) }?.1 ?? generalSteps[0]
    }

    /// Passender Vorschlag zuerst, dann die allgemeinen.
    static func stepOptions(for title: String) -> [String] {
        var options = [firstStep(for: title)]
        for step in generalSteps where !options.contains(step) {
            options.append(step)
        }
        return options
    }

    /// „Wo ist mein Schlüssel?“ → ["schlüssel"]
    static func searchWords(_ query: String) -> [String] {
        var q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        q = q.trimmingCharacters(in: CharacterSet(charactersIn: "?!."))
        for prefix in ["wo ist ", "wo sind ", "wo liegt ", "wo liegen ", "hab ich ", "habe ich ", "wo "]
        where q.hasPrefix(prefix) {
            q.removeFirst(prefix.count)
            break
        }
        let filler: Set<String> = ["mein", "meine", "meinen", "der", "die", "das", "den", "ich", "schon", "heute"]
        return q.split(separator: " ").map(String.init).filter { !filler.contains($0) }
    }
}
