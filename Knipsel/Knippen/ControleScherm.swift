import CoreData
import SwiftUI

/// De invoer van het controlescherm: het concept uit de indeling plus de keuzes van de gebruiker.
struct ControleInvoer: Equatable {
    var concept: ReceptConcept
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
        // Een stap per alinea; regeleinden binnen een stap worden spaties.
        invoer.stappenTekst = concept.stappen.map { $0.tekst.replacingOccurrences(of: "\n", with: " ") }
            .joined(separator: "\n\n")
        return invoer
    }
}

/// Het controlescherm: het gestructureerde recept, bewerkbaar, met twijfel in oranje en
/// categorie- en labelvoorstellen als knopjes. Op iPad staat de foto ernaast.
struct ControleScherm: View {
    let sessie: KnipSessie
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

    init(sessie: KnipSessie, invoer: ControleInvoer, klaar: @escaping () -> Void) {
        self.sessie = sessie
        self.klaar = klaar
        _invoer = State(initialValue: invoer)
    }

    var body: some View {
        Group {
            if breedte == .regular {
                HStack(spacing: 0) {
                    KnipselScherm(sessie: sessie, alleenKijken: true)
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
                        Text(
                            invoer.twijfelAantal == 1
                                ? "1 regel om te controleren. Vergelijk hem met de uitsnede uit de foto."
                                : "\(invoer.twijfelAantal) regels om te controleren. Vergelijk ze met de uitsnede uit de foto."
                        )
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    .font(.subheadline)
                }
                .listRowBackground(Color.orange.opacity(0.15))
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
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(index + 1, format: .number)
                            .font(.headline)
                            .foregroundStyle(Color.accentColor)
                            .frame(minWidth: 18, alignment: .trailing)
                        regelVeld($regel, isIngredient: false, plaatshouder: "Stap")
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
                LabeledContent("Blad") {
                    TextField("Blad of boek", text: $invoer.bronNaam)
                        .multilineTextAlignment(.trailing)
                }
                DatePicker("Datum", selection: $invoer.bronDatum, displayedComponents: .date)
                LabeledContent("Pagina") {
                    TextField("Pagina", text: $invoer.bronPagina)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Kookboek", value: Kookboek.mijn.naam)
            } header: {
                Text("Bron")
            } footer: {
                Text("Alleen de tekst wordt bewaard; de foto niet.")
            }
        }
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
            }
            if twijfel, let uitsnede = sessie.uitsnede(regel.wrappedValue.regels) {
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
            try invoer.receptInvoer.bewaar(in: context)
            sessie.herstel()  // de foto's uit het geheugen (B7)
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
