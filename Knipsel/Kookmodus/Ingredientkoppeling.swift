import Foundation

/// Welke ingrediënten komen in een stap voor? Koppelt op naam: het kernwoord van de ingrediëntnaam
/// ("verse gember" → gember) tegen de woorden van de stap, met eenvoudige normalisatie voor meervoud
/// en verkleinwoord (ui/uien/uitjes) en samenstellingen (bouillon ↔ groentebouillon, olie ↔
/// olijfolie). Liever een ingrediënt missen dan een verkeerd ingrediënt oranje maken.
enum Ingredientkoppeling {
    /// Een woord in de staptekst dat bij een of meer ingrediënten hoort.
    struct Treffer: Equatable, Sendable {
        /// Bereik in de staptekst (UTF-16-offsets, zodat het ook in een AttributedString past).
        let bereik: NSRange
        /// Indices in de ingrediëntenlijst.
        let ingredienten: [Int]
    }

    /// Treffers in `tekst` voor de ingrediënten met deze namen (index = positie in de lijst).
    static func treffers(in tekst: String, namen: [String]) -> [Treffer] {
        let kernen = namen.map(kernwoorden)
        var resultaat: [Treffer] = []
        let ns = tekst as NSString
        for woordtreffer in woordRegex.matches(in: tekst, range: NSRange(location: 0, length: ns.length)) {
            let woord = vouw(ns.substring(with: woordtreffer.range))
            guard woord.count >= 2, !stopwoorden.contains(woord) else { continue }
            let vormen = varianten(woord)
            // Eerst exacte treffers; alleen als die er niet zijn, een samenstelling.
            var gevonden = kernen.indices.filter { i in kernen[i].contains { !$0.isDisjoint(with: vormen) } }
            if gevonden.isEmpty {
                gevonden = kernen.indices.filter { i in
                    kernen[i].contains { kern in kern.contains { k in vormen.contains { isSamenstelling(k, $0) } } }
                }
            }
            if !gevonden.isEmpty {
                resultaat.append(Treffer(bereik: woordtreffer.range, ingredienten: gevonden))
            }
        }
        return resultaat
    }

    /// Indices van de ingrediënten die in `tekst` voorkomen, in lijstvolgorde.
    static func ingredienten(in tekst: String, namen: [String]) -> [Int] {
        Array(Set(treffers(in: tekst, namen: namen).flatMap(\.ingredienten))).sorted()
    }

    // MARK: - Normaliseren

    private static let woordRegex = try! NSRegularExpression(pattern: #"\p{L}+"#)

    /// Per inhoudswoord van de naam de vormen waaronder het in een stap kan staan.
    static func kernwoorden(_ naam: String) -> [Set<String>] {
        let ns = naam as NSString
        return woordRegex.matches(in: naam, range: NSRange(location: 0, length: ns.length))
            .map { vouw(ns.substring(with: $0.range)) }
            .filter { $0.count >= 2 && !stopwoorden.contains($0) && !bijvoeglijk.contains($0) }
            .map(varianten)
    }

    /// Het woord zelf plus mogelijke enkelvoudsvormen: "uien" → ui, "tomaten" → tomaat,
    /// "uitjes" → ui, "kippen" → kip, "courgettes" → courgette.
    static func varianten(_ woord: String) -> Set<String> {
        var vormen: Set<String> = [woord]
        var basis = woord
        for achtervoegsel in ["etjes", "etje", "tjes", "jes", "tje", "je"]
        where basis.hasSuffix(achtervoegsel) && basis.count - achtervoegsel.count >= 2 {
            basis = String(basis.dropLast(achtervoegsel.count))
            vormen.insert(basis)
            break
        }
        if basis == "eieren" { vormen.insert("ei") }
        if basis.hasSuffix("en"), basis.count >= 4 {
            let stam = String(basis.dropLast(2))
            vormen.insert(stam)
            if let laatste = stam.last, let voorlaatste = stam.dropLast().last {
                if laatste == voorlaatste, !klinkers.contains(laatste) {
                    vormen.insert(String(stam.dropLast()))  // kippen → kip
                } else if !klinkers.contains(laatste), klinkers.contains(voorlaatste),
                    !klinkers.contains(stam.dropLast(2).last ?? "a")
                {
                    // tomaten → tomaat: open lettergreep met één klinker.
                    var lang = stam
                    lang.insert(voorlaatste, at: lang.index(before: lang.endIndex))
                    vormen.insert(lang)
                }
            }
        }
        if basis.hasSuffix("s"), basis.count >= 5 { vormen.insert(String(basis.dropLast())) }
        return vormen.filter { $0.count >= 2 }
    }

    /// `kort` is het laatste deel van samenstelling `lang`: bouillon ↔ groentebouillon. Niet voor
    /// heel korte woorden (ui), en niet voor voltooide deelwoorden ("gezouten" is geen zout).
    private static func isSamenstelling(_ a: String, _ b: String) -> Bool {
        let (kort, lang) = a.count <= b.count ? (a, b) : (b, a)
        guard kort.count >= 4, lang.count - kort.count >= 3, lang.hasSuffix(kort) else { return false }
        return !lang.hasPrefix("ge") && !lang.hasPrefix("onge")
    }

    private static let klinkers: Set<Character> = ["a", "e", "i", "o", "u"]

    private static let stopwoorden: Set<String> = [
        "de", "het", "een", "en", "of", "met", "van", "voor", "in", "op", "aan", "uit", "om", "te", "tot", "naar",
        "zonder", "bij", "er", "erbij", "erdoor", "eraan", "toe", "mee", "door", "over", "onder", "tegen", "dan",
        "nog", "ook", "al", "je", "u", "ze", "die", "dat", "wat", "als", "per", "tijdens", "na", "zo", "smaak",
    ]

    /// Bijvoeglijke woorden in ingrediëntnamen; die zijn geen kernwoord ("verse gember" → gember).
    private static let bijvoeglijk: Set<String> = [
        "vers", "verse", "rode", "rood", "witte", "wit", "gele", "geel", "groene", "groen", "zwarte", "zwart",
        "grote", "groot", "kleine", "klein", "fijne", "fijn", "grove", "grof", "gedroogde", "gemalen",
        "geraspte", "gehakte", "gesneden", "gesnipperde", "halve", "hele", "koude", "warme", "lauwe", "zachte",
        "harde", "oude", "jonge", "belegen", "biologische", "ongezouten", "gezouten", "extra", "vierge", "zoete",
        "zure", "platte", "krokante", "gerookte", "gekookte", "rijpe", "stevige", "kruimige", "vastkokende",
        "bloemige", "lichte", "donkere", "volle", "magere", "halfvolle", "gepelde", "ongepelde", "diepvries",
        "bevroren", "naturel", "gezeefde", "fijngehakte", "gemengde",
    ]

    private static func vouw(_ tekst: String) -> String { IngredientParser.vouw(tekst) }
}
