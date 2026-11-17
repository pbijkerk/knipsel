import CoreData
import SwiftUI

/// Het vel "Boodschappen" (schets 1A): alle ingrediënten geschaald en aangevinkt, behalve wat je meestal
/// in huis hebt. De hoofdknop zet ze op de eigen lijst in Knipsel (#39) van het kookboek van het recept,
/// of — als dat in Instellingen zo staat — in Herinneringen; de andere bestemming en "Delen als tekst"
/// staan eronder.
///
/// Voor meerdere recepten uit de bibliotheek (#40, schets 3A) staat bovenaan per recept een rij met
/// porties, is alles opgeteld en staat onder elke regel uit welke recepten hij komt.
struct BoodschappenVel: View {
    /// De recepten op het vel; bij één recept uit de receptweergave precies één.
    let recepten: [VelRecept]
    let bestemming: any Boodschappenbestemming
    /// Met Thuis (gedeeld of met inhoud) mag je bij meerdere recepten kiezen op welke lijst ze gaan.
    let thuisBestaat: Bool
    private let defaults: UserDefaults
    private let standaard: BoodschappenStandaard
    /// Eén recept uit de receptweergave: porties en factor zijn daar al gekozen.
    private let enkel: (porties: Int, factor: Double)?
    /// Na het versturen naar een lijst (de bibliotheek zet dan de selectie uit).
    private let naSucces: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @Environment(\.openURL) private var openURL

    @State private var meestal: MeestalInHuis
    @State private var aangevinkt: Set<String>
    @State private var dubbele: [String: DubbelItem] = [:]
    @State private var keuzes: [String: DubbelKeuze] = [:]
    @State private var fase: Fase
    @State private var toegang: HerinneringenToegang
    @State private var foutmelding: String?
    /// De lijst is verstuurd of gedeeld: dan telt wat uitgevinkt stond mee voor "leren".
    @State private var geteld = false
    /// Per regel-id wat er al op de eigen lijst staat en wat het samen wordt ("2 uien" → "5 uien").
    @State private var opLijst: [String: (bestaand: String, samen: String?)] = [:]
    /// Gekozen personen per recept (alleen bij meerdere recepten).
    @State private var porties: [String: Int]
    /// Op welke lijst in Knipsel het komt: het kookboek van het recept, of bij meerdere de meeste.
    @State private var kookboek: Kookboek

    enum Fase: Equatable {
        case kiezen
        case bezig
        case klaar(Boodschappenresultaat)
        case klaarLijst(Boodschappenresultaat, Kookboek)
    }

    init(
        recept: String, porties: Int, invoer: [BoodschappenInvoer], factor: Double,
        bestemming: any Boodschappenbestemming, kookboek: Kookboek = .mijn, defaults: UserDefaults = .standard,
        fase: Fase = .kiezen
    ) {
        self.init(
            recepten: [VelRecept(id: recept, titel: recept, invoer: invoer, standaard: 0, kookboek: kookboek)],
            enkel: (porties, factor), bestemming: bestemming, thuisBestaat: false, defaults: defaults, fase: fase,
            naSucces: {})
    }

    /// Meerdere recepten uit de bibliotheek (#40): elk begint op zijn eigen standaardporties.
    init(
        recepten: [VelRecept], bestemming: any Boodschappenbestemming, thuisBestaat: Bool,
        defaults: UserDefaults = .standard, fase: Fase = .kiezen, naSucces: @escaping () -> Void = {}
    ) {
        self.init(
            recepten: recepten, enkel: nil, bestemming: bestemming, thuisBestaat: thuisBestaat, defaults: defaults,
            fase: fase, naSucces: naSucces)
    }

    private init(
        recepten: [VelRecept], enkel: (porties: Int, factor: Double)?, bestemming: any Boodschappenbestemming,
        thuisBestaat: Bool, defaults: UserDefaults, fase: Fase, naSucces: @escaping () -> Void
    ) {
        self.recepten = recepten
        self.enkel = enkel
        self.bestemming = bestemming
        self.thuisBestaat = thuisBestaat
        self.defaults = defaults
        self.naSucces = naSucces
        standaard = .laad(uit: defaults)
        _kookboek = State(initialValue: VelBestemming.kookboek(voor: recepten.map(\.kookboek)))
        let porties = Dictionary(
            recepten.map { ($0.id, $0.start.flatMap { $0 > 0 ? $0 : nil } ?? $0.standaard) },
            uniquingKeysWith: { a, _ in a })
        _porties = State(initialValue: porties)
        let meestal = MeestalInHuis.laad(uit: defaults)
        _meestal = State(initialValue: meestal)
        let regels = BoodschappenLijst.regels(
            recepten: Self.delen(recepten, enkel: enkel, porties: porties), meestalInHuis: meestal)
        _aangevinkt = State(initialValue: Set(regels.filter { !$0.meestalInHuis }.map(\.id)))
        _fase = State(initialValue: fase)
        _toegang = State(initialValue: bestemming.toegang)
    }

    private var meerdere: Bool { enkel == nil }

    private var hoofd: VelBestemming { VelBestemming.hoofd(standaard: standaard, kookboek: kookboek) }

    private static func delen(
        _ recepten: [VelRecept], enkel: (porties: Int, factor: Double)?, porties: [String: Int]
    ) -> [ReceptBoodschappen] {
        recepten.map { recept in
            if let enkel {
                return ReceptBoodschappen(titel: recept.titel, invoer: recept.invoer, factor: enkel.factor)
            }
            return ReceptBoodschappen(
                titel: recept.titel, invoer: recept.invoer, standaard: recept.standaard,
                porties: porties[recept.id] ?? recept.standaard)
        }
    }

    private var regels: [BoodschappenRegel] {
        BoodschappenLijst.regels(
            recepten: Self.delen(recepten, enkel: enkel, porties: porties), meestalInHuis: meestal)
    }

    /// Per recept de titel en het aantal personen, voor de tekst en de notitie.
    private var titelsEnPorties: [(titel: String, porties: Int)] {
        recepten.map { recept in
            (recept.titel, enkel?.porties ?? (recept.standaard > 0 ? porties[recept.id] ?? recept.standaard : 0))
        }
    }

    /// Wat er in de herkomst op de lijst komt: het recept, of bij meerdere de recepten van de regel.
    private func herkomst(_ regel: BoodschappenRegel) -> String? {
        guard meerdere else { return recepten.first?.titel }
        return regel.herkomst.isEmpty ? nil : regel.herkomst.joined(separator: ", ")
    }

    private var gekozen: [BoodschappenRegel] { regels.filter { aangevinkt.contains($0.id) } }

    /// Wat er echt bij komt: aangevinkt, min wat al op de lijst staat en overgeslagen wordt.
    private var aantal: Int {
        gekozen.filter { regel in
            guard dubbele[regel.id] != nil else { return true }
            return (keuzes[regel.id] ?? .overslaan) != .overslaan
        }.count
    }

    private var titel: String {
        guard let enkel else { return VelRecept.titel(aantal: recepten.count) }
        return Weergave.porties(enkel.porties).map { "Boodschappen · \($0)" } ?? "Boodschappen"
    }

    var body: some View {
        NavigationStack {
            Group {
                if case .klaar(let resultaat) = fase {
                    bevestiging(resultaat)
                } else if case .klaarLijst(let resultaat, let boek) = fase {
                    bevestigingLijst(resultaat, kookboek: boek)
                } else {
                    lijst
                }
            }
            .navigationTitle(titel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sluit", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .tint(Kookkleuren.accent)
        .task {
            laadOpLijst()
            await laadDubbele()
        }
        .onChange(of: porties) {
            laadOpLijst()
            Task { await laadDubbele() }
        }
        .onChange(of: kookboek) { laadOpLijst() }
        .onDisappear(perform: leer)
        .alert(
            "Er ging iets mis", isPresented: Binding(get: { foutmelding != nil }, set: { if !$0 { foutmelding = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(foutmelding ?? "")
        }
    }

    // MARK: - De lijst

    private var lijst: some View {
        let alle = regels
        let nodig = alle.filter { !$0.meestalInHuis }
        let inHuis = alle.filter(\.meestalInHuis)
        return List {
            if meerdere { receptRijen }
            Section {
                if toegang == .geweigerd { geenToegang }
                ForEach(nodig) { rij($0) }
            } header: {
                Text("Vink uit wat je al in huis hebt.")
                    .font(.subheadline)
                    .foregroundStyle(Color(.secondaryLabel))
                    .textCase(nil)
            } footer: {
                if let suggestie = meestal.suggestie(in: nodig) {
                    leerVoorstel(suggestie)
                }
            }
            if !inHuis.isEmpty {
                Section("Meestal in huis") {
                    ForEach(inHuis) { rij($0) }
                }
            }
            if alle.isEmpty {
                Text(meerdere ? "Deze recepten hebben geen ingrediënten." : "Dit recept heeft geen ingrediënten.")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) { knoppen }
    }

    /// Bovenaan bij meerdere recepten: "Zet op: Mijn lijst | Thuis" en per recept de porties.
    @ViewBuilder private var receptRijen: some View {
        if VelBestemming.toonKookboekKeuze(meerdere: meerdere, thuisBestaat: thuisBestaat) {
            Section {
                HStack(spacing: 12) {
                    Text("Zet op:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("Zet op", selection: $kookboek) {
                        Text("Mijn lijst").tag(Kookboek.mijn)
                        Text("Thuis").tag(Kookboek.thuis)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                .accessibilityElement(children: .contain)
            }
        }
        Section {
            ForEach(recepten) { recept in
                HStack(spacing: 10) {
                    Text(recept.titel)
                        .font(.system(.body, design: .serif).weight(.semibold))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if recept.standaard > 0 {
                        PortiesKnoppen(
                            porties: porties[recept.id] ?? recept.standaard,
                            wijzig: { porties[recept.id] = min(99, max(1, $0)) }, kleur: Kookkleuren.accent,
                            rond: true
                        )
                        .accessibilityLabel("Porties \(recept.titel)")
                    } else {
                        Text("Porties onbekend")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text(recepten.count == 1 ? "1 recept" : "\(recepten.count) recepten")
        }
    }

    private func rij(_ regel: BoodschappenRegel) -> some View {
        let aan = aangevinkt.contains(regel.id)
        let uit = meerdere && !regel.herkomst.isEmpty ? regel.herkomst.joined(separator: ", ") : nil
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                if aan { aangevinkt.remove(regel.id) } else { aangevinkt.insert(regel.id) }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: aan ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(aan ? Kookkleuren.accent : Color.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(regel.tekst)
                            .foregroundStyle(aan ? .primary : .secondary)
                        if let uit {
                            Text(uit)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(uit.map { "\(regel.tekst), uit \($0)" } ?? regel.tekst)
            .accessibilityValue(aan ? "aangevinkt" : "niet aangevinkt")
            .accessibilityHint(aan ? "Tik als je het al in huis hebt" : "Tik om het op de lijst te zetten")
            if aan, let dubbel = dubbele[regel.id] {
                dubbelKeuze(regel, dubbel)
            } else if aan, hoofd != .herinneringen, let bekend = opLijst[regel.id] {
                opLijstRegel(bekend)
            }
        }
    }

    /// "Staat al op je lijst: 2 uien" met overslaan (standaard) of erbij tellen.
    private func dubbelKeuze(_ regel: BoodschappenRegel, _ dubbel: DubbelItem) -> some View {
        let keuze = keuzes[regel.id] ?? .overslaan
        let tweede: (DubbelKeuze, String) =
            dubbel.opgeteld.map { (.bijtellen, "Tel erbij op: \($0)") } ?? (.losToevoegen, "Toch los toevoegen")
        return HStack(spacing: 6) {
            Image(systemName: "checklist")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Staat al op je lijst: \(dubbel.bestaand.titel)")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Picker("Wat wil je?", selection: Binding(get: { keuze }, set: { keuzes[regel.id] = $0 })) {
                    Text("Overslaan").tag(DubbelKeuze.overslaan)
                    Text(tweede.1).tag(tweede.0)
                }
            } label: {
                HStack(spacing: 3) {
                    Text(keuze == .overslaan ? "Overslaan" : (keuze == .bijtellen ? "Erbij tellen" : "Los erbij"))
                    Image(systemName: "chevron.up.chevron.down").imageScale(.small)
                }
                .fontWeight(.semibold)
            }
            .accessibilityLabel("Wat te doen met \(regel.naam)")
            .accessibilityValue(keuze == .overslaan ? "Overslaan" : tweede.1)
        }
        .font(.footnote)
        .padding(.leading, 34)
    }

    /// "Staat al op je lijst: 2 uien · wordt 5 uien" (eigen lijst: optellen gaat vanzelf).
    private func opLijstRegel(_ bekend: (bestaand: String, samen: String?)) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checklist")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(
                bekend.samen.map { "Staat al op je lijst: \(bekend.bestaand) · wordt \($0)" }
                    ?? "Staat al op je lijst: \(bekend.bestaand)"
            )
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.footnote)
        .padding(.leading, 34)
    }

    /// "Peper staat meestal uit. Altijd uit?" — klein, onder de lijst, geen pop-up.
    private func leerVoorstel(_ regel: BoodschappenRegel) -> some View {
        let naam = regel.woord.prefix(1).uppercased() + regel.woord.dropFirst()
        return HStack(spacing: 8) {
            Text("\(naam) staat meestal uit. Altijd uit?")
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Ja") {
                meestal.neemOver(regel)
                meestal.bewaar(in: defaults)
                aangevinkt.remove(regel.id)
            }
            .fontWeight(.semibold)
            Button("Nee") {
                meestal.wijsAf(regel)
                meestal.bewaar(in: defaults)
            }
        }
        .font(.footnote)
        .buttonStyle(.borderless)
        .padding(.top, 4)
    }

    private var geenToegang: some View {
        VStack(alignment: .leading, spacing: 8) {
            SwiftUI.Label("Geen toegang tot Herinneringen", systemImage: "exclamationmark.triangle")
                .font(.headline)
            Text(
                "Knipsel mag je boodschappen niet in Herinneringen zetten. Zet het aan in Instellingen › Apps › Knipsel › Herinneringen (Volledige toegang), of deel de lijst als tekst."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Button("Open Instellingen") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    private var knoppen: some View {
        VStack(spacing: 10) {
            switch hoofd {
            case .lijst(let boek):
                hoofdknop(hoofd.knop(aantal: gekozen.count), hint: "Zet ze op je boodschappenlijst in Knipsel") {
                    zetOpKnipselLijst(boek)
                }
                .disabled(gekozen.isEmpty || fase == .bezig)
                HStack(spacing: 10) {
                    if toegang != .geweigerd {
                        Button(action: zetOpLijst) {
                            SwiftUI.Label("Naar Herinneringen", systemImage: "checklist")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .disabled(gekozen.isEmpty || fase == .bezig)
                    }
                    deelKnop
                }
            case .herinneringen:
                if toegang != .geweigerd {
                    hoofdknop(hoofd.knop(aantal: aantal), hint: "Zet ze in Herinneringen, in de lijst Boodschappen") {
                        zetOpLijst()
                    }
                    .disabled(aantal == 0 || fase == .bezig)
                }
                HStack(spacing: 10) {
                    Button {
                        zetOpKnipselLijst(kookboek)
                    } label: {
                        SwiftUI.Label(kookboek == .thuis ? "Op de Thuis-lijst" : "Op mijn lijst", systemImage: "cart")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(gekozen.isEmpty || fase == .bezig)
                    deelKnop
                }
            }
        }
        .frame(maxWidth: 520)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func hoofdknop(_ titel: String, hint: String, actie: @escaping () -> Void) -> some View {
        Button(action: actie) {
            HStack(spacing: 8) {
                if fase == .bezig { ProgressView().tint(.white) }
                Text(titel)
            }
            .font(.headline.weight(.bold))
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Kookkleuren.accent, in: Capsule())
            .foregroundStyle(.white)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint(hint)
    }

    private var deelKnop: some View {
        ShareLink(item: BoodschappenLijst.tekst(recepten: titelsEnPorties, regels: gekozen)) {
            SwiftUI.Label("Delen als tekst", systemImage: "square.and.arrow.up")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .disabled(gekozen.isEmpty)
        .simultaneousGesture(TapGesture().onEnded { geteld = true })
    }

    // MARK: - Bevestiging

    private func bevestiging(_ resultaat: Boodschappenresultaat) -> some View {
        VStack(spacing: 18) {
            Spacer(minLength: 12)
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Kookkleuren.accent)
                .accessibilityHidden(true)
            Text("\(resultaat.aantal == 1 ? "1 item" : "\(resultaat.aantal) items") in Herinneringen › Boodschappen")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            if resultaat.overgeslagen > 0 {
                Text(
                    resultaat.overgeslagen == 1
                        ? "1 stond al op je lijst en is overgeslagen."
                        : "\(resultaat.overgeslagen) stonden al op je lijst en zijn overgeslagen."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
            if resultaat.lijstAangemaakt {
                Text(
                    "Knipsel heeft de lijst Boodschappen aangemaakt. Wil je hem per afdeling ingedeeld? Open de lijst in Herinneringen, kies Toon lijstinfo › Lijsttype › Boodschappen."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
            Button {
                openURL(AppConfiguratie.herinneringenURL)
            } label: {
                SwiftUI.Label("Open Herinneringen", systemImage: "checklist")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.bordered)
            Button("Klaar") { dismiss() }
                .font(.headline)
                .frame(minHeight: 44)
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
    }

    private func bevestigingLijst(_ resultaat: Boodschappenresultaat, kookboek boek: Kookboek) -> some View {
        VStack(spacing: 18) {
            Spacer(minLength: 12)
            Image(systemName: "cart.fill.badge.plus")
                .font(.system(size: 52))
                .foregroundStyle(Kookkleuren.accent)
                .accessibilityHidden(true)
            Text(VelBestemming.lijst(boek).bevestiging(aantal: resultaat.aantal))
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            if resultaat.bijgewerkt > 0 {
                Text(
                    resultaat.bijgewerkt == 1
                        ? "1 ervan is opgeteld bij wat er al op stond."
                        : "\(resultaat.bijgewerkt) ervan zijn opgeteld bij wat er al op stond."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
            Text(
                boek == .thuis
                    ? "Je vindt de lijst onder 🛒 in de bibliotheek. Wie Thuis met je deelt, ziet hem ook."
                    : "Je vindt de lijst onder 🛒 in de bibliotheek, per afdeling in de volgorde van de winkel."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            Button("Klaar") { dismiss() }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
                .buttonStyle(.bordered)
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Acties

    /// Wat er al open op de eigen lijst staat, per regel van het vel.
    private func laadOpLijst() {
        guard case .lijst(let boek) = hoofd else { return }
        let open = Boodschappenlijsten.items(in: boek, context: context).filter { !$0.afgevinkt }
        var gevonden: [String: (bestaand: String, samen: String?)] = [:]
        for regel in regels {
            guard let item = open.first(where: { $0.sleutel == regel.sleutel }) else { continue }
            let samen = BoodschappenLijst.samengevoegd(Boodschappenlijsten.lijstRegel(item), LijstRegel(regel))
            gevonden[regel.id] = (item.tekstOfNaam, samen.flatMap { $0.tekst == item.tekstOfNaam ? nil : $0.tekst })
        }
        opLijst = gevonden
    }

    private func zetOpKnipselLijst(_ boek: Kookboek) {
        do {
            let resultaat = try Boodschappenlijsten.zetOpLijst(
                gekozen.map { (LijstRegel($0), herkomst($0)) }, kookboek: boek, context: context)
            geteld = true
            fase = .klaarLijst(resultaat, boek)
            naSucces()
            Task { await OnbekendeAfdelingen.gedeeld.deelIn(context: context) }
        } catch {
            foutmelding = "Op de lijst zetten lukte niet: \(error.localizedDescription)"
        }
    }

    private func laadDubbele() async {
        guard toegang == .toegestaan, hoofd == .herinneringen else { return }
        dubbele = await bestemming.dubbele(in: regels)
    }

    private func zetOpLijst() {
        Task {
            if toegang == .nietGevraagd {
                toegang = await bestemming.vraagToegang()
                guard toegang == .toegestaan else { return }
                // Eerst laten zien wat er al op de lijst staat; de gebruiker tikt daarna opnieuw.
                let gevonden = await bestemming.dubbele(in: regels)
                if !gevonden.keys.filter(aangevinkt.contains).isEmpty {
                    dubbele = gevonden
                    return
                }
            }
            guard toegang == .toegestaan else { return }
            fase = .bezig
            do {
                let resultaat = try await bestemming.zetOpLijst(
                    gekozen, keuzes: keuzes, notitie: HerinneringenDienst.notitie(recepten: recepten.map(\.titel)))
                geteld = true
                fase = .klaar(resultaat)
                naSucces()
            } catch {
                fase = .kiezen
                foutmelding = "Op de lijst zetten lukte niet: \(error.localizedDescription)"
            }
        }
    }

    /// Wat uitgevinkt stond telt mee (L2: Knipsel onthoudt wat je vaak uitvinkt).
    private func leer() {
        guard geteld else { return }
        meestal.registreerUitgevinkt(regels.filter { !aangevinkt.contains($0.id) })
        meestal.bewaar(in: defaults)
    }
}

/// Eén recept op het vel: titel, ingrediënten, standaardporties (0 = onbekend) en kookboek.
struct VelRecept: Identifiable, Equatable {
    let id: String
    let titel: String
    let invoer: [BoodschappenInvoer]
    let standaard: Int
    let kookboek: Kookboek
    /// Met hoeveel personen het vel begint; `nil` = de standaardporties (vanuit het weekmenu, #41:
    /// de geplande porties, met restjes dubbel).
    let start: Int?

    init(
        id: String, titel: String, invoer: [BoodschappenInvoer], standaard: Int, kookboek: Kookboek = .mijn,
        start: Int? = nil
    ) {
        self.id = id
        self.titel = titel
        self.invoer = invoer
        self.standaard = standaard
        self.kookboek = kookboek
        self.start = start
    }

    init(_ recept: Recept) {
        self.init(
            id: recept.objectID.uriRepresentation().absoluteString, titel: recept.titelOfStandaard,
            invoer: recept.gesorteerdeIngredienten.map { BoodschappenInvoer($0) }, standaard: Int(recept.porties),
            kookboek: recept.kookboekWaarde)
    }

    /// Vanuit het weekmenu (#41): met de geplande porties.
    init(_ recept: Recept, porties: Int?) {
        self.init(
            id: recept.objectID.uriRepresentation().absoluteString, titel: recept.titelOfStandaard,
            invoer: recept.gesorteerdeIngredienten.map { BoodschappenInvoer($0) }, standaard: Int(recept.porties),
            kookboek: recept.kookboekWaarde, start: porties)
    }

    /// Titel van het vel: "Boodschappen · 3 recepten".
    static func titel(aantal: Int) -> String {
        aantal == 1 ? "Boodschappen · 1 recept" : "Boodschappen · \(aantal) recepten"
    }
}
