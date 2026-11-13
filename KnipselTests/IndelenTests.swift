import CoreGraphics
import Foundation
import Testing
import UIKit

@testable import Knipsel

/// De testpagina uit docs/spikes (verzonnen): recept in twee kolommen, een supermarktadvertentie
/// ernaast en een lezersbrief eronder. Deze regels en kaders zijn wat Vision (nl-NL, accurate) er op
/// de Mac van maakte; zo is de indeling te testen los van de versie van de tekstherkenning.
enum Testpagina {
    static func r(_ tekst: String, _ x: CGFloat, _ y: CGFloat, _ b: CGFloat, _ h: CGFloat, _ zeker: Float = 1)
        -> HerkendeRegel
    {
        HerkendeRegel(tekst: tekst, kader: CGRect(x: x, y: y, width: b, height: h), betrouwbaarheid: zeker)
    }

    static let regels: [HerkendeRegel] = [
        r("Pompoensoep met gember", 0.034, 0.033, 0.732, 0.045),
        r("Een warme soep voor koude dagen. Voor 4 personen • 45 minuten", 0.034, 0.089, 0.638, 0.019),
        r("Ingrediënten", 0.031, 0.137, 0.115, 0.015),
        r("1 flespompoen (ca. 1 kg)", 0.034, 0.158, 0.206, 0.015, 0.5),
        r("2 uien, gesnipperd", 0.034, 0.181, 0.154, 0.015),
        r("3 cm verse gember", 0.034, 0.202, 0.159, 0.015),
        r("2 el olijfolie", 0.031, 0.223, 0.096, 0.015),
        r("1 l groentebouillon", 0.034, 0.243, 0.151, 0.015, 0.5),
        r("200 ml kokosmelk", 0.031, 0.265, 0.151, 0.012),
        r("½ ti kerriepoeder", 0.031, 0.287, 0.143, 0.015),
        r("peper en zout", 0.031, 0.308, 0.12, 0.016),
        r("1. Schil de pompoen, verwijder de pitten en", 0.341, 0.137, 0.352, 0.017),
        r("snijd het vruchtvlees in blokjes van 2 cm.", 0.341, 0.16, 0.336, 0.015),
        r("2. Verhit de olie in een grote pan en fruit", 0.341, 0.204, 0.331, 0.017),
        r("de ui en geraspte gember 5 minuten op", 0.341, 0.225, 0.318, 0.017),
        r("middelhoog vuur.", 0.338, 0.246, 0.152, 0.02),
        r("3. Voeg de pompoen en kerriepoeder toe", 0.341, 0.291, 0.331, 0.017),
        r("en bak 2 minuten mee. Schenk de bouillon", 0.341, 0.315, 0.346, 0.012),
        r("erbij en laat 20 minuten zachtjes koken.", 0.339, 0.335, 0.331, 0.015),
        r("NU 2 HALEN", 0.74, 0.15, 0.172, 0.021),
        r("1 BETALEN!", 0.74, 0.177, 0.169, 0.019),
        r("Alle wasmiddelen bij uw", 0.742, 0.2, 0.214, 0.015),
        r("supermarkt. Geldig t/m", 0.74, 0.216, 0.203, 0.017),
        r("zondag.", 0.74, 0.235, 0.076, 0.015),
        r("4. Pureer de soep met een staafmixer, roer", 0.341, 0.381, 0.346, 0.015),
        r("de kokosmelk erdoor en breng op smaak", 0.341, 0.402, 0.331, 0.017),
        r("met peper en zout.", 0.341, 0.425, 0.154, 0.016),
        r("Lezersbrief: Mijn buurman heeft al schutting groeit. Wat zijn mijn rechten?", 0.034, 0.599, 0.617, 0.024),
        r("weken last van zijn heg die over de", 0.031, 0.614, 0.26, 0.017),
        r("Volgens de wet moet een heg... (lees", 0.349, 0.613, 0.269, 0.019),
        r("verder op pagina 34)", 0.659, 0.602, 0.164, 0.015),
    ]

    static let stappen = [
        "Schil de pompoen, verwijder de pitten en snijd het vruchtvlees in blokjes van 2 cm.",
        "Verhit de olie in een grote pan en fruit de ui en geraspte gember 5 minuten op middelhoog vuur.",
        "Voeg de pompoen en kerriepoeder toe en bak 2 minuten mee. Schenk de bouillon erbij en laat 20 minuten zachtjes koken.",
        "Pureer de soep met een staafmixer, roer de kokosmelk erdoor en breng op smaak met peper en zout.",
    ]

    static let categorieen = StandaardCategorieen.alle.map(\.naam)
    static let labels = StandaardCategorieen.labels

    static var beeld: CGImage {
        get throws {
            let url = try #require(Bundle(for: BundelSleutel.self).url(forResource: "testpagina", withExtension: "png"))
            return try #require(UIImage(contentsOfFile: url.path)?.cgImage)
        }
    }

    private final class BundelSleutel {}
}

struct RegelIndelerTests {
    @Test func deeltTestpaginaIn() {
        let indeling = RegelIndeler.deelIn(
            Testpagina.regels, categorieen: Testpagina.categorieen, labels: Testpagina.labels)
        #expect(indeling.blokken(.titel) == [0])
        #expect(indeling.blokken(.intro) == [1])
        #expect(indeling.blokken(.ingredient) == Array(2...10))
        #expect(indeling.blokken(.stap) == Array(11...18) + [24, 25, 26])
        // Advertentie (19–23) en lezersbrief (27–30) weg.
        #expect(indeling.blokken(.weg) == Array(19...23) + Array(27...30))
        #expect(indeling.categorieen == ["Soepen"])
        #expect(indeling.labels == ["Vegetarisch"])
        #expect(indeling.bron == .regels)
    }

    @Test func blokkenEnLeesvolgorde() throws {
        let opmaak = Opmaak(Testpagina.regels)
        // Stap 4 staat bij Vision ná de advertentie, maar in de leesvolgorde direct na stap 3.
        let volgorde = opmaak.leesvolgorde
        let drie = try #require(volgorde.firstIndex(of: 18))
        #expect(volgorde[drie + 1] == 24)
        // De advertentie is één blok, de lezersbrief ook.
        #expect(Set((19...23).map { opmaak.blokVanRegel[$0] }).count == 1)
        #expect(Set((27...30).map { opmaak.blokVanRegel[$0] }).count == 1)
        // Elke stap een eigen blok.
        #expect(Set([11, 13, 16, 24].map { opmaak.blokVanRegel[$0] }).count == 4)
    }

    @Test func reclamewoorden() {
        #expect(RegelIndeler.isReclame("NU 2 HALEN"))
        #expect(RegelIndeler.isReclame("supermarkt. Geldig t/m"))
        #expect(RegelIndeler.isReclame("Nu € 2,99"))
        #expect(RegelIndeler.isReclame("(lees verder op pagina 34)"))
        #expect(!RegelIndeler.isReclame("Haal de pan van het vuur."))
        #expect(!RegelIndeler.isReclame("2 el olijfolie"))
    }

    @Test func zonderNummeringIsElkeAlineaEenStap() {
        func r(_ t: String, _ x: CGFloat, _ y: CGFloat, _ b: CGFloat, _ h: CGFloat) -> HerkendeRegel {
            Testpagina.r(t, x, y, b, h)
        }
        let regels = [
            r("Snelle tomatensoep", 0.05, 0.05, 0.6, 0.05),
            r("2 el olie", 0.05, 0.15, 0.2, 0.015),
            r("1 ui", 0.05, 0.17, 0.2, 0.015),
            r("1 blik tomaten", 0.05, 0.19, 0.2, 0.015),
            r("Verhit de olie en fruit de ui. Voeg de", 0.35, 0.15, 0.4, 0.015),
            r("tomaten toe en laat 10 minuten koken.", 0.35, 0.17, 0.4, 0.015),
            r("Pureer de soep en breng op smaak met", 0.35, 0.22, 0.4, 0.015),
            r("peper en zout.", 0.35, 0.24, 0.2, 0.015),
        ]
        let indeling = RegelIndeler.deelIn(regels, categorieen: Testpagina.categorieen, labels: Testpagina.labels)
        #expect(indeling.blokken(.ingredient) == [1, 2, 3])
        #expect(indeling.blokken(.stap) == [4, 5, 6, 7])
        let concept = ReceptOpbouw.bouw(regels, indeling: indeling)
        #expect(
            concept.stappen.map(\.tekst) == [
                "Verhit de olie en fruit de ui. Voeg de tomaten toe en laat 10 minuten koken.",
                "Pureer de soep en breng op smaak met peper en zout.",
            ])
    }

    @Test func voorstellenAlleenUitBestaandeNamen() {
        #expect(Voorstellen.categorieen(titel: "Pompoensoep", intro: "", uit: ["Soep & stoof"]) == [])
        #expect(Voorstellen.categorieen(titel: "Pompoensoep", intro: "", uit: ["soepen"]) == ["soepen"])
        #expect(Voorstellen.categorieen(titel: "Rijstsalade", intro: "", uit: Testpagina.categorieen) == ["Salades"])
        #expect(
            Voorstellen.labels(
                ingredienten: ["4 kippendijen", "1 ui", "2 el olie"], minuten: 25, uit: Testpagina.labels)
                == ["Vlees", "Snel (< 30 min)"])
        #expect(
            Voorstellen.labels(
                ingredienten: ["200 g champignons", "1 ui", "1 l bouillon"], minuten: 0, uit: Testpagina.labels) == [
                    "Vegetarisch"
                ])
    }

    /// Eind-tot-eind: de echte Vision-herkenning (in de simulator) op testpagina.png, dan de regels.
    @Test func eindTotEindOpTestpagina() async throws {
        let regels = try await ScanService.herken(try Testpagina.beeld)
        let indeling = await RegelIndeler().deelIn(
            regels, categorieen: Testpagina.categorieen, labels: Testpagina.labels)
        let concept = ReceptOpbouw.bouw(regels, indeling: indeling)

        #expect(concept.titel == "Pompoensoep met gember")
        #expect(concept.ingredienten.count == 8)
        #expect(concept.ingredienten.map(\.tekst).contains("2 uien, gesnipperd"))
        #expect(concept.stappen.map(\.tekst) == Testpagina.stappen)
        #expect(concept.porties == 4)
        #expect(concept.minuten == 45)
        // Advertentie en lezersbrief zijn weg.
        let alles = ([concept.titel, concept.intro] + concept.ingredienten.map(\.tekst) + concept.stappen.map(\.tekst))
            .joined(separator: " ")
        #expect(!alles.localizedCaseInsensitiveContains("halen"))
        #expect(!alles.localizedCaseInsensitiveContains("buurman"))
        #expect(indeling.categorieen == ["Soepen"])
    }
}

struct ReceptOpbouwTests {
    /// De indeling uit de proef (docs/spikes): code voegt samen, de tekst blijft letterlijk.
    @Test func voegtTestpaginaSamenZoalsDeProef() {
        let indeling = Indeling(
            aantal: Testpagina.regels.count, titel: [0], intro: [1], ingredienten: Array(3...10),
            bereiding: Array(11...18) + [24, 25, 26])
        let concept = ReceptOpbouw.bouw(Testpagina.regels, indeling: indeling)
        #expect(concept.titel == "Pompoensoep met gember")
        #expect(concept.intro == "Een warme soep voor koude dagen. Voor 4 personen • 45 minuten")
        #expect(concept.porties == 4)
        #expect(concept.minuten == 45)
        #expect(
            concept.ingredienten.map(\.tekst) == [
                "1 flespompoen (ca. 1 kg)", "2 uien, gesnipperd", "3 cm verse gember", "2 el olijfolie",
                "1 l groentebouillon", "200 ml kokosmelk", "½ ti kerriepoeder", "peper en zout",
            ])
        #expect(concept.stappen.map(\.tekst) == Testpagina.stappen)
        #expect(concept.stappen[2].regels == [16, 17, 18])
    }

    @Test func kopjeInIngredientenValtWeg() {
        let indeling = Indeling(aantal: Testpagina.regels.count, titel: [0], ingredienten: Array(2...10))
        #expect(ReceptOpbouw.bouw(Testpagina.regels, indeling: indeling).ingredienten.count == 8)
    }

    @Test func twijfel() {
        let indeling = Indeling(aantal: Testpagina.regels.count, titel: [0], ingredienten: Array(3...10))
        let ingredienten = ReceptOpbouw.bouw(Testpagina.regels, indeling: indeling).ingredienten
        let twijfel = ingredienten.filter { ReceptOpbouw.isTwijfel($0, isIngredient: true) }.map(\.tekst)
        // Betrouwbaarheid 0,5 is niet lager dan de drempel; "ti" is een geraden eenheid.
        #expect(twijfel == ["½ ti kerriepoeder"])

        let onzeker = ConceptRegel(tekst: "1 l groentebouillon", laagVertrouwen: true)
        #expect(ReceptOpbouw.isTwijfel(onzeker, isIngredient: true))
        var verbeterd = onzeker
        verbeterd.tekst = "1 l groentebouillon."
        #expect(!ReceptOpbouw.isTwijfel(verbeterd, isIngredient: true))

        // Spike: de "l" viel weg.
        #expect(ReceptOpbouw.isTwijfel(ConceptRegel(tekst: "1 groentebouillon"), isIngredient: true))
        #expect(!ReceptOpbouw.isTwijfel(ConceptRegel(tekst: "1 groentebouillon"), isIngredient: false))
        #expect(ReceptOpbouw.isOnzeker(Testpagina.r("x", 0, 0, 1, 1, 0.3)))
        #expect(!ReceptOpbouw.isOnzeker(Testpagina.r("x", 0, 0, 1, 1, 0.5)))
    }

    @Test func plakken() {
        #expect(ReceptOpbouw.plak(["Schenk de groente-", "bouillon erbij."]) == "Schenk de groentebouillon erbij.")
        #expect(ReceptOpbouw.plak(["peper- en", "zout"]) == "peper- en zout")
        #expect(ReceptOpbouw.plak(["Bak", "", " goudbruin."]) == "Bak goudbruin.")
    }

    @Test func doorlopendIngredientWordtWeerHeel() {
        func r(_ t: String, _ x: CGFloat, _ y: CGFloat, _ b: CGFloat, _ h: CGFloat) -> HerkendeRegel {
            Testpagina.r(t, x, y, b, h)
        }
        let regels = [
            r("1 flespompoen (ca.", 0, 0, 0.2, 0.015), r("1 kg)", 0, 0.02, 0.1, 0.015),
            r("2 uien", 0, 0.04, 0.1, 0.015),
        ]
        let concept = ReceptOpbouw.bouw(regels, indeling: Indeling(aantal: 3, ingredienten: [0, 1, 2]))
        #expect(concept.ingredienten.map(\.tekst) == ["1 flespompoen (ca. 1 kg)", "2 uien"])
    }

    @Test func portiesEnTijd() {
        #expect(ReceptOpbouw.porties(in: "Voor 4 personen") == 4)
        #expect(ReceptOpbouw.porties(in: "6 pers. · 1 uur") == 6)
        #expect(ReceptOpbouw.porties(in: "Een warme soep") == 0)
        #expect(ReceptOpbouw.minuten(in: "45 minuten") == 45)
        #expect(ReceptOpbouw.minuten(in: "1 uur 15 min") == 75)
        #expect(ReceptOpbouw.minuten(in: "Bereidingstijd: 2 uur") == 120)
    }

    @Test func nummerVanStapEraf() {
        #expect(ReceptOpbouw.zonderNummer("3. Voeg de pompoen toe") == "Voeg de pompoen toe")
        #expect(ReceptOpbouw.zonderNummer("12) Bak") == "Bak")
        #expect(ReceptOpbouw.zonderNummer("1,5 liter") == "1,5 liter")
    }

    @Test func indelingUitBloknummers() {
        let indeling = Indeling(aantal: 4, titel: [0, 9], intro: [0, 1], ingredienten: [2, -1], bereiding: [3])
        #expect(indeling.rollen == [.titel, .intro, .ingredient, .stap])
        #expect(Rol.weg.volgende == .titel)
        #expect(Rol.titel.volgende == .intro)
        #expect(Indeling.bestaande(["soepen", "Bestaat niet", "Soepen"], uit: ["Soepen"]) == ["Soepen"])
    }
}

@MainActor
struct KnipSessieTests {
    @Test func vakkenEnRolWisselen() throws {
        let indeling = RegelIndeler.deelIn(
            Testpagina.regels, categorieen: Testpagina.categorieen, labels: Testpagina.labels)
        let sessie = KnipSessie(paginas: [], regels: Testpagina.regels, indeling: indeling)
        let vakken = sessie.vakken
        // Titel, intro, ingrediënten, 4 stappen, advertentie, lezersbrief.
        #expect(vakken.count == 9)
        let advertentie = try #require(vakken.first { $0.regels.contains(19) })
        #expect(advertentie.rol == .weg)
        sessie.wisselRol(advertentie)
        #expect((19...23).allSatisfy { sessie.rol($0) == .titel })
        #expect(sessie.concept.titel.hasPrefix("Pompoensoep met gember NU 2 HALEN"))
    }

    @Test func uitsnedeUitDeFoto() throws {
        let beeld = UIImage(cgImage: try Testpagina.beeld)
        let sessie = KnipSessie(paginas: [beeld], regels: Testpagina.regels, indeling: Indeling(rollen: []))
        let uitsnede = try #require(sessie.uitsnede([7]))
        // Een regel van ±180 × 22 pixels, met wat rand.
        #expect(uitsnede.size.width > 150 && uitsnede.size.width < 260)
        #expect(uitsnede.size.height > 15 && uitsnede.size.height < 60)
        sessie.herstel()
        #expect(sessie.paginas.isEmpty)
    }
}
