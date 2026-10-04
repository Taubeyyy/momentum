import Foundation
import UIKit

/// Verbindung zur Werkbank auf dopa.taubey.com (hub.js). Anmeldung mit dem Dopa-Konto des Besitzers.
@MainActor
final class Api: ObservableObject {
    static let shared = Api()
    static let base = "https://dopa.taubey.com"

    @Published private(set) var token: String?
    @Published private(set) var email: String?
    private let defaults = UserDefaults.standard

    private init() {
        token = defaults.string(forKey: "api.token")
        email = defaults.string(forKey: "api.email")
    }

    struct ApiError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    private struct ErrorBody: Decodable { let error: String?; let message: String? }
    private struct Empty: Encodable {}

    // MARK: Anmeldung

    func login(email: String, password: String) async throws {
        struct Body: Encodable { let email: String; let password: String }
        struct Res: Decodable { let token: String? }
        let mail = email.trimmingCharacters(in: .whitespaces)
        let res: Res = try await send("/api/auth/login", method: "POST", body: Body(email: mail, password: password), auth: false)
        guard let token = res.token else { throw ApiError(message: "Der Server hat keinen Token geschickt.") }
        self.token = token
        self.email = mail
        defaults.set(token, forKey: "api.token")
        defaults.set(mail, forKey: "api.email")
    }

    func logout() {
        token = nil
        email = nil
        defaults.removeObject(forKey: "api.token")
        defaults.removeObject(forKey: "api.email")
    }

    // MARK: Werkbank

    func overview() async throws -> Overview { try await send("/api/hub/overview") }

    func feedback(_ project: String, all: Bool = false) async throws -> [FeedbackItem] {
        let res: FeedbackList = try await send("/api/hub/projects/\(project)/feedback" + (all ? "?all=1" : ""))
        return res.items
    }

    func markFeedback(_ project: String, id: Int, note: String? = nil, reopen: Bool = false) async throws -> [FeedbackItem] {
        struct Body: Encodable { let note: String?; let reopen: Bool }
        let res: FeedbackList = try await send("/api/hub/projects/\(project)/feedback/\(id)", method: "POST",
                                               body: Body(note: note, reopen: reopen))
        return res.items
    }

    func startJob(project: String, prompt: String, feedbackIds: [Int], resume: Bool) async throws -> Job {
        struct Body: Encodable { let project: String; let prompt: String; let feedbackIds: [Int]; let resume: Bool }
        return try await send("/api/hub/jobs", method: "POST",
                              body: Body(project: project, prompt: prompt, feedbackIds: feedbackIds, resume: resume))
    }

    func job(_ id: String) async throws -> Job { try await send("/api/hub/jobs/\(id)") }

    func stopJob(_ id: String) async throws -> Job { try await send("/api/hub/jobs/\(id)/stop", method: "POST", body: Empty()) }

    func setModel(_ id: String) async throws -> ClaudeState {
        struct Body: Encodable { let model: String }
        return try await send("/api/hub/model", method: "POST", body: Body(model: id))
    }

    func refreshLimits() async throws -> ClaudeState { try await send("/api/hub/limits/refresh", method: "POST", body: Empty()) }

    func latestRelease() async throws -> Release { try await send("/api/dopa/latest?app=claude", auth: false) }

    // MARK: Netz

    private func send<T: Decodable>(_ path: String, method: String = "GET", auth: Bool = true) async throws -> T {
        try await perform(request(path, method: method, auth: auth), auth: auth)
    }

    private func send<T: Decodable, B: Encodable>(_ path: String, method: String, body: B, auth: Bool = true) async throws -> T {
        var r = request(path, method: method, auth: auth)
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONEncoder().encode(body)
        return try await perform(r, auth: auth)
    }

    private func request(_ path: String, method: String, auth: Bool) -> URLRequest {
        var r = URLRequest(url: URL(string: Self.base + path)!)
        r.httpMethod = method
        r.timeoutInterval = 70
        if auth, let token { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return r
    }

    private func perform<T: Decodable>(_ request: URLRequest, auth: Bool) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 401 && auth { logout() }
            let err = try? JSONDecoder().decode(ErrorBody.self, from: data)
            throw ApiError(message: err?.error ?? err?.message ?? "Server-Fehler (\(status))")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Modelle (wie hub.js sie schickt)

struct Overview: Decodable {
    let claude: ClaudeState
    let running: JobRef?
    let projects: [Project]
}

struct Project: Decodable, Identifiable, Hashable {
    let id: String
    let label: String
    let repo: String
    let open: Int
    let ci: CI
    let install: String?        // neueste .ipa (für TrollStore)
    let job: JobRef?

    static func == (a: Project, b: Project) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct CI: Decodable {
    let build: BuildInfo?
    let ui: UIInfo?
}
struct BuildInfo: Decodable { let run: Int; let ok: Bool; let notes: String?; let at: Double? }
struct UIInfo: Decodable { let run: Int; let ok: Bool; let at: Double? }

struct JobRef: Decodable {
    let id: String
    let project: String
    let status: String
    let startedAt: Double
    var running: Bool { status == "running" }
}

struct ClaudeWindow: Decodable { let pct: Double; let resetsAt: Double }
struct ClaudeLimits: Decodable { let fiveHour: ClaudeWindow?; let week: ClaudeWindow?; let model: String?; let at: Double? }
struct ClaudeModel: Decodable, Identifiable { let id: String; let label: String; let hint: String }
struct ClaudeState: Decodable {
    let installed: Bool
    let model: String
    let models: [ClaudeModel]
    let limits: ClaudeLimits?
    let canRefresh: Bool
}

struct FeedbackItem: Decodable, Identifiable {
    let id: Int
    let text: String
    let screen: String?
    let build: String?
    let createdAt: Double
    let doneAt: Double?
    let doneNote: String?
}
struct FeedbackList: Decodable { let items: [FeedbackItem] }

struct JobEvent: Decodable { let kind: String; let text: String?; let name: String?; let detail: String? }
struct Job: Decodable {
    let id: String
    let project: String
    let status: String          // running · done · failed · stopped
    let startedAt: Double
    let resumed: Bool
    let sessionId: String?
    let minutes: Int?
    let events: [JobEvent]
    var running: Bool { status == "running" }
}

struct Release: Decodable { let build: Int; let notes: String; let url: String? }

/// .ipa per TrollStore installieren (apple-magnifier://install?url=…).
@MainActor
func installWithTrollStore(_ url: String) {
    let encoded = url.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? url
    if let troll = URL(string: "apple-magnifier://install?url=\(encoded)") {
        UIApplication.shared.open(troll)
    }
}
