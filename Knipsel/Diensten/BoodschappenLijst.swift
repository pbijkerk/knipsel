import Foundation

/// Eén ingrediënt zoals het in het recept staat, los van Core Data zodat de lijst puur te testen is.
struct BoodschappenInvoer: Equatable, Sendable {
    var ruweTekst: String
    var hoeveelheid: Double?
    var hoeveelheidTot: Double?
    var eenheid: String?
    var naam: String?
    var toelichting: String?

    init(
        ruweTekst: String, hoeveelheid: Double? = nil, hoeveelheidTot: Double? = nil, eenheid: String? = nil,
        naam: String? = nil, toelichting: String? = nil
    ) {
        self.ruweTekst = ruweTekst
        self.hoeveelheid = hoeveelheid
        self.hoeveelheidTot = hoeveelheidTot
        self.eenheid = eenheid
        self.naam = naam
        self.toelichting = toelichting
    }

    /// Een regel door de ingrediëntparser, zoals bij het bewaren van een recept.
    init(regel: String) {
        let p = IngredientParser.parse(regel)
        self.init(
            ruweTekst: regel, hoeveelheid: p.hoeveelheid, hoeveelheidTot: p.hoeveelheidTot, eenheid: p.eenheid,
            naam: p.naam.isEmpty ? nil : p.naam, toelichting: p.toelichting)
    }

    init(_ ingredient: Ingredient) {
        self.init(
            ruweTekst: ingredient.ruweTekst ?? "", hoeveelheid: ingredient.hoeveelheid?.doubleValue,
            hoeveelheidTot: ingredient.hoeveelheidTot?.doubleValue, eenheid: ingredient.eenheid,
            naam: ingredient.naam, toelichting: ingredient.toelichting)
    }
}

/// Eén regel op de boodschappenlijst: "3 uien", "200 ml kokosmelk", of letterlijk "peper en zout".
struct BoodschappenRegel: Identifiable, Equatable, Sendable {
    /// Genormaliseerde naam plus maatsoort; uniek binnen één lijst.
    let id: String
    /// Genormaliseerde naam (enkelvoud, kleine letters, zonder accenten): vergelijken met Herinneringen.
    let sleutel: String
    /// De naam zoals in het recept ("uien", "kokosmelk"); bij een regel zonder hoeveelheid de hele tekst.
    let naam: String
    let hoeveelheid: Double?
    let hoeveelheidTot: Double?
    let eenheid: String?
    /// Wat er op de lijst komt: "3 uien", "1½ el olijfolie", "wat zout".
    let tekst: String
    /// Staat standaard uitgevinkt, onderaan in "Meestal in huis".
    let meestalInHuis: Bool

    /// Zonder hoeveelheid (L3): de letterlijke tekst, niet op te tellen.
    var isTekst: Bool { hoeveelheid == nil }

    /// Het woord dat in "Meestal in huis" komt als je dit vaak uitvinkt: "peper", "boter".
    var woord: String { Portieschaling.getal(naam, voor: 1).lowercased() }
}

/// Van ingrediënten en porties naar een boodschappenlijst (L1, L3, L5). Puur, zonder opslag.
enum BoodschappenLijst {
    /// Geschaald met `factor` (zie `Portieschaling.factor`); gelijke ingrediënten binnen het recept
    /// worden één regel als de maat gelijk of om te rekenen is (g/kg, ml/cl/dl/l). Lepels worden niet
    /// naar ml omgerekend: 1 el en 1 tl olie blijven twee regels. Kopjes ("Voor de saus:") vallen weg;
    /// een regel zonder hoeveelheid komt er letterlijk op.
    static func regels(
        _ invoer: [BoodschappenInvoer], factor: Double, meestalInHuis: MeestalInHuis = .standaard
    ) -> [BoodschappenRegel] {
        var volgorde: [String] = []
        var stapels: [String: Stapel] = [:]

        for ingredient in invoer {
            let ruw = IngredientParser.zonderOpsommingsteken(ingredient.ruweTekst)
            guard let hoeveelheid = ingredient.hoeveelheid, let naam = ingredient.naam?.trimmed, !naam.isEmpty
            else {
                guard !ruw.isEmpty, IngredientParser.groepskop(ruw) == nil, !IngredientParser.isKopje(ruw) else {
                    continue
                }
                let naam = ingredient.naam?.trimmed.nietLeeg ?? ruw
                let id = "tekst:" + sleutel(ruw)
                if stapels[id] == nil {
                    volgorde.append(id)
                    stapels[id] = Stapel(naam: naam, tekst: ruw, sleutel: sleutel(naam))
                }
                continue
            }
            let maat = Maat(eenheid: ingredient.eenheid)
            let id = sleutel(naam) + "|" + maat.soort
            let van = hoeveelheid * factor * maat.naarBasis
            let tot = ingredient.hoeveelheidTot.map { $0 * factor * maat.naarBasis }
            let toelichting = maatToelichting(ingredient.toelichting, factor: factor)
            if var stapel = stapels[id] {
                stapel.voegToe(van: van, tot: tot, eenheid: maat.eenheid, toelichting: toelichting)
                stapels[id] = stapel
            } else {
                volgorde.append(id)
                stapels[id] = Stapel(
                    naam: naam, sleutel: sleutel(naam), van: van, tot: tot, eenheden: [maat.eenheid],
                    toelichting: toelichting, aantal: 1, factor: factor)
            }
        }

        return volgorde.compactMap { id in
            guard let stapel = stapels[id] else { return nil }
            return stapel.regel(id: id, meestalInHuis: meestalInHuis)
        }
    }

    /// Platte tekst om te delen (WhatsApp, AH-app): kop plus "• 3 uien" per regel.
    static func tekst(recept: String, porties: Int, regels: [BoodschappenRegel]) -> String {
        let personen = Weergave.porties(porties).map { " (\($0))" } ?? ""
        let kop = "Boodschappen · \(recept)\(personen)"
        return ([kop] + regels.map { "• \($0.tekst)" }).joined(separator: "\n")
    }

    /// "3 uien" op de lijst en "2 uien" erbij → "5 uien". `nil` als het niet op te tellen is (geen
    /// hoeveelheid, of g en el).
    static func opgeteld(bestaand titel: String, plus regel: BoodschappenRegel) -> String? {
        guard let hoeveelheid = regel.hoeveelheid else { return nil }
        let bestaand = BoodschappenInvoer(regel: titel)
        guard bestaand.hoeveelheid != nil, let naam = bestaand.naam, sleutel(naam) == regel.sleutel else {
            return nil
        }
        let erbij = BoodschappenInvoer(
            ruweTekst: regel.tekst, hoeveelheid: hoeveelheid, hoeveelheidTot: regel.hoeveelheidTot,
            eenheid: regel.eenheid, naam: regel.naam)
        let samen = regels([bestaand, erbij], factor: 1, meestalInHuis: MeestalInHuis(woorden: []))
        guard samen.count == 1 else { return nil }
        return samen[0].tekst
    }

    /// Kleine letters, zonder accenten en leestekens, eerste bekende woord in enkelvoud: "Uien" → "ui".
    static func sleutel(_ naam: String) -> String {
        let enkelvoud = Portieschaling.getal(naam.lowercased(), voor: 1)
        let woorden = IngredientParser.vouw(enkelvoud)
            .components(separatedBy: CharacterSet.letters.union(.decimalDigits).inverted)
            .filter { !$0.isEmpty }
        return woorden.joined(separator: " ")
    }

    // MARK: - Maten

    /// Soort maat en de factor naar de basiseenheid (g of ml). Lepels en telwoorden zijn hun eigen soort.
    private struct Maat {
        let eenheid: String?
        let soort: String
        let naarBasis: Double

        init(eenheid ruw: String?) {
            let eenheid = ruw?.trimmed.lowercased().nietLeeg
            self.eenheid = eenheid
            switch eenheid {
            case "mg": (soort, naarBasis) = ("gewicht", 0.001)
            case "g": (soort, naarBasis) = ("gewicht", 1)
            case "kg": (soort, naarBasis) = ("gewicht", 1000)
            case "ml": (soort, naarBasis) = ("volume", 1)
            case "cl": (soort, naarBasis) = ("volume", 10)
            case "dl": (soort, naarBasis) = ("volume", 100)
            case "l": (soort, naarBasis) = ("volume", 1000)
            case nil: (soort, naarBasis) = ("stuks", 1)
            case let eenheid?: (soort, naarBasis) = (Portieschaling.eenheid(eenheid, voor: 1), 1)
            }
        }

        /// Welke eenheid een opgeteld totaal krijgt: dezelfde als alles dezelfde was, anders g/kg of
        /// ml/l naar grootte.
        static func weergave(_ eenheden: [String?], basis: Double) -> (eenheid: String?, deler: Double) {
            let uniek = Set(eenheden.map { $0 ?? "" })
            if uniek.count == 1, let enige = eenheden.first {
                return (enige, Maat(eenheid: enige).naarBasis)
            }
            switch Maat(eenheid: eenheden.first ?? nil).soort {
            case "gewicht": return basis >= 1000 ? ("kg", 1000) : ("g", 1)
            case "volume": return basis >= 1000 ? ("l", 1000) : ("ml", 1)
            default: return (eenheden.first ?? nil, 1)
            }
        }
    }

    /// Alleen een maat in de toelichting gaat mee ("400 g" bij een blik), geschaald; "gesnipperd" niet.
    private static func maatToelichting(_ toelichting: String?, factor: Double) -> String? {
        guard let toelichting, !toelichting.isEmpty else { return nil }
        let delen = toelichting.components(separatedBy: "; ").filter { deel in
            let p = IngredientParser.parse(deel)
            return p.naam.isEmpty && p.eenheid != nil && p.hoeveelheid != nil
        }
        guard !delen.isEmpty else { return nil }
        return Portieschaling.schaalToelichting(delen.joined(separator: "; "), factor: factor)
    }

    /// Wat er per regel bij elkaar komt.
    private struct Stapel {
        var naam: String
        var tekst: String?
        var sleutel: String
        var van: Double = 0
        var tot: Double?
        var eenheden: [String?] = []
        var toelichting: String?
        var aantal = 0
        var factor: Double = 1

        init(naam: String, tekst: String, sleutel: String) {
            self.naam = naam
            self.tekst = tekst
            self.sleutel = sleutel
        }

        init(
            naam: String, sleutel: String, van: Double, tot: Double?, eenheden: [String?], toelichting: String?,
            aantal: Int, factor: Double
        ) {
            self.naam = naam
            self.sleutel = sleutel
            self.van = van
            self.tot = tot
            self.eenheden = eenheden
            self.toelichting = toelichting
            self.aantal = aantal
            self.factor = factor
        }

        mutating func voegToe(van extra: Double, tot extraTot: Double?, eenheid: String?, toelichting nieuw: String?) {
            if tot != nil || extraTot != nil { tot = (tot ?? van) + (extraTot ?? extra) }
            van += extra
            eenheden.append(eenheid)
            // Twee verschillende toelichtingen ("400 g" en "200 g") kloppen opgeteld niet meer.
            if toelichting != nieuw { toelichting = nil }
            aantal += 1
        }

        func regel(id: String, meestalInHuis: MeestalInHuis) -> BoodschappenRegel {
            if let tekst {
                return BoodschappenRegel(
                    id: id, sleutel: sleutel, naam: naam, hoeveelheid: nil, hoeveelheidTot: nil, eenheid: nil,
                    tekst: tekst, meestalInHuis: meestalInHuis.bevat(tekst))
            }
            let (eenheid, deler) = Maat.weergave(eenheden, basis: van)
            // Ongeschaald en niet opgeteld blijft de hoeveelheid precies zoals in het recept.
            let afronden = abs(factor - 1) > 0.0001 || aantal > 1
            func waarde(_ basis: Double) -> Double {
                afronden ? Portieschaling.rond(basis / deler, eenheid: eenheid) : basis / deler
            }
            let hoeveelheid = waarde(van)
            let bovengrens = tot.map(waarde).flatMap { $0 > hoeveelheid ? $0 : nil }
            let maat =
                Portieschaling.maat(hoeveelheid: hoeveelheid, tot: bovengrens, eenheid: eenheid, factor: 1) ?? ""
            let geteld = Portieschaling.naam(
                naam, hoeveelheid: hoeveelheid, tot: bovengrens, eenheid: eenheid, factor: 1)
            var tekst = "\(maat) \(geteld)"
            if let toelichting { tekst += " (\(toelichting))" }
            return BoodschappenRegel(
                id: id, sleutel: sleutel, naam: naam, hoeveelheid: hoeveelheid, hoeveelheidTot: bovengrens,
                eenheid: eenheid, tekst: tekst, meestalInHuis: meestalInHuis.bevat(naam))
        }
    }
}

extension String {
    fileprivate var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    fileprivate var nietLeeg: String? { isEmpty ? nil : self }
}
