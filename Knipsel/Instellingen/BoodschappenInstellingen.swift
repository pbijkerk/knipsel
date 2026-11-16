import SwiftUI

/// Instellingen › Boodschappen: wat je meestal in huis hebt (L2). Die woorden staan op de
/// boodschappenlijst standaard uitgevinkt.
struct BoodschappenInstellingen: View {
    private let defaults: UserDefaults
    @State private var meestal: MeestalInHuis
    @State private var nieuw = ""

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        _meestal = State(initialValue: MeestalInHuis.laad(uit: defaults))
    }

    var body: some View {
        List {
            Section {
                ForEach(meestal.woorden, id: \.self) { woord in
                    Text(woord)
                }
                .onDelete { plekken in
                    for woord in plekken.map({ meestal.woorden[$0] }) { meestal.verwijder(woord) }
                    meestal.bewaar(in: defaults)
                }
                HStack {
                    TextField("Bijvoorbeeld boter", text: $nieuw)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(voegToe)
                    Button("Voeg toe", action: voegToe)
                        .disabled(nieuw.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Meestal in huis")
            } footer: {
                Text(
                    "Deze ingrediënten staan op je boodschappenlijst standaard uitgevinkt, onderaan bij Meestal in huis. Een woord telt ook in samenstellingen: olie geldt ook voor sesamolie. Veeg naar links om te verwijderen. Vink je iets vaak uit, dan stelt Knipsel voor het hier toe te voegen."
                )
            }
            Section {
                Button("Zet de standaardlijst terug") {
                    meestal.herstelStandaard()
                    meestal.bewaar(in: defaults)
                }
                .disabled(meestal.woorden == MeestalInHuis.standaardWoorden)
            } footer: {
                Text(
                    "Knipsel zet je boodschappen in Herinneringen, in de lijst Boodschappen, of je deelt ze als tekst. Alleen wat je zelf aanvinkt gaat erheen."
                )
            }
        }
        .navigationTitle("Boodschappen")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func voegToe() {
        meestal.voegToe(nieuw)
        meestal.bewaar(in: defaults)
        nieuw = ""
    }
}
