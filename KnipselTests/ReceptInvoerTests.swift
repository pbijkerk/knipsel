import CoreData
import Foundation
import ImageIO
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

    @Test func gewijzigdeRegelWordtOpnieuwGeparsed() throws {
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
        // De velden van de oude tekst ("uien") zijn vervangen door die van de nieuwe.
        #expect(ui.hoeveelheid == 3)
        #expect(ui.naam == "sjalotten")
    }

    @Test func bewarenVultGestructureerdeVelden() throws {
        let context = legeOpslag().context
        var invoer = ReceptInvoer()
        invoer.titel = "Test"
        invoer.ingredientenTekst = "1 flespompoen (ca. 1 kg)\n½ tl kerriepoeder\npeper en zout"
        let ingredienten = try invoer.bewaar(in: context).gesorteerdeIngredienten
        #expect(ingredienten.map(\.ruweTekst) == ["1 flespompoen (ca. 1 kg)", "½ tl kerriepoeder", "peper en zout"])
        #expect(ingredienten[0].hoeveelheid == 1)
        #expect(ingredienten[0].naam == "flespompoen")
        #expect(ingredienten[0].toelichting == "ca. 1 kg")
        #expect(ingredienten[1].hoeveelheid == 0.5)
        #expect(ingredienten[1].eenheid == "tl")
        #expect(ingredienten[2].hoeveelheid == nil)
        #expect(ingredienten[2].naam == "peper en zout")
    }

    @Test func groepskopWordtGroepEnKomtTerug() throws {
        let context = legeOpslag().context
        var invoer = ReceptInvoer()
        invoer.titel = "Test"
        invoer.ingredientenTekst = "500 g pasta\nVoor de saus:\n2 el olie\n1 teen knoflook"
        let recept = try invoer.bewaar(in: context)
        #expect(recept.gesorteerdeIngredienten.map(\.ruweTekst) == ["500 g pasta", "2 el olie", "1 teen knoflook"])
        #expect(recept.gesorteerdeIngredienten.map(\.groep) == [nil, "Voor de saus", "Voor de saus"])
        #expect(ReceptInvoer(recept: recept).ingredientenTekst == invoer.ingredientenTekst)
    }

    @Test func receptenUitFaseEenWordenGestructureerd() throws {
        let context = legeOpslag().context
        let recept = Recept(context: context)
        recept.titel = "Oud recept"
        for (index, tekst) in ["2 el olie", "1 ui", ""].enumerated() {
            let ingredient = Ingredient(context: context)
            ingredient.ruweTekst = tekst
            ingredient.volgorde = Int16(index)
            ingredient.recept = recept
        }
        try context.save()
        #expect(try Inrichting.structureerIngredienten(in: context) == 2)
        #expect(recept.gesorteerdeIngredienten.map(\.naam) == ["olie", "ui", nil])
        #expect(recept.gesorteerdeIngredienten[0].eenheid == "el")
        // Tweede keer: niets meer te doen; een lege regel blijft ongemoeid.
        #expect(try Inrichting.structureerIngredienten(in: context) == 0)
    }

    @Test func controleNaarRecept() throws {
        let context = legeOpslag().context
        try Inrichting.zaaiStandaard(in: context)
        let soepen = try categorie("Soepen", in: context)
        var concept = ReceptOpbouw.bouw(
            Testpagina.regels,
            indeling: RegelIndeler.deelIn(
                Testpagina.regels, categorieen: Testpagina.categorieen, labels: Testpagina.labels))
        concept.ingredienten[6].tekst = "½ tl kerriepoeder"
        let controle = ControleInvoer(
            concept: concept, categorieen: [soepen.objectID], bronNaam: "Het Testblad",
            bronDatum: Date(timeIntervalSince1970: 1_794_528_000), bronPagina: "52")
        #expect(controle.twijfelAantal == 0)

        let recept = try controle.receptInvoer.bewaar(in: context)
        #expect(recept.titel == "Pompoensoep met gember")
        #expect(recept.porties == 4)
        #expect(recept.bereidingstijdMinuten == 45)
        #expect(recept.kookboek == Kookboek.mijn.rawValue)
        #expect(recept.bronNaam == "Het Testblad")
        #expect(recept.categorieen == [soepen])
        #expect(recept.gesorteerdeIngredienten.count == 8)
        #expect(recept.gesorteerdeIngredienten[4].eenheid == "l")
        #expect(recept.gesorteerdeStappen.map(\.tekst) == Testpagina.stappen)
    }
}

struct FotodatumTests {
    @Test func datumUitExif() throws {
        let data = NSMutableData()
        let doel = try #require(CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil))
        let context = try #require(
            CGContext(
                data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let beeld = try #require(context.makeImage())
        let eigenschappen: [CFString: Any] = [
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: "2026:11:07 09:30:00"]
        ]
        CGImageDestinationAddImage(doel, beeld, eigenschappen as CFDictionary)
        #expect(CGImageDestinationFinalize(doel))

        let datum = try #require(Fotodatum.uit(data as Data))
        let delen = Calendar.current.dateComponents([.year, .month, .day], from: datum)
        #expect(delen.year == 2026 && delen.month == 11 && delen.day == 7)
        #expect(Fotodatum.uit(Data("geen foto".utf8)) == nil)
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
