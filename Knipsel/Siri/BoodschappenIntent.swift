import AppIntents
import CoreData

/// "Wat staat er op mijn boodschappenlijst in Knipsel": Siri somt de open items op, eerst je eigen lijst,
/// dan Thuis (#39). Draait op de achtergrond; de app hoeft niet open.
struct BoodschappenlijstIntent: AppIntent {
    static let title: LocalizedStringResource = "Wat staat er op mijn boodschappenlijst"
    static let description = IntentDescription("Somt op wat er nog open op je boodschappenlijst in Knipsel staat.")
    static let supportedModes: IntentModes = .background

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = Opslag.gedeeld.context
        let mijn = Boodschappenlijsten.secties(Boodschappenlijsten.items(in: .mijn, context: context))
        let thuis = Boodschappenlijsten.secties(Boodschappenlijsten.items(in: .thuis, context: context))
        let tekst = BoodschappenSiri.opsomming(
            mijn: mijn.flatMap { $0.items.map(\.tekstOfNaam) }, thuis: thuis.flatMap { $0.items.map(\.tekstOfNaam) })
        return .result(dialog: "\(tekst)")
    }
}

/// Wat Siri zegt; puur, zodat het te testen is.
enum BoodschappenSiri {
    /// "3 uien, 1 flespompoen en 200 ml kokosmelk".
    static func reeks(_ delen: [String]) -> String {
        guard delen.count > 1 else { return delen.first ?? "" }
        return delen.dropLast().joined(separator: ", ") + " en " + (delen.last ?? "")
    }

    static func opsomming(mijn: [String], thuis: [String]) -> String {
        switch (mijn.isEmpty, thuis.isEmpty) {
        case (true, true):
            return "Je boodschappenlijst is leeg."
        case (false, true):
            return "Op je lijst: \(reeks(mijn))."
        case (true, false):
            return "Op de Thuis-lijst: \(reeks(thuis))."
        case (false, false):
            return "Op je lijst: \(reeks(mijn)). Op de Thuis-lijst: \(reeks(thuis))."
        }
    }
}
