import CoreData

/// Beheer van categorieën en labels (Instellingen › Categorieën / Labels).
enum Bibliotheekbeheer {
    enum Fout: LocalizedError, Equatable {
        case legeNaam
        case naamBestaatAl(String)

        var errorDescription: String? {
            switch self {
            case .legeNaam: "Geef een naam op."
            case .naamBestaatAl(let naam): "Er bestaat al een \u{201C}\(naam)\u{201D}."
            }
        }
    }

    /// Een korte keuzelijst SF Symbols voor categorieën: de standaardsymbolen plus wat extra's.
    static let symbolen: [String] = {
        let extra = [
            "flame", "fish", "stove", "refrigerator", "popcorn", "party.popper", "gift", "snowflake",
            "sun.max", "globe.europe.africa", "heart", "star", "cup.and.heat.waves", "tray", "bag",
        ]
        var gezien = Set<String>()
        return (StandaardCategorieen.alle.map(\.symbool) + extra).filter { gezien.insert($0).inserted }
    }()

    // MARK: Categorieën

    @discardableResult
    static func nieuweCategorie(naam: String, symbool: String, in context: NSManagedObjectContext) throws -> Categorie {
        let naam = try controleerNaam(
            naam, bestaand: try context.fetch(Categorie.verzoek()).map { ($0.objectID, $0.naam) })
        let volgorde = (try context.fetch(Categorie.verzoek()).map(\.volgorde).max() ?? -1) + 1
        let categorie = Categorie(context: context)
        categorie.naam = naam
        categorie.symbool = symbool
        categorie.volgorde = volgorde
        try context.save()
        return categorie
    }

    /// Wijzigt naam, symbool en zichtbaarheid in één keer.
    static func wijzig(_ categorie: Categorie, naam: String, symbool: String, verborgen: Bool) throws {
        guard let context = categorie.managedObjectContext else { return }
        let bestaand = try context.fetch(Categorie.verzoek()).map { ($0.objectID, $0.naam) }
        categorie.naam = try controleerNaam(naam, bestaand: bestaand, behalve: categorie.objectID)
        categorie.symbool = symbool
        categorie.verborgen = verborgen
        try context.bewaarIndienNodig()
    }

    /// Hoeveel recepten na verwijderen van deze categorie geen enkele categorie meer hebben.
    static func receptenZonderCategorieNaVerwijderen(_ categorie: Categorie) -> Int {
        (categorie.recepten ?? []).filter { ($0.categorieen ?? []).count == 1 }.count
    }

    /// Uitleg in de bevestigingsvraag bij verwijderen, met aantallen.
    static func verwijderMelding(_ categorie: Categorie) -> String {
        let aantal = categorie.aantalRecepten
        guard aantal > 0 else { return "Er staan geen recepten in deze categorie." }
        let zonder = receptenZonderCategorieNaVerwijderen(categorie)
        let basis =
            "Deze categorie heeft \(aantal == 1 ? "1 recept" : "\(aantal) recepten"). De recepten blijven bewaard."
        let zonderCategorie = "\u{201C}Zonder categorie\u{201D}"
        if zonder == 0 { return basis }
        if zonder == aantal {
            return basis + (aantal == 1 ? " Het komt onder \(zonderCategorie)." : " Ze komen onder \(zonderCategorie).")
        }
        let deel =
            zonder == 1
            ? "1 daarvan heeft geen andere categorie en komt"
            : "\(zonder) daarvan hebben geen andere categorie en komen"
        return basis + " \(deel) onder \(zonderCategorie)."
    }

    /// Verwijdert de categorie; de recepten blijven bestaan. Recepten zonder andere categorie vallen
    /// daarna onder "Zonder categorie" (een filter, geen echte categorie).
    static func verwijder(_ categorie: Categorie) throws {
        guard let context = categorie.managedObjectContext else { return }
        context.delete(categorie)
        try context.save()
    }

    /// Volgorde na slepen (`onMove`): nummert alle categorieën opnieuw van 0.
    static func verplaats(_ categorieen: [Categorie], van bron: IndexSet, naar doel: Int) throws {
        var nieuw = categorieen
        nieuw.move(fromOffsets: bron, toOffset: doel)
        for (index, categorie) in nieuw.enumerated() where categorie.volgorde != Int16(index) {
            categorie.volgorde = Int16(index)
        }
        try categorieen.first?.managedObjectContext?.bewaarIndienNodig()
    }

    // MARK: Labels

    @discardableResult
    static func nieuwLabel(naam: String, in context: NSManagedObjectContext) throws -> ReceptLabel {
        let naam = try controleerNaam(
            naam, bestaand: try context.fetch(ReceptLabel.verzoek()).map { ($0.objectID, $0.naam) })
        let label = ReceptLabel(context: context)
        label.naam = naam
        try context.save()
        return label
    }

    static func hernoem(_ label: ReceptLabel, naar naam: String) throws {
        guard let context = label.managedObjectContext else { return }
        let bestaand = try context.fetch(ReceptLabel.verzoek()).map { ($0.objectID, $0.naam) }
        label.naam = try controleerNaam(naam, bestaand: bestaand, behalve: label.objectID)
        try context.bewaarIndienNodig()
    }

    static func verwijder(_ label: ReceptLabel) throws {
        guard let context = label.managedObjectContext else { return }
        context.delete(label)
        try context.save()
    }

    // MARK: Hulp

    /// Geeft de opgeschoonde naam terug, of een fout bij een lege of al bestaande naam.
    static func controleerNaam(
        _ naam: String, bestaand: [(NSManagedObjectID, String?)], behalve: NSManagedObjectID? = nil
    ) throws -> String {
        let schoon = naam.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !schoon.isEmpty else { throw Fout.legeNaam }
        let sleutel = Inrichting.sleutel(schoon)
        if let dubbel = bestaand.first(where: { $0.0 != behalve && Inrichting.sleutel($0.1 ?? "") == sleutel }) {
            throw Fout.naamBestaatAl(dubbel.1 ?? schoon)
        }
        return schoon
    }
}
