import CoreData
import SwiftUI

/// iPad (en brede vensters): drie kolommen — zijbalk, lijst, recept.
struct BibliotheekSplit: View {
    @Environment(\.managedObjectContext) private var context
    @State private var filter = ReceptFilter()
    @State private var zijbalkKeuze: CategorieKeuze? = .alles
    @State private var gekozenRecept: NSManagedObjectID?
    @State private var toonInstellingen = false
    @State private var toonNieuw = false
    /// Zijbalk standaard zichtbaar, zoals in de schets (tab 2B).
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
        } content: {
            ReceptLijst(filter: filter, selectie: $gekozenRecept)
                .navigationTitle(lijstTitel)
                .searchable(text: $filter.zoekterm, prompt: "Zoek op recept of ingrediënt")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Nieuw recept", systemImage: "plus") { toonNieuw = true }
                    }
                }
        } detail: {
            if let gekozenRecept {
                NavigationStack {
                    ReceptScherm(id: gekozenRecept) { self.gekozenRecept = nil }
                }
                .id(gekozenRecept)
            } else {
                ContentUnavailableView(
                    "Kies een recept", systemImage: "scissors",
                    description: Text("Of voeg er een toe met de plusknop."))
            }
        }
        .onChange(of: zijbalkKeuze) { _, nieuw in
            filter.categorie = nieuw ?? .alles
        }
        .sheet(isPresented: $toonInstellingen) { InstellingenView() }
        .sheet(isPresented: $toonNieuw) { ReceptBewerken(recept: nil) }
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
                ForEach(categorieen, id: \.objectID) { categorie in
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

    private var aantalZonderCategorie: Int {
        recepten.filter { ($0.categorieen ?? []).isEmpty }.count
    }
}
