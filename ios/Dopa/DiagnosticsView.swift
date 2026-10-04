import SwiftUI
import ActivityKit
import UserNotifications
import WidgetKit

/// Technik-Ansicht (Profil → Technik): prüft, was unter TrollStore
/// funktioniert. Vor allem für die Live-Activity-Fehlersuche gedacht.
struct DiagnosticsView: View {
    @EnvironmentObject private var store: Store
    @State private var notifStatus = "…"
    @State private var diag: Diagnostics.Info?     // erst auf Knopfdruck
    @State private var activityStates: [String] = []
    @State private var liveLog: [String] = LiveLog.lines
    @State private var message: String?
    @State private var placedWidgets = "…"

    private var appGroupOK: Bool { Shared.containerURL != nil && Shared.defaults != nil }
    private var liveActivitiesOK: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    private var build: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    var body: some View {
        Form {
            Section {
                check("App Group (Widget ↔ App)", appGroupOK)
                check("Live Activities erlaubt", liveActivitiesOK)
                row("Benachrichtigungen", notifStatus)
                row("KI", Server.shared.aiAvailable ? (Server.shared.aiLabel ?? "an") : "aus")
            } header: {
                Text("Checks")
            } footer: {
                Text("Version \(build)")
            }
            .dopaRow()

            Section {
                check("iPhone-App-Kennung (LSRequiresIPhoneOS)",
                      Bundle.main.object(forInfoDictionaryKey: "LSRequiresIPhoneOS") as? Bool == true)
                row("Laufen gerade", activityStates.isEmpty ? "keine" : activityStates.joined(separator: ", "))
                row("Erweiterung geladen", LiveProbe.loaded ?? "noch nie")
                row("Gezeichnet", LiveProbe.rendered ?? "noch nie")
                row("Dopa-Widgets platziert", placedWidgets)
                if let diag {
                    row("Registriert als", diag.registration)
                    check("Widget-Erweiterung bekannt", diag.plugins.contains("com.taubey.dopa.widget"))
                    row("Erweiterungen", diag.plugins.isEmpty ? "keine" : diag.plugins.joined(separator: ", "))
                }
                Button("Live Activity testen (2 Min)") {
                    LiveTimer.test()
                    refreshActivities()
                }
                Button("Diagnose an Claude senden") { sendDiagnosis() }
                Button(diag == nil ? "System prüfen" : "Neu prüfen") {
                    refreshActivities()
                    diag = Diagnostics.read()
                }
                if !liveLog.isEmpty {
                    ForEach(Array(liveLog.reversed().enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    Button("Protokoll leeren", role: .destructive) { LiveLog.clear() }
                }
            } header: {
                Text("Live Activity")
            } footer: {
                Text("Läuft seit Build 51. Falls sie wieder verschwindet: Dopa in TrollStore auf „User“ lassen, Test starten, Handy sperren, dann „Diagnose an Claude senden“.")
            }
            .dopaRow()

            Section("Benachrichtigungs-Test") {
                Button("Test-Benachrichtigung in 5 Sekunden") { testNotification() }
            }
            .dopaRow()

            if let message {
                Section { Text(message).font(.footnote) }
                .dopaRow()
            }
        }
        .dopaBackground()
        .navigationTitle("Technik")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            refreshActivities()
            diag = Diagnostics.read()       // Registrierung gleich zeigen (für den Reparatur-Hinweis)
            readPlacedWidgets()
            await refreshNotifStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: .liveLogChanged)) { _ in
            liveLog = LiveLog.lines
            refreshActivities()
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }
    }

    private func check(_ label: String, _ ok: Bool) -> some View {
        HStack {
            Text(label)
            Spacer()
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? Color.green : Color.red)
        }
    }

    /// Welche Dopa-Widgets auf Home- oder Sperrbildschirm liegen – ohne die startet iOS die Erweiterung selten.
    private func readPlacedWidgets() {
        WidgetCenter.shared.getCurrentConfigurations { result in
            let text: String
            switch result {
            case .success(let widgets):
                let kinds: [String] = widgets.map { "\($0.kind) (\($0.family))" }
                text = widgets.isEmpty ? "keine" : "\(widgets.count): " + kinds.joined(separator: ", ")
            case .failure(let error):
                text = "Fehler: \(error.localizedDescription)"
            }
            DispatchQueue.main.async { placedWidgets = text }
        }
    }

    /// Alles, was für die Fehlersuche zählt, als Feedback an den Server (kein Screenshot nötig).
    private func sendDiagnosis() {
        let info = Diagnostics.read()
        let lines = [
            "Live-Activity-Diagnose · Version \(build)",
            "LSRequiresIPhoneOS: \(Bundle.main.object(forInfoDictionaryKey: "LSRequiresIPhoneOS") as? Bool == true)",
            "erlaubt: \(liveActivitiesOK) · Benachrichtigungen: \(notifStatus)",
            "registriert als: \(info.registration)",
            "Widgets platziert: \(placedWidgets)",
            "Erweiterungen: \(info.plugins.joined(separator: ", "))",
            "laufen: \(activityStates.joined(separator: ", "))",
            "geladen: \(LiveProbe.loaded ?? "nie") · gezeichnet: \(LiveProbe.rendered ?? "nie")",
            "Protokoll:",
        ] + LiveLog.lines.suffix(20)
        store.addFeedback(lines.joined(separator: "\n"), screen: "Technik-Diagnose")
        message = "Gesendet – Claude sieht es beim nächsten Mal."
    }

    private func refreshActivities() {
        activityStates = Activity<DopaTimerAttributes>.activities.map { "\($0.activityState)" }
    }

    private func testNotification() {
        Task {
            let center = UNUserNotificationCenter.current()
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            await refreshNotifStatus()
            guard granted else {
                message = "Benachrichtigungen nicht erlaubt."
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "Dopa"
            content.body = "Test angekommen 👋"
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger))
            message = "Kommt in 5 Sekunden."
        }
    }

    private func refreshNotifStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notifStatus = switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: "erlaubt"
        case .denied: "abgelehnt"
        case .notDetermined: "noch nicht gefragt"
        @unknown default: "?"
        }
    }
}
