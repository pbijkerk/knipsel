import AppIntents
import CoreData

/// Een ingrediënt voor Siri (#44, C): "Wat kan ik maken met prei in Knipsel". Siri kent in een zin
/// alleen entiteiten, geen vrije tekst; de suggesties zijn de ingrediënten uit je recepten, en elk
/// ander woord mag ook (de zoekvraag zelf is dan het ingrediënt).
struct IngredientEntiteit: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Ingrediënt")
    static let defaultQuery = IngredientQuery()

    /// De naam in kleine letters, zoals je hem zou intypen: "prei", "rode ui".
    let id: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(id)") }

    /// Kleine letters, zonder spaties en leestekens eromheen.
    static func schoon(_ tekst: String) -> String {
        tekst.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).lowercased()
    }
}

struct IngredientQuery: EntityStringQuery {
    /// Zoveel ingrediënten krijgt Siri als suggestie (voor de zin met het ingrediënt erin).
    static let aantalSuggesties = 40

    func entities(for identifiers: [String]) async throws -> [IngredientEntiteit] {
        identifiers.map(IngredientEntiteit.schoon).filter { !$0.isEmpty }.map(IngredientEntiteit.init(id:))
    }

    func entities(matching string: String) async throws -> [IngredientEntiteit] {
        let naam = IngredientEntiteit.schoon(string)
        guard !naam.isEmpty else { return [] }
        let bekend = await MainActor.run { WatKanIkMakenOpslag.bekendeIngredienten(in: Opslag.gedeeld.context) }
        let erbij = WatKanIkMaken.suggesties(voor: naam, bekend: bekend, gekozen: [], aantal: 6).filter { $0 != naam }
        return ([naam] + erbij).map(IngredientEntiteit.init(id:))
    }

    func suggestedEntities() async throws -> [IngredientEntiteit] {
        let bekend = await MainActor.run { WatKanIkMakenOpslag.bekendeIngredienten(in: Opslag.gedeeld.context) }
        return bekend.prefix(Self.aantalSuggesties).map(IngredientEntiteit.init(id:))
    }
}

/// "Wat kan ik maken met prei in Knipsel": Siri noemt hoeveel recepten er zijn en het snelste, en
/// Knipsel opent *Wat kan ik maken?* met die ene chip (#44, C).
struct WatKanIkMakenIntent: AppIntent {
    static let title: LocalizedStringResource = "Wat kan ik maken met…"
    static let description = IntentDescription(
        "Zoekt recepten in Knipsel met een ingrediënt dat je in huis hebt en opent Wat kan ik maken?")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Ingrediënt", requestValueDialog: "Met welk ingrediënt?")
    var ingredient: IngredientEntiteit

    static var parameterSummary: some ParameterSummary {
        Summary("Wat kan ik maken met \(\.$ingredient)")
    }

    init() {}

    init(ingredient: IngredientEntiteit) {
        self.ingredient = ingredient
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let tekst = Self.start(ingredient: ingredient.id, in: Opslag.gedeeld.context)
        return .result(dialog: "\(tekst)")
    }

    /// Zoekt in alle recepten (beide kookboeken), bewaart het ingrediënt als enige chip, zet het
    /// scherm klaar in `router` en geeft de zin voor Siri terug.
    @MainActor
    static func start(
        ingredient: String, in context: NSManagedObjectContext, router: WatKanIkMakenRouter = .gedeeld,
        defaults: UserDefaults = .standard
    ) -> String {
        let naam = IngredientEntiteit.schoon(ingredient)
        guard !naam.isEmpty else { return "Met welk ingrediënt?" }
        let resultaten = WatKanIkMaken.zoek(
            [naam], in: WatKanIkMakenOpslag.kandidaten(in: context, kookboek: nil),
            meestalInHuis: .laad(uit: defaults), sortering: .snelst)
        WatKanIkMaken.bewaar([naam], in: defaults)
        router.open(met: [naam])
        return WatKanIkMaken.siriAntwoord(ingredient: naam, resultaten: resultaten)
    }
}
