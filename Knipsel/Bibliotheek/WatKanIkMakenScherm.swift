import CoreData
import Observation
import SwiftUI

// MARK: - Core Data naar de zoeker

extension WatKanIkMaken.Kandidaat {
    /// Een recept uit de opslag, met id = de objectID-URI.
    @MainActor
    init(_ recept: Recept) {
        self.init(
            id: recept.objectID.uriRepresentation().absoluteString, titel: recept.titelOfStandaard,
            minuten: recept.weergaveMinuten, laatstGekooktOp: recept.laatstGekooktOp,
            kookboek: recept.kookboekWaarde,
            ingredienten: recept.gesorteerdeIngredienten.map {
                WatKanIkMaken.Regel(BoodschappenInvoer($0), groep: $0.groep)
            })
    }
}

/// De Core Data-kant van "Wat kan ik maken?" (#44), los te testen met een opslag in het geheugen.
@MainActor
enum WatKanIkMakenOpslag {
    /// Alle recepten (of die van één kookboek) als kandidaat.
    static func kandidaten(in context: NSManagedObjectContext, kookboek: Kookboek?) -> [WatKanIkMaken.Kandidaat] {
        recepten(in: context, kookboek: kookboek).map(WatKanIkMaken.Kandidaat.init)
    }

    static func recepten(in context: NSManagedObjectContext, kookboek: Kookboek?) -> [Recept] {
        let verzoek = ReceptFilter(kookboek: kookboek).verzoek()
        verzoek.relationshipKeyPathsForPrefetching = ["ingredienten"]
        return ((try? context.fetch(verzoek)) ?? []).filter { !$0.isDeleted }
    }

    static func bekendeIngredienten(in context: NSManagedObjectContext, defaults: UserDefaults = .standard)
        -> [String]
    {
        WatKanIkMaken.bekendeIngredienten(
            in: kandidaten(in: context, kookboek: nil), meestalInHuis: .laad(uit: defaults))
    }

    /// Zet wat er voor dit recept nog ontbreekt op de eigen lijst van het kookboek van het recept (#39),
    /// met het recept als herkomst. Zonder schalen: de hoeveelheden uit het recept.
    @discardableResult
    static func zetOntbrekendeOpLijst(
        _ resultaat: WatKanIkMaken.Resultaat, context: NSManagedObjectContext,
        geheugen: AfdelingGeheugen = .laad()
    ) throws -> (resultaat: Boodschappenresultaat, kookboek: Kookboek) {
        let regels = BoodschappenLijst.regels(
            resultaat.ontbrekendeInvoer, factor: 1, meestalInHuis: MeestalInHuis(woorden: [])
        ).map(LijstRegel.init)
        let kookboek = resultaat.recept.kookboek
        let uit = try Boodschappenlijsten.zetOpLijst(
            regels, herkomst: resultaat.recept.titel, kookboek: kookboek, context: context, geheugen: geheugen)
        return (uit, kookboek)
    }
}

/// Siri zet hier "open Wat kan ik maken? met deze chip" neer (`WatKanIkMakenIntent`); de bibliotheek
/// neemt het af.
@MainActor
@Observable
final class WatKanIkMakenRouter {
    static let gedeeld = WatKanIkMakenRouter()

    struct Verzoek: Identifiable, Equatable, Sendable {
        let id = UUID()
        let ingredienten: [String]
    }

    private(set) var verzoek: Verzoek?

    func open(met ingredienten: [String]) {
        verzoek = Verzoek(ingredienten: ingredienten)
    }

    func neemAf() -> Verzoek? {
        defer { verzoek = nil }
        return verzoek
    }
}

extension View {
    /// Opent "Wat kan ik maken?" als Siri daarom vraagt; `versie` maakt het scherm opnieuw aan zodat
    /// het de nieuwe chip leest, ook als het al open stond.
    func watKanIkMakenVerzoek(toon: Binding<Bool>, versie: Binding<UUID>, voorOpenen: @escaping () -> Void = {})
        -> some View
    {
        onChange(of: WatKanIkMakenRouter.gedeeld.verzoek?.id, initial: true) {
            guard WatKanIkMakenRouter.gedeeld.neemAf() != nil else { return }
            voorOpenen()
            versie.wrappedValue = UUID()
            toon.wrappedValue = true
        }
    }
}

// MARK: - De ingang in de bibliotheek

/// "Wat kan ik maken? · prei, eieren ›" bovenaan de bibliotheek (iPhone en iPad), in de stijl van
/// "Vandaag: …" (#41). Met de ingrediënten die je de vorige keer opgaf.
struct WatKanIkMakenRij: View {
    let actie: () -> Void
    @State private var chips: [String] = WatKanIkMaken.laadChips()

    var body: some View {
        Button(action: actie) {
            HStack(spacing: 8) {
                Image(systemName: "basket")
                    .foregroundStyle(Kookkleuren.accent)
                Text("Wat kan ik maken?")
                    .fontWeight(.semibold)
                    .layoutPriority(1)
                Text(chips.joined(separator: ", "))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .font(.subheadline)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            chips.isEmpty ? "Wat kan ik maken?" : "Wat kan ik maken met \(chips.joined(separator: ", "))"
        )
        .accessibilityHint("Zoek recepten met wat je in huis hebt")
        .onAppear { chips = WatKanIkMaken.laadChips() }
    }
}

// MARK: - Het scherm

/// "Wat kan ik maken?" (#44, schets A): wat je in huis hebt als chips, wat je meestal in huis hebt telt
/// mee, en de recepten in groepen op hoeveel er nog ontbreekt. Tik = recept; 🛒 zet wat ontbreekt op
/// de lijst. Met één chip ("met prei", C) kies je Snelst of Lang niet gekookt.
struct WatKanIkMakenScherm: View {
    /// Het kookboek van de bibliotheek (`nil` = alles).
    let kookboek: Kookboek?
    private let defaults: UserDefaults

    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: []) private var alleRecepten: FetchedResults<Recept>

    @State private var chips: [String]
    @State private var invoer = ""
    @State private var sortering: WatKanIkMaken.Sortering
    @State private var toonMeer = false
    @State private var meestal: MeestalInHuis
    @State private var kandidaten: [WatKanIkMaken.Kandidaat] = []
    @State private var bekend: [String] = []
    @State private var resultaten: [WatKanIkMaken.Resultaat] = []
    @State private var geopend: NSManagedObjectID?
    @State private var melding: String?
    @State private var vel: WatKanIkMaken.Resultaat?
    @FocusState private var invoerActief: Bool

    /// - Parameters:
    ///   - chips: om mee te beginnen; standaard wat je de vorige keer opgaf.
    ///   - sortering: met één chip (voor voorbeelden en tests).
    init(
        kookboek: Kookboek?, chips: [String]? = nil, sortering: WatKanIkMaken.Sortering = .snelst,
        toonMeer: Bool = false, defaults: UserDefaults = .standard
    ) {
        self.kookboek = kookboek
        self.defaults = defaults
        _chips = State(initialValue: chips ?? WatKanIkMaken.laadChips(uit: defaults))
        _sortering = State(initialValue: sortering)
        _toonMeer = State(initialValue: toonMeer)
        _meestal = State(initialValue: MeestalInHuis.laad(uit: defaults))
    }

    var body: some View {
        List {
            Section {
                invoerVeld
                if invoerActief || !invoer.isEmpty {
                    suggestieRij
                }
                NavigationLink {
                    BoodschappenInstellingen(defaults: defaults)
                } label: {
                    SwiftUI.Label(WatKanIkMaken.basisRegel(meestal), systemImage: "house")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .accessibilityHint("Pas aan wat je meestal in huis hebt")
                if chips.count == 1, !resultaten.isEmpty {
                    Picker("Sorteer", selection: $sortering) {
                        Text(WatKanIkMaken.Sortering.snelst.naam).tag(WatKanIkMaken.Sortering.snelst)
                        Text(WatKanIkMaken.Sortering.langNietGekookt.naam).tag(
                            WatKanIkMaken.Sortering.langNietGekookt)
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                }
            }
            ForEach(WatKanIkMaken.groepen(resultaten), id: \.groep) { groep in
                Section {
                    if groep.groep == .nogMeer, !toonMeer {
                        Button("Toon meer (\(groep.resultaten.count))") { toonMeer = true }
                    } else {
                        ForEach(groep.resultaten) { resultaat in
                            rij(resultaat)
                        }
                    }
                } header: {
                    Text(groep.groep.titel)
                }
            }
        }
        .overlay {
            if chips.isEmpty {
                ContentUnavailableView(
                    "Wat heb je in huis?", systemImage: "basket",
                    description: Text(
                        "Typ wat je in huis hebt, zoals prei, eieren of kaas. Knipsel zoekt recepten die erbij passen en laat zien wat er nog mist."
                    )
                )
                .padding(.top, 160)
                .allowsHitTesting(false)
            } else if resultaten.isEmpty, !kandidaten.isEmpty || alleRecepten.isEmpty {
                ContentUnavailableView(
                    "Geen recepten met \(chips.joined(separator: ", "))", systemImage: "magnifyingglass",
                    description: Text(
                        "Geen van je recepten gebruikt dit. Probeer een ander of algemener woord, zoals ui in plaats van rode ui."
                    )
                )
                .padding(.top, 160)
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            if let melding {
                Text(melding)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: melding) {
                        try? await Task.sleep(for: .seconds(2.5))
                        withAnimation { self.melding = nil }
                    }
            }
        }
        .navigationTitle("Wat kan ik maken?")
        .toolbar {
            if !chips.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Wis") { wijzig([]) }
                        .accessibilityHint("Wist alle ingrediënten")
                }
            }
        }
        .navigationDestination(item: $geopend) { id in
            ReceptScherm(id: id, naVerwijderen: { geopend = nil }, naVerplaatsen: { geopend = $0 })
        }
        .sheet(item: $vel) { resultaat in
            BoodschappenVel(
                recept: resultaat.recept.titel, porties: 0, invoer: resultaat.ontbrekendeInvoer, factor: 1,
                bestemming: HerinneringenDienst.gedeeld, kookboek: resultaat.recept.kookboek
            )
            .presentationDetents([.medium, .large])
        }
        .onAppear {
            meestal = MeestalInHuis.laad(uit: defaults)
            laad()
        }
        .onChange(of: alleRecepten.count) { laad() }
        .onChange(of: sortering) { herbereken() }
        .onChange(of: meestal) { herbereken() }
    }

    // MARK: - Invoer

    private var invoerVeld: some View {
        Stroomopmaak(ruimte: 8) {
            ForEach(chips, id: \.self) { chip in
                Button {
                    wijzig(chips.filter { $0 != chip })
                } label: {
                    HStack(spacing: 4) {
                        Text(chip)
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.accentColor.opacity(0.18), in: Capsule())
                    .foregroundStyle(.primary)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(chip), verwijder")
            }
            TextField(chips.isEmpty ? "prei, eieren, kaas…" : "＋ nog iets…", text: $invoer)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($invoerActief)
                .frame(minWidth: 140)
                .padding(.vertical, 7)
                .onSubmit {
                    neemInvoerOver()
                    invoerActief = true
                }
                .onChange(of: invoer) { _, nieuw in
                    // Een komma (ook bij dicteren) maakt er meteen een chip van.
                    if nieuw.contains(",") { neemInvoerOver() }
                }
                .accessibilityLabel("Ingrediënt toevoegen")
        }
        .padding(.vertical, 4)
    }

    private var suggestieRij: some View {
        let lijst = WatKanIkMaken.suggesties(voor: invoer, bekend: bekend, gekozen: chips)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(lijst, id: \.self) { naam in
                    Chip(titel: naam, symbool: "plus", gekozen: false) {
                        invoer = ""
                        wijzig(WatKanIkMaken.voegToe(naam, aan: chips))
                    }
                }
            }
        }
        .opacity(lijst.isEmpty ? 0 : 1)
        .accessibilityLabel("Suggesties")
    }

    private func neemInvoerOver() {
        let tekst = invoer
        invoer = ""
        wijzig(WatKanIkMaken.voegToe(tekst, aan: chips))
    }

    private func wijzig(_ nieuw: [String]) {
        chips = nieuw
        WatKanIkMaken.bewaar(nieuw, in: defaults)
        if nieuw.count != 1 { sortering = .snelst }
        toonMeer = false
        herbereken()
    }

    // MARK: - Resultaten

    private func laad() {
        kandidaten = WatKanIkMakenOpslag.kandidaten(in: context, kookboek: kookboek)
        bekend = WatKanIkMaken.bekendeIngredienten(in: kandidaten, meestalInHuis: meestal)
        herbereken()
    }

    private func herbereken() {
        resultaten = WatKanIkMaken.zoek(
            chips, in: kandidaten, meestalInHuis: meestal, sortering: chips.count == 1 ? sortering : .passend)
    }

    private func recept(_ resultaat: WatKanIkMaken.Resultaat) -> Recept? {
        guard let url = URL(string: resultaat.recept.id),
            let id = context.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url),
            let recept = try? context.existingObject(with: id) as? Recept, !recept.isDeleted
        else { return nil }
        return recept
    }

    @ViewBuilder
    private func rij(_ resultaat: WatKanIkMaken.Resultaat) -> some View {
        if let recept = recept(resultaat) {
            HStack(spacing: 12) {
                Button {
                    geopend = recept.objectID
                } label: {
                    WatKanIkMakenRegel(recept: recept, resultaat: resultaat, sortering: toonSortering)
                }
                .buttonStyle(.plain)
                if !resultaat.ontbrekend.isEmpty {
                    Button {
                        zetOpLijst(resultaat)
                    } label: {
                        Image(systemName: "cart.badge.plus")
                            .font(.title3)
                            .foregroundStyle(Kookkleuren.accent)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Ontbrekende op de lijst")
                    .accessibilityHint(resultaat.mistTekst)
                }
            }
            .swipeActions(edge: .trailing) {
                if !resultaat.ontbrekend.isEmpty {
                    Button("Op de lijst", systemImage: "cart.badge.plus") { zetOpLijst(resultaat) }
                        .tint(Kookkleuren.accent)
                }
            }
            .contextMenu {
                Button("Open recept", systemImage: "book") { geopend = recept.objectID }
                if !resultaat.ontbrekend.isEmpty {
                    Button("Ontbrekende op de lijst", systemImage: "cart.badge.plus") { zetOpLijst(resultaat) }
                }
            }
        }
    }

    /// Met één chip toont de regel de tijd of hoe lang geleden.
    private var toonSortering: WatKanIkMaken.Sortering { chips.count == 1 ? sortering : .passend }

    /// Naar de lijst uit Instellingen › Boodschappen (#39): de eigen lijst meteen, Herinneringen via het vel.
    private func zetOpLijst(_ resultaat: WatKanIkMaken.Resultaat) {
        switch BoodschappenStandaard.laad(uit: defaults) {
        case .knipsel:
            do {
                let (uit, boek) = try WatKanIkMakenOpslag.zetOntbrekendeOpLijst(resultaat, context: context)
                withAnimation { melding = VelBestemming.lijst(boek).bevestiging(aantal: uit.aantal) }
                Task { await OnbekendeAfdelingen.gedeeld.deelIn(context: context) }
            } catch {
                withAnimation { melding = "Op de lijst zetten lukte niet" }
            }
        case .herinneringen:
            vel = resultaat
        }
    }
}

/// Eén resultaat: kaart-symbool, titel, "mist: bladerdeeg" of "alles in huis" met de tijd, de
/// varianten ("rode ui ≈ ui") en een kleine meter.
struct WatKanIkMakenRegel: View {
    @ObservedObject var recept: Recept
    let resultaat: WatKanIkMaken.Resultaat
    var sortering: WatKanIkMaken.Sortering = .passend
    var nu: Date = .now

    var body: some View {
        HStack(spacing: 12) {
            CategorieIcoon(recept: recept)
            VStack(alignment: .leading, spacing: 3) {
                Text(resultaat.recept.titel)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(onderregel)
                    .font(.subheadline)
                    .foregroundStyle(resultaat.ontbrekend.isEmpty ? Color.green : .secondary)
                    .lineLimit(2)
                if !resultaat.varianten.isEmpty {
                    Text(resultaat.varianten.map(\.tekst).joined(separator: ", "))
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
                ProgressView(value: resultaat.aandeel)
                    .tint(resultaat.ontbrekend.isEmpty ? Color.green : Kookkleuren.accent)
                    .frame(maxWidth: 90)
                    .accessibilityLabel("\(resultaat.inHuis) van \(resultaat.nodig) in huis")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var onderregel: String {
        var delen = [resultaat.mistTekst]
        if sortering == .langNietGekookt {
            delen.append(WatKanIkMakenRegel.geleden(resultaat.recept.laatstGekooktOp, nu: nu))
        } else if let tijd = Weergave.tijd(minuten: resultaat.recept.minuten) {
            delen.append(tijd)
        }
        return delen.joined(separator: " · ")
    }

    /// "nooit gekookt", "vandaag gekookt", "3 dagen niet", "8 wk niet".
    static func geleden(_ datum: Date?, nu: Date) -> String {
        guard let datum else { return "nooit gekookt" }
        let dagen = Int(nu.timeIntervalSince(datum) / 86_400)
        switch dagen {
        case ..<1: return "vandaag gekookt"
        case 1: return "1 dag niet"
        case ..<14: return "\(dagen) dagen niet"
        default: return "\(dagen / 7) wk niet"
        }
    }
}
