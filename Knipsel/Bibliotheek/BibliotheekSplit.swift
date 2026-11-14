import CoreData
import SwiftUI

/// iPad (en brede vensters): twee kolommen — de zijbalk met categorieën en labels, en rechts een
/// `NavigationStack` met het kaartenraster (of de lijst, Instellingen › Weergave). Een recept opent
/// over het raster (push); er is geen lege kolom "Kies een recept" meer (U6). Bovenaan "Verder met…"
/// (U8), en *Knip* zweeft rechtsonder zoals op de iPhone.
struct BibliotheekSplit: View {
    @Environment(\.managedObjectContext) private var context
    @State private var filter = ReceptFilter()
    @State private var zijbalkKeuze: CategorieKeuze? = .alles
    @State private var pad: [NSManagedObjectID] = []
    @State private var toonInstellingen = false
    @State private var toonNieuw = false
    @State private var toonKnippen = false
    @State private var verder: VerderKeuze?
    @State private var verderGestart: VerderKeuze?
    @AppStorage(AppConfiguratie.sleutelBibliotheekWeergave) private var weergave = BibliotheekWeergave.kaarten
    /// Zijbalk standaard zichtbaar, zoals in de schets.
    @State private var kolommen: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $kolommen) {
            Zijbalk(keuze: $zijbalkKeuze, labels: $filter.labels)
                .navigationTitle("Knipsel")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Instellingen", systemImage: "gearshape") { toonInstellingen = true }
                    }
                }
        } detail: {
            NavigationStack(path: $pad) {
                ReceptLijst(filter: filter, weergave: weergave, kop: kop)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        HStack {
                            Spacer()
                            KnipKnop { toonKnippen = true }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                    }
                    .navigationTitle(lijstTitel)
                    .searchable(text: $filter.zoekterm, prompt: "Zoek op recept of ingrediënt")
                    .navigationDestination(for: NSManagedObjectID.self) { id in
                        ReceptScherm(id: id) { pad.removeAll { $0 == id } }
                    }
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Nieuw recept", systemImage: "plus") { toonNieuw = true }
                        }
                    }
            }
        }
        .onChange(of: zijbalkKeuze) { _, nieuw in
            filter.categorie = nieuw ?? .alles
            // Een andere categorie: terug naar het raster.
            pad.removeAll()
        }
        .verderMet($verder, gestart: $verderGestart)
        .sheet(isPresented: $toonInstellingen) { InstellingenView() }
        .sheet(isPresented: $toonNieuw) { ReceptBewerken(recept: nil) }
        .sheet(isPresented: $toonKnippen) { KnipStart() }
    }

    /// "Verder met…" boven het raster; niet tijdens het zoeken.
    private var kop: AnyView? {
        guard let verder, filter.zoekterm.isEmpty else { return nil }
        return AnyView(
            VerderMetKaart(
                keuze: verder, verder: { verderGestart = verder },
                vergeet: { KookVoortgang().wis(recept: verder.stand.recept) }
            )
            .padding(.horizontal, weergave == .kaarten ? 24 : 16)
            .padding(.top, 4)
            .padding(.bottom, 12))
    }

    private var lijstTitel: String {
        switch filter.categorie {
        case .alles: return "Alle recepten"
        case .zonderCategorie: return "Zonder categorie"
        case .categorie(let id):
            return (try? context.existingObject(with: id) as? Categorie)?.naamOfStandaard ?? "Recepten"
        }
    }
}

/// Zijbalk: kookboek, categorieën met aantallen en labels (aan/uit, combineerbaar met de categorie).
struct Zijbalk: View {
    @Binding var keuze: CategorieKeuze?
    @Binding var labels: Set<NSManagedObjectID>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "volgorde", ascending: true)],
        predicate: NSPredicate(format: "verborgen == NO"))
    private var categorieen: FetchedResults<Categorie>
    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(
            key: "naam", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
    ])
    private var alleLabels: FetchedResults<ReceptLabel>
    @FetchRequest(sortDescriptors: []) private var recepten: FetchedResults<Recept>

    var body: some View {
        List(selection: $keuze) {
            Section("Kookboeken") {
                SwiftUI.Label("Alles", systemImage: "books.vertical")
                    .badge(recepten.count)
                    .tag(CategorieKeuze.alles)
            }
            Section("Categorieën") {
                ForEach(zichtbareCategorieen, id: \.objectID) { categorie in
                    SwiftUI.Label(categorie.naamOfStandaard, systemImage: categorie.symboolOfStandaard)
                        .badge(categorie.aantalRecepten)
                        .tag(CategorieKeuze.categorie(categorie.objectID))
                }
                if aantalZonderCategorie > 0 {
                    SwiftUI.Label("Zonder categorie", systemImage: "tray")
                        .badge(aantalZonderCategorie)
                        .tag(CategorieKeuze.zonderCategorie)
                }
            }
            if !alleLabels.isEmpty {
                Section("Labels") {
                    ForEach(alleLabels, id: \.objectID) { label in
                        let gekozen = labels.contains(label.objectID)
                        Button {
                            if gekozen {
                                labels.remove(label.objectID)
                            } else {
                                labels.insert(label.objectID)
                            }
                        } label: {
                            HStack {
                                SwiftUI.Label(
                                    label.naamOfStandaard, systemImage: gekozen ? "checkmark.circle.fill" : "tag")
                                Spacer()
                                Text(label.aantalRecepten, format: .number).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityAddTraits(gekozen ? .isSelected : [])
                    }
                }
            }
        }
    }

    /// Zoals de chiprij op de iPhone: lege categorieën niet tonen, de gekozen categorie wel.
    private var zichtbareCategorieen: [Categorie] {
        categorieen.filter {
            FilterChips.toonInRij(aantal: $0.aantalRecepten, gekozen: keuze == .categorie($0.objectID))
        }
    }

    private var aantalZonderCategorie: Int {
        recepten.filter { ($0.categorieen ?? []).isEmpty }.count
    }
}
