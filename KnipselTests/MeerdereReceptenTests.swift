import CoreData
import Foundation
import Testing

@testable import Knipsel

// #40: één boodschappenlijst voor meerdere recepten. Optellen over recepten, porties per recept,
// meestal in huis, de bestemming bij gemengde kookboeken, de tekstexport en de selectie.

private func recept(
    _ titel: String, _ regels: [String], standaard: Int = 4, porties: Int? = nil
) -> ReceptBoodschappen {
    ReceptBoodschappen(
        titel: titel, invoer: regels.map { BoodschappenInvoer(regel: $0) }, standaard: standaard,
        porties: porties ?? standaard)
}

struct MeerdereReceptenTests {
    private func teksten(_ recepten: [ReceptBoodschappen], meestal: MeestalInHuis = .standaard) -> [String] {
        BoodschappenLijst.regels(recepten: recepten, meestalInHuis: meestal).map(\.tekst)
    }

    @Test func optellenOverRecepten() {
        let regels = BoodschappenLijst.regels(recepten: [
            recept("Pompoensoep", ["2 uien", "200 ml room", "1 el olijfolie"]),
            recept("Linzensalade", ["1 ui", "0,5 l room", "100 g feta"]),
        ])
        #expect(regels.map(\.tekst) == ["3 uien", "700 ml room", "1 el olijfolie", "100 g feta"])
        #expect(regels[0].herkomst == ["Pompoensoep", "Linzensalade"])
        #expect(regels[1].herkomst == ["Pompoensoep", "Linzensalade"])
        #expect(regels[3].herkomst == ["Linzensalade"])
    }

    @Test func literEnMilliliterNaarLiter() {
        #expect(
            teksten([recept("Soep", ["1 l bouillon"]), recept("Risotto", ["500 ml bouillon"])]) == [
                "1½ l bouillon"
            ])
    }

    @Test func stuksNaarBovenOpHetTotaalNietPerRecept() {
        // Per recept naar boven zou 1 + 1 = 2 citroenen geven; samen is het ½ + ½ = 1.
        #expect(teksten([recept("Vis", ["½ citroen"]), recept("Dressing", ["½ citroen"])]) == ["1 citroen"])
        // Gehalveerd: ½ ui + ½ ui = 1 ui (niet 2).
        #expect(
            teksten([
                recept("Soep", ["1 ui"], standaard: 4, porties: 2),
                recept("Saus", ["1 ui"], standaard: 4, porties: 2),
            ]) == ["1 ui"])
        // 1½ + 1 = 2½ → 3 uien.
        #expect(
            teksten([recept("Soep", ["1 ui"], standaard: 2, porties: 3), recept("Saus", ["1 ui"])]) == ["3 uien"])
    }

    @Test func portiesPerRecept() {
        // 400 g voor 4, gekookt voor 2 = 200 g; 100 g voor 2, gekookt voor 4 = 200 g.
        #expect(
            teksten([
                recept("Pompoensoep", ["400 g pompoen"], standaard: 4, porties: 2),
                recept("Ovenschotel", ["100 g pompoen"], standaard: 2, porties: 4),
            ]) == ["400 g pompoen"])
        // Onbekend aantal porties (0): niet schalen.
        #expect(teksten([recept("Soep", ["2 uien"], standaard: 0, porties: 0)]) == ["2 uien"])
    }

    @Test func meestalInHuisUitgevinkt() {
        let regels = BoodschappenLijst.regels(recepten: [
            recept("Soep", ["2 uien", "1 el olijfolie", "zout"]),
            recept("Salade", ["2 el olijfolie", "peper en zout"]),
        ])
        let inHuis = regels.filter(\.meestalInHuis).map(\.tekst)
        #expect(inHuis == ["3 el olijfolie", "zout", "peper en zout"])
        #expect(regels.first { $0.tekst == "3 el olijfolie" }?.herkomst == ["Soep", "Salade"])
        #expect(regels.filter { !$0.meestalInHuis }.map(\.tekst) == ["2 uien"])
    }

    @Test func eenReceptZonderHerkomst() {
        let regels = BoodschappenLijst.regels([BoodschappenInvoer(regel: "2 uien")], factor: 1)
        #expect(regels.first?.herkomst == [])
    }

    @Test func tekstMetMeerdereRecepten() {
        let regels = BoodschappenLijst.regels(recepten: [
            recept("Pompoensoep", ["2 uien"]), recept("Linzensalade", ["1 ui", "100 g feta"], standaard: 2),
        ])
        #expect(
            BoodschappenLijst.tekst(recepten: [("Pompoensoep", 4), ("Linzensalade", 2)], regels: regels)
                == "Boodschappen · 2 recepten\n– Pompoensoep (4 personen)\n– Linzensalade (2 personen)\n\n• 3 uien\n• 100 g feta"
        )
        // Zonder bekend aantal personen geen haakjes; één recept zoals vanuit het recept zelf.
        #expect(
            BoodschappenLijst.tekst(recepten: [("Soep", 0), ("Salade", 2)], regels: [])
                == "Boodschappen · 2 recepten\n– Soep\n– Salade (2 personen)\n")
        #expect(
            BoodschappenLijst.tekst(recepten: [("Soep", 4)], regels: Array(regels.prefix(1)))
                == "Boodschappen · Soep (4 personen)\n• 3 uien")
    }

    @MainActor @Test func notitieInHerinneringen() {
        #expect(
            HerinneringenDienst.notitie(recepten: ["Pompoensoep", "Linzensalade"])
                == "Pompoensoep, Linzensalade · Knipsel")
    }

    @Test func bestemmingBijGemengdeKookboeken() {
        #expect(VelBestemming.kookboek(voor: [.mijn, .thuis, .thuis]) == .thuis)
        #expect(VelBestemming.kookboek(voor: [.mijn, .mijn, .thuis]) == .mijn)
        #expect(VelBestemming.kookboek(voor: [.mijn, .thuis]) == .mijn)
        #expect(VelBestemming.kookboek(voor: [.thuis]) == .thuis)
        #expect(VelBestemming.kookboek(voor: []) == .mijn)
        #expect(VelBestemming.toonKookboekKeuze(meerdere: true, thuisBestaat: true))
        #expect(!VelBestemming.toonKookboekKeuze(meerdere: true, thuisBestaat: false))
        #expect(!VelBestemming.toonKookboekKeuze(meerdere: false, thuisBestaat: true))
        #expect(VelRecept.titel(aantal: 3) == "Boodschappen · 3 recepten")
    }

    @Test func selectie() {
        var selectie = Selectie<String>()
        selectie.wissel("a")
        #expect(selectie.aantal == 0)  // alleen in selectiemodus
        selectie.start()
        selectie.wissel("b")
        selectie.wissel("a")
        selectie.wissel("c")
        #expect(selectie.gekozen == ["b", "a", "c"])
        selectie.wissel("a")
        #expect(selectie.gekozen == ["b", "c"])
        #expect(selectie.bevat("c") && !selectie.bevat("a"))
        selectie.stop()
        #expect(!selectie.actief && selectie.gekozen.isEmpty)
        selectie.start(met: "d")
        #expect(selectie.actief && selectie.gekozen == ["d"])
        #expect(Selectie<String>.knop(aantal: 3) == "Boodschappen voor 3 recepten")
        #expect(Selectie<String>.knop(aantal: 1) == "Boodschappen voor 1 recept")
    }
}

@MainActor
struct MeerdereReceptenLijstTests {
    @Test func herkomstPerRegelOpDeLijst() throws {
        let opslag = legeOpslag()
        let regels = BoodschappenLijst.regels(recepten: [
            recept("Pompoensoep", ["2 uien"]), recept("Linzensalade", ["1 ui", "100 g feta"]),
        ])
        let resultaat = try Boodschappenlijsten.zetOpLijst(
            regels.map { (LijstRegel($0), $0.herkomst.joined(separator: ", ")) }, kookboek: .thuis,
            context: opslag.context, geheugen: AfdelingGeheugen())
        #expect(resultaat.toegevoegd == 2)
        let lijst = Boodschappenlijsten.items(in: .thuis, context: opslag.context)
        #expect(lijst.map(\.tekstOfNaam) == ["3 uien", "100 g feta"])
        #expect(lijst.map(\.herkomst) == ["Pompoensoep, Linzensalade", "Linzensalade"])
        #expect(Boodschappenlijsten.items(in: .mijn, context: opslag.context).isEmpty)
    }
}
