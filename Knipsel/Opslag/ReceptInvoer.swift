import CoreData

/// Het invoerformulier van een recept, los van Core Data: wijzigingen gaan pas naar de opslag bij
/// "Bewaar". Ingrediënten zijn één regel per ingrediënt, stappen één per alinea. Naast de letterlijke
/// regel vult `IngredientParser` hoeveelheid, eenheid, naam en toelichting; een regel als
/// "Voor de saus:" wordt de groep van de ingrediënten eronder.
struct ReceptInvoer: Equatable {
    var titel = ""
    var intro = ""
    var porties = 0
    var bereidingstijdMinuten = 0
    var totaleTijdMinuten = 0
    var bronNaam = ""
    var bronDatum: Date?
    var bronPagina = ""
    var notities = ""
    var categorieen: Set<NSManagedObjectID> = []
    var labels: Set<NSManagedObjectID> = []
    var ingredientenTekst = ""
    var stappenTekst = ""

    init() {}

    init(recept: Recept) {
        titel = recept.titel ?? ""
        intro = recept.intro ?? ""
        porties = Int(recept.porties)
        bereidingstijdMinuten = Int(recept.bereidingstijdMinuten)
        totaleTijdMinuten = Int(recept.totaleTijdMinuten)
        bronNaam = recept.bronNaam ?? ""
        bronDatum = recept.bronDatum
        bronPagina = recept.bronPagina ?? ""
        notities = recept.notities ?? ""
        categorieen = Set((recept.categorieen ?? []).map(\.objectID))
        labels = Set((recept.labels ?? []).map(\.objectID))
        // Groepen terug als kopregel ("Voor de saus:"), zodat bewaren ze weer herkent.
        var regels: [String] = []
        var groep: String?
        for ingredient in recept.gesorteerdeIngredienten {
            if let nieuw = ingredient.groep, !nieuw.isEmpty, nieuw != groep {
                regels.append(nieuw + ":")
            }
            groep = ingredient.groep
            if let tekst = ingredient.ruweTekst { regels.append(tekst) }
        }
        ingredientenTekst = regels.joined(separator: "\n")
        // Lege regel tussen stappen: leest prettiger in het invoerveld; `regels(_:)` slaat hem over.
        stappenTekst = recept.gesorteerdeStappen.compactMap(\.tekst).joined(separator: "\n\n")
    }

    var isGeldig: Bool { !Self.schoon(titel).isEmpty }

    /// Niet-lege regels, zonder spaties eromheen.
    static func regels(_ tekst: String) -> [String] {
        tekst.split(whereSeparator: \.isNewline).map { schoon(String($0)) }.filter { !$0.isEmpty }
    }

    /// Schrijft de invoer naar `recept`, of naar een nieuw recept als dat `nil` is, en bewaart.
    @discardableResult
    func bewaar(in context: NSManagedObjectContext, recept bestaand: Recept? = nil) throws -> Recept {
        let recept = bestaand ?? Recept(context: context)
        recept.titel = Self.schoon(titel)
        recept.intro = Self.leegIsNil(intro)
        recept.porties = Int16(clamping: max(0, porties))
        recept.bereidingstijdMinuten = Int32(clamping: max(0, bereidingstijdMinuten))
        recept.totaleTijdMinuten = Int32(clamping: max(0, totaleTijdMinuten))
        recept.bronNaam = Self.leegIsNil(bronNaam)
        recept.bronDatum = bronDatum
        recept.bronPagina = Self.leegIsNil(bronPagina)
        recept.notities = Self.leegIsNil(notities)
        recept.categorieen = Set(categorieen.compactMap { try? context.existingObject(with: $0) as? Categorie })
        recept.labels = Set(labels.compactMap { try? context.existingObject(with: $0) as? ReceptLabel })
        recept.gewijzigdOp = .now

        // Bestaande objecten op dezelfde plek hergebruiken: minder wijzigingen om te synchroniseren.
        // Kopregels ("Voor de saus:") worden de groep van de regels eronder, geen eigen ingrediënt.
        var ingredientRegels: [(tekst: String, groep: String?)] = []
        var groep: String?
        for regel in Self.regels(ingredientenTekst) {
            if let kop = IngredientParser.groepskop(regel) {
                groep = kop
            } else {
                ingredientRegels.append((regel, groep))
            }
        }
        let ingredienten = recept.gesorteerdeIngredienten
        for (index, regel) in ingredientRegels.enumerated() {
            let ingredient = index < ingredienten.count ? ingredienten[index] : Ingredient(context: context)
            if ingredient.ruweTekst != regel.tekst || !ingredient.isGestructureerd {
                ingredient.ruweTekst = regel.tekst
                ingredient.vulGestructureerd()
            }
            if ingredient.groep != regel.groep { ingredient.groep = regel.groep }
            ingredient.volgorde = Int16(clamping: index)
            ingredient.recept = recept
        }
        for overbodig in ingredienten.dropFirst(ingredientRegels.count) {
            context.delete(overbodig)
        }

        let stapRegels = Self.regels(stappenTekst)
        let stappen = recept.gesorteerdeStappen
        for (index, regel) in stapRegels.enumerated() {
            let stap = index < stappen.count ? stappen[index] : Stap(context: context)
            stap.tekst = regel
            stap.volgorde = Int16(clamping: index)
            stap.recept = recept
        }
        for overbodig in stappen.dropFirst(stapRegels.count) {
            context.delete(overbodig)
        }

        try context.save()
        return recept
    }

    private static func schoon(_ tekst: String) -> String {
        tekst.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func leegIsNil(_ tekst: String) -> String? {
        let schoon = schoon(tekst)
        return schoon.isEmpty ? nil : schoon
    }
}
