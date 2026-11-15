import Foundation

/// Een recept zoals een website het in schema.org-gegevens meestuurt (JSON-LD of microdata).
struct SchemaRecept: Equatable, Sendable {
    /// Stappen onder een kopje (`HowToSection`), of zonder kopje (`naam == nil`).
    struct Stapgroep: Equatable, Sendable {
        var naam: String?
        var stappen: [String]
    }

    var naam = ""
    var beschrijving = ""
    /// 0 = onbekend.
    var porties = 0
    var voorbereidingMinuten = 0
    var kookMinuten = 0
    var totaalMinuten = 0
    var ingredienten: [String] = []
    var stapgroepen: [Stapgroep] = []
    var afbeelding: URL?
    var auteur: String?
    var uitgever: String?

    var stappen: [String] { stapgroepen.flatMap(\.stappen) }

    /// De tijd voor het recept: de totale tijd, anders voorbereiden + koken.
    var minuten: Int { totaalMinuten > 0 ? totaalMinuten : voorbereidingMinuten + kookMinuten }

    /// Genoeg om een recept te heten: een naam en ingrediënten of stappen.
    var isBruikbaar: Bool { !naam.isEmpty && (!ingredienten.isEmpty || !stapgroepen.isEmpty) }
}

/// Leest schema.org `Recipe` uit de HTML van een receptsite: eerst JSON-LD (`<script
/// type="application/ld+json">`, ook in `@graph` en lijsten), anders microdata (`itemprop`).
/// Puur en zonder netwerk; de tekst blijft letterlijk (K2), alleen tags en entiteiten gaan weg.
enum SchemaReceptLezer {
    /// Het (grootste) recept op de pagina, of `nil` als er geen is.
    static func lees(html: String, basis: URL? = nil) -> SchemaRecept? {
        let blokken = jsonLD(in: html)
        let index = idIndex(blokken)
        let kandidaten = blokken.flatMap { recepten(in: $0) }.map { recept(uit: $0, index: index, basis: basis) }
        if let beste = kandidaten.filter(\.isBruikbaar).max(by: { omvang($0) < omvang($1) }) {
            return beste
        }
        if let microdata = microdata(in: html, basis: basis), microdata.isBruikbaar {
            return microdata
        }
        return nil
    }

    private static func omvang(_ recept: SchemaRecept) -> Int {
        recept.ingredienten.count + recept.stappen.count
    }

    // MARK: - JSON-LD

    private static let scriptRegex = try! NSRegularExpression(
        pattern: #"<script\b[^>]*type\s*=\s*["']?application/ld\+json["']?[^>]*>([\s\S]*?)</script\s*>"#,
        options: .caseInsensitive)

    /// De inhoud van alle JSON-LD-blokken die als JSON te lezen zijn.
    static func jsonLD(in html: String) -> [Any] {
        let ns = html as NSString
        return scriptRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)).compactMap { treffer in
            var tekst = ns.substring(with: treffer.range(at: 1))
            for rommel in ["<!--", "-->", "<![CDATA[", "]]>", "//<![CDATA[", "//]]>"] {
                tekst = tekst.replacingOccurrences(of: rommel, with: "")
            }
            // Losse regeleinden en tabs in strings maken JSON ongeldig; buiten strings zijn het spaties.
            tekst = tekst.replacingOccurrences(of: #"[\n\r\t]"#, with: " ", options: .regularExpression)
            guard let data = tekst.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        }
    }

    /// Alle objecten met `@type` Recipe (als tekst of in een lijst), waar ze ook staan.
    static func recepten(in json: Any) -> [[String: Any]] {
        var gevonden: [[String: Any]] = []
        func zoek(_ waarde: Any, diepte: Int) {
            guard diepte < 12 else { return }
            if let object = waarde as? [String: Any] {
                if heeftType(object, "recipe") {
                    gevonden.append(object)
                    return
                }
                for (_, kind) in object { zoek(kind, diepte: diepte + 1) }
            } else if let lijst = waarde as? [Any] {
                for kind in lijst { zoek(kind, diepte: diepte + 1) }
            }
        }
        zoek(json, diepte: 0)
        return gevonden
    }

    /// `"@type": "Recipe"`, `["Recipe", "NewsArticle"]`, `"schema:Recipe"` of `"http://schema.org/Recipe"`.
    static func heeftType(_ object: [String: Any], _ type: String) -> Bool {
        let typen: [String] =
            (object["@type"] as? String).map { [$0] } ?? (object["@type"] as? [Any])?.compactMap { $0 as? String } ?? []
        return typen.contains { kandidaat in
            let laatste = kandidaat.split(whereSeparator: { "/:#".contains($0) }).last.map(String.init) ?? kandidaat
            return laatste.lowercased() == type
        }
    }

    /// Objecten met een `@id`, om verwijzingen als `"image": {"@id": "…#primaryimage"}` op te lossen.
    private static func idIndex(_ blokken: [Any]) -> [String: [String: Any]] {
        var index: [String: [String: Any]] = [:]
        func loop(_ waarde: Any, diepte: Int) {
            guard diepte < 12 else { return }
            if let object = waarde as? [String: Any] {
                if let id = object["@id"] as? String, object.count > 1, index[id] == nil { index[id] = object }
                for (_, kind) in object { loop(kind, diepte: diepte + 1) }
            } else if let lijst = waarde as? [Any] {
                for kind in lijst { loop(kind, diepte: diepte + 1) }
            }
        }
        for blok in blokken { loop(blok, diepte: 0) }
        return index
    }

    private static func recept(uit object: [String: Any], index: [String: [String: Any]], basis: URL?)
        -> SchemaRecept
    {
        func los(_ waarde: Any?) -> Any? {
            if let object = waarde as? [String: Any], let id = object["@id"] as? String, object.count == 1 {
                return index[id] ?? object
            }
            return waarde
        }
        var recept = SchemaRecept()
        recept.naam = tekst(object["name"]) ?? tekst(object["headline"]) ?? ""
        recept.beschrijving = tekst(object["description"]) ?? ""
        recept.porties = porties(object["recipeYield"] ?? object["yield"])
        recept.voorbereidingMinuten = minuten(object["prepTime"] as? String)
        recept.kookMinuten = minuten(object["cookTime"] as? String)
        recept.totaalMinuten = minuten(object["totalTime"] as? String)
        recept.ingredienten = ingredienten(object["recipeIngredient"] ?? object["ingredients"])
        recept.stapgroepen = stapgroepen(los(object["recipeInstructions"]), index: index)
        recept.afbeelding = afbeelding(los(object["image"]), index: index, basis: basis)
        recept.auteur = naam(los(object["author"]), index: index)
        recept.uitgever = naam(los(object["publisher"]), index: index)
        return recept
    }

    // MARK: - Velden

    /// Platte tekst uit een JSON-waarde (tekst, getal, of een lijst daarvan: de eerste).
    static func tekst(_ waarde: Any?) -> String? {
        switch waarde {
        case let tekst as String:
            let schoon = HTMLTekst.schoon(tekst)
            return schoon.isEmpty ? nil : schoon
        case let getal as NSNumber:
            return getal.stringValue
        case let lijst as [Any]:
            return lijst.lazy.compactMap { tekst($0) }.first
        default:
            return nil
        }
    }

    /// `"4"`, `4`, `"4 personen"`, `["4", "4 servings"]`, `"Voor 4-6 personen"` → 4. Onbekend: 0.
    static func porties(_ waarde: Any?) -> Int {
        switch waarde {
        case let getal as NSNumber:
            return max(0, getal.intValue)
        case let tekst as String:
            guard let bereik = tekst.range(of: #"\d+"#, options: .regularExpression) else { return 0 }
            return Int(tekst[bereik]) ?? 0
        case let lijst as [Any]:
            return lijst.lazy.map { porties($0) }.first { $0 > 0 } ?? 0
        case let object as [String: Any]:
            return porties(object["value"] ?? object["name"])
        default:
            return 0
        }
    }

    private static let duurRegex = try! NSRegularExpression(
        pattern:
            #"^P(?:(\d+(?:[.,]\d+)?)D)?(?:T(?:(\d+(?:[.,]\d+)?)H)?(?:(\d+(?:[.,]\d+)?)M)?(?:(\d+(?:[.,]\d+)?)S)?)?$"#,
        options: .caseInsensitive)

    /// ISO 8601-duur in minuten: `PT1H15M` → 75, `P0DT0H20M` → 20, `PT90M` → 90, `PT45S` → 1.
    /// Onbekend of leeg: 0.
    static func minuten(_ iso: String?) -> Int {
        guard let iso = iso?.trimmingCharacters(in: .whitespaces), !iso.isEmpty else { return 0 }
        let ns = iso as NSString
        guard let treffer = duurRegex.firstMatch(in: iso, range: NSRange(location: 0, length: ns.length)) else {
            return 0
        }
        func deel(_ groep: Int) -> Double {
            let bereik = treffer.range(at: groep)
            guard bereik.location != NSNotFound else { return 0 }
            return Double(ns.substring(with: bereik).replacingOccurrences(of: ",", with: ".")) ?? 0
        }
        let totaal = deel(1) * 1440 + deel(2) * 60 + deel(3) + deel(4) / 60
        return Int(totaal.rounded(.up))
    }

    static func ingredienten(_ waarde: Any?) -> [String] {
        let regels: [String]
        switch waarde {
        case let lijst as [Any]:
            regels = lijst.flatMap { element -> [String] in
                if let tekst = element as? String { return HTMLTekst.platteTekst(tekst).components(separatedBy: "\n") }
                if let object = element as? [String: Any], let naam = tekst(object["name"] ?? object["text"]) {
                    return [naam]
                }
                return []
            }
        case let tekst as String:
            regels = HTMLTekst.platteTekst(tekst).components(separatedBy: "\n")
        default:
            regels = []
        }
        return regels.map { IngredientParser.zonderOpsommingsteken($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// `recipeInstructions` als tekst, lijst van teksten, `HowToStep`'s, `HowToSection`'s (groepen) of
    /// `ItemList`. Een nummer vooraan ("1. Snijd …") gaat eraf: de app nummert zelf.
    static func stapgroepen(_ waarde: Any?, index: [String: [String: Any]] = [:]) -> [SchemaRecept.Stapgroep] {
        var groepen: [SchemaRecept.Stapgroep] = []
        func voegToe(_ stappen: [String], groep: String?) {
            let stappen = stappen.map(schoonStap).filter { !$0.isEmpty && !isStapLabel($0) }
            guard !stappen.isEmpty else { return }
            if let laatste = groepen.last, laatste.naam == groep {
                groepen[groepen.count - 1].stappen += stappen
            } else {
                groepen.append(SchemaRecept.Stapgroep(naam: groep, stappen: stappen))
            }
        }
        func loop(_ waarde: Any?, groep: String?, diepte: Int) {
            guard diepte < 8 else { return }
            switch waarde {
            case let tekst as String:
                voegToe(stappen(uitTekst: tekst), groep: groep)
            case let lijst as [Any]:
                for element in lijst { loop(element, groep: groep, diepte: diepte + 1) }
            case var object as [String: Any]:
                if let id = object["@id"] as? String, object.count == 1, let gevonden = index[id] { object = gevonden }
                if heeftType(object, "howtosection") {
                    let naam = tekst(object["name"]) ?? groep
                    loop(object["itemListElement"] ?? object["steps"], groep: naam, diepte: diepte + 1)
                } else if heeftType(object, "itemlist") {
                    loop(object["itemListElement"], groep: groep, diepte: diepte + 1)
                } else if let tekst = object["text"] as? String {
                    voegToe(stappen(uitTekst: tekst), groep: groep)
                } else if let lijst = object["itemListElement"] {
                    loop(lijst, groep: groep, diepte: diepte + 1)
                } else if let naam = object["name"] as? String {
                    voegToe(stappen(uitTekst: naam), groep: groep)
                }
            default:
                break
            }
        }
        loop(waarde, groep: nil, diepte: 0)
        return groepen
    }

    /// Eén tekstveld: lijstjes en alinea's worden aparte stappen; één lange lap tekst knipt
    /// `StapSplitser` op zinnen.
    private static func stappen(uitTekst tekst: String) -> [String] {
        let regels = HTMLTekst.platteTekst(tekst).components(separatedBy: "\n").filter { !$0.isEmpty }
        if regels.count == 1, let enige = regels.first, enige.count > StapSplitser.doelLengte {
            return StapSplitser.stappen(in: enige)
        }
        return regels
    }

    private static func schoonStap(_ stap: String) -> String {
        ReceptOpbouw.zonderNummer(IngredientParser.zonderOpsommingsteken(HTMLTekst.schoon(stap)))
    }

    /// "Stap 1", "Step 2": een label, geen stap.
    private static func isStapLabel(_ tekst: String) -> Bool {
        tekst.range(of: #"^(stap|step)\s*\d+[.:]?$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// De eerste afbeelding: een URL, een `ImageObject` (`url`/`contentUrl`) of een lijst daarvan.
    static func afbeelding(_ waarde: Any?, index: [String: [String: Any]] = [:], basis: URL?) -> URL? {
        switch waarde {
        case let tekst as String:
            let schoon = HTMLTekst.entiteiten(tekst).trimmingCharacters(in: .whitespaces)
            guard !schoon.isEmpty, let url = URL(string: schoon, relativeTo: basis)?.absoluteURL,
                ["http", "https"].contains(url.scheme?.lowercased() ?? "")
            else { return nil }
            return url
        case let lijst as [Any]:
            return lijst.lazy.compactMap { afbeelding($0, index: index, basis: basis) }.first
        case var object as [String: Any]:
            if let id = object["@id"] as? String, object["url"] == nil, object["contentUrl"] == nil,
                let gevonden = index[id]
            {
                object = gevonden
            }
            return afbeelding(object["url"] ?? object["contentUrl"], index: index, basis: basis)
        default:
            return nil
        }
    }

    /// De naam van een `Person` of `Organization` (of de eerste in een lijst), of een tekst.
    static func naam(_ waarde: Any?, index: [String: [String: Any]] = [:]) -> String? {
        switch waarde {
        case let tekst as String:
            let schoon = HTMLTekst.schoon(tekst)
            return schoon.isEmpty || schoon.hasPrefix("http") ? nil : schoon
        case let lijst as [Any]:
            return lijst.lazy.compactMap { naam($0, index: index) }.first
        case var object as [String: Any]:
            if let id = object["@id"] as? String, object["name"] == nil, let gevonden = index[id] { object = gevonden }
            return tekst(object["name"])
        default:
            return nil
        }
    }

    /// Zegt de pagina zelf dat hij achter een betaalmuur staat (`"isAccessibleForFree": false`)?
    /// `nil` als de pagina er niets over zegt.
    static func isGratis(in html: String) -> Bool? {
        var uitkomst: Bool?
        func loop(_ waarde: Any, diepte: Int) {
            guard diepte < 12 else { return }
            if let object = waarde as? [String: Any] {
                for (sleutel, kind) in object {
                    if sleutel == "isAccessibleForFree" {
                        let gratis: Bool? =
                            (kind as? Bool)
                            ?? (kind as? String).flatMap { ["true": true, "false": false][$0.lowercased()] }
                        if let gratis { uitkomst = (uitkomst ?? true) && gratis }
                    } else {
                        loop(kind, diepte: diepte + 1)
                    }
                }
            } else if let lijst = waarde as? [Any] {
                for kind in lijst { loop(kind, diepte: diepte + 1) }
            }
        }
        for blok in jsonLD(in: html) { loop(blok, diepte: 0) }
        return uitkomst
    }

    // MARK: - Microdata

    /// Terugval voor sites zonder JSON-LD: `itemscope itemtype="https://schema.org/Recipe"` met
    /// `itemprop`'s erin.
    static func microdata(in html: String, basis: URL?) -> SchemaRecept? {
        guard
            let scope = HTMLTekst.elementen(
                in: html,
                waar: { _, attributen in
                    attributen["itemtype"]?.lowercased().hasSuffix("schema.org/recipe") == true
                }
            ).first
        else { return nil }
        var binnen = scope.binnen

        func metProp(_ namen: Set<String>, in html: String) -> [HTMLTekst.Element] {
            HTMLTekst.elementen(in: html) { _, attributen in
                guard let props = attributen["itemprop"] else { return false }
                return props.split(separator: " ").contains { namen.contains(String($0)) }
            }
        }
        func waarde(_ element: HTMLTekst.Element) -> String {
            let a = element.attributen
            return HTMLTekst.schoon(a["content"] ?? a["datetime"] ?? element.binnen)
        }

        var recept = SchemaRecept()
        // Stappen eerst: die zijn soms zelf `HowToStep`-scopes met een eigen `itemprop="text"`.
        for element in metProp(["recipeInstructions"], in: binnen) {
            let lijstjes = HTMLTekst.elementen(in: element.binnen) { naam, _ in naam == "li" }
            let teksten = metProp(["text"], in: element.binnen)
            let stappen =
                !teksten.isEmpty
                ? teksten.map { $0.binnen } : !lijstjes.isEmpty ? lijstjes.map(\.binnen) : [element.binnen]
            recept.stapgroepen += stapgroepen(stappen.map { $0 as Any })
        }
        recept.ingredienten = metProp(["recipeIngredient", "ingredients"], in: binnen).map(waarde)
            .map { IngredientParser.zonderOpsommingsteken($0) }.filter { !$0.isEmpty }
        recept.afbeelding =
            metProp(["image"], in: binnen).lazy.compactMap { element -> URL? in
                let a = element.attributen
                return afbeelding(a["src"] ?? a["content"] ?? a["href"], basis: basis)
            }.first
        recept.porties = metProp(["recipeYield"], in: binnen).lazy.map { porties(waarde($0)) }.first { $0 > 0 } ?? 0
        recept.voorbereidingMinuten = metProp(["prepTime"], in: binnen).first.map { minuten(waarde($0)) } ?? 0
        recept.kookMinuten = metProp(["cookTime"], in: binnen).first.map { minuten(waarde($0)) } ?? 0
        recept.totaalMinuten = metProp(["totalTime"], in: binnen).first.map { minuten(waarde($0)) } ?? 0
        recept.auteur = metProp(["author"], in: binnen).first.map(waarde).flatMap { $0.isEmpty ? nil : $0 }

        // Naam en beschrijving: niet die van een geneste scope (de auteur heeft ook een `name`).
        for genest in HTMLTekst.elementen(in: binnen, waar: { _, a in a["itemscope"] != nil })
        where !genest.binnen.isEmpty {
            binnen = binnen.replacingOccurrences(of: genest.binnen, with: "")
        }
        recept.naam = metProp(["name"], in: binnen).first.map(waarde) ?? ""
        recept.beschrijving = metProp(["description"], in: binnen).first.map(waarde) ?? ""
        return recept
    }

    // MARK: - Naar het controlescherm

    /// Het concept voor het controlescherm. Ingrediënten en stappen blijven letterlijk; een kopje als
    /// "Voor de saus:" in de ingrediënten wordt bij bewaren de groep (`ReceptInvoer`).
    static func concept(_ recept: SchemaRecept) -> ReceptConcept {
        var concept = ReceptConcept()
        concept.titel = recept.naam
        concept.intro = recept.beschrijving
        concept.porties = recept.porties
        concept.minuten = recept.minuten
        concept.ingredienten = recept.ingredienten.map { ConceptRegel(tekst: $0) }
        concept.stappen = recept.stapgroepen.flatMap { groep in
            groep.stappen.map { ConceptRegel(tekst: $0, groep: groep.naam) }
        }
        return concept
    }
}
