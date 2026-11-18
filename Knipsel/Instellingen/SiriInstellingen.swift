import AppIntents
import SwiftUI

/// Instellingen › Siri en Opdrachten (fase 6, K10): wat je tegen Siri kunt zeggen, een link naar
/// Opdrachten, en de proef met AirPods en Apple Watch (S3, standaard uit).
struct SiriInstellingen: View {
    @AppStorage(AppConfiguratie.sleutelAirPodsProef) private var airPodsProef = false

    /// Wat je tegen Siri kunt zeggen. Siri wil de appnaam in elke zin.
    static let zinnen: [(zeg: String, doet: String)] = [
        ("\"Kook pompoensoep met Knipsel\"", "opent de kookmodus voor dat recept"),
        ("\"Volgende stap in Knipsel\"", "volgende stap, ook met de app op de achtergrond"),
        ("\"Vorige stap in Knipsel\"", "een stap terug"),
        ("\"Herhaal de stap in Knipsel\"", "stap opnieuw voorlezen"),
        ("\"Wat heb ik nodig in Knipsel\"", "ingrediënten van deze stap"),
        ("\"Wat kan ik maken met prei in Knipsel\"", "recepten met wat je in huis hebt"),
    ]

    var body: some View {
        Section {
            SiriTipView(intent: VolgendeStapIntent())
                .siriTipViewStyle(.automatic)
            ForEach(Self.zinnen, id: \.zeg) { zin in
                VStack(alignment: .leading, spacing: 2) {
                    Text(zin.zeg)
                        .font(.body.weight(.semibold))
                    Text(zin.doet)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            ShortcutsLink()
                .shortcutsLinkStyle(.automaticOutline)
                .frame(maxWidth: .infinity)
        } header: {
            Text("Siri en Opdrachten")
        } footer: {
            Text(
                "Zeg \"Hé Siri\" en dan de zin; \"Knipsel\" hoort er altijd in. De stappen werken alleen als de kookmodus open is, ook als Knipsel op de achtergrond staat of het scherm op slot is. Je recepten zijn ook te vinden in Spotlight (alleen titel en categorie, op dit toestel)."
            )
        }
        Section {
            Toggle(isOn: $airPodsProef) {
                SwiftUI.Label("Bediening met AirPods en Apple Watch (proef)", systemImage: "airpods")
            }
        } footer: {
            Text(
                "Een proef: tijdens het koken staat het recept onder Nu speelt. Eén keer op het steeltje van je AirPods drukken leest de stap voor of stopt, twee keer is de volgende stap, drie keer de vorige; op de Apple Watch en het vergrendelscherm werken dezelfde knoppen. Muziek pauzeert dan tijdens het voorlezen in plaats van zachter te gaan. Geldt vanaf de volgende keer dat je de kookmodus opent."
            )
        }
    }
}
