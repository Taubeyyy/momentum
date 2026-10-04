import AppIntents
import Foundation

// Siri & Kurzbefehle. Laufen im Hintergrund, ohne dass die App aufgeht –
// „Hey Siri, Dopa merken“ ist schneller als Entsperren, App suchen, tippen.

struct RememberIntent: AppIntent {
    static var title: LocalizedStringResource = "Merken"
    static var description = IntentDescription("Merkt sich etwas – Ort, Erledigtes, Absprache oder Notiz.")

    @Parameter(title: "Was", requestValueDialog: "Was soll ich mir merken?")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let kind = MemoKind.detect(text)
        Store.shared.addMemo(text, kind: kind)
        return .result(dialog: "\(kind.emoji) Gemerkt: \(text)")
    }
}

struct FindIntent: AppIntent {
    static var title: LocalizedStringResource = "Wo ist …?"
    static var description = IntentDescription("Sucht in allem, was du dir gemerkt hast, und nennt den neuesten Treffer.")

    @Parameter(title: "Was", requestValueDialog: "Was suchst du?")
    var query: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let words = Smart.searchWords(query)
        let hit = Store.shared.data.memos.first { memo in
            !words.isEmpty && words.allSatisfy { memo.text.localizedStandardContains($0) }
        }
        guard let hit else {
            return .result(dialog: "Dazu hab ich nichts gemerkt.")
        }
        let when = RelativeDateTimeFormatter().localizedString(for: hit.createdAt, relativeTo: .now)
        return .result(dialog: "\(hit.text) – \(when).")
    }
}

struct StartIntent: AppIntent {
    static var title: LocalizedStringResource = "Hilf mir anfangen"
    static var description = IntentDescription("Nimmt eine offene Aufgabe, nennt den winzigen ersten Schritt und startet den Timer.")

    @Parameter(title: "Minuten", default: 5)
    var minutes: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = Store.shared
        if let run = store.data.focus, run.endsAt > .now {
            return .result(dialog: "Läuft schon: \(run.title), bis \(run.endsAt.formatted(date: .omitted, time: .shortened)).")
        }
        let minutes = min(max(self.minutes, 1), 120)
        guard let task = store.pickTask() else {
            store.startFocus(taskID: nil, title: "Fokus", step: "", minutes: minutes)
            return .result(dialog: "Keine offenen Aufgaben – ich starte dir \(minutes) Minuten Fokus.")
        }
        let step = task.firstStep.isEmpty ? Smart.firstStep(for: task.title) : task.firstStep
        store.startFocus(taskID: task.id, title: task.title, step: step, minutes: minutes)
        return .result(dialog: "\(task.title). Erster Schritt: \(step). \(minutes) Minuten laufen.")
    }
}

struct AddShopIntent: AppIntent {
    static var title: LocalizedStringResource = "Auf die Einkaufsliste"
    static var description = IntentDescription("Setzt eine oder mehrere Sachen auf die Einkaufsliste – „Milch, Brot und Eier“.")

    @Parameter(title: "Was", requestValueDialog: "Was soll auf die Liste?")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let names = ShopText.split(text)
        Store.shared.addShop(text)
        return .result(dialog: "Steht drauf: \(names.joined(separator: ", ")).")
    }
}

struct DopaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RememberIntent(), phrases: [
            "\(.applicationName) merken",
            "Merk dir was mit \(.applicationName)",
            "In \(.applicationName) merken",
        ])
        AppShortcut(intent: FindIntent(), phrases: [
            "\(.applicationName) suchen",
            "Frag \(.applicationName) wo was ist",
            "Wo ist was in \(.applicationName)",
        ])
        AppShortcut(intent: AddShopIntent(), phrases: [
            "\(.applicationName) Einkaufsliste",
            "Setz was auf die \(.applicationName) Liste",
            "\(.applicationName) einkaufen",
        ])
        AppShortcut(intent: StartIntent(), phrases: [
            "\(.applicationName) anfangen",
            "Hilf mir anfangen mit \(.applicationName)",
            "Starte \(.applicationName)",
        ])
    }
}
