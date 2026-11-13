import CoreData
import SwiftUI

/// Recept handmatig invoeren of bewerken. Wijzigingen gaan pas naar de opslag bij "Bewaar".
struct ReceptBewerken: View {
    let recept: Recept?

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var invoer: ReceptInvoer
    @State private var foutmelding: String?

    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "volgorde", ascending: true)])
    private var categorieen: FetchedResults<Categorie>
    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(
            key: "naam", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
    ])
    private var labels: FetchedResults<ReceptLabel>

    init(recept: Recept?) {
        self.recept = recept
        _invoer = State(initialValue: recept.map(ReceptInvoer.init(recept:)) ?? ReceptInvoer())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Titel", text: $invoer.titel, axis: .vertical)
                        .font(.system(.title3, design: .serif).bold())
                    TextField("Intro (optioneel)", text: $invoer.intro, axis: .vertical)
                        .lineLimit(2...8)
                }

                Section("Porties en tijd") {
                    Stepper(value: $invoer.porties, in: 0...99) {
                        LabeledContent("Porties", value: Weergave.porties(invoer.porties) ?? "onbekend")
                    }
                    minutenVeld("Bereidingstijd", waarde: $invoer.bereidingstijdMinuten)
                    minutenVeld("Totale tijd", waarde: $invoer.totaleTijdMinuten)
                }

                Section("Indeling") {
                    NavigationLink {
                        Keuzelijst(
                            titel: "Categorieën",
                            items: categorieen.map {
                                Keuzelijst.Item(
                                    id: $0.objectID, naam: $0.naamOfStandaard, symbool: $0.symboolOfStandaard,
                                    toelichting: $0.verborgen ? "verborgen" : nil)
                            },
                            gekozen: $invoer.categorieen)
                    } label: {
                        LabeledContent(
                            "Categorieën",
                            value: samenvatting(
                                invoer.categorieen, uit: categorieen.map { ($0.objectID, $0.naamOfStandaard) }))
                    }
                    NavigationLink {
                        Keuzelijst(
                            titel: "Labels",
                            items: labels.map {
                                Keuzelijst.Item(id: $0.objectID, naam: $0.naamOfStandaard, symbool: "tag")
                            },
                            gekozen: $invoer.labels)
                    } label: {
                        LabeledContent(
                            "Labels",
                            value: samenvatting(invoer.labels, uit: labels.map { ($0.objectID, $0.naamOfStandaard) }))
                    }
                }

                Section {
                    TextField("Bijvoorbeeld: 2 el olijfolie", text: $invoer.ingredientenTekst, axis: .vertical)
                        .lineLimit(4...30)
                } header: {
                    Text("Ingrediënten")
                } footer: {
                    Text("Eén ingrediënt per regel.")
                }

                Section {
                    TextField("Bijvoorbeeld: Verhit de olie in een pan.", text: $invoer.stappenTekst, axis: .vertical)
                        .lineLimit(4...40)
                } header: {
                    Text("Bereiding")
                } footer: {
                    Text("Eén stap per alinea.")
                }

                Section("Bron") {
                    TextField("Blad of boek", text: $invoer.bronNaam)
                    Toggle("Datum bekend", isOn: datumBekend)
                    if let datum = invoer.bronDatum {
                        DatePicker(
                            "Datum", selection: Binding(get: { datum }, set: { invoer.bronDatum = $0 }),
                            displayedComponents: .date)
                    }
                    TextField("Pagina", text: $invoer.bronPagina)
                }

                Section("Notities") {
                    TextField("Bijvoorbeeld: minder zout", text: $invoer.notities, axis: .vertical)
                        .lineLimit(2...12)
                }
            }
            .navigationTitle(recept == nil ? "Nieuw recept" : "Recept bewerken")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bewaar", action: bewaar)
                        .disabled(!invoer.isGeldig)
                }
            }
            .alert(
                "Bewaren mislukt",
                isPresented: Binding(get: { foutmelding != nil }, set: { if !$0 { foutmelding = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(foutmelding ?? "")
            }
        }
    }

    private func minutenVeld(_ titel: String, waarde: Binding<Int>) -> some View {
        LabeledContent(titel) {
            HStack(spacing: 4) {
                TextField("0", value: waarde, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(minWidth: 44)
                Text("min").foregroundStyle(.secondary)
            }
        }
    }

    private var datumBekend: Binding<Bool> {
        Binding(
            get: { invoer.bronDatum != nil },
            set: { invoer.bronDatum = $0 ? (invoer.bronDatum ?? .now) : nil })
    }

    private func samenvatting(_ gekozen: Set<NSManagedObjectID>, uit alle: [(NSManagedObjectID, String)]) -> String {
        let namen = alle.filter { gekozen.contains($0.0) }.map(\.1)
        return namen.isEmpty ? "Geen" : namen.joined(separator: ", ")
    }

    private func bewaar() {
        do {
            try invoer.bewaar(in: context, recept: recept)
            dismiss()
        } catch {
            context.rollback()
            foutmelding = error.localizedDescription
        }
    }
}

/// Meerkeuzelijst met vinkjes (categorieën of labels bij een recept).
struct Keuzelijst: View {
    struct Item: Identifiable {
        let id: NSManagedObjectID
        let naam: String
        var symbool: String?
        var toelichting: String?
    }

    let titel: String
    let items: [Item]
    @Binding var gekozen: Set<NSManagedObjectID>

    var body: some View {
        List(items) { item in
            Button {
                if gekozen.contains(item.id) {
                    gekozen.remove(item.id)
                } else {
                    gekozen.insert(item.id)
                }
            } label: {
                HStack {
                    if let symbool = item.symbool {
                        SwiftUI.Label(item.naam, systemImage: symbool)
                    } else {
                        Text(item.naam)
                    }
                    if let toelichting = item.toelichting {
                        Text(toelichting).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if gekozen.contains(item.id) {
                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(gekozen.contains(item.id) ? .isSelected : [])
        }
        .navigationTitle(titel)
    }
}
