import AppIntents
import CoreData

// Siri en Opdrachten (fase 6, K10). Siri eist de appnaam in elke zin; de zinnen staan in
// `KnipselOpdrachten`. Er is geen Siri-entitlement nodig: dat is alleen voor SiriKit.

/// "Kook pompoensoep met Knipsel": opent de app en de kookmodus voor dat recept, vanaf stap 1.
struct KookReceptIntent: AppIntent {
    static let title: LocalizedStringResource = "Kook een recept"
    static let description = IntentDescription("Opent de kookmodus van Knipsel voor een recept, vanaf stap 1.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Recept", requestValueDialog: "Welk recept wil je koken?")
    var recept: ReceptEntiteit

    @Parameter(title: "Personen", requestValueDialog: "Voor hoeveel personen?")
    var porties: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("Kook \(\.$recept)") {
            \.$porties
        }
    }

    init() {}

    init(recept: ReceptEntiteit, porties: Int? = nil) {
        self.recept = recept
        self.porties = porties
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let tekst = KookReceptIntent.start(recept: recept.id, porties: porties, in: Opslag.gedeeld.context)
        return .result(dialog: "\(tekst)")
    }

    /// Zet het kookverzoek klaar in `router` en geeft de zin voor Siri terug.
    @MainActor
    static func start(
        recept id: String, porties: Int?, in context: NSManagedObjectContext, router: KookRouter = .gedeeld
    ) -> String {
        guard let recept = ReceptZoeker.recept(id: id, in: context) else {
            return "Dat recept staat niet (meer) in Knipsel."
        }
        guard !recept.gesorteerdeStappen.isEmpty else {
            return "\(recept.titelOfStandaard) heeft nog geen stappen om te koken."
        }
        router.kook(recept: recept.sleutelURL, porties: porties)
        return "Kookmodus voor \(recept.titelOfStandaard)."
    }
}

/// Spotlight: een recept openen toont het in de bibliotheek.
struct OpenReceptIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open recept"
    static let description = IntentDescription("Toont een recept in Knipsel.")

    @Parameter(title: "Recept")
    var target: ReceptEntiteit

    init() {}

    init(target: ReceptEntiteit) {
        self.target = target
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let recept = ReceptZoeker.recept(id: target.id, in: Opslag.gedeeld.context) {
            KookRouter.gedeeld.toon(recept: recept.sleutelURL)
        }
        return .result()
    }
}

/// "Volgende stap in Knipsel": op de lopende kookbeurt, zonder de app naar voren te halen.
struct VolgendeStapIntent: AppIntent {
    static let title: LocalizedStringResource = "Volgende stap"
    static let description = IntentDescription("Gaat in de kookmodus naar de volgende stap en leest die voor.")
    static let supportedModes: IntentModes = .background

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(KookOpdrachtUitvoerder.voerUit(.volgende))")
    }
}

struct VorigeStapIntent: AppIntent {
    static let title: LocalizedStringResource = "Vorige stap"
    static let description = IntentDescription("Gaat in de kookmodus een stap terug en leest die voor.")
    static let supportedModes: IntentModes = .background

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(KookOpdrachtUitvoerder.voerUit(.vorige))")
    }
}

struct HerhaalStapIntent: AppIntent {
    static let title: LocalizedStringResource = "Herhaal de stap"
    static let description = IntentDescription("Leest de huidige stap in de kookmodus nog een keer voor.")
    static let supportedModes: IntentModes = .background

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(KookOpdrachtUitvoerder.voerUit(.herhaal))")
    }
}

/// "Wat heb ik nodig in Knipsel": de ingrediënten van deze stap, of anders de hele lijst.
struct LeesIngredientenIntent: AppIntent {
    static let title: LocalizedStringResource = "Lees de ingrediënten"
    static let description = IntentDescription(
        "Leest in de kookmodus voor wat je nodig hebt voor deze stap, of anders alle ingrediënten.")
    static let supportedModes: IntentModes = .background

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(KookOpdrachtUitvoerder.voerUit(.ingredienten))")
    }
}
