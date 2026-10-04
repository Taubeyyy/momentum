import SwiftUI
import UIKit

/// Update-Info mit direktem Link (Feedback #32): Der Build-Runner legt jede neue .ipa auf den
/// Dopa-Server; die App fragt nach und installiert per TrollStore-Link mit einem Tipp.
@MainActor
final class Updates: ObservableObject {
    static let shared = Updates()

    @Published private(set) var latest: Server.Release?
    private var lastCheck = Date.distantPast

    var currentBuild: Int { Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0 }
    var currentVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }
    var available: Bool { (latest?.build ?? 0) > currentBuild }

    /// Beim Öffnen der App – höchstens alle 30 Minuten (oder sofort mit `force`).
    func check(force: Bool = false) async {
        guard force || Date().timeIntervalSince(lastCheck) > 1800 else { return }
        lastCheck = Date()
        if let release = try? await Server.shared.latestRelease() { latest = release }
    }

    /// Direkt in TrollStore installieren; klappt das nicht, die Release-Seite öffnen.
    func install() {
        guard let latest else { return }
        let page = URL(string: latest.page ?? "https://github.com/Taubeyyy/momentum/releases/latest")
        guard let url = latest.url,
              let encoded = url.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let troll = URL(string: "apple-magnifier://install?url=\(encoded)") else {
            if let page { UIApplication.shared.open(page) }
            return
        }
        UIApplication.shared.open(troll) { opened in
            if !opened, let page { UIApplication.shared.open(page) }
        }
    }
}

/// Hinweis oben in „Heute“, wenn ein neuer Build da ist.
struct UpdateBanner: View {
    @ObservedObject private var updates = Updates.shared

    var body: some View {
        if updates.available, let latest = updates.latest {
            Panel(highlighted: true) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(DS.purpleMuted)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Build \(latest.build) ist da").font(.system(size: 15, weight: .semibold)).foregroundStyle(DS.ink)
                        if !latest.notes.isEmpty {
                            Text(latest.notes).font(.system(size: 12)).foregroundStyle(DS.muted).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                    Button("Installieren") { updates.install() }
                        .buttonStyle(PillButtonStyle(prominent: true))
                }
                .padding(14)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
