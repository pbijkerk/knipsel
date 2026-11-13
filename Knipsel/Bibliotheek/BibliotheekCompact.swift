import CoreData
import SwiftUI

/// iPhone: lijst met zoekveld en twee rijen chips (categorie en labels) die je combineert.
struct BibliotheekCompact: View {
    @State private var filter = ReceptFilter()
    @State private var pad: [NSManagedObjectID] = []
    @State private var toonInstellingen = false
    @State private var toonNieuw = false

    var body: some View {
        NavigationStack(path: $pad) {
            ReceptLijst(filter: filter, kop: AnyView(FilterChips(filter: $filter).padding(.vertical, 8)))
                .navigationTitle("Recepten")
                .searchable(text: $filter.zoekterm, prompt: "Zoek op recept of ingrediënt")
                .navigationDestination(for: NSManagedObjectID.self) { id in
                    ReceptScherm(id: id) { pad.removeAll { $0 == id } }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Instellingen", systemImage: "gearshape") { toonInstellingen = true }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Nieuw recept", systemImage: "plus") { toonNieuw = true }
                    }
                }
        }
        .sheet(isPresented: $toonInstellingen) { InstellingenView() }
        .sheet(isPresented: $toonNieuw) { ReceptBewerken(recept: nil) }
    }
}

/// Twee horizontale rijen chips: één categorie (of Alles / Zonder categorie) en nul of meer labels.
struct FilterChips: View {
    @Binding var filter: ReceptFilter

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "volgorde", ascending: true)],
        predicate: NSPredicate(format: "verborgen == NO"))
    private var categorieen: FetchedResults<Categorie>
    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(
            key: "naam", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
    ])
    private var labels: FetchedResults<ReceptLabel>
    @FetchRequest(sortDescriptors: []) private var recepten: FetchedResults<Recept>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Chip(titel: "Alles", aantal: recepten.count, gekozen: filter.categorie == .alles) {
                        filter.categorie = .alles
                    }
                    ForEach(categorieen, id: \.objectID) { categorie in
                        let keuze = CategorieKeuze.categorie(categorie.objectID)
                        Chip(
                            titel: categorie.naamOfStandaard, symbool: categorie.symboolOfStandaard,
                            aantal: categorie.aantalRecepten, gekozen: filter.categorie == keuze
                        ) {
                            filter.categorie = filter.categorie == keuze ? .alles : keuze
                        }
                    }
                    if aantalZonderCategorie > 0 || filter.categorie == .zonderCategorie {
                        Chip(
                            titel: "Zonder categorie", symbool: "tray", aantal: aantalZonderCategorie,
                            gekozen: filter.categorie == .zonderCategorie
                        ) {
                            filter.categorie = filter.categorie == .zonderCategorie ? .alles : .zonderCategorie
                        }
                    }
                }
                .padding(.horizontal)
            }
            if !labels.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(labels, id: \.objectID) { label in
                            let gekozen = filter.labels.contains(label.objectID)
                            Chip(titel: label.naamOfStandaard, symbool: gekozen ? "checkmark" : nil, gekozen: gekozen) {
                                if gekozen {
                                    filter.labels.remove(label.objectID)
                                } else {
                                    filter.labels.insert(label.objectID)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    private var aantalZonderCategorie: Int {
        recepten.filter { ($0.categorieen ?? []).isEmpty }.count
    }
}
