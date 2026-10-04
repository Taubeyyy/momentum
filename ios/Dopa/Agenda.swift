import EventKit
import SwiftUI

/// Ein Termin aus dem iPhone-Kalender, so wie Dopa ihn braucht.
struct AgendaEvent: Identifiable, Hashable {
    let id: String              // eindeutig pro Vorkommen
    let eventID: String         // gleich für alle Wiederholungen – für die eigene Vorlaufzeit
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let location: String
    let calendarID: String
    let color: Color

    /// Kurzer, stabiler Schlüssel für Benachrichtigungs-IDs.
    var key: String {
        var hash: UInt64 = 1469598103934665603
        for byte in id.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        return String(hash, radix: 16)
    }

    /// Minuten vor Beginn: eigene Einstellung, sonst mit/ohne Ort.
    func lead(_ settings: CalendarSettings) -> Int {
        if let custom = settings.leads[eventID] { return custom }
        return location.isEmpty ? settings.leadWithout : settings.leadWithPlace
    }

    func leaveAt(_ settings: CalendarSettings) -> Date {
        start.addingTimeInterval(-Double(lead(settings)) * 60)
    }
}

struct AgendaCalendar: Identifiable {
    let id: String
    let title: String
    let color: Color
}

/// Liest Termine (nur lesen, nie ändern) für heute und die nächsten Tage.
@MainActor
final class Agenda: ObservableObject {
    static let shared = Agenda()

    @Published private(set) var events: [AgendaEvent] = []
    @Published private(set) var authorized = false
    @Published private(set) var denied = false

    private let store = EKEventStore()

    private init() {
        updateStatus()
        refresh()
        // Termin im Kalender geändert → Zeitleiste und Losgehen-Erinnerungen nachziehen
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            Task { @MainActor in
                Agenda.shared.refresh()
                Store.shared.rescheduleReminders()
            }
        }
    }

    private func updateStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(iOS 17, *) {
            authorized = status == .fullAccess
        } else {
            authorized = status == .authorized
        }
        denied = status == .denied || status == .restricted
    }

    func requestAccess() async {
        if #available(iOS 17, *) {
            _ = try? await store.requestFullAccessToEvents()
        } else {
            _ = try? await store.requestAccess(to: .event)
        }
        updateStatus()
        refresh()
        Store.shared.rescheduleReminders()
    }

    /// Heute bis in acht Tagen neu einlesen (geht schnell, läuft beim Öffnen der App).
    func refresh() {
        updateStatus()
        guard authorized else {
            events = []
            return
        }
        let start = Calendar.current.startOfDay(for: Date())
        let end = start.addingTimeInterval(8 * 86_400)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        events = store.events(matching: predicate).compactMap { e in
            guard let startDate = e.startDate, let endDate = e.endDate else { return nil }
            let eventID = e.eventIdentifier ?? e.calendarItemIdentifier
            return AgendaEvent(
                id: "\(eventID)|\(Int(startDate.timeIntervalSince1970))",
                eventID: eventID,
                title: (e.title?.isEmpty == false ? e.title : nil) ?? "Termin",
                start: startDate,
                end: endDate,
                allDay: e.isAllDay,
                location: (e.location ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                calendarID: e.calendar?.calendarIdentifier ?? "",
                color: e.calendar.map { Color(cgColor: $0.cgColor) } ?? DS.purpleMuted)
        }
        .sorted { $0.start < $1.start }
    }

    var calendars: [AgendaCalendar] {
        guard authorized else { return [] }
        return store.calendars(for: .event)
            .map { AgendaCalendar(id: $0.calendarIdentifier, title: $0.title, color: Color(cgColor: $0.cgColor)) }
            .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
    }

    /// Alles, was diesen Tag berührt (auch ganztägig).
    func events(on day: Date, hidden: [String]) -> [AgendaEvent] {
        let start = Calendar.current.startOfDay(for: day)
        let end = start.addingTimeInterval(86_400)
        return events.filter { !hidden.contains($0.calendarID) && $0.start < end && $0.end > start }
    }

    /// Kommende Termine mit Uhrzeit, für die Losgehen-Erinnerungen.
    func upcoming(days: Int, hidden: [String]) -> [AgendaEvent] {
        let now = Date()
        let end = Calendar.current.startOfDay(for: now).addingTimeInterval(Double(days) * 86_400)
        return events.filter { !$0.allDay && !hidden.contains($0.calendarID) && $0.start > now && $0.start < end }
    }

    /// Der nächste Termin mit Uhrzeit, der noch nicht angefangen hat.
    func next(after now: Date = Date(), hidden: [String]) -> AgendaEvent? {
        events.first { !$0.allDay && !hidden.contains($0.calendarID) && $0.start > now }
    }
}
