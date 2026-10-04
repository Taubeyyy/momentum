import SwiftUI

/// Startseite: läuft gerade etwas? Projekte mit offenem Feedback und Build-Stand. Limits und Modell.
struct HomeView: View {
    @ObservedObject private var jobs = Jobs.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var overview: Overview?
    @State private var error: String?
    @State private var refreshing = false
    @State private var savingModel = false
    @State private var update: Release?

    var body: some View {
        List {
            if let update, let url = update.url {
                Section {
                    UpdateRow(release: update, url: url)
                }
            }

            if let running = runningRef {
                Section {
                    NavigationLink(value: Route.job(running.id)) {
                        HStack(spacing: 12) {
                            ProgressView()
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Claude arbeitet").font(.headline)
                                Text(label(for: running.project)).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if let overview {
                Section("Projekte") {
                    ForEach(overview.projects) { project in
                        NavigationLink(value: Route.project(project.id)) {
                            ProjectRow(project: project)
                        }
                    }
                }
                limitsSection(overview.claude)
                modelSection(overview.claude)
            } else if let error {
                Section {
                    Text(error).foregroundStyle(.secondary)
                    Button("Nochmal versuchen") { Task { await load() } }
                }
            } else {
                Section { HStack { Spacer(); ProgressView(); Spacer() } }
            }

            Section {
                Button("Abmelden", role: .destructive) { Api.shared.logout() }
            } footer: {
                Text("Build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?") · \(Api.shared.email ?? "")")
            }
        }
        .navigationTitle("Claude")
        .navigationDestination(for: Route.self) { route in
            switch route {
            case .project(let id): ProjectView(projectId: id)
            case .job(let id): JobView(jobId: id)
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { Task { await load() } }
        }
        .onChange(of: jobs.current?.status) { _ in Task { await load() } }
    }

    private var runningRef: JobRef? {
        if let job = jobs.current, job.running {
            return JobRef(id: job.id, project: job.project, status: job.status, startedAt: job.startedAt)
        }
        return overview?.running
    }

    private func label(for project: String) -> String {
        overview?.projects.first(where: { $0.id == project })?.label ?? project
    }

    // MARK: Limits

    @ViewBuilder private func limitsSection(_ claude: ClaudeState) -> some View {
        Section {
            if let limits = claude.limits {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(alignment: .leading, spacing: 14) {
                        if let five = limits.fiveHour { LimitRow(title: "5 Stunden", window: five, now: context.date) }
                        if let week = limits.week { LimitRow(title: "Woche", window: week, now: context.date) }
                    }
                    .padding(.vertical, 6)
                }
            } else {
                Text("Noch keine Zahlen.").foregroundStyle(.secondary)
            }
            if claude.canRefresh {
                Button {
                    Task { await refreshLimits() }
                } label: {
                    HStack {
                        Text(refreshing ? "Frage nach …" : "Limits aktualisieren")
                        Spacer()
                        if refreshing { ProgressView() }
                    }
                }
                .disabled(refreshing)
            }
        } header: {
            Text("Limits")
        } footer: {
            if let limits = claude.limits {
                Text("Stand \(Times.ago(limits.at))" + (limits.model.map { " · zuletzt \($0)" } ?? ""))
            }
        }
    }

    // MARK: Modell

    @ViewBuilder private func modelSection(_ claude: ClaudeState) -> some View {
        Section {
            Picker("Modell", selection: Binding(
                get: { claude.model },
                set: { id in Task { await setModel(id) } }
            )) {
                ForEach(claude.models) { model in
                    Text(model.label).tag(model.id)
                }
            }
            .disabled(savingModel)
        } footer: {
            Text((claude.models.first(where: { $0.id == claude.model })?.hint ?? "") + ". Gilt für neue Aufträge.")
        }
    }

    // MARK: Laden

    private func load() async {
        do {
            let fresh = try await Api.shared.overview()
            withAnimation(.easeOut(duration: 0.2)) { overview = fresh; error = nil }
            if let running = fresh.running, Jobs.shared.current?.id != running.id {
                await Jobs.shared.show(running.id)
            }
        } catch {
            if overview == nil { self.error = error.localizedDescription }
        }
        if let release = try? await Api.shared.latestRelease(),
           let mine = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""),
           release.build > mine {
            update = release
        }
    }

    private func refreshLimits() async {
        refreshing = true
        defer { refreshing = false }
        do {
            _ = try await Api.shared.refreshLimits()
            await load()
        } catch {
            Toast.shared.show(error.localizedDescription)
        }
    }

    private func setModel(_ id: String) async {
        savingModel = true
        defer { savingModel = false }
        do {
            _ = try await Api.shared.setModel(id)
            await load()
        } catch {
            Toast.shared.show(error.localizedDescription)
        }
    }
}

enum Route: Hashable {
    case project(String)
    case job(String)
}

private struct ProjectRow: View {
    let project: Project

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: project.id == "fakester" ? "music.note" : "brain.head.profile")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(project.id == "fakester" ? Color.pink : Color.purple, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(project.label).font(.headline)
                Text(buildLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if project.open > 0 {
                Text("\(project.open)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.25), in: Capsule())
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.vertical, 4)
    }

    private var buildLine: String {
        guard let build = project.ci.build else { return "Noch kein Build gemeldet" }
        var line = "Build \(build.run) " + (build.ok ? "ok" : "kaputt")
        if let ui = project.ci.ui, ui.run == build.run { line += ui.ok ? " · Test ok" : " · Test rot" }
        if let at = build.at { line += " · \(Times.ago(at))" }
        return line
    }
}

private struct LimitRow: View {
    let title: String
    let window: ClaudeWindow
    let now: Date

    var body: some View {
        let reset = Date(timeIntervalSince1970: window.resetsAt / 1000)
        let pct = reset <= now ? 0 : min(max(window.pct, 0), 100)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(pct.rounded())) %").font(.title3.weight(.bold).monospacedDigit())
            }
            ProgressView(value: pct, total: 100)
                .tint(pct >= 85 ? .orange : Theme.accent)
            Text(Times.reset(reset, now: now)).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct UpdateRow: View {
    let release: Release
    let url: String

    var body: some View {
        Button {
            installWithTrollStore(url)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill").font(.title2).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Build \(release.build) ist da").font(.headline).foregroundStyle(.primary)
                    if !release.notes.isEmpty {
                        Text(release.notes).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
        }
    }
}
