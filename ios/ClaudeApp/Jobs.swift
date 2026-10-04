import SwiftUI
import UserNotifications

/// Der Auftrag, an dem Claude gerade arbeitet (oder zuletzt gearbeitet hat). Es läuft immer nur einer;
/// die App fragt alle paar Sekunden nach, was Claude macht. Der Auftrag läuft auf dem Server weiter,
/// auch wenn die App zu ist.
@MainActor
final class Jobs: ObservableObject {
    static let shared = Jobs()

    @Published private(set) var current: Job?
    @Published private(set) var sending = false
    private var polling: Task<Void, Never>?
    var visibleJobId: String?

    func show(_ id: String) async {
        guard let fresh = try? await Api.shared.job(id) else { return }
        current = fresh
        if fresh.running { startPolling() }
    }

    func start(project: String, prompt: String, feedbackIds: [Int], resume: Bool) async throws -> Job {
        sending = true
        defer { sending = false }
        let job = try await Api.shared.startJob(project: project, prompt: prompt, feedbackIds: feedbackIds, resume: resume)
        withAnimation(.easeOut(duration: 0.25)) { current = job }
        startPolling()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        return job
    }

    func stop() async {
        guard let id = current?.id else { return }
        if let fresh = try? await Api.shared.stopJob(id) { withAnimation { current = fresh } }
    }

    private func startPolling() {
        guard polling == nil else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                let active = UIApplication.shared.applicationState == .active
                try? await Task.sleep(nanoseconds: active ? 3_000_000_000 : 10_000_000_000)
                guard let self, let id = self.current?.id else { break }
                guard let fresh = try? await Api.shared.job(id) else { continue }
                withAnimation(.easeOut(duration: 0.2)) { self.current = fresh }
                if !fresh.running {
                    self.finished(fresh)
                    break
                }
            }
            self?.polling = nil
        }
    }

    private func finished(_ job: Job) {
        UINotificationFeedbackGenerator().notificationOccurred(job.status == "done" ? .success : .warning)
        guard UIApplication.shared.applicationState != .active || visibleJobId != job.id else { return }
        let content = UNMutableNotificationContent()
        content.title = job.status == "done" ? "Claude ist fertig" : "Claude hat aufgehört"
        content.body = String((job.events.last(where: { $0.kind == "text" })?.text ?? "").prefix(180))
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "job-\(job.id)", content: content, trigger: nil))
    }
}

/// Ein Auftrag in voller Länge: Verlauf, Stopp, Weiterschreiben im selben Gespräch.
struct JobView: View {
    let jobId: String
    @ObservedObject private var jobs = Jobs.shared
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var job: Job? { jobs.current?.id == jobId ? jobs.current : nil }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let job {
                        Transcript(job: job)
                    } else {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                    }
                    Color.clear.frame(height: 1).id("ende")
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: job?.events.count ?? 0) { _ in
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("ende", anchor: .bottom) }
            }
            .onAppear { proxy.scrollTo("ende", anchor: .bottom) }
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(projectLabel)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            jobs.visibleJobId = jobId
            if job == nil || job?.running == true { await jobs.show(jobId) }
        }
        .onDisappear { if jobs.visibleJobId == jobId { jobs.visibleJobId = nil } }
    }

    private var projectLabel: String {
        switch job?.project {
        case "fakester": return "Fakester"
        case "dopa": return "Dopa"
        default: return "Auftrag"
        }
    }

    @ViewBuilder private var bottomBar: some View {
        if let job {
            VStack(spacing: 0) {
                Divider()
                if job.running {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        HStack(spacing: 10) {
                            ProgressView()
                            let minutes = Int((context.date.timeIntervalSince1970 * 1000 - job.startedAt) / 60000)
                            Text(minutes < 1 ? "Claude arbeitet …" : "Claude arbeitet … \(minutes) Min")
                                .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                            Spacer()
                            Button("Stopp", role: .destructive) { Task { await jobs.stop() } }
                                .buttonStyle(.bordered)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                    }
                } else {
                    HStack(alignment: .bottom, spacing: 10) {
                        TextField("Weiterschreiben …", text: $draft, axis: .vertical)
                            .lineLimit(1...5)
                            .focused($focused)
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .background(Theme.field, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        Button {
                            send(job)
                        } label: {
                            Image(systemName: jobs.sending ? "ellipsis" : "arrow.up")
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 36, height: 36)
                                .background(Theme.accent, in: Circle())
                                .foregroundStyle(.white)
                        }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || jobs.sending)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                }
            }
            .background(.bar)
        }
    }

    private func send(_ job: Job) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        focused = false
        Task {
            do {
                _ = try await jobs.start(project: job.project, prompt: text, feedbackIds: [], resume: job.sessionId != nil)
                draft = ""
            } catch {
                Toast.shared.show(error.localizedDescription)
            }
        }
    }
}

/// Verlauf: Claudes Sätze voll, Werkzeug-Schritte zusammengefasst (die letzten drei sichtbar).
struct Transcript: View {
    let job: Job

    private enum Block: Identifiable {
        case you(Int, String)
        case text(Int, String)
        case tools(Int, [JobEvent])
        case error(Int, String)
        var id: Int {
            switch self {
            case .you(let i, _), .text(let i, _), .tools(let i, _), .error(let i, _): return i
            }
        }
    }

    private var blocks: [Block] {
        var out: [Block] = []
        var run: [JobEvent] = []
        var runStart = 0
        func flush() { if !run.isEmpty { out.append(.tools(runStart, run)); run = [] } }
        for (i, e) in job.events.enumerated() {
            if e.kind == "tool" {
                if run.isEmpty { runStart = i }
                run.append(e)
                continue
            }
            flush()
            switch e.kind {
            case "you": out.append(.you(i, e.text ?? ""))
            case "text": out.append(.text(i, e.text ?? ""))
            default: out.append(.error(i, e.text ?? ""))
            }
        }
        flush()
        return out
    }

    var body: some View {
        let all = blocks
        VStack(alignment: .leading, spacing: 14) {
            ForEach(all) { block in
                switch block {
                case .you(_, let text):
                    HStack {
                        Spacer(minLength: 48)
                        Text(text)
                            .font(.body)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 9)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                case .text(_, let text):
                    Text(LocalizedStringKey(text))
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .tools(_, let tools):
                    ToolRun(tools: tools, live: job.running && block.id == all.last?.id)
                case .error(_, let text):
                    Label(text, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }
            if job.status == "done" {
                Text(job.minutes.map { "Fertig nach \($0) Min" } ?? "Fertig")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }
}

private struct ToolRun: View {
    let tools: [JobEvent]
    let live: Bool
    @State private var open = false

    var body: some View {
        let shown = open ? tools : Array(tools.suffix(3))
        VStack(alignment: .leading, spacing: 6) {
            if tools.count > 3 && !open {
                Button("+ \(tools.count - 3) weitere Schritte") { withAnimation { open = true } }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .buttonStyle(.plain)
            }
            ForEach(Array(shown.enumerated()), id: \.offset) { _, tool in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: Self.symbol(tool.name ?? ""))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    Text(tool.detail?.isEmpty == false ? tool.detail! : (tool.name ?? ""))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.field.opacity(live ? 1 : 0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    static func symbol(_ name: String) -> String {
        switch name {
        case "Bash": return "terminal"
        case "Edit", "MultiEdit", "Write": return "pencil"
        case "Read": return "doc.text"
        case "Grep", "Glob": return "magnifyingglass"
        case "WebSearch", "WebFetch": return "globe"
        case "TodoWrite": return "checklist"
        default: return "gearshape"
        }
    }
}
