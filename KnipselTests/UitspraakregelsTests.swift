import Testing

@testable import Knipsel

struct UitspraakregelsTests {
    @Test(
        "Hoeveelheden, eenheden en afkortingen",
        arguments: [
            // Lepels: uitgeschreven getal, enkelvoud bij 1 en breuken.
            ("2 el olijfolie", "twee eetlepels olijfolie"),
            ("1 el olie", "één eetlepel olie"),
            ("½ tl kerriepoeder", "een halve theelepel kerriepoeder"),
            ("¾ tl zout", "driekwart theelepel zout"),
            ("1 1/2 el suiker", "anderhalve eetlepel suiker"),
            ("3 tl", "drie theelepels"),
            // Breuken.
            ("¼ l melk", "een kwart liter melk"),
            ("1½ l groentebouillon", "anderhalve liter groentebouillon"),
            ("1/2 l water", "een halve liter water"),
            ("laat 2½ uur sudderen", "laat twee en een half uur sudderen"),
            ("½ ui", "een halve ui"),
            // Maten: getal blijft cijfers.
            ("1 l groentebouillon", "1 liter groentebouillon"),
            ("200 ml kokosmelk", "200 milliliter kokosmelk"),
            ("2 dl room", "2 deciliter room"),
            ("250 g bloem", "250 gram bloem"),
            ("250g bloem", "250 gram bloem"),
            ("1 kg pompoen", "1 kilo pompoen"),
            ("blokjes van 2 cm", "blokjes van 2 centimeter"),
            ("1,5 l water", "1,5 liter water"),
            // Temperatuur.
            ("Verwarm de oven op 180 °C.", "Verwarm de oven op 180 graden."),
            ("op 180°C", "op 180 graden"),
            ("op 180 graden", "op 180 graden"),
            // Bereiken.
            ("3-4 tenen knoflook", "drie à vier tenen knoflook"),
            ("3 à 4 tenen", "drie à vier tenen"),
            ("bak 8–10 min.", "bak acht à tien minuten."),
            // Afkortingen.
            ("ca. 1 kg", "circa 1 kilo"),
            ("bak 5 min. en roer", "bak 5 minuten en roer"),
            ("Bak 5 min. Roer dan", "Bak 5 minuten. Roer dan"),
            ("bijv. peterselie", "bijvoorbeeld peterselie"),
            ("stap 1 t/m 3", "stap 1 tot en met 3"),
            ("voor 4 pers. als hoofdgerecht", "voor 4 personen als hoofdgerecht"),
            ("± 10 min", "ongeveer 10 minuten"),
        ])
    func uitspraak(_ invoer: String, _ verwacht: String) {
        #expect(Uitspraakregels.uitspreekbaar(invoer) == verwacht)
    }

    @Test(
        "Laat woorden en losse getallen staan",
        arguments: [
            "verse gember", "olijfolie", "Verhit de olie.", "glás", "een glas wijn", "mello", "lente-ui",
            "stap 2", "snijd in 4 stukken", "13-11-2026", "gele paprika", "Laat koken.", "dl'tje",
        ])
    func laatStaan(_ tekst: String) {
        #expect(Uitspraakregels.uitspreekbaar(tekst) == tekst)
    }

    @Test func eenheidAlleenNaEenGetal() {
        #expect(Uitspraakregels.uitspreekbaar("Giet de l uit de pan") == "Giet de l uit de pan")
        #expect(Uitspraakregels.uitspreekbaar("1 g gember") == "1 gram gember")
        #expect(Uitspraakregels.uitspreekbaar("2 gemberwortels") == "2 gemberwortels")
        #expect(Uitspraakregels.uitspreekbaar("3 limoenen") == "3 limoenen")
    }

    @Test func helePompoensoepStap() {
        #expect(
            Uitspraakregels.uitspreekbaar(
                "Voeg de pompoen en ½ tl kerriepoeder toe en bak 2 min. mee. Schenk 1½ l bouillon erbij.")
                == "Voeg de pompoen en een halve theelepel kerriepoeder toe en bak 2 minuten mee. Schenk anderhalve liter bouillon erbij."
        )
    }
}
