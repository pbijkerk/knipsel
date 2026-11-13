import CoreData

// De klassen bij `Knipsel.xcdatamodeld`. Codegeneratie staat daar uit ("Manual/None"), zodat de
// eigenschappen hier leesbaar in de broncode staan. CloudKit-regels (zie docs/ontwerp.md §7): elk
// attribuut optioneel of met standaardwaarde, geen unieke constraints, elke relatie optioneel met
// inverse en ongeordend (volgorde staat in een eigen attribuut).

/// Kookboek waar een recept bij hoort (B8). In fase 1 bestaat alleen "Mijn recepten".
enum Kookboek: String, CaseIterable, Sendable {
    case mijn
    case thuis

    var naam: String {
        switch self {
        case .mijn: "Mijn recepten"
        case .thuis: "Thuis"
        }
    }
}

@objc(Recept)
final class Recept: NSManagedObject {
    @NSManaged var uuid: UUID?
    @NSManaged var titel: String?
    @NSManaged var intro: String?
    /// 0 = onbekend.
    @NSManaged var porties: Int16
    /// 0 = onbekend.
    @NSManaged var bereidingstijdMinuten: Int32
    /// 0 = onbekend.
    @NSManaged var totaleTijdMinuten: Int32
    @NSManaged var notities: String?
    @NSManaged var bronNaam: String?
    @NSManaged var bronDatum: Date?
    @NSManaged var bronPagina: String?
    /// 0 = geen beoordeling, anders 1–5.
    @NSManaged var beoordeling: Int16
    @NSManaged var laatstGekooktOp: Date?
    @NSManaged var aangemaaktOp: Date?
    @NSManaged var gewijzigdOp: Date?
    /// Ruwe waarde van `Kookboek`; standaard "mijn".
    @NSManaged var kookboek: String
    @NSManaged var categorieen: Set<Categorie>?
    @NSManaged var labels: Set<ReceptLabel>?
    @NSManaged var ingredienten: Set<Ingredient>?
    @NSManaged var stappen: Set<Stap>?
    @NSManaged var kooklog: Set<Kooklog>?

    static func verzoek() -> NSFetchRequest<Recept> { NSFetchRequest(entityName: "Recept") }

    override func awakeFromInsert() {
        super.awakeFromInsert()
        uuid = UUID()
        aangemaaktOp = .now
    }
}

@objc(Ingredient)
final class Ingredient: NSManagedObject {
    @NSManaged var volgorde: Int16
    /// Bijvoorbeeld "Voor de saus".
    @NSManaged var groep: String?
    /// De letterlijke regel zoals ingevoerd of herkend. Altijd gevuld; de velden hieronder vult de parser (fase 2).
    @NSManaged var ruweTekst: String?
    @NSManaged var hoeveelheid: NSNumber?
    @NSManaged var hoeveelheidTot: NSNumber?
    @NSManaged var eenheid: String?
    @NSManaged var naam: String?
    @NSManaged var toelichting: String?
    @NSManaged var recept: Recept?

    static func verzoek() -> NSFetchRequest<Ingredient> { NSFetchRequest(entityName: "Ingredient") }
}

@objc(Stap)
final class Stap: NSManagedObject {
    @NSManaged var volgorde: Int16
    @NSManaged var groep: String?
    @NSManaged var tekst: String?
    /// 0 = geen timer.
    @NSManaged var timerSeconden: Int32
    @NSManaged var recept: Recept?

    static func verzoek() -> NSFetchRequest<Stap> { NSFetchRequest(entityName: "Stap") }
}

@objc(Categorie)
final class Categorie: NSManagedObject {
    /// Vaste sleutel over toestellen heen; bepaalt welke van twee dubbele categorieën blijft.
    @NSManaged var uuid: UUID?
    @NSManaged var naam: String?
    /// SF Symbol.
    @NSManaged var symbool: String?
    @NSManaged var volgorde: Int16
    @NSManaged var verborgen: Bool
    @NSManaged var isStandaard: Bool
    @NSManaged var recepten: Set<Recept>?

    static func verzoek() -> NSFetchRequest<Categorie> { NSFetchRequest(entityName: "Categorie") }

    override func awakeFromInsert() {
        super.awakeFromInsert()
        uuid = UUID()
    }
}

/// Entiteit "Label". De Swift-naam is anders om botsing met SwiftUI.Label te voorkomen.
@objc(ReceptLabel)
final class ReceptLabel: NSManagedObject {
    @NSManaged var uuid: UUID?
    @NSManaged var naam: String?
    @NSManaged var recepten: Set<Recept>?

    static func verzoek() -> NSFetchRequest<ReceptLabel> { NSFetchRequest(entityName: "Label") }

    override func awakeFromInsert() {
        super.awakeFromInsert()
        uuid = UUID()
    }
}

@objc(Kooklog)
final class Kooklog: NSManagedObject {
    @NSManaged var datum: Date?
    @NSManaged var notitie: String?
    @NSManaged var recept: Recept?

    static func verzoek() -> NSFetchRequest<Kooklog> { NSFetchRequest(entityName: "Kooklog") }
}

// MARK: - Gemak voor de weergave

extension Recept {
    var titelOfStandaard: String {
        let titel = (titel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return titel.isEmpty ? "Naamloos recept" : titel
    }

    var gesorteerdeIngredienten: [Ingredient] {
        (ingredienten ?? []).sorted { $0.volgorde < $1.volgorde }
    }

    var gesorteerdeStappen: [Stap] {
        (stappen ?? []).sorted { $0.volgorde < $1.volgorde }
    }

    var gesorteerdeCategorieen: [Categorie] {
        (categorieen ?? []).sorted { ($0.volgorde, $0.naam ?? "") < ($1.volgorde, $1.naam ?? "") }
    }

    var gesorteerdeLabels: [ReceptLabel] {
        (labels ?? []).sorted { ($0.naam ?? "").localizedStandardCompare($1.naam ?? "") == .orderedAscending }
    }
}

extension Categorie {
    var naamOfStandaard: String { naam ?? "Naamloos" }
    var symboolOfStandaard: String { symbool ?? "fork.knife" }
    var aantalRecepten: Int { recepten?.count ?? 0 }
}

extension ReceptLabel {
    var naamOfStandaard: String { naam ?? "Naamloos" }
    var aantalRecepten: Int { recepten?.count ?? 0 }
}
