import Foundation
import Testing

@testable import Knipsel

struct PortieschalingTests {
    struct Geval: CustomTestStringConvertible, Sendable {
        let regel: String
        let van: Int
        let naar: Int
        let verwacht: String
        var testDescription: String { "\(regel) · \(van)→\(naar)" }
    }

    static let gevallen: [Geval] = [
        // De rekensom uit het issue: 1½ × ½ tl = ¾ tl.
        Geval(regel: "½ tl kerriepoeder", van: 4, naar: 6, verwacht: "¾ tl kerriepoeder"),
        Geval(regel: "2 uien, gesnipperd", van: 4, naar: 6, verwacht: "3 uien, gesnipperd"),
        Geval(regel: "1 flespompoen (ca. 1 kg)", van: 4, naar: 6, verwacht: "1½ flespompoen, ca. 1½ kg"),
        Geval(
            regel: "1 blik tomatenblokjes (400 g)", van: 2, naar: 3, verwacht: "1½ blikken tomatenblokjes, 600 g"),
        Geval(regel: "3 cm verse gember", van: 4, naar: 6, verwacht: "4½ cm verse gember"),
        Geval(regel: "1 l groentebouillon", van: 4, naar: 6, verwacht: "1½ l groentebouillon"),
        Geval(regel: "200 ml kokosmelk", van: 4, naar: 6, verwacht: "300 ml kokosmelk"),
        Geval(regel: "2 el olijfolie", van: 4, naar: 6, verwacht: "3 el olijfolie"),
        // Grammen op 5 of 10.
        Geval(regel: "150 g oude kaas, geraspt", van: 4, naar: 3, verwacht: "115 g oude kaas, geraspt"),
        Geval(regel: "500 g kastanjechampignons", van: 6, naar: 7, verwacht: "580 g kastanjechampignons"),
        Geval(regel: "100 g koude boter", van: 4, naar: 1, verwacht: "25 g koude boter"),
        // Lepels op ¼, ook naar beneden; nooit 0.
        Geval(regel: "1 el honing", van: 4, naar: 1, verwacht: "¼ el honing"),
        Geval(regel: "½ tl zout", van: 4, naar: 1, verwacht: "¼ tl zout"),
        Geval(regel: "1 tl komijn", van: 3, naar: 2, verwacht: "⅔ tl komijn"),
        // Bereik: beide grenzen schalen, eenheid wordt meervoud.
        Geval(regel: "3-4 tenen knoflook", van: 4, naar: 2, verwacht: "1½–2 tenen knoflook"),
        Geval(regel: "1-2 teentjes knoflook", van: 2, naar: 4, verwacht: "2–4 teentjes knoflook"),
        Geval(regel: "1 teen knoflook, geperst", van: 2, naar: 6, verwacht: "3 tenen knoflook, geperst"),
        // Stuks op ½.
        Geval(regel: "4 eieren", van: 4, naar: 3, verwacht: "3 eieren"),
        Geval(regel: "3 stengels prei", van: 4, naar: 5, verwacht: "4 stengels prei"),
        Geval(regel: "1/2 citroen", van: 4, naar: 2, verwacht: "¼ citroen"),
        // Zonder hoeveelheid: letterlijk.
        Geval(regel: "peper en zout", van: 4, naar: 6, verwacht: "peper en zout"),
        Geval(regel: "handje peterselie", van: 2, naar: 4, verwacht: "handje peterselie"),
        // Zelfde aantal: niets afronden.
        Geval(regel: "⅓ el sambal", van: 4, naar: 4, verwacht: "⅓ el sambal"),
        // Grote maten.
        Geval(regel: "1 kg runderstoofvlees", van: 6, naar: 4, verwacht: "⅔ kg runderstoofvlees"),
    ]

    @Test(arguments: gevallen)
    func schaaltRegel(_ geval: Geval) {
        let p = IngredientParser.parse(geval.regel)
        let tekst = Portieschaling.regel(
            ruweTekst: geval.regel, hoeveelheid: p.hoeveelheid, tot: p.hoeveelheidTot, eenheid: p.eenheid,
            naam: p.naam.isEmpty ? nil : p.naam, toelichting: p.toelichting,
            factor: Portieschaling.factor(van: geval.van, naar: geval.naar))
        #expect(tekst == geval.verwacht)
    }

    @Test func factorZonderBekendePortiesIsEen() {
        #expect(Portieschaling.factor(van: 0, naar: 6) == 1)
        #expect(Portieschaling.factor(van: 4, naar: 6) == 1.5)
    }

    @Test func maatAlleenHoeveelheidEnEenheid() {
        #expect(Portieschaling.maat(hoeveelheid: 0.5, eenheid: "tl", factor: 1.5) == "¾ tl")
        #expect(Portieschaling.maat(hoeveelheid: 1, eenheid: nil, factor: 1.5) == "1½")
        #expect(Portieschaling.maat(hoeveelheid: nil, eenheid: "snufje", factor: 2) == "snufje")
        #expect(Portieschaling.maat(hoeveelheid: 3, tot: 4, eenheid: "tenen", factor: 1) == "3–4 tenen")
    }

    @Test func afrondenPerEenheid() {
        #expect(Portieschaling.rond(0.1, eenheid: "el") == 0.25)
        #expect(Portieschaling.rond(4.3, eenheid: "el") == 4.5)
        #expect(Portieschaling.rond(372, eenheid: "g") == 370)
        #expect(Portieschaling.rond(1234, eenheid: "g") == 1230)
        #expect(Portieschaling.rond(2.4, eenheid: "g") == 2)
        #expect(Portieschaling.rond(1.26, eenheid: nil) == 1.5)
        #expect(Portieschaling.rond(0.02, eenheid: "snufje") == 0.25)
    }

    @Test func enkelvoudEnMeervoudVanEenheid() {
        #expect(Portieschaling.eenheid("teen", voor: 3) == "tenen")
        #expect(Portieschaling.eenheid("tenen", voor: 1) == "teen")
        #expect(Portieschaling.eenheid("blik", voor: 1.5) == "blikken")
        #expect(Portieschaling.eenheid("el", voor: 3) == "el")
    }
}
