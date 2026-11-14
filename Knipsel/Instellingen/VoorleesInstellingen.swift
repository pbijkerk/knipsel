import SwiftUI

/// Sectie "Voorlezen" (K9): standaard aan, ingrediënten meelezen, stem en tempo met een proefzin.
/// Staat in Instellingen en onder Weergave (Aa).
struct VoorleesInstellingenSecties: View {
    @AppStorage(AppConfiguratie.sleutelVoorlezenAan) private var standaardAan = true
    @AppStorage(AppConfiguratie.sleutelIngredientenMeelezen) private var ingredientenMeelezen = false
    @AppStorage(AppConfiguratie.sleutelVoorleesStem) private var stem = ""
    @AppStorage(AppConfiguratie.sleutelVoorleesTempo) private var tempo = Voorleestempo.standaard

    /// Speelt de proefzin; in renders een nep-spreker.
    let voorlezer: VoorleesService
    var stemmen: [Stem] = Stemkeuze.geinstalleerd()

    static let proefzin = "Verhit 2 el olijfolie en fruit de ui en ½ tl kerriepoeder ca. 5 min. op middelhoog vuur."

    private var gekozenStem: Stem? { Stemkeuze.kies(uit: stemmen, voorkeur: stem.isEmpty ? nil : stem) }

    var body: some View {
        Section {
            Toggle("Voorlezen standaard aan", isOn: $standaardAan)
            Toggle("Ingrediënten van de stap meelezen", isOn: $ingredientenMeelezen)
        } header: {
            Text("Voorlezen")
        } footer: {
            Text(
                "In de kookmodus leest Knipsel elke stap voor en wacht dan tot jij verder gaat. Met de luidspreker bovenin zet je het aan of uit; dat onthoudt Knipsel."
            )
        }
        Section {
            Picker("Stem", selection: $stem) {
                Text(stemmen.isEmpty ? "Standaard" : "Automatisch (\(stemmen[0].naam))").tag("")
                ForEach(stemmen) { stem in
                    Text(stem.omschrijving).tag(stem.id)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Tempo", value: Voorleestempo.label(tempo))
                Slider(value: $tempo, in: Voorleestempo.minimum...Voorleestempo.maximum, step: 0.1) {
                    Text("Tempo")
                } minimumValueLabel: {
                    Image(systemName: "tortoise").accessibilityLabel("Langzamer")
                } maximumValueLabel: {
                    Image(systemName: "hare").accessibilityLabel("Sneller")
                }
                .accessibilityValue(Voorleestempo.label(tempo))
            }
            Button {
                if voorlezer.spreekt {
                    voorlezer.stop()
                } else {
                    voorlezer.spreek(
                        Uitspraakregels.uitspreekbaar(Self.proefzin),
                        met: Voorleesinstellingen(stem: gekozenStem?.id, tempo: tempo))
                }
            } label: {
                SwiftUI.Label(
                    voorlezer.spreekt ? "Stop" : "Probeer",
                    systemImage: voorlezer.spreekt ? "stop.fill" : "play.fill")
            }
        } header: {
            Text("Stem en tempo")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if !Stemkeuze.heeftVerbeterdeStem(stemmen) {
                    Text("Op dit toestel staat alleen een standaardstem; een verbeterde stem klinkt veel natuurlijker.")
                        .bold()
                }
                Text(
                    "Een verbeterde stem download je gratis via Instellingen › Toegankelijkheid › Gesproken materiaal › Stemmen › Nederlands. Kies daar bijvoorbeeld Xander of Claire (verbeterd) en kom dan hier terug."
                )
            }
        }
        .onDisappear { voorlezer.stop() }
    }
}

/// Eigen scherm voor het voorlezen, vanuit Instellingen.
struct VoorleesInstellingenView: View {
    @State private var voorlezer = VoorleesService(isAan: true)

    var body: some View {
        Form {
            VoorleesInstellingenSecties(voorlezer: voorlezer)
        }
        .navigationTitle("Voorlezen")
        .navigationBarTitleDisplayMode(.inline)
    }
}
