import SwiftUI
import UIKit

/// Teksten van het herstelscherm en de Thuis-melding als de opslag niet openging (audit v0.1, #1).
/// Puur, zodat ze zonder scherm te testen zijn.
@MainActor
enum Herstel {
    static let titel = "Je recepten konden niet worden geopend"

    /// Geruststelling voorop: er is niets weg, en Knipsel herstelt of wist niets vanzelf.
    static func uitleg(synchroniseert: Bool) -> String {
        let waar = synchroniseert ? "Ze staan in iCloud en op dit toestel" : "Ze staan nog op dit toestel"
        return
            "Je recepten zijn niet weg. \(waar), maar Knipsel kon ze deze keer niet openen. Knipsel verandert of wist niets; probeer het gewoon opnieuw."
    }

    /// Na een mislukte "Probeer opnieuw".
    static let nogSteedsNiet =
        "Het lukte nog steeds niet. Sluit Knipsel helemaal af (veeg de app omhoog in de appkiezer) en open de app opnieuw. Blijft dit scherm, kopieer dan de foutmelding en stuur die door."

    static let thuisTitel = "Thuis kon niet worden geopend"
    static let thuisUitleg =
        "Je eigen recepten werken gewoon. De recepten in Thuis van je huisgenoot zijn niet weg, maar staan nu niet op dit toestel. Sluit Knipsel helemaal af en open de app opnieuw; blijft deze melding staan, kopieer dan de foutmelding en stuur die door."

    /// Wat "Kopieer foutmelding" op het klembord zet: versie, welke store, en de fout zonder
    /// persoonsgegevens (`DeelFout.logregel`) plus de systeemtekst.
    static func kopieertekst(
        fout: any Error, store: Kookboeken.StoreSoort, versie: String = ContentView.versie,
        toestel: String = UIDevice.current.model, systeem: String = UIDevice.current.systemVersion
    ) -> String {
        let welke = store == .prive ? "Mijn recepten (privéstore)" : "Thuis van een ander (gedeelde store)"
        return """
            Knipsel \(versie), \(toestel) iOS \(systeem)
            Niet geopend: \(welke)
            Code: \(Foutmelding.code(fout))
            \(DeelFout.logregel(fout))
            \((fout as NSError).localizedDescription)
            """
    }
}

/// Wat de app toont in plaats van de bibliotheek als de privéstore niet openging. Geen automatische
/// herstelactie: alleen opnieuw proberen en de foutmelding kopiëren.
struct HerstelScherm: View {
    let opslag: Opslag
    /// Aangeroepen als de opslag na "Probeer opnieuw" wel open is.
    let geopend: () -> Void

    @State private var mislukt = false
    @State private var gekopieerd = false
    @State private var bezig = false

    init(opslag: Opslag, mislukt: Bool = false, geopend: @escaping () -> Void) {
        self.opslag = opslag
        self.geopend = geopend
        _mislukt = State(initialValue: mislukt)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .font(.system(size: 54, weight: .regular))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                    .padding(.top, 24)
                VStack(spacing: 10) {
                    Text(Herstel.titel)
                        .font(.system(.title2, design: .serif).weight(.bold))
                        .multilineTextAlignment(.center)
                    Text(Herstel.uitleg(synchroniseert: opslag.synchroniseert))
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    if mislukt {
                        Text(Herstel.nogSteedsNiet)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let fout = opslag.laadfout {
                    Text("Foutcode: \(Foutmelding.code(fout))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                VStack(spacing: 12) {
                    Button(action: probeerOpnieuw) {
                        SwiftUI.Label("Probeer opnieuw", systemImage: "arrow.clockwise")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(bezig)
                    Button(action: kopieer) {
                        SwiftUI.Label(
                            gekopieerd ? "Gekopieerd" : "Kopieer foutmelding",
                            systemImage: gekopieerd ? "checkmark" : "doc.on.doc"
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func probeerOpnieuw() {
        bezig = true
        defer { bezig = false }
        if opslag.probeerOpnieuwTeOpenen() {
            geopend()
        } else {
            mislukt = true
            gekopieerd = false
        }
    }

    private func kopieer() {
        guard let fout = opslag.laadfout else { return }
        UIPasteboard.general.string = Herstel.kopieertekst(
            fout: fout, store: opslag.laadfouten[.prive] != nil ? .prive : .gedeeld)
        gekopieerd = true
    }
}

/// De rustige melding in Instellingen › Thuis delen als alleen de gedeelde store (Thuis van een
/// ander) niet openging; de rest van de app werkt dan gewoon.
struct ThuisLaadfoutSectie: View {
    let fout: any Error
    @State private var gekopieerd = false

    var body: some View {
        Section {
            SwiftUI.Label(Herstel.thuisTitel, systemImage: "exclamationmark.icloud")
                .foregroundStyle(.orange)
            Text(Herstel.thuisUitleg)
                .font(.callout)
            Button(
                gekopieerd ? "Gekopieerd" : "Kopieer foutmelding",
                systemImage: gekopieerd ? "checkmark" : "doc.on.doc"
            ) {
                UIPasteboard.general.string = Herstel.kopieertekst(fout: fout, store: .gedeeld)
                gekopieerd = true
            }
        } footer: {
            Text("Foutcode: \(Foutmelding.code(fout))")
                .font(.caption.monospaced())
        }
    }
}
