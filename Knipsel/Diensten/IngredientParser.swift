import Foundation

/// Een ingrediëntregel, uit elkaar gehaald. De letterlijke regel blijft daarnaast altijd bewaard
/// (`Ingredient.ruweTekst`); deze velden zijn er voor schalen, zoeken en voorlezen.
struct GeparseerdIngredient: Equatable, Sendable {
    var hoeveelheid: Double?
    /// Bovengrens bij een bereik: "3-4 tenen" → 3 tot 4.
    var hoeveelheidTot: Double?
    /// Maten en lepels genormaliseerd ("eetlepels" → "el", "gram" → "g", "liter" → "l"); telwoorden
    /// zoals "tenen", "blik" en "snufje" zoals ze er staan, in kleine letters.
    var eenheid: String?
    var naam: String
    /// Wat tussen haakjes of na de eerste komma staat: "(ca. 1 kg)", ", gesnipperd".
    var toelichting: String?
    /// De eenheid is alleen herkend via een bekende verwarring van de tekstherkenning ("ti" → "tl").
    var eenheidGeraden = false
}

/// Haalt Nederlandse ingrediëntregels uit elkaar: hoeveelheid (ook ½, 1½, 1/2, 3-4, "een"),
/// eenheid, naam en toelichting, plus groepskoppen als "Voor de saus:". Puur en zonder opslag.
enum IngredientParser {
    // MARK: - Openbaar

    static func parse(_ regel: String) -> GeparseerdIngredient {
        var rest = zonderOpsommingsteken(regel)

        // Toelichting tussen haakjes, waar die ook staat.
        var toelichtingen: [String] = []
        while let open = rest.firstIndex(of: "("), let dicht = rest[open...].firstIndex(of: ")") {
            let binnen = rest[rest.index(after: open)..<dicht].trimmingCharacters(in: .whitespaces)
            if !binnen.isEmpty { toelichtingen.append(binnen) }
            rest.removeSubrange(open...dicht)
        }
        rest = schoon(rest)

        // "ca. 1 kg", "± 200 g": de benadering zit al in de letterlijke regel.
        if let bereik = rest.range(
            of: #"^(ca\.?|circa|ong\.?|ongeveer|±)\s*"#, options: [.regularExpression, .caseInsensitive])
        {
            rest.removeSubrange(bereik)
        }

        var resultaat = GeparseerdIngredient(naam: "")
        if let (van, tot, lengte) = hoeveelheid(aanBeginVan: rest) {
            resultaat.hoeveelheid = van
            resultaat.hoeveelheidTot = tot
            rest = schoon(String(rest.dropFirst(lengte)))
        }

        if let (eenheid, lengte, geraden) = eenheid(aanBeginVan: rest, naHoeveelheid: resultaat.hoeveelheid != nil) {
            resultaat.eenheid = eenheid
            resultaat.eenheidGeraden = geraden
            rest = schoon(String(rest.dropFirst(lengte)))
        }

        // Naam en toelichting na de eerste komma.
        if let komma = rest.firstIndex(of: ",") {
            let na = schoon(String(rest[rest.index(after: komma)...]))
            if !na.isEmpty { toelichtingen.append(na) }
            rest = String(rest[..<komma])
        }
        resultaat.naam = schoon(rest)
        resultaat.toelichting = toelichtingen.isEmpty ? nil : toelichtingen.joined(separator: "; ")
        return resultaat
    }

    /// "Voor de saus:" → "Voor de saus". Ook zonder dubbele punt als de regel met "Voor de/het"
    /// begint en geen hoeveelheid heeft. Kopjes als "Ingrediënten" zijn geen groep.
    static func groepskop(_ regel: String) -> String? {
        let tekst = zonderOpsommingsteken(regel)
        guard !tekst.isEmpty, !isKopje(tekst), hoeveelheid(aanBeginVan: tekst) == nil else { return nil }
        if tekst.hasSuffix(":") {
            let kop = schoon(String(tekst.dropLast()))
            return kop.isEmpty || kop.split(separator: " ").count > 6 ? nil : kop
        }
        let woorden = tekst.split(separator: " ")
        if tekst.range(of: #"^voor (de|het|een) "#, options: [.regularExpression, .caseInsensitive]) != nil,
            woorden.count <= 5, tekst.rangeOfCharacter(from: .decimalDigits) == nil
        {
            return tekst
        }
        return nil
    }

    /// Een los kopje boven een lijst: "Ingrediënten", "Bereiding:", "Werkwijze".
    static func isKopje(_ regel: String) -> Bool {
        let sleutel = vouw(zonderOpsommingsteken(regel)).trimmingCharacters(in: CharacterSet(charactersIn: ": ."))
        return kopjes.contains(sleutel)
    }

    /// Lijkt deze regel een ingrediënt? Begint met een hoeveelheid of eenheid ("2 el", "snufje"),
    /// en is geen genummerde stap ("1. Schil …") of tijd ("20 minuten").
    static func lijktIngredient(_ regel: String) -> Bool {
        let tekst = zonderOpsommingsteken(regel)
        guard !tekst.isEmpty, tekst.count <= 70, !isGenummerd(tekst) else { return false }
        if vrijeIngredienten.contains(vouw(tekst)) { return true }
        // Een zin ("Een warme soep voor koude dagen.") is geen ingrediënt.
        if tekst.hasSuffix(".") || tekst.contains(". ") { return false }
        let p = parse(tekst)
        guard p.hoeveelheid != nil || p.eenheid != nil else { return false }
        guard let eersteWoord = p.naam.split(separator: " ").first.map({ vouw(String($0)) }) else {
            return p.eenheid != nil
        }
        return !geenIngredientWoorden.contains(eersteWoord.trimmingCharacters(in: .punctuationCharacters))
    }

    /// Een genummerde stap: "1. Schil …", "2) Verhit …".
    static func isGenummerd(_ regel: String) -> Bool {
        regel.range(of: #"^\s*\d{1,2}\s*[.)]\s*\p{L}"#, options: .regularExpression) != nil
    }

    /// Twijfel: een getal zonder eenheid voor iets dat bijna altijd een maat heeft
    /// ("1 groentebouillon": de "l" is bij het herkennen weggevallen), een groot getal zonder
    /// eenheid ("200 kokosmelk"), of een eenheid die alleen geraden is ("½ ti").
    static func mistEenheid(_ regel: String) -> Bool {
        let p = parse(regel)
        if p.eenheidGeraden { return true }
        guard let hoeveelheid = p.hoeveelheid, p.eenheid == nil, !p.naam.isEmpty else { return false }
        if hoeveelheid >= 50 { return true }
        let naam = vouw(p.naam)
        return maatplichtig.contains { naam.contains($0) }
    }

    // MARK: - Hoeveelheid

    private static let breuken: [Character: Double] = [
        "¼": 0.25, "½": 0.5, "¾": 0.75, "⅓": 1.0 / 3, "⅔": 2.0 / 3, "⅛": 0.125,
    ]

    /// Eén getal: "2", "1,5", "1.5", "½", "1½", "1 ½", "1/2", "1 1/2".
    private static let getalPatroon =
        #"(\d+\s+\d+/\d+|\d+/\d+|\d+(?:[.,]\d+)?\s?[¼½¾⅓⅔⅛]|\d+(?:[.,]\d+)?|[¼½¾⅓⅔⅛])"#

    /// Getal, eventueel als bereik ("3-4", "2 à 3", "2 tot 3"), gevolgd door spatie, letter of einde
    /// (dus niet de "1." van een genummerde stap).
    private static let bereikRegex = try! NSRegularExpression(
        pattern: "^" + getalPatroon + #"(?:\s*(?:-|–|—|à|tot)\s*"# + getalPatroon + #")?(?=\s|\p{L}|$)"#)

    private static let telwoorden: [String: Double] = [
        "een": 1, "één": 1, "half": 0.5, "halve": 0.5, "anderhalf": 1.5, "anderhalve": 1.5, "twee": 2,
        "drie": 3, "vier": 4, "vijf": 5, "zes": 6,
    ]

    /// Hoeveelheid aan het begin, met het aantal gelezen tekens.
    private static func hoeveelheid(aanBeginVan tekst: String) -> (Double, Double?, Int)? {
        let ns = tekst as NSString
        if let treffer = bereikRegex.firstMatch(in: tekst, range: NSRange(location: 0, length: ns.length)),
            let van = getal(ns.substring(with: treffer.range(at: 1)))
        {
            var tot: Double?
            if treffer.range(at: 2).location != NSNotFound,
                let waarde = getal(ns.substring(with: treffer.range(at: 2))),
                waarde > van
            {
                tot = waarde
            }
            return (van, tot, treffer.range.length)
        }
        // Telwoord: "een blik tomaten", "halve citroen". Niet "een paar" of "een beetje".
        let woorden = tekst.split(separator: " ", maxSplits: 2).map(String.init)
        if let eerste = woorden.first, let waarde = telwoorden[eerste.lowercased()], woorden.count > 1,
            !["paar", "beetje", "klein", "kleine"].contains(woorden[1].lowercased())
        {
            return (waarde, nil, eerste.count)
        }
        return nil
    }

    private static func getal(_ tekst: String) -> Double? {
        let t = tekst.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return nil }
        // "1 1/2" of "1/2"
        if t.contains("/") {
            let delen = t.split(separator: " ")
            var som = 0.0
            for deel in delen {
                if deel.contains("/") {
                    let ab = deel.split(separator: "/")
                    guard ab.count == 2, let a = Double(ab[0]), let b = Double(ab[1]), b != 0 else { return nil }
                    som += a / b
                } else {
                    guard let a = Double(deel) else { return nil }
                    som += a
                }
            }
            return som
        }
        // "1½", "1 ½", "½"
        if let laatste = t.last, let breuk = breuken[laatste] {
            let geheel = t.dropLast().trimmingCharacters(in: .whitespaces)
            return (geheel.isEmpty ? 0 : Double(geheel.replacingOccurrences(of: ",", with: ".")) ?? 0) + breuk
        }
        return Double(t.replacingOccurrences(of: ",", with: "."))
    }

    // MARK: - Eenheid

    /// Maten en lepels: schrijfwijze → vaste afkorting.
    private static let maten: [String: String] = [
        "g": "g", "gr": "g", "gram": "g", "kg": "kg", "kilo": "kg", "kilogram": "kg", "mg": "mg", "ml": "ml",
        "milliliter": "ml", "cl": "cl", "centiliter": "cl", "dl": "dl", "deciliter": "dl", "l": "l", "ltr": "l",
        "liter": "l", "el": "el", "eetl": "el", "eetlepel": "el", "eetlepels": "el", "tl": "tl", "theel": "tl",
        "theelepel": "tl", "theelepels": "tl", "kl": "kl", "koffielepel": "kl", "koffielepels": "kl", "cm": "cm",
        "mm": "mm",
    ]

    /// Telwoorden die als eenheid dienen; bewaard zoals geschreven.
    private static let teleenheden: Set<String> = [
        "teen", "tenen", "teentje", "teentjes", "blik", "blikken", "blikje", "blikjes", "pot", "potten", "potje",
        "potjes", "pak", "pakken", "pakje", "pakjes", "zak", "zakken", "zakje", "zakjes", "bos", "bossen", "bosje",
        "bosjes", "tak", "takken", "takje", "takjes", "snuf", "snufje", "snufjes", "scheut", "scheutje",
        "scheutjes", "mespunt", "mespuntje", "handje", "handjes", "handvol", "handjevol", "plak", "plakken",
        "plakje", "plakjes", "stuk", "stuks", "stukje", "stukjes", "kop", "koppen", "kopje", "kopjes", "glas",
        "glazen", "glaasje", "beker", "bekers", "bekertje", "blad", "bladen", "blaadje", "blaadjes", "vel", "vellen",
        "velletje", "velletjes", "stengel", "stengels", "steel", "stelen", "struik", "struiken", "krop", "kroppen",
        "druppel", "druppels", "bakje", "bakjes", "doos", "doosje", "fles", "flessen", "flesje", "rol", "rollen",
        "bol", "bollen",
    ]

    /// Bekende verwarringen van de tekstherkenning: "tl" wordt soms "ti".
    private static let ocrVerwarringen: [String: String] = ["ti": "tl"]

    /// Eenheden die alleen meetellen als er al een hoeveelheid stond (anders is "l" of "pot" de naam).
    private static let alleenNaHoeveelheid: Set<String> = ["g", "l", "kg", "ml", "cl", "dl", "mg", "cm", "mm"]

    private static func eenheid(aanBeginVan tekst: String, naHoeveelheid: Bool) -> (String, Int, Bool)? {
        // Het woord aan het begin, zonder punt erachter ("el.", "gr.").
        guard let bereik = tekst.range(of: #"^\p{L}+\.?"#, options: .regularExpression) else { return nil }
        let woord = String(tekst[bereik])
        let kaal = woord.hasSuffix(".") ? String(woord.dropLast()) : woord
        let sleutel = kaal.lowercased()
        // Er moet nog een naam volgen: "2 el" alleen is te kort om zeker te zijn, maar wel toegestaan.
        let naWoord = tekst[bereik.upperBound...]
        guard naWoord.isEmpty || naWoord.first == " " || naWoord.first == "," else { return nil }

        if let maat = maten[sleutel] {
            if alleenNaHoeveelheid.contains(maat) || maat == "el" || maat == "tl" {
                guard naHoeveelheid else { return nil }
            }
            // Hoofdletters ("L", "G") alleen voor l en g; "EL" en "Tl" ook.
            return (maat, woord.count, false)
        }
        if teleenheden.contains(sleutel) {
            return (sleutel, woord.count, false)
        }
        if naHoeveelheid, let geraden = ocrVerwarringen[sleutel], !naWoord.isEmpty {
            return (geraden, woord.count, true)
        }
        return nil
    }

    // MARK: - Woordenlijsten

    private static let kopjes: Set<String> = [
        "ingredienten", "ingredient", "benodigdheden", "nodig", "je hebt nodig", "wat heb je nodig", "bereiding",
        "bereidingswijze", "werkwijze", "zo maak je het", "zo maak je het klaar", "recept",
    ]

    /// Regels zonder hoeveelheid die toch vaak een ingrediënt zijn.
    private static let vrijeIngredienten: Set<String> = [
        "peper en zout", "zout en peper", "peper", "zout", "peper en zout naar smaak", "olie om te bakken",
        "boter om in te vetten",
    ]

    /// Woorden na een getal die op tijd, aantal personen of temperatuur wijzen, niet op een ingrediënt.
    private static let geenIngredientWoorden: Set<String> = [
        "minuten", "minuut", "min", "uur", "uren", "seconden", "personen", "persoon", "pers", "porties", "portie",
        "graden", "stappen", "keer",
    ]

    /// Ingrediënten die vrijwel altijd een maat hebben; zonder eenheid is die waarschijnlijk weggevallen.
    private static let maatplichtig = [
        "bouillon", "fond", "melk", "room", "water", "olie", "azijn", "wijn", "bier", "sap", "saus", "siroop",
        "stroop", "honing", "bloem", "meel", "suiker", "rijst", "pasta", "yoghurt", "kwark", "boter", "kaas",
        "ketchup", "mayonaise", "mosterd", "chocolade", "gehakt", "port", "cognac", "likeur", "custard", "pulp",
        "passata",
    ]

    // MARK: - Hulp

    private static func zonderOpsommingsteken(_ regel: String) -> String {
        var tekst = schoon(regel)
        while let eerste = tekst.first, "•·-–—*▪︎●".contains(eerste) {
            tekst = schoon(String(tekst.dropFirst()))
        }
        return tekst
    }

    private static func schoon(_ tekst: String) -> String {
        tekst.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Kleine letters zonder accenten, voor vergelijken.
    static func vouw(_ tekst: String) -> String {
        tekst.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "nl_NL"))
    }
}
