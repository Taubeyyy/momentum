import SwiftUI
import UIKit

extension Notification.Name {
    static let deviceDidShake = Notification.Name("deviceDidShake")
}

/// Schütteln irgendwo in der App → Feedback-Fenster.
extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        if motion == .motionShake {
            NotificationCenter.default.post(name: .deviceDidShake, object: nil)
        }
    }
}

// MARK: - Feedback

/// Feedback an Claude: wird sofort gespeichert und verschickt, sobald Internet da ist.
/// Darunter siehst du, was schon umgesetzt wurde.
struct FeedbackSheet: View {
    let screen: String
    @EnvironmentObject private var store: Store
    @ObservedObject private var server = Server.shared
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var statuses: [Server.FeedbackStatus] = []
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Was nervt, was fehlt, was wäre cool?", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($focused)
                } footer: {
                    Text(server.isConnected
                         ? "Geht an deinen Server. Claude liest es dort und baut es ein."
                         : "Wird gespeichert und verschickt, sobald du im Profil mit dem Server verbunden bist.")
                }
                .dopaRow()

                if !store.pendingFeedback.isEmpty {
                    Section("Wartet auf Internet") {
                        ForEach(store.pendingFeedback) { item in
                            Text(item.text).font(.subheadline).lineLimit(2)
                        }
                    }
                    .dopaRow()
                }

                if !statuses.isEmpty {
                    Section("Schon geschickt") {
                        ForEach(statuses) { item in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.text).font(.subheadline).lineLimit(3)
                                if item.done_at != nil {
                                    Label(item.done_note.isEmpty ? "Umgesetzt" : item.done_note, systemImage: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                } else {
                                    Text("offen").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .dopaRow()
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .dopaBackground()
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Senden") {
                        store.addFeedback(text, screen: screen)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        Toaster.shared.show("Danke – ist bei Claude angekommen")
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task {
                focused = true
                await store.syncFeedback()
                if server.isConnected, let list = try? await server.feedbackStatus() {
                    statuses = list
                }
            }
        }
    }
}

// MARK: - Verbindung (im Profil)

struct ServerSection: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var server = Server.shared
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var message: String?
    @State private var confirmRestore = false

    var body: some View {
        Section {
            if server.isConnected {
                Label(server.email ?? "Verbunden", systemImage: "checkmark.icloud")
                HStack {
                    Text("Automatisch")
                    Spacer()
                    Text(BackupText.short(server.backupAt, connected: true))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Button("Jetzt sichern") {
                    run { await store.backupNow(force: true); return "Gesichert." }
                }
                Button("Vom Server wiederherstellen") { confirmRestore = true }
                Button("Abmelden", role: .destructive) { server.logout() }
            } else {
                TextField("E-Mail", text: $email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Passwort (mind. 8 Zeichen)", text: $password)
                    .textContentType(.password)
                HStack {
                    Button("Anmelden") { connect(create: false) }
                        .buttonStyle(.borderedProminent)
                    Button("Konto erstellen") { connect(create: true) }
                        .buttonStyle(.bordered)
                }
                .disabled(busy || email.isEmpty || password.count < 8)
            }
            if busy {
                ProgressView()
            }
        } header: {
            Text("Server")
        } footer: {
            Text(message ?? (server.isConnected
                ? "Dopa sichert von selbst: kurz nach jeder Änderung, beim Schließen und ab und zu im Hintergrund."
                : "Für KI, Feedback an Claude und automatische Backups. Ohne Konto funktioniert Dopa trotzdem komplett."))
        }
        .dopaRow()
        .confirmationDialog("Vom Server wiederherstellen?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Ersetzen", role: .destructive) {
                run { try await store.restoreFromServer(); return "Wiederhergestellt." }
            }
        } message: {
            Text("Alles, was jetzt in Dopa ist, wird durch das Server-Backup ersetzt.")
        }
    }

    private func connect(create: Bool) {
        run {
            try await server.login(email: email, password: password, create: create)
            password = ""
            await store.syncFeedback()
            await server.refreshStatus()
            // Frisch installiert und auf dem Server liegt ein Backup? Gleich anbieten.
            if !create && store.looksFresh && server.backupAt != nil {
                confirmRestore = true
                return "Verbunden. Auf dem Server liegt ein Backup."
            }
            await store.backupNow(force: true)
            return create ? "Konto erstellt und verbunden." : "Verbunden."
        }
    }

    private func run(_ action: @escaping () async throws -> String) {
        busy = true
        message = nil
        Task {
            do {
                message = try await action()
            } catch {
                message = error.localizedDescription
            }
            busy = false
        }
    }
}
