import SwiftUI
import UIKit
import PhotosUI

/// Fotos für „Notizen“ (z. B. wo der Schlüssel liegt): verkleinert als JPEG im App-Group-Ordner,
/// dazu ein kleines Vorschaubild für die Liste. Nicht im JSON-Backup – das bleibt klein.
enum MemoPhotos {
    private static let cache = NSCache<NSString, UIImage>()

    static var folder: URL {
        let base = Shared.containerURL
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Speichert Foto + Vorschau, gibt den Dateinamen zurück. Seit Build 105 in hoher Auflösung
    /// (Zettel und Tafeln sollen beim Reinzoomen lesbar bleiben), Vorschau scharf auf dem Retina-Display.
    static func save(_ image: UIImage) -> String? {
        let name = UUID().uuidString + ".jpg"
        guard let full = resized(image, maxSide: 2800).jpegData(compressionQuality: 0.85),
              let thumb = resized(image, maxSide: 480).jpegData(compressionQuality: 0.75) else { return nil }
        do {
            try full.write(to: folder.appendingPathComponent(name), options: .atomic)
            try thumb.write(to: folder.appendingPathComponent(thumbName(name)), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    static func image(_ name: String) -> UIImage? {
        UIImage(contentsOfFile: folder.appendingPathComponent(name).path)
    }

    static func thumbnail(_ name: String) -> UIImage? {
        if let cached = cache.object(forKey: name as NSString) { return cached }
        let image = UIImage(contentsOfFile: folder.appendingPathComponent(thumbName(name)).path) ?? self.image(name)
        if let image { cache.setObject(image, forKey: name as NSString) }
        return image
    }

    static func delete(_ name: String) {
        cache.removeObject(forKey: name as NSString)
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(thumbName(name)))
    }

    private static func thumbName(_ name: String) -> String { "t-" + name }

    private static func resized(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let side = max(image.size.width, image.size.height)
        guard side > maxSide else { return image }
        let scale = maxSide / side
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

/// Kamera (UIImagePickerController) für SwiftUI.
struct CameraPicker: UIViewControllerRepresentable {
    let onPick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var available: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onPick(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// Vorschaubild in der Liste – antippen zeigt das Foto groß.
struct MemoThumbnail: View {
    let name: String
    var size: CGFloat = 52
    @State private var showFull = false

    var body: some View {
        Button { showFull = true } label: {
            Group {
                if let image = MemoPhotos.thumbnail(name) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "photo").foregroundStyle(DS.faint)
                }
            }
            .frame(width: size, height: size)
            .background(DS.field)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(DS.line))
        }
        .buttonStyle(PressStyle())
        .fullScreenCover(isPresented: $showFull) { PhotoViewer(name: name) }
        .accessibilityLabel("Foto ansehen")
    }
}

/// Foto groß, mit zwei Fingern zoombar, Tippen schließt.
struct PhotoViewer: View {
    let name: String
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let image = MemoPhotos.image(name) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(max(1, scale * pinch))
                    .gesture(MagnificationGesture()
                        .updating($pinch) { value, state, _ in state = value }
                        .onEnded { value in scale = min(4, max(1, scale * value)) })
                    .onTapGesture(count: 2) { withAnimation(.spring()) { scale = scale > 1 ? 1 : 2.5 } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Foto nicht mehr da – Fotos sind nicht im Backup.")
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.15), in: Circle())
            }
            .buttonStyle(PressStyle())
            .padding(16)
        }
        .statusBarHidden()
    }
}
