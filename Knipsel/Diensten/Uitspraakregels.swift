import Foundation

/// Maakt recepttekst uitspreekbaar voor het voorlezen (K9): `2 el` → "twee eetlepels", `½ tl` → "een halve
/// theelepel", `ca.` → "circa", `180 °C` → "180 graden", `3-4` → "drie à vier". Puur en zonder AVFoundation,
/// zodat het overal te testen is.
///
/// Uitgangspunten:
/// - Een eenheid wordt alleen vervangen direct na een getal: de "g" in "gember" en de "el" in "mello" blijven staan.
/// - Getallen blijven cijfers (de stem spreekt die goed uit), behalve bij lepels en bereiken, waar het
///   uitgeschreven getal natuurlijker klinkt ("twee eetlepels", "drie à vier"), en bij breuken.
/// - Wat niet herkend wordt, blijft letterlijk staan.
enum Uitspraakregels {
    /// De tekst zoals hij voorgelezen wordt.
    static func uitspreekbaar(_ tekst: String) -> String {
        afkortingen(hoeveelheden(tekst))
    }

    // MARK: - Hoeveelheden met eenheid

    /// Een eenheid: enkelvoud en meervoud zoals ze uitgesproken worden.
    private struct Eenheid {
        let enkelvoud: String
        let meervoud: String
        /// Lepels: "twee eetlepels" in plaats van "2 eetlepels".
        var uitschrijven = false
        /// Het-woord: "anderhalf uur", niet "anderhalve uur".
        var isHetWoord = false
    }

    /// Afkorting (kleine letters, zonder punt) → eenheid.
    private static let eenheden: [String: Eenheid] = {
        let eetlepel = Eenheid(enkelvoud: "eetlepel", meervoud: "eetlepels", uitschrijven: true)
        let theelepel = Eenheid(enkelvoud: "theelepel", meervoud: "theelepels", uitschrijven: true)
        let koffielepel = Eenheid(enkelvoud: "koffielepel", meervoud: "koffielepels", uitschrijven: true)
        let liter = Eenheid(enkelvoud: "liter", meervoud: "liter")
        let gram = Eenheid(enkelvoud: "gram", meervoud: "gram")
        let kilo = Eenheid(enkelvoud: "kilo", meervoud: "kilo")
        let minuut = Eenheid(enkelvoud: "minuut", meervoud: "minuten")
        let seconde = Eenheid(enkelvoud: "seconde", meervoud: "seconden")
        let uur = Eenheid(enkelvoud: "uur", meervoud: "uur", isHetWoord: true)
        let persoon = Eenheid(enkelvoud: "persoon", meervoud: "personen")
        let graden = Eenheid(enkelvoud: "graden", meervoud: "graden")
        return [
            "el": eetlepel, "eetl": eetlepel, "eetlepel": eetlepel, "eetlepels": eetlepel,
            "tl": theelepel, "theel": theelepel, "theelepel": theelepel, "theelepels": theelepel,
            "kl": koffielepel,
            "l": liter, "ltr": liter, "liter": liter,
            "ml": Eenheid(enkelvoud: "milliliter", meervoud: "milliliter"),
            "cl": Eenheid(enkelvoud: "centiliter", meervoud: "centiliter"),
            "dl": Eenheid(enkelvoud: "deciliter", meervoud: "deciliter"),
            "g": gram, "gr": gram, "gram": gram,
            "mg": Eenheid(enkelvoud: "milligram", meervoud: "milligram"),
            "kg": kilo, "kilo": kilo,
            "cm": Eenheid(enkelvoud: "centimeter", meervoud: "centimeter"),
            "mm": Eenheid(enkelvoud: "millimeter", meervoud: "millimeter"),
            "min": minuut, "minuut": minuut, "minuten": minuut,
            "sec": seconde, "seconde": seconde, "seconden": seconde,
            "u": uur, "uur": uur,
            "pers": persoon, "personen": persoon, "persoon": persoon,
            "°c": graden, "°": graden, "graden": graden, "graden c": graden,
        ]
    }()

    private static let breukTekens = "½¼¾⅓⅔"
    /// Eén hoeveelheid: "1 1/2", "1/2", "1½", "½", "2", "1,5".
    private static let getal = #"\d+ \d/\d(?!\d)|\d+/\d+|\d+(?:,\d+)?(?: ?[½¼¾⅓⅔])?|[½¼¾⅓⅔]"#
    /// Langste vormen eerst, zodat "gram" niet als "g" + "ram" gelezen wordt.
    private static let eenheidPatroon =
        #"eetlepels|eetlepel|theelepels|theelepel|eetl|theel|el|tl|kl|liter|ltr|ml|cl|dl|l|gram|gr|mg|kg|kilo|g|"#
        + #"cm|mm|minuten|minuut|min|seconden|seconde|sec|uur|u|personen|persoon|pers|graden ?C|graden|° ?C|°"#

    private static let hoeveelheidRegex = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\d.,/\-–])"#
            + "(?<van>\(getal))"
            // Een bereik, maar geen datum (13-11-2026).
            + #"(?:(?:\s?[\-–]\s?|\s+à\s+)(?<tot>"# + getal + #")(?![\-–/\d]))?"#
            + "(?:\\s?(?<eenheid>\(eenheidPatroon))(?<punt>\\.)?(?![\\p{L}\\d]))?",
        options: [.caseInsensitive])

    private static func hoeveelheden(_ tekst: String) -> String {
        vervang(hoeveelheidRegex, in: tekst) { ns, treffer in
            let origineel = ns.substring(with: treffer.range)
            let van = deel(ns, treffer, "van")!
            let tot = deel(ns, treffer, "tot")
            let afkorting = deel(ns, treffer, "eenheid")
            let eenheid = afkorting.flatMap {
                eenheden[$0.lowercased().replacingOccurrences(of: "° c", with: "°c")]
            }
            // Wat er na de hoeveelheid volgt, bepaalt "halve" of "half".
            let rest = ns.substring(from: treffer.range.location + treffer.range.length)
            let volgendWoord = eenheid.map(\.enkelvoud) ?? eersteWoord(rest)
            let hetWoord = eenheid?.isHetWoord ?? volgendWoord.map(isHetWoord) ?? true

            guard let vanGetal = Hoeveelheid(van) else { return origineel }
            let totGetal = tot.flatMap(Hoeveelheid.init)
            // Een los heel getal zonder eenheid of bereik ("stap 2", "in 4 stukken") blijft staan.
            if eenheid == nil, totGetal == nil, vanGetal.breuk == nil { return origineel }

            var uitspraak: String
            var enkelvoud: Bool
            if let totGetal {
                uitspraak =
                    "\(vanGetal.uitgesproken(uitschrijven: true, hetWoord: hetWoord)) à "
                    + totGetal.uitgesproken(uitschrijven: true, hetWoord: hetWoord)
                enkelvoud = totGetal.isEnkelvoud
            } else {
                uitspraak = vanGetal.uitgesproken(uitschrijven: eenheid?.uitschrijven ?? false, hetWoord: hetWoord)
                enkelvoud = vanGetal.isEnkelvoud
            }
            if let eenheid {
                uitspraak += " " + (enkelvoud ? eenheid.enkelvoud : eenheid.meervoud)
                // Een afkortingspunt valt weg; een punt aan het eind van de zin blijft.
                if deel(ns, treffer, "punt") != nil, isZinseinde(rest) { uitspraak += "." }
            }
            return uitspraak
        }
    }

    /// Een hoeveelheid uit de tekst: geheel getal, breuk of allebei; of een kommagetal dat blijft staan.
    private struct Hoeveelheid {
        var geheel: Int?
        var breuk: Character?
        var letterlijk: String?

        init?(_ tekst: String) {
            var tekst = tekst
            // "1 1/2": eerst het gehele deel.
            if tekst.contains("/"), let spatie = tekst.firstIndex(of: " ") {
                guard let getal = Int(tekst[..<spatie]) else { return nil }
                geheel = getal
                tekst = String(tekst[tekst.index(after: spatie)...])
            }
            tekst = tekst.replacingOccurrences(of: " ", with: "")
            if tekst.contains("/") {
                let delen = tekst.split(separator: "/").compactMap { Int($0) }
                guard delen.count == 2 else { return nil }
                switch (delen[0], delen[1]) {
                case (1, 2): breuk = "½"
                case (1, 4): breuk = "¼"
                case (3, 4): breuk = "¾"
                case (1, 3): breuk = "⅓"
                case (2, 3): breuk = "⅔"
                default: letterlijk = (geheel.map { "\($0) " } ?? "") + tekst
                }
                return
            }
            if tekst.contains(",") {
                letterlijk = tekst
                return
            }
            if let laatste = tekst.last, Uitspraakregels.breukTekens.contains(laatste) {
                breuk = laatste
                let voor = tekst.dropLast()
                if !voor.isEmpty {
                    guard let getal = Int(voor) else { return nil }
                    geheel = getal
                }
                return
            }
            guard let getal = Int(tekst) else { return nil }
            geheel = getal
        }

        /// "1 eetlepel", "een halve eetlepel", "anderhalve eetlepel": enkelvoud. "2 eetlepels": meervoud.
        var isEnkelvoud: Bool {
            if letterlijk != nil { return false }
            if breuk != nil { return true }
            return geheel == 1
        }

        func uitgesproken(uitschrijven: Bool, hetWoord: Bool) -> String {
            if let letterlijk { return letterlijk }
            let half = hetWoord ? "half" : "halve"
            guard let breuk else {
                return Uitspraakregels.getalwoord(geheel ?? 0, uitschrijven: uitschrijven)
            }
            let breukwoord: String
            switch breuk {
            case "½": breukwoord = "een \(half)"
            case "¼": breukwoord = "een kwart"
            case "¾": breukwoord = "driekwart"
            case "⅓": breukwoord = "een derde"
            default: breukwoord = "twee derde"
            }
            guard let geheel, geheel > 0 else { return breukwoord }
            if geheel == 1, breuk == "½" { return "ander\(half)" }
            // "2½ uur" → "twee en een half uur": met cijfers ervoor klinkt het als een opsomming.
            return "\(Uitspraakregels.getalwoord(geheel, uitschrijven: true)) en \(breukwoord)"
        }
    }

    private static let telwoorden = [
        "nul", "één", "twee", "drie", "vier", "vijf", "zes", "zeven", "acht", "negen", "tien", "elf", "twaalf",
        "dertien", "veertien", "vijftien", "zestien", "zeventien", "achttien", "negentien", "twintig",
    ]

    /// 2 → "twee" (tot en met twintig, als `uitschrijven`), anders als cijfers.
    static func getalwoord(_ getal: Int, uitschrijven: Bool) -> String {
        uitschrijven && telwoorden.indices.contains(getal) ? telwoorden[getal] : String(getal)
    }

    /// Het-woorden die na "half" kunnen volgen; verkleinwoorden (-je) zijn altijd het-woorden.
    private static let hetWoorden: Set<String> = [
        "uur", "ons", "pond", "blik", "pak", "glas", "stuk", "ei", "brood", "kopje", "bord",
    ]

    private static func isHetWoord(_ woord: String) -> Bool {
        let woord = woord.lowercased()
        return hetWoorden.contains(woord) || woord.hasSuffix("je")
    }

    private static func eersteWoord(_ tekst: String) -> String? {
        let woord = tekst.drop { $0 == " " }.prefix { $0.isLetter }
        return woord.isEmpty ? nil : String(woord)
    }

    /// Volgt er niets meer, of een nieuwe zin met een hoofdletter?
    private static func isZinseinde(_ rest: String) -> Bool {
        let na = rest.drop { $0 == " " || $0 == "\n" }
        guard let eerste = na.first else { return true }
        return rest.first?.isWhitespace == true && eerste.isUppercase
    }

    // MARK: - Afkortingen

    /// Afkorting (zonder punt) → voluit. Alleen als los woord met punt; "ca" en "±" ook zonder.
    private static let afkortingenLijst: [(String, String)] = [
        ("o.a", "onder andere"), ("ca", "circa"), ("evt", "eventueel"), ("bijv", "bijvoorbeeld"),
        ("bv", "bijvoorbeeld"), ("ong", "ongeveer"), ("enz", "enzovoort"), ("pers", "personen"),
        ("max", "maximaal"), ("incl", "inclusief"), ("excl", "exclusief"), ("resp", "respectievelijk"),
    ]

    private static let afkortingRegex = try! NSRegularExpression(
        pattern: #"(?<![\p{L}.])(?<afk>"#
            + afkortingenLijst.map { NSRegularExpression.escapedPattern(for: $0.0) }.joined(separator: "|")
            + #")(?:(?<punt>\.)|(?=\s+\d))(?!\p{L})"#,
        options: [.caseInsensitive])

    private static let plusMinRegex = try! NSRegularExpression(pattern: #"±\s?"#)
    /// "t/m" en "v.a." hebben een schuine streep of twee punten; apart van de lijst hierboven.
    private static let totEnMetRegex = try! NSRegularExpression(
        pattern: #"(?<![\p{L}/])t\s?/\s?m(?![\p{L}/])\.?"#, options: [.caseInsensitive])

    private static func afkortingen(_ tekst: String) -> String {
        let voluit = Dictionary(uniqueKeysWithValues: afkortingenLijst)
        let tekst = vervang(afkortingRegex, in: tekst) { ns, treffer in
            let afkorting = deel(ns, treffer, "afk")!
            guard var woord = voluit[afkorting.lowercased()] else { return ns.substring(with: treffer.range) }
            if afkorting.first?.isUppercase == true { woord = woord.prefix(1).uppercased() + woord.dropFirst() }
            let rest = ns.substring(from: treffer.range.location + treffer.range.length)
            if deel(ns, treffer, "punt") != nil, isZinseinde(rest) { woord += "." }
            return woord
        }
        let zonderPlusMin = vervang(plusMinRegex, in: tekst) { _, _ in "ongeveer " }
        return vervang(totEnMetRegex, in: zonderPlusMin) { _, _ in "tot en met" }
    }

    // MARK: - Hulpjes

    private static func deel(_ ns: NSString, _ treffer: NSTextCheckingResult, _ naam: String) -> String? {
        let bereik = treffer.range(withName: naam)
        return bereik.location == NSNotFound ? nil : ns.substring(with: bereik)
    }

    /// Vervangt elke treffer door wat `door` teruggeeft, van achter naar voren.
    private static func vervang(
        _ regex: NSRegularExpression, in tekst: String, door: (NSString, NSTextCheckingResult) -> String
    ) -> String {
        let ns = tekst as NSString
        let uit = NSMutableString(string: tekst)
        for treffer in regex.matches(in: tekst, range: NSRange(location: 0, length: ns.length)).reversed() {
            uit.replaceCharacters(in: treffer.range, with: door(ns, treffer))
        }
        return uit as String
    }
}
