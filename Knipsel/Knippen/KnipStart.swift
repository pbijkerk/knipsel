import CoreData
import PhotosUI
import SwiftUI
import VisionKit

/// Recept knippen: pagina scannen of foto kiezen → knipselscherm → controle → bewaren.
struct KnipStart: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @State private var sessie = KnipSessie()
    @State private var fotoKeuze: [PhotosPickerItem] = []
    @State private var toonScanner = false
    @State private var toonScannerMelding = false
    @State private var controle: ControleInvoer?

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "volgorde", ascending: true)],
        predicate: NSPredicate(format: "verborgen == NO"))
    private var categorieen: FetchedResults<Categorie>
    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(
            key: "naam", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
    ])
    private var labels: FetchedResults<ReceptLabel>

    var body: some View {
        NavigationStack {
            inhoud
                .navigationTitle(sessie.toestand == .klaar ? "Kies het recept" : "Knip recept")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuleer") {
                            sessie.herstel()
                            dismiss()
                        }
                    }
                    if sessie.toestand == .klaar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Controleer") { controle = maakControle() }
                        }
                        ToolbarItem(placement: .bottomBar) {
                            Button("Opnieuw", systemImage: "arrow.counterclockwise") { sessie.herstel() }
                                .labelStyle(.titleAndIcon)
                        }
                    }
                }
                .navigationDestination(
                    isPresented: Binding(get: { controle != nil }, set: { if !$0 { controle = nil } })
                ) {
                    if let controle {
                        ControleScherm(sessie: sessie, invoer: controle) { dismiss() }
                    }
                }
        }
        .fullScreenCover(isPresented: $toonScanner) {
            Documentcamera { beelden in
                toonScanner = false
                guard !beelden.isEmpty else { return }
                // Een scan heeft geen opnamedatum: vandaag.
                Task { await verwerk(beelden, datum: nil) }
            }
            .ignoresSafeArea()
        }
        .alert("Scanner niet beschikbaar", isPresented: $toonScannerMelding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                "De documentscanner werkt niet op dit toestel (bijvoorbeeld in de simulator). Kies een foto uit je fotobibliotheek."
            )
        }
        .onChange(of: fotoKeuze) { _, keuze in
            guard !keuze.isEmpty else { return }
            Task { await laadFotos(keuze) }
        }
    }

    @ViewBuilder private var inhoud: some View {
        switch sessie.toestand {
        case .kiezen:
            keuze
        case .bezig(let tekst):
            ProgressView(tekst)
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .klaar:
            KnipselScherm(sessie: sessie)
        case .fout(let melding):
            ContentUnavailableView {
                SwiftUI.Label("Niet gelukt", systemImage: "exclamationmark.triangle")
            } description: {
                Text(melding)
            } actions: {
                Button("Opnieuw") { sessie.herstel() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var keuze: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "scissors")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text("Knip een recept uit de krant")
                .font(.system(.title2, design: .serif).bold())
                .multilineTextAlignment(.center)
            Text(
                "Fotografeer de pagina of kies een foto. Knipsel zoekt zelf de titel, ingrediënten en bereiding; advertenties en andere stukken vallen weg. Loopt het recept door op een tweede pagina? Scan ze allebei."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 480)
            VStack(spacing: 12) {
                Button {
                    if Documentcamera.isBeschikbaar {
                        toonScanner = true
                    } else {
                        toonScannerMelding = true
                    }
                } label: {
                    SwiftUI.Label("Scan pagina's", systemImage: "doc.viewfinder")
                        .frame(maxWidth: 320)
                }
                .buttonStyle(.borderedProminent)
                PhotosPicker(
                    selection: $fotoKeuze, maxSelectionCount: 4, selectionBehavior: .ordered, matching: .images
                ) {
                    SwiftUI.Label("Kies foto's", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: 320)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            Spacer()
            Text("Alleen de tekst wordt bewaard, de foto niet.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    // MARK: - Acties

    private func laadFotos(_ keuze: [PhotosPickerItem]) async {
        var beelden: [UIImage] = []
        var datum: Date?
        for item in keuze {
            guard let data = try? await item.loadTransferable(type: Data.self), let beeld = UIImage(data: data) else {
                continue
            }
            if datum == nil { datum = Fotodatum.uit(data) }
            beelden.append(beeld)
        }
        fotoKeuze = []
        guard !beelden.isEmpty else {
            sessie.toestand = .fout("De foto kon niet worden geladen.")
            return
        }
        await verwerk(beelden, datum: datum)
    }

    private func verwerk(_ beelden: [UIImage], datum: Date?) async {
        await sessie.verwerk(
            beelden, datum: datum, categorieen: categorieen.map(\.naamOfStandaard),
            labels: labels.map(\.naamOfStandaard))
    }

    /// Concept + voorstellen (namen → objecten) voor het controlescherm.
    private func maakControle() -> ControleInvoer {
        let voorgesteldeCategorieen = ids(
            sessie.indeling.categorieen, uit: categorieen.map { ($0.objectID, $0.naamOfStandaard) })
        let voorgesteldeLabels = ids(sessie.indeling.labels, uit: labels.map { ($0.objectID, $0.naamOfStandaard) })
        return ControleInvoer(
            concept: sessie.concept, categorieen: voorgesteldeCategorieen, labels: voorgesteldeLabels,
            voorgesteldeCategorieen: voorgesteldeCategorieen, voorgesteldeLabels: voorgesteldeLabels,
            bronDatum: sessie.bronDatum)
    }

    private func ids(_ namen: [String], uit lijst: [(NSManagedObjectID, String)]) -> Set<NSManagedObjectID> {
        let sleutels = Set(namen.map(Inrichting.sleutel))
        return Set(lijst.filter { sleutels.contains(Inrichting.sleutel($0.1)) }.map(\.0))
    }
}

/// De documentscanner van iOS (rechtzetten, meerdere pagina's). Werkt niet in de simulator.
struct Documentcamera: UIViewControllerRepresentable {
    let klaar: ([UIImage]) -> Void

    static var isBeschikbaar: Bool { VNDocumentCameraViewController.isSupported }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(klaar: klaar) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let klaar: ([UIImage]) -> Void

        init(klaar: @escaping ([UIImage]) -> Void) {
            self.klaar = klaar
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan
        ) {
            klaar((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            klaar([])
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController, didFailWithError error: any Error
        ) {
            klaar([])
        }
    }
}
