import Foundation
import WidgetKit

/// Einzige Quelle der Wahrheit für die App. Speichert nach jeder Änderung
/// und spiegelt das, was die Widgets brauchen, in die App-Group-Defaults.
@MainActor
final class Store: ObservableObject {
    /// Eine Instanz für App und Benachrichtigungs-Aktionen (AppDelegate).
    static let shared = Store()

    @Published private(set) var data = AppData()
    /// Die letzte Belohnung – RootView zeigt sie kurz oben an (+XP, Level-Up, Quest).
    @Published var lastAward: Award?
    private let fileURL: URL

    private init() {
        fileURL = Shared.dataURL
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("dopa.json")
        if let raw = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(AppData.self, from: raw) {
            data = decoded
        }
        // Einmalige Erinnerungen von gestern und älter sind vorbei
        let yesterday = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-86_400)
        data.reminders.custom.removeAll { r in r.onDate.map { $0 < yesterday } ?? false }
        // Abgehakte Einkäufe von gestern und älter brauchen wir nur noch in der Statistik
        data.shopItems.removeAll { item in item.boughtAt.map { !Calendar.current.isDateInToday($0) } ?? false }
        if data.purchases.count > 1500 { data.purchases.removeFirst(data.purchases.count - 1500) }
        // Gewohnheiten: zwei Monate reichen für die Wochenansicht
        let twoMonths = Date().addingTimeInterval(-60 * 86_400)
        data.habitTicks.removeAll { $0.date < twoMonths }
        if data.payments.count > 400 { data.payments.removeFirst(data.payments.count - 400) }
        // „Erledigt“/„Bin los“-Markierungen älter als zwei Wochen braucht niemand mehr
        let cutoff = Quest.dayKey(Date().addingTimeInterval(-14 * 86_400))
        data.reminderAcks = data.reminderAcks.filter { $0.value >= cutoff }
    }

    private func save() {
        do {
            try JSONEncoder().encode(data).write(to: fileURL, options: .atomic)
            // „Als Nächstes“- und Morgen-Widget lesen die Datei direkt
            WidgetCenter.shared.reloadTimelines(ofKind: "NextWidget")
            WidgetCenter.shared.reloadTimelines(ofKind: "MorningWidget")
            WidgetCenter.shared.reloadTimelines(ofKind: "ShopWidget")
        } catch {
            print("Speichern fehlgeschlagen: \(error)")
        }
        scheduleBackup()
        scheduleDayRefresh()
    }

    // MARK: Aufgaben

    var openTasks: [TaskItem] { data.tasks.filter { $0.doneAt == nil } }

    /// Für heute: ohne Tag oder fällig bis heute (nicht „Irgendwann“).
    var todayTasks: [TaskItem] {
        let end = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400)
        return openTasks.filter { !$0.someday && ($0.dueDay.map { $0 < end } ?? true) }
    }

    /// Für einen späteren Tag geplant.
    var upcomingTasks: [TaskItem] {
        let end = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400)
        return openTasks.filter { !$0.someday && ($0.dueDay.map { $0 >= end } ?? false) }
            .sorted { ($0.dueDay ?? .distantFuture) < ($1.dueDay ?? .distantFuture) }
    }

    /// Ohne Termin – irgendwann.
    var somedayTasks: [TaskItem] { openTasks.filter(\.someday) }

    enum TaskPlan: Equatable { case today, tomorrow, date(Date), someday }

    func plan(of task: TaskItem) -> TaskPlan {
        if task.someday { return .someday }
        guard let due = task.dueDay else { return .today }
        let cal = Calendar.current
        if due < cal.startOfDay(for: Date()).addingTimeInterval(86_400) { return .today }
        if cal.isDateInTomorrow(due) { return .tomorrow }
        return .date(due)
    }

    /// Heute, morgen, ein Datum oder irgendwann – frei planbar.
    func setPlan(_ id: UUID, _ plan: TaskPlan) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        updateTask(id) { task in
            switch plan {
            case .today:
                task.dueDay = nil
                task.someday = false
            case .tomorrow:
                task.dueDay = cal.date(byAdding: .day, value: 1, to: today)
                task.someday = false
            case .date(let date):
                let day = cal.startOfDay(for: date)
                task.dueDay = day <= today ? nil : day
                task.someday = false
            case .someday:
                task.dueDay = nil
                task.someday = true
            }
            // Uhrzeit wandert mit auf den neuen Tag; „Irgendwann“ hat keine Uhrzeit
            if let at = task.remindAt {
                task.remindAt = task.someday ? nil : Timing.moveTime(at, to: task.dueDay ?? today)
            }
        }
        if data.tasks.first(where: { $0.id == id })?.remindAt != nil || plan == .someday { rescheduleReminders() }
    }

    /// Mini-Schritt zeigen (beim ersten Mal schlägt Dopa einen vor) oder wieder ausblenden.
    func setShowStep(_ id: UUID, _ show: Bool) {
        updateTask(id) { task in
            task.showStep = show
            if show && task.firstStep.isEmpty { task.firstStep = Smart.firstStep(for: task.title) }
        }
    }

    func setFirstStep(_ id: UUID, _ step: String) {
        updateTask(id) { $0.firstStep = step }      // nicht trimmen – wird beim Tippen live gesetzt
    }

    /// Feste Uhrzeit mit Erinnerung (nil = keine). Legt die Aufgabe auf den passenden Tag.
    func setTaskTime(_ id: UUID, _ time: Date?) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        updateTask(id) { task in
            task.remindAt = time
            guard let time else { return }
            let day = cal.startOfDay(for: time)
            task.dueDay = day <= today ? nil : day
            task.someday = false
        }
        rescheduleReminders()
    }

    func renameTask(_ id: UUID, _ title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        updateTask(id) { $0.title = title }
    }

    // MARK: Schritte (selbst angelegt oder zerlegt)

    func addStep(_ taskID: UUID, _ title: String, minutes: Int = 5) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        updateTask(taskID) { $0.steps.append(SubStep(title: title, minutes: minutes)) }
    }

    func updateStep(_ taskID: UUID, _ stepID: UUID, title: String? = nil, minutes: Int? = nil) {
        updateTask(taskID) { task in
            guard let i = task.steps.firstIndex(where: { $0.id == stepID }) else { return }
            if let title, !title.trimmingCharacters(in: .whitespaces).isEmpty { task.steps[i].title = title }
            if let minutes { task.steps[i].minutes = max(1, min(240, minutes)) }
        }
    }

    func deleteStep(_ taskID: UUID, _ stepID: UUID) {
        updateTask(taskID) { $0.steps.removeAll { $0.id == stepID } }
    }

    func moveSteps(_ taskID: UUID, from source: IndexSet, to destination: Int) {
        updateTask(taskID) { $0.steps.move(fromOffsets: source, toOffset: destination) }
    }

    /// Ohne Umweg loslegen: nächster Schritt, dessen Minuten (sonst 10).
    func quickStart(_ task: TaskItem, minutes: Int? = nil) {
        guard data.focus == nil else { return }
        startFocus(taskID: task.id, title: task.title, step: task.nextStep,
                   minutes: minutes ?? task.nextStepMinutes ?? 10)
    }

    var doneToday: [TaskItem] {
        data.tasks.filter { task in task.doneAt.map { Calendar.current.isDateInToday($0) } ?? false }
    }

    /// Aufgabe mit Frist (Tage ab heute; ≤ 0 = heute) – z. B. ein Auftrag aus „Merken“.
    func addTask(_ title: String, day: Int) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        var task = TaskItem(title: title, firstStep: Smart.firstStep(for: title))
        if day > 0 {
            task.dueDay = Calendar.current.date(byAdding: .day, value: day, to: Calendar.current.startOfDay(for: Date()))
        }
        data.tasks.insert(task, at: 0)
        save()
    }

    func addTask(_ title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        data.tasks.insert(TaskItem(title: title, firstStep: Smart.firstStep(for: title)), at: 0)
        save()
    }

    /// „Such mir was aus“: eine der drei ältesten offenen Aufgaben – die bleiben sonst ewig liegen.
    func pickTask() -> TaskItem? {
        openTasks.sorted { $0.createdAt < $1.createdAt }.prefix(3).randomElement()
    }

    func setDone(_ id: UUID, _ done: Bool) {
        let wasDone = data.tasks.first { $0.id == id }?.doneAt != nil
        updateTask(id) { $0.doneAt = done ? Date() : nil }
        if done && !wasDone { award(.taskDone) }
        if !done && wasDone { revoke(.taskDone) }
        if let t = data.tasks.first(where: { $0.id == id }), t.remindAt != nil || t.spotID != nil {
            rescheduleReminders()           // Erinnerung (Uhrzeit oder Ort) weg bzw. wieder da
        }
    }

    /// Eigene Reihenfolge: gezogene Aufgabe an die Stelle der anderen.
    func reorderTask(_ moving: UUID, to target: UUID) {
        guard moving != target,
              let from = data.tasks.firstIndex(where: { $0.id == moving }),
              let to = data.tasks.firstIndex(where: { $0.id == target }) else { return }
        data.tasks.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        save()
    }

    /// „Auf morgen“ – ohne schlechtes Gewissen schieben.
    func moveToTomorrow(_ id: UUID) {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))
        updateTask(id) { $0.dueDay = tomorrow }
        Toaster.shared.show("Auf morgen geschoben")
    }

    /// Aus „Nächste Tage“ nach heute holen.
    func moveToToday(_ id: UUID) {
        updateTask(id) { $0.dueDay = nil }
    }

    func deleteTask(_ id: UUID) {
        let hadTime = data.tasks.first { $0.id == id }?.remindAt != nil
        data.tasks.removeAll { $0.id == id }
        save()
        if hadTime { rescheduleReminders() }
    }

    private func updateTask(_ id: UUID, _ change: (inout TaskItem) -> Void) {
        guard let i = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        change(&data.tasks[i])
        save()
    }

    // MARK: Merken

    /// `kind: nil` = automatisch erkennen.
    func addMemo(_ text: String, kind: MemoKind?, xp: XPKind? = .memo, photo: String? = nil) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        data.memos.insert(Memo(text: text, kind: kind, photo: photo), at: 0)
        save()
        syncMemoWidget()
        if let xp { award(xp) }
    }

    /// „Gegessen ✔︎“ aus der Essens-Erinnerung.
    func mealEaten() {
        addMemo("Gegessen", kind: .done, xp: .mealEaten)
    }

    func deleteMemo(_ id: UUID) {
        if let photo = data.memos.first(where: { $0.id == id })?.photo { MemoPhotos.delete(photo) }
        data.memos.removeAll { $0.id == id }
        save()
        syncMemoWidget()
    }

    private func syncMemoWidget() {
        let latest = data.memos.first.map { "\($0.photo == nil ? $0.kind.emoji : "📷") \($0.text)" } ?? ""
        Shared.defaults?.set(latest, forKey: Shared.widgetTextKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "NoteWidget")
    }

    // MARK: Morgen

    /// Häkchen und Startzeit gelten nur für heute – am nächsten Tag ist alles wieder offen.
    var morning: Morning { data.morning.forToday() }

    var morningLeaveDate: Date { morning.leaveDate() }

    func startMorningIfNeeded() {
        guard morning.startedAt == nil else { return }
        var m = morning
        m.day = Date()
        m.startedAt = Date()
        data.morning = m
        save()
    }

    func toggleMorningStep(_ id: UUID) {
        var m = morning
        m.day = Date()
        if m.startedAt == nil { m.startedAt = Date() }
        let checking = !m.checked.contains(id)
        if checking {
            m.checked.append(id)
        } else {
            m.checked.removeAll { $0 == id }
        }
        data.morning = m
        save()
        let today = Quest.dayKey()
        if checking && m.isDone && data.game.morningAwardedDay != today {
            data.game.morningAwardedDay = today
            award(.morningStep, .morningDone)
        } else if checking {
            award(.morningStep)
        } else {
            revoke(.morningStep)
        }
    }

    /// Heute später/früher los – oder ohne Uhr (-1). nil = zurück zum Plan.
    func setMorningLeaveToday(_ minutes: Int?) {
        var m = morning
        m.day = Date()
        m.todayLeave = minutes
        data.morning = m
        save()
    }

    func resetMorning() {
        var m = data.morning
        m.day = nil
        m.startedAt = nil
        m.checked = []
        data.morning = m
        save()
    }

    func updateMorningPlan(steps: [RoutineStep], leaveAt: Int, days: [Int]) {
        data.morning.steps = steps.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
        data.morning.leaveAt = leaveAt
        data.morning.days = days
        save()
        rescheduleReminders()
    }

    // MARK: Wecker von außen

    func updateReminders(_ settings: ReminderSettings) {
        let buttonsChanged = settings.snoozeMinutes != data.reminders.snoozeMinutes
            || settings.mealSnooze != data.reminders.mealSnooze
            || settings.extendMinutes != data.reminders.extendMinutes
        data.reminders = settings
        save()
        if buttonsChanged { Reminders.registerCategories(settings) }
        rescheduleReminders()
    }

    func rescheduleReminders() {
        let context = Reminders.Context(
            settings: data.reminders,
            morning: data.morning,
            evening: data.evening,
            acks: data.reminderAcks,
            habits: data.habits,
            habitsDone: Set(data.habits.filter { habitCount($0.id) >= $0.perDay }.map(\.id)),
            money: data.money,
            events: data.calendar.on && data.calendar.leaveOn
                ? Agenda.shared.upcoming(days: 3, hidden: data.calendar.hidden) : [],
            calendar: data.calendar,
            companion: companionNotes(),
            script: todayScript,
            tasks: data.tasks.filter { $0.doneAt == nil && ($0.remindAt ?? .distantPast) > Date() },
            spots: data.spots,
            spotTasks: data.tasks.filter { $0.doneAt == nil && $0.spotID != nil },
            shopCount: data.shopItems.filter { $0.boughtAt == nil }.count)
        Task { await Reminders.reschedule(context) }
    }

    // MARK: Einkauf

    /// Offene Sachen in der Reihenfolge des zuletzt gewählten Ladens.
    var shopOpen: [ShopItem] { shopOpen(for: currentPlace) }

    var shopInCart: [ShopItem] { data.shopItems.filter { $0.boughtAt != nil } }

    private var openKeys: Set<String> { Set(shopOpen.map { ShopText.key($0.name) }) }

    /// „Milch, Brot und Eier“ → drei Einträge; was schon draufsteht, kommt nicht doppelt.
    /// Gang: erst was du/Gemini schon mal festgelegt habt, dann Stichwörter, sonst fragt Gemini.
    /// Genau ein Artikel (Barcode, Prospekt) – ohne „Milch Brot Eier“-Zerlegen. Doppelt wird nichts.
    func addShopItem(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = ShopText.key(name)
        guard !name.isEmpty, !openKeys.contains(key) else { return }
        var item = ShopItem(name: name)
        if let learned = data.shopLearned[key] { item.category = learned }
        data.shopItems.append(item)
        save()
        if item.category == .other { Task { await categorizeWithAI([name]) } }
        Task { await estimatePrices() }
    }

    func addShop(_ input: String) {
        var keys = openKeys
        var unknown: [String] = []
        let known = Set(data.shopLearned.keys).union(data.purchases.map(\.key))
        for name in ShopText.split(input, known: known) {
            let key = ShopText.key(name)
            guard !keys.contains(key) else { continue }
            keys.insert(key)
            var item = ShopItem(name: name)
            if let learned = data.shopLearned[key] { item.category = learned }
            if item.category == .other { unknown.append(name) }
            data.shopItems.append(item)
        }
        save()
        if !unknown.isEmpty { Task { await categorizeWithAI(unknown) } }
        Task { await estimatePrices() }
    }

    // MARK: Einkauf: Preise

    private static func priceKey(_ name: String) -> String { name.lowercased().trimmingCharacters(in: .whitespaces) }

    /// Dein eigener Preis (pro Stück × Menge) schlägt die Schätzung. Eigene Preise zeigt Dopa auch,
    /// wenn die Schätzungen ausgeschaltet sind.
    func shopPrice(_ item: ShopItem) -> Double? {
        if let own = PriceBook.price(for: item.name, own: data.ownPrices) { return own }
        return data.shopPricesOn ? data.shopPrices[Self.priceKey(item.name)] : nil
    }

    /// Hast du den Preis selbst eingetragen? (dann ohne „~“ anzeigen)
    func isOwnPrice(_ item: ShopItem) -> Bool {
        data.ownPrices[ShopText.key(item.name)] != nil
    }

    /// Summe der Schätzungen; `known` = wie viele davon einen Preis haben.
    func shopTotal(_ items: [ShopItem]) -> (sum: Double, known: Int) {
        let prices = items.compactMap { shopPrice($0) }
        return (prices.reduce(0, +), prices.count)
    }

    /// Fehlende Preise bei Gemini schätzen lassen (eine Anfrage für alle).
    func estimatePrices() async {
        guard data.shopPricesOn, Server.shared.isConnected, Server.shared.aiAvailable else { return }
        let missing = shopOpen.map(\.name).filter {
            data.shopPrices[Self.priceKey($0)] == nil && PriceBook.price(for: $0, own: data.ownPrices) == nil
        }
        // deine eigenen Preise als Richtwert mitschicken (höchstens 30)
        let known: String = data.ownPrices.sorted { $0.key < $1.key }.prefix(30)
            .map { "\($0.key) \(MoneyMath.euro($0.value))" }.joined(separator: "; ")
        guard !missing.isEmpty,
              let result = try? await Server.shared.prices(Array(missing.prefix(40)), known: known) else { return }
        for (name, euro) in result { data.shopPrices[Self.priceKey(name)] = euro }
        if data.shopPrices.count > 600 { data.shopPrices = [:] }    // Notbremse, falls die Liste ausufert
        save()
    }

    /// Preis von Hand – pro Stück gemerkt und beim nächsten Mal statt der Schätzung genommen.
    /// Leer/0 = eigenen Preis vergessen, dann schätzt Dopa wieder.
    func setShopPrice(_ item: ShopItem, _ euro: Double?) {
        let key = ShopText.key(item.name)
        data.shopPrices[Self.priceKey(item.name)] = nil
        if let euro, euro > 0 {
            data.ownPrices[key] = PriceBook.unitPrice(total: euro, name: item.name)
        } else {
            data.ownPrices[key] = nil
            Task { await estimatePrices() }
        }
        save()
    }

    func setShopPricesOn(_ on: Bool) {
        data.shopPricesOn = on
        save()
        if on { Task { await estimatePrices() } }
    }

    // MARK: Einkauf: Läden und Einkaufsmodus

    var currentPlace: ShopPlace? {
        data.shopPlaces.first { $0.id == data.lastPlace } ?? data.shopPlaces.first
    }

    func choosePlace(_ id: UUID) {
        data.lastPlace = id
        save()
    }

    func savePlace(_ place: ShopPlace) {
        if let i = data.shopPlaces.firstIndex(where: { $0.id == place.id }) {
            data.shopPlaces[i] = place
        } else {
            data.shopPlaces.append(place)
        }
        save()
    }

    func deletePlace(_ id: UUID) {
        data.shopPlaces.removeAll { $0.id == id }
        if data.lastPlace == id { data.lastPlace = data.shopPlaces.first?.id }
        save()
    }

    /// Offene Sachen in der Gang-Reihenfolge des Ladens.
    func shopOpen(for place: ShopPlace?) -> [ShopItem] {
        let order = place?.fullOrder ?? ShopCategory.allCases
        func rank(_ c: ShopCategory) -> Int { order.firstIndex(of: c) ?? 99 }
        return data.shopItems
            .filter { $0.boughtAt == nil }
            .sorted { (rank($0.category), $0.addedAt) < (rank($1.category), $1.addedAt) }
    }

    /// Einkauf abschließen: Wagen leeren, bezahlten Betrag ins Geld-Tagebuch, Reihenfolge merken.
    func finishShopping(place: ShopPlace?, paid: Double, learnedOrder: [ShopCategory]?) {
        let count = shopInCart.count
        if let place, let learnedOrder, let i = data.shopPlaces.firstIndex(where: { $0.id == place.id }) {
            data.shopPlaces[i].order = learnedOrder
        }
        if paid > 0 {
            data.spends.append(Spend(title: "Einkauf \(place?.name ?? "")".trimmingCharacters(in: .whitespaces),
                                     amount: paid, kind: .groceries))
        }
        data.shopItems.removeAll { $0.boughtAt != nil }
        save()
        if count > 0 { award(.shopDone) }
        Toaster.shared.show(paid > 0 ? "Einkauf fertig · \(MoneyMath.euro(paid)) notiert" : "Einkauf fertig")
    }

    private func categorizeWithAI(_ names: [String]) async {
        guard Server.shared.isConnected, Server.shared.aiAvailable,
              let result = try? await Server.shared.categorize(names) else { return }
        for (name, raw) in result {
            guard let category = ShopCategory(rawValue: raw), category != .other else { continue }
            let key = ShopText.key(name)
            data.shopLearned[key] = category
            for i in data.shopItems.indices where ShopText.key(data.shopItems[i].name) == key && data.shopItems[i].category == .other {
                data.shopItems[i].category = category
            }
        }
        save()
    }

    /// Von Hand in einen anderen Gang – und fürs nächste Mal merken.
    func setCategory(_ id: UUID, _ category: ShopCategory) {
        guard let i = data.shopItems.firstIndex(where: { $0.id == id }) else { return }
        data.shopItems[i].category = category
        data.shopLearned[ShopText.key(data.shopItems[i].name)] = category
        save()
    }

    func toggleBought(_ id: UUID) {
        guard let i = data.shopItems.firstIndex(where: { $0.id == id }) else { return }
        let item = data.shopItems[i]
        let key = ShopText.key(item.name)
        if let bought = item.boughtAt {
            data.shopItems[i].boughtAt = nil
            data.purchases.removeAll { $0.key == key && $0.date == bought }
            save()
            revoke(.shopBought)
        } else {
            let now = Date()
            data.shopItems[i].boughtAt = now
            data.purchases.append(Purchase(key: key, name: item.name, date: now))
            save()
            award(.shopBought)
        }
    }

    func removeShop(_ id: UUID) {
        data.shopItems.removeAll { $0.id == id }
        save()
    }

    func clearCart() {
        data.shopItems.removeAll { $0.boughtAt != nil }
        save()
    }

    struct ShopSuggestion: Identifiable {
        var id: String { key }
        let key: String
        let name: String
        let reason: String
    }

    /// Was du regelmäßig kaufst und laut deinem eigenen Rhythmus bald wieder brauchst.
    var shopDue: [ShopSuggestion] {
        let now = Date()
        let day = 86_400.0
        let onList = openKeys
        var result: [(ShopSuggestion, Double)] = []
        for (key, buys) in Dictionary(grouping: data.purchases, by: \.key) where !onList.contains(key) {
            // Käufe am selben Tag zählen einmal
            var dates: [Date] = []
            for date in buys.map(\.date).sorted() where dates.last.map({ date.timeIntervalSince($0) > day / 2 }) ?? true {
                dates.append(date)
            }
            guard dates.count >= 2, let last = dates.last else { continue }
            let gaps = zip(dates.dropFirst(), dates).map { $0.timeIntervalSince($1) }.sorted()
            let interval = gaps[gaps.count / 2]
            let since = now.timeIntervalSince(last)
            guard since >= interval - day / 2 else { continue }
            let every = max(1, Int((interval / day).rounded()))
            let ago = Int((since / day).rounded())
            let name = buys.max { $0.date < $1.date }?.name ?? key
            let reason = "ca. alle \(every) \(every == 1 ? "Tag" : "Tage") · zuletzt vor \(ago) \(ago == 1 ? "Tag" : "Tagen")"
            result.append((ShopSuggestion(key: key, name: name, reason: reason), since / interval))
        }
        return result.sorted { $0.1 > $1.1 }.prefix(6).map { $0.0 }
    }

    /// Die am häufigsten gekauften Sachen als Ein-Tipp-Knöpfe.
    var shopFrequent: [String] {
        let skip = openKeys.union(shopDue.map(\.key))
        return Dictionary(grouping: data.purchases, by: \.key)
            .filter { !skip.contains($0.key) && $0.value.count >= 2 }
            .sorted { $0.value.count > $1.value.count }
            .prefix(8)
            .compactMap { $0.value.max { $0.date < $1.date }?.name }
    }

    /// Essen, das ohne Kochen geht – weil du tagsüber oft vergisst zu essen.
    var snackHints: [String] {
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        let recentSnack = data.purchases.contains { $0.date > weekAgo && Self.isGrabFood($0.key) }
        let listed = shopOpen.contains { Self.isGrabFood(ShopText.key($0.name)) }
        guard !recentSnack, !listed else { return [] }
        return ["Bananen", "Nüsse", "Müsliriegel", "Joghurt", "Brötchen"]
    }

    private static func isGrabFood(_ key: String) -> Bool {
        ["banane", "nüsse", "nuss", "riegel", "joghurt", "brötchen", "apfel", "äpfel", "skyr", "cracker"]
            .contains { key.contains($0) }
    }

    // MARK: Kauf-Parkplatz

    func park(_ name: String, price: Double?) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let wish = ParkedWish(name: name, price: price)
        data.parked.insert(wish, at: 0)
        save()
        Reminders.scheduleWish(wish)
        award(.wishParked)
    }

    func decide(_ id: UUID, _ decision: ParkedWish.Decision) {
        guard let i = data.parked.firstIndex(where: { $0.id == id }) else { return }
        guard data.parked[i].decision == nil else { return }
        data.parked[i].decision = decision
        data.parked[i].decidedAt = Date()
        if decision == .keep, let price = data.parked[i].price, price > 0, budgetMonthly > 0 {
            data.spends.append(Spend(title: data.parked[i].name, amount: price))
        }
        save()
        Reminders.cancelWish(id)
        award(decision == .drop ? XPKind.wishDropped : XPKind.wishKept)
    }

    func removeWish(_ id: UUID) {
        data.parked.removeAll { $0.id == id }
        save()
        Reminders.cancelWish(id)
    }

    var droppedWishes: [ParkedWish] { data.parked.filter { $0.decision == .drop } }
    var savedMoney: Double { droppedWishes.compactMap(\.price).reduce(0, +) }

    // MARK: Game

    var level: Int { Level.level(for: data.game.xp) }
    var theme: Theme { Theme.named(data.game.theme) }

    struct QuestStatus: Identifiable {
        let quest: Quest
        let progress: Int
        let done: Bool
        var id: String { quest.key }
    }

    var weekQuests: [QuestStatus] {
        let week = Quest.weekKey()
        let current = data.game.week == week
        return Quest.forWeek(week).map { q in
            let progress = current ? data.game.questProgress[q.key, default: 0] : 0
            return QuestStatus(quest: q, progress: min(progress, q.target),
                               done: current && data.game.questsClaimed.contains(q.key))
        }
    }

    /// Wie viele Tage diese Woche du Dopa benutzt hast – nur Info, kein Streak.
    var activeDaysThisWeek: Int {
        let cal = Calendar(identifier: .iso8601)
        let thisWeek = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return (0..<7).filter { offset in
            guard let day = cal.date(byAdding: .day, value: -offset, to: Date()) else { return false }
            let c = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: day)
            return c == thisWeek && data.game.activeDays.contains(Quest.dayKey(day))
        }.count
    }

    func setTheme(_ id: String) {
        guard Theme.named(id).level <= level else { return }
        data.game.theme = id
        save()
    }

    @discardableResult
    func award(_ kinds: XPKind...) -> Award? { award(kinds) }

    /// Punkte gutschreiben, Wochen-Quests weiterzählen, Level-Up erkennen.
    @discardableResult
    func award(_ kinds: [XPKind]) -> Award? {
        var total = kinds.reduce(0) { $0 + $1.amount }
        guard total > 0 else { return nil }
        dotCheer += 1
        ensureWeek()

        // Variable Belohnung: selten ein Glückstreffer – hält das Ganze frisch
        let lucky = kinds.contains { $0.canBeLucky } && Double.random(in: 0..<1) < 0.08
        if lucky { total += 25 }

        let before = level
        let reason = kinds.map(\.reason).joined(separator: " + ") + (lucky ? " + Glückstreffer" : "")
        data.game.xp += total
        ensureMonth()
        data.game.monthXP += total
        data.game.log.insert(XPEvent(date: Date(), amount: total, reason: reason), at: 0)

        for kind in kinds {
            if let q = kind.quest { data.game.questProgress[q.key, default: 0] += q.amount }
        }
        var finished: Quest?
        for q in Quest.forWeek(data.game.week) where !data.game.questsClaimed.contains(q.key)
            && data.game.questProgress[q.key, default: 0] >= q.target {
            data.game.questsClaimed.append(q.key)
            data.game.xp += Quest.reward
            data.game.monthXP += Quest.reward
            data.game.log.insert(XPEvent(date: Date(), amount: Quest.reward, reason: "Wochen-Quest: \(q.title)"), at: 0)
            finished = q
        }
        if data.game.log.count > 60 { data.game.log.removeLast(data.game.log.count - 60) }

        let today = Quest.dayKey()
        if !data.game.activeDays.contains(today) {
            data.game.activeDays.append(today)
            if data.game.activeDays.count > 30 { data.game.activeDays.removeFirst() }
        }

        let after = level
        let result = Award(amount: total + (finished == nil ? 0 : Quest.reward), reason: reason, lucky: lucky,
                           newLevel: after > before ? after : nil, quest: finished?.title)
        lastAward = result
        save()
        return result
    }

    /// Rückgängig (z. B. Häkchen wieder weg) – Punkte und Quest-Fortschritt zurück, ohne Anzeige.
    private func revoke(_ kind: XPKind) {
        ensureWeek()
        ensureMonth()
        data.game.xp = max(0, data.game.xp - kind.amount)
        data.game.monthXP = max(0, data.game.monthXP - kind.amount)
        if let q = kind.quest {
            data.game.questProgress[q.key] = max(0, data.game.questProgress[q.key, default: 0] - q.amount)
        }
        save()
    }

    private func ensureMonth() {
        let month = Self.monthKey()
        guard data.game.month != month else { return }
        data.game.month = month
        data.game.monthXP = 0
    }

    static func monthKey(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    // MARK: Spaß-Budget

    var monthXP: Int { data.game.month == Self.monthKey() ? data.game.monthXP : 0 }

    /// Monatsbudget: fest eingestellt oder ein Anteil von dem, was laut Geld-Überblick frei ist.
    var budgetMonthly: Double {
        let b = data.budget
        guard b.linked else { return b.monthly }
        let month = moneyMonth
        return month.income > 0 ? MoneyMath.linkedBudget(free: month.free, share: b.share) : b.monthly
    }

    /// Gekoppelt, aber nach Fixkosten und Raten bleibt nichts übrig.
    var budgetSqueezed: Bool { data.budget.linked && moneyMonth.income > 0 && budgetMonthly <= 0 }

    /// Freigespielt: Monatsbudget × Anteil der Ziel-XP (gedeckelt bei 100 %).
    var budgetUnlocked: Double {
        let monthly = budgetMonthly
        guard monthly > 0 else { return 0 }
        return monthly * min(1, Double(monthXP) / Double(max(1, data.budget.targetXP)))
    }

    /// Spaß-Ausgaben dieses Monats – nur die zählen fürs Spaß-Budget.
    var spendsThisMonth: [Spend] {
        let month = Self.monthKey()
        return data.spends.filter { Self.monthKey($0.date) == month && $0.kind == .fun && !$0.income }
            .sorted { $0.date > $1.date }
    }

    var budgetSpent: Double { spendsThisMonth.reduce(0) { $0 + $1.amount } }
    var budgetLeft: Double { max(0, budgetUnlocked - budgetSpent) }

    func updateBudget(_ settings: BudgetSettings) {
        data.budget = settings
        save()
    }

    func addSpend(_ title: String, amount: Double) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard amount > 0 else { return }
        data.spends.append(Spend(title: title.isEmpty ? "Ausgabe" : title, amount: amount, kind: .fun))
        save()
    }

    // MARK: Geld-Tagebuch

    /// „4,50 Döner“ / „+20 Oma“ – ein Feld, kein Formular. false = kein Betrag erkannt.
    @discardableResult
    func addEntry(_ text: String, kind: SpendKind? = nil) -> Bool {
        guard let parsed = MoneyMath.parseEntry(text) else { return false }
        let entry = Spend(title: parsed.title, amount: parsed.amount,
                          kind: kind ?? SpendKind.detect(parsed.title), income: parsed.income)
        data.spends.append(entry)
        if data.spends.count > 3000 { data.spends.removeFirst(data.spends.count - 3000) }
        save()
        award(.spendLogged)
        Toaster.shared.show(parsed.income
            ? "+\(MoneyMath.euro(parsed.amount)) \(parsed.title)"
            : "\(MoneyMath.euro(parsed.amount)) \(parsed.title) · \(entry.kind.label)")
        return true
    }

    // MARK: Geld: Screenshot und Tipps

    private static func scanDate(_ text: String) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var c = DateComponents()
        c.year = parts[0]; c.month = parts[1]; c.day = parts[2]; c.hour = 12
        return Calendar.current.date(from: c)
    }

    func scanDateLabel(_ text: String) -> String {
        Self.scanDate(text).map { DayLabel.text(for: $0) } ?? text
    }

    /// Steht so schon im Tagebuch? (gleicher Betrag, gleicher Tag, ähnlicher Name)
    func isKnownEntry(_ entry: Server.ScanEntry) -> Bool {
        guard let date = Self.scanDate(entry.date) else { return false }
        let title = entry.title.lowercased()
        return data.spends.contains { spend in
            abs(spend.amount - entry.amount) < 0.01 && spend.income == entry.income
                && Calendar.current.isDate(spend.date, inSameDayAs: date)
                && (spend.title.lowercased().contains(title) || title.contains(spend.title.lowercased()))
        }
    }

    /// Kurze Liste der letzten Einträge – damit Gemini „schon drin“ erkennt.
    func knownEntriesSummary() -> String {
        data.spends.suffix(30).map { "\($0.title) \(MoneyMath.euro($0.amount)) \(Quest.dayKey($0.date))" }
            .joined(separator: "; ")
    }

    /// Ausgewählte Buchungen ins Tagebuch, offene Raten in „Offene Zahlungen“.
    func importScan(entries: [Server.ScanEntry], debts: [Server.ScanDebt], balance: Double? = nil, account: String = "") {
        if let balance {
            data.bank = BankBalance(amount: balance, account: account)
        }
        for e in entries {
            data.spends.append(Spend(title: e.title, amount: e.amount, date: Self.scanDate(e.date) ?? Date(),
                                     kind: SpendKind.detect(e.title), income: e.income))
        }
        for d in debts {
            data.money.append(MoneyItem(title: d.title, amount: d.amount, kind: .debt,
                                        due: Self.scanDate(d.due) ?? Date(), remaining: max(1, d.remaining), remind: true))
        }
        save()
        rescheduleReminders()
        if !entries.isEmpty { award(.spendLogged) }
        let parts = [balance == nil ? nil : "Kontostand",
                     entries.isEmpty ? nil : "\(entries.count) Buchungen", debts.isEmpty ? nil : "\(debts.count) Raten"].compactMap { $0 }
        Toaster.shared.show(parts.joined(separator: " und ") + " übernommen")
    }

    /// Kompakte Monatsübersicht für die Tipps (nur Summen und häufige Posten, keine Kontodaten).
    func moneySummaryForTips() -> String {
        let month = moneyMonth
        let entries = entriesThisMonth.filter { !$0.income }
        var lines = [
            "Monat bis heute: Rein \(MoneyMath.euro(month.income + month.extra)), fest \(MoneyMath.euro(month.fixed)), Raten \(MoneyMath.euro(month.debts)), Ausgaben \(MoneyMath.euro(month.spent)) in \(entries.count) Einträgen, noch frei \(MoneyMath.euro(month.left)).",
        ]
        let kinds = MoneyMath.byKind(entries).map { k in
            "\(k.kind.label) \(MoneyMath.euro(k.amount)) (\(entries.filter { $0.kind == k.kind }.count)×)"
        }
        if !kinds.isEmpty { lines.append("Nach Art: " + kinds.joined(separator: ", ")) }
        let top = Dictionary(grouping: entries) { $0.title.lowercased() }
            .map { (title: $0.value[0].title, count: $0.value.count, sum: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.sum > $1.sum }
            .prefix(6)
            .map { "\($0.title) \($0.count)× (\(MoneyMath.euro($0.sum)))" }
        if !top.isEmpty { lines.append("Größte Posten: " + top.joined(separator: ", ")) }
        let debts = self.debts.map { "\($0.title) \(MoneyMath.euro($0.amount)) noch \($0.remaining)×" }
        if !debts.isEmpty { lines.append("Offene Raten: " + debts.joined(separator: ", ")) }
        if budgetMonthly > 0 {
            lines.append("Spaß-Budget: \(MoneyMath.euro(budgetUnlocked)) freigespielt, \(MoneyMath.euro(budgetSpent)) ausgegeben.")
        }
        return lines.joined(separator: "\n")
    }

    func setSpendKind(_ id: UUID, _ kind: SpendKind) {
        guard let i = data.spends.firstIndex(where: { $0.id == id }) else { return }
        data.spends[i].kind = kind
        save()
    }

    var entriesThisMonth: [Spend] {
        let month = Self.monthKey()
        return data.spends.filter { Self.monthKey($0.date) == month }.sorted { $0.date > $1.date }
    }

    var spentToday: Double {
        data.spends.filter { !$0.income && Calendar.current.isDateInToday($0.date) }.reduce(0) { $0 + $1.amount }
    }

    /// Was du oft einträgst – als Ein-Tipp-Knöpfe („Döner 4,50 €“).
    var frequentEntries: [Spend] {
        let since = Date().addingTimeInterval(-60 * 86_400)
        let recent = data.spends.filter { $0.date > since && !$0.income && !$0.title.hasPrefix("Einkauf") }
        return Dictionary(grouping: recent) { "\($0.title.lowercased())|\($0.amount)" }
            .filter { $0.value.count >= 2 }
            .sorted { $0.value.count > $1.value.count }
            .prefix(6)
            .compactMap { $0.value.last }
    }

    /// Nochmal dasselbe wie damals (Ein-Tipp-Knopf).
    func repeatEntry(_ entry: Spend) {
        data.spends.append(Spend(title: entry.title, amount: entry.amount, kind: entry.kind))
        save()
        award(.spendLogged)
        Toaster.shared.show("\(MoneyMath.euro(entry.amount)) \(entry.title)")
    }

    func deleteSpend(_ id: UUID) {
        data.spends.removeAll { $0.id == id }
        save()
    }

    // MARK: Eigene Erinnerungen

    func saveReminder(_ reminder: CustomReminder) {
        var r = data.reminders
        if let i = r.custom.firstIndex(where: { $0.id == reminder.id }) {
            r.custom[i] = reminder
        } else {
            r.custom.append(reminder)
        }
        r.custom.sort { $0.minutes < $1.minutes }
        updateReminders(r)
    }

    func deleteReminder(_ id: UUID) {
        var r = data.reminders
        r.custom.removeAll { $0.id == id }
        updateReminders(r)
    }

    func isAcked(_ id: UUID, on date: Date = Date()) -> Bool {
        data.reminderAcks[id.uuidString] == Quest.dayKey(date)
    }

    /// „Erledigt“ – stoppt die Wiederholungen für heute und landet als Erledigt in „Merken“.
    func ackReminder(_ id: UUID) {
        guard let reminder = data.reminders.custom.first(where: { $0.id == id }) else { return }
        data.reminderAcks[id.uuidString] = Quest.dayKey()
        save()
        Reminders.cancelFollowUps(for: id)
        addMemo(reminder.title, kind: .done)
    }

    func unackReminder(_ id: UUID) {
        data.reminderAcks[id.uuidString] = nil
        save()
        rescheduleReminders()
    }

    // MARK: Tagesbegleiter

    private var dayRefreshTask: Task<Void, Never>?
    private var lastCompanionAttempt = Date.distantPast

    /// Nach Änderungen (kurz gebündelt): Widget-Tag neu schreiben, Morgen/Abend-Texte nachziehen.
    private func scheduleDayRefresh() {
        dayRefreshTask?.cancel()
        dayRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.writeWidgetDay()
            await Reminders.replaceCompanion(self.companionNotes())
        }
    }

    func theOne(on day: Date = Date()) -> TaskItem? {
        guard let id = data.theOne[Quest.dayKey(day)] else { return nil }
        return data.tasks.first { $0.id == id }
    }

    /// Abends gefragt = für morgen; nach Mitternacht noch derselbe Abend → der heutige Kalendertag.
    var reviewTargetDay: Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return cal.component(.hour, from: Date()) < Evening.dayStartHour ? today
            : cal.date(byAdding: .day, value: 1, to: today) ?? today
    }

    /// „Das Eine“ für einen Tag – vorhandene Aufgabe gleichen Namens oder eine neue.
    func setTheOne(_ text: String, for day: Date) {
        let title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        let isToday = cal.isDateInToday(day)
        if let i = data.tasks.firstIndex(where: { $0.doneAt == nil && $0.title.caseInsensitiveCompare(title) == .orderedSame }) {
            if !isToday { data.tasks[i].dueDay = start }
            data.theOne[Quest.dayKey(day)] = data.tasks[i].id
        } else {
            let task = TaskItem(title: title, firstStep: Smart.firstStep(for: title), dueDay: isToday ? nil : start)
            data.tasks.insert(task, at: 0)
            data.theOne[Quest.dayKey(day)] = task.id
        }
        let cutoff = Quest.dayKey(Date().addingTimeInterval(-30 * 86_400))
        data.theOne = data.theOne.filter { $0.key >= cutoff }
        save()
        Toaster.shared.show(isToday ? "Das Eine für heute steht" : "Das Eine für morgen steht")
    }

    /// Eine vorhandene Aufgabe zum Einen für heute machen.
    func makeTheOne(_ id: UUID) {
        guard let i = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        data.tasks[i].dueDay = nil
        data.theOne[Quest.dayKey()] = id
        save()
        Toaster.shared.show("Das Eine für heute")
    }

    func phase(at date: Date = Date()) -> DayPhase {
        let e = evening
        let start = ((e.bedTonight - e.totalMinutes) % 1440 + 1440) % 1440
        return DayPhase.at(ClockTime.minutes(of: date), eveningStart: start, bed: e.bedTonight)
    }

    private var todayScript: CompanionScript? { data.companion?.day == Quest.dayKey() ? data.companion : nil }

    /// Was Dot gerade sagt: heute von Gemini geschrieben, sonst eingebaut.
    func dotLine(_ phase: DayPhase, at date: Date = Date()) -> String {
        let line = todayScript?.line(for: phase, minutes: ClockTime.minutes(of: date)) ?? ""
        return line.isEmpty ? CompanionText.line(phase, day: Quest.dayKey(date)) : line
    }

    var mealsToday: Int {
        data.memos.filter { $0.kind == .done && $0.text == "Gegessen" && Calendar.current.isDateInToday($0.createdAt) }.count
    }

    /// „3 erledigt · 40 Min Fokus · 2× gegessen“ – leer, wenn noch nichts war (kein „0 erledigt“).
    var reviewLine: String {
        var parts: [String] = []
        let done = doneToday.count
        if done > 0 { parts.append("\(done) erledigt") }
        if focusMinutesToday > 0 { parts.append("\(focusMinutesToday) Min Fokus") }
        if mealsToday > 0 { parts.append("\(mealsToday)× gegessen") }
        let habitsDone = data.habits.filter { habitCount($0.id) >= $0.perDay }.count
        if habitsDone > 0 { parts.append("\(habitsDone) \(habitsDone == 1 ? "Gewohnheit" : "Gewohnheiten")") }
        return parts.joined(separator: " · ")
    }

    /// Fakten für den Morgen: Termine mit Losgeh-Zeit, das Eine, Tabletten.
    func briefingFacts(for day: Date) -> [String] {
        var facts: [String] = []
        let cal = data.calendar
        if cal.on {
            for e in Agenda.shared.events(on: day, hidden: cal.hidden).filter({ !$0.allDay }).prefix(3) {
                var line = "\(ClockTime.string(ClockTime.minutes(of: e.start))) \(e.title)"
                if cal.leaveOn && !e.location.isEmpty && e.lead(cal) > 0 {
                    line += " (los \(ClockTime.string(ClockTime.minutes(of: e.leaveAt(cal)))))"
                }
                facts.append(line)
            }
        }
        if let one = theOne(on: day), one.doneAt == nil { facts.append("Das Eine: \(one.title)") }
        let today = Calendar.current.isDateInToday(day)
        for h in data.habits where h.isMed && !(today && habitCount(h.id) >= h.perDay) {
            facts.append(h.remindAt.map { "\(h.title) um \(ClockTime.string($0))" } ?? h.title)
        }
        return facts
    }

    /// Morgen-Überblick und Tagesrückblick für die nächsten sieben Tage.
    func companionNotes() -> [Reminders.CompanionNote] {
        let r = data.reminders
        guard r.briefingOn || r.reviewOn else { return [] }
        let cal = Calendar.current
        let now = Date()
        let startOfToday = cal.startOfDay(for: now)
        var notes: [Reminders.CompanionNote] = []
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: startOfToday) else { continue }
            let key = Quest.dayKey(day)
            let isToday = offset == 0
            if r.briefingOn {
                let routineDay = data.morning.isScheduled(on: day)     // pausiert = freier Tag
                let m = isToday ? morning : data.morning
                let at = routineDay ? (isToday ? m.wakeToday : m.wakeAt) : r.freeDayBriefingAt
                let fire = ClockTime.date(at, on: day)
                if fire > now {
                    let line = isToday ? dotLine(.morning) : CompanionText.line(.morning, day: key)
                    let title = routineDay && !m.untimed
                        ? "Guten Morgen · los um \(ClockTime.string(isToday ? m.leaveToday : m.leaveAt))"
                        : "Guten Morgen"
                    notes.append(.init(id: "cmp-brief-\(key)", date: fire, title: title,
                                       body: ([line] + briefingFacts(for: day)).joined(separator: "\n"),
                                       category: Reminders.Category.morning, route: routineDay ? "morgen" : "jetzt"))
                }
            }
            if r.reviewOn {
                let e = isToday ? evening : data.evening
                let bed = isToday ? e.bedTonight : e.bedAt
                let start = ((bed - e.totalMinutes) % 1440 + 1440) % 1440
                let at = start >= 18 * 60 + 30 ? start - 30 : 21 * 60
                let fire = ClockTime.date(at, on: day)
                if fire > now {
                    let stats = isToday ? reviewLine : ""
                    let line = isToday ? dotLine(.evening) : CompanionText.line(.evening, day: key)
                    let body = (stats.isEmpty ? "" : "Heute: \(stats).\n") + line + "\nGedrückt halten: Was ist morgen das Eine?"
                    notes.append(.init(id: "cmp-review-\(key)", date: fire, title: "Tagesrückblick",
                                       body: body, category: Reminders.Category.review, route: "jetzt"))
                }
            }
        }
        return notes
    }

    /// Einmal am Tag schreibt Dot seine Sätze neu (Gemini) – gegen das Abnutzen.
    func refreshCompanionIfNeeded() async {
        let today = Quest.dayKey()
        guard data.companion?.day != today, Server.shared.isConnected, Server.shared.aiAvailable,
              Calendar.current.component(.hour, from: Date()) >= 4,
              Date().timeIntervalSince(lastCompanionAttempt) > 1800 else { return }
        lastCompanionAttempt = Date()
        guard var script = try? await Server.shared.companionDay(name: dotName, level: level, context: companionContext()) else { return }
        script.day = today
        data.companion = script
        save()
        rescheduleReminders()
    }

    private func companionContext() -> [String] {
        var lines: [String] = []
        let facts = briefingFacts(for: Date())
        if !facts.isEmpty { lines.append("Heute fest: " + facts.joined(separator: "; ")) }
        let open = todayTasks.prefix(8).map(\.title)
        if !open.isEmpty { lines.append("Offene Aufgaben: " + open.joined(separator: "; ")) }
        if let last = data.checkins.last {
            let energy = ["low": "wenig", "med": "mittel", "high": "viel"][last.energy] ?? last.energy
            lines.append("Letzter Check-in (\(last.day)): Stimmung \(last.mood)/5, Energie \(energy)")
        }
        if let sleepLine { lines.append(sleepLine) }
        let habits = data.habits.map(\.title)
        if !habits.isEmpty { lines.append("Gewohnheiten: " + habits.joined(separator: ", ")) }
        lines.append(data.morning.isScheduled(on: Date()) ? "Heute ist ein Tag mit Morgen-Checkliste (früh los)." : "Heute ohne festen Morgen.")
        return lines
    }

    /// Heutige Fixpunkte (Erinnerungen, Termine, Losgehen, Abendroutine, Gewohnheiten) nach Uhrzeit.
    func todayAnchors() -> [Anchor] {
        let now = Date()
        let cal = Calendar.current
        var anchors: [Anchor] = []
        for r in data.reminders.custom where r.isDue(on: now) && !isAcked(r.id) {
            anchors.append(Anchor(time: ClockTime.date(r.minutes), title: r.title))
        }
        for t in data.tasks where t.doneAt == nil {
            if let at = t.remindAt, Calendar.current.isDate(at, inSameDayAs: now) {
                anchors.append(Anchor(time: at, title: t.title))
            }
        }
        if data.calendar.on {
            for e in Agenda.shared.events(on: now, hidden: data.calendar.hidden) where !e.allDay {
                anchors.append(Anchor(time: e.start, title: e.title))
            }
        }
        let m = morning
        if m.days.contains(cal.component(.weekday, from: now)) && !m.isDone && !m.untimed {
            anchors.append(Anchor(time: ClockTime.date(m.leaveToday), title: "Losgehen"))
        }
        let e = evening
        if !e.isDone {
            anchors.append(Anchor(time: e.bedDate().addingTimeInterval(-Double(e.totalMinutes) * 60), title: "Abendroutine"))
        }
        for h in data.habits {
            if let at = h.remindAt, habitCount(h.id) < h.perDay {
                anchors.append(Anchor(time: ClockTime.date(at), title: h.title))
            }
        }
        return anchors.sorted { $0.time < $1.time }
    }

    /// Was das Dot-Widget zeigt: nächste Fixpunkte, Dots Sätze, das Eine.
    func writeWidgetDay() {
        let now = Date()
        let e = evening
        var lines: [String: String] = [:]
        for phase in DayPhase.allCases { lines[phase.rawValue] = dotLine(phase, at: now) }
        lines["afternoon"] = dotLine(.day, at: ClockTime.date(16 * 60))
        let start = ((e.bedTonight - e.totalMinutes) % 1440 + 1440) % 1440
        let one = theOne().flatMap { $0.doneAt == nil ? $0.title : nil }
        let day = WidgetDay(day: Quest.dayKey(), dotName: dotName, level: level,
                            anchors: todayAnchors(), lines: lines,
                            eveningStart: start, bed: e.bedTonight, theOne: one)
        if let raw = try? JSONEncoder().encode(day) {
            Shared.defaults?.set(raw, forKey: WidgetDay.key)
            WidgetCenter.shared.reloadTimelines(ofKind: "DotWidget")
        }
    }

    // MARK: Abendroutine

    /// Häkchen gelten für den laufenden Abend (bis 5 Uhr früh).
    var evening: Evening { data.evening.forTonight() }

    func toggleEveningStep(_ id: UUID) {
        var e = evening
        e.night = Evening.nightKey()
        if e.startedAt == nil { e.startedAt = Date() }
        let checking = !e.checked.contains(id)
        if checking {
            e.checked.append(id)
        } else {
            e.checked.removeAll { $0 == id }
        }
        data.evening = e
        save()
        if checking && e.isDone && data.game.eveningAwardedDay != e.night {
            data.game.eveningAwardedDay = e.night
            award(.eveningStep, .eveningDone)
        } else if checking {
            award(.eveningStep)
        } else {
            revoke(.eveningStep)
        }
    }

    /// Heute Abend später/früher ins Bett – oder ohne Uhr (-1). nil = zurück zum Plan.
    func setEveningBedTonight(_ minutes: Int?) {
        var e = evening
        e.night = Evening.nightKey()
        e.tonightBed = minutes
        data.evening = e
        save()
    }

    func resetEvening() {
        var e = data.evening
        e.night = ""
        e.startedAt = nil
        e.checked = []
        data.evening = e
        save()
    }

    func updateEveningPlan(steps: [RoutineStep], bedAt: Int, days: [Int]) {
        data.evening.steps = steps.filter { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty }
        data.evening.bedAt = bedAt
        data.evening.days = days
        save()
        rescheduleReminders()
    }

    // MARK: Gewohnheiten

    func habitCount(_ id: UUID, on day: Date = Date()) -> Int {
        data.habitTicks.filter { $0.habit == id && Calendar.current.isDate($0.date, inSameDayAs: day) }.count
    }

    /// Wann heute zuletzt abgehakt (für Tabletten: „um 8:12“).
    func lastTick(_ id: UUID) -> Date? {
        data.habitTicks.last { $0.habit == id && Calendar.current.isDateInToday($0.date) }?.date
    }

    /// Einmal abhaken. Aus der Benachrichtigung (`onlyIfOpen`) nicht über das Tagesziel hinaus.
    func tickHabit(_ id: UUID, onlyIfOpen: Bool = false) {
        guard let habit = data.habits.first(where: { $0.id == id }) else { return }
        let before = habitCount(id)
        if onlyIfOpen && before >= habit.perDay {
            Reminders.cancelHabitFollowUps(id)
            return
        }
        data.habitTicks.append(HabitTick(habit: id, date: Date()))
        save()
        if habit.isMed {
            // landet auch in „Merken“ – dann findet die Suche „Tabletten genommen?“ es
            addMemo("\(habit.title) genommen", kind: .done, xp: nil)
        }
        if before + 1 == habit.perDay {
            Reminders.cancelHabitFollowUps(id)
            award(.habitTick, .habitDone)
        } else {
            award(.habitTick)
        }
    }

    func untickHabit(_ id: UUID) {
        guard let i = data.habitTicks.lastIndex(where: { $0.habit == id && Calendar.current.isDateInToday($0.date) }) else { return }
        let before = habitCount(id)
        data.habitTicks.remove(at: i)
        save()
        revoke(.habitTick)
        if let habit = data.habits.first(where: { $0.id == id }), before == habit.perDay {
            revoke(.habitDone)
            rescheduleReminders()
        }
    }

    func saveHabit(_ habit: Habit) {
        if let i = data.habits.firstIndex(where: { $0.id == habit.id }) {
            data.habits[i] = habit
        } else {
            data.habits.append(habit)
        }
        save()
        rescheduleReminders()
    }

    func deleteHabit(_ id: UUID) {
        data.habits.removeAll { $0.id == id }
        data.habitTicks.removeAll { $0.habit == id }
        save()
        rescheduleReminders()
    }

    func reorderHabit(_ moving: UUID, to target: UUID) {
        guard moving != target,
              let from = data.habits.firstIndex(where: { $0.id == moving }),
              let to = data.habits.firstIndex(where: { $0.id == target }) else { return }
        data.habits.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        save()
    }

    func moveHabits(from source: IndexSet, to destination: Int) {
        data.habits.move(fromOffsets: source, toOffset: destination)
        save()
    }

    // MARK: Geld

    var moneyMonth: MoneyMath.Month { MoneyMath.month(data.money, payments: data.payments, entries: data.spends) }

    /// Offene Zahlungen, die nächste zuerst.
    var debts: [MoneyItem] {
        data.money.filter { $0.kind == .debt }
            .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
    }

    /// Fällig bis morgen oder schon überfällig – für die Zeitleiste.
    var debtsDueSoon: [MoneyItem] {
        debts.filter { item in item.due.map { MoneyMath.daysUntil($0) <= 1 } ?? false }
    }

    func saveMoney(_ item: MoneyItem) {
        if let i = data.money.firstIndex(where: { $0.id == item.id }) {
            data.money[i] = item
        } else {
            data.money.append(item)
        }
        save()
        rescheduleReminders()
    }

    func deleteMoney(_ id: UUID) {
        data.money.removeAll { $0.id == id }
        save()
        Reminders.cancelMoney(id)
        rescheduleReminders()
    }

    /// „Bezahlt“: Rate verbuchen, nächste Fälligkeit setzen oder ganz abhaken.
    func markPaid(_ id: UUID) {
        guard let i = data.money.firstIndex(where: { $0.id == id }), data.money[i].kind == .debt else { return }
        let item = data.money[i]
        data.payments.append(Payment(itemID: item.id, title: item.title, amount: item.amount))
        let next = MoneyMath.afterPayment(item)
        if let next {
            data.money[i] = next
        } else {
            data.money.remove(at: i)
        }
        save()
        Reminders.cancelMoney(id)
        rescheduleReminders()
        award(.billPaid)
        Toaster.shared.show(next == nil ? "\(item.title) ist abbezahlt" : "Bezahlt – noch \(next?.remaining ?? 0)×")
    }

    // MARK: Kalender

    func updateCalendar(_ settings: CalendarSettings) {
        data.calendar = settings
        save()
        rescheduleReminders()
    }

    /// Eigene Vorlaufzeit für einen Termin (gilt auch für seine Wiederholungen).
    func setEventLead(_ eventID: String, minutes: Int?) {
        if let minutes {
            data.calendar.leads[eventID] = minutes
        } else {
            data.calendar.leads[eventID] = nil
        }
        save()
        rescheduleReminders()
    }

    /// „Bin schon los“ – keine weiteren Losgehen-Nachrichten für diesen Termin.
    func ackEvent(_ key: String) {
        data.reminderAcks["cal-\(key)"] = Quest.dayKey()
        save()
        Reminders.cancelEvent(key)
    }

    private func ensureWeek() {
        let week = Quest.weekKey()
        guard data.game.week != week else { return }
        data.game.week = week
        data.game.questProgress = [:]
        data.game.questsClaimed = []
    }

    // MARK: Feedback & Server

    var pendingFeedback: [FeedbackItem] { data.feedback.filter { !$0.sent } }

    func addFeedback(_ text: String, screen: String) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        data.feedback.append(FeedbackItem(text: text, screen: screen))
        save()
        Task { await syncFeedback() }
    }

    /// Schickt alles, was noch wartet. Ohne Verbindung/Internet passiert einfach nichts.
    func syncFeedback() async {
        let pending = pendingFeedback
        guard Server.shared.isConnected, !pending.isEmpty,
              let accepted = try? await Server.shared.sendFeedback(pending) else { return }
        // Auch abgelehnte (leere) gelten als erledigt, sonst hängen sie ewig in der Schlange
        let sentIDs = Set(pending.map(\.id.uuidString)).union(accepted)
        for i in data.feedback.indices where sentIDs.contains(data.feedback[i].id.uuidString) {
            data.feedback[i].sent = true
        }
        save()
    }

    /// Plan aus dem Smart Dump übernehmen – in der Reihenfolge des Plans oben in die Liste.
    func addPlan(_ tasks: [Server.PlanTask]) {
        for task in tasks.reversed() {
            let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            data.tasks.insert(TaskItem(title: title, firstStep: task.step), at: 0)
        }
        save()
    }

    // MARK: Dot & Check-in

    var dotName: String { data.game.dotName.isEmpty ? "Dot" : data.game.dotName }

    func renameDot(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        data.game.dotName = name.isEmpty ? "Dot" : String(name.prefix(20))
        save()
    }

    var todayCheckIn: CheckIn? { data.checkins.last { $0.day == Quest.dayKey() } }

    func checkIn(mood: Int, energy: String) {
        data.checkins.removeAll { $0.day == Quest.dayKey() }
        data.checkins.append(CheckIn(day: Quest.dayKey(), mood: mood, energy: energy))
        if data.checkins.count > 120 { data.checkins.removeFirst(data.checkins.count - 120) }
        save()
    }

    /// Dot passt die App an (Vorschlag „edit“). Findet er das Ding nicht, sagt er's und ändert nichts.
    private func applyEdit(_ a: DotAction) -> Bool {
        guard let edit = DotEdit(rawValue: a.key) else { return false }
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let missing: () -> Bool = {
            Toaster.shared.show("„\(a.title.isEmpty ? a.step : a.title)“ find ich nicht")
            return false
        }
        let open = openTasks
        let taskID: UUID? = DotChat.match(a.title, in: open.map(\.title)).map { open[$0].id }
        var s = data.reminders
        let m = data.morning
        let e = data.evening

        switch edit {
        case .morningLeave:
            guard let time = a.time else { return false }
            updateMorningPlan(steps: m.steps, leaveAt: time, days: m.days)
        case .morningDays:
            let days = DotEdit.weekdays(a.items)
            guard !days.isEmpty else { return false }
            updateMorningPlan(steps: m.steps, leaveAt: m.leaveAt, days: days)
        case .morningAdd:
            guard !a.step.isEmpty else { return false }
            updateMorningPlan(steps: m.steps + [RoutineStep(title: a.step, minutes: a.minutes > 0 ? a.minutes : 3)],
                              leaveAt: m.leaveAt, days: m.days)
        case .morningRemove:
            guard let i = DotChat.match(a.step.isEmpty ? a.title : a.step, in: m.steps.map(\.title)) else { return missing() }
            var steps = m.steps
            steps.remove(at: i)
            updateMorningPlan(steps: steps, leaveAt: m.leaveAt, days: m.days)
        case .eveningBed:
            guard let time = a.time else { return false }
            updateEveningPlan(steps: e.steps, bedAt: time, days: e.days)
        case .eveningDays:
            let days = DotEdit.weekdays(a.items)
            guard !days.isEmpty else { return false }
            updateEveningPlan(steps: e.steps, bedAt: e.bedAt, days: days)
        case .eveningAdd:
            guard !a.step.isEmpty else { return false }
            updateEveningPlan(steps: e.steps + [RoutineStep(title: a.step, minutes: a.minutes > 0 ? a.minutes : 3)],
                              bedAt: e.bedAt, days: e.days)
        case .eveningRemove:
            guard let i = DotChat.match(a.step.isEmpty ? a.title : a.step, in: e.steps.map(\.title)) else { return missing() }
            var steps = e.steps
            steps.remove(at: i)
            updateEveningPlan(steps: steps, bedAt: e.bedAt, days: e.days)
        case .mealTimes:
            let times: [Int] = a.items.compactMap { DotChat.parseTime($0) }
            guard !times.isEmpty else { return false }
            s.mealTimes = times.sorted()
            s.mealsOn = true
            updateReminders(s)
        case .nudgeWindow:
            let times: [Int] = a.items.compactMap { DotChat.parseTime($0) }
            guard times.count >= 2 else { return false }
            s.nudgeFrom = times[0]
            s.nudgeTo = times[1]
            if a.minutes > 0 { s.nudgeEvery = max(15, a.minutes) }
            s.nudgeOn = true
            updateReminders(s)
        case .reminderTime:
            guard let time = a.time else { return false }
            guard let i = DotChat.match(a.title, in: s.custom.map(\.title)) else { return missing() }
            var reminder = s.custom[i]
            reminder.minutes = time
            saveReminder(reminder)
        case .reminderDelete:
            guard let i = DotChat.match(a.title, in: s.custom.map(\.title)) else { return missing() }
            deleteReminder(s.custom[i].id)
        case .habitAdd:
            guard !a.step.isEmpty else { return false }
            saveHabit(Habit(title: a.step, symbol: "checkmark", perDay: a.minutes > 0 ? min(12, a.minutes) : 1,
                            remindAt: a.time))
        case .habitRemove:
            guard let i = DotChat.match(a.title, in: data.habits.map(\.title)) else { return missing() }
            deleteHabit(data.habits[i].id)
        case .habitTime:
            guard let i = DotChat.match(a.title, in: data.habits.map(\.title)) else { return missing() }
            var habit = data.habits[i]
            habit.remindAt = a.time
            saveHabit(habit)
        case .taskRename:
            guard let taskID else { return missing() }
            guard !a.step.isEmpty else { return false }
            renameTask(taskID, a.step)
        case .taskDelete:
            guard let taskID else { return missing() }
            deleteTask(taskID)
        case .taskPlan:
            guard let taskID else { return missing() }
            let plan: TaskPlan = a.day < 0 ? .someday : a.day == 0 ? .today : a.day == 1 ? .tomorrow
                : .date(cal.date(byAdding: .day, value: a.day, to: start) ?? start)
            setPlan(taskID, plan)
        case .taskTime:
            guard let taskID, let time = a.time else { return taskID == nil ? missing() : false }
            setTaskTime(taskID, DotChat.date(day: max(0, a.day), time: time, from: Date()))
        case .shopRemove:
            let items = data.shopItems.filter { $0.boughtAt == nil }
            guard let i = DotChat.match(a.title, in: items.map(\.name)) else { return missing() }
            removeShop(items[i].id)
        case .timerPresets:
            let numbers: [Int] = a.items.compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }.filter { (1...180).contains($0) }
            guard !numbers.isEmpty else { return false }
            s.timerPresets = Array(Set(numbers).sorted().prefix(4))
            updateReminders(s)
        case .snooze:
            guard a.minutes > 0 else { return false }
            s.snoozeMinutes = min(120, a.minutes)
            updateReminders(s)
        case .theme:
            let want = a.step.lowercased()
            guard let theme = Theme.all.first(where: { $0.name.lowercased() == want || $0.id == want }) else { return missing() }
            guard theme.level <= level else {
                Toaster.shared.show("\(theme.name) gibt's ab Level \(theme.level)")
                return false
            }
            setTheme(theme.id)
        case .dotName:
            guard !a.step.isEmpty else { return false }
            renameDot(a.step)
        case .memoDelete:
            guard let i = DotChat.match(a.title, in: data.memos.map(\.text)) else { return missing() }
            deleteMemo(data.memos[i].id)
        case .chatClear:
            // erst nach dem Abhaken leeren – sonst verschwindet der Knopf, während er noch gedrückt wird
            Task { @MainActor in self.clearDotChat() }
        case .shopClear:
            data.shopItems.removeAll { $0.boughtAt == nil }
            save()
        }
        return true
    }

    /// Dot stellt die App ein: Morgen/Abend pausieren (bis Tag X) oder wieder an, sonst Schalter an/aus.
    private func applySetting(_ a: DotAction) {
        guard let setting = DotSetting(rawValue: a.title) else { return }
        let on = a.step == "on"
        let cal = Calendar.current
        let days = a.day > 0 ? a.day : DotSetting.defaultPauseDays
        let until = cal.date(byAdding: .day, value: days, to: cal.startOfDay(for: Date()))
        var s = data.reminders
        switch setting {
        case .morning:
            data.morning.pausedUntil = on ? nil : until
            if on { s.morningOn = true }
        case .evening:
            data.evening.pausedUntil = on ? nil : until
            if on { s.eveningOn = true }
        case .nudges: s.nudgeOn = on
        case .meals: s.mealsOn = on
        case .briefing: s.briefingOn = on
        case .review: s.reviewOn = on
        case .countdown: s.countdownOn = on
        case .halfway: s.halfwayOn = on
        }
        updateReminders(s)          // speichert und plant alle Mitteilungen neu
    }

    // MARK: Prospekte

    /// Eingelesenen Prospekt speichern; abgelaufene fliegen bei der Gelegenheit raus.
    @discardableResult
    func addFlyer(_ scan: Server.FlyerScan) -> Flyer {
        let offers: [Offer] = scan.offers.map { Offer(name: $0.name, price: $0.price, unit: $0.unit, note: $0.note) }
        let validTo = Self.scanDate(scan.validTo)
        var flyers = Offers.active(data.flyers, now: Date())
        // weitere Seite desselben Prospekts (gleicher Laden, gleiches Ende, heute eingelesen) → zusammenlegen
        if let i = flyers.firstIndex(where: { f in
            !scan.store.isEmpty && f.store.lowercased() == scan.store.lowercased()
                && f.validTo == validTo && Calendar.current.isDateInToday(f.added)
        }) {
            flyers[i].offers = Offers.merge(offers, into: flyers[i].offers)
            data.flyers = flyers
            save()
            return flyers[i]
        }
        let flyer = Flyer(store: scan.store, validFrom: Self.scanDate(scan.validFrom), validTo: validTo, offers: offers)
        data.flyers = flyers + [flyer]
        save()
        return flyer
    }

    func deleteFlyer(_ id: UUID) {
        data.flyers.removeAll { $0.id == id }
        save()
    }

    /// Gültige Prospekte (ohne abgelaufene).
    var activeFlyers: [Flyer] { Offers.active(data.flyers, now: Date()) }

    // MARK: Orte

    func saveSpot(_ spot: Spot) {
        if let i = data.spots.firstIndex(where: { $0.id == spot.id }) {
            data.spots[i] = spot
        } else {
            data.spots.append(spot)
        }
        save()
        rescheduleReminders()
    }

    func deleteSpot(_ id: UUID) {
        data.spots.removeAll { $0.id == id }
        for i in data.tasks.indices where data.tasks[i].spotID == id { data.tasks[i].spotID = nil }
        save()
        rescheduleReminders()
    }

    /// Aufgabe an einen Ort hängen (nil = keiner) – meldet sich beim Ankommen.
    func setTaskSpot(_ taskID: UUID, _ spotID: UUID?) {
        updateTask(taskID) { $0.spotID = spotID }
        rescheduleReminders()
    }

    func spot(_ id: UUID?) -> Spot? {
        guard let id else { return nil }
        return data.spots.first { $0.id == id }
    }

    // MARK: Apple Watch (über Health)

    /// Schlaf und Schritte holen. Schritte haken Gewohnheiten mit Schrittziel ab (sobald die App offen ist).
    func refreshHealth() async {
        guard !CommandLine.arguments.contains("-uitest") else { return }
        let stepHabits = data.habits.filter { ($0.stepGoal ?? 0) > 0 }
        guard data.reminders.sleepOn || !stepHabits.isEmpty else { return }
        await Health.shared.refresh(all: data.reminders.sleepOn, steps: !stepHabits.isEmpty)
        guard let steps = Health.shared.stepsToday else { return }
        for habit in stepHabits where steps >= (habit.stepGoal ?? 0) && habitCount(habit.id) < habit.perDay {
            tickHabit(habit.id, onlyIfOpen: true)
            Toaster.shared.show("\(habit.title): \(steps) Schritte – abgehakt")
        }
    }

    /// Kurze Nacht laut Uhr → Tipps und Dot werden sanfter.
    var shortNight: Bool { data.reminders.sleepOn && Timing.shortNight(Health.shared.sleepLastNight) }

    /// Schlaf und Bewegung als eine Zeile für Dot – nur, wenn du „Schlaf & Bewegung“ eingeschaltet hast.
    private var sleepLine: String? {
        guard data.reminders.sleepOn else { return nil }
        return Health.shared.line
    }

    // MARK: Dot-Gespräch

    @Published private(set) var dotThinking = false
    /// Zählt hoch, wenn etwas geschafft wurde – jeder sichtbare Dot hüpft kurz.
    @Published private(set) var dotCheer = 0

    /// Foto der letzten Nachricht (nur im Speicher, für „Nochmal versuchen“).
    private var lastDotPhoto: String?

    /// `photo` = Base64-JPEG (Wochenplan, Packliste …) – Dot sieht es, gespeichert wird nur „mit Foto“.
    func sendToDot(_ text: String, photo: String? = nil) async {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty && photo != nil { text = "Schau dir das Foto an." }
        guard !text.isEmpty, !dotThinking else { return }
        data.dotChat.removeAll { $0.failed }
        data.dotChat.append(DotMessage(fromDot: false, text: String(text.prefix(1500)), hasPhoto: photo != nil))
        save()
        lastDotPhoto = photo
        await refreshHealth()           // frische Schritte/Schlaf, bevor Dot plant
        await askDot(text, photo: photo)
    }

    /// Nach „Ich komm nicht durch“: die letzte eigene Nachricht nochmal schicken (mit Foto, falls dabei).
    func retryDot() async {
        guard !dotThinking else { return }
        data.dotChat.removeAll { $0.failed }
        guard let last = data.dotChat.last, !last.fromDot else { save(); return }
        await askDot(last.text, photo: last.hasPhoto ? lastDotPhoto : nil)
    }

    func clearDotChat() {
        data.dotChat = []
        save()
    }

    private func askDot(_ message: String, photo: String? = nil) async {
        let earlier: [DotMessage] = Array(data.dotChat.dropLast())
        let history: [Server.ChatLine] = DotChat.history(earlier).map { Server.ChatLine(fromDot: $0.fromDot, text: $0.text) }
        dotThinking = true
        do {
            let reply = try await Server.shared.chat(message, history: history, context: dotContext(), name: dotName,
                                                     level: level, image: photo)
            let actions: [DotAction] = (reply.actions ?? []).compactMap { Self.dotAction($0) }
            let answer = reply.answer.isEmpty ? "Da fällt mir gerade nichts Gutes ein. Sag's nochmal anders?" : reply.answer
            data.dotChat.append(DotMessage(fromDot: true, text: answer, actions: actions, suggestions: reply.suggestions ?? []))
        } catch {
            data.dotChat.append(DotMessage(fromDot: true, text: "Ich komm gerade nicht durch – Netz oder Server hakt.", failed: true))
        }
        dotThinking = false
        data.dotChat = DotChat.trimmed(data.dotChat)
        save()
    }

    private static func dotAction(_ a: Server.ChatAction) -> DotAction? {
        guard let kind = DotAction.Kind(rawValue: a.kind), !a.title.isEmpty || kind == .edit else { return nil }
        let time: Int? = a.time.flatMap { DotChat.parseTime($0) }
        if kind == .reminder && time == nil { return nil }
        let items: [String] = (a.items ?? []).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if kind == .steps && items.isEmpty { return nil }
        let entries: [PlanEntry] = (a.entries ?? []).compactMap { e in
            guard let at = e.time.flatMap({ DotChat.parseTime($0) }), !e.title.isEmpty else { return nil }
            return PlanEntry(title: e.title, day: max(0, min(13, e.day ?? 0)), time: at, minutes: max(5, e.minutes ?? 60))
        }
        if kind == .schedule && entries.isEmpty { return nil }
        if kind == .setting && DotSetting(rawValue: a.title) == nil { return nil }
        if kind == .edit && DotEdit(rawValue: a.key ?? "") == nil { return nil }
        return DotAction(kind: kind, title: a.title, step: a.step ?? "", minutes: a.minutes ?? 10,
                         time: time, day: max(0, a.day ?? 0), items: items, entries: entries,
                         place: (a.place ?? "").trimmingCharacters(in: .whitespaces), key: a.key ?? "")
    }

    /// Vorschlag aus dem Gespräch anlegen – erst beim Antippen, nie von allein.
    func applyDotAction(message messageID: UUID, action actionID: UUID) {
        guard let mi = data.dotChat.firstIndex(where: { $0.id == messageID }),
              let ai = data.dotChat[mi].actions.firstIndex(where: { $0.id == actionID }) else { return }
        let a = data.dotChat[mi].actions[ai]
        guard !a.done else { return }
        if a.kind == .focus && data.focus != nil {
            Toaster.shared.show("Es läuft schon ein Timer")
            return
        }
        var target: TaskItem?
        if a.kind == .done || a.kind == .tomorrow || a.kind == .steps {
            let open = openTasks
            guard let i = DotChat.match(a.title, in: open.map(\.title)) else {
                Toaster.shared.show("Die Aufgabe find ich nicht mehr")
                return
            }
            target = open[i]
        }
        // „edit“ erst ausführen – klappt es nicht (Ding nicht gefunden), bleibt der Knopf offen
        if a.kind == .edit {
            guard applyEdit(a) else { return }
        }
        data.dotChat[mi].actions[ai].done = true
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        switch a.kind {
        case .task:
            var task = TaskItem(title: a.title, firstStep: a.step.isEmpty ? Smart.firstStep(for: a.title) : a.step)
            if a.day > 0 { task.dueDay = cal.date(byAdding: .day, value: a.day, to: start) }
            task.steps = DotChat.newSteps(a.items, existing: []).map { SubStep(title: $0, minutes: 5) }
            if let time = a.time {
                let at = DotChat.date(day: a.day, time: time, from: Date())
                if at > Date() { task.remindAt = at }       // Uhrzeit mit Erinnerung
            }
            if !a.place.isEmpty {
                // Ort: meldet sich beim Ankommen („erinner mich zhs …“)
                if let i = DotChat.matchSpot(a.place, in: data.spots.map(\.name)) {
                    task.spotID = data.spots[i].id
                } else {
                    Toaster.shared.show("Ort „\(a.place)“ gibt's noch nicht – Profil → Orte")
                }
            }
            data.tasks.insert(task, at: 0)
            save()
            if task.remindAt != nil || task.spotID != nil { rescheduleReminders() }
        case .setting:
            applySetting(a)
        case .edit:
            break                   // schon vor dem Abhaken angewendet (applyEdit)
        case .schedule:
            // alle Termine als einmalige Erinnerungen – stehen dann im Plan und kommen als Mitteilung
            var r = data.reminders
            for e in a.entries {
                let day = cal.date(byAdding: .day, value: e.day, to: start) ?? start
                r.custom.append(CustomReminder(title: e.title, minutes: e.time, onDate: day, detail: e.untilText))
            }
            r.custom.sort { $0.minutes < $1.minutes }
            updateReminders(r)
        case .steps:
            if let target, let i = data.tasks.firstIndex(where: { $0.id == target.id }) {
                let fresh = DotChat.newSteps(a.items, existing: data.tasks[i].steps.map(\.title))
                data.tasks[i].steps += fresh.map { SubStep(title: $0, minutes: 5) }
                save()
            }
        case .reminder:
            let time = a.time ?? 9 * 60
            let now = cal.component(.hour, from: Date()) * 60 + cal.component(.minute, from: Date())
            let offset = DotChat.reminderDay(time: time, day: a.day, nowMinutes: now)
            let day = cal.date(byAdding: .day, value: offset, to: start) ?? start
            saveReminder(CustomReminder(title: a.title, minutes: time, onDate: day, detail: a.step))
        case .shop:
            addShop(a.title)
        case .memo:
            addMemo(a.title, kind: nil)
        case .focus:
            let task = openTasks.first { $0.title.localizedCaseInsensitiveCompare(a.title) == .orderedSame }
            startFocus(taskID: task?.id, title: task?.title ?? a.title, step: a.step,
                       minutes: min(90, max(1, a.minutes)))
        case .done:
            if let target { setDone(target.id, true) }
        case .tomorrow:
            if let target { moveToTomorrow(target.id) }
            save()
        }
        dotCheer += 1
        Toaster.shared.show(a.doneLabel)
    }

    /// Was Dot über den Tag wissen darf – kompakt, damit auch kleine Modelle damit klarkommen.
    func dotContext() -> String {
        let cal = Calendar.current
        let now = Date()
        let clock = DateFormatter()
        clock.dateFormat = "HH:mm"
        let date = DateFormatter()
        date.dateFormat = "dd.MM."
        var lines: [String] = []

        if let c = todayCheckIn {
            let energy = ["low": "wenig", "med": "mittel", "high": "viel"][c.energy] ?? c.energy
            lines.append("Check-in heute: Stimmung \(c.mood)/5, Energie \(energy)")
        } else {
            lines.append("Heute noch kein Check-in.")
        }
        if let sleepLine { lines.append(sleepLine) }
        if let run = data.focus {
            lines.append("Läuft gerade: Timer für „\(run.title)“ bis \(clock.string(from: run.endsAt))")
        }
        let anchors = todayAnchors().filter { $0.time > now.addingTimeInterval(-30 * 60) }.prefix(8)
        if !anchors.isEmpty {
            lines.append("Heute noch angesetzt: " + anchors.map { "\(clock.string(from: $0.time)) \($0.title)" }.joined(separator: "; "))
        }
        if let tomorrow = cal.date(byAdding: .day, value: 1, to: now) {
            let facts = briefingFacts(for: tomorrow)
            if !facts.isEmpty { lines.append("Morgen fest: " + facts.joined(separator: "; ")) }
        }
        if let one = theOne(), one.doneAt == nil { lines.append("Das Eine heute: \(one.title)") }

        let done = doneToday.prefix(8).map(\.title)
        lines.append("Heute erledigt: " + (done.isEmpty ? "noch nichts" : done.joined(separator: "; "))
                     + ". Fokus heute: \(focusMinutesToday) Min.")

        // Morgen- und Abendzeiten: damit Dot Uhrzeiten passend legen kann
        for (offset, label) in [(0, "Heute"), (1, "Morgen")] {
            guard let day = cal.date(byAdding: .day, value: offset, to: now) else { continue }
            let m = data.morning.forToday(day)
            if m.isScheduled(on: day) && !m.untimed {
                lines.append("\(label): aufstehen ca. \(ClockTime.string(m.wakeToday)), los um \(ClockTime.string(m.leaveToday))"
                             + (offset == 0 && m.isDone ? " (Morgen schon geschafft)" : ""))
            } else if offset == 1 {
                lines.append("Morgen: kein fester Morgen (kein Losgehen geplant)")
            }
        }
        lines.append("Bettzeit heute: \(ClockTime.string(evening.bedTonight))")

        // Einstellungen, die Dot ändern kann (kind setting)
        let r = data.reminders
        let pauseText: (Date?) -> String = { until in
            guard let until, until > now else { return "an" }
            return "pausiert bis \(date.string(from: until))"
        }
        let state: [String] = [
            "morning (Morgen-Check): \(pauseText(data.morning.pausedUntil))",
            "evening (Abendroutine): \(pauseText(data.evening.pausedUntil))",
            "nudges (Stupser): \(r.nudgeOn ? "an" : "aus")",
            "meals (Essen): \(r.mealsOn ? "an" : "aus")",
            "briefing (Morgen-Überblick): \(r.briefingOn ? "an" : "aus")",
            "review (Tagesrückblick): \(r.reviewOn ? "an" : "aus")",
            "countdown (Losgeh-Countdown): \(r.countdownOn ? "an" : "aus")",
            "halfway (Timer-Halbzeit): \(r.halfwayOn ? "an" : "aus")",
        ]
        lines.append("Einstellungen: " + state.joined(separator: "; "))

        // Was Dot anpassen kann (kind edit) – mit aktuellen Werten
        let m = data.morning
        let e = data.evening
        lines.append("Morgen-Check: \(DotEdit.weekdayText(m.days)), los um \(ClockTime.string(m.leaveAt)), Schritte: "
                     + m.steps.map { "\($0.title) (\($0.minutes) Min)" }.joined(separator: ", "))
        lines.append("Abendroutine: \(DotEdit.weekdayText(e.days)), Bett um \(ClockTime.string(e.bedAt)), Schritte: "
                     + e.steps.map { "\($0.title) (\($0.minutes) Min)" }.joined(separator: ", "))
        lines.append("Essens-Erinnerung um " + r.mealTimes.map { ClockTime.string($0) }.joined(separator: ", ")
                     + "; Stupser \(ClockTime.string(r.nudgeFrom))–\(ClockTime.string(r.nudgeTo)) alle \(r.nudgeEvery) Min"
                     + "; Timer-Knöpfe \(r.timerPresets.map { String($0) }.joined(separator: ", ")) Min; „Später“ \(r.snoozeMinutes) Min")
        let habitList: [String] = data.habits.map { h in h.title + (h.remindAt.map { " (\(ClockTime.string($0)))" } ?? "") }
        if !habitList.isEmpty { lines.append("Gewohnheiten: " + habitList.joined(separator: ", ")) }
        let customs: [String] = r.custom.prefix(15).map { "\($0.title) um \(ClockTime.string($0.minutes))" }
        if !customs.isEmpty { lines.append("Eigene Erinnerungen: " + customs.joined(separator: ", ")) }
        let colors: [String] = Theme.all.filter { $0.level <= level }.map(\.name)
        lines.append("Farbe gerade: \(theme.name) (frei: \(colors.joined(separator: ", "))); Dots Name: \(dotName)")
        lines.append(data.spots.isEmpty ? "Noch keine Orte angelegt (Profil → Orte)."
                     : "Deine Orte: " + data.spots.map(\.name).joined(separator: ", "))

        // Aufgaben mit ihren Schritten (✓ = erledigt), damit Dot Schritte ergänzen kann statt doppelt
        let today: [String] = todayTasks.prefix(12).map { t in
            var s = t.title
            if let at = t.remindAt { s += " [um \(clock.string(from: at))]" }
            if let place = self.spot(t.spotID) { s += " [bei \(place.name)]" }
            if !t.steps.isEmpty {
                let steps: [String] = t.steps.prefix(10).map { ($0.done ? "✓ " : "") + $0.title }
                s += " (Schritte: " + steps.joined(separator: ", ") + ")"
            } else if t.showStep && !t.firstStep.isEmpty {
                s += " (erster Schritt: \(t.firstStep))"
            }
            let age = cal.dateComponents([.day], from: t.createdAt, to: now).day ?? 0
            if age >= 3 { s += " – liegt seit \(age) Tagen" }
            return s
        }
        lines.append(today.isEmpty ? "Keine offenen Aufgaben für heute." : "Offene Aufgaben heute:\n- " + today.joined(separator: "\n- "))
        let later: [String] = upcomingTasks.prefix(6).map { t in
            var s = t.title + (t.dueDay.map { " (\(date.string(from: $0)))" } ?? "")
            if !t.steps.isEmpty { s += " (Schritte: " + t.steps.prefix(6).map(\.title).joined(separator: ", ") + ")" }
            return s
        }
        if !later.isEmpty { lines.append("Später geplant: " + later.joined(separator: "; ")) }
        if !somedayTasks.isEmpty { lines.append("Irgendwann-Liste: \(somedayTasks.count) Sachen") }

        let habits = data.habits.filter { habitCount($0.id) < $0.perDay }.map(\.title)
        if !habits.isEmpty { lines.append("Gewohnheiten heute noch offen: " + habits.joined(separator: ", ")) }

        let shop = shopOpen.prefix(20).map(\.name)
        if !shop.isEmpty { lines.append("Einkaufsliste: " + shop.joined(separator: ", ")) }
        // Angebote aus eingelesenen Prospekten (gekürzt)
        var deals: [String] = []
        for flyer in activeFlyers {
            for offer in flyer.offers.prefix(25) where deals.count < 40 {
                deals.append("\(flyer.storeName): \(offer.name)" + (offer.price > 0 ? " \(MoneyMath.euro(offer.price))" : ""))
            }
        }
        if !deals.isEmpty { lines.append("Angebote aus Prospekten: " + deals.joined(separator: "; ")) }

        let memos: [String] = data.memos.sorted { $0.createdAt > $1.createdAt }.prefix(15).compactMap { m in
            let text = m.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return "\(date.string(from: m.createdAt)) \(clock.string(from: m.createdAt)): \(String(text.prefix(140)))"
        }
        if !memos.isEmpty { lines.append("Letzte Notizen (neueste zuerst):\n- " + memos.joined(separator: "\n- ")) }
        return lines.joined(separator: "\n")
    }

    // MARK: Unterschritte

    func setSteps(_ taskID: UUID, _ steps: [SubStep]) {
        updateTask(taskID) { $0.steps = steps }
    }

    func toggleStep(_ taskID: UUID, _ stepID: UUID) {
        guard let t = data.tasks.firstIndex(where: { $0.id == taskID }),
              let s = data.tasks[t].steps.firstIndex(where: { $0.id == stepID }) else { return }
        data.tasks[t].steps[s].done.toggle()
        let nowDone = data.tasks[t].steps[s].done
        save()
        if nowDone { award(.morningStep) }   // kleiner Schritt = kleine Punkte
    }

    /// Smart-Dump-Ergebnis übernehmen. `picked` enthält die Kennungen der angehakten Einträge.
    func applyDump(_ dump: Server.Dump, picked: Set<String>) {
        let today = Calendar.current.startOfDay(for: Date())
        func day(_ offset: Int) -> Date? {
            offset < 0 ? nil : Calendar.current.date(byAdding: .day, value: offset, to: today)
        }
        var reminders = data.reminders

        // Zeitplan: Aufgabe für den Tag + einmalige Erinnerung zur Startzeit
        for (i, block) in dump.schedule.enumerated() where picked.contains(DumpKey.block(i)) {
            let date = day(block.day) ?? today
            data.tasks.insert(TaskItem(title: block.title, firstStep: block.step, dueDay: date), at: 0)
            if let minutes = ClockTime.parse(block.start) {
                reminders.custom.append(CustomReminder(title: block.title, minutes: minutes, onDate: date,
                                                       detail: "\(block.minutes) Min · \(block.step)"))
            }
        }
        for (i, task) in dump.tasks.enumerated().reversed() where picked.contains(DumpKey.task(i)) {
            data.tasks.insert(TaskItem(title: task.title, firstStep: task.step, dueDay: day(task.day)), at: 0)
        }
        for (i, r) in dump.reminders.enumerated() where picked.contains(DumpKey.reminder(i)) {
            if let minutes = ClockTime.parse(r.time) {
                reminders.custom.append(CustomReminder(title: r.title, minutes: minutes, onDate: day(r.day) ?? today))
            }
        }
        reminders.custom.sort { $0.minutes < $1.minutes }
        data.reminders = reminders
        save()

        let shopping = dump.shopping.enumerated().filter { picked.contains(DumpKey.shop($0.offset)) }.map { $0.element }
        if !shopping.isEmpty { addShop(shopping.joined(separator: ", ")) }
        for (i, note) in dump.notes.enumerated() where picked.contains(DumpKey.note(i)) {
            addMemo(note, kind: nil)
        }
        rescheduleReminders()
        Toaster.shared.show(dump.schedule.isEmpty ? "Übernommen" : "Plan steht – Erinnerungen sind gestellt")
    }

    private var lastBackup = Date.distantPast
    private var changedSinceBackup = true
    private var backupTask: Task<Void, Never>?

    /// Feedback #15: Jede Änderung landet von selbst auf dem Server – gebündelt 30 Sekunden
    /// nach der letzten Änderung, damit nicht jeder Haken eine Anfrage ist.
    private func scheduleBackup() {
        changedSinceBackup = true
        guard Server.shared.isConnected else { return }
        backupTask?.cancel()
        backupTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.backupNow()
        }
    }

    /// Sichern, wenn sich seit dem letzten Mal etwas geändert hat (oder `force`).
    func backupNow(force: Bool = false) async {
        guard Server.shared.isConnected, force || changedSinceBackup else { return }
        changedSinceBackup = false
        lastBackup = Date()
        do {
            try await Server.shared.uploadBackup(data)
        } catch {
            changedSinceBackup = true      // nächster Versuch beim nächsten Anlass
        }
    }

    /// Beim Verlassen der App: sofort sichern, was noch offen ist (höchstens einmal pro Minute).
    func backupIfDue() async {
        guard Date().timeIntervalSince(lastBackup) > 60 else { return }
        backupTask?.cancel()
        await backupNow()
    }

    /// Beim Öffnen: lange nichts gesichert (z. B. nach einer Neuinstallation)? Dann einmal komplett.
    func backupIfStale() async {
        let last = Server.shared.backupAt ?? .distantPast
        guard Date().timeIntervalSince(last) > 6 * 3600 else { return }
        await backupNow(force: true)
    }

    /// Fast leer (frisch installiert)? Dann lohnt sich das Server-Backup.
    var looksFresh: Bool {
        data.tasks.count + data.memos.count + data.shopItems.count + data.purchases.count < 3 && data.game.xp < 40
    }

    func restoreFromServer() async throws {
        let restored = try await Server.shared.downloadBackup()
        data = restored
        save()
        syncMemoWidget()
        rescheduleReminders()
    }

    // MARK: Backup

    /// Alles als JSON-Datei zum Teilen/Sichern (z. B. vor einer Neuinstallation).
    func exportBackup() -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let raw = try? encoder.encode(data) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Dopa-Backup-\(Quest.dayKey()).json")
        do {
            try raw.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    func importBackup(from url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let raw = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        data = try decoder.decode(AppData.self, from: raw)
        save()
        syncMemoWidget()
        rescheduleReminders()
    }

    // MARK: Fokus

    var focusMinutesToday: Int {
        data.focusLog
            .filter { Calendar.current.isDateInToday($0.day) }
            .reduce(0) { $0 + $1.minutes }
    }

    func startFocus(taskID: UUID?, title: String, step: String, minutes: Int) {
        clearFocusOutputs()
        let now = Date()
        let run = FocusRun(taskID: taskID, title: title, step: step,
                           startedAt: now, endsAt: now.addingTimeInterval(TimeInterval(minutes * 60)))
        data.focus = run
        if let taskID, let i = data.tasks.firstIndex(where: { $0.id == taskID }), !step.isEmpty {
            data.tasks[i].firstStep = step
        }
        save()
        publishFocus(run)
        award(.focusStarted)
    }

    func extendFocus(minutes: Int) {
        guard var run = data.focus else { return }
        run.endsAt = max(run.endsAt, Date()).addingTimeInterval(TimeInterval(minutes * 60))
        data.focus = run
        save()
        Notifier.cancelFocusEnd()       // Live Activity läuft weiter und wird nur verlängert
        publishFocus(run)
    }

    /// Beendet den laufenden Timer. `completed` hakt die zugehörige Aufgabe ab.
    func stopFocus(completed: Bool) {
        guard let run = data.focus else { return }
        let worked = min(Date().timeIntervalSince(run.startedAt), 3 * 3600)
        let minutes = Int((worked / 60).rounded())
        if minutes > 0 {
            data.focusLog.append(FocusLog(day: Date(), minutes: minutes))
        }
        var kinds: [XPKind] = minutes > 0 ? [.focusMinutes(minutes)] : []
        if completed, let id = run.taskID, let i = data.tasks.firstIndex(where: { $0.id == id }),
           data.tasks[i].doneAt == nil {
            data.tasks[i].doneAt = Date()
            kinds.append(.taskDone)
        }
        data.focus = nil
        save()
        clearFocusOutputs()
        award(kinds)
    }

    /// Widget-Countdown, Ablauf-Benachrichtigung, Live Activity (falls iOS sie zulässt).
    private func publishFocus(_ run: FocusRun) {
        let d = Shared.defaults
        d?.set(run.step.isEmpty ? run.title : run.step, forKey: Shared.focusStepKey)
        d?.set(run.startedAt, forKey: Shared.focusStartKey)
        d?.set(run.endsAt, forKey: Shared.focusEndKey)
        WidgetCenter.shared.reloadTimelines(ofKind: "FocusWidget")
        Notifier.scheduleFocusEnd(run, halfway: data.reminders.halfwayOn)
        LiveTimer.show(run)
    }

    private func clearFocusOutputs() {
        for key in [Shared.focusStepKey, Shared.focusStartKey, Shared.focusEndKey] {
            Shared.defaults?.removeObject(forKey: key)
        }
        WidgetCenter.shared.reloadTimelines(ofKind: "FocusWidget")
        Notifier.cancelFocusEnd()
        LiveTimer.endAll()
    }
}
