import SwiftUI

/// Fase 0: lege schil zodat de TestFlight-straat (Xcode Cloud) staat voordat de functies komen.
/// De opzet volgt het ontwerp: zijbalk met categorieën (iPad) / lijst (iPhone).
struct ContentView: View {
    @State private var selectie: StandaardCategorie?

    var body: some View {
        NavigationSplitView {
            List(StandaardCategorieen.alle, selection: $selectie) { categorie in
                NavigationLink(value: categorie) {
                    Label(categorie.naam, systemImage: categorie.symbool)
                }
            }
            .navigationTitle("Knipsel")
        } detail: {
            ContentUnavailableView {
                Label("Nog geen knipsels", systemImage: "scissors")
            } description: {
                Text(
                    "Hier komen je recepten uit kranten en tijdschriften. "
                        + "Deze testversie (\(Self.versie)) bevat alleen de basis."
                )
            }
        }
    }

    static var versie: String {
        let info = Bundle.main.infoDictionary
        let versie = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(versie) (\(build))"
    }
}

#Preview {
    ContentView()
}
