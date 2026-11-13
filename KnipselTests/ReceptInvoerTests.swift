import CoreData
import Foundation
import SwiftUI
import Testing

@testable import Knipsel

@MainActor
struct ReceptInvoerTests {
    @Test func regelsSlaanLegeRegelsOver() {
        #expect(ReceptInvoer.regels("  1 ui \n\n\n2 el olijfolie\r\n  \n") == ["1 ui", "2 el olijfolie"])
        #expect(ReceptInvoer.regels("").isEmpty)
    }

    @Test func titelIsVerplicht() {
        var invoer = ReceptInvoer()
        #expect(!invoer.isGeldig)
        invoer.titel = "   "
        #expect(!invoer.isGeldig)
        invoer.titel = "Soep"
        #expect(invoer.isGeldig)
    }

    @Test func bewarenZetVolgordeEnRuweTekst() throws {
        let context = legeOpslag().context
        var invoer = ReceptInvoer()
        invoer.titel = "  Groene minestrone "
        invoer.intro = "  "
        invoer.porties = 4
        invoer.bereidingstijdMinuten = 35
        invoer.bronNaam = "Verzonnen Weekblad"
        invoer.bronPagina = "12"
        invoer.ingredientenTekst = "1 courgette\n200 g doperwten\n\n1 l bouillon"
        invoer.stappenTekst = "Snijd de groente.\n\nKook alles 15 minuten."
        let recept = try invoer.bewaar(in: context)

        #expect(recept.titel == "Groene minestrone")
        #expect(recept.intro == nil)
        #expect(recept.porties == 4)
        #expect(recept.bereidingstijdMinuten == 35)
        #expect(recept.gesorteerdeIngredienten.map(\.ruweTekst) == ["1 courgette", "200 g doperwten", "1 l bouillon"])
        #expect(recept.gesorteerdeIngredienten.map(\.volgorde) == [0, 1, 2])
        #expect(recept.gesorteerdeStappen.map(\.tekst) == ["Snijd de groente.", "Kook alles 15 minuten."])
    }

    @Test func bewerkenHergebruiktEnRuimtOp() throws {
        let context = legeOpslag().context
        var invoer = ReceptInvoer()
        invoer.titel = "Pannenkoeken"
        invoer.ingredientenTekst = "250 g bloem\n2 eieren\n500 ml melk"
        invoer.stappenTekst = "Meng.\nBak."
        let recept = try invoer.bewaar(in: context)
        let eerste = recept.gesorteerdeIngredienten[0]
        eerste.naam = "bloem"  // alsof de parser (fase 2) dit heeft ingevuld

        var bewerkt = ReceptInvoer(recept: recept)
        #expect(bewerkt.stappenTekst == "Meng.\n\nBak.")
        bewerkt.ingredientenTekst = "250 g bloem\n3 eieren"
        bewerkt.stappenTekst = "Meng alles."
        try bewerkt.bewaar(in: context, recept: recept)

        #expect(recept.gesorteerdeIngredienten.map(\.ruweTekst) == ["250 g bloem", "3 eieren"])
        #expect(recept.gesorteerdeIngredienten[0] == eerste)
        // Ongewijzigde regel houdt zijn gestructureerde velden.
        #expect(eerste.naam == "bloem")
        #expect(try context.count(for: Ingredient.verzoek()) == 2)
        #expect(try context.count(for: Stap.verzoek()) == 1)
    }

    @Test func gewijzigdeRegelVerliestGestructureerdeVelden() throws {
        let context = legeOpslag().context
        var invoer = ReceptInvoer()
        invoer.titel = "Test"
        invoer.ingredientenTekst = "2 uien"
        let recept = try invoer.bewaar(in: context)
        let ui = recept.gesorteerdeIngredienten[0]
        ui.hoeveelheid = 2
        ui.naam = "uien"

        var bewerkt = ReceptInvoer(recept: recept)
        bewerkt.ingredientenTekst = "3 sjalotten"
        try bewerkt.bewaar(in: context, recept: recept)
        #expect(ui.ruweTekst == "3 sjalotten")
        #expect(ui.hoeveelheid == nil)
        #expect(ui.naam == nil)
    }
}

struct WeergaveTests {
    @Test func tijden() {
        #expect(Weergave.tijd(minuten: 0) == nil)
        #expect(Weergave.tijd(minuten: 45) == "45 min")
        #expect(Weergave.tijd(minuten: 60) == "1 u")
        #expect(Weergave.tijd(minuten: 135) == "2 u 15 min")
    }

    @Test func hoeveelheden() {
        #expect(Weergave.hoeveelheid(2) == "2")
        #expect(Weergave.hoeveelheid(0.5) == "½")
        #expect(Weergave.hoeveelheid(1.5) == "1½")
        #expect(Weergave.hoeveelheid(0.25) == "¼")
        #expect(Weergave.hoeveelheid(2, tot: 3) == "2–3")
        #expect(Weergave.hoeveelheid(0.3) == "0,3")
    }

    @Test func bron() {
        #expect(Weergave.bron(naam: nil, datum: nil, pagina: nil) == nil)
        #expect(Weergave.bron(naam: "Testblad", datum: nil, pagina: "52") == "Testblad · p. 52")
    }

    @Test func extraTekstgrootteStoptBijAX5() {
        #expect(Leesinstellingen.vergroot(.large, met: 0) == .large)
        #expect(Leesinstellingen.vergroot(.large, met: 2) == .xxLarge)
        #expect(Leesinstellingen.vergroot(.accessibility4, met: 4) == .accessibility5)
    }
}
