import CoreData
import SwiftUI

/// iPhone: kaarten (of een lijst) met zoekveld, één chiprij met categorieën, de labels achter
/// "Filter" en een zwevende knop "Knip" onderin (U1, U2, U5). Bovenaan "Verder met…" als je een
/// kookmodus halverwege sloot (U8), en "Nog te controleren" als er ingelezen recepten wachten (#18).
struct BibliotheekCompact: View {
    @State private var filter = ReceptFilter()
    @State private var pad: [NSManagedObjectID] = []
    @State private var toonInstellingen = false
    @State private var toonNieuw = false
    @State private var toonKnippen = false
    @State private var toonLabels = false
    @State private var verder: VerderKeuze?
    @State private var verderGestart: VerderKeuze?
    @State private var toonInbox = false
    @State private var toonBoodschappen = false
    @State private var selectie = ReceptSelectie()
    @Environment(InleesInbox.self) private var inbox
    @AppStorage(AppConfiguratie.sleutelBibliotheekWeergave) private var weergave = BibliotheekWeergave.kaarten

    /// - Parameter selectie: begin in selectiemodus (#40), voor voorbeelden en tests.
    init(selectie: ReceptSelectie = ReceptSelectie()) {
        _selectie = State(initialValue: selectie)
    }

    var body: some View {
        NavigationStack(path: $pad) {
            ReceptLijst(
                filter: filter, weergave: weergave,
                kop: AnyView(
                    VStack(spacing: 0) {
                        if let verder, filter.zoekterm.isEmpty {
                            VerderMetKaart(
                                keuze: verder, verder: { verderGestart = verder },
                                vergeet: { KookVoortgang().wis(recept: verder.stand.recept) }
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                        }
                        if !inbox.items.isEmpty, filter.zoekterm.isEmpty {
                            NogTeControlerenKaart(
                                aantal: inbox.items.count, bezig: inbox.items.contains { $0.status == .bezig }
                            ) { toonInbox = true }
                            .padding(.horizontal, 16)
                            .padding(.top, verder == nil ? 4 : 10)
                        }
                        FilterChips(filter: $filter, toonLabels: $toonLabels).padding(.vertical, 8)
                    }),
                selectie: $selectie
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if selectie.actief {
                    SelectieBalk(selectie: $selectie)
                } else {
                    HStack {
                        Spacer()
                        KnipKnop { toonKnippen = true }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle(selectie.actief ? "Kies recepten" : "Recepten")
            .searchable(text: $filter.zoekterm, prompt: "Zoek op recept of ingrediënt")
            .navigationDestination(for: NSManagedObjectID.self) { id in
                ReceptScherm(
                    id: id, naVerwijderen: { pad.removeAll { $0 == id } },
                    naVerplaatsen: { nieuw in pad = pad.map { $0 == id ? nieuw : $0 } })
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Instellingen", systemImage: "gearshape") { toonInstellingen = true }
                }
                // De eigen boodschappenlijst (#39), met het aantal open items.
                ToolbarItem(placement: .topBarTrailing) {
                    BoodschappenKnop { toonBoodschappen = true }
                }
                // Recepten kiezen voor één boodschappenlijst (#40).
                if !selectie.actief {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Selecteer") { selectie.start() }
                    }
                }
            }
            .navigationDestination(isPresented: $toonBoodschappen) { BoodschappenScherm() }
            .inleesInvoer(nieuw: { toonNieuw = true }, toonInbox: $toonInbox)
        }
        .verderMet($verder, gestart: $verderGestart)
        .toonReceptVerzoek(pad: $pad)
        .sheet(isPresented: $toonInstellingen) { InstellingenView() }
        .sheet(isPresented: $toonNieuw) { ReceptBewerken(recept: nil) }
        .sheet(isPresented: $toonKnippen) { KnipStart() }
        .sheet(isPresented: $toonLabels) {
            LabelFilter(filter: $filter)
                .presentationDetents([.medium, .large])
        }
    }
}

/// Eén horizontale rij chips met categorieën (of Alles / Zonder categorie), en rechts vast de chip
/// "Filter" die de labels (en, met Thuis-recepten, het kookboek) opent; het aantal gekozen filters
/// staat erop. Gelijknamige categorieën uit Mijn recepten en Thuis zijn één chip.
struct FilterChips: View {
    @Binding var filter: ReceptFilter
    @Binding var toonLabels: Bool

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "volgorde", ascending: true)])
    private var categorieen: FetchedResults<Categorie>
    @FetchRequest(sortDescriptors: []) private var labels: FetchedResults<ReceptLabel>
    @FetchRequest(sortDescriptors: []) private var recepten: FetchedResults<Recept>

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Chip(
                        titel: filter.kookboek?.naam ?? "Alles", symbool: filter.kookboek?.symbool,
                        aantal: inKookboek.count, gekozen: filter.categorie == .alles
                    ) {
                        filter.categorie = .alles
                    }
                    ForEach(zichtbareCategorieen) { groep in
                        Chip(
                            titel: groep.naam, symbool: groep.symbool, aantal: groep.aantal,
                            gekozen: filter.categorie == groep.keuze
                        ) {
                            filter.categorie = filter.categorie == groep.keuze ? .alles : groep.keuze
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
            if !labels.isEmpty || aantalFilters > 0 || toonKookboeken {
                Chip(
                    titel: "Filter", symbool: "line.3.horizontal.decrease",
                    aantal: aantalFilters == 0 ? nil : aantalFilters, gekozen: aantalFilters > 0
                ) {
                    toonLabels = true
                }
                .accessibilityLabel(aantalFilters == 0 ? "Filter" : "Filter, \(aantalFilters) gekozen")
                .padding(.leading, 4)
                .padding(.trailing)
            }
        }
    }

    private var aantalFilters: Int { filter.labels.count + (filter.kookboek == nil ? 0 : 1) }

    private var toonKookboeken: Bool {
        Bibliotheekkookboeken.toon(aantalThuis: recepten.filter(\.isThuis).count, gekozen: filter.kookboek)
    }

    private var inKookboek: [Recept] {
        recepten.filter { filter.kookboek == nil || $0.kookboekWaarde == filter.kookboek }
    }

    /// Lege categorieën staan niet in de rij; de gekozen categorie blijft staan, ook als hij leeg raakt.
    private var zichtbareCategorieen: [CategorieGroep] {
        CategorieGroep.groepeer(Array(categorieen), kookboek: filter.kookboek).filter {
            Self.toonInRij(aantal: $0.aantal, gekozen: filter.categorie == $0.keuze)
        }
    }

    static func toonInRij(aantal: Int, gekozen: Bool) -> Bool { aantal > 0 || gekozen }

    private var aantalZonderCategorie: Int {
        inKookboek.filter { ($0.categorieen ?? []).isEmpty }.count
    }
}
