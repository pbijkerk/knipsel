import CoreData

/// Welke categorie de bibliotheek toont. Op **naam**, niet op objectID: "Mijn recepten" en Thuis
/// hebben elk een eigen "Soepen" (`Kookboeken`), en de bibliotheek toont die als één categorie.
enum CategorieKeuze: Hashable, Sendable {
    case alles
    case categorie(String)
    /// Recepten zonder enige categorie, bijvoorbeeld na het verwijderen van hun categorie.
    case zonderCategorie
}

/// Zoeken en filteren in de bibliotheek: zoekterm (titel én ingrediënt), één categorie, nul of meer
/// labels en eventueel één kookboek. Alles wordt gecombineerd (EN), zodat "Thuis + Hoofdgerechten +
/// Vegetarisch + Snel" werkt. Categorieën en labels op naam (hoofdletters en accenten tellen niet).
struct ReceptFilter: Equatable {
    var zoekterm = ""
    var categorie: CategorieKeuze = .alles
    var labels: Set<String> = []
    /// `nil` = beide kookboeken.
    var kookboek: Kookboek?

    var isLeeg: Bool {
        zoekterm.trimmingCharacters(in: .whitespaces).isEmpty && categorie == .alles && labels.isEmpty
            && kookboek == nil
    }

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
        case .categorie(let naam): delen.append(NSPredicate(format: "ANY categorieen.naam ==[cd] %@", naam))
        case .zonderCategorie: delen.append(NSPredicate(format: "categorieen.@count == 0"))
        }

        for label in labels.sorted() {
            delen.append(NSPredicate(format: "ANY labels.naam ==[cd] %@", label))
        }

        if let kookboek {
            delen.append(NSPredicate(format: "kookboek == %@", kookboek.rawValue))
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

/// Eén categorie zoals de bibliotheek hem toont: alle gelijknamige categorieën uit beide kookboeken
/// samen. Het aantal telt elk recept één keer.
struct CategorieGroep: Identifiable, Equatable {
    /// De naam zoals hij getoond wordt (bij voorkeur die uit Mijn recepten).
    let naam: String
    let symbool: String
    let aantal: Int
    /// De objecten in deze groep; de eerste is de hoofdcategorie (bij voorkeur uit Mijn recepten).
    let categorieen: [Categorie]

    var id: String { Inrichting.sleutel(naam) }
    var keuze: CategorieKeuze { .categorie(naam) }

    /// Groepeert op naam, in de volgorde van `categorieen`. Telt alleen recepten uit `kookboek` als
    /// dat gezet is. Een groep waarvan de categorie in Mijn recepten verborgen is, valt weg.
    static func groepeer(_ categorieen: [Categorie], kookboek: Kookboek? = nil) -> [CategorieGroep] {
        var volgorde: [String] = []
        var perSleutel: [String: [Categorie]] = [:]
        for categorie in categorieen {
            let sleutel = Inrichting.sleutel(categorie.naamOfStandaard)
            if perSleutel[sleutel] == nil { volgorde.append(sleutel) }
            perSleutel[sleutel, default: []].append(categorie)
        }
        return volgorde.compactMap { sleutel in
            guard let groep = perSleutel[sleutel] else { return nil }
            let hoofd = groep.first { $0.kookboekWaarde == .mijn } ?? groep[0]
            // Verborgen in Instellingen › Categorieën (Mijn recepten): de hele groep weg.
            guard !hoofd.verborgen else { return nil }
            let recepten = Set(
                groep.flatMap { ($0.recepten ?? []).filter { kookboek == nil || $0.kookboekWaarde == kookboek } }
                    .map(\.objectID))
            return CategorieGroep(
                naam: hoofd.naamOfStandaard, symbool: hoofd.symboolOfStandaard, aantal: recepten.count,
                categorieen: [hoofd] + groep.filter { $0 !== hoofd })
        }
    }
}

/// Eén label zoals de bibliotheek het toont (gelijknamige labels uit beide kookboeken samen).
struct LabelGroep: Identifiable, Equatable {
    let naam: String
    let aantal: Int

    var id: String { Inrichting.sleutel(naam) }

    static func groepeer(_ labels: [ReceptLabel], kookboek: Kookboek? = nil) -> [LabelGroep] {
        var volgorde: [String] = []
        var perSleutel: [String: [ReceptLabel]] = [:]
        for label in labels {
            let sleutel = Inrichting.sleutel(label.naamOfStandaard)
            if perSleutel[sleutel] == nil { volgorde.append(sleutel) }
            perSleutel[sleutel, default: []].append(label)
        }
        return volgorde.compactMap { sleutel in
            guard let groep = perSleutel[sleutel] else { return nil }
            let hoofd = groep.first { $0.kookboekWaarde == .mijn } ?? groep[0]
            let recepten = Set(
                groep.flatMap { ($0.recepten ?? []).filter { kookboek == nil || $0.kookboekWaarde == kookboek } }
                    .map(\.objectID))
            return LabelGroep(naam: hoofd.naamOfStandaard, aantal: recepten.count)
        }
    }
}

/// Keuzelijsten (controlescherm, recept bewerken): één categorie of label per naam. Per naam wint
/// een gekozen object, dan een uit `kookboek`, dan de eerste. Bij het bewaren zet `Kookboeken.herstel`
/// een keuze uit het andere kookboek om naar de gelijknamige van het recept zelf.
enum Keuzeopties {
    static func uniek<T: NSManagedObject>(
        _ objecten: [T], gekozen: Set<NSManagedObjectID> = [], kookboek: Kookboek = .mijn
    ) -> [T] {
        var volgorde: [String] = []
        var beste: [String: T] = [:]
        func score(_ object: T) -> Int {
            (gekozen.contains(object.objectID) ? 2 : 0) + (Kookboek(veld: object.kookboekVeld) == kookboek ? 1 : 0)
        }
        for object in objecten {
            let sleutel = Inrichting.sleutel(object.value(forKey: "naam") as? String ?? "")
            if let huidig = beste[sleutel] {
                if score(object) > score(huidig) { beste[sleutel] = object }
            } else {
                volgorde.append(sleutel)
                beste[sleutel] = object
            }
        }
        return volgorde.compactMap { beste[$0] }
    }
}
