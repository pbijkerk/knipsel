import CoreData
import SwiftUI

/// Wanneer de lijst de schakelaar Mijn lijst | Thuis toont: als Thuis gedeeld is, of als er al iets in
/// Thuis staat (recepten of boodschappen) — zonder Thuis is er niets te kiezen.
enum BoodschappenSchakelaar {
    static func toon(rol: ThuisStatus.Rol, thuisItems: Int, thuisRecepten: Int) -> Bool {
        rol != .nietGedeeld || thuisItems > 0 || thuisRecepten > 0
    }
}

/// De eigen boodschappenlijst (#39, schets 2A): per afdeling in de volgorde van de winkel, ronde vinkjes,
/// afgevinkt zakt naar onderen. Groot genoeg om in de winkel met één hand te gebruiken.
struct BoodschappenScherm: View {
    var delen: ThuisDelen = .gedeeld
    var herinneringen: any Boodschappenbestemming = HerinneringenDienst.gedeeld

    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: Boodschappenlijsten.sortering) private var alle: FetchedResults<BoodschappenItem>
    @FetchRequest(
        sortDescriptors: [], predicate: NSPredicate(format: "kookboek == %@", Kookboek.thuis.rawValue))
    private var thuisRecepten: FetchedResults<Recept>

    @State private var kookboek: Kookboek
    @State private var nieuw = ""
    @State private var bewerken: TeBewerken?
    @State private var afgevinktOpen = true
    @State private var melding: String?
    @State private var bezig = false
    @FocusState private var invoerActief: Bool

    init(
        kookboek: Kookboek = .mijn, delen: ThuisDelen = .gedeeld,
        herinneringen: any Boodschappenbestemming = HerinneringenDienst.gedeeld
    ) {
        _kookboek = State(initialValue: kookboek)
        self.delen = delen
        self.herinneringen = herinneringen
    }

    private var items: [BoodschappenItem] {
        alle.filter { !$0.isDeleted && $0.kookboekWaarde == kookboek }
    }

    private var toonSchakelaar: Bool {
        kookboek == .thuis
            || BoodschappenSchakelaar.toon(
                rol: delen.status.rol, thuisItems: alle.filter { $0.kookboekWaarde == .thuis }.count,
                thuisRecepten: thuisRecepten.count)
    }

    var body: some View {
        let items = items
        let secties = Boodschappenlijsten.secties(items)
        let afgevinkt = Boodschappenlijsten.afgevinkt(items)
        List {
            if toonSchakelaar {
                Section {
                    Picker("Lijst", selection: $kookboek) {
                        Text("Mijn lijst").tag(Kookboek.mijn)
                        Text("Thuis").tag(Kookboek.thuis)
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.large)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                } footer: {
                    if kookboek == .thuis {
                        Text("Wie Thuis met je deelt, ziet en wijzigt deze lijst ook.")
                    }
                }
            }
            Section {
                invoer
            }
            if items.isEmpty {
                Section { leeg }
            }
            ForEach(secties, id: \.afdeling) { sectie in
                Section {
                    ForEach(sectie.items, id: \.objectID) { rij($0) }
                } header: {
                    SwiftUI.Label(sectie.afdeling.naam, systemImage: sectie.afdeling.symbool)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Kookkleuren.markering)
                }
            }
            if !afgevinkt.isEmpty {
                Section {
                    if afgevinktOpen {
                        ForEach(afgevinkt, id: \.objectID) { rij($0) }
                    }
                } header: {
                    Button {
                        withAnimation { afgevinktOpen.toggle() }
                    } label: {
                        HStack {
                            Text("Afgevinkt (\(afgevinkt.count))")
                            Spacer()
                            Image(systemName: afgevinktOpen ? "chevron.down" : "chevron.right")
                        }
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 36)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(afgevinktOpen ? "Tik om in te klappen" : "Tik om uit te klappen")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(kookboek == .thuis ? "Boodschappen · Thuis" : "Boodschappen")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("Meer", systemImage: "ellipsis") {
                    ShareLink(item: Boodschappenlijsten.tekst(items, kookboek: kookboek)) {
                        SwiftUI.Label("Delen als tekst", systemImage: "square.and.arrow.up")
                    }
                    .disabled(secties.isEmpty)
                    Button("Ook naar Herinneringen", systemImage: "checklist") {
                        Task { await naarHerinneringen(secties.flatMap(\.items)) }
                    }
                    .disabled(secties.isEmpty || bezig)
                    Divider()
                    Button("Wis afgevinkt", systemImage: "trash", role: .destructive) { wisAfgevinkt() }
                        .disabled(afgevinkt.isEmpty)
                }
            }
        }
        .sheet(item: $bewerken) { keuze in
            BoodschappenItemBewerken(item: keuze.item)
                .presentationDetents([.medium, .large])
        }
        .alert(
            "Boodschappen", isPresented: Binding(get: { melding != nil }, set: { if !$0 { melding = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(melding ?? "")
        }
        .task {
            await delen.vernieuw()
            await OnbekendeAfdelingen.gedeeld.deelIn(context: context)
        }
        .tint(Kookkleuren.accent)
    }

    // MARK: - Onderdelen

    private var invoer: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle.fill")
                .font(.title2)
                .foregroundStyle(Kookkleuren.accent)
                .accessibilityHidden(true)
            TextField("Item toevoegen, bijvoorbeeld 2 uien", text: $nieuw)
                .font(.body)
                .submitLabel(.done)
                .focused($invoerActief)
                .onSubmit(voegToe)
                .accessibilityLabel("Item toevoegen")
            if !nieuw.trimmingCharacters(in: .whitespaces).isEmpty {
                Button("Voeg toe", action: voegToe)
                    .fontWeight(.semibold)
                    .buttonStyle(.borderless)
            }
        }
        .frame(minHeight: 48)
    }

    private var leeg: some View {
        VStack(spacing: 10) {
            Image(systemName: "cart")
                .font(.system(size: 40))
                .foregroundStyle(Kookkleuren.accent)
                .accessibilityHidden(true)
            Text(kookboek == .thuis ? "De Thuis-lijst is leeg" : "Je lijst is leeg")
                .font(.headline)
            Text(
                "Zet boodschappen erop vanuit een recept (⋯ › Boodschappen…) of typ ze hierboven. Knipsel telt gelijke ingrediënten op en zet ze per afdeling, in de volgorde van de winkel."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            if kookboek == .thuis {
                Text("Wat hier staat, ziet je huisgenoot ook.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func rij(_ item: BoodschappenItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                vink(item)
            } label: {
                Image(systemName: item.afgevinkt ? "checkmark.circle.fill" : "circle")
                    .font(.title)
                    .foregroundStyle(item.afgevinkt ? Kookkleuren.accent : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.tekstOfNaam)
            .accessibilityValue(item.afgevinkt ? "afgevinkt" : "niet afgevinkt")
            .accessibilityHint(item.afgevinkt ? "Tik om terug op de lijst te zetten" : "Tik om af te vinken")
            Button {
                bewerken = TeBewerken(item: item)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.tekstOfNaam)
                        .font(.body)
                        .strikethrough(item.afgevinkt)
                        .foregroundStyle(item.afgevinkt ? .secondary : .primary)
                    if let herkomst = item.herkomst, !herkomst.isEmpty {
                        Text(herkomst)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Tik om te bewerken")
        }
        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 16))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Verwijder", systemImage: "trash", role: .destructive) { verwijder(item) }
        }
    }

    // MARK: - Acties

    private func voegToe() {
        let tekst = nieuw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tekst.isEmpty else { return }
        do {
            try Boodschappenlijsten.voegToe(tekst: tekst, kookboek: kookboek, context: context)
            nieuw = ""
            invoerActief = true
            Task { await OnbekendeAfdelingen.gedeeld.deelIn(context: context) }
        } catch {
            melding = Foutmelding.tekst(error, actie: "Toevoegen")
        }
    }

    private func vink(_ item: BoodschappenItem) {
        withAnimation {
            do {
                try Boodschappenlijsten.vink(item, af: !item.afgevinkt)
            } catch {
                melding = Foutmelding.tekst(error, actie: "Afvinken")
            }
        }
    }

    private func verwijder(_ item: BoodschappenItem) {
        do {
            try Boodschappenlijsten.verwijder(item)
        } catch {
            melding = Foutmelding.tekst(error, actie: "Verwijderen")
        }
    }

    private func wisAfgevinkt() {
        do {
            try Boodschappenlijsten.wisAfgevinkt(in: kookboek, context: context)
        } catch {
            melding = Foutmelding.tekst(error, actie: "Wissen")
        }
    }

    /// De open items ook in Herinneringen › Boodschappen (wat daar al open staat, slaat Knipsel over).
    private func naarHerinneringen(_ open: [BoodschappenItem]) async {
        bezig = true
        defer { bezig = false }
        var toegang = herinneringen.toegang
        if toegang == .nietGevraagd { toegang = await herinneringen.vraagToegang() }
        guard toegang == .toegestaan else {
            melding =
                "Knipsel mag niet in Herinneringen schrijven. Zet het aan in Instellingen › Apps › Knipsel › Herinneringen (Volledige toegang)."
            return
        }
        do {
            let resultaat = try await herinneringen.zetOpLijst(
                open.map(Boodschappenlijsten.regel), keuzes: [:], notitie: "Knipsel")
            var tekst = VelBestemming.herinneringen.bevestiging(aantal: resultaat.aantal) + "."
            if resultaat.overgeslagen > 0 { tekst += " \(resultaat.overgeslagen) stonden er al op." }
            melding = tekst
        } catch {
            melding = Foutmelding.tekst(error, actie: "Naar Herinneringen")
        }
    }
}

/// Het item dat in het vel Bewerken open staat.
private struct TeBewerken: Identifiable {
    let item: BoodschappenItem
    var id: NSManagedObjectID { item.objectID }
}

/// 🛒 in de bibliotheek met het aantal open items (beide lijsten samen).
struct BoodschappenKnop: View {
    var actie: () -> Void
    @FetchRequest(sortDescriptors: [], predicate: Boodschappenlijsten.predicaatOpen(kookboek: nil))
    private var open: FetchedResults<BoodschappenItem>

    var body: some View {
        Button(action: actie) {
            // Het getal als superscript naast de kar (schets 2A), binnen de knop: een overlay buiten het
            // frame snijdt de glazen knop af.
            HStack(alignment: .top, spacing: 1) {
                Image(systemName: "cart")
                if open.count > 0 {
                    Text(open.count > 99 ? "99+" : "\(open.count)")
                        .font(.system(size: 11, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Kookkleuren.accent, in: Capsule())
                        .offset(y: -2)
                }
            }
        }
        .accessibilityLabel(open.isEmpty ? "Boodschappen" : "Boodschappen, \(open.count) open")
    }
}
