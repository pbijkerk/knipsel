import AppIntents
import CoreData

/// "Wat eten we vandaag in Knipsel": Siri noemt wat er vandaag in het weekmenu staat (#41), eerst je
/// eigen week, dan Thuis. Draait op de achtergrond; de app hoeft niet open.
struct VandaagIntent: AppIntent {
    static let title: LocalizedStringResource = "Wat eten we vandaag"
    static let description = IntentDescription("Zegt wat er vandaag in het weekmenu van Knipsel staat.")
    static let supportedModes: IntentModes = .background

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(Self.antwoord(in: Opslag.gedeeld.context))")
    }

    /// Het antwoord voor Siri; los van `perform`, zodat het te testen is.
    @MainActor
    static func antwoord(
        in context: NSManagedObjectContext, nu: Date = .now, kalender: Calendar = Weekplanning.kalender()
    ) -> String {
        let mijn = Weekmenu.vandaag(in: .mijn, context: context, nu: nu, kalender: kalender)
        let thuis = Weekmenu.vandaag(in: .thuis, context: context, nu: nu, kalender: kalender)
        return Weekplanning.siriVandaag(
            mijn: mijn.map(Weekplanning.korteTitel), thuis: thuis.map(Weekplanning.korteTitel))
    }
}
