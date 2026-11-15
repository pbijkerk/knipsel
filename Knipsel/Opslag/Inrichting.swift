import CoreData

/// Standaardcategorieën en -labels aanmaken en dubbelen opruimen.
///
/// Twee toestellen die voor het eerst starten, zaaien elk de standaardset; na sync via iCloud staan
/// alle categorieën dan dubbel. CloudKit kent geen unieke constraints, dus ontdubbelt Knipsel zelf op
/// naam. Welke blijft, moet op elk toestel hetzelfde uitvallen (anders verwijdert toestel A de ene
/// en toestel B de andere): dat is die met de laagste `uuid`.
///
/// Fase 8: alleen "Mijn recepten" krijgt de standaardset. Thuis krijgt alleen de categorieën en
/// labels die zijn recepten nodig hebben (`Kookboeken`). Ontdubbelen gebeurt per store en per
/// kookboek: een privé-"Soepen" en een Thuis-"Soepen" horen allebei te bestaan, maar twee
/// huisgenoten die tegelijk een Thuis-"Soepen" aanmaken, krijgen er na sync één.
enum Inrichting {
    /// Vergelijkingssleutel voor namen: zonder spaties eromheen, hoofdletters en accenten.
    static func sleutel(_ naam: String) -> String {
        naam.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "nl_NL"))
    }

    /// Maakt de ontbrekende standaardcategorieën en -labels aan in "Mijn recepten" (de privéstore).
    /// Idempotent: een naam die daar al bestaat (ongeacht hoofdletters) wordt overgeslagen.
    static func zaaiStandaard(in context: NSManagedObjectContext) throws {
        let prive = Kookboeken.store(.prive, in: context.persistentStoreCoordinator)
        func mijn<T: NSManagedObject>(_ verzoek: NSFetchRequest<T>) -> NSFetchRequest<T> {
            verzoek.predicate = NSPredicate(format: "kookboek == %@", Kookboek.mijn.rawValue)
            if let prive { verzoek.affectedStores = [prive] }
            return verzoek
        }
        let bestaandeCategorieen = Set(try context.fetch(mijn(Categorie.verzoek())).compactMap { $0.naam.map(sleutel) })
        for (index, standaard) in StandaardCategorieen.alle.enumerated()
        where !bestaandeCategorieen.contains(sleutel(standaard.naam)) {
            let categorie = Categorie(context: context)
            categorie.naam = standaard.naam
            categorie.symbool = standaard.symbool
            categorie.volgorde = Int16(index)
            categorie.isStandaard = true
            if let prive { context.assign(categorie, to: prive) }
        }

        let bestaandeLabels = Set(try context.fetch(mijn(ReceptLabel.verzoek())).compactMap { $0.naam.map(sleutel) })
        for naam in StandaardCategorieen.labels where !bestaandeLabels.contains(sleutel(naam)) {
            let label = ReceptLabel(context: context)
            label.naam = naam
            if let prive { context.assign(label, to: prive) }
        }
        try context.bewaarIndienNodig()
    }

    /// Voegt categorieën en labels met dezelfde naam samen, per store en kookboek (zie boven).
    /// Recepten van een dubbele gaan naar de overblijvende. Geeft het aantal verwijderde dubbelen terug.
    @discardableResult
    static func ontdubbel(in context: NSManagedObjectContext) throws -> Int {
        var verwijderd = 0

        for groep in dubbeleGroepen(try context.fetch(Categorie.verzoek()), naam: \.naam, uuid: \.uuid, in: context) {
            let blijft = groep[0]
            for dubbel in groep.dropFirst() {
                for recept in dubbel.recepten ?? [] {
                    recept.categorieen = (recept.categorieen ?? []).subtracting([dubbel]).union([blijft])
                }
                blijft.isStandaard = blijft.isStandaard || dubbel.isStandaard
                context.delete(dubbel)
                verwijderd += 1
            }
        }

        for groep in dubbeleGroepen(try context.fetch(ReceptLabel.verzoek()), naam: \.naam, uuid: \.uuid, in: context) {
            let blijft = groep[0]
            for dubbel in groep.dropFirst() {
                for recept in dubbel.recepten ?? [] {
                    recept.labels = (recept.labels ?? []).subtracting([dubbel]).union([blijft])
                }
                context.delete(dubbel)
                verwijderd += 1
            }
        }

        try context.bewaarIndienNodig()
        return verwijderd
    }

    /// Groepen van twee of meer objecten met dezelfde naam in dezelfde store en hetzelfde kookboek;
    /// per groep staat de blijver vooraan.
    private static func dubbeleGroepen<T: NSManagedObject>(
        _ objecten: [T], naam: KeyPath<T, String?>, uuid: KeyPath<T, UUID?>, in context: NSManagedObjectContext
    ) -> [[T]] {
        let perNaam = Dictionary(grouping: objecten.filter { !sleutel($0[keyPath: naam] ?? "").isEmpty }) {
            "\($0.objectID.persistentStore?.identifier ?? "")|\(Kookboek(veld: $0.kookboekVeld).rawValue)|"
                + sleutel($0[keyPath: naam] ?? "")
        }
        return perNaam.values
            .filter { $0.count > 1 }
            .map { groep in
                // Zonder uuid achteraan ("~" sorteert na hexadecimale tekens).
                groep.sorted { ($0[keyPath: uuid]?.uuidString ?? "~") < ($1[keyPath: uuid]?.uuidString ?? "~") }
            }
    }

    /// Haalt ingrediënten die nog alleen hun letterlijke regel hebben (recepten uit fase 1) door de
    /// parser. Idempotent; geeft het aantal bijgewerkte ingrediënten terug.
    @discardableResult
    static func structureerIngredienten(in context: NSManagedObjectContext) throws -> Int {
        let verzoek = Ingredient.verzoek()
        verzoek.predicate = NSPredicate(
            format: "ruweTekst != nil AND naam == nil AND hoeveelheid == nil AND eenheid == nil")
        var aantal = 0
        for ingredient in try context.fetch(verzoek) {
            let p = IngredientParser.parse(ingredient.ruweTekst ?? "")
            guard !p.naam.isEmpty || p.hoeveelheid != nil || p.eenheid != nil else { continue }
            ingredient.vulGestructureerd()
            aantal += 1
        }
        try context.bewaarIndienNodig()
        return aantal
    }
}
