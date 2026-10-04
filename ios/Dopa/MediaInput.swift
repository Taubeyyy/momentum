import SwiftUI
import PhotosUI
import UIKit

// Fotos statt Tippen (Feedback #29): Kamera oder Mediathek, verkleinert an Gemini,
// Ergebnis wie beim Smart Dump zum Abhaken.

enum MediaUpload {
    /// Verkleinert (längste Seite `maxSide`) als JPEG, Base64 – klein genug für den Server (≤ 10 MB).
    static func jpegBase64(_ image: UIImage, maxSide: CGFloat = 1600, quality: CGFloat = 0.7) -> String? {
        let side = max(image.size.width, image.size.height)
        let scale = side > maxSide ? maxSide / side : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: quality)?.base64EncodedString()
    }
}

/// Bild mit ID – für `.sheet(item:)`.
struct PickedImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Fragt „Foto aufnehmen / Aus Fotos wählen“ und liefert das Bild – erst wenn das Auswahl-Fenster
/// zu ist, damit das nächste Fenster (z. B. „Foto einsortieren“) sicher aufgeht.
struct PhotoSource: ViewModifier {
    @Binding var isPresented: Bool
    var title = "Foto"
    let onPick: (UIImage) -> Void
    @State private var showCamera = false
    @State private var showLibrary = false

    func body(content: Content) -> some View {
        content
            .confirmationDialog(title, isPresented: $isPresented, titleVisibility: .hidden) {
                if CameraPicker.available {
                    Button("Foto aufnehmen") { showCamera = true }
                }
                Button("Aus Fotos wählen") { showLibrary = true }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in deliver(image) }.ignoresSafeArea()
            }
            .sheet(isPresented: $showLibrary) {
                LibraryPicker { image in deliver(image) }.ignoresSafeArea()
            }
    }

    private func deliver(_ image: UIImage) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { onPick(image) }
    }
}

/// Mediathek als normales Fenster (PHPicker). Ersetzt `.photosPicker` – das konnte unter iOS 16
/// andere Fenster (Profil, Feedback) blockieren. Braucht keine Foto-Berechtigung.
struct LibraryPicker: UIViewControllerRepresentable {
    let onPick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: LibraryPicker
        init(_ parent: LibraryPicker) { self.parent = parent }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else { return }
            let onPick = parent.onPick
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                guard let image = object as? UIImage else { return }
                DispatchQueue.main.async { onPick(image) }
            }
        }
    }
}

extension View {
    func photoSource(isPresented: Binding<Bool>, title: String = "Foto", onPick: @escaping (UIImage) -> Void) -> some View {
        modifier(PhotoSource(isPresented: isPresented, title: title, onPick: onPick))
    }
}

/// Foto → Aufgaben, Erinnerungen, Einkauf, Notizen (wie Smart Dump) → abhaken → übernehmen.
struct PhotoDumpSheet: View {
    let image: UIImage
    var hint: String?
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var dump: Server.Dump?
    @State private var picked: Set<String> = []
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(DS.line))

                    if busy {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("\(store.dotName) schaut sich das Foto an …").font(.system(size: 14)).foregroundStyle(DS.muted)
                        }
                        .padding(.top, 18)
                    }
                    if let error {
                        Text(error).font(.system(size: 13)).foregroundStyle(DS.muted).padding(.top, 14)
                        Button("Nochmal versuchen", action: run).buttonStyle(SoftButtonStyle()).padding(.top, 10)
                    }
                    if let dump {
                        if !dump.summary.isEmpty {
                            Text(dump.summary).font(.system(size: 14)).foregroundStyle(Color(hex: 0xC5BDCA)).padding(.top, 16)
                        }
                        DumpResultView(dump: dump, picked: $picked)
                        Button("\(picked.count) übernehmen") {
                            store.applyDump(dump, picked: picked)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            dismiss()
                        }
                        .buttonStyle(SolidButtonStyle())
                        .disabled(picked.isEmpty)
                        .padding(.top, 18)
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .background(DS.surface.ignoresSafeArea())
            .navigationTitle("Foto einsortieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
            .task { if dump == nil && !busy { run() } }
        }
    }

    private func run() {
        guard let encoded = MediaUpload.jpegBase64(image) else {
            error = "Das Foto ließ sich nicht vorbereiten."
            return
        }
        busy = true
        error = nil
        Task {
            do {
                let result = try await Server.shared.photoDump(encoded, hint: hint)
                withAnimation(.easeOut(duration: 0.25)) {
                    dump = result
                    picked = DumpKey.all(result)
                }
            } catch {
                self.error = error.localizedDescription
            }
            busy = false
        }
    }
}
