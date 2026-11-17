import CoreData
import SwiftUI

/// Een item op de boodschappenlijst bewerken: naam, hoeveelheid en afdeling. Een andere afdeling
/// onthoudt Knipsel voor dit ingrediënt.
struct BoodschappenItemBewerken: View {
    @ObservedObject var item: BoodschappenItem
    private let defaults: UserDefaults

    @Environment(\.dismiss) private var dismiss
    @State private var naam: String
    @State private var hoeveelheid: String
    @State private var eenheid: String
    @State private var afdeling: Afdeling
    @State private var foutmelding: String?

    init(item: BoodschappenItem, defaults: UserDefaults = .standard) {
        self.item = item
        self.defaults = defaults
        _naam = State(initialValue: item.naam ?? item.tekstOfNaam)
        _hoeveelheid = State(initialValue: item.hoeveelheid.map { Self.getal($0.doubleValue) } ?? "")
        _eenheid = State(initialValue: item.eenheid ?? "")
        _afdeling = State(initialValue: item.afdelingWaarde)
    }

    /// 1,5 in plaats van 1.5; hele getallen zonder komma.
    static func getal(_ waarde: Double) -> String {
        waarde.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "nl_NL")))
    }

    /// "1,5", "1½", "½" of "2" → getal; leeg of onzin → `nil`.
    static func hoeveelheid(uit tekst: String) -> Double? {
        let schoon = tekst.trimmingCharacters(in: .whitespaces)
        guard !schoon.isEmpty else { return nil }
        return IngredientParser.parse("\(schoon) x").hoeveelheid
    }

    private var voorbeeld: String {
        BoodschappenLijst.lijstTekst(
            naam: naam, hoeveelheid: Self.hoeveelheid(uit: hoeveelheid),
            eenheid: eenheid.trimmingCharacters(in: .whitespaces).isEmpty ? nil : eenheid.lowercased())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Naam", text: $naam)
                        .font(.body)
                        .frame(minHeight: 44)
                    HStack(spacing: 12) {
                        TextField("Hoeveel", text: $hoeveelheid)
                            .keyboardType(.decimalPad)
                            .frame(minHeight: 44)
                        Divider()
                        TextField("Eenheid (g, ml, bos)", text: $eenheid)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .frame(minHeight: 44)
                    }
                } footer: {
                    Text("Op de lijst: \(voorbeeld)")
                }
                Section {
                    Picker("Afdeling", selection: $afdeling) {
                        ForEach(Afdeling.allCases) { afdeling in
                            SwiftUI.Label(afdeling.naam, systemImage: afdeling.symbool).tag(afdeling)
                        }
                    }
                    .frame(minHeight: 44)
                } footer: {
                    Text("Knipsel onthoudt de afdeling voor dit ingrediënt, ook de volgende keer.")
                }
                if let herkomst = item.herkomst, !herkomst.isEmpty {
                    Section("Uit") {
                        Text(herkomst).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button("Verwijder van de lijst", systemImage: "trash", role: .destructive) {
                        try? Boodschappenlijsten.verwijder(item)
                        dismiss()
                    }
                    .frame(minHeight: 44)
                }
            }
            .navigationTitle("Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bewaar", systemImage: "checkmark", action: bewaar)
                        .disabled(naam.trimmingCharacters(in: .whitespaces).isEmpty)
                }
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

    private func bewaar() {
        var geheugen = AfdelingGeheugen.laad(uit: defaults)
        do {
            try Boodschappenlijsten.wijzig(
                item, naam: naam, hoeveelheid: Self.hoeveelheid(uit: hoeveelheid), eenheid: eenheid,
                afdeling: afdeling, geheugen: &geheugen, defaults: defaults)
            dismiss()
        } catch {
            foutmelding = "Bewaren lukte niet: \(error.localizedDescription)"
        }
    }
}
