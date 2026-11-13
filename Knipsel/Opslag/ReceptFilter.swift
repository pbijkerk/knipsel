import CoreData

/// Welke categorie de bibliotheek toont.
enum CategorieKeuze: Hashable, Sendable {
    case alles
    case categorie(NSManagedObjectID)
    /// Recepten zonder enige categorie, bijvoorbeeld na het verwijderen van hun categorie.
    case zonderCategorie
}

/// Zoeken en filteren in de bibliotheek: zoekterm (titel én ingrediënt), één categorie en nul of meer
/// labels. Alles wordt gecombineerd (EN), zodat "Hoofdgerechten + Vegetarisch + Snel" werkt.
struct ReceptFilter: Equatable {
    var zoekterm = ""
    var categorie: CategorieKeuze = .alles
    var labels: Set<NSManagedObjectID> = []

    var isLeeg: Bool { zoekterm.trimmingCharacters(in: .whitespaces).isEmpty && categorie == .alles && labels.isEmpty }

    var predicaat: NSPredicate? {
        var delen: [NSPredicate] = []

        // Elk woord moet ergens voorkomen: in de titel of in een ingrediënt.
        for woord in zoekterm.split(whereSeparator: \.isWhitespace).map(String.init) {
            delen.append(
                NSPredicate(
                    format: "titel CONTAINS[cd] %@ OR ANY ingredienten.ruweTekst CONTAINS[cd] %@ "
                        + "OR ANY ingredienten.naam CONTAINS[cd] %@",
                    woord, woord, woord))
        }

        switch categorie {
        case .alles: break
        case .categorie(let id): delen.append(NSPredicate(format: "ANY categorieen == %@", id))
        case .zonderCategorie: delen.append(NSPredicate(format: "categorieen.@count == 0"))
        }

        for label in labels.sorted(by: { $0.uriRepresentation().absoluteString < $1.uriRepresentation().absoluteString }
        ) {
            delen.append(NSPredicate(format: "ANY labels == %@", label))
        }

        return delen.isEmpty ? nil : NSCompoundPredicate(andPredicateWithSubpredicates: delen)
    }

    static var sortering: [NSSortDescriptor] {
        [
            NSSortDescriptor(
                key: "titel", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
        ]
    }

    func verzoek() -> NSFetchRequest<Recept> {
        let verzoek = Recept.verzoek()
        verzoek.predicate = predicaat
        verzoek.sortDescriptors = Self.sortering
        return verzoek
    }
}
