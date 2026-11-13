import SwiftUI

/// Lettertype van de recepttekst.
enum Lettertype: String, CaseIterable, Identifiable, Sendable {
    /// New York.
    case serif
    /// SF Pro.
    case sans

    var id: String { rawValue }

    var naam: String {
        switch self {
        case .serif: "New York (serif)"
        case .sans: "SF Pro"
        }
    }

    var ontwerp: Font.Design {
        switch self {
        case .serif: .serif
        case .sans: .default
        }
    }
}

/// Leesinstellingen (Aa): lettertype en een extra vergroting bovenop de systeemtekstgrootte, plus
/// het voorlezen in de kookmodus.
enum Leesinstellingen {
    static let maximaleExtraGrootte = 4

    /// Schuift de Dynamic Type-grootte `stappen` treden op, tot en met AX5.
    static func vergroot(_ basis: DynamicTypeSize, met stappen: Int) -> DynamicTypeSize {
        let alle = DynamicTypeSize.allCases
        guard let index = alle.firstIndex(of: basis) else { return basis }
        return alle[min(alle.count - 1, max(0, index + stappen))]
    }
}

struct LeesinstellingenView: View {
    @AppStorage(AppConfiguratie.sleutelLettertype) private var lettertype: Lettertype = .serif
    @AppStorage(AppConfiguratie.sleutelExtraGrootte) private var extraGrootte = 0
    @AppStorage(AppConfiguratie.sleutelKookmodusDonker) private var kookmodusDonker = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var tekstgrootte
    @State private var voorlezer = VoorleesService(isAan: true)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $extraGrootte, in: 0...Leesinstellingen.maximaleExtraGrootte) {
                        LabeledContent("Tekstgrootte", value: extraGrootte == 0 ? "Systeem" : "+\(extraGrootte)")
                    }
                } footer: {
                    Text("Bovenop de tekstgrootte uit Instellingen › Beeldscherm en helderheid.")
                }
                Section("Lettertype") {
                    Picker("Lettertype", selection: $lettertype) {
                        ForEach(Lettertype.allCases) { soort in
                            Text(soort.naam)
                                .font(.system(.body, design: soort.ontwerp))
                                .tag(soort)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    Toggle("Altijd donker", isOn: $kookmodusDonker)
                } header: {
                    Text("Kookmodus")
                } footer: {
                    Text("Uit: de kookmodus volgt de licht/donker-instelling van je toestel.")
                }
                Section("Voorbeeld") {
                    Text("Verhit de olie en fruit de ui in 5 minuten glazig.")
                        .font(.system(.body, design: lettertype.ontwerp))
                        .dynamicTypeSize(Leesinstellingen.vergroot(tekstgrootte, met: extraGrootte))
                }
                VoorleesInstellingenSecties(voorlezer: voorlezer)
            }
            .navigationTitle("Weergave")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klaar") { dismiss() }
                }
            }
        }
    }
}
