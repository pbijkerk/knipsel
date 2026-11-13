import Foundation
import Testing

@testable import Knipsel

struct IngredientParserTests {
    struct Geval: CustomTestStringConvertible, Sendable {
        let regel: String
        let hoeveelheid: Double?
        var tot: Double? = nil
        let eenheid: String?
        let naam: String
        var toelichting: String? = nil
        var testDescription: String { regel }
    }

    static let gevallen: [Geval] = [
        Geval(regel: "½ tl kerriepoeder", hoeveelheid: 0.5, eenheid: "tl", naam: "kerriepoeder"),
        Geval(regel: "2 el olijfolie", hoeveelheid: 2, eenheid: "el", naam: "olijfolie"),
        Geval(regel: "1 l groentebouillon", hoeveelheid: 1, eenheid: "l", naam: "groentebouillon"),
        Geval(regel: "200 ml kokosmelk", hoeveelheid: 200, eenheid: "ml", naam: "kokosmelk"),
        Geval(regel: "ca. 1 kg aardappelen", hoeveelheid: 1, eenheid: "kg", naam: "aardappelen"),
        Geval(regel: "3-4 tenen knoflook", hoeveelheid: 3, tot: 4, eenheid: "tenen", naam: "knoflook"),
        Geval(regel: "1½ el bloem", hoeveelheid: 1.5, eenheid: "el", naam: "bloem"),
        Geval(regel: "1/2 citroen", hoeveelheid: 0.5, eenheid: nil, naam: "citroen"),
        Geval(regel: "1 1/2 dl room", hoeveelheid: 1.5, eenheid: "dl", naam: "room"),
        Geval(regel: "snufje zout", hoeveelheid: nil, eenheid: "snufje", naam: "zout"),
        Geval(regel: "scheutje melk", hoeveelheid: nil, eenheid: "scheutje", naam: "melk"),
        Geval(
            regel: "1 teen knoflook, geperst", hoeveelheid: 1, eenheid: "teen", naam: "knoflook", toelichting: "geperst"
        ),
        Geval(
            regel: "1 blik tomatenblokjes (400 g)", hoeveelheid: 1, eenheid: "blik", naam: "tomatenblokjes",
            toelichting: "400 g"),
        Geval(regel: "1 bos lente-uitjes", hoeveelheid: 1, eenheid: "bos", naam: "lente-uitjes"),
        Geval(regel: "4 stuks stoofpeer", hoeveelheid: 4, eenheid: "stuks", naam: "stoofpeer"),
        Geval(regel: "3 cm verse gember", hoeveelheid: 3, eenheid: "cm", naam: "verse gember"),
        Geval(regel: "2 uien, gesnipperd", hoeveelheid: 2, eenheid: nil, naam: "uien", toelichting: "gesnipperd"),
        Geval(
            regel: "1 flespompoen (ca. 1 kg)", hoeveelheid: 1, eenheid: nil, naam: "flespompoen",
            toelichting: "ca. 1 kg"),
        Geval(regel: "peper en zout", hoeveelheid: nil, eenheid: nil, naam: "peper en zout"),
        Geval(regel: "250 gram bloem", hoeveelheid: 250, eenheid: "g", naam: "bloem"),
        Geval(regel: "500 gr. gehakt", hoeveelheid: 500, eenheid: "g", naam: "gehakt"),
        Geval(regel: "200ml slagroom", hoeveelheid: 200, eenheid: "ml", naam: "slagroom"),
        Geval(regel: "2 eetlepels honing", hoeveelheid: 2, eenheid: "el", naam: "honing"),
        Geval(regel: "1 theelepel komijn", hoeveelheid: 1, eenheid: "tl", naam: "komijn"),
        Geval(regel: "1,5 liter water", hoeveelheid: 1.5, eenheid: "l", naam: "water"),
        Geval(regel: "2 à 3 sjalotten", hoeveelheid: 2, tot: 3, eenheid: nil, naam: "sjalotten"),
        Geval(regel: "2 tot 3 el sojasaus", hoeveelheid: 2, tot: 3, eenheid: "el", naam: "sojasaus"),
        Geval(regel: "¼ tl cayennepeper", hoeveelheid: 0.25, eenheid: "tl", naam: "cayennepeper"),
        Geval(regel: "1 ½ kg mosselen", hoeveelheid: 1.5, eenheid: "kg", naam: "mosselen"),
        Geval(regel: "een snufje nootmuskaat", hoeveelheid: 1, eenheid: "snufje", naam: "nootmuskaat"),
        Geval(regel: "halve citroen, het sap", hoeveelheid: 0.5, eenheid: nil, naam: "citroen", toelichting: "het sap"),
        Geval(regel: "• 2 takjes tijm", hoeveelheid: 2, eenheid: "takjes", naam: "tijm"),
        Geval(regel: "4 plakjes ontbijtspek", hoeveelheid: 4, eenheid: "plakjes", naam: "ontbijtspek"),
        Geval(regel: "1 kopje rijst", hoeveelheid: 1, eenheid: "kopje", naam: "rijst"),
        Geval(regel: "3 eieren", hoeveelheid: 3, eenheid: nil, naam: "eieren"),
        Geval(regel: "olie om te bakken", hoeveelheid: nil, eenheid: nil, naam: "olie om te bakken"),
        Geval(
            regel: "100 g pure chocolade (70%), in stukjes", hoeveelheid: 100, eenheid: "g", naam: "pure chocolade",
            toelichting: "70%; in stukjes"),
        Geval(regel: "2 EL olie", hoeveelheid: 2, eenheid: "el", naam: "olie"),
        Geval(regel: "1 pot kappertjes", hoeveelheid: 1, eenheid: "pot", naam: "kappertjes"),
        Geval(regel: "een paar takjes peterselie", hoeveelheid: nil, eenheid: nil, naam: "een paar takjes peterselie"),
    ]

    @Test(arguments: gevallen)
    func parse(_ geval: Geval) {
        let p = IngredientParser.parse(geval.regel)
        #expect(p.hoeveelheid == geval.hoeveelheid)
        #expect(p.hoeveelheidTot == geval.tot)
        #expect(p.eenheid == geval.eenheid)
        #expect(p.naam == geval.naam)
        #expect(p.toelichting == geval.toelichting)
    }

    @Test func minstensDertigGevallen() {
        #expect(Self.gevallen.count >= 30)
    }

    @Test func ocrVerwarringTiWordtTlMaarIsTwijfel() {
        let p = IngredientParser.parse("½ ti kerriepoeder")
        #expect(p.eenheid == "tl")
        #expect(p.naam == "kerriepoeder")
        #expect(p.eenheidGeraden)
        #expect(IngredientParser.mistEenheid("½ ti kerriepoeder"))
    }

    @Test func groepskoppen() {
        #expect(IngredientParser.groepskop("Voor de saus:") == "Voor de saus")
        #expect(IngredientParser.groepskop("Voor het deeg") == "Voor het deeg")
        #expect(IngredientParser.groepskop("Garnering:") == "Garnering")
        #expect(IngredientParser.groepskop("Ingrediënten:") == nil)
        #expect(IngredientParser.groepskop("2 el olie") == nil)
        #expect(IngredientParser.groepskop("Voor 4 personen") == nil)
    }

    @Test func kopjes() {
        #expect(IngredientParser.isKopje("Ingrediënten"))
        #expect(IngredientParser.isKopje("Ingredienten"))
        #expect(IngredientParser.isKopje("Bereiding:"))
        #expect(!IngredientParser.isKopje("2 uien"))
    }

    @Test func lijktIngredient() {
        #expect(IngredientParser.lijktIngredient("2 el olijfolie"))
        #expect(IngredientParser.lijktIngredient("snufje zout"))
        #expect(IngredientParser.lijktIngredient("peper en zout"))
        #expect(!IngredientParser.lijktIngredient("1. Schil de pompoen, verwijder de pitten en"))
        #expect(!IngredientParser.lijktIngredient("20 minuten zachtjes koken"))
        #expect(!IngredientParser.lijktIngredient("Een warme soep voor koude dagen."))
    }

    @Test func mistEenheid() {
        // Spike: "1 l groentebouillon" werd "1 groentebouillon".
        #expect(IngredientParser.mistEenheid("1 groentebouillon"))
        #expect(IngredientParser.mistEenheid("200 kokosmelk"))
        #expect(IngredientParser.mistEenheid("2 olijfolie"))
        #expect(!IngredientParser.mistEenheid("1 l groentebouillon"))
        #expect(!IngredientParser.mistEenheid("2 uien, gesnipperd"))
        #expect(!IngredientParser.mistEenheid("1 flespompoen (ca. 1 kg)"))
        #expect(!IngredientParser.mistEenheid("peper en zout"))
    }

    @Test func genummerd() {
        #expect(IngredientParser.isGenummerd("1. Schil de pompoen"))
        #expect(IngredientParser.isGenummerd("12) Bak"))
        #expect(!IngredientParser.isGenummerd("1 l bouillon"))
        #expect(!IngredientParser.isGenummerd("1.5 kg aardappelen"))
    }
}
