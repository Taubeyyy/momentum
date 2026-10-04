import Foundation

/// RUHT SEIT BUILD 62: Edwin fand die Werkstatt „cool, aber too much“ – Seite, Mitteilung, Bauteile und Hut sind raus.
/// Logik und gespeicherter Stand (`AppData.workshop`) bleiben, damit sie bei Bedarf zurückkommen kann.
///
/// Dots Werkstatt – ein ruhiges Idle-Spiel. Bauteile gibt es fürs echte Nutzen der App (Erledigen, Fokus,
/// Gewohnheiten), Funken sammeln die Maschinen von allein. Nichts geht verloren, nichts reißt ab:
/// wer ein paar Tage weg ist, findet einfach mehr Funken vor (bis zu zwei Tage Vorrat).
/// Nur Foundation – läuft in der App und in den Logik-Tests.

struct Machine: Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String          // SF Symbol
    let tier: Int               // 1 … 5: teurer, aber mehr Funken
    let rate: Double            // Funken pro Stunde je Stufe
    let blurb: String

    static let all: [Machine] = [
        Machine(id: "wheel", name: "Funkenrad", symbol: "gearshape.fill", tier: 1, rate: 6,
                blurb: "Dreht sich, wenn Dot pustet. Der Anfang von allem."),
        Machine(id: "lamp", name: "Kurbellampe", symbol: "lightbulb.fill", tier: 2, rate: 14,
                blurb: "Leuchtet nachts – und sammelt dabei Funken."),
        Machine(id: "kettle", name: "Teekessel-Turbine", symbol: "cup.and.saucer.fill", tier: 3, rate: 30,
                blurb: "Pfeift leise. Dot schwört, Tee macht schneller."),
        Machine(id: "antenna", name: "Sternen-Antenne", symbol: "antenna.radiowaves.left.and.right", tier: 4, rate: 60,
                blurb: "Fängt Funken aus dem All. Angeblich."),
        Machine(id: "printer", name: "Dot-Drucker", symbol: "printer.fill", tier: 5, rate: 120,
                blurb: "Druckt kleine Dots. Die sammeln dann mit."),
        Machine(id: "cloud", name: "Wolkenmaschine", symbol: "cloud.bolt.fill", tier: 6, rate: 240,
                blurb: "Fängt Gewitter in Gläsern. Riecht nach Regen und Funken."),
    ]

    static let maxLevel = 10

    /// Kosten für die nächste Stufe (von `level` auf `level + 1`).
    func cost(fromLevel level: Int) -> (parts: Int, sparks: Int) {
        let next = level + 1
        let parts = 2 * tier * next
        let sparks = level == 0 ? 0 : Int(40 * Double(tier) * pow(Double(next), 1.6))
        return (parts, sparks)
    }

    /// Ab welcher Gesamtzahl gebauter Stufen die Maschine sichtbar wird (die nächste wartet schon als Umriss).
    var unlockAtLevels: Int { (tier - 1) * 3 }
}

/// Hüte für Dot – mit Funken gekauft, sichtbar überall in der App.
struct Hat: Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String          // SF Symbol
    let color: UInt32           // Farbe als Hex
    let price: Int

    static let all: [Hat] = [
        Hat(id: "flower", name: "Blümchen", symbol: "camera.macro", color: 0xF9A8D4, price: 80),
        Hat(id: "star", name: "Sternchen", symbol: "star.fill", color: 0xFDE047, price: 200),
        Hat(id: "sun", name: "Sonnenkranz", symbol: "sun.max.fill", color: 0xFCD34D, price: 320),
        Hat(id: "cap", name: "Doktorhut", symbol: "graduationcap.fill", color: 0x1F2937, price: 450),
        Hat(id: "bolt", name: "Blitz", symbol: "bolt.fill", color: 0xFACC15, price: 650),
        Hat(id: "phones", name: "Kopfhörer", symbol: "headphones", color: 0xE5E7EB, price: 900),
        Hat(id: "moon", name: "Mondmütze", symbol: "moon.stars.fill", color: 0xC7D2FE, price: 1400),
        Hat(id: "crown", name: "Krone", symbol: "crown.fill", color: 0xF59E0B, price: 2000),
        Hat(id: "party", name: "Partyhut", symbol: "party.popper.fill", color: 0xF472B6, price: 3200),
    ]
}

/// Räume für die Werkstatt-Szene – mit Funken gekauft. Farben als Hex (Wand oben/unten, Fenster oben/unten).
struct Room: Identifiable, Hashable {
    let id: String
    let name: String
    let wall: (UInt32, UInt32)
    let sky: (UInt32, UInt32)
    let price: Int

    static func == (a: Room, b: Room) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static let all: [Room] = [
        Room(id: "night", name: "Nachtwerkstatt", wall: (0x2B1D13, 0x1A120C), sky: (0x1E1B4B, 0x312E81), price: 0),
        Room(id: "dawn", name: "Morgenrot", wall: (0x3A1F1A, 0x1F120F), sky: (0xF97316, 0xFDBA74), price: 500),
        Room(id: "forest", name: "Waldhütte", wall: (0x1C2A1A, 0x101A0F), sky: (0x14532D, 0x4ADE80), price: 1500),
        Room(id: "space", name: "Weltall", wall: (0x14102B, 0x0A0818), sky: (0x020617, 0x4C1D95), price: 4000),
    ]

    static let standard = all[0]
}

/// Ausbau der Werkstatt selbst: größeres Lager (mehr Vorrat), bessere Werkzeuge (mehr Funken).
enum WorkshopUpgrade: String, CaseIterable, Hashable {
    case storage, tools

    var name: String { self == .storage ? "Größeres Lager" : "Bessere Werkzeuge" }
    var symbol: String { self == .storage ? "archivebox.fill" : "wrench.and.screwdriver.fill" }
    var maxLevel: Int { self == .storage ? 4 : 5 }

    func effect(_ level: Int) -> String {
        self == .storage ? "Vorrat \(48 + 24 * level) Std" : "+\(15 * level) % Funken"
    }

    func cost(fromLevel level: Int) -> (parts: Int, sparks: Int) {
        let next = level + 1
        return self == .storage ? (5 * next, 300 * next * next) : (8 * next, 500 * next * next)
    }
}

struct WorkshopState: Codable, Hashable {
    var levels: [String: Int] = [:]
    var parts = 0
    var sparks = 0.0
    var totalSparks = 0.0           // alles je Gesammelte (für Titel)
    var lastCollect: Date?          // nil = Werkstatt noch nicht gestartet
    var hats: [String] = []         // gekaufte Hüte
    var hat: String?                // den trägt Dot gerade
    var storage = 0                 // Ausbau: Lager
    var tools = 0                   // Ausbau: Werkzeuge
    var crateDay = ""               // „2026-10-04“ – an dem Tag schon geöffnet
    var rooms: [String] = []        // gekaufte Räume (Nachtwerkstatt gibt's immer)
    var room = "night"              // aktueller Raum

    init() {}

    var currentRoom: Room { Room.all.first { $0.id == room } ?? Room.standard }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        levels = (try? c.decodeIfPresent([String: Int].self, forKey: .levels)) ?? [:]
        parts = (try? c.decodeIfPresent(Int.self, forKey: .parts)) ?? 0
        sparks = (try? c.decodeIfPresent(Double.self, forKey: .sparks)) ?? 0
        totalSparks = (try? c.decodeIfPresent(Double.self, forKey: .totalSparks)) ?? 0
        lastCollect = (try? c.decodeIfPresent(Date.self, forKey: .lastCollect)) ?? nil
        hats = (try? c.decodeIfPresent([String].self, forKey: .hats)) ?? []
        hat = (try? c.decodeIfPresent(String.self, forKey: .hat)) ?? nil
        storage = (try? c.decodeIfPresent(Int.self, forKey: .storage)) ?? 0
        tools = (try? c.decodeIfPresent(Int.self, forKey: .tools)) ?? 0
        crateDay = (try? c.decodeIfPresent(String.self, forKey: .crateDay)) ?? ""
        rooms = (try? c.decodeIfPresent([String].self, forKey: .rooms)) ?? []
        room = (try? c.decodeIfPresent(String.self, forKey: .room)) ?? "night"
    }

    func level(_ upgrade: WorkshopUpgrade) -> Int { upgrade == .storage ? storage : tools }

    func level(_ machine: Machine) -> Int { levels[machine.id] ?? 0 }

    var builtLevels: Int { levels.values.reduce(0, +) }
}

enum Workshop {
    /// Vorrat: so viele Stunden sammelt die Werkstatt, bevor sie voll ist (danach wartet sie einfach).
    static func storageHours(_ state: WorkshopState) -> Double { 48 + 24 * Double(state.storage) }

    /// Funken pro Stunde aller Maschinen (mit Werkzeug-Bonus).
    static func production(_ state: WorkshopState) -> Double {
        let base = Machine.all.reduce(0.0) { $0 + $1.rate * Double(state.level($1)) }
        return base * (1 + 0.15 * Double(state.tools))
    }

    /// Was seit dem letzten Einsammeln bereitliegt.
    static func pending(_ state: WorkshopState, now: Date) -> Double {
        guard let last = state.lastCollect else { return 0 }
        let hours = min(storageHours(state), max(0, now.timeIntervalSince(last) / 3600))
        return production(state) * hours
    }

    /// Wie voll das Lager ist (0…1) – für die Anzeige.
    static func fill(_ state: WorkshopState, now: Date) -> Double {
        guard let last = state.lastCollect, production(state) > 0 else { return 0 }
        return min(1, max(0, now.timeIntervalSince(last) / 3600 / storageHours(state)))
    }

    static func isFull(_ state: WorkshopState, now: Date) -> Bool {
        guard let last = state.lastCollect, production(state) > 0 else { return false }
        return now.timeIntervalSince(last) >= storageHours(state) * 3600
    }

    // MARK: Ausbau, Hüte, Kiste, Titel

    static func canUpgrade(_ state: WorkshopState, _ upgrade: WorkshopUpgrade) -> Bool {
        let level = state.level(upgrade)
        guard level < upgrade.maxLevel, state.builtLevels > 0 else { return false }
        let cost = upgrade.cost(fromLevel: level)
        return state.parts >= cost.parts && Int(state.sparks) >= cost.sparks
    }

    static func upgrade(_ state: WorkshopState, _ upgrade: WorkshopUpgrade, now: Date) -> WorkshopState? {
        var s = collect(state, now: now)       // erst mit altem Bonus einsammeln
        guard canUpgrade(s, upgrade) else { return nil }
        let cost = upgrade.cost(fromLevel: s.level(upgrade))
        s.parts -= cost.parts
        s.sparks -= Double(cost.sparks)
        if upgrade == .storage { s.storage += 1 } else { s.tools += 1 }
        return s
    }

    static func buy(_ state: WorkshopState, _ hat: Hat) -> WorkshopState? {
        guard !state.hats.contains(hat.id), Int(state.sparks) >= hat.price else { return nil }
        var s = state
        s.sparks -= Double(hat.price)
        s.hats.append(hat.id)
        s.hat = hat.id
        return s
    }

    static func owns(_ state: WorkshopState, _ room: Room) -> Bool {
        room.price == 0 || state.rooms.contains(room.id)
    }

    /// Raum kaufen (und gleich einziehen) oder – schon gekauft – nur wechseln.
    static func enter(_ state: WorkshopState, _ room: Room) -> WorkshopState? {
        var s = state
        if !owns(state, room) {
            guard Int(state.sparks) >= room.price else { return nil }
            s.sparks -= Double(room.price)
            s.rooms.append(room.id)
        }
        s.room = room.id
        return s
    }

    /// Was Dot in der Werkstatt sagt – wechselt alle paar Sekunden, passt zur Lage.
    static func dotLine(_ state: WorkshopState, now: Date, tick: Int) -> String {
        if state.builtLevels == 0 { return "Ein Funkenrad wär schön. Eine Aufgabe reicht dafür." }
        if isFull(state, now: now) { return "Lager voll! Ich hab schon gestapelt." }
        let lines = [
            "Die Maschinen summen. Ich mag das.",
            "Funken sind wie Konfetti, nur nützlicher.",
            "Kein Stress. Die Werkstatt wartet auf dich.",
            "Hast du was erledigt? Dann gibt's Bauteile.",
            "Ich hab das Rad geölt. Glaub ich.",
            "Leise Arbeit ist auch Arbeit.",
        ]
        return lines[((tick % lines.count) + lines.count) % lines.count]
    }

    /// Einmal am Tag eine Kiste – sobald irgendwas gebaut ist. Kein Streak: verpasste Tage sind einfach weg.
    static func crateReady(_ state: WorkshopState, today: String) -> Bool {
        state.builtLevels > 0 && state.crateDay != today
    }

    /// Kiste öffnen; `roll` (0…1) kommt vom Zufall. Mal Funken, mal Bauteile, selten viel von beidem.
    static func openCrate(_ state: WorkshopState, today: String, roll: Double) -> (state: WorkshopState, text: String)? {
        guard crateReady(state, today: today) else { return nil }
        var s = state
        s.crateDay = today
        let hourly = max(10, production(state))
        if roll < 0.5 {
            let sparks = (hourly * 3).rounded()
            s.sparks += sparks
            s.totalSparks += sparks
            return (s, "+\(amount(sparks)) Funken")
        } else if roll < 0.9 {
            let parts = 2 + Int(roll * 10) % 3
            s.parts += parts
            return (s, "+\(parts) Bauteile")
        } else {
            let sparks = (hourly * 8).rounded()
            s.sparks += sparks
            s.totalSparks += sparks
            s.parts += 5
            return (s, "Glückskiste! +\(amount(sparks)) Funken und 5 Bauteile")
        }
    }

    /// Titel nach allen je gesammelten Funken.
    static func title(_ state: WorkshopState) -> String {
        switch state.totalSparks {
        case ..<300: return "Lehrling"
        case ..<1_500: return "Bastler"
        case ..<6_000: return "Tüftler"
        case ..<25_000: return "Erfinder"
        default: return "Funken-Legende"
        }
    }

    static func collect(_ state: WorkshopState, now: Date) -> WorkshopState {
        var s = state
        let got = pending(state, now: now)
        s.sparks += got
        s.totalSparks += got
        s.lastCollect = now
        return s
    }

    /// Bauteile fürs echte Nutzen – aus den Punkten einer Belohnung (mindestens 1).
    static func parts(forXP xp: Int) -> Int { max(1, xp / 10) }

    static func canUpgrade(_ state: WorkshopState, _ machine: Machine) -> Bool {
        let level = state.level(machine)
        guard level < Machine.maxLevel, isVisible(state, machine) else { return false }
        let cost = machine.cost(fromLevel: level)
        return state.parts >= cost.parts && Int(state.sparks) >= cost.sparks
    }

    static func isVisible(_ state: WorkshopState, _ machine: Machine) -> Bool {
        state.builtLevels >= machine.unlockAtLevels
    }

    /// Erst einsammeln (damit die Produktion ab jetzt mit der neuen Stufe rechnet), dann bauen.
    static func upgrade(_ state: WorkshopState, _ machine: Machine, now: Date) -> WorkshopState? {
        var s = collect(state, now: now)
        guard canUpgrade(s, machine) else { return nil }
        let cost = machine.cost(fromLevel: s.level(machine))
        s.parts -= cost.parts
        s.sparks -= Double(cost.sparks)
        s.levels[machine.id] = s.level(machine) + 1
        if s.lastCollect == nil { s.lastCollect = now }
        return s
    }

    /// Was fehlt, freundlich: „Noch 3 Bauteile – z. B. eine Aufgabe erledigen.“
    static func missingText(_ state: WorkshopState, _ machine: Machine) -> String? {
        let level = state.level(machine)
        guard level < Machine.maxLevel else { return "Ganz ausgebaut." }
        let cost = machine.cost(fromLevel: level)
        let parts = cost.parts - state.parts
        let sparks = cost.sparks - Int(state.sparks)
        if parts > 0 { return "Noch \(parts) Bauteil\(parts == 1 ? "" : "e") – z. B. eine Aufgabe erledigen." }
        if sparks > 0 { return "Noch \(sparks) Funken – die sammelt Dot von allein." }
        return nil
    }

    /// „1.234“ ohne Nachkommastellen.
    static func amount(_ value: Double) -> String { Timing.thousands(Int(value)) }
}
