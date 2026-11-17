import Foundation

/// Een regel op de eigen lijst in Knipsel, los van Core Data zodat optellen puur te testen is.
struct LijstRegel: Equatable, Sendable {
    var naam: String
    var sleutel: String
    var hoeveelheid: Double?
    var eenheid: String?
    var tekst: String

    init(naam: String, sleutel: String? = nil, hoeveelheid: Double? = nil, eenheid: String? = nil, tekst: String? = nil)
    {
        self.naam = naam
        self.sleutel = sleutel ?? BoodschappenLijst.sleutel(naam)
        self.hoeveelheid = hoeveelheid
        self.eenheid = eenheid?.isEmpty == true ? nil : eenheid
        self.tekst = tekst ?? BoodschappenLijst.lijstTekst(naam: naam, hoeveelheid: hoeveelheid, eenheid: eenheid)
    }

    init(_ regel: BoodschappenRegel) {
        self.init(
            naam: regel.naam, sleutel: regel.sleutel, hoeveelheid: regel.hoeveelheid, eenheid: regel.eenheid,
            tekst: regel.tekst)
    }

    /// Een vrij ingetypte regel ("＋ Item"): "2 uien", "500 ml melk" of gewoon "wc-papier".
    init?(vrijeTekst: String) {
        let regels = BoodschappenLijst.regels(
            [BoodschappenInvoer(regel: vrijeTekst)], factor: 1, meestalInHuis: MeestalInHuis(woorden: []))
        guard let regel = regels.first else { return nil }
        self.init(regel)
    }
}

/// Optellen op de eigen lijst (#39): een nieuw ingrediënt met dezelfde naam en een optelbare maat komt
/// bij het open item ("2 uien" + "1 ui" = "3 uien", "500 ml" + "1 l" = "1½ l"). Hergebruikt de
/// optel- en maatlogica van het boodschappenvel, met hele stuks in de winkel.
extension BoodschappenLijst {
    /// Samen één regel, of `nil` als het niet samen kan (andere naam, g en el, of een van beide zonder
    /// hoeveelheid). Twee regels zonder hoeveelheid met dezelfde naam ("peper en zout") worden één.
    static func samengevoegd(_ bestaand: LijstRegel, _ erbij: LijstRegel) -> LijstRegel? {
        guard !bestaand.sleutel.isEmpty, bestaand.sleutel == erbij.sleutel else { return nil }
        switch (bestaand.hoeveelheid, erbij.hoeveelheid) {
        case (nil, nil):
            return bestaand
        case (let a?, let b?):
            let invoer = [
                BoodschappenInvoer(
                    ruweTekst: bestaand.tekst, hoeveelheid: a, eenheid: bestaand.eenheid, naam: bestaand.naam),
                BoodschappenInvoer(ruweTekst: erbij.tekst, hoeveelheid: b, eenheid: erbij.eenheid, naam: erbij.naam),
            ]
            let samen = regels(invoer, factor: 1, meestalInHuis: MeestalInHuis(woorden: []))
            guard samen.count == 1, let regel = samen.first else { return nil }
            return LijstRegel(regel)
        default:
            return nil
        }
    }

    /// "Pompoensoep" + "Linzensalade" → "Pompoensoep, Linzensalade"; geen dubbele.
    static func herkomst(_ bestaand: String?, plus nieuw: String?) -> String? {
        var titels = herkomstTitels(bestaand)
        for titel in herkomstTitels(nieuw) where !titels.contains(titel) { titels.append(titel) }
        return titels.isEmpty ? nil : titels.joined(separator: ", ")
    }

    static func herkomstTitels(_ tekst: String?) -> [String] {
        (tekst ?? "").components(separatedBy: ", ").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// De tekst op de lijst bij een naam en hoeveelheid: "3 uien", "200 ml kokosmelk", of de naam.
    static func lijstTekst(naam: String, hoeveelheid: Double?, eenheid: String?) -> String {
        let naam = naam.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hoeveelheid, hoeveelheid > 0, !naam.isEmpty else { return naam }
        let invoer = BoodschappenInvoer(ruweTekst: naam, hoeveelheid: hoeveelheid, eenheid: eenheid, naam: naam)
        return regels([invoer], factor: 1, meestalInHuis: MeestalInHuis(woorden: [])).first?.tekst ?? naam
    }

    /// Platte tekst van de eigen lijst, per afdeling in winkelvolgorde: kop, lege regel, afdeling,
    /// "• 3 uien". Alleen wat nog open staat.
    static func tekst(titel: String, perAfdeling groepen: [(afdeling: Afdeling, regels: [String])]) -> String {
        var delen = [titel]
        for groep in groepen where !groep.regels.isEmpty {
            delen.append("")
            delen.append(groep.afdeling.naam)
            delen += groep.regels.map { "• \($0)" }
        }
        return delen.joined(separator: "\n")
    }
}
