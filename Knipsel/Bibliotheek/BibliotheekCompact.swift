import CoreData
import SwiftUI

/// iPhone: kaarten (of een lijst) met zoekveld, één chiprij met categorieën, de labels achter
/// "Filter" en een zwevende knop "Knip" onderin (U1, U2, U5).
struct BibliotheekCompact: View {
    @State private var filter = ReceptFilter()
    @State private var pad: [NSManagedObjectID] = []
    @State private var toonInstellingen = false
    @State private var toonNieuw = false
    @State private var toonKnippen = false
    @State private var toonLabels = false
    @AppStorage(AppConfiguratie.sleutelBibliotheekWeergave) private var weergave = BibliotheekWeergave.kaarten

    var body: some View {
        NavigationStack(path: $pad) {
            ReceptLijst(
                filter: filter, weergave: weergave,
                kop: AnyView(FilterChips(filter: $filter, toonLabels: $toonLabels).padding(.vertical, 8))
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    Spacer()
                    KnipKnop { toonKnippen = true }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
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
        .sheet(isPresented: $toonKnippen) { KnipStart() }
        .sheet(isPresented: $toonLabels) {
            LabelFilter(labels: $filter.labels)
                .presentationDetents([.medium, .large])
        }
    }
}

/// Eén horizontale rij chips met categorieën (of Alles / Zonder categorie), en rechts vast de chip
/// "Filter" die de labels opent; het aantal gekozen labels staat erop.
struct FilterChips: View {
    @Binding var filter: ReceptFilter
    @Binding var toonLabels: Bool

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "volgorde", ascending: true)],
        predicate: NSPredicate(format: "verborgen == NO"))
    private var categorieen: FetchedResults<Categorie>
    @FetchRequest(sortDescriptors: []) private var labels: FetchedResults<ReceptLabel>
    @FetchRequest(sortDescriptors: []) private var recepten: FetchedResults<Recept>

    var body: some View {
        HStack(spacing: 0) {
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
                .padding(.leading)
                .padding(.trailing, 8)
            }
            .mask {
                // Zachte rand vóór de vaste chip "Filter": je ziet dat de rij verder scrolt.
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 20)
                }
            }
            if !labels.isEmpty || !filter.labels.isEmpty {
                Chip(
                    titel: "Filter", symbool: "line.3.horizontal.decrease",
                    aantal: filter.labels.isEmpty ? nil : filter.labels.count, gekozen: !filter.labels.isEmpty
                ) {
                    toonLabels = true
                }
                .accessibilityLabel(
                    filter.labels.isEmpty ? "Filter op labels" : "Filter op labels, \(filter.labels.count) gekozen"
                )
                .padding(.leading, 4)
                .padding(.trailing)
            }
        }
    }

    private var aantalZonderCategorie: Int {
        recepten.filter { ($0.categorieen ?? []).isEmpty }.count
    }
}
