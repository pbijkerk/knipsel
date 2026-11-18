import CoreData
import Observation
import OSLog

/// Zet het CloudKit-schema van Knipsel klaar in de **Development**-omgeving, zodat CloudKit Console ›
/// *Deploy Schema Changes* echt iets te deployen heeft (docs/ontwerp.md §7).
///
/// Zonder dit komt een recordtype of veld pas in Development als een Debug-build er toevallig een
/// record mee exporteert; na modelversie 4 en 5 gebeurde dat niet, dus zei de Console "geen
/// wijzigingen" en misten `CD_BoodschappenItem` en `CD_Maaltijd` in Production.
///
/// `initializeCloudKitSchema(options:)` (Apple, `NSPersistentCloudKitContainer.h`): maakt voor elke
/// store mét CloudKit (hier privé én gedeeld; het schema geldt voor de hele container) "volle"
/// voorbeeldrecords met elk veld dat Core Data kan schrijven, uploadt ze en wist ze weer. Het moet ná
/// `loadPersistentStores`, blokkeert tot CloudKit klaar is (dus niet op de main thread), en werkt
/// alleen tegen Development: in een TestFlight/App Store-build (Production) mag het nooit draaien.
/// Daarom bestaat dit alleen in Debug-builds.
@MainActor
@Observable
final class CloudKitSchema {
    enum Toestand: Equatable, Sendable {
        case nietGestart
        case bezig
        case klaar
        case mislukt(String)

        var tekst: String {
            switch self {
            case .nietGestart: "Nog niet klaargezet"
            case .bezig: "Bezig…"
            case .klaar: "CloudKit-schema klaar"
            case .mislukt(let melding): "Mislukt: \(melding)"
            }
        }
    }

    /// UserDefaults-sleutel per modelversie: elke nieuwe modelversie zet het schema één keer opnieuw klaar.
    static func sleutel(modelversie: String) -> String { "cloudkitSchemaGeinitialiseerd-\(modelversie)" }

    /// De modelversie uit het datamodel (`userDefinedModelVersionIdentifier`, bijv. "5").
    static var modelversie: String {
        Opslag.model.versionIdentifiers.compactMap { $0 as? String }.sorted().last ?? "onbekend"
    }

    /// Moet het schema vanzelf klaargezet worden? Alleen als de app echt met iCloud synchroniseert,
    /// niet onder tests of in previews, en nog niet voor deze modelversie.
    nonisolated static func moetVanzelf(
        synchroniseert: Bool, onderTests: Bool, inPreview: Bool, alGedaan: Bool
    ) -> Bool {
        synchroniseert && !onderTests && !inPreview && !alGedaan
    }

    static var draaitInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    #if DEBUG
        static let gedeeld = CloudKitSchema(opslag: .gedeeld)
    #endif

    private let opslag: Opslag
    private let defaults: UserDefaults
    private(set) var toestand: Toestand

    @ObservationIgnored private let logger = Logger(subsystem: "com.peterbijkerk.knipsel", category: "CloudKitSchema")

    init(opslag: Opslag, defaults: UserDefaults = .standard) {
        self.opslag = opslag
        self.defaults = defaults
        toestand = defaults.bool(forKey: Self.sleutel(modelversie: Self.modelversie)) ? .klaar : .nietGestart
    }

    var kanStarten: Bool { opslag.synchroniseert && toestand != .bezig }

    /// Bij het starten van een Debug-build: één keer per modelversie.
    func startVanzelf() {
        guard
            Self.moetVanzelf(
                synchroniseert: opslag.synchroniseert, onderTests: Opslag.draaitOnderTests,
                inPreview: Self.draaitInPreview,
                alGedaan: defaults.bool(forKey: Self.sleutel(modelversie: Self.modelversie)))
        else { return }
        Task { await zetKlaar() }
    }

    /// De knop in Instellingen › Over Knipsel (alleen Debug), en de automatische eerste keer.
    func zetKlaar() async {
        #if DEBUG
            guard kanStarten else { return }
            toestand = .bezig
            let versie = Self.modelversie
            logger.info("CloudKit-schema klaarzetten voor modelversie \(versie, privacy: .public)…")
            let container = opslag.container
            let resultaat: Result<Void, any Error> = await Task.detached(priority: .utility) {
                Result { try container.initializeCloudKitSchema(options: []) }
            }.value
            switch resultaat {
            case .success:
                defaults.set(true, forKey: Self.sleutel(modelversie: versie))
                toestand = .klaar
                logger.info("CloudKit-schema klaar (modelversie \(versie, privacy: .public))")
            case .failure(let fout):
                toestand = .mislukt(fout.localizedDescription)
                logger.error(
                    "CloudKit-schema klaarzetten mislukt: \(DeelFout.logregel(fout), privacy: .public) \(fout.localizedDescription, privacy: .public)"
                )
            }
        #endif
    }
}
