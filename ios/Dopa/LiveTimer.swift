import ActivityKit
import Foundation

/// Live Activity für den Fokus-Timer – neu gebaut (Build 32). Jeder Schritt landet im Protokoll
/// (Profil → Konto & Backup → Technik), damit man sieht, wo es hängt.
@MainActor
enum LiveTimer {
    /// Läuft schon eine? Dann nur aktualisieren (z. B. +5 Min), sonst neu starten.
    static func show(_ run: FocusRun) {
        let state = DopaTimerAttributes.ContentState(step: run.step, start: run.startedAt, end: run.endsAt)
        let content = ActivityContent(state: state, staleDate: run.endsAt.addingTimeInterval(120))
        if let running = Activity<DopaTimerAttributes>.activities.first(where: { $0.activityState == .active }) {
            Task { await running.update(content) }
            LiveLog.add("aktualisiert bis \(LiveLog.time(run.endsAt))")
            return
        }
        start(title: run.title, content: content)
    }

    /// Diagnose: zwei Minuten Test-Timer.
    static func test() {
        LiveLog.add("Test · registriert als \(Diagnostics.read().registration)")
        let now = Date()
        let state = DopaTimerAttributes.ContentState(step: "Test aus der Technik-Seite", start: now,
                                                     end: now.addingTimeInterval(120))
        start(title: "Dopa-Test", content: ActivityContent(state: state, staleDate: now.addingTimeInterval(240)))
    }

    static func endAll() {
        // Liste jetzt festhalten, sonst beendet der Task ggf. schon die nächste Activity
        let running = Activity<DopaTimerAttributes>.activities
        guard !running.isEmpty else { return }
        Task {
            for activity in running { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        LiveLog.add("beendet (\(running.count))")
    }

    private static func start(title: String, content: ActivityContent<DopaTimerAttributes.ContentState>) {
        let info = ActivityAuthorizationInfo()
        guard info.areActivitiesEnabled else {
            LiveLog.add("nicht gestartet: Live-Aktivitäten sind in den iOS-Einstellungen für Dopa aus")
            return
        }
        do {
            let activity = try Activity.request(attributes: DopaTimerAttributes(title: title), content: content, pushType: nil)
            let started = Date()
            LiveLog.add("gestartet → \(activity.activityState)")
            Task {
                for await state in activity.activityStateUpdates {
                    LiveLog.add("Status → \(state)")
                    // sofort wieder weg und nie gezeichnet = iOS findet die Ansicht nicht
                    if state == .dismissed && Date().timeIntervalSince(started) < 5 {
                        LiveLog.add("→ sofort beendet, Ansicht nicht gefunden (TrollStore: Dopa auf „User“?)")
                    }
                }
            }
        } catch {
            LiveLog.add("Fehler beim Starten: \(error.localizedDescription)")
        }
    }
}

/// Kleines Protokoll (die letzten 40 Zeilen) für die Technik-Seite.
enum LiveLog {
    private static let key = "liveActivityLog"

    static var lines: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }

    static func add(_ text: String) {
        var all = lines
        all.append("\(time(Date()))  \(text)")
        if all.count > 40 { all.removeFirst(all.count - 40) }
        UserDefaults.standard.set(all, forKey: key)
        NotificationCenter.default.post(name: .liveLogChanged, object: nil)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
        NotificationCenter.default.post(name: .liveLogChanged, object: nil)
    }

    static func time(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d:%02d:%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }
}

extension Notification.Name {
    static let liveLogChanged = Notification.Name("liveLogChanged")
}
