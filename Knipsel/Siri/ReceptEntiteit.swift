import AppIntents
import CoreData
import CoreSpotlight

/// Een recept voor Siri, Opdrachten en Spotlight (fase 6). Alleen titel en categorie: meer is niet
/// nodig om een recept te kiezen, en meer komt er niet in de Spotlight-index (docs/privacy.md).
struct ReceptEntiteit: IndexedEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Recept", numericFormat: "\(placeholder: .int) recepten")
    static let defaultQuery = ReceptQuery()

    /// De `uuid` van het recept: vast over toestellen en iCloud heen (anders dan een objectID).
    let id: String
    let titel: String
    let categorie: String?
    let symbool: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(titel)", subtitle: categorie.map { "\($0)" },
            image: DisplayRepresentation.Image(systemName: symbool))
    }
}

extension ReceptEntiteit {
    /// `nil` voor een recept zonder `uuid` (komt niet voor: `awakeFromInsert` zet hem).
    @MainActor
    init?(recept: Recept) {
        guard let uuid = recept.uuid else { return nil }
        let eerste = recept.gesorteerdeCategorieen.first
        self.init(
            id: uuid.uuidString, titel: recept.titelOfStandaard, categorie: eerste?.naam,
            symbool: eerste?.symboolOfStandaard ?? "fork.knife")
    }
}

/// Zoeken van recepten voor Siri en Opdrachten: op titel én ingrediënt (dezelfde regels als de
/// bibliotheek, `ReceptFilter`), en suggesties (laatst gekookt of nieuw).
struct ReceptQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ReceptEntiteit] {
        try await MainActor.run { try ReceptZoeker.entiteiten(voor: identifiers, in: Opslag.gedeeld.context) }
    }

    func entities(matching string: String) async throws -> [ReceptEntiteit] {
        try await MainActor.run { try ReceptZoeker.zoek(string, in: Opslag.gedeeld.context) }
    }

    func suggestedEntities() async throws -> [ReceptEntiteit] {
        try await MainActor.run { try ReceptZoeker.suggesties(in: Opslag.gedeeld.context) }
    }
}

/// De Core Data-kant van `ReceptQuery`, los te testen met een opslag in het geheugen.
@MainActor
enum ReceptZoeker {
    static let aantalSuggesties = 10

    static func recept(id: String, in context: NSManagedObjectContext) -> Recept? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        let verzoek = Recept.verzoek()
        verzoek.predicate = NSPredicate(format: "uuid == %@", uuid as CVarArg)
        verzoek.fetchLimit = 1
        return try? context.fetch(verzoek).first
    }

    static func entiteiten(voor ids: [String], in context: NSManagedObjectContext) throws -> [ReceptEntiteit] {
        let uuids = ids.compactMap(UUID.init(uuidString:))
        guard !uuids.isEmpty else { return [] }
        let verzoek = Recept.verzoek()
        verzoek.predicate = NSPredicate(format: "uuid IN %@", uuids)
        let gevonden = Dictionary(
            try context.fetch(verzoek).compactMap(ReceptEntiteit.init(recept:)).map { ($0.id, $0) },
            uniquingKeysWith: { eerste, _ in eerste })
        // In de gevraagde volgorde.
        return ids.compactMap { gevonden[$0] }
    }

    static func zoek(_ term: String, in context: NSManagedObjectContext) throws -> [ReceptEntiteit] {
        try context.fetch(ReceptFilter(zoekterm: term).verzoek()).compactMap(ReceptEntiteit.init(recept:))
    }

    static func alle(in context: NSManagedObjectContext) throws -> [ReceptEntiteit] {
        try context.fetch(ReceptFilter().verzoek()).compactMap(ReceptEntiteit.init(recept:))
    }

    /// Recepten met stappen, het laatst gekookte of nieuwste eerst.
    static func suggesties(in context: NSManagedObjectContext, aantal: Int = aantalSuggesties) throws
        -> [ReceptEntiteit]
    {
        let recepten = try context.fetch(Recept.verzoek()).filter { !($0.stappen ?? []).isEmpty }
        return
            recepten
            .map { (recept: $0, moment: suggestieMoment(gekookt: $0.laatstGekooktOp, aangemaakt: $0.aangemaaktOp)) }
            .sorted {
                $0.moment != $1.moment ? $0.moment > $1.moment : $0.recept.titelOfStandaard < $1.recept.titelOfStandaard
            }
            .prefix(aantal)
            .compactMap { ReceptEntiteit(recept: $0.recept) }
    }

    /// Het recentste van laatst gekookt en aangemaakt; zonder datum helemaal achteraan.
    nonisolated static func suggestieMoment(gekookt: Date?, aangemaakt: Date?) -> Date {
        [gekookt, aangemaakt].compactMap { $0 }.max() ?? .distantPast
    }
}
