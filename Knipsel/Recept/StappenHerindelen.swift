import Observation
import SwiftUI

/// "Stappen opnieuw indelen" bij een bestaand recept (#17). Alleen de stappen; de tekst blijft
/// letterlijk. Eerst meteen de indeling op het toestel (`StapSplitser`); met een Claude-sleutel
/// daarna Claude, als zijn indeling de letterlijkheidscontrole haalt. Er verandert pas iets bij
/// "Bewaar"; "Annuleer" laat het formulier zoals het was.
@MainActor
@Observable
final class StappenHerindeling {
    /// De stappen zoals ze nu zijn.
    let voor: [String]
    /// Het voorstel.
    private(set) var na: [String]
    private(set) var bron = Indeling.Bron.regels
    private(set) var isBezig = false
    private let tekst: String

    init(stappenTekst: String) {
        tekst = stappenTekst
        voor = ReceptInvoer.regels(stappenTekst)
        na = StapSplitser.stappen(in: stappenTekst)
    }

    var isGewijzigd: Bool { na != voor }

    /// Vraagt Claude om de beginwoorden van elke stap en knipt de letterlijke tekst daarop. Lukt dat
    /// niet (geen sleutel, geen netwerk, beginwoorden die niet kloppen), dan blijft het voorstel van
    /// de regels staan.
    func deelInMetClaude(sleutel: String?, sessie: URLSession = .shared) async {
        guard let sleutel, !sleutel.isEmpty, !voor.isEmpty else { return }
        isBezig = true
        defer { isBezig = false }
        guard
            let beginnen = try? await ClaudeIndeler.stapBeginnen(
                voor: voor.joined(separator: "\n"), sleutel: sleutel, sessie: sessie),
            let geknipt = StapSplitser.knip(tekst, opBeginnen: beginnen)
        else { return }
        na = geknipt
        bron = .claude
    }

    /// "Bewaar": de nieuwe stappen in het formulier, één per alinea.
    func pasToe(op invoer: inout ReceptInvoer) {
        invoer.stappenTekst = na.joined(separator: "\n\n")
    }
}

/// Het voorbeeld vooraf: de stappen nu en het voorstel, genummerd, met Bewaar of Annuleer.
struct StappenHerindelenScherm: View {
    @State var model: StappenHerindeling
    var sleutel: String?
    let bewaar: (StappenHerindeling) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var breedte

    var body: some View {
        NavigationStack {
            Group {
                if breedte == .regular {
                    HStack(spacing: 0) {
                        lijst(nieuw: false)
                        Divider()
                        lijst(nieuw: true)
                    }
                } else {
                    List {
                        status
                        sectie(nieuw: true)
                        sectie(nieuw: false)
                    }
                }
            }
            .navigationTitle("Nieuwe indeling")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleer") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bewaar") {
                        bewaar(model)
                        dismiss()
                    }
                    .disabled(!model.isGewijzigd || model.isBezig)
                }
            }
            .task { await model.deelInMetClaude(sleutel: sleutel) }
        }
    }

    private func lijst(nieuw: Bool) -> some View {
        List {
            if nieuw { status }
            sectie(nieuw: nieuw)
        }
    }

    private var status: some View {
        Section {
            if model.isBezig {
                SwiftUI.Label {
                    Text("Claude deelt in…")
                } icon: {
                    ProgressView()
                }
            } else {
                SwiftUI.Label(model.bron.omschrijving, systemImage: model.bron == .claude ? "sparkles" : "iphone")
            }
            if !model.isGewijzigd && !model.isBezig {
                Text("De indeling blijft hetzelfde.").foregroundStyle(.secondary)
            }
        } footer: {
            Text("De tekst blijft woord voor woord gelijk; alleen de indeling in stappen verandert.")
        }
    }

    private func sectie(nieuw: Bool) -> some View {
        let stappen = nieuw ? model.na : model.voor
        let titel = nieuw ? "Nieuw" : "Nu"
        return Section {
            ForEach(Array(stappen.enumerated()), id: \.offset) { index, stap in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(index + 1, format: .number)
                        .font(.headline)
                        .foregroundStyle(nieuw ? Color.accentColor : .secondary)
                        .frame(minWidth: 18, alignment: .trailing)
                    Text(stap)
                        .foregroundStyle(nieuw ? .primary : .secondary)
                }
            }
        } header: {
            Text("\(titel) · \(stappen.count == 1 ? "1 stap" : "\(stappen.count) stappen")")
        }
    }
}
