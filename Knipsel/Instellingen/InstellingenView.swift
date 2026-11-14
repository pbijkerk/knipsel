import CoreData
import SwiftUI

struct InstellingenView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Bibliotheek") {
                    NavigationLink {
                        CategorieBeheer()
                    } label: {
                        SwiftUI.Label("Categorieën", systemImage: "square.grid.2x2")
                    }
                    NavigationLink {
                        LabelBeheer()
                    } label: {
                        SwiftUI.Label("Labels", systemImage: "tag")
                    }
                }
                Section("Weergave") {
                    NavigationLink {
                        LeesinstellingenView()
                    } label: {
                        SwiftUI.Label("Lettertype en tekstgrootte", systemImage: "textformat.size")
                    }
                    NavigationLink {
                        VoorleesInstellingenView()
                    } label: {
                        SwiftUI.Label("Voorlezen", systemImage: "speaker.wave.2")
                    }
                }
                ClaudeInstellingen()
                Section {
                    LabeledContent("Versie", value: ContentView.versie)
                    LabeledContent("iCloud-sync", value: Opslag.gedeeld.synchroniseert ? "Aan" : "Uit")
                } header: {
                    Text("Over Knipsel")
                } footer: {
                    Text(
                        "Met iCloud staan je recepten op al je toestellen. Is iCloud-sync uit (geen iCloud-account), dan staan ze alleen op dit toestel."
                    )
                }
            }
            .navigationTitle("Instellingen")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klaar") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Indelen met Claude

/// Eigen Anthropic-sleutel invullen of verwijderen (B10). De sleutel staat in de Keychain van dit
/// toestel; zonder sleutel deelt Knipsel in met regels op het toestel.
struct ClaudeInstellingen: View {
    @State private var heeftSleutel = KeychainService.load(forKey: AppConfiguratie.sleutelClaude) != nil
    @State private var invoer = ""
    @State private var foutmelding: String?

    var body: some View {
        Section {
            if heeftSleutel {
                LabeledContent("API-sleutel", value: "Ingesteld")
                Button("Verwijder sleutel", role: .destructive) {
                    KeychainService.delete(forKey: AppConfiguratie.sleutelClaude)
                    heeftSleutel = false
                }
            } else {
                SecureField("API-sleutel (sk-ant-…)", text: $invoer)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Bewaar sleutel", action: bewaar)
                    .disabled(invoer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            Text("Indelen met Claude")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text(
                    "Optioneel. Met een eigen sleutel van Anthropic deelt Claude het recept in (titel, ingrediënten, bereiding). Alleen de herkende tekst gaat naar Anthropic, nooit de foto. Zonder sleutel of zonder internet deelt Knipsel in op dit toestel."
                )
                if let foutmelding {
                    Text(foutmelding).foregroundStyle(.red)
                }
                Link("Privacybeleid", destination: AppConfiguratie.privacyURL)
            }
        }
    }

    private func bewaar() {
        let sleutel = invoer.trimmingCharacters(in: .whitespacesAndNewlines)
        if KeychainService.save(sleutel, forKey: AppConfiguratie.sleutelClaude) {
            invoer = ""
            foutmelding = nil
            heeftSleutel = true
        } else {
            foutmelding = "De sleutel kon niet worden bewaard."
        }
    }
}

// MARK: - Categorieën

/// Hernoemen, symbool kiezen, slepen, verbergen, toevoegen en verwijderen (met bevestiging).
struct CategorieBeheer: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "volgorde", ascending: true)])
    private var categorieen: FetchedResults<Categorie>

    @State private var bewerk: Categorie?
    @State private var toonNieuw = false
    @State private var teVerwijderen: Categorie?
    @State private var foutmelding: String?

    var body: some View {
        List {
            Section {
                ForEach(categorieen, id: \.objectID) { categorie in
                    Button {
                        bewerk = categorie
                    } label: {
                        CategorieRij(categorie: categorie)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            teVerwijderen = categorie
                        } label: {
                            SwiftUI.Label("Verwijder", systemImage: "trash")
                        }
                        Button {
                            voerUit {
                                try Bibliotheekbeheer.wijzig(
                                    categorie, naam: categorie.naamOfStandaard, symbool: categorie.symboolOfStandaard,
                                    verborgen: !categorie.verborgen)
                            }
                        } label: {
                            SwiftUI.Label(
                                categorie.verborgen ? "Toon" : "Verberg",
                                systemImage: categorie.verborgen ? "eye" : "eye.slash")
                        }
                        .tint(.gray)
                    }
                }
                .onMove { bron, doel in
                    voerUit { try Bibliotheekbeheer.verplaats(Array(categorieen), van: bron, naar: doel) }
                }
            } footer: {
                Text(
                    "Sleep om de volgorde te wijzigen. Verborgen categorieën blijven bestaan, maar staan niet in de bibliotheek."
                )
            }
            Section {
                Button("Nieuwe categorie", systemImage: "plus") { toonNieuw = true }
            }
        }
        .navigationTitle("Categorieën")
        .toolbar { EditButton() }
        .sheet(isPresented: Binding(get: { bewerk != nil }, set: { if !$0 { bewerk = nil } })) {
            if let categorie = bewerk {
                CategorieBewerken(categorie: categorie) {
                    // Eerst het blad laten sluiten; twee presentaties tegelijk slaat SwiftUI over.
                    Task {
                        try? await Task.sleep(for: .milliseconds(450))
                        teVerwijderen = categorie
                    }
                }
            }
        }
        .sheet(isPresented: $toonNieuw) { CategorieBewerken(categorie: nil) }
        .confirmationDialog(
            "Categorie verwijderen?",
            isPresented: Binding(get: { teVerwijderen != nil }, set: { if !$0 { teVerwijderen = nil } }),
            titleVisibility: .visible,
            presenting: teVerwijderen
        ) { categorie in
            Button("Verwijder \u{201C}\(categorie.naamOfStandaard)\u{201D}", role: .destructive) {
                voerUit { try Bibliotheekbeheer.verwijder(categorie) }
            }
        } message: { categorie in
            Text(Bibliotheekbeheer.verwijderMelding(categorie))
        }
        .alert(
            "Er ging iets mis", isPresented: Binding(get: { foutmelding != nil }, set: { if !$0 { foutmelding = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(foutmelding ?? "")
        }
    }

    private func voerUit(_ actie: () throws -> Void) {
        do {
            try actie()
        } catch {
            context.rollback()
            foutmelding = error.localizedDescription
        }
    }
}

private struct CategorieRij: View {
    @ObservedObject var categorie: Categorie

    var body: some View {
        HStack {
            SwiftUI.Label(categorie.naamOfStandaard, systemImage: categorie.symboolOfStandaard)
                .foregroundStyle(categorie.verborgen ? .secondary : .primary)
            if categorie.verborgen {
                Text("verborgen").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Text(categorie.aantalRecepten, format: .number).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

/// Naam, symbool en zichtbaarheid van een (nieuwe) categorie.
struct CategorieBewerken: View {
    let categorie: Categorie?
    var vraagVerwijderen: (() -> Void)?

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var naam: String
    @State private var symbool: String
    @State private var verborgen: Bool
    @State private var foutmelding: String?
    @ScaledMetric private var symboolMaat: CGFloat = 48

    init(categorie: Categorie?, vraagVerwijderen: (() -> Void)? = nil) {
        self.categorie = categorie
        self.vraagVerwijderen = vraagVerwijderen
        _naam = State(initialValue: categorie?.naam ?? "")
        _symbool = State(initialValue: categorie?.symbool ?? Bibliotheekbeheer.symbolen[0])
        _verborgen = State(initialValue: categorie?.verborgen ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Naam", text: $naam)
                } footer: {
                    if let foutmelding { Text(foutmelding).foregroundStyle(.red) }
                }
                Section("Symbool") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: symboolMaat), spacing: 8)], spacing: 8) {
                        ForEach(Bibliotheekbeheer.symbolen, id: \.self) { naam in
                            Button {
                                symbool = naam
                            } label: {
                                Image(systemName: naam)
                                    .font(.title3)
                                    .frame(width: symboolMaat, height: symboolMaat)
                                    .background(
                                        symbool == naam ? Color.accentColor.opacity(0.2) : Color(.secondarySystemFill),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(symbool == naam ? Color.accentColor : .clear, lineWidth: 2)
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(naam)
                            .accessibilityAddTraits(symbool == naam ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Toggle("Verberg in de bibliotheek", isOn: $verborgen)
                }
                if let categorie, let vraagVerwijderen {
                    Section {
                        Button("Verwijder categorie", role: .destructive) {
                            dismiss()
                            vraagVerwijderen()
                        }
                    } footer: {
                        Text(categorie.aantalRecepten == 1 ? "1 recept" : "\(categorie.aantalRecepten) recepten")
                    }
                }
            }
            .navigationTitle(categorie == nil ? "Nieuwe categorie" : "Categorie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bewaar", action: bewaar)
                        .disabled(naam.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func bewaar() {
        do {
            if let categorie {
                try Bibliotheekbeheer.wijzig(categorie, naam: naam, symbool: symbool, verborgen: verborgen)
            } else {
                let nieuw = try Bibliotheekbeheer.nieuweCategorie(naam: naam, symbool: symbool, in: context)
                if verborgen {
                    nieuw.verborgen = true
                    try context.save()
                }
            }
            dismiss()
        } catch {
            context.rollback()
            foutmelding = error.localizedDescription
        }
    }
}

// MARK: - Labels

struct LabelBeheer: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(
            key: "naam", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
    ])
    private var labels: FetchedResults<ReceptLabel>

    /// `nil` = nieuw label; anders het label dat hernoemd wordt.
    @State private var bewerkt: ReceptLabel?
    @State private var toonNaamveld = false
    @State private var naam = ""
    @State private var teVerwijderen: ReceptLabel?
    @State private var foutmelding: String?

    var body: some View {
        List {
            Section {
                ForEach(labels, id: \.objectID) { label in
                    Button {
                        bewerkt = label
                        naam = label.naam ?? ""
                        toonNaamveld = true
                    } label: {
                        HStack {
                            SwiftUI.Label(label.naamOfStandaard, systemImage: "tag")
                            Spacer()
                            Text(label.aantalRecepten, format: .number).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) {
                            teVerwijderen = label
                        } label: {
                            SwiftUI.Label("Verwijder", systemImage: "trash")
                        }
                    }
                }
            } footer: {
                Text(
                    "Labels zijn kenmerken naast de categorie, zoals vegetarisch of snel. Een recept kan er meerdere hebben."
                )
            }
            Section {
                Button("Nieuw label", systemImage: "plus") {
                    bewerkt = nil
                    naam = ""
                    toonNaamveld = true
                }
            }
        }
        .navigationTitle("Labels")
        .alert(bewerkt == nil ? "Nieuw label" : "Label hernoemen", isPresented: $toonNaamveld) {
            TextField("Naam", text: $naam)
            Button("Bewaar") { bewaar() }
            Button("Annuleer", role: .cancel) {}
        }
        .confirmationDialog(
            "Label verwijderen?",
            isPresented: Binding(get: { teVerwijderen != nil }, set: { if !$0 { teVerwijderen = nil } }),
            titleVisibility: .visible,
            presenting: teVerwijderen
        ) { label in
            Button("Verwijder \u{201C}\(label.naamOfStandaard)\u{201D}", role: .destructive) {
                voerUit { try Bibliotheekbeheer.verwijder(label) }
            }
        } message: { label in
            Text(
                label.aantalRecepten == 0
                    ? "Geen enkel recept heeft dit label."
                    : "Het label verdwijnt bij \(label.aantalRecepten == 1 ? "1 recept" : "\(label.aantalRecepten) recepten"); de recepten blijven bewaard."
            )
        }
        .alert(
            "Er ging iets mis", isPresented: Binding(get: { foutmelding != nil }, set: { if !$0 { foutmelding = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(foutmelding ?? "")
        }
    }

    private func bewaar() {
        voerUit {
            if let bewerkt {
                try Bibliotheekbeheer.hernoem(bewerkt, naar: naam)
            } else {
                try Bibliotheekbeheer.nieuwLabel(naam: naam, in: context)
            }
        }
    }

    private func voerUit(_ actie: () throws -> Void) {
        do {
            try actie()
        } catch {
            context.rollback()
            foutmelding = error.localizedDescription
        }
    }
}
