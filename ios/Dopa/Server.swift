import Foundation

/// Verbindung zu dopa.taubey.com: Anmeldung, KI, Feedback, Backup.
/// Die App funktioniert komplett ohne – alles hier ist ein Zusatz.
@MainActor
final class Server: ObservableObject {
    static let shared = Server()
    static let baseURL = URL(string: "https://dopa.taubey.com")!

    @Published private(set) var token: String?
    @Published private(set) var email: String?
    @Published private(set) var aiAvailable = false
    @Published private(set) var aiLabel: String?
    @Published private(set) var backupAt: Date?

    private let defaults = UserDefaults.standard

    var isConnected: Bool { token != nil }

    private init() {
        token = defaults.string(forKey: "server.token")
        email = defaults.string(forKey: "server.email")
        aiAvailable = defaults.bool(forKey: "server.ai")
        aiLabel = defaults.string(forKey: "server.aiLabel")
    }

    enum ServerError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
    }

    // MARK: Anmeldung

    struct AuthResponse: Decodable { let token: String? }

    func login(email: String, password: String, create: Bool) async throws {
        let body = ["email": email.trimmingCharacters(in: .whitespaces), "password": password]
        let res: AuthResponse = try await call(create ? "/api/auth/register" : "/api/auth/login",
                                               method: "POST", body: body, auth: false)
        guard let token = res.token else { throw ServerError.message("Der Server hat keinen Token geschickt.") }
        self.token = token
        self.email = body["email"]
        defaults.set(token, forKey: "server.token")
        defaults.set(body["email"], forKey: "server.email")
        await refreshStatus()
    }

    func logout() {
        token = nil
        email = nil
        aiAvailable = false
        defaults.removeObject(forKey: "server.token")
        defaults.removeObject(forKey: "server.email")
        defaults.set(false, forKey: "server.ai")
    }

    struct Status: Decodable { let ai: Bool; let ai_label: String?; let backup_at: Double? }

    func refreshStatus() async {
        guard isConnected else { return }
        guard let s: Status = try? await call("/api/dopa/status") else { return }
        aiAvailable = s.ai
        aiLabel = s.ai_label
        backupAt = s.backup_at.map { Date(timeIntervalSince1970: $0 / 1000) }
        defaults.set(s.ai, forKey: "server.ai")
        defaults.set(s.ai_label, forKey: "server.aiLabel")
    }

    // MARK: KI

    struct StepResponse: Decodable { let step: String }

    func firstStep(for title: String) async throws -> String {
        let res: StepResponse = try await call("/api/dopa/step", method: "POST", body: ["title": title])
        return res.step
    }

    struct PlanTask: Decodable, Identifiable, Hashable {
        let title: String
        let step: String
        let minutes: Int
        var id: String { title + step }
    }

    struct Plan: Decodable {
        let summary: String
        let tasks: [PlanTask]
        let note: String
    }

    func plan(from text: String, scope: String = "auto") async throws -> Plan {
        try await call("/api/dopa/plan", method: "POST", body: ["text": text, "scope": scope])
    }

    struct Aisles: Decodable { let aisles: [String: String] }

    /// Name → Gang (rawValue von ShopCategory).
    func categorize(_ names: [String]) async throws -> [String: String] {
        let res: Aisles = try await call("/api/dopa/categorize", method: "POST", body: ["items": names])
        return res.aisles
    }

    // MARK: Fotos, Screenshots, Sprache (Gemini sieht und hört mit)

    struct ImageBody: Encodable {
        let image: String
        let mime = "image/jpeg"
        var hint: String?
        var known: String?
    }

    /// Foto → wie Smart Dump (Aufgaben, Erinnerungen, Einkauf, Notizen).
    func photoDump(_ image: String, hint: String?) async throws -> Dump {
        try await call("/api/dopa/photo/dump", method: "POST", body: ImageBody(image: image, hint: hint))
    }

    struct Caption: Decodable {
        let caption: String
        let kind: String
        let task: String?           // Auftrag auf dem Foto (z. B. Zettel einer Lehrkraft) → „Auch als Aufgabe?“
        let day: Int?               // Frist in Tagen ab heute, -1 = keine
    }

    /// Notiz-Foto → kurzer Satz, was drauf ist.
    func photoCaption(_ image: String) async throws -> Caption {
        try await call("/api/dopa/photo/caption", method: "POST", body: ImageBody(image: image))
    }

    struct ScanEntry: Decodable, Hashable { let title: String; let amount: Double; let income: Bool; let date: String }
    struct ScanDebt: Decodable, Hashable { let title: String; let amount: Double; let due: String; let remaining: Int }
    struct Scan: Decodable {
        let entries: [ScanEntry]
        let debts: [ScanDebt]
        let tips: [String]
        let balance: Double?        // Kontostand, falls auf dem Screenshot (Sparkasse: große Zahl oben)
        let account: String?
    }

    /// Screenshot aus Bank/Klarna → Buchungen, offene Raten, Tipps.
    func moneyScan(_ image: String, known: String) async throws -> Scan {
        try await call("/api/dopa/money/scan", method: "POST", body: ImageBody(image: image, known: known))
    }

    // MARK: Einkauf: Prospekte und Barcode

    struct FlyerOffer: Decodable { let name: String; let price: Double; let unit: String; let note: String }
    struct FlyerScan: Decodable { let store: String; let validFrom: String; let validTo: String; let offers: [FlyerOffer] }

    /// Prospekt-Foto/Screenshot → Angebote mit Preis und Gültigkeit.
    func flyer(_ image: String) async throws -> FlyerScan {
        try await call("/api/dopa/flyer", method: "POST", body: ImageBody(image: image))
    }

    struct Product: Decodable { let found: Bool; let name: String?; let quantity: String? }

    /// Barcode (EAN) → Produktname aus Open Food Facts.
    func product(barcode: String) async throws -> Product {
        try await call("/api/dopa/barcode", method: "POST", body: ["code": barcode])
    }

    struct Tips: Decodable { let tips: [String] }

    func moneyTips(_ summary: String) async throws -> [String] {
        let res: Tips = try await call("/api/dopa/money/tips", method: "POST", body: ["summary": summary])
        return res.tips
    }

    struct VoiceBody: Encodable { let audio: String; let format: String; let hints: [String] }
    struct Transcript: Decodable { let transcript: String }

    /// Sprachaufnahme (WAV) → Gemini schreibt genau ab.
    func transcribe(wav: Data, hints: [String]) async throws -> String {
        let res: Transcript = try await call("/api/dopa/voice", method: "POST",
                                             body: VoiceBody(audio: wav.base64EncodedString(), format: "wav", hints: hints))
        return res.transcript
    }

    struct Release: Decodable {
        let build: Int
        let notes: String
        let url: String?
        let page: String?
    }

    /// Neuester Build auf dem Dopa-Server (ohne Login).
    func latestRelease() async throws -> Release {
        try await call("/api/dopa/latest", auth: false)
    }

    struct BuildNote: Decodable, Identifiable {
        let build: Int
        let notes: String
        let at: Double
        var id: Int { build }
        var date: Date? { at > 0 ? Date(timeIntervalSince1970: at / 1000) : nil }
    }
    struct Changelog: Decodable { let builds: [BuildNote] }

    /// „Was ist neu“: alle Builds mit ihrem Update-Text (ohne Login).
    func changelog() async throws -> [BuildNote] {
        let res: Changelog = try await call("/api/dopa/changelog", auth: false)
        return res.builds
    }

    struct DayLines: Decodable {
        let briefing: String; let midday: String; let afternoon: String; let evening: String; let night: String
        let nudges: [String]; let meals: [String]
    }
    struct DayBody: Encodable { let name: String; let level: Int; let context: [String] }

    /// Dots Sätze für heute.
    func companionDay(name: String, level: Int, context: [String]) async throws -> CompanionScript {
        let res: DayLines = try await call("/api/dopa/day", method: "POST", body: DayBody(name: name, level: level, context: context))
        return CompanionScript(day: "", briefing: res.briefing, midday: res.midday, afternoon: res.afternoon,
                               evening: res.evening, night: res.night, nudges: res.nudges, meals: res.meals)
    }

    struct Prices: Decodable { let prices: [String: Double] }

    /// Name → ungefährer Preis in Euro (nur was Gemini sinnvoll schätzen konnte).
    struct PricesBody: Encodable { let items: [String]; let known: String }

    /// `known` = deine eigenen Preise („Milch 1,09 €; Butter 1,79 €“) – die KI schätzt daran ausgerichtet.
    func prices(_ names: [String], known: String = "") async throws -> [String: Double] {
        let res: Prices = try await call("/api/dopa/prices", method: "POST", body: PricesBody(items: names, known: known))
        return res.prices
    }

    struct NextTaskIn: Encodable { let id: String; let title: String; let step: String; let age_days: Int }
    struct NextRequest: Encodable { let tasks: [NextTaskIn]; let energy: String; let focus_today: Int }

    struct NextPick: Decodable {
        let id: String
        let title: String
        let why: String
        let first_move: String
        let minutes: Int
    }

    func whatNow(tasks: [TaskItem], energy: String, focusToday: Int) async throws -> NextPick {
        let now = Date()
        let list = tasks.prefix(40).map {
            NextTaskIn(id: $0.id.uuidString, title: $0.title, step: $0.firstStep,
                       age_days: max(0, Int(now.timeIntervalSince($0.createdAt) / 86_400)))
        }
        return try await call("/api/dopa/next", method: "POST",
                              body: NextRequest(tasks: Array(list), energy: energy, focus_today: focusToday))
    }

    struct DumpTask: Decodable, Hashable { let title: String; let step: String; let minutes: Int; let day: Int }
    struct DumpReminder: Decodable, Hashable { let title: String; let time: String; let day: Int }
    struct DumpBlock: Decodable, Hashable { let start: String; let title: String; let step: String; let minutes: Int; let day: Int }

    struct Dump: Decodable {
        let summary: String
        let tasks: [DumpTask]
        let reminders: [DumpReminder]
        let shopping: [String]
        let notes: [String]
        let schedule: [DumpBlock]
    }

    /// Smart Dump: alles Erzählte einsortiert – Aufgaben, Zeitplan, Erinnerungen, Einkauf, Merken.
    func dump(_ text: String) async throws -> Dump {
        try await call("/api/dopa/dump", method: "POST", body: ["text": text])
    }

    // MARK: Worte, Dot, Zerlegen

    struct Interpretation: Decodable {
        let literal: String
        let tone: String
        let temperature: Int
        let overthinking: String
        let reply: String
    }

    func interpret(_ text: String) async throws -> Interpretation {
        try await call("/api/dopa/interpret", method: "POST", body: ["text": text])
    }

    struct Rewrite: Decodable { let result: String; let changed: String }

    func rewrite(_ text: String, mode: String) async throws -> Rewrite {
        try await call("/api/dopa/rewrite", method: "POST", body: ["text": text, "mode": mode])
    }

    // MARK: Dot-Gespräch

    struct ChatLine: Encodable { let fromDot: Bool; let text: String }
    struct ChatBody: Encodable {
        let message: String
        let history: [ChatLine]
        let context: String
        let name: String
        let level: Int
        let image: String?          // Foto als Base64-JPEG (optional)
        let mime: String?
    }
    struct ChatEntry: Decodable {
        let title: String
        let day: Int?
        let time: String?
        let minutes: Int?
    }
    struct ChatAction: Decodable {
        let kind: String
        let title: String
        let step: String?
        let time: String?
        let day: Int?
        let minutes: Int?
        let items: [String]?
        let entries: [ChatEntry]?
        let place: String?
        let key: String?            // bei „edit“: was geändert wird
    }
    struct ChatReply: Decodable {
        let answer: String
        let actions: [ChatAction]?
        let suggestions: [String]?
    }

    func chat(_ message: String, history: [ChatLine], context: String, name: String, level: Int,
              image: String? = nil) async throws -> ChatReply {
        try await call("/api/dopa/chat", method: "POST",
                       body: ChatBody(message: message, history: history, context: context, name: name, level: level,
                                      image: image, mime: image == nil ? nil : "image/jpeg"))
    }

    struct BreakdownStep: Decodable { let title: String; let minutes: Int }
    struct Breakdown: Decodable { let steps: [BreakdownStep]; let opener: String }
    struct BreakdownBody: Encodable { let title: String; let resolution: Int }

    func breakdown(_ title: String, resolution: Int) async throws -> Breakdown {
        try await call("/api/dopa/breakdown", method: "POST", body: BreakdownBody(title: title, resolution: resolution))
    }

    // MARK: Feedback

    struct FeedbackOut: Encodable {
        let id: String
        let text: String
        let screen: String
        let app_version: String
        let created_at: Double
    }

    struct Accepted: Decodable { let accepted: [String] }

    func sendFeedback(_ items: [FeedbackItem]) async throws -> [String] {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let out = items.map {
            FeedbackOut(id: $0.id.uuidString, text: $0.text, screen: $0.screen, app_version: version,
                        created_at: $0.createdAt.timeIntervalSince1970 * 1000)
        }
        let res: Accepted = try await call("/api/dopa/feedback", method: "POST", body: ["items": out])
        return res.accepted
    }

    struct FeedbackStatus: Decodable, Identifiable {
        let id: String
        let text: String
        let done_at: Double?
        let done_note: String
    }

    struct FeedbackList: Decodable { let items: [FeedbackStatus] }

    func feedbackStatus() async throws -> [FeedbackStatus] {
        let res: FeedbackList = try await call("/api/dopa/feedback")
        return res.items
    }

    // MARK: Backup

    struct BackupSaved: Decodable { let updated_at: Double }

    func uploadBackup(_ data: AppData) async throws {
        let res: BackupSaved = try await call("/api/dopa/backup", method: "PUT", body: data)
        backupAt = Date(timeIntervalSince1970: res.updated_at / 1000)
    }

    struct BackupIn: Decodable { let updated_at: Double; let data: AppData }

    func downloadBackup() async throws -> AppData {
        let res: BackupIn = try await call("/api/dopa/backup")
        return res.data
    }

    // MARK: HTTP

    private struct ErrorBody: Decodable { let error: String?; let message: String? }

    private func call<T: Decodable>(_ path: String, method: String = "GET", auth: Bool = true) async throws -> T {
        try await send(request(path, method: method, auth: auth), auth: auth)
    }

    private func call<T: Decodable, B: Encodable>(_ path: String, method: String, body: B,
                                                  auth: Bool = true) async throws -> T {
        var r = request(path, method: method, auth: auth)
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONEncoder().encode(body)
        return try await send(r, auth: auth)
    }

    private func request(_ path: String, method: String, auth: Bool) -> URLRequest {
        var r = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        r.httpMethod = method
        r.timeoutInterval = 60
        if auth, let token { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return r
    }

    private func send<T: Decodable>(_ request: URLRequest, auth: Bool) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 401 && auth { logout() }
            let err = try? JSONDecoder().decode(ErrorBody.self, from: data)
            throw ServerError.message(err?.message ?? err?.error ?? "Server-Fehler (\(status))")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
