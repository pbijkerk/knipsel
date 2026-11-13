import Foundation

/// Porties schalen: hoeveelheid × factor, afgerond op wat je in de keuken echt afmeet (lepels op ¼,
/// grammen op 5 of 10, stuks op ½) en weergegeven met nette breuken. Puur, zonder opslag.
enum Portieschaling {
    /// 4 → 6 personen = 1,5. Zonder bekend aantal porties (0) blijft alles zoals het staat.
    static func factor(van: Int, naar: Int) -> Double {
        guard van > 0, naar > 0 else { return 1 }
        return Double(naar) / Double(van)
    }

    /// Geschaalde hoeveelheid (en bovengrens bij een bereik), afgerond per eenheid. Factor 1 laat de
    /// hoeveelheid ongemoeid, zodat ⅓ el niet ongevraagd verandert.
    static func schaal(_ hoeveelheid: Double, tot: Double? = nil, eenheid: String?, factor: Double) -> (
        hoeveelheid: Double, tot: Double?
    ) {
        guard abs(factor - 1) > 0.0001 else { return (hoeveelheid, tot) }
        let van = rond(hoeveelheid * factor, eenheid: eenheid)
        guard let tot else { return (van, nil) }
        let bovengrens = rond(tot * factor, eenheid: eenheid)
        return (van, bovengrens > van ? bovengrens : nil)
    }

    /// Hoeveelheid en eenheid als tekst: "¾ tl", "3–4 tenen", "1½". `nil` zonder hoeveelheid.
    static func maat(hoeveelheid: Double?, tot: Double? = nil, eenheid: String?, factor: Double) -> String? {
        guard let hoeveelheid else { return eenheid }
        let geschaald = schaal(hoeveelheid, tot: tot, eenheid: eenheid, factor: factor)
        let getal = Weergave.hoeveelheid(geschaald.hoeveelheid, tot: geschaald.tot)
        guard let eenheid, !eenheid.isEmpty else { return getal }
        return "\(getal) \(Self.eenheid(eenheid, voor: geschaald.tot ?? geschaald.hoeveelheid))"
    }

    /// Een hele ingrediëntregel, geschaald. Regels zonder hoeveelheid ("peper en zout") of die de
    /// parser niet uit elkaar haalde, blijven letterlijk staan.
    static func regel(
        ruweTekst: String, hoeveelheid: Double?, tot: Double? = nil, eenheid: String?, naam: String?,
        toelichting: String?, factor: Double
    ) -> String {
        guard let hoeveelheid, let naam, !naam.isEmpty,
            let maat = maat(hoeveelheid: hoeveelheid, tot: tot, eenheid: eenheid, factor: factor)
        else { return ruweTekst }
        let rest = [naam, toelichting.map { schaalToelichting($0, factor: factor) }].compactMap { $0 }
            .joined(separator: ", ")
        return "\(maat) \(rest)"
    }

    /// Een maat in de toelichting schaalt mee: "ca. 1 kg" → "ca. 1½ kg". Andere tekst blijft staan.
    static func schaalToelichting(_ toelichting: String, factor: Double) -> String {
        guard abs(factor - 1) > 0.0001 else { return toelichting }
        return toelichting.components(separatedBy: "; ").map { deel in
            let p = IngredientParser.parse(deel)
            guard p.naam.isEmpty, p.eenheid != nil,
                let maat = maat(hoeveelheid: p.hoeveelheid, tot: p.hoeveelheidTot, eenheid: p.eenheid, factor: factor),
                p.hoeveelheid != nil
            else { return deel }
            let benadering = deel.range(
                of: #"^(ca\.?|circa|ong\.?|ongeveer|±)\s*"#, options: [.regularExpression, .caseInsensitive])
            return (benadering.map { String(deel[$0]) } ?? "") + maat
        }.joined(separator: "; ")
    }

    // MARK: - Afronden

    private static let lepels: Set<String> = ["el", "tl", "kl"]
    private static let gewichten: Set<String> = ["g", "ml", "mg"]
    private static let groteMaten: Set<String> = ["kg", "l"]
    private static let halveMaten: Set<String> = ["cl", "dl", "cm", "mm"]

    /// Breuken die je met een lepel of een mes nog kunt afmeten.
    private static let lepelbreuken: [Double] = [0, 0.25, 1.0 / 3, 0.5, 2.0 / 3, 0.75, 1]

    /// Rondt af op wat bij de eenheid past; nooit naar 0 (een snufje blijft een snufje).
    static func rond(_ waarde: Double, eenheid: String?) -> Double {
        guard waarde > 0 else { return waarde }
        let sleutel = eenheid?.lowercased() ?? ""
        if lepels.contains(sleutel) {
            return waarde < 3 ? max(0.25, naarBreuk(waarde)) : max(0.5, rond(waarde, op: 0.5))
        }
        if gewichten.contains(sleutel) {
            switch waarde {
            case ..<10: return max(1, rond(waarde, op: 1))
            case ..<500: return rond(waarde, op: 5)
            default: return rond(waarde, op: 10)
            }
        }
        if groteMaten.contains(sleutel) {
            // ⅔ kg in plaats van 0,65 kg als dat er vlak bij ligt.
            let breuk = naarBreuk(waarde)
            return abs(breuk - waarde) <= 0.03 && breuk > 0 ? breuk : max(0.05, rond(waarde, op: 0.05))
        }
        if halveMaten.contains(sleutel) { return max(0.5, rond(waarde, op: 0.5)) }
        // Stuks, tenen, blikken, snufjes: onder de 1 een nette breuk, daarboven op ½.
        return waarde < 1 ? max(0.25, naarBreuk(waarde)) : rond(waarde, op: 0.5)
    }

    private static func rond(_ waarde: Double, op stap: Double) -> Double {
        (waarde / stap).rounded() * stap
    }

    /// 0,72 → ¾, 1,3 → 1⅓.
    private static func naarBreuk(_ waarde: Double) -> Double {
        let geheel = waarde.rounded(.down)
        let deel = waarde - geheel
        let dichtste = lepelbreuken.min { abs($0 - deel) < abs($1 - deel) } ?? 0
        return geheel + dichtste
    }

    // MARK: - Enkelvoud en meervoud

    private static let meervouden: [String: String] = [
        "teen": "tenen", "teentje": "teentjes", "blik": "blikken", "blikje": "blikjes", "pot": "potten",
        "potje": "potjes", "pak": "pakken", "pakje": "pakjes", "zak": "zakken", "zakje": "zakjes", "bos": "bossen",
        "bosje": "bosjes", "tak": "takken", "takje": "takjes", "snufje": "snufjes", "scheutje": "scheutjes",
        "mespuntje": "mespuntjes", "handje": "handjes", "plak": "plakken", "plakje": "plakjes", "stukje": "stukjes",
        "kop": "koppen", "kopje": "kopjes", "glas": "glazen", "beker": "bekers", "bekertje": "bekertjes",
        "blad": "bladen", "blaadje": "blaadjes", "vel": "vellen", "velletje": "velletjes", "stengel": "stengels",
        "steel": "stelen", "struik": "struiken", "krop": "kroppen", "druppel": "druppels", "bakje": "bakjes",
        "doosje": "doosjes", "fles": "flessen", "flesje": "flesjes", "rol": "rollen", "bol": "bollen",
    ]
    private static let enkelvouden = Dictionary(uniqueKeysWithValues: meervouden.map { ($1, $0) })

    /// "teen" bij 3 → "tenen", "tenen" bij 1 → "teen". Maten (el, g) veranderen niet.
    static func eenheid(_ eenheid: String, voor waarde: Double) -> String {
        if waarde > 1, let meervoud = meervouden[eenheid] { return meervoud }
        if waarde <= 1, let enkelvoud = enkelvouden[eenheid] { return enkelvoud }
        return eenheid
    }
}
