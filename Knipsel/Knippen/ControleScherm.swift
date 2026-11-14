import CoreData
import SwiftUI

/// De invoer van het controlescherm: het concept uit de indeling plus de keuzes van de gebruiker.
struct ControleInvoer: Equatable {
    /// Waar het recept vandaan komt: bepaalt de woorden in het bronblok.
    enum Soort: Equatable {
        /// Een geknipte pagina (foto): blad, datum, pagina.
        case papier
        /// Een website: site, datum, link (in `bronPagina`).
        case website
        /// Geplakte of gedeelde tekst, of een PDF.
        case tekst
    }

    var concept: ReceptConcept
    var soort = Soort.papier
    /// De receptfoto van de site (al bijgesneden en verkleind, `GerechtFoto`); nooit een krantenfoto (B7).
    var fotoData: Data?
    var categorieen: Set<NSManagedObjectID> = []
    var labels: Set<NSManagedObjectID> = []
    /// Wat de indeler voorstelde; blijft zichtbaar als voorstel als de gebruiker het uitzet.
    var voorgesteldeCategorieen: Set<NSManagedObjectID> = []
    var voorgesteldeLabels: Set<NSManagedObjectID> = []
    var bronNaam = ""
    var bronDatum = Date.now
    var bronPagina = ""

    var twijfelAantal: Int {
        concept.ingredienten.filter { ReceptOpbouw.isTwijfel($0, isIngredient: true) }.count
            + concept.stappen.filter { ReceptOpbouw.isTwijfel($0, isIngredient: false) }.count
    }

    /// Naar het gewone invoerformulier; bewaren gaat via de bestaande opslaglaag.
    var receptInvoer: ReceptInvoer {
        var invoer = ReceptInvoer()
        invoer.titel = concept.titel
        invoer.intro = concept.intro
        invoer.porties = concept.porties
        invoer.bereidingstijdMinuten = concept.minuten
        invoer.bronNaam = bronNaam
        invoer.bronDatum = bronDatum
        invoer.bronPagina = bronPagina
        invoer.categorieen = categorieen
        invoer.labels = labels
        invoer.ingredientenTekst = concept.ingredienten.map(\.tekst).joined(separator: "\n")
        // Een stap per alinea; regeleinden binnen een stap worden spaties. Een stapgroep (van een
        // website) wordt een kopregel met dubbele punt, die `ReceptInvoer` weer als groep leest.
        var regels: [String] = []
        var groep: String?
        for stap in concept.stappen {
            if let nieuw = stap.groep, !nieuw.isEmpty, nieuw != groep { regels.append(nieuw + ":") }
            groep = stap.groep
            regels.append(stap.tekst.replacingOccurrences(of: "\n", with: " "))
        }
        invoer.stappenTekst = regels.joined(separator: "\n\n")
        return invoer
    }
}

/// Het controlescherm: het gestructureerde recept, bewerkbaar, met twijfel in oranje en
/// categorie- en labelvoorstellen als knopjes. Op iPad staat de foto ernaast. Zonder knipsessie
/// (een website, geplakte tekst) is er geen paginafoto en geen uitsnede.
struct ControleScherm: View {
    let sessie: KnipSessie?
    let klaar: () -> Void

    @Environment(\.managedObjectContext) private var context
    @Environment(\.horizontalSizeClass) private var breedte
    @State private var invoer: ControleInvoer
    @State private var foutmelding: String?

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "volgorde", ascending: true)],
        predicate: NSPredicate(format: "verborgen == NO"))
    private var categorieen: FetchedResults<Categorie>
    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(
            key: "naam", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
    ])
    private var labels: FetchedResults<ReceptLabel>

    init(sessie: KnipSessie?, invoer: ControleInvoer, klaar: @escaping () -> Void) {
        self.sessie = sessie
        self.klaar = klaar
        _invoer = State(initialValue: invoer)
    }

    var body: some View {
        Group {
            if breedte == .regular, let sessie, !sessie.paginas.isEmpty {
                HStack(spacing: 0) {
                    KnipselScherm(sessie: sessie, alleenKijken: true)
                        .containerRelativeFrame(.horizontal) { lengte, _ in lengte * 0.42 }
                        .background(Color(.secondarySystemBackground))
                    Divider()
                    formulier
                }
            } else if breedte == .regular, let beeld = fotoBeeld {
                // Website op iPad: de foto van de site links, zoals de paginafoto bij knippen.
                HStack(spacing: 0) {
                    VStack(spacing: 16) {
                        Image(uiImage: beeld)
                            .resizable()
                            .aspectRatio(GerechtFoto.verhouding, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .accessibilityLabel("Foto van het gerecht van de site")
                        fotoWegKnop
                        Text(fotoUitleg)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer(minLength: 0)
                    }
                    .padding(24)
                    .containerRelativeFrame(.horizontal) { lengte, _ in lengte * 0.42 }
                    .background(Color(.secondarySystemBackground))
                    Divider()
                    formulier
                }
            } else {
                formulier
            }
        }
        .navigationTitle("Controle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Bewaar", action: bewaar)
                    .disabled(invoer.concept.titel.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .alert(
            "Bewaren mislukt", isPresented: Binding(get: { foutmelding != nil }, set: { if !$0 { foutmelding = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(foutmelding ?? "")
        }
    }

    private var formulier: some View {
        Form {
            if invoer.twijfelAantal > 0 {
                Section {
                    SwiftUI.Label {
                        Text(twijfelTekst)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    .font(.subheadline)
                }
                .listRowBackground(Color.orange.opacity(0.15))
            }

            if breedte != .regular, let beeld = fotoBeeld {
                Section {
                    Image(uiImage: beeld)
                        .resizable()
                        .aspectRatio(GerechtFoto.verhouding, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                        .accessibilityLabel("Foto van het gerecht van de site")
                    fotoWegKnop
                } footer: {
                    Text(fotoUitleg)
                }
            }

            Section {
                TextField("Titel", text: $invoer.concept.titel, axis: .vertical)
                    .font(.system(.title3, design: .serif).bold())
                TextField("Intro (optioneel)", text: $invoer.concept.intro, axis: .vertical)
                    .lineLimit(1...6)
                Stepper(value: $invoer.concept.porties, in: 0...99) {
                    LabeledContent("Porties", value: Weergave.porties(invoer.concept.porties) ?? "onbekend")
                }
                LabeledContent("Bereidingstijd") {
                    HStack(spacing: 4) {
                        TextField("0", value: $invoer.concept.minuten, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(minWidth: 44)
                        Text("min").foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                ForEach($invoer.concept.ingredienten) { $regel in
                    regelVeld($regel, isIngredient: true, plaatshouder: "Ingrediënt")
                }
                .onDelete { invoer.concept.ingredienten.remove(atOffsets: $0) }
                Button("Ingrediënt toevoegen", systemImage: "plus") {
                    invoer.concept.ingredienten.append(ConceptRegel(tekst: ""))
                }
            } header: {
                Text("Ingrediënten")
            }

            Section {
                ForEach(Array($invoer.concept.stappen.enumerated()), id: \.element.id) { index, $regel in
                    VStack(alignment: .leading, spacing: 6) {
                        if let groep = nieuweGroep(index) {
                            Text(groep)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityAddTraits(.isHeader)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(index + 1, format: .number)
                                .font(.headline)
                                .foregroundStyle(Color.accentColor)
                                .frame(minWidth: 18, alignment: .trailing)
                            regelVeld($regel, isIngredient: false, plaatshouder: "Stap")
                            if heeftStapActies(index) {
                                Menu {
                                    stapActies(index)
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .foregroundStyle(Color.accentColor)
                                        .frame(minWidth: 28, minHeight: 28)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Stap \(index + 1) splitsen of samenvoegen")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contextMenu { stapActies(index) }
                    .swipeActions(edge: .leading) {
                        if index > 0 {
                            Button("Samenvoegen", systemImage: "arrow.merge") { voegSamen(index) }
                                .tint(.accentColor)
                        }
                    }
                    .listRowBackground(
                        ReceptOpbouw.isTwijfel(regel, isIngredient: false) ? Color.orange.opacity(0.15) : nil)
                }
                .onDelete { invoer.concept.stappen.remove(atOffsets: $0) }
                Button("Stap toevoegen", systemImage: "plus") {
                    invoer.concept.stappen.append(ConceptRegel(tekst: ""))
                }
            } header: {
                Text("Bereiding")
            } footer: {
                if invoer.concept.stappen.count > 1 || invoer.concept.stappen.contains(where: { isSplitsbaar($0) }) {
                    Text("Met ⋯ bij een stap splits je hem op een zin, of voeg je hem samen met de stap ervoor.")
                }
            }

            Section {
                Stroom(afstand: 8) {
                    ForEach(categorieen, id: \.objectID) { categorie in
                        keuzeChip(
                            categorie.naamOfStandaard, id: categorie.objectID, in: $invoer.categorieen,
                            voorstel: invoer.voorgesteldeCategorieen)
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            } header: {
                Text("Categorie")
            } footer: {
                if let voorstel = namen(invoer.voorgesteldeCategorieen, uit: categorieen.map(\.objectID)) {
                    Text("Voorstel: \(voorstel). Meerdere kiezen mag.")
                }
            }

            if !labels.isEmpty {
                Section {
                    Stroom(afstand: 8) {
                        ForEach(labels, id: \.objectID) { label in
                            keuzeChip(
                                label.naamOfStandaard, id: label.objectID, in: $invoer.labels,
                                voorstel: invoer.voorgesteldeLabels)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                } header: {
                    Text("Labels")
                } footer: {
                    if let voorstel = namen(invoer.voorgesteldeLabels, uit: labels.map(\.objectID)) {
                        Text("Voorstel: \(voorstel).")
                    }
                }
            }

            Section {
                LabeledContent(invoer.soort == .website ? "Site" : "Blad") {
                    TextField(invoer.soort == .website ? "Naam van de site" : "Blad of boek", text: $invoer.bronNaam)
                        .multilineTextAlignment(.trailing)
                }
                DatePicker("Datum", selection: $invoer.bronDatum, displayedComponents: .date)
                LabeledContent(invoer.soort == .website ? "Link" : "Pagina") {
                    TextField(invoer.soort == .website ? "Webadres" : "Pagina", text: $invoer.bronPagina)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(invoer.soort == .website ? .URL : .default)
                        .textInputAutocapitalization(invoer.soort == .website ? .never : nil)
                        .lineLimit(1)
                }
                LabeledContent("Kookboek", value: Kookboek.mijn.naam)
            } header: {
                Text("Bron")
            } footer: {
                Text(bronUitleg)
            }
        }
    }

    private var fotoBeeld: UIImage? {
        invoer.fotoData.flatMap(UIImage.init(data:))
    }

    private var fotoWegKnop: some View {
        Button("Foto niet bewaren", systemImage: "photo.badge.minus", role: .destructive) {
            withAnimation { invoer.fotoData = nil }
        }
    }

    private let fotoUitleg = "De foto van de site komt bij het recept. Uit te zetten in Instellingen › Inlezen."

    private var twijfelTekst: String {
        let vergelijk = sessie?.paginas.isEmpty == false ? " Vergelijk met de uitsnede uit de foto." : ""
        return invoer.twijfelAantal == 1
            ? "1 regel om te controleren.\(vergelijk)"
            : "\(invoer.twijfelAantal) regels om te controleren.\(vergelijk)"
    }

    private var bronUitleg: String {
        switch invoer.soort {
        case .papier: "Alleen de tekst wordt bewaard; de foto niet."
        case .website: "De site, de link en de datum blijven bij het recept."
        case .tekst: "Vul in waar het recept vandaan komt, als je dat weet."
        }
    }

    /// Het kopje van een stapgroep, alleen bij de eerste stap van die groep.
    private func nieuweGroep(_ index: Int) -> String? {
        let stappen = invoer.concept.stappen
        guard stappen.indices.contains(index), let groep = stappen[index].groep, !groep.isEmpty else { return nil }
        return index > 0 && stappen[index - 1].groep == groep ? nil : groep
    }

    // MARK: - Splitsen en samenvoegen

    private func isSplitsbaar(_ stap: ConceptRegel) -> Bool {
        StapSplitser.zinnen(in: stap.tekst).count > 1
    }

    private func heeftStapActies(_ index: Int) -> Bool {
        index > 0 || (invoer.concept.stappen.indices.contains(index) && isSplitsbaar(invoer.concept.stappen[index]))
    }

    /// "Splits hier" (kies de zin waarmee de nieuwe stap begint) en "Voeg samen met vorige".
    @ViewBuilder
    private func stapActies(_ index: Int) -> some View {
        if invoer.concept.stappen.indices.contains(index) {
            let zinnen = StapSplitser.zinnen(in: invoer.concept.stappen[index].tekst)
            if zinnen.count > 1 {
                Menu("Splits hier", systemImage: "scissors") {
                    ForEach(1..<zinnen.count, id: \.self) { zin in
                        Button("Vóór „\(Self.begin(van: zinnen[zin]))”") {
                            withAnimation { invoer.concept.splitsStap(index, voorZin: zin) }
                        }
                    }
                }
            }
            if index > 0 {
                Button("Voeg samen met vorige", systemImage: "arrow.merge") { voegSamen(index) }
            }
        }
    }

    private func voegSamen(_ index: Int) {
        withAnimation { invoer.concept.voegStapSamenMetVorige(index) }
    }

    /// De eerste woorden van een zin, voor in het menu.
    static func begin(van zin: String) -> String {
        let woorden = zin.split(separator: " ")
        return woorden.count <= 6 ? zin : woorden.prefix(6).joined(separator: " ") + " …"
    }

    /// Eén ingrediënt of stap; bij twijfel oranje met de uitsnede uit de foto eronder.
    private func regelVeld(_ regel: Binding<ConceptRegel>, isIngredient: Bool, plaatshouder: String) -> some View {
        let twijfel = ReceptOpbouw.isTwijfel(regel.wrappedValue, isIngredient: isIngredient)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if twijfel {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Controleren")
                }
                TextField(plaatshouder, text: regel.tekst, axis: .vertical)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if twijfel, let uitsnede = sessie?.uitsnede(regel.wrappedValue.regels) {
                Image(uiImage: uitsnede)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 48, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.orange.opacity(0.6)))
                    .accessibilityLabel("Uitsnede uit de foto")
            }
        }
        .listRowBackground(isIngredient && twijfel ? Color.orange.opacity(0.15) : nil)
    }

    private func keuzeChip(
        _ titel: String, id: NSManagedObjectID, in gekozen: Binding<Set<NSManagedObjectID>>,
        voorstel: Set<NSManagedObjectID>
    ) -> some View {
        let isGekozen = gekozen.wrappedValue.contains(id)
        return Chip(
            titel: titel, symbool: isGekozen ? "checkmark" : (voorstel.contains(id) ? "sparkles" : nil),
            gekozen: isGekozen
        ) {
            if isGekozen {
                gekozen.wrappedValue.remove(id)
            } else {
                gekozen.wrappedValue.insert(id)
            }
        }
    }

    private func namen(_ ids: Set<NSManagedObjectID>, uit volgorde: [NSManagedObjectID]) -> String? {
        let namen = volgorde.filter(ids.contains).compactMap { id -> String? in
            switch try? context.existingObject(with: id) {
            case let categorie as Categorie: categorie.naamOfStandaard
            case let label as ReceptLabel: label.naamOfStandaard
            default: nil
            }
        }
        return namen.isEmpty ? nil : namen.joined(separator: ", ")
    }

    private func bewaar() {
        do {
            let recept = try invoer.receptInvoer.bewaar(in: context)
            if let foto = invoer.fotoData {
                try recept.zetFoto(foto)
            }
            sessie?.herstel()  // de foto's uit het geheugen (B7)
            klaar()
        } catch {
            context.rollback()
            foutmelding = error.localizedDescription
        }
    }
}

/// Knopjes die naar de volgende regel doorlopen.
struct Stroom: Layout {
    var afstand: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rijen = indeling(breedte: proposal.width ?? .infinity, subviews: subviews)
        let hoogte = rijen.map(\.hoogte).reduce(0, +) + afstand * CGFloat(max(0, rijen.count - 1))
        let breedte = rijen.map(\.breedte).max() ?? 0
        return CGSize(width: proposal.width ?? breedte, height: hoogte)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for rij in indeling(breedte: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in rij.indices {
                let maat = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(maat))
                x += maat.width + afstand
            }
            y += rij.hoogte + afstand
        }
    }

    private struct Rij {
        var indices: [Int] = []
        var breedte: CGFloat = 0
        var hoogte: CGFloat = 0
    }

    private func indeling(breedte: CGFloat, subviews: Subviews) -> [Rij] {
        var rijen: [Rij] = []
        var rij = Rij()
        for index in subviews.indices {
            let maat = subviews[index].sizeThatFits(.unspecified)
            let nieuweBreedte = rij.indices.isEmpty ? maat.width : rij.breedte + afstand + maat.width
            if nieuweBreedte > breedte, !rij.indices.isEmpty {
                rijen.append(rij)
                rij = Rij(indices: [index], breedte: maat.width, hoogte: maat.height)
            } else {
                rij.indices.append(index)
                rij.breedte = nieuweBreedte
                rij.hoogte = max(rij.hoogte, maat.height)
            }
        }
        if !rij.indices.isEmpty { rijen.append(rij) }
        return rijen
    }
}
