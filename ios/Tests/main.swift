import Foundation

// Logik-Tests für die Regeln ohne KI. Laufen im CI vor dem Build:
//   swiftc Shared/Smart.swift Shared/Shop.swift Shared/Models.swift Shared/Money.swift Shared/Companion.swift Shared/DotChat.swift Shared/Timing.swift Shared/Sleep.swift Shared/Workshop.swift Dopa/Game.swift Tests/main.swift -o logic && ./logic

var failures = 0

func expect<T: Equatable>(_ actual: T, _ expected: T, _ what: String) {
    if actual != expected {
        print("✗ \(what): erwartet \(expected), bekommen \(actual)")
        failures += 1
    }
}

// Merken: Art erkennen
let memoCases: [(String, MemoKind)] = [
    ("Schlüssel liegt auf der Kommode", .place),
    ("Hab den Schlüssel auf den Tisch gelegt", .place),
    ("Karte in die Jacke gesteckt", .place),
    ("Ladekabel ist im Rucksack", .place),
    ("Herd ist aus", .done),
    ("Tabletten genommen", .done),
    ("Hab die Mail abgeschickt", .done),
    ("Frau M. sagt: Bastelsachen statt Malsachen", .agreement),
    ("Mama meint ich soll morgen früher kommen", .agreement),
    ("Idee für Fakester: Rundenmodus", .note),
]
for (text, kind) in memoCases {
    expect(MemoKind.detect(text), kind, "MemoKind(\(text))")
}

// Morgen-Check pausieren („diese Woche kein Morgen-Check“)
var pausedMorning = Morning()
pausedMorning.pausedUntil = day(2026, 10, 12)              // ab Montag wieder
expect(pausedMorning.isScheduled(on: day(2026, 10, 9)), false, "Freitag pausiert")
expect(pausedMorning.isScheduled(on: day(2026, 10, 12)), true, "Montag wieder an")
expect(pausedMorning.forToday(day(2026, 10, 9)).untimed, true, "pausierter Tag ohne Uhr")
var pausedEvening = Evening()
pausedEvening.pausedUntil = day(2026, 10, 11)
expect(pausedEvening.isScheduled(day(2026, 10, 10, 21)), false, "Abendroutine pausiert")

// Dot stellt die App ein
expect(DotSetting.morning.label(on: false, days: 3, from: day(2026, 10, 9)), "Morgen-Check pausieren bis Mo 12.10.", "Morgen pausieren")
expect(DotSetting.morning.label(on: false, days: 0, from: day(2026, 10, 9)), "Morgen-Check pausieren bis Fr 16.10.", "ohne Angabe eine Woche")
expect(DotSetting.nudges.label(on: false, days: 0), "Stupser aus", "Stupser aus")
expect(DotSetting.morning.label(on: true, days: 0), "Morgen-Check wieder an", "wieder an")
expect(DotAction(kind: .setting, title: "nudges", step: "off").label, "Stupser aus", "Einstellungs-Knopf")

// Dot passt die App an (edit)
expect(DotEdit.weekdays(["Mo", "Mittwoch", "fr"]), [2, 4, 6], "Wochentage aus Wörtern")
expect(DotEdit.weekdays(["werktags"]), [2, 3, 4, 5, 6], "werktags")
expect(DotEdit.weekdayText([2, 3, 4, 5, 6]), "Mo–Fr", "Mo–Fr als Text")
expect(DotEdit.weekdayText([1, 2, 4]), "Mo, Mi, So", "Woche ab Montag")
expect(DotAction(kind: .edit, title: "", time: 465, key: "morning.leave").label, "Morgens los um 7:45", "Losgehzeit")
expect(DotAction(kind: .edit, title: "Mails", step: "Mails beantworten", key: "task.rename").label,
       "„Mails“ → „Mails beantworten“", "Aufgabe umbenennen")
expect(DotAction(kind: .edit, title: "", items: ["Mo", "Di", "Do"], key: "morning.days").label,
       "Morgen-Check Mo, Di, Do", "Morgen-Tage")
expect(DotAction(kind: .edit, title: "", step: "Grün", key: "theme").label, "Farbe: Grün", "Farbe")
expect(DotAction(kind: .edit, title: "x", key: "quatsch").label, "Einstellung ändern", "unbekannt")
expect(DotAction(kind: .edit, title: "", key: "chat.clear").label, "Unser Gespräch leeren", "Chat leeren")
expect(DotAction(kind: .edit, title: "Herd ist aus", key: "memo.delete").label, "Notiz löschen · Herd ist aus", "Notiz löschen")

// Eigene Preise: pro Stück gemerkt
expect(PriceBook.count("2x Milch"), 2, "2x")
expect(PriceBook.count("3 Äpfel"), 3, "3 Stück")
expect(PriceBook.count("1 kg Mehl"), 1, "Größe zählt als 1")
expect(PriceBook.count("Milch"), 1, "ohne Menge")
expect(PriceBook.unitPrice(total: 2.18, name: "2x Milch"), 1.09, "Stückpreis")
expect(PriceBook.price(for: "3x Milch", own: ["milch": 1.09]), 3.27, "nächstes Mal × Menge")
expect(PriceBook.price(for: "Butter", own: ["milch": 1.09]) == nil, true, "kein eigener Preis")

// Prospekte: Gültigkeit, Suche, Angebot zur Einkaufsliste
let fNow = day(2026, 10, 10, 12)                                    // Samstag
let lidl = Flyer(store: "Lidl", validFrom: day(2026, 10, 6), validTo: day(2026, 10, 11),
                 offers: [Offer(name: "Milka Alpenmilch Schokolade", price: 0.99, unit: "100 g"),
                          Offer(name: "Weidemilch 1,5 %", price: 0.89, unit: "1 l"), Offer(name: "Butter", price: 1.59)])
let rewe = Flyer(store: "Rewe", validFrom: day(2026, 10, 13), validTo: day(2026, 10, 18),
                 offers: [Offer(name: "Frische Milch", price: 0.79)])
let oldAldi = Flyer(store: "Aldi", validTo: day(2026, 10, 4), offers: [Offer(name: "Milch", price: 0.5)])
expect(Offers.active([lidl, rewe, oldAldi], now: fNow).map(\.store), ["Lidl", "Rewe"], "abgelaufen fliegt raus")
expect(Offers.isUpcoming(rewe, now: fNow), true, "Rewe gilt erst ab Dienstag")
expect(Offers.validText(rewe, now: fNow), "ab Di 13.10. · bis So 18.10.", "Gültigkeit als Text")
expect(Offers.search("milch", in: [lidl, rewe, oldAldi], now: fNow).map { $0.offer.price }, [0.79, 0.89, 0.99], "Suche, günstigste zuerst")
expect(Offers.best(for: "2x Butter", in: [lidl], now: fNow)?.offer.price, 1.59, "Angebot zur Einkaufsliste")
expect(Offers.best(for: "Zahnpasta", in: [lidl], now: fNow) == nil, true, "kein Angebot")
let noDate = Flyer(store: "", added: day(2026, 10, 1), offers: [])
expect(Offers.isActive(noDate, now: fNow), true, "ohne Datum 10 Tage gültig")
expect(Offers.isActive(noDate, now: day(2026, 10, 12)), false, "danach weg")

// Prospekt-Link aus kaufDA („Teilen“-Text mit Weiterleitungs-Link)
let sharedFlyerText = "Sieh dir mal diesen Kaufland-Prospekt in der kaufDA App an! https://nfx6.adj.st/brochureviewer/9cbe/0?adjust_t=z&adjust_fallback=https://www.kaufda.de/contentViewer/static/9cbe?page=1"
expect(Offers.flyerURL(from: sharedFlyerText)?.host, "www.kaufda.de", "Web-Ansicht hinter dem Weiterleitungs-Link")
expect(Offers.flyerURL(from: "https://www.kaufda.de/x")?.absoluteString, "https://www.kaufda.de/x", "direkter Link")
expect(Offers.flyerURL(from: "kein Link hier") == nil, true, "ohne Link nichts")
expect(Offers.merge([Offer(name: "Butter"), Offer(name: "Milch")], into: [Offer(name: "butter")]).count, 2, "Seiten ohne Doppelte")

// Kontostand vom Screenshot
let oldData = try! JSONDecoder().decode(AppData.self, from: #"{"tasks":[]}"#.data(using: .utf8)!)
expect(oldData.bank == nil, true, "ohne Kontostand lesbar")
let bankJSON = #"{"amount":-12.35,"account":"Sparkasse"}"#.data(using: .utf8)!
expect(try! JSONDecoder().decode(BankBalance.self, from: bankJSON).amount, -12.35, "Kontostand im Minus")

// Aufträge auf „Merken“ (Lehrkraft, Chef …) – Vorfilter für „Auch als Aufgabe?“
expect(Smart.looksLikeAssignment("Frau M. sagt, ich soll bis Freitag 20 Kopien machen"), true, "Auftrag erkannt")
expect(Smart.looksLikeAssignment("Plakat für die 3b vorbereiten"), true, "Vorbereiten ist ein Auftrag")
expect(Smart.looksLikeAssignment("Schlüssel liegt auf der Kommode"), false, "Ort ist kein Auftrag")

// Erster Schritt
expect(Smart.firstStep(for: "Zimmer aufräumen"), "Nur 5 Sachen an ihren Platz legen", "Schritt Zimmer")
expect(Smart.firstStep(for: "Arzttermin machen"), "Nur die Nummer oder Website raussuchen", "Schritt Arzt")
expect(Smart.firstStep(for: "Einkaufsliste schreiben"), "Nur aufschreiben, was fehlt", "Schritt Einkauf vor Schreiben")
expect(Smart.firstStep(for: "Nicht vergessen: Geschenk"), "Nur hinsetzen und es aufmachen", "‚vergessen‘ ist kein Essen")
expect(Smart.firstStep(for: "Mappe abgeben"), "Nur hinsetzen und es aufmachen", "‚Mappe‘ ist kein Code")

// Suche
expect(Smart.searchWords("Wo ist mein Schlüssel?"), ["schlüssel"], "Suche Schlüssel")
expect(Smart.searchWords("hab ich den Herd aus"), ["herd", "aus"], "Suche Herd")

// Einkauf: Gänge
let shopCases: [(String, ShopCategory)] = [
    ("Reis", .pantry),
    ("Eis", .frozen),
    ("Eistee", .drinks),
    ("Kartoffelchips", .snacks),
    ("Kartoffeln", .produce),
    ("Erdnussbutter", .pantry),
    ("Butter", .dairy),
    ("Eier", .dairy),
    ("Orangensaft", .drinks),
    ("Tomatenmark", .pantry),
    ("Tomaten", .produce),
    ("Klopapier", .household),
    ("Toastbrot", .bakery),
    ("Hackfleisch", .meat),
    ("Olivenöl", .pantry),
    ("Kindershampoo", .household),
    ("Geschenkpapier", .other),
]
for (name, category) in shopCases {
    expect(ShopCategory.detect(name), category, "Gang(\(name))")
}

// Einkauf: Normalisieren und Aufteilen
expect(ShopText.key("2x Milch"), "milch", "key 2x Milch")
expect(ShopText.key("1 kg Mehl"), "mehl", "key 1 kg Mehl")
expect(ShopText.key("500g Hack"), "hack", "key 500g Hack")
expect(ShopText.key("Milch"), "milch", "key Milch")
expect(ShopText.split("milch, brot und eier"), ["Milch", "Brot", "Eier"], "split")

// Game: Level-Kurve, Quests, Deckel
expect(Level.threshold(1), 0, "Schwelle L1")
expect(Level.threshold(2), 40, "Schwelle L2")
expect(Level.threshold(3), 120, "Schwelle L3")
expect(Level.level(for: 39), 1, "39 XP")
expect(Level.level(for: 40), 2, "40 XP")
expect(Level.level(for: 119), 2, "119 XP")
expect(Level.level(for: 120), 3, "120 XP")
expect(Level.progress(50).have, 10, "Fortschritt have")
expect(Level.progress(50).need, 80, "Fortschritt need")
expect(XPKind.focusMinutes(90).amount, 60, "Fokus-Deckel")
let quests = Quest.forWeek("2026-W40").map(\.key)
expect(quests.count, 3, "3 Quests")
expect(Set(quests).count, 3, "Quests verschieden")
expect(Quest.forWeek("2026-W40").map(\.key), quests, "Quests fest pro Woche")
var comps = DateComponents()
comps.year = 2026; comps.month = 9; comps.day = 30; comps.hour = 12
expect(Quest.weekKey(Calendar(identifier: .gregorian).date(from: comps)!), "2026-W40", "ISO-Woche")

// Geld-Überblick
func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
    var c = DateComponents()
    c.year = y; c.month = m; c.day = d; c.hour = h; c.minute = min
    return Calendar.current.date(from: c)!
}
let october = day(2026, 10, 2)
let items = [
    MoneyItem(title: "FSJ", amount: 450, kind: .income, dayOfMonth: 1),
    MoneyItem(title: "Handy", amount: 15, kind: .fixed, dayOfMonth: 5),
    MoneyItem(title: "Klarna Zalando", amount: 30, kind: .debt, due: day(2026, 10, 20), remaining: 3),
    MoneyItem(title: "Klarna alt", amount: 10, kind: .debt, due: day(2026, 9, 28), remaining: 1),   // überfällig
    MoneyItem(title: "Später", amount: 99, kind: .debt, due: day(2026, 11, 3), remaining: 1),
]
let month = MoneyMath.month(items, payments: [], now: october)
expect(month.income, 450, "Geld rein")
expect(month.fixed, 15, "Fixkosten")
expect(month.debts, 40, "Raten im Oktober: eine Klarna-Rate + Überfälliges, November zählt nicht")
expect(month.free, 395, "Frei")
// Bezahlte Rate zählt im selben Monat weiter, auch wenn die nächste schon im November liegt
let paidItem = MoneyMath.afterPayment(items[2])!
expect(paidItem.remaining, 2, "eine Rate weniger")
expect(MoneyMath.daysUntil(paidItem.due!, now: day(2026, 10, 20)), 31, "nächste Rate einen Monat später")
let afterPaying = MoneyMath.month([items[0], items[1], paidItem, items[3]],
                                  payments: [Payment(itemID: items[2].id, title: "Klarna", amount: 30, date: day(2026, 10, 20))],
                                  now: day(2026, 10, 21))
expect(afterPaying.debts, 40, "Bezahltes zählt im Monat weiter")
expect(MoneyMath.afterPayment(items[3]) == nil, true, "letzte Rate = abbezahlt")
expect(MoneyMath.linkedBudget(free: 395, share: 0.3), 115, "30 % vom Freien, auf 5 € abgerundet")
expect(MoneyMath.linkedBudget(free: -20, share: 0.3), 0, "nichts frei = 0")
expect(MoneyMath.openTotal(items), 30 * 3 + 10 + 99, "insgesamt offen")
expect(MoneyMath.dueText(day(2026, 10, 2), now: october), "heute fällig", "heute fällig")
expect(MoneyMath.dueText(day(2026, 10, 3), now: october), "morgen fällig", "morgen fällig")
expect(MoneyMath.dueText(day(2026, 9, 29), now: october), "seit 3 Tagen offen", "überfällig")
expect(MoneyMath.parse("12,50 €"), 12.5, "Betrag mit Komma")

// Abendroutine: ein Abend geht bis 5 Uhr früh
expect(Evening.nightKey(day(2026, 10, 2, 23, 40)), "2026-10-02", "Abend vor Mitternacht")
expect(Evening.nightKey(day(2026, 10, 3, 0, 30)), "2026-10-02", "nach Mitternacht noch derselbe Abend")
expect(Evening.nightKey(day(2026, 10, 3, 6, 0)), "2026-10-03", "morgens neuer Tag")
var evening = Evening()
evening.bedAt = 30                      // 0:30
expect(evening.bedDate(day(2026, 10, 2, 22, 0)), day(2026, 10, 3, 0, 30), "Bett nach Mitternacht")
expect(evening.bedDate(day(2026, 10, 3, 0, 10)), day(2026, 10, 3, 0, 30), "nach Mitternacht gleicher Abend")
evening.bedAt = 23 * 60 + 30
expect(evening.startAt, 23 * 60 + 30 - evening.totalMinutes, "Anfangszeit")
evening.night = "2026-10-02"
evening.checked = [evening.steps[0].id]
expect(evening.forTonight(day(2026, 10, 3, 1, 0)).checked.count, 1, "Häkchen bleiben bis 5 Uhr")
expect(evening.forTonight(day(2026, 10, 3, 18, 0)).checked.count, 0, "nächster Abend frisch")

// Einkauf: diktiert ohne Komma, Gang-Reihenfolge lernen
expect(ShopText.split("Milch Brot Eier"), ["Milch", "Brot", "Eier"], "Diktat ohne Komma")
expect(ShopText.split("rote Paprika"), ["Rote Paprika"], "zusammengehörig bleibt zusammen")
expect(ShopText.split("Hafer Milch", known: ["hafer"]), ["Hafer", "Milch"], "gelernte Wörter zählen")
expect(ShopText.split("Milch, Brot und Eier"), ["Milch", "Brot", "Eier"], "Komma und und")
let order: [ShopCategory] = [.produce, .bakery, .dairy, .meat, .frozen, .pantry]
expect(ShopText.learnOrder(current: order, seen: [.dairy, .produce, .dairy]),
       [.dairy, .bakery, .produce, .meat, .frozen, .pantry], "Kühlregal vor Obst gelernt, Rest bleibt")
expect(ShopText.learnOrder(current: order, seen: []), order, "nichts gesehen = nichts ändern")
let place = ShopPlace(name: "Lidl", order: [.dairy, .dairy, .produce])
expect(place.fullOrder.count, ShopCategory.allCases.count, "fehlende Gänge werden ergänzt")
expect(place.fullOrder.first, .dairy, "eigene Reihenfolge zuerst")

// Geld-Tagebuch
let doener = MoneyMath.parseEntry("4,50 Döner")!
expect(doener.amount, 4.5, "Betrag vorne")
expect(doener.title, "Döner", "Titel")
expect(doener.income, false, "Ausgabe")
expect(MoneyMath.parseEntry("Bahn 12.90€")!.amount, 12.9, "Betrag hinten mit €")
expect(MoneyMath.parseEntry("+20 Oma")!.income, true, "Plus = Einnahme")
expect(MoneyMath.parseEntry("Taschengeld 150")!.income, true, "Taschengeld = Einnahme")
expect(MoneyMath.parseEntry("Döner") == nil, true, "ohne Betrag nichts")
expect(SpendKind.detect("Döner"), .food, "Döner = Essen")
expect(SpendKind.detect("Einkauf Lidl"), .groceries, "Lidl = Einkauf")
expect(SpendKind.detect("Robux"), .fun, "Robux = Spaß")
expect(SpendKind.detect("Busch"), .other, "kurzes Stichwort nur als ganzes Wort")
let ledger = [
    Spend(title: "Döner", amount: 4.5, date: day(2026, 10, 1), kind: .food),
    Spend(title: "Oma", amount: 20, date: day(2026, 10, 1), kind: .other, income: true),
    Spend(title: "Steam", amount: 10, date: day(2026, 9, 30), kind: .fun),
]
let withLedger = MoneyMath.month(items, payments: [], entries: ledger, now: october)
expect(withLedger.extra, 20, "einmalige Einnahme")
expect(withLedger.spent, 4.5, "nur Oktober-Ausgaben")
expect(withLedger.free, 415, "frei inkl. Einnahme")
expect(withLedger.left, 410.5, "noch übrig")
expect(MoneyMath.week(ledger, weekStart: day(2026, 9, 28, 0)), [0, 0, 10, 4.5, 0, 0, 0], "Woche Mo–So")

expect(MoneyMath.splitEntries("12 Bahn, 3 Kaffee und 4,50 Döner"), ["12 Bahn", "3 Kaffee", "4,50 Döner"], "mehrere Einträge")
expect(MoneyMath.splitEntries("4,50 Döner"), ["4,50 Döner"], "Komma im Betrag trennt nicht")

// Routinen: eigene Zeit nur für heute
var morning = Morning()
morning.day = day(2026, 10, 2, 7)
morning.todayLeave = 9 * 60
expect(morning.leaveToday, 9 * 60, "heute später los")
expect(morning.forToday(day(2026, 10, 5, 7)).todayLeave == nil, true, "Montag wieder Plan")
expect(morning.forToday(day(2026, 10, 3, 7)).untimed, true, "Samstag (kein Routine-Tag) = ohne Uhr")
var weekendEvening = Evening()
weekendEvening.days = [1, 2, 3, 4, 5]                   // Fr + Sa frei
expect(weekendEvening.forTonight(day(2026, 10, 3, 22)).untimed, true, "Samstagabend frei = ohne Uhr")
expect(weekendEvening.forTonight(day(2026, 10, 5, 22)).untimed, false, "Montagabend mit Zeit")
expect(weekendEvening.isScheduled(day(2026, 10, 4, 1)), false, "Sonntag 1 Uhr gehört noch zum Samstagabend")
morning.todayLeave = -1
expect(morning.untimed, true, "ohne Uhr")
expect(morning.leaveToday, morning.leaveAt, "ohne Uhr rechnet mit Plan")
var lateEvening = Evening()
lateEvening.night = "2026-10-02"
lateEvening.tonightBed = 60
expect(lateEvening.bedDate(day(2026, 10, 2, 22)), day(2026, 10, 3, 1), "heute später ins Bett")

// Tagesbegleiter: Tagesphasen (Abend ab 1 Std. vor der Routine, Nacht ab Schlafenszeit bis 4 Uhr)
expect(DayPhase.at(7 * 60, eveningStart: 23 * 60, bed: 23 * 60 + 30), .morning, "7 Uhr = Morgen")
expect(DayPhase.at(14 * 60, eveningStart: 23 * 60, bed: 23 * 60 + 30), .day, "14 Uhr = Tag")
expect(DayPhase.at(22 * 60 + 10, eveningStart: 23 * 60, bed: 23 * 60 + 30), .evening, "22:10 = Abend")
expect(DayPhase.at(23 * 60 + 45, eveningStart: 23 * 60, bed: 23 * 60 + 30), .night, "nach Schlafenszeit = Nacht")
expect(DayPhase.at(2 * 60, eveningStart: 23 * 60, bed: 23 * 60 + 30), .night, "2 Uhr = Nacht")
expect(DayPhase.at(0 * 60 + 20, eveningStart: 23 * 60 + 45, bed: 60), .evening, "späte Schlafenszeit: 0:20 noch Abend")
expect(DayPhase.at(1 * 60 + 30, eveningStart: 23 * 60 + 45, bed: 60), .night, "nach 1 Uhr Nacht")
var script = CompanionScript(day: "2026-10-03")
script.midday = "Mittag"
script.afternoon = "Nachmittag"
expect(script.line(for: .day, minutes: 13 * 60), "Mittag", "Mittagssatz")
expect(script.line(for: .day, minutes: 16 * 60), "Nachmittag", "Nachmittagssatz")
expect(CompanionText.line(.night, day: "2026-10-03"), CompanionText.line(.night, day: "2026-10-03"), "eingebauter Satz fest pro Tag")

// Altes dopa.json ohne neue Felder bleibt lesbar
let legacy = #"{"tasks":[],"memos":[],"budget":{"monthly":20}}"#.data(using: .utf8)!
let decoded = try! JSONDecoder().decode(AppData.self, from: legacy)
expect(decoded.habits.count, Habit.defaults.count, "Standard-Gewohnheiten")
expect(decoded.budget.monthly, 20, "Budget bleibt")
expect(decoded.budget.linked, false, "nicht gekoppelt")
expect(decoded.calendar.leadWithPlace, 30, "Kalender-Standard")
expect(decoded.dotChat.count, 0, "kein Dot-Gespräch")

// Dot-Gespräch
expect(DotChat.parseTime("14:30"), 870, "Uhrzeit 14:30")
expect(DotChat.parseTime("9:05"), 545, "Uhrzeit 9:05")
expect(DotChat.parseTime("8 Uhr"), 480, "8 Uhr")
expect(DotChat.parseTime("25:00"), nil, "keine Uhrzeit")
expect(DotChat.parseTime(""), nil, "leer")
expect(DotChat.clock(545), "9:05", "Uhr anzeigen")
expect(DotChat.reminderDay(time: 8 * 60, day: 0, nowMinutes: 10 * 60), 1, "schon vorbei → morgen")
expect(DotChat.reminderDay(time: 18 * 60, day: 0, nowMinutes: 10 * 60), 0, "noch heute")
expect(DotAction(kind: .reminder, title: "Oma anrufen", time: 870, day: 1).label, "Erinnerung morgen 14:30 · Oma anrufen", "Erinnerungs-Knopf")
expect(DotAction(kind: .focus, title: "Mails", minutes: 10).label, "Timer 10 Min · Mails", "Timer-Knopf")
var chat: [DotMessage] = (0..<70).map { DotMessage(fromDot: $0 % 2 == 1, text: "n\($0)") }
chat.append(DotMessage(fromDot: true, text: "weg", failed: true))
expect(DotChat.trimmed(chat).count, DotChat.keep, "Verlauf gekürzt")
expect(DotChat.history(chat).count, DotChat.sendCount, "Verlauf an die KI")
expect(DotChat.history(chat).last?.text, "n69", "Fehlversuche nicht mitschicken")
expect(DotChat.starters(hour: 9, mood: 1, openTasks: 3, focusRunning: false).first, "Heute geht wenig. Was reicht?", "sanfter Einstieg")
let openTitles = ["Steuererklärung machen", "Oma anrufen", "Mails", "Mails beantworten"]
expect(DotChat.match("oma anrufen", in: openTitles), 1, "Aufgabe genau gefunden")
expect(DotChat.match("Steuererklärung", in: openTitles), 0, "Aufgabe über Teil gefunden")
expect(DotChat.match("Mails", in: openTitles), 2, "genauer Treffer schlägt Teil")
expect(DotChat.match("beantworten", in: openTitles), 3, "eindeutiger Teil")
expect(DotChat.match("Zahnarzt", in: openTitles), nil, "unbekannt → nichts anfassen")
expect(DotChat.match("ma", in: openTitles), nil, "mehrdeutig → nichts anfassen")
expect(DotAction(kind: .tomorrow, title: "Mails").label, "Auf morgen · Mails", "Verschieben-Knopf")
expect(DotAction(kind: .steps, title: "Koffer packen", items: ["Medikamente", "Kleidung"]).label,
       "2 Schritte zu „Koffer packen“", "Schritte-Knopf")
expect(DotAction(kind: .task, title: "Rest packen", time: 430, day: 1, items: ["Ladekabel"]).label,
       "Aufgabe morgen 7:10 · Rest packen (1 Schritt)", "Aufgabe mit Uhrzeit und Schritt")
expect(DotChat.newSteps(["Medikamente", " kleidung ", "Medikamente", "", "Sportsachen"], existing: ["Kleidung"]),
       ["Medikamente", "Sportsachen"], "keine doppelten Schritte")
expect(DotChat.date(day: 1, time: 430, from: day(2026, 10, 4, 22)), day(2026, 10, 5, 7, 10), "morgen 7:10")
let seminar = DotAction(kind: .schedule, title: "Seminarwoche",
                        entries: [PlanEntry(title: "Erste Hilfe", day: 2, time: 540, minutes: 90),
                                  PlanEntry(title: "Reflexion", day: 3, time: 600)])
expect(seminar.label, "Seminarwoche eintragen · 2 Termine", "Wochenplan-Knopf")
expect(seminar.entries[0].untilText, "bis 10:30", "Ende des Termins")
expect(DotChat.dayLabel(2, from: day(2026, 10, 4, 12)), "Di 6.10.", "Tag als Kürzel")
expect(DotAction(kind: .task, title: "Wäsche aufhängen", place: "Zuhause").label,
       "Aufgabe · Wäsche aufhängen · bei Zuhause", "Aufgabe mit Ort")
let spotNames = ["Lidl", "Zuhause", "Uni"]
expect(DotChat.matchSpot("zhs", in: spotNames), 1, "zhs = Zuhause")
expect(DotChat.matchSpot("Daheim", in: spotNames), 1, "daheim = Zuhause")
expect(DotChat.matchSpot("lidl", in: spotNames), 0, "Laden gefunden")
expect(DotChat.matchSpot("Rewe", in: spotNames), nil, "unbekannter Ort")
let oldSpot = try! JSONDecoder().decode(Spot.self, from: #"{"name":"Zuhause","lat":52.5,"lon":13.4}"#.data(using: .utf8)!)
expect(oldSpot.radius, 150, "Ort mit Standard-Radius")
let taskNoSpot = try! JSONDecoder().decode(TaskItem.self, from: #"{"title":"Alt"}"#.data(using: .utf8)!)
expect(taskNoSpot.spotID == nil, true, "alte Aufgabe ohne Ort")
let oldMsg = try! JSONDecoder().decode(DotMessage.self, from: #"{"fromDot":false,"text":"hi"}"#.data(using: .utf8)!)
expect(oldMsg.hasPhoto, false, "alte Nachricht ohne Foto")
// Eigene Zeiten, Countdown, Halbzeit, Schlaf
expect(Timing.parseList("10, 5"), [10, 5], "Liste mit Komma")
expect(Timing.parseList("5 25 5 0 999 x15"), [25, 15, 5], "Liste sortiert, ohne Doppelte und Unsinn")
expect(Timing.listText([10, 5]), "10, 5", "Liste als Text")
let leaveAt = day(2026, 10, 3, 8)
expect(Timing.countdown(leave: leaveAt, offsets: [10, 5, 0], now: leaveAt.addingTimeInterval(-7 * 60)).map { $0.minutes }, [5],
       "Countdown nur noch kommende")
expect(Timing.halfway(start: leaveAt, end: leaveAt.addingTimeInterval(20 * 60)), leaveAt.addingTimeInterval(10 * 60), "Halbzeit")
expect(Timing.halfway(start: leaveAt, end: leaveAt.addingTimeInterval(2 * 60)), nil, "keine Halbzeit bei 2 Min")
let night = day(2026, 10, 2, 23)
let sleepParts: [(start: Date, end: Date)] = [
    (start: night, end: night.addingTimeInterval(3 * 3600)),
    (start: night.addingTimeInterval(2 * 3600), end: night.addingTimeInterval(5 * 3600)),   // Uhr + Handy überlappen
    (start: night.addingTimeInterval(6 * 3600), end: night.addingTimeInterval(7 * 3600)),
]
expect(Timing.asleepSeconds(sleepParts), 6 * 3600, "Schlaf ohne Doppelzählung")
expect(Timing.hoursText(5 * 3600 + 20 * 60), "5:20 Std", "Schlaf als Text")
expect(Timing.shortNight(5 * 3600), true, "kurze Nacht")
expect(Timing.shortNight(nil), false, "ohne Daten keine kurze Nacht")

// Schlaf pro Nacht, Bewegung, Zeile für Dot
let nights = Timing.nightly([
    (start: day(2026, 10, 2, 23), end: day(2026, 10, 3, 6, 30)),       // Nacht auf den 3. → zählt zum 2.
    (start: day(2026, 10, 3, 14), end: day(2026, 10, 3, 14, 30)),      // Mittagsschlaf → zählt zum 3.
    (start: day(2026, 10, 1, 23), end: day(2026, 10, 2, 7)),
])
expect(nights[Calendar.current.startOfDay(for: day(2026, 10, 2))], 7.5 * 3600, "Nacht zählt zum Vortag")
expect(nights[Calendar.current.startOfDay(for: day(2026, 10, 3))], 1800, "Mittagsschlaf zählt zu heute")
let sleepWeek: [Date: TimeInterval] = [day(2026, 10, 1): 21600.0, day(2026, 10, 2): 28800.0]
expect(Timing.average(sleepWeek), 25200.0, "Schnitt")
expect(Timing.thousands(3214), "3.214", "Tausender")
expect(Timing.thousands(12500), "12.500", "Tausender 5-stellig")
expect(Timing.thousands(980), "980", "unter Tausend")
expect(Timing.healthLine(sleep: 5 * 3600, average: nil, bed: day(2026, 10, 2, 1), woke: day(2026, 10, 2, 6),
                         steps: 3214, exercise: 12),
       "Apple Watch: letzte Nacht 5:00 Std Schlaf (1:00–6:00); heute bisher 3.214 Schritte, 12 Min Bewegung – kurze Nacht: heute weniger, kleinere Schritte, Pausen einplanen.",
       "Zeile für Dot")
expect(Timing.healthLine(sleep: nil, average: nil, bed: nil, woke: nil, steps: nil, exercise: 0), nil, "ohne Daten keine Zeile")

// Schlafphasen
let n0 = day(2026, 10, 2, 23)
let sleepSegs: [SleepSegment] = [
    SleepSegment(stage: .unspecified, start: n0, end: n0.addingTimeInterval(8 * 3600)),               // Handy, doppelt
    SleepSegment(stage: .core, start: n0, end: n0.addingTimeInterval(3600)),
    SleepSegment(stage: .deep, start: n0.addingTimeInterval(3600), end: n0.addingTimeInterval(2.5 * 3600)),
    SleepSegment(stage: .awake, start: n0.addingTimeInterval(2.5 * 3600), end: n0.addingTimeInterval(2.75 * 3600)),
    SleepSegment(stage: .core, start: n0.addingTimeInterval(2.75 * 3600), end: n0.addingTimeInterval(5.75 * 3600)),
    SleepSegment(stage: .rem, start: n0.addingTimeInterval(5.75 * 3600), end: n0.addingTimeInterval(7.25 * 3600)),
]
let sleepNight = SleepNight.build(sleepSegs)!
expect(sleepNight.totals[.unspecified] == nil, true, "Handy-Schlaf fliegt raus, wenn die Uhr Phasen hat")
expect(sleepNight.asleep, 7 * 3600, "Schlafzeit ohne Wachphasen")
expect(sleepNight.totals[.deep], 1.5 * 3600, "Tiefschlaf")
expect(sleepNight.totals[.awake], 0.25 * 3600, "Wach")
expect(sleepNight.hasStages, true, "Phasen erkannt")
expect(sleepNight.note(.deep), "im üblichen Bereich", "Tiefschlaf-Anteil 21 %")
expect(sleepNight.note(.core), "im üblichen Bereich", "Kern-Anteil 57 %")
expect(sleepNight.note(.awake) == nil, true, "Wach ohne Einordnung")
let shortDeep = SleepNight.build([
    SleepSegment(stage: .core, start: n0, end: n0.addingTimeInterval(6 * 3600)),
    SleepSegment(stage: .deep, start: n0.addingTimeInterval(6 * 3600), end: n0.addingTimeInterval(6.25 * 3600)),
])!
expect(shortDeep.note(.deep), "etwas weniger als üblich", "wenig Tiefschlaf")
expect(SleepStage(healthValue: 0) == nil, true, "im Bett zählt nicht")
expect(SleepStage(healthValue: 5), .rem, "REM")
expect(SleepNight.build([]) == nil, true, "keine Nacht ohne Daten")

// Dots Werkstatt
let w0 = day(2026, 10, 3, 12)
var shop = WorkshopState()
shop.parts = 2
let wheel = Machine.all[0]
expect(Workshop.canUpgrade(shop, wheel), true, "Funkenrad mit 2 Bauteilen baubar")
expect(Workshop.isVisible(shop, Machine.all[1]), false, "Lampe erst später sichtbar")
shop = Workshop.upgrade(shop, wheel, now: w0)!
expect(shop.level(wheel), 1, "Funkenrad Stufe 1")
expect(shop.parts, 0, "Bauteile verbraucht")
expect(Workshop.pending(shop, now: w0.addingTimeInterval(2 * 3600)), 12, "2 Std × 6 Funken")
expect(Workshop.pending(shop, now: w0.addingTimeInterval(100 * 3600)), 288.0, "Vorrat voll nach 48 Std, nichts weg")
expect(Workshop.isFull(shop, now: w0.addingTimeInterval(49 * 3600)), true, "Werkstatt voll")
shop = Workshop.collect(shop, now: w0.addingTimeInterval(2 * 3600))
expect(shop.sparks, 12, "eingesammelt")
expect(Workshop.missingText(shop, wheel), "Noch 4 Bauteile – z. B. eine Aufgabe erledigen.", "was fehlt")
expect(Workshop.parts(forXP: 25), 2, "Bauteile aus XP")
expect(Workshop.parts(forXP: 3), 1, "mindestens ein Bauteil")
// Werkstatt: Ausbau, Hüte, Kiste, Titel
var ws2 = WorkshopState()
ws2.levels = ["wheel": 2]
ws2.lastCollect = w0
ws2.tools = 2
expect(Workshop.production(ws2), 12 * 1.3, "Werkzeuge geben Bonus")
ws2.storage = 1
expect(Workshop.storageHours(ws2), 72, "größeres Lager")
expect(Workshop.fill(ws2, now: w0.addingTimeInterval(36 * 3600)), 0.5, "Lager halb voll")
ws2.sparks = 100
expect(Workshop.buy(ws2, Hat.all[1]) == nil, true, "Stern zu teuer")
let dressed = Workshop.buy(ws2, Hat.all[0])!
expect(dressed.hat, "flower", "Hut sitzt gleich")
expect(dressed.sparks, 20, "Hut bezahlt")
expect(Workshop.crateReady(ws2, today: "2026-10-04"), true, "Kiste wartet")
let opened = Workshop.openCrate(ws2, today: "2026-10-04", roll: 0.2)!
expect(opened.state.crateDay, "2026-10-04", "Kiste heute offen")
expect(Workshop.crateReady(opened.state, today: "2026-10-04"), false, "nur eine Kiste am Tag")
expect(Workshop.title(ws2), "Lehrling", "Titel am Anfang")
ws2.totalSparks = 7000
expect(Workshop.title(ws2), "Erfinder", "Titel wächst")
expect(WorkshopUpgrade.storage.effect(2), "Vorrat 96 Std", "Lager-Text")
var ws3 = WorkshopState()
ws3.sparks = 600
expect(ws3.currentRoom.id, "night", "Nachtwerkstatt als Start")
expect(Workshop.enter(ws3, Room.all[2]) == nil, true, "Waldhütte zu teuer")
let dawn = Workshop.enter(ws3, Room.all[1])!
expect(dawn.room, "dawn", "eingezogen")
expect(dawn.sparks, 100, "Raum bezahlt")
let back = Workshop.enter(dawn, Room.all[1])!
expect(back.sparks, 100, "gekaufter Raum kostet nichts mehr")
expect(Workshop.dotLine(WorkshopState(), now: w0, tick: 3), "Ein Funkenrad wär schön. Eine Aufgabe reicht dafür.", "Dot am Anfang")
expect(Machine.all.count, 6, "sechs Maschinen")
let oldShop = try! JSONDecoder().decode(WorkshopState.self, from: #"{"parts":3}"#.data(using: .utf8)!)
expect(oldShop.parts, 3, "Werkstatt tolerant gelesen")

// Aufgaben mit Uhrzeit, Mini-Schritt auf Wunsch
expect(Timing.moveTime(day(2026, 10, 3, 14, 30), to: day(2026, 10, 5, 0)), day(2026, 10, 5, 14, 30), "Uhrzeit wandert mit dem Tag")
expect(Timing.defaultTaskTime(day: nil, now: day(2026, 10, 3, 14, 20)), day(2026, 10, 3, 15, 0), "heute: nächste volle Stunde")
expect(Timing.defaultTaskTime(day: day(2026, 10, 6, 0), now: day(2026, 10, 3, 14, 20)), day(2026, 10, 6, 9, 0), "später: 9 Uhr")
expect(Timing.clock(day(2026, 10, 3, 9, 5)), "9:05", "Uhrzeit-Text")
let oldTask = try! JSONDecoder().decode(TaskItem.self, from: #"{"title":"Alt","firstStep":"Nur los"}"#.data(using: .utf8)!)
expect(oldTask.showStep, false, "alter Mini-Schritt erst auf Wunsch")
expect(oldTask.remindAt == nil, true, "alte Aufgabe ohne Uhrzeit")
let oldReminders = try! JSONDecoder().decode(ReminderSettings.self, from: #"{"mealsOn":false}"#.data(using: .utf8)!)
expect(oldReminders.timerPresets, [2, 5, 10, 25], "Timer-Standard")
expect(oldReminders.countdown, [10, 5], "Countdown-Standard")
expect(oldReminders.mealsOn, false, "alte Einstellung bleibt")
let oldChat = #"[{"fromDot":true,"text":"hi"}]"#.data(using: .utf8)!
expect((try? JSONDecoder().decode([DotMessage].self, from: oldChat))?.first?.actions.count, 0, "alte Nachricht lesbar")

if failures > 0 {
    print("\(failures) Logik-Test(s) fehlgeschlagen")
    exit(1)
}
print("Alle Logik-Tests grün")
