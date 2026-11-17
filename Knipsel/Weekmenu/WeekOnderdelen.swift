import CoreData
import SwiftUI

/// Zeven dagknoppen naast elkaar ("ma 23"), voor *Verplaats naar…* en *Plan in*. Bezette dagen hebben
/// een stip; dagen vóór vandaag zijn uit.
struct DagKnoppen: View {
    let dagen: [Date]
    let gekozen: Date?
    var bezet: Set<Date> = []
    let vandaag: Date
    let kalender: Calendar
    let kies: (Date) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(dagen, id: \.self) { dag in
                let aan = gekozen.map { kalender.isDate($0, inSameDayAs: dag) } ?? false
                let voorbij = dag < vandaag
                Button {
                    kies(dag)
                } label: {
                    VStack(spacing: 2) {
                        Text(Weekplanning.afkorting(dag, kalender: kalender))
                            .font(.caption.weight(.semibold))
                        Text("\(kalender.component(.day, from: dag))")
                            .font(.body.weight(.semibold))
                            .monospacedDigit()
                        Circle()
                            .fill(bezet.contains(dag) ? (aan ? Color.white : Color.secondary) : .clear)
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .foregroundStyle(aan ? Color.white : (voorbij ? Color.secondary.opacity(0.5) : .primary))
                    .background(
                        aan ? AnyShapeStyle(Kookkleuren.accent) : AnyShapeStyle(Color.secondary.opacity(0.12)),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay {
                        if kalender.isDate(dag, inSameDayAs: vandaag), !aan {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Kookkleuren.accent, lineWidth: 1.5)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(voorbij)
                .accessibilityLabel(
                    Weekplanning.langeDag(dag, kalender: kalender) + (bezet.contains(dag) ? ", al gepland" : "")
                )
                .accessibilityAddTraits(aan ? .isSelected : [])
            }
        }
    }
}

// MARK: - Kiezer voor een lege dag

/// Een recept (of een notitie) kiezen voor een dag: zoeklijst van de recepten in dit kookboek, met
/// bovenaan een notitie als "Uit eten".
struct ReceptKiezer: View {
    let dag: Date
    let kookboek: Kookboek
    let kalender: Calendar
    let kies: (Recept) -> Void
    let notitie: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @FetchRequest private var recepten: FetchedResults<Recept>
    @State private var zoekterm = ""
    @State private var tekst = ""

    static let voorbeelden = ["Uit eten", "Afhalen", "Restjes uit de vriezer"]

    init(
        dag: Date, kookboek: Kookboek, kalender: Calendar, zoekterm: String = "", kies: @escaping (Recept) -> Void,
        notitie: @escaping (String) -> Void
    ) {
        self.dag = dag
        self.kookboek = kookboek
        self.kalender = kalender
        self.kies = kies
        self.notitie = notitie
        _zoekterm = State(initialValue: zoekterm)
        _recepten = FetchRequest(
            sortDescriptors: [
                NSSortDescriptor(
                    key: "titel", ascending: true,
                    selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
            ],
            predicate: NSPredicate(format: "kookboek == %@", kookboek.rawValue))
    }

    private var gefilterd: [Recept] {
        let term = zoekterm.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return Array(recepten) }
        return recepten.filter { $0.titelOfStandaard.localizedStandardContains(term) }
    }

    var body: some View {
        NavigationStack {
            List {
                if zoekterm.isEmpty {
                    Section {
                        HStack {
                            TextField("Notitie, bijvoorbeeld Uit eten", text: $tekst)
                                .submitLabel(.done)
                                .onSubmit { bewaarNotitie(tekst) }
                            if !tekst.trimmingCharacters(in: .whitespaces).isEmpty {
                                Button("Zet erop") { bewaarNotitie(tekst) }
                                    .fontWeight(.semibold)
                                    .buttonStyle(.borderless)
                            }
                        }
                        .frame(minHeight: 44)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Self.voorbeelden, id: \.self) { voorbeeld in
                                    Button(voorbeeld) { bewaarNotitie(voorbeeld) }
                                        .buttonStyle(.bordered)
                                        .buttonBorderShape(.capsule)
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 10, trailing: 16))
                    } header: {
                        Text("Notitie")
                    }
                }
                Section {
                    ForEach(gefilterd, id: \.objectID) { recept in
                        Button {
                            kies(recept)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                CategorieIcoon(recept: recept)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(recept.titelOfStandaard)
                                        .font(.system(.body, design: .serif).weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                    if let regel = regel(recept) {
                                        Text(regel)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if gefilterd.isEmpty {
                        Text(recepten.isEmpty ? "Nog geen recepten in \(kookboek.naam)." : "Geen recept gevonden.")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(kookboek == .thuis ? "Recepten in Thuis" : "Recepten")
                }
            }
            .listStyle(.insetGrouped)
            .searchable(
                text: $zoekterm, placement: .navigationBarDrawer(displayMode: .always), prompt: "Zoek een recept"
            )
            .navigationTitle(Weekplanning.langeDag(dag, kalender: kalender))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sluit", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .tint(Kookkleuren.accent)
    }

    private func regel(_ recept: Recept) -> String? {
        let delen = [
            Weekweergave.tijd(totaal: Int(recept.totaleTijdMinuten), bereiding: Int(recept.bereidingstijdMinuten)),
            recept.laatstGekooktOp.map { "gekookt \($0.formatted(.relative(presentation: .named)))" },
        ].compactMap { $0 }
        return delen.isEmpty ? nil : delen.joined(separator: " · ")
    }

    private func bewaarNotitie(_ tekst: String) {
        guard !tekst.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        notitie(tekst)
        dismiss()
    }
}

// MARK: - Acties op een gevulde dag

/// Het vel op een gevulde dag: open, kook dit, porties, kook dubbel, verplaats naar…, wis.
struct DagActies: View {
    enum Actie: Equatable {
        case open
        case kook
        case porties(Int)
        case kookDubbel
        case verplaats(Date)
        case kiesOpnieuw
        case wis
    }

    let maaltijd: GeplandeMaaltijd
    let alle: [GeplandeMaaltijd]
    let recept: Recept?
    let dagen: [Date]
    let vandaag: Date
    let kalender: Calendar
    let actie: (Actie) -> Void

    @State private var porties: Int

    init(
        maaltijd: GeplandeMaaltijd, alle: [GeplandeMaaltijd], recept: Recept?, dagen: [Date], vandaag: Date,
        kalender: Calendar, actie: @escaping (Actie) -> Void
    ) {
        self.maaltijd = maaltijd
        self.alle = alle
        self.recept = recept
        self.dagen = dagen
        self.vandaag = vandaag
        self.kalender = kalender
        self.actie = actie
        _porties = State(initialValue: maaltijd.porties > 0 ? maaltijd.porties : Int(recept?.porties ?? 0))
    }

    private var heeftRestjes: Bool { alle.contains { $0.restjesVan == maaltijd.id } }

    private var kop: String {
        switch maaltijd.soort {
        case .recept: maaltijd.titel
        case .notitie: maaltijd.notitie ?? ""
        case .restjes:
            Weekplanning.restjesTitel(
                bronDag: alle.first { $0.id == maaltijd.restjesVan }?.dag, kalender: kalender)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        if let recept {
                            CategorieIcoon(recept: recept)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kop)
                                .font(.system(.title3, design: .serif).weight(.semibold))
                            if maaltijd.soort == .restjes {
                                Text(maaltijd.titel).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                }
                Section {
                    if recept != nil {
                        Button("Open recept", systemImage: "book") { actie(.open) }
                        if !(recept?.gesorteerdeStappen.isEmpty ?? true) {
                            Button("Kook dit", systemImage: "frying.pan") { actie(.kook) }
                        }
                    }
                    if maaltijd.soort == .recept {
                        if porties > 0 {
                            HStack {
                                SwiftUI.Label("Porties", systemImage: "person.2")
                                Spacer()
                                PortiesKnoppen(
                                    porties: porties,
                                    wijzig: { nieuw in
                                        porties = min(99, max(1, nieuw))
                                        actie(.porties(porties))
                                    }, kleur: Kookkleuren.accent, rond: true)
                            }
                        }
                        if !heeftRestjes {
                            Button("Kook dubbel", systemImage: "square.on.square") { actie(.kookDubbel) }
                        }
                    }
                    if maaltijd.soort == .recept, recept == nil {
                        Button("Kies opnieuw", systemImage: "arrow.triangle.2.circlepath") { actie(.kiesOpnieuw) }
                    }
                } footer: {
                    if maaltijd.soort == .recept, !heeftRestjes {
                        Text(
                            "Kook dubbel zet de volgende dag op restjes; op de boodschappenlijst tellen de porties dan dubbel."
                        )
                    }
                }
                Section("Verplaats naar…") {
                    DagKnoppen(
                        dagen: dagen, gekozen: maaltijd.dag, bezet: bezet, vandaag: vandaag, kalender: kalender
                    ) { dag in
                        if !kalender.isDate(dag, inSameDayAs: maaltijd.dag) { actie(.verplaats(dag)) }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                }
                Section {
                    Button("Wis deze dag", systemImage: "trash", role: .destructive) { actie(.wis) }
                } footer: {
                    if heeftRestjes {
                        Text("De restjes van dit recept gaan dan ook van het weekmenu.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(Weekplanning.langeDag(maaltijd.dag, kalender: kalender))
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(Kookkleuren.accent)
    }

    private var bezet: Set<Date> {
        Set(dagen.filter { Weekplanning.maaltijd(op: $0, in: alle, kalender: kalender) != nil })
    }
}

// MARK: - Plan in (vanuit het recept, schets B)

/// "📅 Plan in": een dag van deze of volgende week, de porties (standaard die van het recept); het
/// kookboek volgt het recept. Staat er al iets, dan eerst "vervangen?".
struct PlanInVel: View {
    @ObservedObject var recept: Recept
    private let nu: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @AppStorage(AppConfiguratie.sleutelWeekBegin) private var weekBeginWaarde = Weekbegin.maandag.rawValue
    @FetchRequest(sortDescriptors: Weekmenu.sortering) private var alleMaaltijden: FetchedResults<Maaltijd>

    @State private var volgendeWeek: Bool
    @State private var gekozen: Date?
    @State private var porties: Int
    @State private var vraagVervangen = false
    @State private var foutmelding: String?

    init(recept: Recept, nu: Date = .now, volgendeWeek: Bool = false, gekozen: Date? = nil) {
        self.recept = recept
        self.nu = nu
        _volgendeWeek = State(initialValue: volgendeWeek)
        _gekozen = State(initialValue: gekozen)
        _porties = State(initialValue: Int(recept.porties))
    }

    private var kalender: Calendar {
        Weekplanning.kalender(weekBegin: Weekbegin(rawValue: weekBeginWaarde) ?? .maandag)
    }
    private var vandaag: Date { kalender.startOfDay(for: nu) }
    private var kookboek: Kookboek { recept.kookboekWaarde }
    private var dagen: [Date] {
        Weekplanning.dagen(
            vanaf: Weekplanning.week(
                Weekplanning.weekStart(voor: nu, kalender: kalender), verschoven: volgendeWeek ? 1 : 0,
                kalender: kalender),
            kalender: kalender)
    }
    private var maaltijden: [GeplandeMaaltijd] {
        Weekmenu.waarden(alleMaaltijden.filter { !$0.isDeleted && $0.kookboekWaarde == kookboek })
    }
    private var dag: Date? {
        if let gekozen, dagen.contains(gekozen) { return gekozen }
        // Standaard de eerste vrije dag vanaf vandaag.
        let open = dagen.filter { $0 >= vandaag }
        return open.first { Weekplanning.maaltijd(op: $0, in: maaltijden, kalender: kalender) == nil } ?? open.first
    }
    private var bezetDoor: GeplandeMaaltijd? {
        dag.flatMap { Weekplanning.maaltijd(op: $0, in: maaltijden, kalender: kalender) }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Picker("Week", selection: $volgendeWeek) {
                    Text("Deze week").tag(false)
                    Text("Volgende week").tag(true)
                }
                .pickerStyle(.segmented)
                DagKnoppen(
                    dagen: dagen, gekozen: dag,
                    bezet: Set(
                        dagen.filter { Weekplanning.maaltijd(op: $0, in: maaltijden, kalender: kalender) != nil }),
                    vandaag: vandaag, kalender: kalender
                ) { gekozen = $0 }
                if let dag {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(samenvatting(dag))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let bezetDoor {
                            SwiftUI.Label(
                                "Daar staat al \(Weekplanning.korteTitel(bezetDoor))",
                                systemImage: "exclamationmark.circle"
                            )
                            .font(.subheadline)
                            .foregroundStyle(Kookkleuren.markering)
                        }
                    }
                }
                if recept.porties > 0 {
                    HStack {
                        Text("Personen")
                        Spacer()
                        PortiesKnoppen(
                            porties: porties, wijzig: { porties = min(99, max(1, $0)) }, kleur: Kookkleuren.accent,
                            rond: true)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    if bezetDoor != nil { vraagVervangen = true } else { bewaar() }
                } label: {
                    Text(knop)
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(
                            dag == nil
                                ? AnyShapeStyle(Color.secondary.opacity(0.35)) : AnyShapeStyle(Kookkleuren.accent),
                            in: Capsule()
                        )
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .disabled(dag == nil)
            }
            .padding(20)
            .navigationTitle("Plan \u{201E}\(recept.titelOfStandaard)\u{201D} in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sluit", systemImage: "xmark") { dismiss() }
                }
            }
            .confirmationDialog(
                bezetDoor.map { "\(Weekplanning.korteTitel($0)) vervangen?" } ?? "", isPresented: $vraagVervangen,
                titleVisibility: .visible
            ) {
                Button("Vervang", role: .destructive, action: bewaar)
                Button("Annuleer", role: .cancel) {}
            } message: {
                Text("Er is één avondeten per dag.")
            }
            .alert(
                "Er ging iets mis",
                isPresented: Binding(get: { foutmelding != nil }, set: { if !$0 { foutmelding = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(foutmelding ?? "")
            }
        }
        .tint(Kookkleuren.accent)
    }

    private var knop: String {
        guard let dag else { return "Kies een dag" }
        let naam = Weekplanning.dagnaam(dag, kalender: kalender)
        return bezetDoor == nil ? "Zet op \(naam)" : "Vervang op \(naam)"
    }

    private func samenvatting(_ dag: Date) -> String {
        [
            Weekplanning.langeDag(dag, kalender: kalender),
            recept.porties > 0 ? Weergave.porties(porties) : nil,
            kookboek == .thuis ? "Thuis" : "Mijn week",
        ].compactMap { $0 }.joined(separator: " · ")
    }

    private func bewaar() {
        guard let dag else { return }
        do {
            try Weekmenu.plan(
                recept, op: dag, porties: recept.porties > 0 ? porties : 0, context: context, kalender: kalender)
            dismiss()
        } catch {
            foutmelding = "Plannen lukte niet: \(error.localizedDescription)"
        }
    }
}

// MARK: - Vandaag (bovenaan de bibliotheek)

/// "Vandaag: Prei-quiche ›" bovenaan de bibliotheek als er iets gepland is (M6); anders niets. Tik =
/// het recept. Eerst je eigen week, dan Thuis.
struct VandaagRij: View {
    private let nu: Date
    @FetchRequest private var vandaag: FetchedResults<Maaltijd>
    @FetchRequest(sortDescriptors: Weekmenu.sortering) private var alle: FetchedResults<Maaltijd>
    @Environment(\.managedObjectContext) private var context

    init(nu: Date = .now) {
        self.nu = nu
        let kalender = Weekplanning.kalender()
        let begin = kalender.startOfDay(for: nu)
        let eind = Weekplanning.volgendeDag(begin, kalender: kalender)
        _vandaag = FetchRequest(
            sortDescriptors: Weekmenu.sortering,
            predicate: NSPredicate(format: "datum >= %@ AND datum < %@", begin as NSDate, eind as NSDate))
    }

    /// De maaltijd die de rij toont.
    private var keuze: GeplandeMaaltijd? {
        let kalender = Weekplanning.kalender()
        for kookboek in Kookboek.allCases {
            let waarden = Weekmenu.waarden(vandaag.filter { $0.kookboekWaarde == kookboek })
            if let maaltijd = Weekplanning.vandaag(waarden, nu: nu, kalender: kalender) { return maaltijd }
        }
        return nil
    }

    var body: some View {
        if let keuze {
            let recept = Weekmenu.recept(bij: keuze, alle: Weekmenu.waarden(Array(alle)), context: context)
            Button {
                if let recept { KookRouter.gedeeld.toon(recept: recept.sleutelURL) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .foregroundStyle(Kookkleuren.accent)
                    Text("Vandaag:")
                        .foregroundStyle(.secondary)
                    Text(Weekplanning.korteTitel(keuze))
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if recept != nil {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.subheadline)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Vandaag: \(Weekplanning.korteTitel(keuze))")
            .accessibilityHint(recept == nil ? "" : "Tik om het recept te openen")
        }
    }
}
