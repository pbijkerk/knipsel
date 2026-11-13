import CoreData
import Foundation
import SwiftUI
import Testing

@testable import Knipsel

/// De pompoensoep uit de schetsen (verzonnen recept), als bewaard recept.
@MainActor
func pompoensoep(in context: NSManagedObjectContext) throws -> Recept {
    var invoer = ReceptInvoer()
    invoer.titel = "Pompoensoep met gember"
    invoer.porties = 4
    invoer.ingredientenTekst = [
        "1 flespompoen (ca. 1 kg)", "2 uien, gesnipperd", "3 cm verse gember", "2 el olijfolie",
        "1 l groentebouillon", "200 ml kokosmelk", "½ tl kerriepoeder", "peper en zout",
    ].joined(separator: "\n")
    invoer.stappenTekst = [
        "Schil de pompoen, verwijder de pitten en snijd het vruchtvlees in blokjes van 2 cm.",
        "Verhit de olie in een soeppan en fruit de ui en gember 5 minuten op middelhoog vuur.",
        "Voeg de pompoen en het kerriepoeder toe en bak 2 minuten mee. Schenk de bouillon erbij en laat 20 minuten zachtjes koken.",
        "Pureer de soep met een staafmixer, roer de kokosmelk erdoor en breng op smaak met peper en zout.",
    ].joined(separator: "\n")
    return try invoer.bewaar(in: context)
}

@MainActor
struct KookSessieTests {
    private func sessie(porties: Int? = nil) throws -> KookSessie {
        let opslag = legeOpslag()
        return KookSessie(recept: try pompoensoep(in: opslag.context), porties: porties)
    }

    private func namen(_ ingredienten: [KookIngredient]) -> [String] {
        ingredienten.compactMap(\.naam)
    }

    @Test func begintBijStapEen() throws {
        let s = try sessie()
        #expect(s.aantalStappen == 4)
        #expect(s.stapNummer == 1)
        #expect(s.isEersteStap)
        #expect(s.vorigeStap == nil)
        #expect(s.volgendeStap?.id == 1)
        #expect(s.porties == 4)
        #expect(s.factor == 1)
    }

    @Test func navigeertVooruitEnAchteruit() throws {
        let s = try sessie()
        #expect(s.volgende())
        #expect(s.volgende())
        #expect(s.stapNummer == 3)
        #expect(s.gebeurtenis == .volgende)
        #expect(s.vorige())
        #expect(s.stapNummer == 2)
        #expect(s.gebeurtenis == .vorige)
    }

    @Test func grenzen() throws {
        let s = try sessie()
        #expect(!s.vorige())
        #expect(s.stapNummer == 1)
        #expect(s.gebeurtenis == .grens)

        for _ in 0..<3 { s.volgende() }
        #expect(s.isLaatsteStap)
        #expect(s.volgende())
        #expect(s.isAfgerond)
        #expect(s.gebeurtenis == .afgerond)
        #expect(s.ingredientenInHuidigeStap.isEmpty)
        #expect(!s.volgende())
        #expect(s.isAfgerond)

        // Vanuit "Eet smakelijk" terug naar de laatste stap.
        #expect(s.vorige())
        #expect(!s.isAfgerond)
        #expect(s.stapNummer == 4)
    }

    @Test func naarStap() throws {
        let s = try sessie()
        #expect(s.naarStap(2))
        #expect(s.stapNummer == 3)
        #expect(s.gebeurtenis == .naarStap(2))
        #expect(!s.naarStap(9))
        #expect(s.stapNummer == 3)
    }

    @Test func herhaalMeldtZonderTeVerspringen() throws {
        let s = try sessie()
        s.volgende()
        let nummer = s.gebeurtenisNummer
        s.herhaal()
        s.herhaal()
        #expect(s.stapNummer == 2)
        #expect(s.gebeurtenis == .herhaal)
        #expect(s.gebeurtenisNummer == nummer + 2)
    }

    @Test func afvinken() throws {
        let s = try sessie()
        let olie = s.ingredienten[3]
        #expect(!s.isAfgevinkt(olie))
        s.wisselAfgevinkt(olie)
        #expect(s.isAfgevinkt(olie))
        s.volgende()
        #expect(s.isAfgevinkt(olie))
        s.wisselAfgevinkt(olie)
        #expect(!s.isAfgevinkt(olie))
    }

    @Test func ingredientenPerStap() throws {
        let s = try sessie()
        #expect(namen(s.ingredienten(inStap: 0)) == ["flespompoen"])
        #expect(namen(s.ingredienten(inStap: 1)) == ["uien", "verse gember", "olijfolie"])
        #expect(namen(s.ingredienten(inStap: 2)) == ["flespompoen", "groentebouillon", "kerriepoeder"])
        #expect(namen(s.ingredienten(inStap: 3)) == ["kokosmelk", "peper en zout"])
        s.volgende()
        #expect(namen(s.ingredientenInHuidigeStap) == ["uien", "verse gember", "olijfolie"])
    }

    @Test func markeertDeWoordenInDeStap() throws {
        let s = try sessie()
        let tekst = s.stappen[1].tekst as NSString
        let woorden = s.treffers(inStap: 1).map { tekst.substring(with: $0.bereik) }
        #expect(woorden == ["olie", "ui", "gember"])
    }

    @Test func portiesSchalen() throws {
        let s = try sessie(porties: 6)
        #expect(s.factor == 1.5)
        #expect(s.tekst(van: s.ingredienten[6]) == "¾ tl kerriepoeder")
        #expect(s.maat(van: s.ingredienten[4]) == "1½ l")
        #expect(s.tekst(van: s.ingredienten[7]) == "peper en zout")
        s.wijzigPorties(naar: 0)
        #expect(s.porties == 1)
        s.wijzigPorties(naar: 8)
        #expect(s.tekst(van: s.ingredienten[1]) == "4 uien, gesnipperd")
    }

    @Test func zonderBekendePortiesSchaaltNiets() {
        let s = KookSessie(
            titel: "Test", ingredienten: [KookIngredient(id: 0, ruweTekst: "2 uien", hoeveelheid: 2, naam: "uien")],
            stappen: [KookStap(id: 0, tekst: "Snipper de uien.")], receptPorties: 0)
        #expect(s.porties == 1)
        #expect(s.factor == 1)
        #expect(s.tekst(van: s.ingredienten[0]) == "2 uien")
        #expect(namen(s.ingredienten(inStap: 0)) == ["uien"])
    }

    @Test func zonderStappen() {
        let s = KookSessie(titel: "Leeg", ingredienten: [], stappen: [], receptPorties: 2)
        #expect(s.huidigeStap == nil)
        #expect(!s.volgende())
        #expect(!s.isAfgerond)
    }
}

struct IngredientkoppelingTests {
    private func koppel(_ tekst: String, _ namen: [String]) -> [String] {
        Ingredientkoppeling.ingredienten(in: tekst, namen: namen).map { namen[$0] }
    }

    @Test func meervoudEnVerkleinwoord() {
        #expect(koppel("Snipper de ui.", ["uien"]) == ["uien"])
        #expect(koppel("Snijd de uitjes fijn.", ["ui"]) == ["ui"])
        #expect(koppel("Halveer de tomaten.", ["tomaat"]) == ["tomaat"])
        #expect(koppel("Klop de eieren los.", ["eieren"]) == ["eieren"])
        #expect(koppel("Braad de kip.", ["kippen"]) == ["kippen"])
    }

    @Test func samenstellingen() {
        #expect(koppel("Schenk de bouillon erbij.", ["groentebouillon"]) == ["groentebouillon"])
        #expect(koppel("Verhit de olie.", ["olijfolie"]) == ["olijfolie"])
        #expect(koppel("Verhit de olijfolie.", ["olie"]) == ["olie"])
    }

    @Test func kernwoordZonderBijvoeglijkNaamwoord() {
        #expect(koppel("Rasp de gember.", ["verse gember"]) == ["verse gember"])
        #expect(koppel("Strooi de kaas erover.", ["oude kaas"]) == ["oude kaas"])
    }

    /// Liever geen treffer dan een verkeerde.
    @Test func geenValseTreffers() {
        #expect(koppel("Gebruik ongezouten boter.", ["zout"]).isEmpty)
        #expect(koppel("Fruit de prei.", ["ui"]).isEmpty)
        #expect(koppel("Breng op smaak.", ["peper en zout"]).isEmpty)
        #expect(koppel("Haal de pan van het vuur.", ["verse munt"]).isEmpty)
        // Exacte treffer gaat voor: "kokosmelk" is niet de melk.
        #expect(koppel("Roer de kokosmelk erdoor.", ["melk", "kokosmelk"]) == ["kokosmelk"])
    }
}

@MainActor
final class NepSlaapstand: Slaapstand {
    var uitgesteld = false
}

@MainActor
struct SchermAanTests {
    @Test func blijftAanTijdensKookmodus() {
        let nep = NepSlaapstand()
        let scherm = SchermAan(slaapstand: nep)
        #expect(!nep.uitgesteld)
        scherm.kookmodusGeopend()
        #expect(nep.uitgesteld)
        scherm.kookmodusGesloten()
        #expect(!nep.uitgesteld)
    }

    @Test func achtergrondGeeftVrijEnTerugWeerAan() {
        let nep = NepSlaapstand()
        let scherm = SchermAan(slaapstand: nep)
        scherm.kookmodusGeopend()
        scherm.faseGewijzigd(.inactive)
        #expect(nep.uitgesteld)
        scherm.faseGewijzigd(.background)
        #expect(!nep.uitgesteld)
        scherm.faseGewijzigd(.active)
        #expect(nep.uitgesteld)
    }

    @Test func naSluitenNietWeerAanBijTerugkomen() {
        let nep = NepSlaapstand()
        let scherm = SchermAan(slaapstand: nep)
        scherm.kookmodusGeopend()
        scherm.kookmodusGesloten()
        scherm.faseGewijzigd(.background)
        scherm.faseGewijzigd(.active)
        #expect(!nep.uitgesteld)
    }
}

@MainActor
struct KookmatenTests {
    /// K5: bij standaard Dynamic Type ≥ 30 pt op iPhone en ≥ 28 pt op iPad, en meeschalend.
    @Test func staptekstGrootGenoeg() {
        #expect(Kookmaten.stapGrootte(breed: false, tekstgrootte: .large) >= 30)
        #expect(Kookmaten.stapGrootte(breed: true, tekstgrootte: .large) >= 28)
        #expect(Kookmaten.stapGrootte(breed: false, tekstgrootte: .xxxLarge) > 30)
        #expect(Kookmaten.stapGrootte(breed: false, tekstgrootte: .xSmall) >= 30)
        #expect(Kookmaten.stapGrootte(breed: false, tekstgrootte: .accessibility5) <= Kookmaten.stapMaximum)
    }
}

@MainActor
struct KooklogTests {
    @Test func gekooktLegtDatumVast() throws {
        let opslag = legeOpslag()
        let recept = try pompoensoep(in: opslag.context)
        #expect(recept.laatstGekooktOp == nil)
        let datum = Date(timeIntervalSince1970: 1_794_528_000)
        let log = try recept.legGekooktVast(op: datum)
        #expect(log.datum == datum)
        #expect(log.recept == recept)
        #expect(recept.laatstGekooktOp == datum)
        #expect(recept.aantalKeerGekookt == 1)
        #expect(!opslag.context.hasChanges)

        // Een eerdere datum (bijv. achteraf ingevoerd) verschuift laatstGekooktOp niet terug.
        try recept.legGekooktVast(op: datum.addingTimeInterval(-86_400))
        #expect(recept.laatstGekooktOp == datum)
        #expect(recept.aantalKeerGekookt == 2)
        #expect(try opslag.context.count(for: Kooklog.verzoek()) == 2)
    }
}
