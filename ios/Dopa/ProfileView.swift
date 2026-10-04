import SwiftUI
import UniformTypeIdentifiers

/// Profil & Einstellungen (als Seite im aktuellen Tab) – aufgebaut wie die iOS-Einstellungen: oben Dot mit Level,
/// darunter klare Gruppen mit farbigen Symbolen. Alles Seltene eine Ebene tiefer.
struct ProfilePage: View {
    @EnvironmentObject private var store: Store
    @ObservedObject private var server = Server.shared
    @ObservedObject private var updates = Updates.shared
    @ObservedObject private var health = Health.shared
    @AppStorage("leftHanded") private var leftHanded = true     // „Mehr“-Bubble links
    @State private var showFeedback = false

    private var build: String {
        let info = Bundle.main.infoDictionary
        return info?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var body: some View {
        List {
            Section { ProfileHeader() }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

            // Dot-Gespräch und Schlaf liegen unter „Mehr“ – hier nicht doppelt (Build 61)
            Section("Fortschritt") {
                NavigationLink { QuestsPage() } label: {
                    SettingsRow(icon: "flag.checkered", color: .orange, title: "Wochen-Quests",
                                value: "\(store.weekQuests.filter(\.done).count) von \(store.weekQuests.count)")
                }
                NavigationLink { ProgressPage() } label: {
                    SettingsRow(icon: "sparkles", color: Color(hex: 0x8B5CF6), title: "Level & Fähigkeiten",
                                value: "Level \(store.level)")
                }
                NavigationLink { ThemesPage() } label: {
                    SettingsRow(icon: "paintpalette.fill", color: .pink, title: "Farben", value: store.theme.name)
                }
            }
            .dopaRow()

            Section("Einstellungen") {
                Toggle(isOn: $leftHanded) {
                    SettingsRow(icon: "hand.raised.fill", color: .indigo, title: "Linkshänder")
                }
                .tint(store.theme.accent)
                NavigationLink { ReminderSettingsPage() } label: {
                    SettingsRow(icon: "bell.badge.fill", color: .red, title: "Benachrichtigungen")
                }
                NavigationLink { SpotsPage() } label: {
                    SettingsRow(icon: "mappin.and.ellipse", color: Color(hex: 0x6366F1), title: "Orte",
                                value: store.data.spots.isEmpty ? nil : "\(store.data.spots.count)")
                }
                NavigationLink { PlanSettingsPage() } label: {
                    SettingsRow(icon: "sunrise.fill", color: .orange, title: "Routinen & Erinnerungen")
                }
                NavigationLink { HabitsPage() } label: {
                    SettingsRow(icon: "drop.fill", color: .cyan, title: "Gewohnheiten", value: "\(store.data.habits.count)")
                }
                NavigationLink { CalendarSettingsPage() } label: {
                    SettingsRow(icon: "calendar", color: .red, title: "Kalender")
                }
            }
            .dopaRow()

            Section("App & Konto") {
                Button {
                    if updates.available { updates.install() } else { Task { await updates.check(force: true) } }
                } label: {
                    SettingsRow(icon: updates.available ? "arrow.down.circle.fill" : "checkmark.seal.fill",
                                color: updates.available ? .blue : .green,
                                title: updates.available ? "Update auf Build \(updates.latest?.build ?? 0) installieren" : "Dopa ist aktuell",
                                value: "Build \(updates.currentBuild)")
                }
                NavigationLink { AccountPage() } label: {
                    SettingsRow(icon: "icloud.fill", color: .blue, title: "Konto & Backup",
                                value: BackupText.short(server.backupAt, connected: server.isConnected))
                }
            }
            .dopaRow()

            Section {
                Button { showFeedback = true } label: {
                    SettingsRow(icon: "envelope.fill", color: .green, title: "Feedback an Claude")
                }
                NavigationLink { DiagnosticsView() } label: {
                    SettingsRow(icon: "wrench.and.screwdriver.fill", color: .gray, title: "Technik")
                }
            } footer: {
                Text("Feedback geht auch überall: Handy schütteln. · Dopa \(build)")
            }
            .dopaRow()
        }
        .dopaBackground()
        .navigationTitle("Profil")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(isPresented: $showFeedback) {
            FeedbackSheet(screen: "Profil")
                .environmentObject(store)
        }
    }
}

/// Kopf des Profils: Dot mit Level-Ring, Name (antippen = umbenennen), Level und Fortschritt.
struct ProfileHeader: View {
    @EnvironmentObject private var store: Store
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        let level = store.level
        let progress = Level.progress(store.data.game.xp)
        let fraction = Double(progress.have) / Double(max(progress.need, 1))
        VStack(spacing: 10) {
            ZStack {
                Circle().stroke(Color(hex: 0x2E2635), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(store.theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: fraction)
                DotView(level: level, size: 92, tappable: true)
            }
            .frame(width: 118, height: 118)

            Button {
                newName = store.dotName
                renaming = true
            } label: {
                HStack(spacing: 6) {
                    Text(store.dotName).font(.system(size: 26, weight: .bold, design: .rounded))
                    Image(systemName: "pencil").font(.system(size: 13, weight: .semibold)).foregroundStyle(DS.faint)
                }
                .foregroundStyle(DS.ink)
            }
            .buttonStyle(PressStyle())

            Text("Level \(level) · \(Level.title(level)) · \(progress.have)/\(progress.need) XP")
                .font(.system(size: 13)).foregroundStyle(DS.muted)
            let days = store.activeDaysThisWeek
            Text(days == 0 ? "Diese Woche geht's gerade erst los."
                 : "Diese Woche an \(days) \(days == 1 ? "Tag" : "Tagen") etwas für dich gemacht.")
                .font(.system(size: 13)).foregroundStyle(DS.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .alert("Wie soll er heißen?", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Sichern") { store.renameDot(newName) }
            Button("Abbrechen", role: .cancel) {}
        }
    }
}

/// Wochen-Quests als eigene Seite.
struct QuestsPage: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        List {
            Section {
                ForEach(store.weekQuests) { item in
                    QuestRow(quest: item.quest, progress: item.progress, done: item.done)
                }
            } footer: {
                Text("Jede Woche drei neue, je +\(Quest.reward) XP. Nicht geschafft? Egal – nächste Woche gibt's neue.")
            }
            .dopaRow()
        }
        .dopaBackground()
        .navigationTitle("Wochen-Quests")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Farben zum Freischalten.
struct ThemesPage: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        List {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 12)], spacing: 12) {
                    ForEach(Theme.all) { theme in
                        ThemeTile(theme: theme,
                                  unlocked: theme.level <= store.level,
                                  selected: store.data.game.theme == theme.id) {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.easeInOut(duration: 0.25)) { store.setTheme(theme.id) }
                        }
                    }
                }
                .padding(.vertical, 6)
            } footer: {
                Text("Neue Farben schaltest du mit Leveln frei.")
            }
            .dopaRow()
        }
        .dopaBackground()
        .navigationTitle("Farben")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// „gesichert vor 3 Min“
enum BackupText {
    static func short(_ date: Date?, connected: Bool) -> String {
        guard connected else { return "nicht verbunden" }
        guard let date else { return "noch nicht gesichert" }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.unitsStyle = .short
        return "gesichert \(f.localizedString(for: date, relativeTo: Date()))"
    }
}

/// Fähigkeiten pro Level und die letzten Punkte.
struct ProgressPage: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        List {
            Section {
                ForEach(DotAbility.all) { ability in
                    let unlocked = ability.level <= store.level
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(ability.level)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(unlocked ? .white : DS.faint)
                            .frame(width: 26, height: 26)
                            .background(unlocked ? store.theme.accent : DS.field, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(ability.title).font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(unlocked ? DS.ink : DS.muted)
                            Text(ability.text).font(.system(size: 12)).foregroundStyle(DS.muted)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Fähigkeiten")
            }
            .dopaRow()

            if !store.data.game.log.isEmpty {
                Section("Zuletzt bekommen") {
                    ForEach(Array(store.data.game.log.prefix(12).enumerated()), id: \.offset) { _, event in
                        HStack {
                            Text(event.reason).font(.subheadline).lineLimit(1)
                            Spacer()
                            Text("+\(event.amount)")
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .foregroundStyle(store.theme.accent)
                        }
                    }
                }
                .dopaRow()
            }
        }
        .dopaBackground()
        .navigationTitle("Level")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Konto, Server-Backup, Datei-Backup – und ganz unten die Technik.
struct AccountPage: View {
    @EnvironmentObject private var store: Store
    @State private var backupURL: URL?
    @State private var importing = false
    @State private var importError: String?
    @State private var confirmImport: URL?

    var body: some View {
        List {
            ServerSection()

            Section {
                if let backupURL {
                    ShareLink(item: backupURL) {
                        Label("Backup-Datei teilen", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button {
                        backupURL = store.exportBackup()
                    } label: {
                        Label("Backup als Datei", systemImage: "externaldrive")
                    }
                }
                Button {
                    importing = true
                } label: {
                    Label("Backup-Datei einspielen", systemImage: "square.and.arrow.down")
                }
            } header: {
                Text("Datei")
            } footer: {
                Text(importError ?? "Zusätzlich zum Server – zum Beispiel vor einer Neuinstallation in „Dateien“ ablegen.")
            }
            .dopaRow()

            Section {
                NavigationLink {
                    DiagnosticsView()
                } label: {
                    Label("Technik (Fehlersuche)", systemImage: "wrench.and.screwdriver")
                        .foregroundStyle(DS.muted)
                }
            }
            .dopaRow()
        }
        .dopaBackground()
        .navigationTitle("Konto & Backup")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { confirmImport = url }
        }
        .confirmationDialog("Backup einspielen?", isPresented: Binding(
            get: { confirmImport != nil }, set: { if !$0 { confirmImport = nil } }
        ), titleVisibility: .visible) {
            Button("Ersetzen", role: .destructive) {
                guard let url = confirmImport else { return }
                do {
                    try store.importBackup(from: url)
                    importError = "Backup eingespielt."
                } catch {
                    importError = "Das war keine gültige Dopa-Sicherung."
                }
            }
        } message: {
            Text("Alles, was jetzt in Dopa ist, wird durch das Backup ersetzt.")
        }
    }
}

struct QuestRow: View {
    let quest: Quest
    let progress: Int
    let done: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                CheckBox(done: done).scaleEffect(0.8)
                Text(quest.title).strikethrough(done)
                Spacer()
                Text("\(progress)/\(quest.target)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(progress), total: Double(quest.target))
        }
        .padding(.vertical, 2)
    }
}

struct ThemeTile: View {
    let theme: Theme
    let unlocked: Bool
    let selected: Bool
    let onSelect: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(colors: theme.background(scheme), startPoint: .top, endPoint: .bottom))
                    Circle().fill(theme.accent).frame(width: 26, height: 26)
                    if !unlocked {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.black.opacity(0.45))
                        Image(systemName: "lock.fill").foregroundStyle(.white)
                    }
                }
                .frame(height: 64)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(selected ? theme.accent : .clear, lineWidth: 3))
                Text(unlocked ? theme.name : "Level \(theme.level)")
                    .font(.caption)
                    .foregroundStyle(unlocked ? Color.primary : Color.secondary)
            }
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
    }
}
