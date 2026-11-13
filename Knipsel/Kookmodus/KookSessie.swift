import Foundation
import Observation

/// Een ingrediënt zoals de kookmodus het nodig heeft: los van Core Data, zodat de sessie puur en
/// testbaar blijft.
struct KookIngredient: Identifiable, Equatable, Sendable {
    /// Positie in de ingrediëntenlijst.
    let id: Int
    var ruweTekst: String
    var hoeveelheid: Double?
    var hoeveelheidTot: Double?
    var eenheid: String?
    var naam: String?
    var toelichting: String?
    var groep: String?

    /// De naam om op te koppelen; voor regels die de parser nog niet uit elkaar haalde, uit de ruwe tekst.
    var koppelnaam: String {
        if let naam, !naam.isEmpty { return naam }
        return IngredientParser.parse(ruweTekst).naam
    }
}

struct KookStap: Identifiable, Equatable, Sendable {
    /// Positie in de bereiding (0 = stap 1).
    let id: Int
    var tekst: String
    var timerSeconden: Int = 0
    var groep: String?
}

/// Eén kookbeurt: welke stap, wat is afgevinkt, voor hoeveel personen. Een toestandsmachine zonder
/// UI; de kookmodus toont hem, en voorlezen, spraak, Siri en timers (fase 4–7) sturen hem aan en
/// luisteren naar `gebeurtenis`.
@MainActor
@Observable
final class KookSessie: Identifiable {
    /// Wat er het laatst gebeurde, voor wie moet reageren (bevestiging in beeld, voorlezen).
    enum Gebeurtenis: Equatable, Sendable {
        case volgende
        case vorige
        case naarStap(Int)
        case herhaal
        /// Na de laatste stap: "Eet smakelijk".
        case afgerond
        /// Er is geen vorige of volgende stap meer.
        case grens
    }

    let titel: String
    let ingredienten: [KookIngredient]
    let stappen: [KookStap]
    /// Porties van het recept; 0 = onbekend (dan schaalt er niets).
    let receptPorties: Int

    /// Index van de huidige stap (0 = stap 1).
    private(set) var huidigeIndex = 0
    /// Voorbij de laatste stap: het recept is klaar.
    private(set) var isAfgerond = false
    private(set) var afgevinkt: Set<Int> = []
    /// Voor hoeveel personen er gekookt wordt.
    private(set) var porties: Int

    private(set) var gebeurtenis: Gebeurtenis?
    /// Telt elke gebeurtenis, ook twee keer dezelfde ("herhaal", "herhaal"); handig voor `onChange`.
    private(set) var gebeurtenisNummer = 0

    /// Per stap de woorden die naar ingrediënten verwijzen.
    private let treffersPerStap: [[Ingredientkoppeling.Treffer]]

    init(titel: String, ingredienten: [KookIngredient], stappen: [KookStap], receptPorties: Int, porties: Int? = nil) {
        self.titel = titel
        self.ingredienten = ingredienten
        self.stappen = stappen
        self.receptPorties = max(0, receptPorties)
        self.porties = max(1, porties ?? (receptPorties > 0 ? receptPorties : 1))
        let namen = ingredienten.map(\.koppelnaam)
        treffersPerStap = stappen.map { Ingredientkoppeling.treffers(in: $0.tekst, namen: namen) }
    }

    // MARK: - Toestand

    var aantalStappen: Int { stappen.count }
    var huidigeStap: KookStap? { stappen.indices.contains(huidigeIndex) ? stappen[huidigeIndex] : nil }
    var vorigeStap: KookStap? { stappen.indices.contains(huidigeIndex - 1) ? stappen[huidigeIndex - 1] : nil }
    var volgendeStap: KookStap? { stappen.indices.contains(huidigeIndex + 1) ? stappen[huidigeIndex + 1] : nil }
    /// 1-gebaseerd, zoals de kok het noemt: "Stap 3 van 4".
    var stapNummer: Int { huidigeIndex + 1 }
    var isEersteStap: Bool { huidigeIndex == 0 }
    var isLaatsteStap: Bool { huidigeIndex >= stappen.count - 1 }

    /// Schaalfactor ten opzichte van het recept.
    var factor: Double { Portieschaling.factor(van: receptPorties, naar: porties) }

    /// Ander aantal personen; minstens 1.
    func wijzigPorties(naar aantal: Int) {
        porties = max(1, aantal)
    }

    // MARK: - Navigatie

    /// Een stap verder; na de laatste stap is het recept afgerond. `false` als dat al zo was.
    @discardableResult
    func volgende() -> Bool {
        guard !isAfgerond, !stappen.isEmpty else { return meld(.grens, gelukt: false) }
        if isLaatsteStap {
            isAfgerond = true
            return meld(.afgerond)
        }
        huidigeIndex += 1
        return meld(.volgende)
    }

    /// Een stap terug; vanuit "Eet smakelijk" terug naar de laatste stap.
    @discardableResult
    func vorige() -> Bool {
        if isAfgerond {
            isAfgerond = false
            return meld(.vorige)
        }
        guard huidigeIndex > 0 else { return meld(.grens, gelukt: false) }
        huidigeIndex -= 1
        return meld(.vorige)
    }

    /// Naar stap `index` (0 = stap 1), bijvoorbeeld "ga naar stap 3".
    @discardableResult
    func naarStap(_ index: Int) -> Bool {
        guard stappen.indices.contains(index) else { return meld(.grens, gelukt: false) }
        huidigeIndex = index
        isAfgerond = false
        return meld(.naarStap(index))
    }

    /// Verandert niets aan de stap, maar meldt dat hij herhaald moet worden (voorlezen, fase 4).
    func herhaal() {
        meld(.herhaal)
    }

    @discardableResult
    private func meld(_ nieuwe: Gebeurtenis, gelukt: Bool = true) -> Bool {
        gebeurtenis = nieuwe
        gebeurtenisNummer += 1
        return gelukt
    }

    // MARK: - Afvinken

    func isAfgevinkt(_ ingredient: KookIngredient) -> Bool { afgevinkt.contains(ingredient.id) }

    func wisselAfgevinkt(_ ingredient: KookIngredient) {
        if afgevinkt.contains(ingredient.id) {
            afgevinkt.remove(ingredient.id)
        } else {
            afgevinkt.insert(ingredient.id)
        }
    }

    // MARK: - Ingrediënten per stap

    /// Woorden in de staptekst die naar een ingrediënt verwijzen (voor de oranje markering).
    func treffers(inStap index: Int) -> [Ingredientkoppeling.Treffer] {
        treffersPerStap.indices.contains(index) ? treffersPerStap[index] : []
    }

    /// De ingrediënten die in stap `index` gebruikt worden, in lijstvolgorde.
    func ingredienten(inStap index: Int) -> [KookIngredient] {
        let indices = Set(treffers(inStap: index).flatMap(\.ingredienten))
        return ingredienten.filter { indices.contains($0.id) }
    }

    var ingredientenInHuidigeStap: [KookIngredient] {
        isAfgerond ? [] : ingredienten(inStap: huidigeIndex)
    }

    /// Ingrediëntregel voor het gekozen aantal porties: "1½ l groentebouillon".
    func tekst(van ingredient: KookIngredient) -> String {
        Portieschaling.regel(
            ruweTekst: ingredient.ruweTekst, hoeveelheid: ingredient.hoeveelheid, tot: ingredient.hoeveelheidTot,
            eenheid: ingredient.eenheid, naam: ingredient.naam, toelichting: ingredient.toelichting, factor: factor)
    }

    /// Alleen hoeveelheid en eenheid ("1½ l"), voor vette opmaak; `nil` zonder hoeveelheid.
    func maat(van ingredient: KookIngredient) -> String? {
        guard ingredient.hoeveelheid != nil, ingredient.naam != nil else { return nil }
        return Portieschaling.maat(
            hoeveelheid: ingredient.hoeveelheid, tot: ingredient.hoeveelheidTot, eenheid: ingredient.eenheid,
            factor: factor)
    }
}

extension KookSessie {
    /// Een sessie voor een bewaard recept.
    convenience init(recept: Recept, porties: Int? = nil) {
        let ingredienten = recept.gesorteerdeIngredienten.enumerated().map { index, ingredient in
            KookIngredient(
                id: index, ruweTekst: ingredient.ruweTekst ?? "", hoeveelheid: ingredient.hoeveelheid?.doubleValue,
                hoeveelheidTot: ingredient.hoeveelheidTot?.doubleValue, eenheid: ingredient.eenheid,
                naam: ingredient.naam, toelichting: ingredient.toelichting, groep: ingredient.groep)
        }
        let stappen = recept.gesorteerdeStappen.enumerated().map { index, stap in
            KookStap(id: index, tekst: stap.tekst ?? "", timerSeconden: Int(stap.timerSeconden), groep: stap.groep)
        }
        self.init(
            titel: recept.titelOfStandaard, ingredienten: ingredienten, stappen: stappen,
            receptPorties: Int(recept.porties), porties: porties)
    }
}
