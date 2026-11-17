import CoreData
import SwiftUI

/// iPad (en brede vensters): twee kolommen — de zijbalk met categorieën en labels, en rechts een
/// `NavigationStack` met het kaartenraster (of de lijst, Instellingen › Weergave). Een recept opent
/// over het raster (push); er is geen lege kolom "Kies een recept" meer (U6). Bovenaan "Verder met…"
/// (U8) met daarnaast "Nog te controleren" (#18), en *Knip* zweeft rechtsonder zoals op de iPhone.
/// Een link of tekst uit Safari kun je op het raster slepen.
struct BibliotheekSplit: View {
    @Environment(\.managedObjectContext) private var context
    @State private var filter = ReceptFilter()
    @State private var zijbalkKeuze: ZijbalkKeuze? = .kookboek(nil)
    @State private var pad: [NSManagedObjectID] = []
    @State private var toonInstellingen = false
    @State private var toonNieuw = false
    @State private var toonKnippen = false
    @State private var verder: VerderKeuze?
    @State private var verderGestart: VerderKeuze?
    @State private var toonInbox = false
    @State private var selectie = ReceptSelectie()
    @Environment(InleesInbox.self) private var inbox
    @AppStorage(AppConfiguratie.sleutelBibliotheekWeergave) private var weergave = BibliotheekWeergave.kaarten
    /// Zijbalk standaard zichtbaar, zoals in de schets.
    @State private var kolommen: NavigationSplitViewVisibility = .all

    /// - Parameter selectie: begin in selectiemodus (#40), voor voorbeelden en tests.
    init(selectie: ReceptSelectie = ReceptSelectie()) {
        _selectie = State(initialValue: selectie)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $kolommen) {
            Zijbalk(keuze: $zijbalkKeuze, labels: $filter.labels, kookboek: filter.kookboek)
                .navigationTitle("Knipsel")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Instellingen", systemImage: "gearshape") { toonInstellingen = true }
                    }
                }
        } detail: {
            if zijbalkKeuze == .boodschappen {
                // De eigen boodschappenlijst (#39) in de detailkolom.
                NavigationStack { BoodschappenScherm() }
            } else if zijbalkKeuze == .weekmenu {
                // Het weekmenu (#41) in de detailkolom.
                NavigationStack { WeekScherm() }
            } else {
                receptenKolom
            }
        }
        .onChange(of: zijbalkKeuze) { _, nieuw in
            switch nieuw ?? .kookboek(nil) {
            case .boodschappen, .weekmenu:
                break
            case .kookboek(let kookboek):
                // Een kookboek kiezen begint met al zijn recepten.
                filter.kookboek = kookboek
                filter.categorie = .alles
            case .categorie(let categorie):
                // Binnen het gekozen kookboek.
                filter.categorie = categorie
            }
            // Een andere categorie: terug naar het raster.
            pad.removeAll()
        }
        .verderMet($verder, gestart: $verderGestart)
        .toonReceptVerzoek(pad: $pad)
        .sheet(isPresented: $toonInstellingen) { InstellingenView() }
        .sheet(isPresented: $toonNieuw) { ReceptBewerken(recept: nil) }
        .sheet(isPresented: $toonKnippen) { KnipStart() }
    }

    private var receptenKolom: some View {
        NavigationStack(path: $pad) {
            ReceptLijst(filter: filter, weergave: weergave, kop: kop, selectie: $selectie)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if selectie.actief {
                        SelectieBalk(selectie: $selectie)
                    } else {
                        HStack {
                            Spacer()
                            KnipKnop { toonKnippen = true }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 12)
                    }
                }
                .navigationTitle(selectie.actief ? "Kies recepten" : lijstTitel)
                .toolbar {
                    // Recepten kiezen voor één boodschappenlijst (#40).
                    if !selectie.actief {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Selecteer") { selectie.start() }
                        }
                    }
                }
                .searchable(text: $filter.zoekterm, prompt: "Zoek op recept of ingrediënt")
                .navigationDestination(for: NSManagedObjectID.self) { id in
                    ReceptScherm(
                        id: id, naVerwijderen: { pad.removeAll { $0 == id } },
                        naVerplaatsen: { nieuw in pad = pad.map { $0 == id ? nieuw : $0 } })
                }
                .inleesInvoer(nieuw: { toonNieuw = true }, toonInbox: $toonInbox, slepen: true)
        }
    }

    /// "Verder met…" en "Nog te controleren" boven het raster, naast elkaar als er ruimte is; niet
    /// tijdens het zoeken.
    private var kop: AnyView? {
        guard filter.zoekterm.isEmpty else { return nil }
        let inboxZichtbaar = !inbox.items.isEmpty
        guard verder != nil || inboxZichtbaar else {
            // Alleen "Vandaag: …" (#41); verdwijnt vanzelf als er niets gepland is.
            return AnyView(
                VandaagRij()
                    .frame(maxWidth: 560, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, weergave == .kaarten ? 24 : 16)
                    .padding(.top, 4))
        }
        return AnyView(
            VStack(alignment: .leading, spacing: 10) {
                VandaagRij()
                    .frame(maxWidth: 560, alignment: .leading)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 12) { kopKaarten }
                    VStack(spacing: 10) { kopKaarten }
                }
            }
            .padding(.horizontal, weergave == .kaarten ? 24 : 16)
            .padding(.top, 4)
            .padding(.bottom, 12))
    }

    @ViewBuilder private var kopKaarten: some View {
        if let verder {
            VerderMetKaart(
                keuze: verder, verder: { verderGestart = verder },
                vergeet: { KookVoortgang().wis(recept: verder.stand.recept) }
            )
            .frame(minWidth: 420)
        }
        if !inbox.items.isEmpty {
            NogTeControlerenKaart(
                aantal: inbox.items.count, bezig: inbox.items.contains { $0.status == .bezig }
            ) { toonInbox = true }
            .frame(minWidth: 320)
        }
    }

    private var lijstTitel: String {
        let categorie: String? =
            switch filter.categorie {
            case .alles: nil
            case .zonderCategorie: "Zonder categorie"
            case .categorie(let naam): naam
            }
        switch (filter.kookboek, categorie) {
        case (nil, nil): return "Alle recepten"
        case (nil, let categorie?): return categorie
        case (let kookboek?, nil): return kookboek.naam
        case (let kookboek?, let categorie?): return "\(kookboek.naam) · \(categorie)"
        }
    }
}

/// Wat er in de zijbalk gekozen is: een kookboek (Alles, Mijn recepten, Thuis) of een categorie
/// binnen het gekozen kookboek.
enum ZijbalkKeuze: Hashable {
    /// De eigen boodschappenlijst (#39), bovenaan.
    case boodschappen
    /// Het weekmenu (#41), onder de boodschappen.
    case weekmenu
    case kookboek(Kookboek?)
    case categorie(CategorieKeuze)
}

/// Zijbalk: kookboeken (Alles, en met Thuis-recepten ook Mijn recepten en Thuis), categorieën met
/// aantallen en labels (aan/uit, combineerbaar met de categorie). Gelijknamige categorieën en labels
/// uit beide kookboeken staan er één keer.
struct Zijbalk: View {
    @Binding var keuze: ZijbalkKeuze?
    @Binding var labels: Set<String>
    /// Het gekozen kookboek: de aantallen tellen alleen daarin.
    var kookboek: Kookboek?

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "volgorde", ascending: true)])
    private var categorieen: FetchedResults<Categorie>
    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(
            key: "naam", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
    ])
    private var alleLabels: FetchedResults<ReceptLabel>
    @FetchRequest(sortDescriptors: []) private var recepten: FetchedResults<Recept>
    @FetchRequest(sortDescriptors: [], predicate: Boodschappenlijsten.predicaatOpen(kookboek: nil))
    private var openBoodschappen: FetchedResults<BoodschappenItem>

    var body: some View {
        List(selection: $keuze) {
            Section {
                SwiftUI.Label("Boodschappen", systemImage: "cart")
                    .badge(openBoodschappen.count)
                    .tag(ZijbalkKeuze.boodschappen)
                SwiftUI.Label("Weekmenu", systemImage: "calendar")
                    .tag(ZijbalkKeuze.weekmenu)
            }
            Section("Kookboeken") {
                SwiftUI.Label("Alles", systemImage: "books.vertical")
                    .badge(recepten.count)
                    .tag(ZijbalkKeuze.kookboek(nil))
                if Bibliotheekkookboeken.toon(aantalThuis: aantal(in: .thuis), gekozen: kookboek) {
                    ForEach(Kookboek.allCases) { boek in
                        SwiftUI.Label(boek.naam, systemImage: boek.symbool)
                            .badge(aantal(in: boek))
                            .tag(ZijbalkKeuze.kookboek(boek))
                    }
                }
            }
            Section("Categorieën") {
                ForEach(zichtbareCategorieen) { groep in
                    SwiftUI.Label(groep.naam, systemImage: groep.symbool)
                        .badge(groep.aantal)
                        .tag(ZijbalkKeuze.categorie(groep.keuze))
                }
                if aantalZonderCategorie > 0 {
                    SwiftUI.Label("Zonder categorie", systemImage: "tray")
                        .badge(aantalZonderCategorie)
                        .tag(ZijbalkKeuze.categorie(.zonderCategorie))
                }
            }
            if !labelGroepen.isEmpty {
                Section("Labels") {
                    ForEach(labelGroepen) { label in
                        let gekozen = labels.contains(label.naam)
                        Button {
                            if gekozen {
                                labels.remove(label.naam)
                            } else {
                                labels.insert(label.naam)
                            }
                        } label: {
                            HStack {
                                SwiftUI.Label(label.naam, systemImage: gekozen ? "checkmark.circle.fill" : "tag")
                                Spacer()
                                Text(label.aantal, format: .number).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityAddTraits(gekozen ? .isSelected : [])
                    }
                }
            }
        }
    }

    private func aantal(in boek: Kookboek) -> Int {
        recepten.filter { $0.kookboekWaarde == boek }.count
    }

    private var labelGroepen: [LabelGroep] { LabelGroep.groepeer(Array(alleLabels), kookboek: kookboek) }

    /// Zoals de chiprij op de iPhone: lege categorieën niet tonen, de gekozen categorie wel.
    private var zichtbareCategorieen: [CategorieGroep] {
        CategorieGroep.groepeer(Array(categorieen), kookboek: kookboek).filter {
            FilterChips.toonInRij(aantal: $0.aantal, gekozen: keuze == .categorie($0.keuze))
        }
    }

    private var aantalZonderCategorie: Int {
        recepten.filter { ($0.categorieen ?? []).isEmpty && (kookboek == nil || $0.kookboekWaarde == kookboek) }.count
    }
}

/// Wanneer de bibliotheek de keuze tussen de kookboeken toont: alleen als er iets in Thuis staat
/// (of Thuis/Mijn recepten nog gekozen is) — zonder Thuis is er niets te kiezen.
enum Bibliotheekkookboeken {
    static func toon(aantalThuis: Int, gekozen: Kookboek?) -> Bool { aantalThuis > 0 || gekozen != nil }
}
