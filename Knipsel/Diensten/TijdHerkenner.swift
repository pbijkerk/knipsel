import Foundation

/// Een tijd in een staptekst: "20 minuten", "1½ uur", "10-15 min".
struct Tijdvermelding: Equatable, Sendable {
    /// Seconden voor de timer; bij een bereik de bovengrens ("10-15 min" → 900).
    let seconden: Int
    /// Ondergrens bij een bereik ("10-15 min" → 600), anders `nil`.
    let vanaf: Int?
    /// Waar de tijd in de tekst staat.
    let bereik: Range<String.Index>
    /// De letterlijke tekst: "10-15 min".
    let tekst: String

    var isBereik: Bool { vanaf != nil }

    /// Voor in beeld: "20 min", "1 u 30 min", "10–15 min".
    var label: String { Tijdweergave.label(seconden: seconden, vanaf: vanaf) }
}

/// Haalt tijden uit een staptekst (K11). Puur, zonder taalmodel: getallen in cijfers en woorden
/// ("twintig", "anderhalf", "een half", "drie kwartier"), met een eenheid erachter (uur, u, minuten,
/// min., seconden, sec., kwartier). Een bereik ("10-15 min", "10 à 15 minuten", "5 of 6 minuten")
/// geeft de bovengrens als timer; "1 uur en 15 minuten" en "1 u 15 min" worden één tijd; "een minuut
/// of vijf" is vijf minuten.
///
/// Telt niet: getallen zonder tijdeenheid (temperaturen "180 °C", "2 el", jaartallen), kloktijden
/// ("om 18.00 uur", "om 3 uur").
enum TijdHerkenner {
    /// Alle tijden in `tekst`, op volgorde.
    static func tijden(in tekst: String) -> [Tijdvermelding] {
        let ns = tekst as NSString
        var termen: [Term] = []
        for treffer in patroon.matches(in: tekst, range: NSRange(location: 0, length: ns.length)) {
            if let term = term(uit: treffer, in: ns) { termen.append(term) }
        }
        return voegSamen(termen, in: ns).compactMap { term in
            guard term.seconden > 0, term.seconden <= maximum,
                let bereik = Range(term.bereik, in: tekst)
            else { return nil }
            return Tijdvermelding(
                seconden: term.seconden, vanaf: term.vanaf, bereik: bereik, tekst: String(tekst[bereik]))
        }
    }

    /// De tijd voor de timer van een stap: de langste ("bak 2 minuten mee … laat 20 minuten koken" →
    /// 20 minuten). Bij gelijke tijden de eerste.
    static func hoofdtijd(in tekst: String) -> Tijdvermelding? {
        tijden(in: tekst).reduce(nil) { beste, tijd in
            guard let beste else { return tijd }
            return tijd.seconden > beste.seconden ? tijd : beste
        }
    }

    /// Voor `Stap.timerSeconden`: de hoofdtijd in seconden, 0 = geen tijd.
    static func timerSeconden(in tekst: String) -> Int {
        hoofdtijd(in: tekst)?.seconden ?? 0
    }

    /// Langer dan drie dagen is geen kooktimer meer.
    static let maximum = 72 * 3600

    // MARK: - Patroon

    private struct Term {
        var seconden: Int
        var vanaf: Int?
        var bereik: NSRange
        /// 3 = uur, 2 = kwartier, 1 = minuut, 0 = seconde; om "1 uur en 15 minuten" samen te voegen.
        var rang: Int
    }

    private static let eenheden: [(patroon: String, seconden: Double, rang: Int)] = [
        ("uurtjes|uurtje|uren|uur|u", 3600, 3),
        ("kwartiertje|kwartier", 900, 2),
        ("minuutjes|minuutje|minuten|minuut|mins|min", 60, 1),
        ("seconden|seconde|secondes|sec", 1, 0),
    ]

    /// Getallen in woorden, langste eerst (anders wint "acht" van "achttien").
    private static let woordgetallen: [String: Double] = {
        let eenheden = ["een", "twee", "drie", "vier", "vijf", "zes", "zeven", "acht", "negen"]
        var tabel: [String: Double] = [
            "één": 1, "tien": 10, "elf": 11, "twaalf": 12, "dertien": 13, "veertien": 14, "vijftien": 15,
            "zestien": 16, "zeventien": 17, "achttien": 18, "negentien": 19, "twintig": 20, "dertig": 30,
            "veertig": 40, "vijftig": 50, "zestig": 60, "zeventig": 70, "tachtig": 80, "negentig": 90,
            "anderhalf": 1.5, "anderhalve": 1.5, "half": 0.5, "halve": 0.5, "een half": 0.5, "een halve": 0.5,
            "één half": 0.5,
        ]
        for (index, woord) in eenheden.enumerated() {
            tabel[woord] = Double(index + 1)
            for (tiental, waarde) in [("twintig", 20.0), ("dertig", 30), ("veertig", 40), ("vijftig", 50)] {
                tabel[woord + "en" + tiental] = waarde + Double(index + 1)
                // "tweeëntwintig", "drieënveertig".
                if woord.hasSuffix("e") { tabel[woord + "ën" + tiental] = waarde + Double(index + 1) }
            }
        }
        return tabel
    }()

    private static let getal: String = {
        let woorden = woordgetallen.keys.sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0).replacingOccurrences(of: " ", with: "\\s+") }
        let cijfers = "\\d+(?:[.,]\\d+)?(?:\\s?[½¼¾]|\\s\\d/\\d)?|\\d/\\d|[½¼¾]"
        return "(?:\(cijfers)|\(woorden.joined(separator: "|")))"
    }()

    private static let eenheid = "(?:" + eenheden.map(\.patroon).joined(separator: "|") + ")"

    /// Groepen: 1–2 = "een minuut of vijf" (eenheid, getal); 3–5 = getal, getal tot, eenheid.
    private static let patroon: NSRegularExpression = {
        let grens = "(?<![\\p{L}\\p{N}])"
        let einde = "(?![\\p{L}\\p{N}])"
        let tussen = "\\s*(?:-|–|—|tot|à|a|of)\\s*"
        let ongeveer = "(?:een|één)\\s+(minuutje|minuut|uurtje|uur)\\s+of\\s+(\(getal))"
        let gewoon = "(\(getal))(?:\(tussen)(\(getal)))?\\s?(\(eenheid))"
        let kwartier = "(kwartiertje|kwartier)"
        let tekst = "\(grens)(?:\(ongeveer)\(einde)|\(gewoon)\(einde)|\(kwartier)\(einde))"
        return try! NSRegularExpression(pattern: tekst, options: [.caseInsensitive])
    }()

    private static func term(uit treffer: NSTextCheckingResult, in tekst: NSString) -> Term? {
        func groep(_ index: Int) -> String? {
            let bereik = treffer.range(at: index)
            return bereik.location == NSNotFound ? nil : tekst.substring(with: bereik)
        }
        if let eenheidTekst = groep(1), let getalTekst = groep(2) {
            guard let getal = waarde(getalTekst), let maat = eenheid(eenheidTekst) else { return nil }
            return Term(seconden: Int((getal * maat.seconden).rounded()), bereik: treffer.range, rang: maat.rang)
        }
        if let getalTekst = groep(3), let eenheidTekst = groep(5) {
            guard let getal = waarde(getalTekst), let maat = eenheid(eenheidTekst) else { return nil }
            if isKloktijd(getalTekst, rang: maat.rang, voor: treffer.range, in: tekst) { return nil }
            let boven = groep(4).flatMap { waarde($0) }
            let seconden = Int(((boven ?? getal) * maat.seconden).rounded())
            let vanaf = boven.map { _ in Int((getal * maat.seconden).rounded()) }
            // "5-3 minuten" is geen bereik; dan alleen de laatste.
            if let vanaf, vanaf >= seconden { return Term(seconden: seconden, bereik: treffer.range, rang: maat.rang) }
            return Term(seconden: seconden, vanaf: vanaf, bereik: treffer.range, rang: maat.rang)
        }
        if groep(6) != nil {
            return Term(seconden: 900, vanaf: nil, bereik: treffer.range, rang: 2)
        }
        return nil
    }

    /// "om 18.00 uur", "om 3 uur", "18:30 uur": een tijdstip, geen duur.
    private static func isKloktijd(_ getal: String, rang: Int, voor bereik: NSRange, in tekst: NSString) -> Bool {
        guard rang == 3 else { return false }
        if getal.range(of: "^\\d{1,2}[.:]\\d{2}$", options: .regularExpression) != nil { return true }
        let ervoor = tekst.substring(to: bereik.location).lowercased()
        return ervoor.range(of: "(?:^|[^\\p{L}])(?:om|vanaf)\\s+$", options: .regularExpression) != nil
    }

    private static func eenheid(_ tekst: String) -> (seconden: Double, rang: Int)? {
        let klein = tekst.lowercased()
        for eenheid in eenheden
        where klein.range(of: "^(?:\(eenheid.patroon))$", options: .regularExpression) != nil {
            return (eenheid.seconden, eenheid.rang)
        }
        return nil
    }

    /// "1,5" → 1.5, "1½" → 1.5, "1 1/2" → 1.5, "anderhalf" → 1.5, "twintig" → 20.
    static func waarde(_ tekst: String) -> Double? {
        let klein = tekst.lowercased().replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if let woord = woordgetallen[klein] { return woord }
        var rest = klein
        var breuk = 0.0
        for (teken, waarde) in [("½", 0.5), ("¼", 0.25), ("¾", 0.75)] where rest.hasSuffix(teken) {
            breuk = waarde
            rest = String(rest.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        if let streep = rest.range(of: "\\d/\\d$", options: .regularExpression) {
            let delen = rest[streep].split(separator: "/").compactMap { Double($0) }
            guard delen.count == 2, delen[1] > 0 else { return nil }
            breuk = delen[0] / delen[1]
            rest = String(rest[..<streep.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        if rest.isEmpty { return breuk > 0 ? breuk : nil }
        guard let geheel = Double(rest.replacingOccurrences(of: ",", with: ".")) else { return nil }
        return geheel + breuk
    }

    /// "1 uur en 15 minuten", "1 u 15 min", "2 minuten en 30 seconden": aflopende eenheden met alleen
    /// "en" of witruimte ertussen worden één tijd.
    private static func voegSamen(_ termen: [Term], in tekst: NSString) -> [Term] {
        var resultaat: [Term] = []
        for term in termen {
            if var vorige = resultaat.last, vorige.vanaf == nil, term.vanaf == nil, vorige.rang > term.rang {
                let begin = vorige.bereik.location + vorige.bereik.length
                let tussen = tekst.substring(with: NSRange(location: begin, length: term.bereik.location - begin))
                if tussen.range(of: "^\\s*(?:en)?\\s*$", options: [.regularExpression, .caseInsensitive]) != nil {
                    vorige.seconden += term.seconden
                    vorige.bereik = NSRange(
                        location: vorige.bereik.location,
                        length: term.bereik.location + term.bereik.length - vorige.bereik.location)
                    vorige.rang = term.rang
                    resultaat[resultaat.count - 1] = vorige
                    continue
                }
            }
            resultaat.append(term)
        }
        return resultaat
    }
}
