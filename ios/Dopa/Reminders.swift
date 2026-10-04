import CoreLocation
import Foundation
import UserNotifications

/// Der „Wecker von außen“: wiederkehrende lokale Benachrichtigungen.
/// Jede Uhrzeit ist ein eigener, sich täglich wiederholender Eintrag – läuft also weiter,
/// auch wenn die App tagelang zu bleibt. Die Texte werden bei jedem Öffnen neu ausgelost,
/// damit sie sich nicht abnutzen.
enum Reminders {
    private static let prefix = "rem-"

    enum Category {
        static let meal = "MEAL"
        static let nudge = "NUDGE"
        static let morning = "MORNING"
        static let park = "PARK"
        static let task = "TASK"
        static let habit = "HABIT"
        static let med = "MED"
        static let money = "MONEY"
        static let event = "EVENT"
        static let spend = "SPEND"
        static let review = "REVIEW"
        static let focus = "FOCUS"
        static let todo = "TODO"            // Aufgabe mit Uhrzeit
    }

    enum Action {
        static let mealEaten = "meal.eaten"
        static let mealSnooze = "meal.snooze"
        static let nudgeMemo = "nudge.memo"
        static let parkKeep = "park.keep"
        static let parkDrop = "park.drop"
        static let taskDone = "task.done"
        static let taskSnooze = "task.snooze"
        static let habitDone = "habit.done"
        static let habitSnooze = "habit.snooze"
        static let moneyPaid = "money.paid"
        static let eventGone = "event.gone"
        static let spendAdd = "spend.add"
        static let reviewOne = "review.one"
        static let focusDone = "focus.done"
        static let focusMore = "focus.more"
        static let todoDone = "todo.done"
        static let todoSnooze = "todo.snooze"
    }

    /// Eine Begleiter-Nachricht (Morgen-Überblick, Tagesrückblick) mit festem Text.
    struct CompanionNote {
        var id: String
        var date: Date
        var title: String
        var body: String
        var category: String
        var route: String
    }

    /// Alles, was zum Planen gebraucht wird – als Schnappschuss, damit es im Hintergrund laufen kann.
    struct Context {
        var settings: ReminderSettings
        var morning: Morning
        var evening: Evening
        var acks: [String: String]
        var habits: [Habit]
        var habitsDone: Set<UUID>
        var money: [MoneyItem]
        var events: [AgendaEvent]
        var calendar: CalendarSettings
        var companion: [CompanionNote] = []
        var script: CompanionScript?
        var tasks: [TaskItem] = []          // offene Aufgaben mit Uhrzeit
        var spots: [Spot] = []              // Orte
        var spotTasks: [TaskItem] = []      // offene Aufgaben mit Ort
        var shopCount = 0                   // offene Sachen auf der Einkaufsliste
    }

    /// Knöpfe in den Mitteilungen (auch auf der Uhr). Snooze- und „+ Min“-Zeiten kommen aus den Einstellungen.
    static func registerCategories(_ settings: ReminderSettings = ReminderSettings()) {
        let snooze = "In \(settings.snoozeMinutes) Min"
        let meal = UNNotificationCategory(
            identifier: Category.meal,
            actions: [
                UNNotificationAction(identifier: Action.mealEaten, title: "Gegessen ✔︎", options: []),
                UNNotificationAction(identifier: Action.mealSnooze, title: "In \(settings.mealSnooze) Min nochmal", options: []),
            ],
            intentIdentifiers: [])
        let nudge = UNNotificationCategory(
            identifier: Category.nudge,
            actions: [
                UNTextInputNotificationAction(identifier: Action.nudgeMemo, title: "Kurz was merken", options: [],
                                              textInputButtonTitle: "Merken",
                                              textInputPlaceholder: "Wo war ich, was wollte ich?"),
            ],
            intentIdentifiers: [])
        let morning = UNNotificationCategory(identifier: Category.morning, actions: [], intentIdentifiers: [])
        let park = UNNotificationCategory(
            identifier: Category.park,
            actions: [
                UNNotificationAction(identifier: Action.parkKeep, title: "Will ich noch", options: []),
                UNNotificationAction(identifier: Action.parkDrop, title: "Doch nicht", options: []),
            ],
            intentIdentifiers: [])
        let task = UNNotificationCategory(
            identifier: Category.task,
            actions: [
                UNNotificationAction(identifier: Action.taskDone, title: "Erledigt ✔︎", options: []),
                UNNotificationAction(identifier: Action.taskSnooze, title: snooze, options: []),
            ],
            intentIdentifiers: [])
        let habit = UNNotificationCategory(
            identifier: Category.habit,
            actions: [
                UNNotificationAction(identifier: Action.habitDone, title: "Erledigt ✔︎", options: []),
                UNNotificationAction(identifier: Action.habitSnooze, title: snooze, options: []),
            ],
            intentIdentifiers: [])
        let med = UNNotificationCategory(
            identifier: Category.med,
            actions: [
                UNNotificationAction(identifier: Action.habitDone, title: "Genommen ✔︎", options: []),
                UNNotificationAction(identifier: Action.habitSnooze, title: snooze, options: []),
            ],
            intentIdentifiers: [])
        let money = UNNotificationCategory(
            identifier: Category.money,
            actions: [UNNotificationAction(identifier: Action.moneyPaid, title: "Bezahlt ✔︎", options: [])],
            intentIdentifiers: [])
        let event = UNNotificationCategory(
            identifier: Category.event,
            actions: [UNNotificationAction(identifier: Action.eventGone, title: "Bin schon los", options: [])],
            intentIdentifiers: [])
        let spend = UNNotificationCategory(
            identifier: Category.spend,
            actions: [
                UNTextInputNotificationAction(identifier: Action.spendAdd, title: "Eintragen", options: [],
                                              textInputButtonTitle: "Eintragen",
                                              textInputPlaceholder: "z. B. 4,50 Döner, 12 Bahn"),
            ],
            intentIdentifiers: [])
        let review = UNNotificationCategory(
            identifier: Category.review,
            actions: [
                UNTextInputNotificationAction(identifier: Action.reviewOne, title: "Morgen das Eine", options: [],
                                              textInputButtonTitle: "Festlegen",
                                              textInputPlaceholder: "z. B. Bewerbung abschicken"),
            ],
            intentIdentifiers: [])
        // Timer zu Ende: direkt von der Uhr aus beenden oder verlängern
        let focus = UNNotificationCategory(
            identifier: Category.focus,
            actions: [
                UNNotificationAction(identifier: Action.focusDone, title: "Fertig ✔︎", options: []),
                UNNotificationAction(identifier: Action.focusMore, title: "+\(settings.extendMinutes) Min", options: []),
            ],
            intentIdentifiers: [])
        let todo = UNNotificationCategory(
            identifier: Category.todo,
            actions: [
                UNNotificationAction(identifier: Action.todoDone, title: "Erledigt ✔︎", options: []),
                UNNotificationAction(identifier: Action.todoSnooze, title: snooze, options: []),
            ],
            intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories(
            [meal, nudge, morning, park, task, habit, med, money, event, spend, review, focus, todo])
    }

    static func reschedule(_ ctx: Context) async {
        let settings = ctx.settings
        let morning = ctx.morning
        let acks = ctx.acks
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true else { return }

        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)

        var requests: [UNNotificationRequest] = []

        if settings.mealsOn {
            for (i, minutes) in settings.mealTimes.enumerated() {
                let body = ctx.script?.meals.randomElement() ?? Texts.meal.randomElement()!
                requests.append(daily("meal-\(i)", at: minutes, category: Category.meal,
                                      title: Texts.mealTitle(minutes), body: body))
            }
        }

        if settings.nudgeOn {
            // Fenster darf über Mitternacht gehen (z. B. 20:00–1:00)
            let end = settings.nudgeTo > settings.nudgeFrom ? settings.nudgeTo : settings.nudgeTo + 1440
            let every = max(15, settings.nudgeEvery)
            // Dots Tagestexte zuerst, dann die eingebauten – nie zweimal hintereinander gleich
            let pool = (ctx.script?.nudges ?? []) + Texts.nudge
            var shuffled = pool.shuffled()
            for (i, minutes) in stride(from: settings.nudgeFrom + every, through: end, by: every).enumerated().prefix(30) {
                if shuffled.isEmpty { shuffled = pool.shuffled() }
                let text = shuffled.removeLast().replacingOccurrences(of: "{zeit}", with: ClockTime.string(minutes))
                requests.append(daily("nudge-\(i)", at: minutes, category: Category.nudge,
                                      title: "Kurz hochschauen", body: text))
            }
        }

        if settings.morningOn && !settings.briefingOn {
            let wake = morning.wakeAt
            let body = "\(morning.steps.count) Schritte, \(morning.totalMinutes) Min – los um \(ClockTime.string(morning.leaveAt)). Tippen zum Starten."
            for weekday in morning.days {   // Standard Mo–Fr (Sonntag = 1)
                var components = DateComponents()
                components.weekday = weekday
                components.hour = (wake / 60 + 24) % 24
                components.minute = (wake % 60 + 60) % 60
                requests.append(request("morning-\(weekday)", components, category: Category.morning,
                                        title: Texts.morningTitle.randomElement()!, body: body,
                                        route: "morgen"))
            }
        }

        if settings.eveningOn {
            let e = ctx.evening
            for weekday in e.days {
                var components = DateComponents()
                components.weekday = weekday
                components.hour = e.startAt / 60
                components.minute = e.startAt % 60
                requests.append(request("evening-\(weekday)", components, category: Category.morning,
                                        title: Texts.eveningTitle.randomElement()!,
                                        body: "\(e.steps.count) Schritte, \(e.totalMinutes) Min – Bett um \(ClockTime.string(e.bedAt)). Tippen zum Starten.",
                                        route: "abend"))
            }
        }

        if settings.spendAskOn {
            requests.append(daily("spend-ask", at: settings.spendAskAt, category: Category.spend,
                                  title: "Heute was ausgegeben?",
                                  body: Texts.spendAsk.randomElement()!))
        }

        requests += ctx.companion.map(companionRequest)
        requests += morningCountdown(ctx)
        requests += todoRequests(ctx)
        requests += spotRequests(ctx)
        requests += habitRequests(ctx)
        requests += moneyRequests(ctx)
        requests += eventRequests(ctx)

        // Eigene Erinnerungen: täglich bzw. an den gewählten Wochentagen
        for reminder in settings.custom {
            let info: [String: String] = ["reminder": reminder.id.uuidString]
            let body = reminder.detail.isEmpty ? Texts.task.randomElement()! : reminder.detail
            if let onDate = reminder.onDate {
                // einmalig: genau dieser Tag und diese Uhrzeit
                let fire = ClockTime.date(reminder.minutes, on: onDate)
                if fire > Date() {
                    let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                    let content = UNMutableNotificationContent()
                    content.title = reminder.title
                    content.body = body
                    content.sound = .default
                    content.categoryIdentifier = Category.task
                    content.userInfo = info.merging(["route": "tag"]) { a, _ in a }
                    requests.append(UNNotificationRequest(
                        identifier: "\(prefix)once-\(reminder.id.uuidString)", content: content,
                        trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
                }
            }
            let days = reminder.onDate != nil ? [] : reminder.weekdays.isEmpty ? [0] : reminder.weekdays
            for day in days {
                var components = DateComponents()
                if day > 0 { components.weekday = day }
                components.hour = reminder.minutes / 60
                components.minute = reminder.minutes % 60
                requests.append(request("task-\(reminder.id.uuidString)-\(day)", components, category: Category.task,
                                        title: reminder.title, body: body,
                                        route: "tag", info: info))
            }
            // Dranbleiben: einmalige Nachfragen für heute und das nächste Mal – außer schon erledigt
            guard settings.persistOn else { continue }
            for occurrence in nextOccurrences(of: reminder) {
                let dayKey = Self.dayKey(occurrence)
                guard acks[reminder.id.uuidString] != dayKey else { continue }
                for (index, offset) in settings.followUps.sorted().enumerated() {
                    let fire = occurrence.addingTimeInterval(TimeInterval(offset * 60))
                    guard fire > Date() else { continue }
                    let content = UNMutableNotificationContent()
                    content.title = reminder.title
                    content.body = Texts.followUp[index % Texts.followUp.count]
                    content.sound = .default
                    content.categoryIdentifier = Category.task
                    content.userInfo = info.merging(["route": "tag"]) { a, _ in a }
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fire.timeIntervalSinceNow, repeats: false)
                    requests.append(UNNotificationRequest(
                        identifier: "\(prefix)follow-\(reminder.id.uuidString)-\(dayKey)-\(offset)",
                        content: content, trigger: trigger))
                }
            }
        }

        for request in requests {
            try? await center.add(request)
        }
    }

    /// Heute (falls fällig) und das nächste Mal danach.
    private static func nextOccurrences(of reminder: CustomReminder) -> [Date] {
        let cal = Calendar.current
        if let onDate = reminder.onDate { return [ClockTime.date(reminder.minutes, on: onDate)] }
        var result: [Date] = []
        for offset in 0..<8 where result.count < 2 {
            guard let day = cal.date(byAdding: .day, value: offset, to: Date()), reminder.isDue(on: day) else { continue }
            result.append(ClockTime.date(reminder.minutes, on: day))
        }
        return result
    }

    private static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Nach „Erledigt“: heutige Nachfragen zu dieser Erinnerung streichen.
    static func cancelFollowUps(for id: UUID) {
        let today = dayKey(Date())
        remove(prefixes: ["\(prefix)follow-\(id.uuidString)-\(today)-"], ids: ["snooze-\(id.uuidString)"])
    }

    /// Mitteilungen über den Anfang ihrer Kennung streichen (die Minuten sind ja einstellbar).
    private static func remove(prefixes: [String], ids: [String] = []) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let pending = requests.map(\.identifier).filter { id in prefixes.contains { id.hasPrefix($0) } }
            center.removePendingNotificationRequests(withIdentifiers: pending + ids)
        }
        center.getDeliveredNotifications { notes in
            let delivered = notes.map(\.request.identifier).filter { id in prefixes.contains { id.hasPrefix($0) } }
            center.removeDeliveredNotifications(withIdentifiers: delivered + ids)
        }
    }

    // MARK: Aufgaben mit Uhrzeit

    /// Zur Uhrzeit: Titel, darunter der Mini-Schritt (nur wenn du ihn sehen willst). Zeitkritisch → auch auf der Uhr.
    private static func todoRequests(_ ctx: Context) -> [UNNotificationRequest] {
        let now = Date()
        var requests: [UNNotificationRequest] = []
        for task in ctx.tasks where task.doneAt == nil {
            guard let at = task.remindAt, at > now else { continue }
            let step = task.steps.first { !$0.done }?.title ?? (task.showStep ? task.firstStep : "")
            requests.append(once("todo-\(task.id.uuidString)", at: at, category: Category.todo,
                                 title: task.title,
                                 body: step.isEmpty ? "Jetzt dran. Antippen zum Öffnen." : step,
                                 info: ["task": task.id.uuidString, "route": "anfangen"],
                                 timeSensitive: true))
        }
        return requests
    }

    /// „Später“ bei einer Aufgabe mit Uhrzeit.
    static func snoozeTodo(id: String, title: String, minutes: Int) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "Wie versprochen: nochmal."
        content.sound = .default
        content.categoryIdentifier = Category.todo
        content.userInfo = ["task": id, "route": "anfangen"]
        content.interruptionLevel = .timeSensitive
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(1, minutes) * 60), repeats: false)
        try? await UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: "snooze-todo-\(id)", content: content, trigger: trigger))
    }

    // MARK: Orte (beim Ankommen)

    /// Aufgaben mit Ort melden sich beim Ankommen (einmal); Läden mit „Einkaufsliste zeigen“ jedes Mal,
    /// solange etwas auf der Liste steht. iOS erlaubt rund 20 Orte gleichzeitig – mehr wird nicht geplant.
    private static func spotRequests(_ ctx: Context) -> [UNNotificationRequest] {
        var requests: [UNNotificationRequest] = []
        for task in ctx.spotTasks where requests.count < 15 {
            guard let spot = ctx.spots.first(where: { $0.id == task.spotID }) else { continue }
            let content = UNMutableNotificationContent()
            content.title = task.title
            content.body = "Angekommen: \(spot.name). Jetzt passt's."
            content.sound = .default
            content.categoryIdentifier = Category.todo
            content.userInfo = ["task": task.id.uuidString, "route": "anfangen"]
            content.interruptionLevel = .timeSensitive
            requests.append(UNNotificationRequest(identifier: "\(prefix)spot-\(task.id.uuidString)", content: content,
                                                  trigger: arrival(spot, key: task.id.uuidString, repeats: false)))
        }
        if ctx.shopCount > 0 {
            for spot in ctx.spots where spot.shopHint && requests.count < 19 {
                let content = UNMutableNotificationContent()
                content.title = "Du bist bei \(spot.name)"
                content.body = ctx.shopCount == 1 ? "1 Sache auf der Einkaufsliste." : "\(ctx.shopCount) Sachen auf der Einkaufsliste."
                content.sound = .default
                content.userInfo = ["route": "einkauf"]
                requests.append(UNNotificationRequest(identifier: "\(prefix)spot-shop-\(spot.id.uuidString)", content: content,
                                                      trigger: arrival(spot, key: "shop", repeats: true)))
            }
        }
        return requests
    }

    private static func arrival(_ spot: Spot, key: String, repeats: Bool) -> UNLocationNotificationTrigger {
        let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: spot.lat, longitude: spot.lon),
                                      radius: max(100, spot.radius), identifier: "\(spot.id.uuidString)-\(key)")
        region.notifyOnEntry = true
        region.notifyOnExit = false
        return UNLocationNotificationTrigger(region: region, repeats: repeats)
    }

    // MARK: Losgeh-Countdown

    /// Vor dem Losgehen am Morgen: z. B. 10 und 5 Minuten vorher und „Jetzt los“ – zeitkritisch,
    /// damit es auch im Fokus-Modus durchkommt und auf der Uhr tippt. Heute nur, wenn noch nicht geschafft.
    private static func morningCountdown(_ ctx: Context) -> [UNNotificationRequest] {
        guard ctx.settings.countdownOn else { return [] }
        var requests: [UNNotificationRequest] = []
        let cal = Calendar.current
        let now = Date()
        for dayOffset in 0...1 {
            guard let day = cal.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            let m = ctx.morning.forToday(day)
            guard m.isScheduled(on: day), !m.untimed, !(dayOffset == 0 && m.isDone) else { continue }
            let leave = ClockTime.date(m.leaveToday, on: day)
            let info = ["route": "morgen"]
            for step in Timing.countdown(leave: leave, offsets: ctx.settings.countdown, now: now) {
                requests.append(once("leave-\(dayKey(day))-\(step.minutes)", at: step.at, category: Category.morning,
                                     title: "In \(step.minutes) Min los",
                                     body: step.minutes <= 5 ? "Schuhe, Handy, Schlüssel, Geldbeutel."
                                         : "Langsam zum Ende kommen. Was fehlt noch?",
                                     info: info, timeSensitive: true))
            }
            if leave > now {
                requests.append(once("leave-\(dayKey(day))-0", at: leave, category: Category.morning,
                                     title: "Jetzt los",
                                     body: "Tür zu, Schlüssel dabei. Der Rest ist egal.",
                                     info: info, timeSensitive: true))
            }
        }
        return requests
    }

    /// „In 10 Min“ bei einer eigenen Erinnerung.
    static func snoozeTask(id: String, title: String, minutes: Int = 10) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "Wie versprochen: nochmal."
        content.sound = .default
        content.categoryIdentifier = Category.task
        content.userInfo = ["reminder": id, "route": "tag"]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(1, minutes) * 60), repeats: false)
        try? await UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: "snooze-\(id)", content: content, trigger: trigger))
    }

    /// Kauf-Parkplatz: nach 48 Stunden einmal nachfragen.
    static func scheduleWish(_ wish: ParkedWish) {
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = "Kauf-Parkplatz"
            content.body = "48 Stunden sind um. Willst du „\(wish.name)“ immer noch?"
            content.sound = .default
            content.categoryIdentifier = Category.park
            content.userInfo = ["route": "einkauf", "park": wish.id.uuidString]
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(60, wish.decideAfter.timeIntervalSinceNow), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "park-\(wish.id.uuidString)",
                                                        content: content, trigger: trigger))
        }
    }

    static func cancelWish(_ id: UUID) {
        let ids = ["park-\(id.uuidString)"]
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
    }

    /// „Gleich“ beim Essen: einmalig in 15 Minuten nochmal.
    static func snoozeMeal(minutes: Int = 15) async {
        let content = UNMutableNotificationContent()
        content.title = "Essen?"
        content.body = "Du wolltest in \(minutes) Minuten nochmal gefragt werden. Hier ist die Frage."
        content.sound = .default
        content.categoryIdentifier = Category.meal
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(1, minutes) * 60), repeats: false)
        try? await UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: "snooze-meal", content: content, trigger: trigger))
    }

    private static func daily(_ id: String, at minutes: Int, category: String,
                              title: String, body: String, route: String? = nil,
                              info: [String: String] = [:]) -> UNNotificationRequest {
        let m = ((minutes % 1440) + 1440) % 1440
        var components = DateComponents()
        components.hour = m / 60
        components.minute = m % 60
        return request(id, components, category: category, title: title, body: body, route: route, info: info)
    }

    private static func companionRequest(_ note: CompanionNote) -> UNNotificationRequest {
        once(note.id, at: note.date, category: note.category, title: note.title, body: note.body,
             info: ["route": note.route])
    }

    /// Nur Morgen-Überblick und Rückblick neu (nach Änderungen in der App, z. B. „3 erledigt“).
    static func replaceCompanion(_ notes: [CompanionNote]) async {
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .authorized else { return }
        let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix + "cmp-") }
        center.removePendingNotificationRequests(withIdentifiers: old)
        for note in notes { try? await center.add(companionRequest(note)) }
    }

    /// Einmalig zu einem genauen Zeitpunkt.
    private static func once(_ id: String, at date: Date, category: String,
                             title: String, body: String, info: [String: String],
                             timeSensitive: Bool = false) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if timeSensitive { content.interruptionLevel = .timeSensitive }
        content.categoryIdentifier = category
        content.userInfo = info
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return UNNotificationRequest(identifier: prefix + id, content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
    }

    // MARK: Gewohnheiten

    /// Tägliche Erinnerung pro Gewohnheit mit Uhrzeit; mit Dranbleiben fragt Dopa nach, bis sie abgehakt ist.
    private static func habitRequests(_ ctx: Context) -> [UNNotificationRequest] {
        var requests: [UNNotificationRequest] = []
        let cal = Calendar.current
        for habit in ctx.habits {
            guard let at = habit.remindAt else { continue }
            let category = habit.isMed ? Category.med : Category.habit
            let info = ["habit": habit.id.uuidString, "route": "jetzt"]
            requests.append(daily("habit-\(habit.id.uuidString)", at: at, category: category,
                                  title: habit.title, body: Texts.habit(habit), info: info))
            guard ctx.settings.persistOn else { continue }
            for dayOffset in 0...1 {
                if dayOffset == 0 && ctx.habitsDone.contains(habit.id) { continue }
                guard let day = cal.date(byAdding: .day, value: dayOffset, to: Date()) else { continue }
                let base = ClockTime.date(at, on: day)
                for (index, offset) in ctx.settings.followUps.sorted().enumerated() {
                    let fire = base.addingTimeInterval(TimeInterval(offset * 60))
                    guard fire > Date() else { continue }
                    requests.append(once("hfollow-\(habit.id.uuidString)-\(dayKey(day))-\(offset)", at: fire,
                                         category: category, title: habit.title,
                                         body: Texts.followUp[index % Texts.followUp.count], info: info))
                }
            }
        }
        return requests
    }

    /// Nach dem Abhaken: heutige Nachfragen streichen.
    static func cancelHabitFollowUps(_ id: UUID) {
        let today = dayKey(Date())
        remove(prefixes: ["\(prefix)hfollow-\(id.uuidString)-\(today)-"], ids: ["snooze-habit-\(id.uuidString)"])
    }

    static func snoozeHabit(id: String, title: String, category: String, minutes: Int = 10) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "Wie versprochen: nochmal."
        content.sound = .default
        content.categoryIdentifier = category
        content.userInfo = ["habit": id, "route": "jetzt"]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(1, minutes) * 60), repeats: false)
        try? await UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: "snooze-habit-\(id)", content: content, trigger: trigger))
    }

    // MARK: Geld

    /// Raten: 2 Tage vorher und am Tag (überfällig: abends nochmal). Fixkosten/Einnahmen: am Tag morgens.
    private static func moneyRequests(_ ctx: Context) -> [UNNotificationRequest] {
        var requests: [UNNotificationRequest] = []
        let now = Date()
        for item in ctx.money where item.remind {
            let id = item.id.uuidString
            let info = ["money": id, "route": "geld"]
            let amount = MoneyMath.euro(item.amount)
            switch item.kind {
            case .debt:
                guard let due = item.due else { continue }
                let pre = ClockTime.date(10 * 60, on: due.addingTimeInterval(-2 * 86_400))
                if pre > now {
                    requests.append(once("money-\(id)-pre", at: pre, category: Category.money,
                                         title: "In 2 Tagen fällig: \(item.title)",
                                         body: "\(amount). Ist genug auf dem Konto?", info: info))
                }
                let onDay = ClockTime.date(10 * 60, on: due)
                if onDay > now {
                    requests.append(once("money-\(id)-due", at: onDay, category: Category.money,
                                         title: "Heute fällig: \(item.title)",
                                         body: "\(amount) – bezahlen, dann hier abhaken.", info: info))
                } else {
                    // schon fällig und noch offen: einmal am Abend, ohne Drama
                    var late = ClockTime.date(18 * 60, on: now)
                    if late <= now { late = late.addingTimeInterval(86_400) }
                    requests.append(once("money-\(id)-late", at: late, category: Category.money,
                                         title: "Noch offen: \(item.title)",
                                         body: "\(amount). Kurz erledigen, dann ist es weg.", info: info))
                }
            case .fixed, .income:
                var components = DateComponents()
                components.day = min(max(item.dayOfMonth, 1), 31)
                components.hour = 9
                components.minute = 0
                let title = item.kind == .fixed ? "Heute geht ab: \(item.title)" : "Heute kommt Geld: \(item.title)"
                let body = item.kind == .fixed ? "\(amount) – nur damit es dich nicht überrascht."
                    : "\(amount). Das Spaß-Budget rechnet ab jetzt damit."
                requests.append(request("money-\(id)-m", components, category: "", title: title, body: body,
                                        route: "geld", info: info))
            }
        }
        return requests
    }

    static func cancelMoney(_ id: UUID) {
        let ids = ["pre", "due", "late", "m"].map { "\(prefix)money-\(id.uuidString)-\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
    }

    // MARK: Termine

    /// „Losgehen“ zur richtigen Zeit (Weg + Puffer) und mit Ort eine Vorwarnung 15 Min davor.
    private static func eventRequests(_ ctx: Context) -> [UNNotificationRequest] {
        var requests: [UNNotificationRequest] = []
        let now = Date()
        for event in ctx.events.prefix(12) {
            let lead = event.lead(ctx.calendar)
            guard lead > 0, ctx.acks["cal-\(event.key)"] == nil else { continue }
            let leave = event.leaveAt(ctx.calendar)
            let info = ["event": event.key, "route": "tag"]
            let time = ClockTime.string(ClockTime.minutes(of: event.start))
            let hasPlace = !event.location.isEmpty
            if leave > now {
                requests.append(once("cal-\(event.key)-go", at: leave, category: Category.event,
                                     title: hasPlace ? "Losgehen: \(event.title)" : "Gleich: \(event.title)",
                                     body: hasPlace ? "Um \(time) · \(event.location). Handy, Schlüssel, Geldbeutel."
                                         : "Um \(time). Jetzt langsam abschließen.",
                                     info: info, timeSensitive: true))
            }
            if ctx.settings.countdownOn {
                // eigener Countdown (z. B. 10 und 5 Min vorher) – tippt auf der Uhr
                for step in Timing.countdown(leave: leave, offsets: ctx.settings.countdown, now: now) {
                    requests.append(once("cal-\(event.key)-cd\(step.minutes)", at: step.at, category: Category.event,
                                         title: "In \(step.minutes) Min \(hasPlace ? "losgehen" : "geht's los")",
                                         body: "\(event.title) um \(time). Zum Ende kommen, Schuhe in Sichtweite.",
                                         info: info, timeSensitive: true))
                }
            } else {
                let warn = leave.addingTimeInterval(-15 * 60)
                if ctx.calendar.warnOn, hasPlace, warn > now {
                    requests.append(once("cal-\(event.key)-warn", at: warn, category: Category.event,
                                         title: "In 15 Min losgehen",
                                         body: "\(event.title) um \(time). Zum Ende kommen, Schuhe in Sichtweite.",
                                         info: info))
                }
            }
        }
        return requests
    }

    static func cancelEvent(_ key: String) {
        remove(prefixes: ["\(prefix)cal-\(key)-"])
    }

    private static func request(_ id: String, _ components: DateComponents, category: String,
                                title: String, body: String, route: String?,
                                info: [String: String] = [:]) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        var userInfo = info
        if let route { userInfo["route"] = route }
        content.userInfo = userInfo
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        return UNNotificationRequest(identifier: prefix + id, content: content, trigger: trigger)
    }
}

/// Texte ohne Schuld, ohne Anfeuern – kurz, trocken, manchmal ein bisschen frech.
enum Texts {

    static func mealTitle(_ minutes: Int) -> String {
        minutes < 11 * 60 ? "Frühstück?" : minutes < 15 * 60 ? "Mittag?" : "Abendessen?"
    }

    static let meal = [
        "Hast du heute schon was gegessen? Ehrliche Antwort.",
        "Irgendwas Kleines reicht: Brot, Banane, Joghurt.",
        "Dein Kopf läuft gerade auf Reserve. Kurz was essen?",
        "Essen jetzt = kein Heißhunger um Mitternacht.",
        "Kurzer Essens-Check. Muss nichts Großes sein.",
        "Snack-Zeit. Auch wenn du gerade keinen Hunger merkst.",
    ]

    static let nudge = [
        "Es ist {zeit}. Trinken, Klo, Essen?",
        "{zeit}. Ist das gerade noch das, was du machen wolltest?",
        "Kurzer Körper-Check: Wasser, Klo, strecken. Dann weiter.",
        "Du bist vermutlich gerade tief drin. Nur kurz: Es ist {zeit}.",
        "Aufstehen, einmal strecken, Wasser holen.",
        "Wolltest du heute noch was anderes erledigen? Es ist {zeit}.",
        "10 Sekunden Pause. Schultern runter, einmal durchatmen.",
        "Stupser: Wie lange sitzt du schon? Es ist {zeit}.",
        "Falls du gerade zockst: Alles gut. Nur kurz trinken.",
        "Es ist {zeit}. Passt das noch zu deinem Plan für heute?",
    ]

    static let task = [
        "Jetzt dran.",
        "Kurz erledigen, dann ist es weg.",
        "Dein Erinnerungs-Zettel meldet sich.",
        "Jetzt ist ein guter Moment dafür.",
    ]

    static let followUp = [
        "Noch nicht abgehakt. Jetzt kurz?",
        "Letzte Nachfrage – danach lasse ich dich in Ruhe.",
    ]

    static let morningTitle = [
        "Morgen-Checkliste",
        "Guten Morgen. Langsam.",
        "Aufstehen, Schritt für Schritt",
    ]

    static let spendAsk = [
        "Gedrückt halten und reinschreiben: „4,50 Döner“. Fertig.",
        "Ein Satz reicht, z. B. „12 Bahn, 3 Kaffee“. Nichts? Einfach wegwischen.",
        "Kurz fürs Geld-Tagebuch – gedrückt halten und Betrag tippen.",
    ]

    static let eveningTitle = [
        "Abendroutine",
        "Runterfahren",
        "Für Morgen-Ich",
    ]

    static func habit(_ habit: Habit) -> String {
        if habit.isMed {
            return ["Tabletten-Zeit. Danach abhaken, dann weißt du es später sicher.",
                    "Kurz: Tabletten. Abhaken nicht vergessen.",
                    "Tabletten jetzt – und dann hier „Genommen“."].randomElement()!
        }
        let count = habit.perDay > 1 ? " (\(habit.perDay)× am Tag)" : ""
        return ["Kurz \(habit.title)\(count). Danach abhaken.",
                "\(habit.title) – zehn Sekunden, dann weiter.",
                "Erinnerung an dich selbst: \(habit.title)."].randomElement()!
    }
}
