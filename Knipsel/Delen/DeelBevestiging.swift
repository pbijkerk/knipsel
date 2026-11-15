import SwiftUI

/// Het korte scherm van de deel-extensie. Compileert ook in de app (voor schermafbeeldingen en
/// previews); gebruikt daarom alleen SwiftUI en systeemkleuren.
struct DeelBevestiging: View {
    enum Toestand: Equatable {
        case bezig
        case toegevoegd(String)
        case niets
        case mislukt(String)
    }

    let toestand: Toestand
    let klaar: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)
            symbool
                .font(.system(size: 52, weight: .regular))
                .frame(height: 64)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text(titel)
                    .font(.system(.title2, design: .serif).weight(.bold))
                    .multilineTextAlignment(.center)
                Text(uitleg)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            Button(action: klaar) {
                Text("Klaar")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(toestand == .bezig)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }

    @ViewBuilder private var symbool: some View {
        switch toestand {
        case .bezig:
            ProgressView().controlSize(.large)
        case .toegevoegd:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .niets, .mislukt:
            Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
        }
    }

    private var titel: String {
        switch toestand {
        case .bezig: "Toevoegen…"
        case .toegevoegd: "Toegevoegd aan Knipsel"
        case .niets: "Niets om toe te voegen"
        case .mislukt: "Niet gelukt"
        }
    }

    private var uitleg: String {
        switch toestand {
        case .bezig: "Even geduld."
        case .toegevoegd(let wat): "\(wat) staat in Nog te controleren. Open Knipsel om te controleren."
        case .niets:
            "Knipsel kan links, tekst, afbeeldingen en PDF's toevoegen. Hier zat geen van die dingen bij."
        case .mislukt(let reden): reden
        }
    }

    /// Kort, voor de bevestiging.
    static func omschrijving(_ bron: DeelBron) -> String {
        switch bron {
        case .link: "De link"
        case .tekst: "De tekst"
        case .afbeeldingen(let namen): namen.count == 1 ? "De afbeelding" : "De \(namen.count) afbeeldingen"
        case .pdf: "De PDF"
        }
    }
}

#Preview("Toegevoegd") {
    DeelBevestiging(toestand: .toegevoegd("De link")) {}
}

#Preview("Niets") {
    DeelBevestiging(toestand: .niets) {}
}
