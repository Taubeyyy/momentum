import SwiftUI

/// Claude auf dem Dopa-Server: wie viel vom Pro-Limit verbraucht ist, wann es zurückgesetzt wird,
/// und welches Modell die Server-Sitzungen („mach die Updates“) nehmen.
struct ClaudeView: View {
    @ObservedObject private var router = Router.shared
    @ObservedObject private var server = Server.shared
    @State private var state: Server.ClaudeState?
    @State private var error: String?
    @State private var refreshing = false
    @State private var savingModel: String?

    var body: some View {
        NavigationStack {
            DopaScreen(eyebrow: "Dein Pro-Abo und der Dopa-Server", title: "Claude", tab: .more) {
                VStack(spacing: 14) {
                    if server.token == nil {
                        Card(title: "Nicht angemeldet", symbol: "person.crop.circle.badge.questionmark") {
                            Text("Melde dich im Profil beim Dopa-Server an, dann siehst du hier deine Claude-Limits.")
                                .font(.system(size: 15)).foregroundStyle(DS.muted)
                        }
                    } else if let state {
                        ClaudeJobCard()
                        limitsCard(state)
                        modelCard(state)
                        howCard
                    } else if let error {
                        Card(title: "Gerade nicht erreichbar", symbol: "wifi.slash") {
                            Text(error).font(.system(size: 15)).foregroundStyle(DS.muted)
                            Button("Nochmal versuchen") { Task { await load() } }
                                .buttonStyle(SoftButtonStyle())
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    }
                }
            }
        }
        .task { await load() }
        .onChange(of: router.claudeVisible) { visible in
            if visible { Task { await load() } }
        }
    }

    // MARK: Limits

    private func limitsCard(_ state: Server.ClaudeState) -> some View {
        Card(title: "Limits", symbol: "gauge.with.dots.needle.33percent") {
            if let limits = state.limits {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(alignment: .leading, spacing: 16) {
                        if let five = limits.fiveHour {
                            LimitRow(title: "5 Stunden", window: five, now: context.date, weekly: false)
                        }
                        if let week = limits.week {
                            LimitRow(title: "Woche", window: week, now: context.date, weekly: true)
                        }
                        if limits.fiveHour == nil && limits.week == nil {
                            Text("Noch keine Zahlen – tipp auf Aktualisieren.")
                                .font(.system(size: 15)).foregroundStyle(DS.muted)
                        }
                        footer(limits: limits, now: context.date, canRefresh: state.canRefresh)
                    }
                }
            } else {
                Text("Noch keine Zahlen. Sie kommen, sobald Claude auf dem Server einmal gearbeitet hat – oder tipp auf Aktualisieren.")
                    .font(.system(size: 15)).foregroundStyle(DS.muted)
                if state.canRefresh { refreshButton }
            }
        }
    }

    private func footer(limits: Server.ClaudeLimits, now: Date, canRefresh: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if let at = limits.at {
                    Text("Stand \(ClaudeTime.ago(Date(timeIntervalSince1970: at / 1000), now: now))")
                }
                if let model = limits.model { Text("zuletzt mit \(model)") }
            }
            .font(.system(size: 12)).foregroundStyle(DS.faint)
            Spacer(minLength: 0)
            if canRefresh { refreshButton }
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await refresh() }
        } label: {
            HStack(spacing: 6) {
                if refreshing { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                Text(refreshing ? "Frage nach …" : "Aktualisieren")
            }
        }
        .buttonStyle(PillButtonStyle())
        .disabled(refreshing)
    }

    // MARK: Modell

    private func modelCard(_ state: Server.ClaudeState) -> some View {
        Card(title: "Modell auf dem Server", symbol: "cpu") {
            VStack(spacing: 0) {
                ForEach(state.models) { model in
                    Button {
                        Task { await setModel(model.id) }
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.label).font(.system(size: 16, weight: .semibold)).foregroundStyle(DS.ink)
                                Text(model.hint).font(.system(size: 13)).foregroundStyle(DS.muted)
                            }
                            Spacer(minLength: 0)
                            if savingModel == model.id {
                                ProgressView().controlSize(.small)
                            } else if state.model == model.id {
                                Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(DS.purpleMuted)
                            }
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(savingModel != nil)
                    if model.id != state.models.last?.id { Divider().overlay(DS.line) }
                }
                Text("Gilt für neue Sitzungen. In der Claude-App kannst du es pro Sitzung auch ändern.")
                    .font(.system(size: 12)).foregroundStyle(DS.faint)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            }
        }
    }

    private var howCard: some View {
        Card(title: "So geht’s", symbol: "questionmark.circle") {
            Text("Oben einfach „Mach die Updates“ tippen – Claude liest dein Feedback, baut alles ein und meldet die Build-Nummer. Läuft auf dem Server weiter, auch wenn Dopa zu ist. Alternativ: Claude-App → Code → „Dopa-Server“.")
                .font(.system(size: 15)).foregroundStyle(DS.muted)
            if let url = URL(string: "https://claude.ai/code") {
                Link(destination: url) {
                    Label("Claude öffnen", systemImage: "arrow.up.right")
                }
                .buttonStyle(PillButtonStyle())
            }
        }
    }

    // MARK: Laden

    private func load() async {
        guard server.token != nil else { return }
        do {
            let fresh = try await Server.shared.claudeState()
            withAnimation(.easeOut(duration: 0.2)) { state = fresh; error = nil }
            if let id = fresh.job?.id { await ClaudeJobs.shared.load(id) }
        } catch {
            if state == nil { self.error = error.localizedDescription }
        }
    }

    private func refresh() async {
        refreshing = true
        defer { refreshing = false }
        do {
            let fresh = try await Server.shared.refreshClaude()
            withAnimation(.easeOut(duration: 0.2)) { state = fresh }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            Toaster.shared.show(error.localizedDescription)
        }
    }

    private func setModel(_ id: String) async {
        guard state?.model != id else { return }
        savingModel = id
        defer { savingModel = nil }
        do {
            let fresh = try await Server.shared.setClaudeModel(id)
            withAnimation(.easeOut(duration: 0.2)) { state = fresh }
            UISelectionFeedbackGenerator().selectionChanged()
        } catch {
            Toaster.shared.show(error.localizedDescription)
        }
    }
}

/// Eine Limit-Zeile: Prozent, ruhiger Balken, wann es wieder bei null anfängt.
private struct LimitRow: View {
    let title: String
    let window: Server.ClaudeWindow
    let now: Date
    let weekly: Bool

    var body: some View {
        let reset = Date(timeIntervalSince1970: window.resetsAt / 1000)
        let over = reset <= now
        let pct = over ? 0 : min(max(window.pct, 0), 100)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(DS.ink)
                Spacer(minLength: 0)
                Text("\(Int(pct.rounded())) %")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.ink)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(DS.field)
                    Capsule().fill(pct >= 85 ? Color(hex: 0xE0A458) : Store.shared.theme.accent)
                        .frame(width: max(6, geo.size.width * pct / 100))
                }
            }
            .frame(height: 8)
            .animation(.easeOut(duration: 0.4), value: pct)
            Text(over ? "Schon wieder frei" : ClaudeTime.reset(reset, now: now, weekly: weekly))
                .font(.system(size: 13)).foregroundStyle(DS.muted)
        }
    }
}

enum ClaudeTime {
    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "HH:mm"
        return f
    }()
    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEE, d.M."
        return f
    }()

    /// „wieder frei um 17:10 (in 1 Std 57 Min)“ bzw. „wieder frei Fr, 9.10. um 13:00“
    static func reset(_ date: Date, now: Date, weekly: Bool) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        let rest = minutes >= 60 ? "\(minutes / 60) Std \(minutes % 60) Min" : "\(minutes) Min"
        if Calendar.current.isDate(date, inSameDayAs: now) {
            return "Wieder frei um \(clock.string(from: date)) (in \(rest))"
        }
        if weekly || minutes >= 24 * 60 {
            let days = minutes / (24 * 60)
            return "Wieder frei \(day.string(from: date)) um \(clock.string(from: date))" + (days >= 1 ? " (in \(days) \(days == 1 ? "Tag" : "Tagen"))" : "")
        }
        return "Wieder frei morgen um \(clock.string(from: date)) (in \(rest))"
    }

    static func ago(_ date: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "gerade eben" }
        if minutes < 60 { return "vor \(minutes) Min" }
        if minutes < 24 * 60 { return "vor \(minutes / 60) Std" }
        return "vom \(day.string(from: date))"
    }
}
