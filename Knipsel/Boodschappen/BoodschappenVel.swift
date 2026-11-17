import SwiftUI

/// Het vel "Boodschappen" (schets 1A): alle ingrediënten geschaald en aangevinkt, behalve wat je meestal
/// in huis hebt. De hoofdknop zet ze op de eigen lijst in Knipsel (#39) van het kookboek van het recept,
/// of — als dat in Instellingen zo staat — in Herinneringen; de andere bestemming en "Delen als tekst"
/// staan eronder.
struct BoodschappenVel: View {
    let recept: String
    let porties: Int
    let invoer: [BoodschappenInvoer]
    let factor: Double
    let bestemming: any Boodschappenbestemming
    /// Kookboek van het recept: een Thuis-recept gaat op de Thuis-lijst.
    let kookboek: Kookboek
    private let defaults: UserDefaults
    private let hoofd: VelBestemming

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
        self.recept = recept
        self.porties = porties
        self.invoer = invoer
        self.factor = factor
        self.bestemming = bestemming
        self.kookboek = kookboek
        self.defaults = defaults
        hoofd = VelBestemming.hoofd(standaard: .laad(uit: defaults), kookboek: kookboek)
        let meestal = MeestalInHuis.laad(uit: defaults)
        _meestal = State(initialValue: meestal)
        let regels = BoodschappenLijst.regels(invoer, factor: factor, meestalInHuis: meestal)
        _aangevinkt = State(initialValue: Set(regels.filter { !$0.meestalInHuis }.map(\.id)))
        _fase = State(initialValue: fase)
        _toegang = State(initialValue: bestemming.toegang)
    }

    private var regels: [BoodschappenRegel] {
        BoodschappenLijst.regels(invoer, factor: factor, meestalInHuis: meestal)
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
        Weergave.porties(porties).map { "Boodschappen · \($0)" } ?? "Boodschappen"
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
                Text("Dit recept heeft geen ingrediënten.").foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .safeAreaInset(edge: .bottom) { knoppen }
    }

    private func rij(_ regel: BoodschappenRegel) -> some View {
        let aan = aangevinkt.contains(regel.id)
        return VStack(alignment: .leading, spacing: 6) {
            Button {
                if aan { aangevinkt.remove(regel.id) } else { aangevinkt.insert(regel.id) }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: aan ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(aan ? Kookkleuren.accent : Color.secondary)
                        .accessibilityHidden(true)
                    Text(regel.tekst)
                        .foregroundStyle(aan ? .primary : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(regel.tekst)
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
        ShareLink(item: BoodschappenLijst.tekst(recept: recept, porties: porties, regels: gekozen)) {
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
                gekozen.map(LijstRegel.init), herkomst: recept, kookboek: boek, context: context)
            geteld = true
            fase = .klaarLijst(resultaat, boek)
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
                    gekozen, keuzes: keuzes, notitie: HerinneringenDienst.notitie(recept: recept))
                geteld = true
                fase = .klaar(resultaat)
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
