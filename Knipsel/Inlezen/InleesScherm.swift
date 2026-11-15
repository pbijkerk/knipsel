import CoreData
import PhotosUI
import SwiftUI
import WebKit

/// Eén item uit "Nog te controleren": ophalen en inlezen (met voortgang), dan het bestaande
/// controlescherm; bij een betaalmuur de drie alternatieven; bij afbeeldingen het knipselscherm.
/// Bewaren of annuleren haalt het item uit de inbox; er wordt niets bewaard zonder controle.
struct InleesScherm: View {
    let id: InleesItem.ID

    @Environment(InleesInbox.self) private var inbox
    @Environment(\.dismiss) private var dismiss
    @State private var vraagAnnuleren = false
    @State private var toonWeb = false
    @State private var fotoKeuze: [PhotosPickerItem] = []
    @State private var knipBeelden: KnipBeelden?

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "volgorde", ascending: true)],
        // De voorstellen van de indeler komen uit Mijn recepten (Thuis heeft gelijknamige).
        predicate: NSPredicate(format: "verborgen == NO AND kookboek == %@", Kookboek.mijn.rawValue))
    private var categorieen: FetchedResults<Categorie>
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(
                key: "naam", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
        ], predicate: Bibliotheekbeheer.alleenMijn)
    private var labels: FetchedResults<ReceptLabel>

    private var item: InleesItem? { inbox.item(id) }

    var body: some View {
        if let item, case .herkennen(let namen) = item.status {
            // Afbeeldingen: het knipselscherm, zoals bij knippen (met eigen navigatie).
            KnipStart(
                beelden: namen.compactMap { inbox.data(van: $0).flatMap(UIImage.init(data:)) },
                bronNaam: item.bronNaam ?? "", bronPagina: item.bronURL?.absoluteString ?? ""
            ) {
                inbox.verwijder(id)
            }
        } else {
            NavigationStack {
                inhoud
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Annuleer") { vraagAnnuleren = true }
                        }
                    }
                    .navigationDestination(isPresented: $toonWeb) {
                        if let url = item?.bronURL ?? item.flatMap(Self.link) {
                            WebLezer(url: url) { html, adres in
                                toonWeb = false
                                Task {
                                    await verwerker.verwerk(
                                        html: html, url: adres, id: id, categorieen: namen.0, labels: namen.1)
                                }
                            }
                        }
                    }
            }
            .confirmationDialog(
                "Dit recept niet bewaren?", isPresented: $vraagAnnuleren, titleVisibility: .visible
            ) {
                Button("Verwijder uit Nog te controleren", role: .destructive) {
                    inbox.verwijder(id)
                    dismiss()
                }
                Button("Later controleren") { dismiss() }
                Button("Ga door", role: .cancel) {}
            }
            .sheet(item: $knipBeelden) { keuze in
                KnipStart(
                    beelden: keuze.beelden, bronNaam: item?.bronNaam ?? "",
                    bronPagina: item?.bronURL?.absoluteString ?? ""
                ) {
                    inbox.verwijder(id)
                    dismiss()
                }
            }
            .onChange(of: fotoKeuze) { _, keuze in
                guard !keuze.isEmpty else { return }
                Task {
                    knipBeelden = await KnipBeelden.laad(keuze)
                    fotoKeuze = []
                }
            }
            .task(id: item?.status == .wachten) {
                guard item?.status == .wachten else { return }
                // Los van het scherm: sluit je het tussendoor, dan gaat het inlezen door en staat het
                // resultaat later in "Nog te controleren".
                let (verwerker, categorieen, labels) = (verwerker, namen.0, namen.1)
                await Task { await verwerker.verwerk(id, categorieen: categorieen, labels: labels) }.value
            }
        }
    }

    private var verwerker: InleesVerwerker { InleesVerwerker(inbox: inbox) }

    private var namen: ([String], [String]) {
        (categorieen.map(\.naamOfStandaard), labels.map(\.naamOfStandaard))
    }

    static func link(_ item: InleesItem) -> URL? {
        if case .link(let url) = item.bron { return url }
        return nil
    }

    @ViewBuilder private var inhoud: some View {
        switch item?.status {
        case nil:
            ContentUnavailableView("Niet meer in de lijst", systemImage: "tray")
        case .wachten, .bezig:
            ProgressView(bezigTekst)
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle("Inlezen")
                .navigationBarTitleDisplayMode(.inline)
        case .klaar(let resultaat):
            if let item {
                ControleScherm(sessie: nil, invoer: controleInvoer(resultaat, item: item)) {
                    inbox.verwijder(id)
                    dismiss()
                }
            }
        case .betaalmuur:
            BetaalmuurKeuze(
                titel: "Alleen het begin is te lezen",
                uitleg:
                    "\(item?.bronNaam ?? "Deze site") laat zonder inloggen alleen een stukje zien. Kies hoe je het recept toch in Knipsel krijgt.",
                kanOpenen: item?.bronURL != nil || item.flatMap(Self.link) != nil,
                openen: { toonWeb = true }, geplakt: plak, fotoKeuze: $fotoKeuze)
        case .mislukt(let reden):
            if item?.bronURL != nil || item.flatMap(Self.link) != nil {
                BetaalmuurKeuze(
                    titel: "Geen recept gevonden", uitleg: reden + " Probeer het via een van deze wegen.",
                    kanOpenen: true, openen: { toonWeb = true }, geplakt: plak, fotoKeuze: $fotoKeuze)
            } else {
                ContentUnavailableView {
                    SwiftUI.Label("Niet gelukt", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(reden)
                } actions: {
                    Button("Verwijder", role: .destructive) {
                        inbox.verwijder(id)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        case .herkennen:
            EmptyView()
        }
    }

    private var bezigTekst: String {
        switch item?.bron {
        case .link: "Recept ophalen…"
        case .pdf: "PDF lezen…"
        default: "Recept lezen…"
        }
    }

    /// Geplakte tekst (na "selecteer en kopieer"): opnieuw inlezen, met de site als bron.
    private func plak(_ tekst: String) {
        inbox.werkBij(id) {
            if $0.bronURL == nil, case .link(let url) = $0.bron { $0.bronURL = url }
            if $0.bronNaam == nil, let url = $0.bronURL { $0.bronNaam = ReceptInlezer.host(url) }
            $0.bron = .tekst(tekst)
            $0.status = .wachten
        }
    }

    private func controleInvoer(_ resultaat: InleesResultaat, item: InleesItem) -> ControleInvoer {
        let voorgesteldeCategorieen = ids(
            resultaat.categorieen, uit: categorieen.map { ($0.objectID, $0.naamOfStandaard) })
        let voorgesteldeLabels = ids(resultaat.labels, uit: labels.map { ($0.objectID, $0.naamOfStandaard) })
        let url = resultaat.bronURL ?? item.bronURL
        return ControleInvoer(
            concept: resultaat.concept, soort: url != nil ? .website : .tekst,
            fotoData: item.foto.flatMap { inbox.data(van: $0) },
            categorieen: voorgesteldeCategorieen, labels: voorgesteldeLabels,
            voorgesteldeCategorieen: voorgesteldeCategorieen, voorgesteldeLabels: voorgesteldeLabels,
            bronNaam: resultaat.bronNaam.isEmpty ? (item.bronNaam ?? "") : resultaat.bronNaam,
            bronDatum: .now, bronPagina: url?.absoluteString ?? "")
    }

    private func ids(_ namen: [String], uit lijst: [(NSManagedObjectID, String)]) -> Set<NSManagedObjectID> {
        let sleutels = Set(namen.map(Inrichting.sleutel))
        return Set(lijst.filter { sleutels.contains(Inrichting.sleutel($0.1)) }.map(\.0))
    }
}

/// Gekozen afbeeldingen voor het knipselscherm.
struct KnipBeelden: Identifiable {
    let id = UUID()
    let beelden: [UIImage]

    static func laad(_ keuze: [PhotosPickerItem]) async -> KnipBeelden? {
        var beelden: [UIImage] = []
        for item in keuze {
            if let data = try? await item.loadTransferable(type: Data.self), let beeld = UIImage(data: data) {
                beelden.append(beeld)
            }
        }
        return beelden.isEmpty ? nil : KnipBeelden(beelden: beelden)
    }
}

/// Betaalmuur (of geen recept gevonden): (a) de pagina in Knipsel openen en zelf inloggen, (b) de
/// tekst selecteren en plakken, (c) een schermafdruk kiezen.
struct BetaalmuurKeuze: View {
    let titel: String
    let uitleg: String
    let kanOpenen: Bool
    let openen: () -> Void
    let geplakt: (String) -> Void
    @Binding var fotoKeuze: [PhotosPickerItem]

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "lock.doc")
                        .font(.largeTitle)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    Text(titel)
                        .font(.system(.title2, design: .serif).bold())
                    Text(uitleg)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
            if kanOpenen {
                Section {
                    Button(action: openen) {
                        KeuzeRij(
                            titel: "Open de pagina in Knipsel", symbool: "safari",
                            uitleg:
                                "Log daar zelf in bij de site en tik dan op ‘Lees recept van deze pagina’. Knipsel bewaart geen wachtwoorden; de site onthoudt je inlog op dit toestel.",
                            isKnop: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    KeuzeRij(
                        titel: "Selecteer de tekst en plak hem", symbool: "doc.on.clipboard",
                        uitleg:
                            "Selecteer in de app of in Safari het recept, kies Kopieer en tik hieronder op Plak.")
                    PasteButton(payloadType: String.self) { teksten in
                        guard let tekst = teksten.first, !tekst.isEmpty else { return }
                        geplakt(tekst)
                    }
                    .padding(.leading, 40)
                }
            }
            Section {
                PhotosPicker(
                    selection: $fotoKeuze, maxSelectionCount: 4, selectionBehavior: .ordered, matching: .images
                ) {
                    KeuzeRij(
                        titel: "Kies een schermafdruk", symbool: "photo.on.rectangle",
                        uitleg: "Maak schermafdrukken van het recept; Knipsel herkent de tekst op het toestel.",
                        isKnop: true)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Inlezen")
        .navigationBarTitleDisplayMode(.inline)
    }

}

/// Eén alternatief in `BetaalmuurKeuze`: symbool, titel en uitleg.
private struct KeuzeRij: View {
    let titel: String
    let symbool: String
    let uitleg: String
    var isKnop = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbool)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(titel).font(.headline).foregroundStyle(isKnop ? Color.accentColor : .primary)
                Text(uitleg).font(.subheadline).foregroundStyle(.secondary)
            }
            if isKnop {
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// De pagina in Knipsel, om zelf in te loggen bij een site met een betaalmuur. Cookies staan in de
/// gewone (blijvende) website-opslag van de app, op dit toestel; Knipsel bewaart geen wachtwoorden.
/// "Lees recept van deze pagina" haalt de HTML van de geopende pagina op en leest die opnieuw in.
struct WebLezer: View {
    let url: URL
    let lees: (String, URL?) -> Void

    @State private var pagina: WebPage = {
        var configuratie = WebPage.Configuration()
        configuratie.websiteDataStore = .default()
        return WebPage(configuration: configuratie)
    }()
    @State private var leest = false

    var body: some View {
        WebView(pagina)
            .navigationTitle(pagina.title.isEmpty ? (ReceptInlezer.host(url) ?? "Pagina") : pagina.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        Task { await leesPagina() }
                    } label: {
                        SwiftUI.Label("Lees recept van deze pagina", systemImage: "text.viewfinder")
                            .labelStyle(.titleAndIcon)
                    }
                    .disabled(pagina.isLoading || leest)
                }
            }
            .onAppear {
                if pagina.url == nil { pagina.load(URLRequest(url: url)) }
            }
    }

    private func leesPagina() async {
        leest = true
        defer { leest = false }
        if let html = try? await pagina.callJavaScript("return document.documentElement.outerHTML") as? String {
            lees(html, pagina.url ?? url)
        }
    }
}
