import CoreData
import Foundation
import Testing

@testable import Knipsel

struct KaartkleurenTests {
    private static let alleKaartkleuren: [Kleurpaar] = Array(Kaartkleuren.palet.values) + [Kaartkleuren.neutraal]

    @Test func luminantieEnContrastVolgensWCAG() {
        #expect(abs(Hexkleur(0xFFFFFF).relatieveLuminantie - 1) < 0.0001)
        #expect(Hexkleur(0x000000).relatieveLuminantie == 0)
        #expect(abs(Hexkleur.contrast(Hexkleur(0xFFFFFF), Hexkleur(0x000000)) - 21) < 0.001)
        #expect(Hexkleur.contrast(Hexkleur(0x777777), Hexkleur(0x777777)) == 1)
        // Bekende waarde: #767676 op wit is net 4,54:1.
        #expect(abs(Hexkleur.contrast(Hexkleur(0x767676), Hexkleur(0xFFFFFF)) - 4.54) < 0.01)
        // Volgorde maakt niet uit.
        #expect(
            Hexkleur.contrast(Hexkleur(0x2B2622), Hexkleur(0xF0E8DC))
                == Hexkleur.contrast(Hexkleur(0xF0E8DC), Hexkleur(0x2B2622)))
    }

    @Test(arguments: ["titel", "ondertekst"])
    func tekstHaaltMinstens4_5OpElkeKaart(_ soort: String) {
        let tekst = soort == "titel" ? Kaartkleuren.titel : Kaartkleuren.ondertekst
        for kaart in Self.alleKaartkleuren {
            let licht = Hexkleur.contrast(tekst.licht, kaart.licht)
            let donker = Hexkleur.contrast(tekst.donker, kaart.donker)
            #expect(licht >= 4.5, "\(soort) licht op \(String(kaart.licht.waarde, radix: 16)): \(licht)")
            #expect(donker >= 4.5, "\(soort) donker op \(String(kaart.donker.waarde, radix: 16)): \(donker)")
        }
    }

    @Test func donkereVariantIsGedempt() {
        for kaart in Self.alleKaartkleuren {
            #expect(kaart.donker.relatieveLuminantie < kaart.licht.relatieveLuminantie / 4)
        }
    }

    @Test func elkeStandaardcategorieHeeftEenEigenKleur() {
        let namen = StandaardCategorieen.alle.map(\.naam)
        #expect(Set(Kaartkleuren.palet.keys) == Set(namen))
        #expect(Set(Kaartkleuren.palet.values).count == namen.count)
        #expect(!Kaartkleuren.palet.values.contains(Kaartkleuren.neutraal))
        #expect(Kaartkleuren.kleur(voorCategorie: "Soepen") == Kaartkleuren.palet["Soepen"])
        #expect(Kaartkleuren.terugval.count == namen.count)
    }

    @Test func zonderCategorieNeutraal() {
        #expect(Kaartkleuren.kleur(voorCategorie: nil) == Kaartkleuren.neutraal)
        #expect(Kaartkleuren.kleur(voorCategorie: "  ") == Kaartkleuren.neutraal)
    }

    @Test func eigenCategorieKrijgtStabieleKleurUitHetPalet() {
        let kleur = Kaartkleuren.kleur(voorCategorie: "Oma's recepten")
        #expect(Kaartkleuren.terugval.contains(kleur))
        #expect(Kaartkleuren.kleur(voorCategorie: "Oma's recepten") == kleur)
        #expect(Kaartkleuren.kleur(voorCategorie: "oma's recepten") == kleur)
        // FNV-1a ligt vast: dezelfde uitkomst op elk toestel en bij elke start.
        #expect(Kaartkleuren.stabieleHash("") == 0xcbf2_9ce4_8422_2325)
        #expect(Kaartkleuren.stabieleHash("a") == 0xaf63_dc4c_8601_ec8c)
        // Verschillende namen spreiden over het palet.
        let namen = ["Indiaas", "Oma", "Kerst", "Bbq", "Thais", "Italiaans", "Picknick", "Ontbijt op bed"]
        #expect(Set(namen.map { Kaartkleuren.kleur(voorCategorie: $0) }).count > 3)
    }

    @MainActor
    @Test func eersteCategorieOpVolgordeBepaaltKleurEnSymbool() throws {
        let context = legeOpslag().context
        try Inrichting.zaaiStandaard(in: context)
        let lunch = try categorie("Lunch", in: context)
        let salades = try categorie("Salades", in: context)
        #expect(lunch.volgorde < salades.volgorde)

        let recept = Recept(context: context)
        recept.titel = "Linzensalade"
        #expect(recept.kaartCategorie == nil)
        #expect(recept.kaartkleur == Kaartkleuren.neutraal)
        #expect(recept.kaartSymbool == "scissors")

        recept.categorieen = [salades, lunch]
        #expect(recept.kaartCategorie == lunch)
        #expect(recept.kaartkleur == Kaartkleuren.palet["Lunch"])
        #expect(recept.kaartSymbool == lunch.symboolOfStandaard)

        // Andere volgorde in de bibliotheek → andere kaartkleur.
        salades.volgorde = -1
        #expect(recept.kaartCategorie == salades)
        #expect(recept.kaartkleur == Kaartkleuren.palet["Salades"])
    }

    @MainActor
    @Test func weergaveMinutenNeemtTotaleTijdEersteAnders() {
        let context = legeOpslag().context
        let recept = Recept(context: context)
        #expect(recept.weergaveMinuten == 0)
        recept.bereidingstijdMinuten = 25
        #expect(recept.weergaveMinuten == 25)
        recept.totaleTijdMinuten = 60
        #expect(recept.weergaveMinuten == 60)
    }

    @Test func weergaveStandaardKaarten() {
        #expect(BibliotheekWeergave(rawValue: "kaarten") == .kaarten)
        #expect(BibliotheekWeergave(rawValue: "lijst") == .lijst)
        #expect(BibliotheekWeergave.allCases.map(\.titel) == ["Kaarten", "Lijst"])
    }
}
