import SwiftUI
import VisionKit

/// Barcode scannen (Einkauf): Kamera auf den Strichcode, der erste erkannte EAN geht zurück.
/// VisionKit-Scanner (iOS 16, ab A12) – auf älteren Geräten oder ohne Kamera-Erlaubnis ein Hinweis.
struct BarcodeSheet: View {
    let onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private var supported: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                if supported {
                    BarcodeScanner(onCode: onCode)
                        .ignoresSafeArea()
                    Text("Strichcode ins Bild halten")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(.bottom, 40)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "barcode.viewfinder").font(.system(size: 40)).foregroundStyle(DS.purpleMuted)
                        Text("Scannen geht gerade nicht – Kamera für Dopa erlauben (Einstellungen → Dopa → Kamera).")
                            .font(.system(size: 14)).foregroundStyle(DS.muted).multilineTextAlignment(.center)
                    }
                    .padding(30)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(DS.surface.ignoresSafeArea())
                }
            }
            .navigationTitle("Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
        }
    }
}

/// VisionKit-Scanner für Strichcodes (EAN-13, EAN-8, UPC-E).
struct BarcodeScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var done = false

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let code = barcode.payloadStringValue, !code.isEmpty {
                    done = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onCode(code)
                    return
                }
            }
        }
    }
}
