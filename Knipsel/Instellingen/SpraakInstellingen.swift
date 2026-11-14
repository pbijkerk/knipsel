import SwiftUI

/// Instellingen › Spraakbediening (K8): luisteren in de kookmodus, impliciete commando's ("oké" =
/// volgende, B11), alleen met het wekwoord "Knipsel", en de lijst met wat je kunt zeggen.
struct SpraakInstellingenView: View {
    @AppStorage(AppConfiguratie.sleutelSpraakAan) private var aan = true
    @AppStorage(AppConfiguratie.sleutelSpraakImpliciet) private var impliciet = true
    @AppStorage(AppConfiguratie.sleutelSpraakWekwoord) private var alleenMetWekwoord = false

    /// Wat je kunt zeggen, voor de uitleg.
    static let commandos: [(zeg: String, doet: String)] = [
        ("\"volgende\", \"verder\"", "volgende stap"),
        ("\"vorige\", \"terug\"", "vorige stap (herstelt ook een onbedoeld \"oké\")"),
        ("\"herhaal\", \"nog een keer\", \"wat zei je?\"", "stap opnieuw voorlezen"),
        ("\"stop\", \"stil\", \"pauze\"", "direct stoppen met voorlezen"),
        ("\"lees voor\", \"ga door\"", "verder voorlezen"),
        ("\"langzamer\", \"sneller\"", "spreektempo"),
        ("\"ingrediënten\", \"wat heb ik nodig?\"", "ingrediënten van deze stap"),
        ("\"hoeveel bouillon?\"", "hoeveelheid voor jouw aantal personen"),
        ("\"stap 3\", \"stap drie\"", "naar die stap"),
        ("\"stoppen met koken\"", "kookmodus sluiten"),
    ]

    var body: some View {
        Form {
            Section {
                Toggle("Spraakbediening", isOn: $aan)
            } footer: {
                Text(
                    "In de kookmodus luistert Knipsel naar korte opdrachten, zodat je het scherm niet hoeft aan te raken. Alleen zolang de kookmodus open is, en alles op dit toestel. Met de microfoon bovenin de kookmodus zet je het ook aan of uit."
                )
            }
            Section {
                Toggle("\"Oké\" en \"klaar\" = volgende", isOn: $impliciet)
                Toggle("Alleen met \"Knipsel\" ervoor", isOn: $alleenMetWekwoord)
            } header: {
                Text("Herkennen")
            } footer: {
                Text(
                    "Zeg je \"oké\", \"klaar\", \"gedaan\" of \"ja\", dan gaat Knipsel naar de volgende stap; zeg \"terug\" als dat niet de bedoeling was. In een drukke keuken (radio, gesprek) kun je instellen dat Knipsel alleen reageert als je begint met \"Knipsel\", bijvoorbeeld \"Knipsel volgende\" (in één adem)."
                )
            }
            .disabled(!aan)
            Section {
                ForEach(Self.commandos, id: \.zeg) { commando in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(commando.zeg)
                            .font(.body.weight(.semibold))
                        Text(commando.doet)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Wat je kunt zeggen")
            } footer: {
                Text(
                    "Houd het kort: een lange zin met \"volgende\" erin (\"ik pak de volgende pan\") telt bewust niet. Elke opdracht die Knipsel begrijpt, zie je kort onderin met een zacht tikje."
                )
            }
        }
        .navigationTitle("Spraakbediening")
        .navigationBarTitleDisplayMode(.inline)
    }
}
