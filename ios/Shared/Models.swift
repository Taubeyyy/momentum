import Foundation

struct SubStep: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var minutes: Int
    var done = false
}

struct TaskItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var firstStep = ""          // der winzige erste Schritt aus „Hilf mir anfangen“
    var createdAt = Date()
    var doneAt: Date?
    var dueDay: Date?           // für einen bestimmten Tag geplant; nil = heute/offen
    var steps: [SubStep] = []   // eigene oder zerlegte Schritte mit Minuten
    var someday = false         // „Irgendwann“ – taucht nicht unter Heute auf
    var showStep = false        // Mini-Schritt erst zeigen, wenn du ihn willst
    var remindAt: Date?         // feste Uhrzeit mit Erinnerung
    var spotID: UUID?           // erinnern, wenn du an diesem Ort ankommst

    /// Der nächste offene Unterschritt, sonst der winzige erste Schritt.
    var nextStep: String { steps.first { !$0.done }?.title ?? firstStep }

    /// Minuten des nächsten offenen Schritts (für „Anfangen“).
    var nextStepMinutes: Int? { steps.first { !$0.done }?.minutes }

    /// Was noch an Zeit übrig ist (nur offene Schritte).
    var minutesLeft: Int { steps.filter { !$0.done }.reduce(0) { $0 + $1.minutes } }
}

/// Morgendlicher Check-in: Stimmung 1–5, Energie low/med/high.
struct CheckIn: Codable, Hashable {
    var day: String             // „2026-10-02“
    var mood: Int
    var energy: String
}

struct Memo: Codable, Identifiable, Hashable {
    var id = UUID()
    var text: String
    var kind: MemoKind          // Ort / Erledigt / Absprache / Notiz
    var createdAt = Date()
    var photo: String?          // Dateiname im Foto-Ordner (z. B. Bild vom Schlüssel)

    init(text: String, kind: MemoKind? = nil, photo: String? = nil) {
        self.text = text
        self.kind = kind ?? MemoKind.detect(text)
        self.photo = photo
    }
}

struct FocusRun: Codable, Hashable {
    var taskID: UUID?
    var title: String
    var step: String
    var startedAt: Date
    var endsAt: Date
}

struct FocusLog: Codable, Hashable {
    var day: Date
    var minutes: Int
}

struct RoutineStep: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var minutes: Int
}

/// Morgen-Checkliste mit fester Abfahrtszeit. Uhrzeiten als Minuten seit Mitternacht.
struct Morning: Codable, Hashable {
    var steps: [RoutineStep] = Morning.defaultSteps
    var leaveAt = 7 * 60 + 35
    var day: Date?              // an welchem Tag `checked`/`startedAt`/`todayLeave` gelten
    var startedAt: Date?
    var checked: [UUID] = []
    var todayLeave: Int?        // nur heute: andere Los-Zeit; -1 = heute ohne Uhr
    var days = [2, 3, 4, 5, 6]  // Erinnerung + Zeitleiste (1 = So … 7 = Sa)
    var pausedUntil: Date?      // „diese Woche kein Morgen-Check“ – bis zu diesem Tag (ausschließlich) aus

    /// Los-Zeit für heute (eigene Zeit oder Plan).
    var leaveToday: Int { todayLeave.flatMap { $0 >= 0 ? $0 : nil } ?? leaveAt }
    var untimed: Bool { todayLeave == -1 }

    /// Auf 15 Minuten ausgelegt – nicht auf die 10, die man sich vornimmt.
    static let defaultSteps = [
        RoutineStep(title: "Aufstehen, Wasser trinken", minutes: 1),
        RoutineStep(title: "Anziehen", minutes: 3),
        RoutineStep(title: "Bad: Zähne, Gesicht", minutes: 4),
        RoutineStep(title: "Snack einpacken", minutes: 3),
        RoutineStep(title: "Handy, Schlüssel, Geldbeutel, Tasche", minutes: 2),
        RoutineStep(title: "Schuhe und Jacke", minutes: 2),
    ]

    var totalMinutes: Int { steps.reduce(0) { $0 + $1.minutes } }
    var wakeAt: Int { leaveAt - totalMinutes }
    var wakeToday: Int { leaveToday - totalMinutes }

    /// Häkchen, Startzeit und eigene Zeit gelten nur für heute – am nächsten Tag ist alles wieder offen.
    func forToday(_ now: Date = Date()) -> Morning {
        guard !(day.map { Calendar.current.isDate($0, inSameDayAs: now) } ?? false) else { return self }
        var m = self
        m.day = nil
        m.startedAt = nil
        m.checked = []
        // an Tagen ohne feste Zeit (z. B. Wochenende): einfach starten, wann du willst
        m.todayLeave = isScheduled(on: now) ? nil : -1
        return m
    }

    func isScheduled(on date: Date) -> Bool {
        if isPaused(on: date) { return false }
        return days.contains(Calendar.current.component(.weekday, from: date))
    }

    func isPaused(on date: Date) -> Bool {
        guard let pausedUntil else { return false }
        return Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: pausedUntil)
    }

    /// Abfahrt heute; liegt sie schon hinter dem Start (z. B. abends ausprobiert), ab Start gerechnet.
    func leaveDate(_ now: Date = Date()) -> Date {
        let planned = ClockTime.date(leaveToday, on: now)
        let start = startedAt ?? now
        return planned > start ? planned : start.addingTimeInterval(TimeInterval(totalMinutes * 60))
    }

    var isDone: Bool { !steps.isEmpty && steps.allSatisfy { checked.contains($0.id) } }
}

/// Abendroutine: runterfahren und morgen vorbereiten. Ein Abend zählt bis 5 Uhr früh –
/// wer um halb eins noch Zähne putzt, ist noch im selben Abend.
struct Evening: Codable, Hashable {
    var steps: [RoutineStep] = Evening.defaultSteps
    var bedAt = 23 * 60 + 30            // Minuten seit Mitternacht; nach Mitternacht z. B. 0:30 = 30
    var night = ""                      // „2026-10-02“ – zu welchem Abend die Häkchen gehören
    var startedAt: Date?
    var checked: [UUID] = []
    var tonightBed: Int?                // nur heute Abend: andere Schlafenszeit; -1 = ohne Uhr
    var days = [1, 2, 3, 4, 5, 6, 7]    // Abende mit fester Zeit; sonst jederzeit ohne Uhr
    var pausedUntil: Date?              // Abendroutine bis zu diesem Tag (ausschließlich) aus

    static let dayStartHour = 5

    var bedTonight: Int { tonightBed.flatMap { $0 >= 0 ? $0 : nil } ?? bedAt }
    var untimed: Bool { tonightBed == -1 }

    static let defaultSteps = [
        RoutineStep(title: "Handy ans Ladekabel", minutes: 1),
        RoutineStep(title: "Schlüssel, Tasche, Kopfhörer an einen Platz", minutes: 3),
        RoutineStep(title: "Klamotten für morgen raussuchen", minutes: 3),
        RoutineStep(title: "Geschirr in die Küche", minutes: 3),
        RoutineStep(title: "Zähne putzen", minutes: 3),
        RoutineStep(title: "Wecker checken, Wasser ans Bett", minutes: 2),
    ]

    var totalMinutes: Int { steps.reduce(0) { $0 + $1.minutes } }

    /// Anfangen = Schlafenszeit minus Dauer (0–1439).
    var startAt: Int { ((bedAt - totalMinutes) % 1440 + 1440) % 1440 }

    var isDone: Bool { !steps.isEmpty && steps.allSatisfy { checked.contains($0.id) } }

    /// Welcher Abend gerade läuft: bis 5 Uhr früh noch der von gestern.
    static func nightKey(_ now: Date = Date()) -> String {
        let shifted = now.addingTimeInterval(-Double(dayStartHour) * 3600)
        let c = Calendar.current.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Häkchen gelten nur für den laufenden Abend.
    func forTonight(_ now: Date = Date()) -> Evening {
        guard night != Self.nightKey(now) else { return self }
        var e = self
        e.night = ""
        e.startedAt = nil
        e.checked = []
        e.tonightBed = isScheduled(now) ? nil : -1
        return e
    }

    /// Hat der laufende Abend (bis 5 Uhr früh) eine feste Zeit?
    func isScheduled(_ now: Date = Date()) -> Bool {
        let evening = now.addingTimeInterval(-Double(Self.dayStartHour) * 3600)
        if isPaused(on: evening) { return false }
        return days.contains(Calendar.current.component(.weekday, from: evening))
    }

    func isPaused(on date: Date) -> Bool {
        guard let pausedUntil else { return false }
        return Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: pausedUntil)
    }

    /// Schlafenszeit des laufenden Abends (0:30 liegt schon im nächsten Kalendertag).
    func bedDate(_ now: Date = Date()) -> Date {
        let base = Calendar.current.startOfDay(for: now.addingTimeInterval(-Double(Self.dayStartHour) * 3600))
        let bed = bedTonight
        let minutes = bed < Self.dayStartHour * 60 ? bed + 1440 : bed
        return base.addingTimeInterval(TimeInterval(minutes * 60))
    }
}

/// Kleine tägliche Dinge zum Abhaken – ohne Streak, nichts kann „reißen“.
struct Habit: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var symbol: String
    var perDay = 1
    var isMed = false                   // Tabletten: Uhrzeit sichtbar, Schutz vor doppelt eintragen
    var remindAt: Int?                  // Erinnerung (Minuten seit Mitternacht), nil = keine
    var stepGoal: Int?                  // hakt sich selbst ab, sobald die Uhr so viele Schritte zählt

    static let defaults = [
        Habit(title: "Wasser", symbol: "drop", perDay: 6),
        Habit(title: "Tabletten", symbol: "pills", isMed: true),
        Habit(title: "Kurz raus", symbol: "figure.walk"),
        Habit(title: "Zähne", symbol: "sparkles", perDay: 2),
    ]
}

struct HabitTick: Codable, Hashable {
    var habit: UUID
    var date: Date
}

/// Geld-Überblick: was reinkommt, was fest abgeht und was noch offen ist (z. B. Klarna).
struct MoneyItem: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable { case income, fixed, debt }

    var id = UUID()
    var title: String
    var amount: Double
    var kind: Kind
    var dayOfMonth = 1                  // Einnahme/Fixkosten: Tag im Monat
    var due: Date?                      // offene Zahlung: nächste Fälligkeit
    var remaining = 1                   // offene Zahlung: wie oft noch (1 = einmalig)
    var remind = true
}

/// Eine bezahlte Rate – damit der Monat richtig rechnet, auch wenn die nächste Rate schon wartet.
struct Payment: Codable, Identifiable, Hashable {
    var id = UUID()
    var itemID: UUID
    var title: String
    var amount: Double
    var date = Date()
}

/// Termine aus dem iPhone-Kalender – nur lesen, nie ändern.
struct CalendarSettings: Codable, Hashable {
    var on = true                       // Termine zeigen (wenn iOS es erlaubt)
    var leaveOn = true                  // „Losgehen“-Erinnerung
    var leadWithPlace = 30              // Min vor Beginn, wenn ein Ort dabei ist (Weg + Puffer)
    var leadWithout = 10
    var warnOn = true                   // Vorwarnung 15 Min vor dem Losgehen (nur mit Ort)
    var hidden: [String] = []           // ausgeblendete Kalender
    var leads: [String: Int] = [:]      // eigene Vorlaufzeit pro Termin, 0 = keine Erinnerung
}

/// Der „Wecker von außen“: kommt von selbst, ohne dass du etwas startest.
struct ReminderSettings: Codable, Hashable {
    var mealsOn = true
    var mealTimes = [12 * 60 + 30, 18 * 60]
    var nudgeOn = true
    var nudgeFrom = 16 * 60
    var nudgeTo = 23 * 60
    var nudgeEvery = 60
    var morningOn = true        // Mo–Fr zur Aufstehzeit
    var eveningOn = true
    var eveningAt = 21 * 60 + 30
    var persistOn = true                // Dranbleiben: nach 10 und 25 Min nochmal, bis „Erledigt“
    var custom: [CustomReminder] = []
    var spendAskOn = false              // abends: „Heute was ausgegeben?“ mit Antwortfeld
    var spendAskAt = 21 * 60
    var briefingOn = true               // Begleiter: Morgen-Überblick zur Aufstehzeit
    var reviewOn = true                 // Begleiter: Tagesrückblick + „Was ist morgen das Eine?“
    var freeDayBriefingAt = 10 * 60     // an Tagen ohne Morgen-Checkliste
    // Eigene Zeiten
    var timerPresets = [2, 5, 10, 25]   // Knöpfe beim Timer-Start
    var extendMinutes = 5               // „+5 Min“ beim Timer (App + Uhr)
    var snoozeMinutes = 10              // „In 10 Min“ bei Erinnerungen und Gewohnheiten
    var mealSnooze = 15
    var followUps = [10, 25]            // Dranbleiben: so viele Minuten danach nochmal
    var countdownOn = true              // Losgeh-Countdown (tippt auf der Uhr)
    var countdown = [10, 5]             // Minuten vor dem Losgehen
    var halfwayOn = true                // Timer: Tipper zur Halbzeit
    var sleepOn = false                 // Schlaf aus Health → sanfterer Tag
}

/// Eigene Erinnerung, z. B. „Tabletten nehmen“ um 8:00 an Werktagen.
struct CustomReminder: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var minutes: Int                    // Uhrzeit als Minuten seit Mitternacht
    var weekdays: [Int] = []            // 1 = So … 7 = Sa; leer = jeden Tag
    var onDate: Date?                   // gesetzt = einmalig an diesem Tag (z. B. aus einem Zeitplan)
    var detail = ""                     // Text der Benachrichtigung, z. B. der erste Schritt

    func isDue(on date: Date) -> Bool {
        if let onDate { return Calendar.current.isDate(onDate, inSameDayAs: date) }
        return weekdays.isEmpty || weekdays.contains(Calendar.current.component(.weekday, from: date))
    }
}

/// Spaß-Budget: Punkte schalten Geld für Spontankäufe frei.
struct BudgetSettings: Codable, Hashable {
    var monthly: Double = 30            // 0 = aus
    var targetXP = 1500                 // so viele XP im Monat = ganzes Budget frei
    var linked = false                  // statt fester Summe: Anteil vom Freien im Geld-Überblick
    var share = 0.3
}

/// Ein Eintrag im Geld-Tagebuch. Alte Einträge (vor Build 29) waren Spaß-Budget-Ausgaben.
struct Spend: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var amount: Double
    var date = Date()
    var kind: SpendKind = .fun
    var income = false                  // „+20 Oma“
}

/// Ein Laden mit eigener Gang-Reihenfolge – damit du nicht hin und her läufst.
/// Ein Ort (Zuhause, Laden, Uni …) mit Kreis um den Mittelpunkt. Kommst du an, melden sich Aufgaben „bei diesem Ort“.
struct Spot: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var symbol = "mappin.circle.fill"
    var lat: Double
    var lon: Double
    var radius = 150.0                  // Meter
    var shopHint = false                // „Du bist bei Lidl – 5 Sachen auf der Liste“

    init(name: String, symbol: String = "mappin.circle.fill", lat: Double, lon: Double,
         radius: Double = 150, shopHint: Bool = false) {
        self.name = name
        self.symbol = symbol
        self.lat = lat
        self.lon = lon
        self.radius = radius
        self.shopHint = shopHint
    }

    static let symbols = ["house.fill", "cart.fill", "graduationcap.fill", "building.2.fill", "figure.run",
                          "cup.and.saucer.fill", "cross.case.fill", "mappin.circle.fill"]
}

struct ShopPlace: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var order: [ShopCategory] = ShopCategory.allCases

    static let defaults = ["Lidl", "Aldi", "Rewe", "Edeka", "Kaufland", "Netto"].map { ShopPlace(name: $0) }

    /// Fehlende (neue) Gänge hinten anhängen, doppelte raus.
    var fullOrder: [ShopCategory] {
        var seen = Set<ShopCategory>()
        let known = order.filter { seen.insert($0).inserted }
        return known + ShopCategory.allCases.filter { !seen.contains($0) }
    }
}

struct ShopItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var category: ShopCategory
    var addedAt = Date()
    var boughtAt: Date?         // abgehakt („im Wagen“)

    init(name: String) {
        self.name = name
        self.category = ShopCategory.detect(name)
    }
}

/// Ein Kauf – daraus lernt die Liste, was wie oft fällig ist.
struct Purchase: Codable, Hashable {
    var key: String             // normalisiert: „2x Milch“ → „milch“
    var name: String
    var date: Date
}

/// Kauf-Parkplatz: erst 48 Stunden parken, dann entscheiden.
struct ParkedWish: Codable, Identifiable, Hashable {
    enum Decision: String, Codable { case keep, drop }

    var id = UUID()
    var name: String
    var price: Double?
    var parkedAt = Date()
    var decision: Decision?
    var decidedAt: Date?

    static let waitHours = 48.0
    var decideAfter: Date { parkedAt.addingTimeInterval(Self.waitHours * 3600) }
}

struct XPEvent: Codable, Hashable {
    var date: Date
    var amount: Int
    var reason: String
}

/// Game-Schicht: XP, Farben, Wochen-Quests. Bewusst ohne Streaks – nichts kann „reißen“.
struct GameState: Codable, Hashable {
    var xp = 0
    var log: [XPEvent] = []                 // die letzten Punkte, neueste zuerst
    var theme = "lila"
    var week = ""                           // „2026-W40“ – Quests gelten pro Woche
    var questProgress: [String: Int] = [:]
    var questsClaimed: [String] = []
    var activeDays: [String] = []           // „2026-09-30“ – nur zum Anzeigen, kein Streak
    var morningAwardedDay = ""
    var month = ""                          // „2026-10“ – fürs Spaß-Budget
    var monthXP = 0
    var dotName = "Dot"                     // der Assistent – umbenennbar
    var eveningAwardedDay = ""
}

/// Feedback an Claude – wartet in der App, bis Internet da ist.
struct FeedbackItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var text: String
    var screen: String
    var createdAt = Date()
    var sent = false
}

/// Alles, was die App speichert – eine JSON-Datei im App-Group-Container.
struct AppData: Codable {
    var tasks: [TaskItem] = []
    var memos: [Memo] = []
    var focus: FocusRun?
    var focusLog: [FocusLog] = []
    var morning = Morning()
    var reminders = ReminderSettings()
    var shopItems: [ShopItem] = []
    var purchases: [Purchase] = []
    var parked: [ParkedWish] = []
    var game = GameState()
    var feedback: [FeedbackItem] = []
    var shopLearned: [String: ShopCategory] = [:]   // „kichererbsen“ → .pantry (von dir oder Gemini)
    var budget = BudgetSettings()
    var spends: [Spend] = []
    var reminderAcks: [String: String] = [:]        // Erinnerungs-ID → Tag, an dem „Erledigt“ getippt wurde
    var checkins: [CheckIn] = []
    var shopPlaces = ShopPlace.defaults
    var lastPlace: UUID?
    var shopPrices: [String: Double] = [:]          // „2x milch“ → 2,18 (geschätzt)
    var ownPrices: [String: Double] = [:]           // „milch“ → 1,09 pro Stück (von dir eingetragen, schlägt die Schätzung)
    var shopPricesOn = true
    var evening = Evening()
    var companion: CompanionScript?                 // Dots Sätze für einen Tag (Gemini)
    var theOne: [String: UUID] = [:]                // „2026-10-03“ → die Aufgabe, die an dem Tag zählt
    var habits = Habit.defaults
    var habitTicks: [HabitTick] = []
    var money: [MoneyItem] = []
    var payments: [Payment] = []
    var calendar = CalendarSettings()
    var dotChat: [DotMessage] = []                  // Gespräch mit Dot (gekürzt auf DotChat.keep)
    var spots: [Spot] = []                          // Orte für Erinnerungen beim Ankommen
    var bank: BankBalance?                          // Kontostand vom letzten Banking-Screenshot
    var flyers: [Flyer] = []                        // eingelesene Prospekte (abgelaufene fliegen raus)
}

/// Kontostand, wie er auf dem letzten Screenshot stand (z. B. Sparkasse: die große Zahl oben).
struct BankBalance: Codable, Hashable {
    var amount: Double                  // darf negativ sein
    var account = ""                    // „Sparkasse Girokonto“
    var at = Date()                     // wann eingelesen

    init(amount: Double, account: String = "", at: Date = Date()) {
        self.amount = amount
        self.account = account
        self.at = at
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        amount = (try? c.decodeIfPresent(Double.self, forKey: .amount)) ?? 0
        account = (try? c.decodeIfPresent(String.self, forKey: .account)) ?? ""
        at = (try? c.decodeIfPresent(Date.self, forKey: .at)) ?? Date()
    }
}

// Tolerantes Dekodieren: Felder, die in einer älteren Version noch fehlten,
// bekommen ihren Standardwert, statt die ganze Datei unlesbar zu machen.
// (In Extensions, damit die memberwise-Initializer erhalten bleiben.)

private extension KeyedDecodingContainer {
    func value<T: Decodable>(_ key: Key, or fallback: T) -> T {
        (try? decodeIfPresent(T.self, forKey: key)) ?? fallback
    }
}

extension AppData {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tasks = c.value(.tasks, or: [])
        memos = c.value(.memos, or: [])
        focus = c.value(.focus, or: nil)
        focusLog = c.value(.focusLog, or: [])
        morning = c.value(.morning, or: Morning())
        reminders = c.value(.reminders, or: ReminderSettings())
        shopItems = c.value(.shopItems, or: [])
        purchases = c.value(.purchases, or: [])
        parked = c.value(.parked, or: [])
        game = c.value(.game, or: GameState())
        feedback = c.value(.feedback, or: [])
        shopLearned = c.value(.shopLearned, or: [:])
        budget = c.value(.budget, or: BudgetSettings())
        spends = c.value(.spends, or: [])
        reminderAcks = c.value(.reminderAcks, or: [:])
        checkins = c.value(.checkins, or: [])
        shopPlaces = c.value(.shopPlaces, or: ShopPlace.defaults)
        lastPlace = c.value(.lastPlace, or: nil)
        shopPrices = c.value(.shopPrices, or: [:])
        ownPrices = c.value(.ownPrices, or: [:])
        shopPricesOn = c.value(.shopPricesOn, or: true)
        evening = c.value(.evening, or: Evening())
        companion = c.value(.companion, or: nil)
        theOne = c.value(.theOne, or: [:])
        habits = c.value(.habits, or: Habit.defaults)
        habitTicks = c.value(.habitTicks, or: [])
        money = c.value(.money, or: [])
        payments = c.value(.payments, or: [])
        calendar = c.value(.calendar, or: CalendarSettings())
        dotChat = c.value(.dotChat, or: [])
        spots = c.value(.spots, or: [])
        bank = c.value(.bank, or: nil)
        flyers = c.value(.flyers, or: [])
    }
}

extension Evening {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        steps = c.value(.steps, or: Evening.defaultSteps)
        bedAt = c.value(.bedAt, or: 23 * 60 + 30)
        night = c.value(.night, or: "")
        startedAt = c.value(.startedAt, or: nil)
        checked = c.value(.checked, or: [])
        tonightBed = c.value(.tonightBed, or: nil)
        days = c.value(.days, or: [1, 2, 3, 4, 5, 6, 7])
        pausedUntil = c.value(.pausedUntil, or: nil)
    }
}

extension Spot {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        name = c.value(.name, or: "Ort")
        symbol = c.value(.symbol, or: "mappin.circle.fill")
        lat = c.value(.lat, or: 0)
        lon = c.value(.lon, or: 0)
        radius = c.value(.radius, or: 150)
        shopHint = c.value(.shopHint, or: false)
    }
}

extension ShopPlace {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        name = c.value(.name, or: "Laden")
        // unbekannte Gänge (aus einer neueren Version) einfach überspringen
        let raw: [String] = c.value(.order, or: [])
        order = raw.compactMap(ShopCategory.init(rawValue:))
        if order.isEmpty { order = ShopCategory.allCases }
    }
}

extension Habit {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        title = c.value(.title, or: "")
        symbol = c.value(.symbol, or: "checkmark")
        perDay = max(1, c.value(.perDay, or: 1))
        isMed = c.value(.isMed, or: false)
        remindAt = c.value(.remindAt, or: nil)
        stepGoal = c.value(.stepGoal, or: nil)
    }
}

extension MoneyItem {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        title = c.value(.title, or: "")
        amount = c.value(.amount, or: 0)
        kind = c.value(.kind, or: .fixed)
        dayOfMonth = c.value(.dayOfMonth, or: 1)
        due = c.value(.due, or: nil)
        remaining = max(1, c.value(.remaining, or: 1))
        remind = c.value(.remind, or: true)
    }
}

extension CalendarSettings {
    init(from decoder: Decoder) throws {
        let d = CalendarSettings()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        on = c.value(.on, or: d.on)
        leaveOn = c.value(.leaveOn, or: d.leaveOn)
        leadWithPlace = c.value(.leadWithPlace, or: d.leadWithPlace)
        leadWithout = c.value(.leadWithout, or: d.leadWithout)
        warnOn = c.value(.warnOn, or: d.warnOn)
        hidden = c.value(.hidden, or: [])
        leads = c.value(.leads, or: [:])
    }
}

extension FeedbackItem {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        text = c.value(.text, or: "")
        screen = c.value(.screen, or: "")
        createdAt = c.value(.createdAt, or: Date())
        sent = c.value(.sent, or: false)
    }
}

extension GameState {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        xp = c.value(.xp, or: 0)
        log = c.value(.log, or: [])
        theme = c.value(.theme, or: "lila")
        week = c.value(.week, or: "")
        questProgress = c.value(.questProgress, or: [:])
        questsClaimed = c.value(.questsClaimed, or: [])
        activeDays = c.value(.activeDays, or: [])
        morningAwardedDay = c.value(.morningAwardedDay, or: "")
        month = c.value(.month, or: "")
        monthXP = c.value(.monthXP, or: 0)
        dotName = c.value(.dotName, or: "Dot")
        eveningAwardedDay = c.value(.eveningAwardedDay, or: "")
    }
}

extension ShopItem {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        name = c.value(.name, or: "")
        category = c.value(.category, or: ShopCategory.detect(name))
        addedAt = c.value(.addedAt, or: Date())
        boughtAt = c.value(.boughtAt, or: nil)
    }
}

extension ParkedWish {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        name = c.value(.name, or: "")
        price = c.value(.price, or: nil)
        parkedAt = c.value(.parkedAt, or: Date())
        decision = c.value(.decision, or: nil)
        decidedAt = c.value(.decidedAt, or: nil)
    }
}

extension RoutineStep {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        title = c.value(.title, or: "")
        minutes = c.value(.minutes, or: 2)
    }
}

extension Morning {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        steps = c.value(.steps, or: Morning.defaultSteps)
        leaveAt = c.value(.leaveAt, or: 7 * 60 + 35)
        day = c.value(.day, or: nil)
        startedAt = c.value(.startedAt, or: nil)
        checked = c.value(.checked, or: [])
        todayLeave = c.value(.todayLeave, or: nil)
        days = c.value(.days, or: [2, 3, 4, 5, 6])
        pausedUntil = c.value(.pausedUntil, or: nil)
    }
}

extension ReminderSettings {
    init(from decoder: Decoder) throws {
        let d = ReminderSettings()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mealsOn = c.value(.mealsOn, or: d.mealsOn)
        mealTimes = c.value(.mealTimes, or: d.mealTimes)
        nudgeOn = c.value(.nudgeOn, or: d.nudgeOn)
        nudgeFrom = c.value(.nudgeFrom, or: d.nudgeFrom)
        nudgeTo = c.value(.nudgeTo, or: d.nudgeTo)
        nudgeEvery = c.value(.nudgeEvery, or: d.nudgeEvery)
        morningOn = c.value(.morningOn, or: d.morningOn)
        eveningOn = c.value(.eveningOn, or: d.eveningOn)
        eveningAt = c.value(.eveningAt, or: d.eveningAt)
        persistOn = c.value(.persistOn, or: d.persistOn)
        custom = c.value(.custom, or: [])
        spendAskOn = c.value(.spendAskOn, or: d.spendAskOn)
        spendAskAt = c.value(.spendAskAt, or: d.spendAskAt)
        briefingOn = c.value(.briefingOn, or: d.briefingOn)
        reviewOn = c.value(.reviewOn, or: d.reviewOn)
        freeDayBriefingAt = c.value(.freeDayBriefingAt, or: d.freeDayBriefingAt)
        timerPresets = c.value(.timerPresets, or: d.timerPresets)
        extendMinutes = c.value(.extendMinutes, or: d.extendMinutes)
        snoozeMinutes = c.value(.snoozeMinutes, or: d.snoozeMinutes)
        mealSnooze = c.value(.mealSnooze, or: d.mealSnooze)
        followUps = c.value(.followUps, or: d.followUps)
        countdownOn = c.value(.countdownOn, or: d.countdownOn)
        countdown = c.value(.countdown, or: d.countdown)
        halfwayOn = c.value(.halfwayOn, or: d.halfwayOn)
        sleepOn = c.value(.sleepOn, or: d.sleepOn)
    }
}

extension CustomReminder {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        title = c.value(.title, or: "")
        minutes = c.value(.minutes, or: 9 * 60)
        weekdays = c.value(.weekdays, or: [])
        onDate = c.value(.onDate, or: nil)
        detail = c.value(.detail, or: "")
    }
}

extension BudgetSettings {
    init(from decoder: Decoder) throws {
        let d = BudgetSettings()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        monthly = c.value(.monthly, or: d.monthly)
        targetXP = c.value(.targetXP, or: d.targetXP)
        linked = c.value(.linked, or: d.linked)
        share = c.value(.share, or: d.share)
    }
}

extension Spend {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        title = c.value(.title, or: "")
        amount = c.value(.amount, or: 0)
        date = c.value(.date, or: Date())
        kind = c.value(.kind, or: .fun)
        income = c.value(.income, or: false)
    }
}

/// Minuten seit Mitternacht ↔ Uhrzeit.
enum ClockTime {
    static func string(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        return String(format: "%d:%02d", m / 60, m % 60)
    }

    static func date(_ minutes: Int, on day: Date = Date()) -> Date {
        let start = Calendar.current.startOfDay(for: day)
        return start.addingTimeInterval(TimeInterval(minutes * 60))
    }

    /// „8:30“ / „08:30“ → 510
    static func parse(_ text: String) -> Int? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else { return nil }
        return parts[0] * 60 + parts[1]
    }

    static func minutes(of date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

extension TaskItem {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        title = c.value(.title, or: "")
        firstStep = c.value(.firstStep, or: "")
        createdAt = c.value(.createdAt, or: Date())
        doneAt = c.value(.doneAt, or: nil)
        dueDay = c.value(.dueDay, or: nil)
        steps = c.value(.steps, or: [])
        someday = c.value(.someday, or: false)
        showStep = c.value(.showStep, or: false)
        remindAt = c.value(.remindAt, or: nil)
        spotID = c.value(.spotID, or: nil)
    }
}

extension SubStep {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        title = c.value(.title, or: "")
        minutes = c.value(.minutes, or: 5)
        done = c.value(.done, or: false)
    }
}

extension Memo {
    private enum LegacyKeys: String, CodingKey { case isCheck }   // bis Build 9

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.value(.id, or: UUID())
        text = c.value(.text, or: "")
        createdAt = c.value(.createdAt, or: Date())
        photo = c.value(.photo, or: nil)
        let legacyCheck = (try? decoder.container(keyedBy: LegacyKeys.self))?.value(.isCheck, or: false) ?? false
        kind = c.value(.kind, or: MemoKind?.none) ?? (legacyCheck ? .done : MemoKind.detect(text))
    }
}
