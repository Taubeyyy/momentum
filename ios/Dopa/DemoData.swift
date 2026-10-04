import Foundation

extension Store {
    /// Nur für den Simulator-Rundgang im CI (Startargument „-uitest“): ein paar Beispiele,
    /// damit die Bildschirme nicht leer sind. Auf dem Handy passiert hier nichts.
    func seedDemoIfEmpty() {
        guard data.tasks.isEmpty, data.memos.isEmpty else { return }
        addTask("Wäsche waschen")
        addTask("Mama anrufen")
        addTask("Bewerbung abschicken")
        if let first = data.tasks.first {
            addStep(first.id, "Anschreiben öffnen", minutes: 5)
            addStep(first.id, "Lebenslauf anhängen", minutes: 10)
            makeTheOne(first.id)
        }
        addMemo("Schlüssel liegt auf der Kommode", kind: .place, xp: nil)
        addMemo("Herd ist aus", kind: .done, xp: nil)
        addShop("Milch, Brot, Eier, Bananen, Klopapier")
        addEntry("4,50 Döner")
        addEntry("12 Bahn")
        addEntry("+20 Oma")
        saveReminder(CustomReminder(title: "Tabletten", minutes: 8 * 60))
        saveReminder(CustomReminder(title: "Wäsche aufhängen", minutes: 18 * 60 + 30))
    }
}
