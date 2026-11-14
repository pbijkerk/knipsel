import OSLog
import PhotosUI
import SwiftUI
import UIKit

/// De eigen gerechtfoto van een recept, gevuld (scaledToFill) in het vlak dat de ouder geeft.
/// Decodeert buiten de main thread via ImageIO, verkleind tot `maxPixels`, en onthoudt het
/// resultaat in `GerechtFotoCache`.
struct GerechtFotoBeeld: View {
    @ObservedObject var recept: Recept
    /// Lange zijde in pixels: klein voor een lijstregel, groot voor de receptweergave.
    let maxPixels: Int

    @State private var geladen: (sleutel: String, beeld: UIImage)?

    private var sleutel: String {
        GerechtFotoCache.sleutel(id: recept.objectID, gewijzigd: recept.fotoGewijzigdOp, maxPixels: maxPixels)
    }

    var body: some View {
        let sleutel = sleutel
        Color(.secondarySystemFill)
            .overlay {
                if let beeld = beeld(voor: sleutel) {
                    Image(uiImage: beeld)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .accessibilityHidden(true)
            .task(id: sleutel) { await laad(sleutel) }
    }

    private func beeld(voor sleutel: String) -> UIImage? {
        if let geladen, geladen.sleutel == sleutel { return geladen.beeld }
        return GerechtFotoCache.gedeeld.beeld(voor: sleutel)
    }

    private func laad(_ sleutel: String) async {
        if let bekend = GerechtFotoCache.gedeeld.beeld(voor: sleutel) {
            geladen = (sleutel, bekend)
            return
        }
        guard let data = recept.fotoData else { return }
        let maxPixels = maxPixels
        let beeld = await Task.detached(priority: .userInitiated) {
            GerechtFoto.miniatuur(van: data, maxPixels: maxPixels).map { UIImage(cgImage: $0) }
        }.value
        guard let beeld, !Task.isCancelled else { return }
        GerechtFotoCache.gedeeld.bewaar(beeld, voor: sleutel)
        geladen = (sleutel, beeld)
    }
}

/// De camera via `UIImagePickerController` (alleen tonen als `isBeschikbaar`; niet in de simulator).
struct CameraKiezer: UIViewControllerRepresentable {
    let klaar: (UIImage?) -> Void

    static var isBeschikbaar: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let kiezer = UIImagePickerController()
        kiezer.sourceType = .camera
        kiezer.cameraCaptureMode = .photo
        kiezer.delegate = context.coordinator
        return kiezer
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(klaar: klaar) }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let klaar: (UIImage?) -> Void

        init(klaar: @escaping (UIImage?) -> Void) {
            self.klaar = klaar
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            klaar(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            klaar(nil)
        }
    }
}

/// Foto kiezen (PhotosPicker, geen toestemming nodig) of maken (camera), bijsnijden en bewaren bij
/// het recept.
struct GerechtFotoKiezer: ViewModifier {
    @ObservedObject var recept: Recept
    @Binding var bibliotheek: Bool
    @Binding var camera: Bool

    @State private var gekozen: PhotosPickerItem?
    @State private var foutmelding: String?

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $bibliotheek, selection: $gekozen, matching: .images)
            .onChange(of: gekozen) { _, item in
                guard let item else { return }
                gekozen = nil
                Task { await verwerk(item) }
            }
            .fullScreenCover(isPresented: $camera) {
                CameraKiezer { beeld in
                    camera = false
                    if let beeld { Task { await bewaar(beeld) } }
                }
                .ignoresSafeArea()
            }
            .alert(
                "Foto niet bewaard",
                isPresented: Binding(get: { foutmelding != nil }, set: { if !$0 { foutmelding = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(foutmelding ?? "")
            }
    }

    private func verwerk(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                foutmelding = "Deze foto kon Knipsel niet openen."
                return
            }
            let foto = await Task.detached(priority: .userInitiated) { GerechtFoto.maakData(van: data) }.value
            zet(foto)
        } catch {
            foutmelding = error.localizedDescription
        }
    }

    private func bewaar(_ beeld: UIImage) async {
        let foto = await Task.detached(priority: .userInitiated) { GerechtFoto.maakData(van: beeld) }.value
        zet(foto)
    }

    private func zet(_ foto: Data?) {
        guard let foto else {
            foutmelding = "Deze foto kon Knipsel niet openen."
            return
        }
        do {
            try recept.zetFoto(foto)
        } catch {
            recept.managedObjectContext?.rollback()
            foutmelding = error.localizedDescription
            Logger(subsystem: "com.peterbijkerk.knipsel", category: "Recept")
                .error("Foto bewaren mislukt: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension View {
    func gerechtFotoKiezer(recept: Recept, bibliotheek: Binding<Bool>, camera: Binding<Bool>) -> some View {
        modifier(GerechtFotoKiezer(recept: recept, bibliotheek: bibliotheek, camera: camera))
    }
}
