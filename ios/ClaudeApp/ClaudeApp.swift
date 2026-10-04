import SwiftUI

/// Claude-App: steuert Claude auf dem eigenen Server – Projekte (Dopa, Fakester), Feedback auswählen,
/// Aufträge schicken und live mitlesen, Limits und Modell. Nur für den Besitzer.
@main
struct ClaudeRemoteApp: App {
    @StateObject private var api = Api.shared

    init() {
        let nav = UINavigationBarAppearance()
        nav.configureWithDefaultBackground()
        UINavigationBar.appearance().scrollEdgeAppearance = nav
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if api.token == nil {
                    LoginView()
                } else {
                    NavigationStack { HomeView() }
                }
            }
            .tint(Theme.accent)
            .preferredColorScheme(.dark)
            .overlay(alignment: .top) { ToastView() }
        }
    }
}

enum Theme {
    static let accent = Color(red: 0.85, green: 0.47, blue: 0.34)        // warmes Orange
    static let background = Color(UIColor.systemBackground)
    static let field = Color(UIColor.secondarySystemBackground)
}

// MARK: - Anmeldung

struct LoginView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("E-Mail", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Passwort", text: $password)
                        .textContentType(.password)
                } footer: {
                    Text("Dein Dopa-Konto. Die App spricht nur mit deinem eigenen Server.")
                }
                if let error {
                    Section { Text(error).foregroundStyle(.orange) }
                }
                Section {
                    Button {
                        Task { await login() }
                    } label: {
                        HStack {
                            Text("Anmelden")
                            if busy { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(email.isEmpty || password.isEmpty || busy)
                }
            }
            .navigationTitle("Claude")
        }
    }

    private func login() async {
        busy = true
        defer { busy = false }
        do {
            try await Api.shared.login(email: email, password: password)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Kurze Meldungen oben

@MainActor
final class Toast: ObservableObject {
    static let shared = Toast()
    @Published private(set) var text: String?
    private var hide: Task<Void, Never>?

    func show(_ text: String) {
        withAnimation(.spring(response: 0.35)) { self.text = text }
        hide?.cancel()
        hide = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut) { self.text = nil }
        }
    }
}

struct ToastView: View {
    @ObservedObject private var toast = Toast.shared

    var body: some View {
        if let text = toast.text {
            Text(text)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(.thinMaterial, in: Capsule())
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// MARK: - Zeit-Texte

enum Times {
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
    static func reset(_ date: Date, now: Date) -> String {
        if date <= now { return "Schon wieder frei" }
        let minutes = Int(date.timeIntervalSince(now) / 60)
        let rest = minutes >= 60 ? "\(minutes / 60) Std \(minutes % 60) Min" : "\(minutes) Min"
        if Calendar.current.isDate(date, inSameDayAs: now) {
            return "Wieder frei um \(clock.string(from: date)) (in \(rest))"
        }
        if minutes < 24 * 60 {
            return "Wieder frei morgen um \(clock.string(from: date)) (in \(rest))"
        }
        return "Wieder frei \(day.string(from: date)) um \(clock.string(from: date))"
    }

    static func ago(_ ms: Double?, now: Date = Date()) -> String {
        guard let ms else { return "" }
        let minutes = Int(now.timeIntervalSince(Date(timeIntervalSince1970: ms / 1000)) / 60)
        if minutes < 1 { return "gerade eben" }
        if minutes < 60 { return "vor \(minutes) Min" }
        if minutes < 24 * 60 { return "vor \(minutes / 60) Std" }
        return "am \(day.string(from: Date(timeIntervalSince1970: ms / 1000)))"
    }
}
