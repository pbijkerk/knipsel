import CoreData
import SwiftUI

/// Eén regel in de receptenlijst: categoriesymbool op de kaartkleur, titel en "Categorie · tijd · bron".
struct ReceptRij: View {
    @ObservedObject var recept: Recept

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CategorieIcoon(recept: recept)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(recept.titelOfStandaard)
                        .font(.system(.headline, design: .serif))
                    if recept.isThuis {
                        Image(systemName: Kookboek.thuis.symbool)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Thuis")
                    }
                }
                if let onderregel {
                    Text(onderregel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !recept.gesorteerdeLabels.isEmpty {
                    Text(recept.gesorteerdeLabels.map(\.naamOfStandaard).joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var onderregel: String? {
        let categorieen = recept.gesorteerdeCategorieen.map(\.naamOfStandaard).joined(separator: ", ")
        let delen = [
            categorieen.isEmpty ? nil : categorieen,
            Weergave.tijd(minuten: recept.weergaveMinuten),
            recept.bronNaam,
        ].compactMap { $0 }
        return delen.isEmpty ? nil : delen.joined(separator: " · ")
    }
}

/// De gefilterde recepten. Een tik opent het recept in de omringende `NavigationStack`, als kaart of
/// als regel (`weergave`); op iPhone en iPad hetzelfde.
struct ReceptLijst: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.horizontalSizeClass) private var breedte
    @FetchRequest private var recepten: FetchedResults<Recept>
    private let filter: ReceptFilter
    private let weergave: BibliotheekWeergave
    private let kop: AnyView?
    @State private var teVerwijderen: Recept?
    @State private var foutmelding: String?

    /// Kaarten van minimaal 160 pt breed: 2 kolommen op een iPhone. Op iPad minimaal 180 pt: 4 breed
    /// naast de zijbalk in een liggend 11-inch-scherm (1180 pt), meer als er ruimte is.
    private var kolommen: [GridItem] {
        let minimum: CGFloat = breedte == .regular ? Self.minimaleKaartbreedteBreed : Self.minimaleKaartbreedte
        return [GridItem(.adaptive(minimum: minimum), spacing: 12, alignment: .top)]
    }

    static let minimaleKaartbreedte: CGFloat = 160
    static let minimaleKaartbreedteBreed: CGFloat = 180

    /// - Parameter kop: iets boven de recepten dat meescrolt ("Verder met…", de filterchips op iPhone).
    init(filter: ReceptFilter, weergave: BibliotheekWeergave = .lijst, kop: AnyView? = nil) {
        self.filter = filter
        self.weergave = weergave
        self.kop = kop
        _recepten = FetchRequest(
            sortDescriptors: ReceptFilter.sortering, predicate: filter.predicaat, animation: .default)
    }

    var body: some View {
        Group {
            if recepten.isEmpty {
                VStack(spacing: 0) {
                    if let kop { kop }
                    leeg
                }
                .frame(maxHeight: .infinity, alignment: .top)
            } else if weergave == .kaarten {
                ScrollView {
                    VStack(spacing: 0) {
                        if let kop { kop }
                        LazyVGrid(columns: kolommen, spacing: 12) {
                            ForEach(recepten, id: \.objectID) { recept in
                                NavigationLink(value: recept.objectID) {
                                    ReceptKaart(recept: recept)
                                }
                                .buttonStyle(.plain)
                                .contextMenu { verwijderKnop(recept) }
                            }
                        }
                        .padding(.horizontal, breedte == .regular ? 24 : 16)
                        .padding(.top, 4)
                        .padding(.bottom, 16)
                    }
                }
            } else {
                List {
                    if let kop {
                        kop
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                    }
                    ForEach(recepten, id: \.objectID) { recept in
                        NavigationLink(value: recept.objectID) {
                            ReceptRij(recept: recept)
                        }
                        .swipeActions { verwijderKnop(recept) }
                        .contextMenu { verwijderKnop(recept) }
                    }
                }
                .listStyle(.plain)
            }
        }
        .confirmationDialog(
            "Recept verwijderen?",
            isPresented: Binding(get: { teVerwijderen != nil }, set: { if !$0 { teVerwijderen = nil } }),
            titleVisibility: .visible,
            presenting: teVerwijderen
        ) { recept in
            Button("Verwijder \u{201C}\(recept.titelOfStandaard)\u{201D}", role: .destructive) {
                context.delete(recept)
                do { try context.save() } catch { foutmelding = error.localizedDescription }
            }
        } message: { _ in
            Text("Dit kan niet ongedaan worden gemaakt.")
        }
        .alert(
            "Er ging iets mis", isPresented: Binding(get: { foutmelding != nil }, set: { if !$0 { foutmelding = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(foutmelding ?? "")
        }
    }

    private func verwijderKnop(_ recept: Recept) -> some View {
        Button(role: .destructive) {
            teVerwijderen = recept
        } label: {
            SwiftUI.Label("Verwijder", systemImage: "trash")
        }
    }

    @ViewBuilder private var leeg: some View {
        let zoekterm = filter.zoekterm.trimmingCharacters(in: .whitespaces)
        if !zoekterm.isEmpty {
            ContentUnavailableView.search(text: zoekterm)
        } else if !filter.isLeeg {
            ContentUnavailableView(
                "Geen recepten", systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Geen recepten met deze categorie en labels."))
        } else {
            ContentUnavailableView {
                SwiftUI.Label("Nog geen knipsels", systemImage: "scissors")
            } description: {
                Text("Knip een recept uit de krant, of voeg er een toe met de plusknop.")
            }
        }
    }
}

/// Toont een recept op basis van zijn ID; ook als het intussen verwijderd is (bijv. op een ander toestel).
struct ReceptScherm: View {
    @Environment(\.managedObjectContext) private var context
    let id: NSManagedObjectID
    var naVerwijderen: () -> Void = {}
    /// Na verplaatsen naar het andere kookboek (nieuw objectID).
    var naVerplaatsen: (NSManagedObjectID) -> Void = { _ in }

    var body: some View {
        // Ook weg als het recept uit de store verdween (Thuis gestopt): dan geen context meer.
        if let recept = try? context.existingObject(with: id) as? Recept, !recept.isDeleted,
            recept.managedObjectContext != nil
        {
            ReceptWeergave(recept: recept, naVerwijderen: naVerwijderen, naVerplaatsen: naVerplaatsen)
        } else {
            ContentUnavailableView("Recept niet gevonden", systemImage: "scissors")
        }
    }
}
