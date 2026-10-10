import SwiftUI
import WebKit

/// Prospekt-Link (z. B. aus kaufDA „Teilen“) direkt in Dopa ansehen und seitenweise einlesen:
/// „Seite einlesen“ macht ein Bild von dem, was gerade zu sehen ist – wie ein Screenshot, nur bequemer.
/// Keine versteckte Schnittstelle: Dopa liest nur, was du auch siehst.
struct FlyerBrowser: View {
    let url: URL
    @EnvironmentObject private var store: Store
    @ObservedObject private var server = Server.shared
    @StateObject private var web = WebHolder()
    @Environment(\.dismiss) private var dismiss
    @State private var reading = false
    @State private var pages = 0
    @State private var offers = 0

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                WebView(holder: web, url: url)
                    .ignoresSafeArea(edges: .bottom)
                VStack(spacing: 8) {
                    if pages > 0 {
                        Text("\(pages) Seite\(pages == 1 ? "" : "n") gelesen · \(offers) Angebote")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(.black.opacity(0.6), in: Capsule())
                    }
                    Button(action: readPage) {
                        HStack(spacing: 8) {
                            if reading { ProgressView().tint(.white) } else { Image(systemName: "text.viewfinder") }
                            Text(reading ? "\(store.dotName) liest …" : "Seite einlesen")
                        }
                    }
                    .buttonStyle(SolidButtonStyle())
                    .disabled(reading || !server.aiAvailable)
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Prospekt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
    }

    /// Sichtbaren Ausschnitt fotografieren → Angebote lesen → zum Prospekt legen (gleicher Laden = zusammen).
    private func readPage() {
        reading = true
        web.view.takeSnapshot(with: nil) { image, _ in
            guard let image, let encoded = MediaUpload.jpegBase64(image, maxSide: 2000, quality: 0.8) else {
                reading = false
                Toaster.shared.show("Seite ließ sich nicht fotografieren")
                return
            }
            Task { @MainActor in
                do {
                    let scan = try await server.flyer(encoded)
                    if scan.offers.isEmpty {
                        Toaster.shared.show("Auf dieser Seite keine Angebote erkannt")
                    } else {
                        let flyer = store.addFlyer(scan)
                        pages += 1
                        offers = flyer.offers.count
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        Toaster.shared.show("\(flyer.storeName): \(scan.offers.count) Angebote – weiterblättern?")
                    }
                } catch {
                    Toaster.shared.show("Seite ließ sich gerade nicht lesen")
                }
                reading = false
            }
        }
    }
}

/// Hält die WKWebView, damit „Seite einlesen“ ein Bild davon machen kann.
@MainActor
final class WebHolder: ObservableObject {
    let view: WKWebView = {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let view = WKWebView(frame: .zero, configuration: config)
        view.allowsBackForwardNavigationGestures = true
        return view
    }()
}

struct WebView: UIViewRepresentable {
    let holder: WebHolder
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let view = holder.view
        if view.url == nil { view.load(URLRequest(url: url)) }
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}
}
