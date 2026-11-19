import CoreData
import SwiftUI

/// Het weekoverzicht (#41, schets A): zeven dagen onder elkaar met per dag één avondeten — een recept
/// met het aantal personen, restjes, een notitie of leeg. Tik een lege dag om een recept te kiezen, een
/// gevulde voor de acties; slepen ruilt dagen. Onderin de boodschappen voor de rest van de week (het
/// vel uit #40). Lege dagen zijn gewoon: geen rood, geen "je bent achter" (M2).
struct WeekScherm: View {
    var delen: ThuisDelen = .gedeeld
    /// Voor tests en voorbeelden: een vaste "nu".
    private let nu: Date

    @Environment(\.managedObjectContext) private var context
    @AppStorage(AppConfiguratie.sleutelWeekBegin) private var weekBeginWaarde = Weekbegin.maandag.rawValue
    @FetchRequest(sortDescriptors: Weekmenu.sortering) private var alleMaaltijden: FetchedResults<Maaltijd>
    @FetchRequest(sortDescriptors: []) private var recepten: FetchedResults<Recept>
    @FetchRequest(sortDescriptors: [], predicate: Boodschappenlijsten.predicaatOpen(kookboek: .thuis))
    private var thuisItems: FetchedResults<BoodschappenItem>

    @State private var kookboek: Kookboek
    /// Verschuiving ten opzichte van deze week.
    @State private var weekVerschil: Int
    @State private var kiesVoor: DagKeuze?
    @State private var actiesVoor: GeplandeMaaltijd?
    @State private var openRecept: NSManagedObjectID?
    @State private var vel: SelectieBalk.VelKeuze?
    @State private var boodschappenVanaf: Date?
    @State private var dubbelVraag: DubbelVraag?
    @State private var foutmelding: String?

    init(
        kookboek: Kookboek = .mijn, weekVerschil: Int = 0, nu: Date = .now, delen: ThuisDelen = .gedeeld,
        acties: GeplandeMaaltijd? = nil, kiesVoor: Date? = nil
    ) {
        self.nu = nu
        self.delen = delen
        _kookboek = State(initialValue: kookboek)
        _weekVerschil = State(initialValue: weekVerschil)
        _actiesVoor = State(initialValue: acties)
        _kiesVoor = State(initialValue: kiesVoor.map(DagKeuze.init))
    }

    struct DagKeuze: Identifiable {
        let dag: Date
        var id: Date { dag }
    }

    struct DubbelVraag: Identifiable {
        let bron: GeplandeMaaltijd
        let dag: Date
        let door: GeplandeMaaltijd
        var id: UUID { bron.id }
    }

    // MARK: - Afgeleid

    private var kalender: Calendar {
        Weekplanning.kalender(weekBegin: Weekbegin(rawValue: weekBeginWaarde) ?? .maandag)
    }
    private var vandaag: Date { kalender.startOfDay(for: nu) }
    private var start: Date {
        Weekplanning.week(
            Weekplanning.weekStart(voor: nu, kalender: kalender), verschoven: weekVerschil, kalender: kalender)
    }
    private var dagen: [Date] { Weekplanning.dagen(vanaf: start, kalender: kalender) }

    private var maaltijden: [GeplandeMaaltijd] {
        Weekmenu.waarden(alleMaaltijden.filter { !$0.isDeleted && $0.kookboekWaarde == kookboek })
    }

    private var receptPerUUID: [UUID: Recept] {
        Dictionary(
            recepten.compactMap { recept in recept.uuid.map { ($0, recept) } }, uniquingKeysWith: { a, _ in a })
    }

    private var toonSchakelaar: Bool {
        kookboek == .thuis
            || BoodschappenSchakelaar.toon(
                rol: delen.status.rol,
                thuisItems: thuisItems.count + alleMaaltijden.filter { $0.kookboekWaarde == .thuis }.count,
                thuisRecepten: recepten.filter(\.isThuis).count)
    }

    private var titel: String {
        switch weekVerschil {
        case 0: "Deze week"
        case 1: "Volgende week"
        case -1: "Vorige week"
        default: "Week van \(Weekplanning.korteDatum(start, kalender: kalender))"
        }
    }

    /// Vanaf welke dag de boodschappen: gekozen, anders vandaag (of het begin van een latere week).
    private var vanaf: Date? {
        let eerste = dagen.first { $0 >= vandaag }
        if let boodschappenVanaf, let eerste, boodschappenVanaf >= eerste, dagen.contains(boodschappenVanaf) {
            return boodschappenVanaf
        }
        return eerste
    }

    private var paren: [Weekplanning.Boodschappenpaar] {
        guard let vanaf, let laatste = dagen.last else { return [] }
        let paren = Weekplanning.boodschappen(maaltijden, vanaf: vanaf, tot: laatste, kalender: kalender)
        let bekend = receptPerUUID
        return paren.filter { bekend[$0.receptUUID] != nil }
    }

    // MARK: - Weergave

    var body: some View {
        let maaltijden = maaltijden
        let bekend = receptPerUUID
        List {
            if toonSchakelaar {
                Section {
                    Picker("Week", selection: $kookboek) {
                        Text("Mijn week").tag(Kookboek.mijn)
                        Text("Thuis").tag(Kookboek.thuis)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.large)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                } footer: {
                    if kookboek == .thuis {
                        Text("Wie Thuis met je deelt, ziet en wijzigt deze week ook.")
                    }
                }
            }
            Section {
                ForEach(dagen, id: \.self) { dag in
                    dagRij(
                        dag, maaltijd: Weekplanning.maaltijd(op: dag, in: maaltijden, kalender: kalender),
                        alle: maaltijden, bekend: bekend)
                }
            } header: {
                weekKop(gepland: Weekplanning.aantalGepland(maaltijden, dagen: dagen, kalender: kalender))
            } footer: {
                if Weekplanning.aantalGepland(maaltijden, dagen: dagen, kalender: kalender) == 0 {
                    Text("Zet een recept op een dag, of laat dagen gewoon open. Je kunt alles later verschuiven.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(titel)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) { boodschappenKnop }
        .sheet(item: $kiesVoor) { keuze in
            ReceptKiezer(
                dag: keuze.dag, kookboek: kookboek, kalender: kalender,
                kies: { recept in plan(recept, op: keuze.dag) },
                notitie: { tekst in planNotitie(tekst, op: keuze.dag) }
            )
            .presentationDetents([.large])
        }
        .sheet(item: $actiesVoor) { maaltijd in
            DagActies(
                maaltijd: maaltijd, alle: maaltijden,
                recept: Weekmenu.recept(bij: maaltijd, alle: maaltijden, context: context),
                dagen: dagen, vandaag: vandaag, kalender: kalender,
                actie: { voerUit($0, voor: maaltijd) }
            )
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $vel) { keuze in
            BoodschappenVel(
                recepten: keuze.recepten, bestemming: HerinneringenDienst.gedeeld, thuisBestaat: keuze.thuisBestaat)
        }
        .navigationDestination(item: $openRecept) { id in
            ReceptScherm(id: id, naVerwijderen: { openRecept = nil }, naVerplaatsen: { openRecept = $0 })
        }
        .confirmationDialog(
            dubbelVraag.map {
                "Op \(Weekplanning.dagnaam($0.dag, kalender: kalender)) staat al \(Weekplanning.korteTitel($0.door))"
            } ?? "",
            isPresented: Binding(get: { dubbelVraag != nil }, set: { if !$0 { dubbelVraag = nil } }),
            titleVisibility: .visible, presenting: dubbelVraag
        ) { vraag in
            Button("Vervang door restjes", role: .destructive) { kookDubbel(vraag.bron, op: vraag.dag, vervang: true) }
            ForEach(vrijeDagen(na: vraag.bron.dag, in: maaltijden), id: \.self) { dag in
                Button("Restjes op \(Weekplanning.dagnaam(dag, kalender: kalender))") {
                    kookDubbel(vraag.bron, op: dag)
                }
            }
            Button("Annuleer", role: .cancel) {}
        } message: { _ in
            Text("Kies of de restjes die dag vervangen, of zet ze op een andere dag.")
        }
        .alert(
            "Er ging iets mis", isPresented: Binding(get: { foutmelding != nil }, set: { if !$0 { foutmelding = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(foutmelding ?? "")
        }
        .task { await delen.vernieuw() }
        .tint(Kookkleuren.accent)
    }

    private func weekKop(gepland: Int) -> some View {
        HStack(spacing: 8) {
            Button {
                withAnimation { weekVerschil -= 1 }
            } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Vorige week")
            VStack(spacing: 2) {
                Text(Weekplanning.weekTitel(start, kalender: kalender))
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                Text(Weekplanning.teller(gepland: gepland))
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryLabel))
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            Button {
                withAnimation { weekVerschil += 1 }
            } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("Volgende week")
        }
        .textCase(nil)
        .font(.title3.weight(.semibold))
        .foregroundStyle(Kookkleuren.accent)
        .padding(.bottom, 4)
    }

    private func dagRij(_ dag: Date, maaltijd: GeplandeMaaltijd?, alle: [GeplandeMaaltijd], bekend: [UUID: Recept])
        -> some View
    {
        let inhoud = Weekplanning.inhoud(maaltijd, alle: alle) { bekend[$0] != nil }
        let isVandaag = kalender.isDate(dag, inSameDayAs: vandaag)
        return Button {
            if let maaltijd, !isVerwijderd(inhoud) {
                actiesVoor = maaltijd
            } else {
                kiesVoor = DagKeuze(dag: dag)
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(spacing: 0) {
                    Text(Weekplanning.afkorting(dag, kalender: kalender).uppercased())
                        .font(.caption.weight(.bold))
                    Text("\(kalender.component(.day, from: dag))")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }
                .foregroundStyle(isVandaag ? Kookkleuren.accent : .secondary)
                .frame(width: 40)
                inhoudWeergave(inhoud, maaltijd: maaltijd, alle: alle, bekend: bekend)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(toegankelijk(dag, inhoud, isVandaag: isVandaag))
        .accessibilityHint(maaltijd == nil ? "Tik om een recept te kiezen" : "Tik voor acties")
        .modifier(SleepDag(maaltijd: maaltijd) { id in verplaats(id, naar: dag) })
        .listRowBackground(isVandaag ? Kookkleuren.accent.opacity(0.12) : nil)
    }

    private func isVerwijderd(_ inhoud: Daginhoud) -> Bool {
        if case .recept(_, _, true) = inhoud { return true }
        return false
    }

    @ViewBuilder
    private func inhoudWeergave(
        _ inhoud: Daginhoud, maaltijd: GeplandeMaaltijd?, alle: [GeplandeMaaltijd], bekend: [UUID: Recept]
    ) -> some View {
        switch inhoud {
        case .leeg:
            HStack(spacing: 8) {
                Image(systemName: "plus")
                Text("Kies een recept")
            }
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 12)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
            }
        case .recept(let titel, let porties, let verwijderd):
            let recept = maaltijd?.receptUUID.flatMap { bekend[$0] }
            let heeftRestjes = alle.contains { $0.restjesVan == maaltijd?.id }
            HStack(spacing: 12) {
                if let recept {
                    CategorieIcoon(recept: recept)
                } else {
                    leegIcoon("questionmark")
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(titel.isEmpty ? "Naamloos recept" : titel)
                        .font(.system(.body, design: .serif).weight(.semibold))
                        .strikethrough(verwijderd)
                        .foregroundStyle(verwijderd ? .secondary : .primary)
                        .lineLimit(2)
                    if verwijderd {
                        Text("Niet meer in Knipsel · kies opnieuw")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Kookkleuren.markering)
                    } else if let regel = onderregel(recept, kookDubbel: heeftRestjes) {
                        Text(regel)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if porties > 0, !verwijderd {
                    Text("\(porties) p")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        case .notitie(let tekst):
            HStack(spacing: 12) {
                leegIcoon("text.bubble")
                Text(tekst)
                    .font(.body.italic())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .restjes(let titel, let bronDag):
            HStack(spacing: 12) {
                leegIcoon("arrow.uturn.backward")
                VStack(alignment: .leading, spacing: 2) {
                    Text(Weekplanning.restjesTitel(bronDag: bronDag, kalender: kalender))
                        .font(.body.weight(.semibold))
                    Text(titel)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func leegIcoon(_ symbool: String) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.secondary.opacity(0.12))
            .frame(width: 44, height: 44)
            .overlay {
                Image(systemName: symbool)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
    }

    private func onderregel(_ recept: Recept?, kookDubbel: Bool) -> String? {
        let tijd = recept.flatMap {
            Weekweergave.tijd(totaal: Int($0.totaleTijdMinuten), bereiding: Int($0.bereidingstijdMinuten))
        }
        let delen = [tijd, kookDubbel ? "kook dubbel" : nil].compactMap { $0 }
        return delen.isEmpty ? nil : delen.joined(separator: " · ")
    }

    private func toegankelijk(_ dag: Date, _ inhoud: Daginhoud, isVandaag: Bool) -> String {
        let naam = Weekplanning.langeDag(dag, kalender: kalender) + (isVandaag ? ", vandaag" : "")
        switch inhoud {
        case .leeg: return "\(naam): nog niets"
        case .recept(let titel, let porties, let verwijderd):
            return "\(naam): \(titel)" + (verwijderd ? ", niet meer in Knipsel" : "")
                + (Weergave.porties(porties).map { ", \($0)" } ?? "")
        case .notitie(let tekst): return "\(naam): \(tekst)"
        case .restjes(let titel, let bronDag):
            return "\(naam): \(Weekplanning.restjesTitel(bronDag: bronDag, kalender: kalender)), \(titel)"
        }
    }

    @ViewBuilder private var boodschappenKnop: some View {
        let paren = paren
        if let vanaf, let laatste = dagen.last, !paren.isEmpty {
            Menu {
                Section("Boodschappen vanaf") {
                    ForEach(dagen.filter { $0 >= vandaag }, id: \.self) { dag in
                        Button(Weekplanning.langeDag(dag, kalender: kalender)) { boodschappenVanaf = dag }
                    }
                }
            } label: {
                SwiftUI.Label(
                    Weekplanning.boodschappenKnop(vanaf: vanaf, tot: laatste, kalender: kalender),
                    systemImage: "cart.fill"
                )
                .font(.headline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Kookkleuren.accent, in: Capsule())
                .foregroundStyle(.white)
                .contentShape(Capsule())
            } primaryAction: {
                openBoodschappen(paren)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Houd ingedrukt om de begindag te kiezen")
            .frame(maxWidth: 560)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }

    // MARK: - Acties

    private func vrijeDagen(na dag: Date, in maaltijden: [GeplandeMaaltijd]) -> [Date] {
        dagen.filter { $0 > dag && Weekplanning.maaltijd(op: $0, in: maaltijden, kalender: kalender) == nil }
    }

    private func doe(_ werk: () throws -> Void) {
        do {
            try withAnimation { try werk() }
        } catch {
            foutmelding = Foutmelding.tekst(error)
        }
    }

    private func plan(_ recept: Recept, op dag: Date) {
        doe { try Weekmenu.plan(recept, op: dag, kookboek: kookboek, context: context, kalender: kalender) }
    }

    private func planNotitie(_ tekst: String, op dag: Date) {
        doe { try Weekmenu.planNotitie(tekst, op: dag, kookboek: kookboek, context: context, kalender: kalender) }
    }

    private func verplaats(_ id: UUID, naar dag: Date) {
        doe { try Weekmenu.verplaats(id, naar: dag, kookboek: kookboek, context: context, kalender: kalender) }
    }

    private func kookDubbel(_ bron: GeplandeMaaltijd, op dag: Date? = nil, vervang: Bool = false) {
        doe {
            let uitkomst = try Weekmenu.kookDubbel(
                bron.id, op: dag, vervang: vervang, kookboek: kookboek, context: context, kalender: kalender)
            if case .bezet(let dag, let door) = uitkomst {
                dubbelVraag = DubbelVraag(bron: bron, dag: dag, door: door)
            }
        }
    }

    private func voerUit(_ actie: DagActies.Actie, voor maaltijd: GeplandeMaaltijd) {
        // Porties wijzig je in het vel zelf; de rest sluit het.
        if case .porties = actie {} else { actiesVoor = nil }
        let recept = Weekmenu.recept(bij: maaltijd, alle: maaltijden, context: context)
        switch actie {
        case .open:
            openRecept = recept?.objectID
        case .kook:
            if let recept {
                let porties = maaltijd.porties > 0 ? maaltijd.porties : nil
                // Na het sluiten van het vel: een fullScreenCover tijdens die animatie valt weg.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    KookRouter.gedeeld.kook(recept: recept.sleutelURL, porties: porties)
                }
            }
        case .porties(let aantal):
            doe { try Weekmenu.zetPorties(aantal, voor: maaltijd.id, kookboek: kookboek, context: context) }
        case .kookDubbel:
            // Na het sluiten van het vel, anders botst de vraag met de animatie.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                kookDubbel(maaltijd)
            }
        case .verplaats(let dag):
            verplaats(maaltijd.id, naar: dag)
        case .kiesOpnieuw:
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                kiesVoor = DagKeuze(dag: maaltijd.dag)
            }
        case .wis:
            doe { try Weekmenu.wis(maaltijd.id, kookboek: kookboek, context: context) }
        }
    }

    private func openBoodschappen(_ paren: [Weekplanning.Boodschappenpaar]) {
        let bekend = receptPerUUID
        let velRecepten = paren.compactMap { paar in
            bekend[paar.receptUUID].map { VelRecept($0, porties: paar.porties) }
        }
        guard !velRecepten.isEmpty else { return }
        vel = SelectieBalk.VelKeuze(recepten: velRecepten, thuisBestaat: toonSchakelaar)
    }
}

/// Slepen tussen dagen: een gevulde dag is sleepbaar (zijn uuid als tekst), elke dag een doel.
private struct SleepDag: ViewModifier {
    let maaltijd: GeplandeMaaltijd?
    let neerzetten: (UUID) -> Void

    func body(content: Content) -> some View {
        let doel = content.dropDestination(for: String.self) { items, _ in
            guard let id = items.first.flatMap(UUID.init(uuidString:)), id != maaltijd?.id else { return false }
            neerzetten(id)
            return true
        }
        if let maaltijd {
            doel.draggable(maaltijd.id.uuidString)
        } else {
            doel
        }
    }
}

/// Kleine weergaveregels voor het weekmenu.
enum Weekweergave {
    /// De totale tijd als die er is, anders de bereidingstijd.
    static func tijd(totaal: Int, bereiding: Int) -> String? {
        Weergave.tijd(minuten: totaal > 0 ? totaal : bereiding)
    }
}

/// 📅 in de bibliotheek: naar het weekmenu.
struct WeekKnop: View {
    var actie: () -> Void

    var body: some View {
        Button("Weekmenu", systemImage: "calendar", action: actie)
    }
}
