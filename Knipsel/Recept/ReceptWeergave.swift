import CoreData
import OSLog
import SwiftUI

/// Een recept lezen: serif, begrensde regellengte, ingrediënten afvinkbaar, genummerde stappen.
/// Op brede schermen staan ingrediënten en bereiding naast elkaar (K6).
struct ReceptWeergave: View {
    @ObservedObject var recept: Recept
    var naVerwijderen: () -> Void = {}

    init(recept: Recept, porties: Int? = nil, naVerwijderen: @escaping () -> Void = {}) {
        self.recept = recept
        self.naVerwijderen = naVerwijderen
        _gekozenPorties = State(initialValue: porties ?? 0)
    }

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dynamicTypeSize) private var systeemgrootte
    @AppStorage(AppConfiguratie.sleutelLettertype) private var lettertype: Lettertype = .serif
    @AppStorage(AppConfiguratie.sleutelExtraGrootte) private var extraGrootte = 0

    /// Alleen in het geheugen: afvinken hoort bij deze kookbeurt, niet bij het recept.
    @State private var afgevinkt: Set<NSManagedObjectID> = []
    @State private var toonBewerken = false
    @State private var toonLeesinstellingen = false
    @State private var bevestigVerwijderen = false
    @State private var beschikbareBreedte: CGFloat = 0
    /// Gekozen aantal personen; 0 = zoals in het recept.
    @State private var gekozenPorties = 0
    @State private var kookSessie: KookSessie?

    /// ±60–65 tekens per regel bij bodytekst in New York (Dyson, 2004); schaalt mee met de tekstgrootte.
    @ScaledMetric(relativeTo: .body) private var leesbreedte: CGFloat = 560
    @ScaledMetric(relativeTo: .body) private var ingredientenBreedte: CGFloat = 300
    /// Op iPad smaller en gecentreerd; op een iPhone vult de balk de breedte.
    @ScaledMetric(relativeTo: .body) private var balkBreedte: CGFloat = 480

    private var porties: Int { gekozenPorties > 0 ? gekozenPorties : Int(recept.porties) }
    private var factor: Double { Portieschaling.factor(van: Int(recept.porties), naar: porties) }

    private var tekstgrootte: DynamicTypeSize { Leesinstellingen.vergroot(systeemgrootte, met: extraGrootte) }

    /// Naast elkaar alleen als er ruimte is voor beide kolommen en de tekst niet heel groot is.
    private var naastElkaar: Bool {
        !tekstgrootte.isAccessibilitySize && beschikbareBreedte >= ingredientenBreedte + 32 + 420
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                kop
                if naastElkaar {
                    HStack(alignment: .top, spacing: 40) {
                        ingredientenBlok
                            .frame(width: ingredientenBreedte, alignment: .leading)
                        stappenBlok
                            .frame(maxWidth: leesbreedte, alignment: .leading)
                    }
                } else {
                    ingredientenBlok
                    stappenBlok
                }
                notitiesBlok
            }
            .frame(maxWidth: naastElkaar ? ingredientenBreedte + 40 + leesbreedte : leesbreedte, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) { receptBalk }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width - 40
        } action: {
            beschikbareBreedte = $0
        }
        .dynamicTypeSize(tekstgrootte)
        .navigationTitle(recept.titelOfStandaard)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Weergave", systemImage: "textformat.size") { toonLeesinstellingen = true }
                Menu("Meer", systemImage: "ellipsis") {
                    Button("Bewerk", systemImage: "pencil") { toonBewerken = true }
                    Button("Verwijder", systemImage: "trash", role: .destructive) { bevestigVerwijderen = true }
                }
            }
        }
        .sheet(isPresented: $toonBewerken) { ReceptBewerken(recept: recept) }
        .fullScreenCover(item: $kookSessie) { sessie in
            KookmodusScherm(sessie: sessie, gekookt: legGekooktVast)
        }
        .sheet(isPresented: $toonLeesinstellingen) {
            LeesinstellingenView().presentationDetents([.medium, .large])
        }
        .confirmationDialog("Recept verwijderen?", isPresented: $bevestigVerwijderen, titleVisibility: .visible) {
            Button("Verwijder \u{201C}\(recept.titelOfStandaard)\u{201D}", role: .destructive, action: verwijder)
        } message: {
            Text("Dit kan niet ongedaan worden gemaakt.")
        }
    }

    // MARK: Onderdelen

    private func lettertype(_ stijl: Font.TextStyle) -> Font {
        .system(stijl, design: lettertype.ontwerp)
    }

    private var kop: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(recept.titelOfStandaard)
                .font(lettertype(.largeTitle).bold())
                .accessibilityAddTraits(.isHeader)
            if let bron = Weergave.bron(naam: recept.bronNaam, datum: recept.bronDatum, pagina: recept.bronPagina) {
                Text(bron)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            tijdblokken
            if !(recept.categorieen ?? []).isEmpty || !(recept.labels ?? []).isEmpty || recept.aantalKeerGekookt > 0 {
                Stroomopmaak {
                    ForEach(recept.gesorteerdeCategorieen, id: \.objectID) { categorie in
                        Kenmerk(titel: categorie.naamOfStandaard, symbool: categorie.symboolOfStandaard)
                    }
                    ForEach(recept.gesorteerdeLabels, id: \.objectID) { label in
                        Kenmerk(titel: label.naamOfStandaard)
                    }
                    if recept.aantalKeerGekookt > 0 {
                        Kenmerk(titel: "\(recept.aantalKeerGekookt)× gekookt", symbool: "checkmark.circle")
                    }
                }
            }
            if let intro = recept.intro, !intro.isEmpty {
                Text(intro)
                    .font(lettertype(.body).italic())
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    /// Bereiden, totaal en personen als blokjes naast elkaar (schets v2, Recept A); alleen wat er is.
    @ViewBuilder private var tijdblokken: some View {
        let blokken = Weergave.tijdblokken(
            bereiding: Int(recept.bereidingstijdMinuten), totaal: Int(recept.totaleTijdMinuten),
            porties: recept.porties > 0 ? porties : 0)
        if !blokken.isEmpty {
            Stroomopmaak {
                ForEach(blokken, id: \.omschrijving) { tijdblok($0) }
            }
            .padding(.top, 4)
        }
    }

    private func tijdblok(_ blok: Weergave.Tijdblok) -> some View {
        VStack(spacing: 2) {
            Text(blok.waarde)
                .font(.headline)
                .monospacedDigit()
            Text(blok.omschrijving)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minWidth: 92)
        .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    /// Vaste balk onderin (U2): porties en "Kook dit" onder de duim, ook als je naar de bereiding scrolt.
    @ViewBuilder private var receptBalk: some View {
        let kanKoken = !recept.gesorteerdeStappen.isEmpty
        if kanKoken || recept.porties > 0 {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    portiesKnoppen
                    if kanKoken { kookKnop }
                }
                VStack(spacing: 8) {
                    portiesKnoppen
                    if kanKoken { kookKnop }
                }
            }
            .padding(.vertical, 8)
            .padding(.leading, recept.porties > 0 ? 10 : 8)
            .padding(.trailing, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 33, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 33, style: .continuous).stroke(Color(.separator), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            .frame(maxWidth: balkBreedte)
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
    }

    private var kookKnop: some View {
        Button {
            kookSessie = KookSessie(recept: recept, porties: porties > 0 ? porties : nil)
        } label: {
            SwiftUI.Label("Kook dit", systemImage: "play.fill")
                .font(.headline.weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(Kookkleuren.accent, in: Capsule())
                .foregroundStyle(.white)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opent de kookmodus: één stap tegelijk, groot, en het scherm blijft aan")
    }

    private var ingredientenBlok: some View {
        VStack(alignment: .leading, spacing: 12) {
            ingredientenKop
            let ingredienten = recept.gesorteerdeIngredienten
            if ingredienten.isEmpty {
                Text("Geen ingrediënten ingevoerd.").foregroundStyle(.secondary)
            }
            ForEach(Array(ingredienten.enumerated()), id: \.element.objectID) { index, ingredient in
                if let groep = nieuweGroep(ingredient.groep, vorige: index > 0 ? ingredienten[index - 1].groep : nil) {
                    Text(groep)
                        .font(lettertype(.headline))
                        .padding(.top, 6)
                }
                ingredientRegel(ingredient)
            }
        }
    }

    private var ingredientenKop: some View {
        Text(recept.porties > 0 ? "Ingrediënten · voor \(porties)" : "Ingrediënten")
            .font(lettertype(.title2).bold())
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var portiesKnoppen: some View {
        if recept.porties > 0 {
            PortiesKnoppen(porties: porties, wijzig: { gekozenPorties = min(99, max(1, $0)) }, rond: true)
        }
    }

    private func ingredientRegel(_ ingredient: Ingredient) -> some View {
        let isAf = afgevinkt.contains(ingredient.objectID)
        return Button {
            if isAf {
                afgevinkt.remove(ingredient.objectID)
            } else {
                afgevinkt.insert(ingredient.objectID)
            }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: isAf ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isAf ? Color.secondary : Color.accentColor)
                ingredientTekst(ingredient)
                    .font(lettertype(.body))
                    .strikethrough(isAf)
                    .foregroundStyle(isAf ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isAf ? "afgevinkt" : "")
        .accessibilityHint("Tik om af te vinken")
    }

    /// Gestructureerd (na de parser, fase 2): hoeveelheid en eenheid vet. Anders de ruwe tekst.
    private func ingredientTekst(_ ingredient: Ingredient) -> Text {
        guard let hoeveelheid = ingredient.hoeveelheid?.doubleValue, let naam = ingredient.naam else {
            return Text(ingredient.ruweTekst ?? "")
        }
        let maat =
            Portieschaling.maat(
                hoeveelheid: hoeveelheid, tot: ingredient.hoeveelheidTot?.doubleValue, eenheid: ingredient.eenheid,
                factor: factor) ?? ""
        let toelichting = ingredient.toelichting.map { Portieschaling.schaalToelichting($0, factor: factor) }
        let geteld = Portieschaling.naam(
            naam, hoeveelheid: hoeveelheid, tot: ingredient.hoeveelheidTot?.doubleValue, eenheid: ingredient.eenheid,
            factor: factor)
        let rest = [geteld, toelichting].compactMap { $0 }.joined(separator: ", ")
        return Text("\(Text(maat).bold()) \(rest)")
    }

    private var stappenBlok: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Bereiding")
                .font(lettertype(.title2).bold())
                .accessibilityAddTraits(.isHeader)
            let stappen = recept.gesorteerdeStappen
            if stappen.isEmpty {
                Text("Geen stappen ingevoerd.").foregroundStyle(.secondary)
            }
            ForEach(Array(stappen.enumerated()), id: \.element.objectID) { index, stap in
                if let groep = nieuweGroep(stap.groep, vorige: index > 0 ? stappen[index - 1].groep : nil) {
                    Text(groep)
                        .font(lettertype(.headline))
                        .padding(.top, 6)
                }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(index + 1, format: .number)
                        .font(lettertype(.title3).bold())
                        .foregroundStyle(Color.accentColor)
                        .frame(minWidth: 24, alignment: .trailing)
                        .accessibilityLabel("Stap \(index + 1)")
                    VStack(alignment: .leading, spacing: 6) {
                        Text(stap.tekst ?? "")
                            .font(lettertype(.body))
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                        if let timer = Weergave.tijd(minuten: Int(stap.timerSeconden) / 60) {
                            SwiftUI.Label(timer, systemImage: "timer")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder private var notitiesBlok: some View {
        if let notities = recept.notities, !notities.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Notities")
                    .font(lettertype(.title3).bold())
                    .accessibilityAddTraits(.isHeader)
                Text(notities)
                    .font(lettertype(.body))
            }
        }
    }

    private func nieuweGroep(_ groep: String?, vorige: String?) -> String? {
        guard let groep, !groep.isEmpty, groep != vorige else { return nil }
        return groep
    }

    private func legGekooktVast() {
        do {
            try recept.legGekooktVast()
        } catch {
            context.rollback()
            Logger(subsystem: "com.peterbijkerk.knipsel", category: "Recept")
                .error("Gekookt vastleggen mislukt: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func verwijder() {
        naVerwijderen()
        context.delete(recept)
        do {
            try context.save()
        } catch {
            context.rollback()
            Logger(subsystem: "com.peterbijkerk.knipsel", category: "Recept")
                .error("Verwijderen mislukt: \(error.localizedDescription, privacy: .public)")
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            ReceptWeergave(recept: Opslag.voorbeeld.eersteRecept)
        }
        .environment(\.managedObjectContext, Opslag.voorbeeld.context)
    }
#endif
