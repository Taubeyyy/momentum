import SwiftUI
import UserNotifications

/// Aufträge an Claude auf dem Dopa-Server. Der Auftrag läuft dort weiter, auch wenn die App zu ist;
/// die App fragt alle paar Sekunden nach, was Claude gerade macht.
@MainActor
final class ClaudeJobs: ObservableObject {
    static let shared = ClaudeJobs()

    @Published private(set) var job: Server.ClaudeJob?
    @Published private(set) var sending = false
    private var polling: Task<Void, Never>?

    func load(_ id: String) async {
        if let fresh = try? await Server.shared.claudeJob(id) {
            job = fresh
            if fresh.running { startPolling() }
        }
    }

    func start(_ prompt: String, resume: Bool) async throws {
        sending = true
        defer { sending = false }
        let fresh = try await Server.shared.startClaudeJob(prompt, resume: resume)
        withAnimation(.easeOut(duration: 0.25)) { job = fresh }
        startPolling()
    }

    func stop() async {
        guard let id = job?.id else { return }
        if let fresh = try? await Server.shared.stopClaudeJob(id) { withAnimation { job = fresh } }
    }

    private func startPolling() {
        guard polling == nil else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                let visible = Router.shared.claudeVisible && UIApplication.shared.applicationState == .active
                try? await Task.sleep(nanoseconds: visible ? 3_000_000_000 : 10_000_000_000)
                guard let self, let id = self.job?.id else { break }
                guard let fresh = try? await Server.shared.claudeJob(id) else { continue }
                withAnimation(.easeOut(duration: 0.2)) { self.job = fresh }
                if !fresh.running {
                    self.finished(fresh)
                    break
                }
            }
            self?.polling = nil
        }
    }

    private func finished(_ job: Server.ClaudeJob) {
        UINotificationFeedbackGenerator().notificationOccurred(job.status == "done" ? .success : .warning)
        guard UIApplication.shared.applicationState != .active || !Router.shared.claudeVisible else { return }
        let content = UNMutableNotificationContent()
        content.title = job.status == "done" ? "Claude ist fertig" : "Claude hat aufgehört"
        let last = job.events.last(where: { $0.kind == "text" })?.text ?? ""
        content.body = String(last.prefix(180))
        content.sound = .default
        content.userInfo = ["route": "claude"]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "claude-\(job.id)", content: content, trigger: nil))
    }
}

/// Auftragsfeld + Verlauf des aktuellen Auftrags im Claude-Tab.
struct ClaudeJobCard: View {
    @ObservedObject private var jobs = ClaudeJobs.shared
    @State private var draft = ""
    @State private var sameChat = true
    @FocusState private var focused: Bool

    private static let quick = ["Mach die Updates", "Was ist an Feedback offen?", "Wie steht der letzte Build?"]

    var body: some View {
        Card(title: "Auftrag an Claude", symbol: "sparkles") {
            if let job = jobs.job {
                JobTranscript(job: job)
            }
            if jobs.job?.running == true {
                runningBar
            } else {
                compose
            }
        }
    }

    private var canContinue: Bool {
        guard let job = jobs.job, job.sessionId != nil else { return false }
        return Date().timeIntervalSince1970 * 1000 - job.startedAt < 12 * 3600 * 1000
    }

    private var compose: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(canContinue && sameChat ? "Weiterschreiben …" : "Was soll Claude machen?", text: $draft, axis: .vertical)
                .lineLimit(1...6)
                .focused($focused)
                .font(.system(size: 16))
                .padding(12)
                .background(DS.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(DS.fieldBorder))

            if draft.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Self.quick, id: \.self) { text in
                            Button(text) { send(text) }.buttonStyle(PillButtonStyle())
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            HStack(spacing: 10) {
                if canContinue {
                    Toggle(isOn: $sameChat) {
                        Text("Im selben Gespräch").font(.system(size: 13)).foregroundStyle(DS.muted)
                    }
                    .toggleStyle(.switch)
                    .tint(Store.shared.theme.accent)
                    .fixedSize()
                }
                Spacer(minLength: 0)
                Button {
                    send(draft)
                } label: {
                    HStack(spacing: 6) {
                        if jobs.sending { ProgressView().controlSize(.small).tint(.white) }
                        Text("Schicken")
                    }
                }
                .buttonStyle(PillButtonStyle(prominent: true))
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || jobs.sending)
            }
        }
    }

    private var runningBar: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 10) {
                ProgressView()
                let minutes = Int((context.date.timeIntervalSince1970 * 1000 - (jobs.job?.startedAt ?? 0)) / 60000)
                Text(minutes < 1 ? "Claude arbeitet …" : "Claude arbeitet … \(minutes) Min")
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(DS.muted)
                Spacer(minLength: 0)
                Button("Stopp") { Task { await jobs.stop() } }
                    .buttonStyle(PillButtonStyle())
            }
        }
    }

    private func send(_ text: String) {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !jobs.sending else { return }
        focused = false
        let resume = canContinue && sameChat
        Task {
            do {
                try await jobs.start(prompt, resume: resume)
                draft = ""
            } catch {
                Toaster.shared.show(error.localizedDescription)
            }
        }
    }
}

/// Verlauf eines Auftrags: Claudes Sätze voll, Werkzeug-Schritte zusammengefasst (die letzten drei sichtbar).
private struct JobTranscript: View {
    let job: Server.ClaudeJob

    private enum Block: Identifiable {
        case you(Int, String)
        case text(Int, String)
        case tools(Int, [Server.ClaudeEvent])
        case error(Int, String)
        var id: Int {
            switch self {
            case .you(let i, _), .text(let i, _), .tools(let i, _), .error(let i, _): return i
            }
        }
    }

    private var blocks: [Block] {
        var out: [Block] = []
        var run: [Server.ClaudeEvent] = []
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
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks) { block in
                switch block {
                case .you(_, let text):
                    HStack {
                        Spacer(minLength: 40)
                        Text(text)
                            .font(.system(size: 15))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Store.shared.theme.accent.opacity(0.85), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                case .text(_, let text):
                    Text(LocalizedStringKey(text))
                        .font(.system(size: 15))
                        .foregroundStyle(DS.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .tools(_, let tools):
                    ToolRun(tools: tools, live: job.running && block.id == blocks.last?.id)
                case .error(_, let text):
                    Text(text).font(.system(size: 14)).foregroundStyle(Color(hex: 0xE0A458))
                }
            }
            if !job.running, job.status == "done" {
                Text(job.minutes.map { "Fertig nach \($0) Min" } ?? "Fertig")
                    .font(.system(size: 12)).foregroundStyle(DS.faint)
            }
        }
        .padding(.bottom, 4)
    }
}

private struct ToolRun: View {
    let tools: [Server.ClaudeEvent]
    let live: Bool
    @State private var open = false

    var body: some View {
        let shown = open ? tools : Array(tools.suffix(3))
        VStack(alignment: .leading, spacing: 5) {
            if tools.count > 3 && !open {
                Button("+ \(tools.count - 3) weitere Schritte") { withAnimation { open = true } }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.purpleMuted)
                    .buttonStyle(.plain)
            }
            ForEach(Array(shown.enumerated()), id: \.offset) { _, tool in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Image(systemName: Self.symbol(tool.name ?? ""))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.faint)
                        .frame(width: 14)
                    Text(tool.detail?.isEmpty == false ? tool.detail! : (tool.name ?? ""))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(DS.muted)
                        .lineLimit(2)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.field.opacity(live ? 1 : 0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    static func symbol(_ name: String) -> String {
        switch name {
        case "Bash": "terminal"
        case "Edit", "MultiEdit", "Write": "pencil"
        case "Read": "doc.text"
        case "Grep", "Glob": "magnifyingglass"
        case "WebSearch", "WebFetch": "globe"
        case "TodoWrite": "checklist"
        default: "gearshape"
        }
    }
}
