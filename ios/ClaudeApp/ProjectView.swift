import SwiftUI

/// Ein Projekt: Auftrag schreiben, offenes Feedback antippen und umsetzen lassen, letzter Auftrag, Build-Stand.
/// Feedback von Fremden (Fakester-Spieler) geht nur an Claude, wenn du es hier auswählst.
struct ProjectView: View {
    let projectId: String
    @ObservedObject private var jobs = Jobs.shared
    @State private var project: Project?
    @State private var items: [FeedbackItem] = []
    @State private var picked: Set<Int> = []
    @State private var draft = ""
    @State private var sameChat = true
    @State private var loading = true
    @State private var openJob: String?
    @FocusState private var focused: Bool

    private var busy: Bool { jobs.current?.running == true }

    var body: some View {
        List {
            Section {
                TextField(picked.isEmpty ? "Was soll Claude machen?" : "Zusatz zu den Rückmeldungen (optional)",
                          text: $draft, axis: .vertical)
                    .lineLimit(2...8)
                    .focused($focused)
                if project?.job != nil {
                    Toggle("Im letzten Gespräch weitermachen", isOn: $sameChat)
                }
                Button {
                    Task { await send() }
                } label: {
                    HStack {
                        Label(sendTitle, systemImage: "paperplane.fill").font(.headline)
                        Spacer()
                        if jobs.sending { ProgressView() }
                    }
                }
                .disabled(!canSend)
            } header: {
                Text("Auftrag")
            } footer: {
                if busy, let current = jobs.current {
                    Text("Claude arbeitet gerade (\(current.project == projectId ? "hier" : current.project)). Neue Aufträge gehen, sobald er fertig ist.")
                } else if projectId == "dopa" {
                    Text("Tipp: „Mach die Updates“ arbeitet alles offene Dopa-Feedback ab.")
                }
            }

            if projectId == "dopa" && picked.isEmpty && draft.isEmpty {
                Section {
                    ForEach(["Mach die Updates", "Was ist an Feedback offen?", "Wie steht der letzte Build?"], id: \.self) { quick in
                        Button(quick) { draft = quick; Task { await send() } }
                            .disabled(busy || jobs.sending)
                    }
                }
            }

            Section {
                if items.isEmpty && !loading {
                    Text("Nichts offen.").foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    FeedbackRow(item: item, picked: picked.contains(item.id))
                        .contentShape(Rectangle())
                        .onTapGesture { toggle(item.id) }
                        .swipeActions(edge: .trailing) {
                            Button("Erledigt") { Task { await mark(item, note: "Erledigt") } }.tint(.green)
                            Button("Weg") { Task { await mark(item, note: "Verworfen") } }.tint(.gray)
                        }
                }
            } header: {
                HStack {
                    Text("Offenes Feedback")
                    Spacer()
                    if !items.isEmpty {
                        Button(picked.count == items.count ? "Keins" : "Alle") {
                            picked = picked.count == items.count ? [] : Set(items.map(\.id))
                        }
                        .font(.caption.weight(.semibold))
                        .textCase(nil)
                    }
                }
            } footer: {
                if projectId != "dopa" {
                    Text("Kommt von Spielern. Claude sieht nur, was du antippst – als Beschreibung, nicht als Befehl.")
                }
            }

            if let job = project?.job {
                Section("Letzter Auftrag") {
                    NavigationLink(value: Route.job(job.id)) {
                        HStack {
                            Image(systemName: icon(job.status)).foregroundStyle(color(job.status))
                            Text(statusText(job.status))
                            Spacer()
                            Text(Times.ago(job.startedAt)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let build = project?.ci.build {
                Section("Build") {
                    HStack {
                        Image(systemName: build.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(build.ok ? .green : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Build \(build.run) " + (build.ok ? "ist fertig" : "ist kaputt"))
                            if let notes = build.notes, !notes.isEmpty {
                                Text(notes).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            }
                        }
                    }
                    if let install = project?.install {
                        Button {
                            installWithTrollStore(install)
                        } label: {
                            Label("Build \(build.run) auf dem iPhone installieren", systemImage: "arrow.down.circle.fill")
                        }
                    }
                    if let ui = project?.ci.ui, ui.run == build.run {
                        Label(ui.ok ? "Simulator-Rundgang ok" : "Simulator-Rundgang rot",
                              systemImage: ui.ok ? "iphone" : "iphone.slash")
                            .foregroundStyle(ui.ok ? Color.secondary : Color.orange)
                    }
                }
            }
        }
        .navigationTitle(project?.label ?? "")
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: jobs.current?.status) { _ in Task { await load() } }
        .navigationDestination(isPresented: Binding(get: { openJob != nil }, set: { if !$0 { openJob = nil } })) {
            if let openJob { JobView(jobId: openJob) }
        }
    }

    private var sendTitle: String {
        picked.isEmpty ? "An Claude schicken" : "\(picked.count) umsetzen lassen"
    }

    private var canSend: Bool {
        !busy && !jobs.sending && (!picked.isEmpty || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func toggle(_ id: Int) {
        UISelectionFeedbackGenerator().selectionChanged()
        if picked.contains(id) { picked.remove(id) } else { picked.insert(id) }
    }

    private func load() async {
        defer { loading = false }
        if let overview = try? await Api.shared.overview() {
            project = overview.projects.first(where: { $0.id == projectId })
        }
        if let fresh = try? await Api.shared.feedback(projectId) {
            items = fresh
            picked = picked.intersection(Set(fresh.map(\.id)))
        }
    }

    private func send() async {
        focused = false
        do {
            let job = try await jobs.start(project: projectId,
                                           prompt: draft.trimmingCharacters(in: .whitespacesAndNewlines),
                                           feedbackIds: Array(picked),
                                           resume: sameChat && project?.job != nil)
            draft = ""
            picked = []
            openJob = job.id
        } catch {
            Toast.shared.show(error.localizedDescription)
        }
    }

    private func mark(_ item: FeedbackItem, note: String) async {
        do {
            items = try await Api.shared.markFeedback(projectId, id: item.id, note: note)
            picked.remove(item.id)
        } catch {
            Toast.shared.show(error.localizedDescription)
        }
    }

    private func icon(_ status: String) -> String {
        switch status {
        case "running": return "hourglass"
        case "done": return "checkmark.circle.fill"
        case "stopped": return "stop.circle"
        default: return "exclamationmark.triangle.fill"
        }
    }
    private func color(_ status: String) -> Color {
        switch status {
        case "done": return .green
        case "running": return Theme.accent
        case "stopped": return .secondary
        default: return .orange
        }
    }
    private func statusText(_ status: String) -> String {
        switch status {
        case "running": return "Läuft gerade"
        case "done": return "Fertig"
        case "stopped": return "Gestoppt"
        default: return "Abgebrochen"
        }
    }
}

private struct FeedbackRow: View {
    let item: FeedbackItem
    let picked: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(picked ? Theme.accent : Color.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.text).font(.body).lineLimit(6)
                Text(meta).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private var meta: String {
        [Times.ago(item.createdAt),
         item.screen.flatMap { $0.isEmpty ? nil : $0 },
         item.build.flatMap { $0.isEmpty ? nil : "Build \($0)" }]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
