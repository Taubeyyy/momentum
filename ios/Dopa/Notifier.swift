import Foundation
import UserNotifications

/// Lokale Benachrichtigungen – Server-Pushs gehen unter TrollStore nicht.
enum Notifier {
    static let focusEndID = "focus-end"
    static let focusHalfID = "focus-half"

    static func scheduleFocusEnd(_ run: FocusRun, halfway: Bool = false) {
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true else { return }
            // Beim ersten Mal wartet das auf den Erlaubnis-Dialog – läuft der Timer da noch?
            guard (Shared.defaults?.object(forKey: Shared.focusEndKey) as? Date) == run.endsAt else { return }

            let content = UNMutableNotificationContent()
            content.title = "Zeit ist um"
            content.body = run.step.isEmpty ? run.title : "\(run.title) – \(run.step)"
            content.sound = .default
            content.categoryIdentifier = Reminders.Category.focus
            content.interruptionLevel = .timeSensitive      // kommt auch im Fokus-Modus durch (Handy + Uhr)
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, run.endsAt.timeIntervalSinceNow), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: focusEndID, content: content, trigger: trigger))

            // Halbzeit: ein kurzer Tipper (auf der Uhr am Handgelenk), damit du merkst, wo du stehst
            if halfway, let half = Timing.halfway(start: run.startedAt, end: run.endsAt), half > Date() {
                let left = Int((run.endsAt.timeIntervalSince(half) / 60).rounded())
                let note = UNMutableNotificationContent()
                note.title = "Halbzeit"
                note.body = "Noch \(left) Min · \(run.step.isEmpty ? run.title : run.step)"
                note.sound = .default
                note.interruptionLevel = .timeSensitive
                let at = UNTimeIntervalNotificationTrigger(timeInterval: max(1, half.timeIntervalSinceNow), repeats: false)
                try? await center.add(UNNotificationRequest(identifier: focusHalfID, content: note, trigger: at))
            }
        }
    }

    static func cancelFocusEnd() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [focusEndID, focusHalfID])
        center.removeDeliveredNotifications(withIdentifiers: [focusEndID, focusHalfID])
    }
}
