import CoreData
import Foundation
import Testing

@testable import Knipsel

@MainActor
struct BibliotheekbeheerTests {
    @Test func categorieVerwijderenZetReceptOnderZonderCategorie() throws {
        let context = legeOpslag().context
        try Inrichting.zaaiStandaard(in: context)
        let soepen = try categorie("Soepen", in: context)
        let lunch = try categorie("Lunch", in: context)
        let alleenSoep = try maakRecept("Tomatensoep", categorieen: [soepen], in: context)
        let soepEnLunch = try maakRecept("Erwtensoep", categorieen: [soepen, lunch], in: context)

        #expect(Bibliotheekbeheer.receptenZonderCategorieNaVerwijderen(soepen) == 1)
        try Bibliotheekbeheer.verwijder(soepen)

        // Recepten blijven bestaan.
        #expect(try context.count(for: Recept.verzoek()) == 2)
        #expect(alleenSoep.categorieen?.isEmpty ?? true)
        #expect(soepEnLunch.categorieen == [lunch])

        var filter = ReceptFilter()
        filter.categorie = .zonderCategorie
        #expect(try context.fetch(filter.verzoek()).map(\.titel) == ["Tomatensoep"])
    }

    @Test func verwijderMeldingNoemtAantallen() throws {
        let context = legeOpslag().context
        try Inrichting.zaaiStandaard(in: context)
        let soepen = try categorie("Soepen", in: context)
        let lunch = try categorie("Lunch", in: context)
        #expect(Bibliotheekbeheer.verwijderMelding(soepen) == "Er staan geen recepten in deze categorie.")

        try maakRecept("Tomatensoep", categorieen: [soepen], in: context)
        try maakRecept("Erwtensoep", categorieen: [soepen, lunch], in: context)
        let melding = Bibliotheekbeheer.verwijderMelding(soepen)
        #expect(melding.contains("2 recepten"))
        #expect(melding.contains("1 daarvan heeft geen andere categorie"))
        #expect(melding.contains("Zonder categorie"))
    }

    @Test func nieuweCategorieKomtAchteraan() throws {
        let context = legeOpslag().context
        try Inrichting.zaaiStandaard(in: context)
        let nieuw = try Bibliotheekbeheer.nieuweCategorie(naam: "  Indonesisch ", symbool: "flame", in: context)
        #expect(nieuw.naam == "Indonesisch")
        #expect(nieuw.volgorde == 13)
        #expect(!nieuw.isStandaard)
    }

    @Test func dubbeleOfLegeNaamWordtGeweigerd() throws {
        let context = legeOpslag().context
        try Inrichting.zaaiStandaard(in: context)
        #expect(throws: Bibliotheekbeheer.Fout.naamBestaatAl("Soepen")) {
            try Bibliotheekbeheer.nieuweCategorie(naam: "SOEPEN", symbool: "drop", in: context)
        }
        #expect(throws: Bibliotheekbeheer.Fout.legeNaam) {
            try Bibliotheekbeheer.nieuweCategorie(naam: "   ", symbool: "drop", in: context)
        }
        let lunch = try categorie("Lunch", in: context)
        #expect(throws: Bibliotheekbeheer.Fout.naamBestaatAl("Brood")) {
            try Bibliotheekbeheer.wijzig(lunch, naam: "brood", symbool: "basket", verborgen: false)
        }
    }

    @Test func wijzigenHernoemtEnVerbergt() throws {
        let context = legeOpslag().context
        try Inrichting.zaaiStandaard(in: context)
        let lunch = try categorie("Lunch", in: context)
        // Alleen hoofdletters wijzigen van de eigen naam mag.
        try Bibliotheekbeheer.wijzig(lunch, naam: "lunch", symbool: "sun.max", verborgen: true)
        #expect(lunch.naam == "lunch")
        #expect(lunch.symbool == "sun.max")
        #expect(lunch.verborgen)
    }

    @Test func slepenNummertDeVolgordeOpnieuw() throws {
        let context = legeOpslag().context
        try Inrichting.zaaiStandaard(in: context)
        let verzoek = Categorie.verzoek()
        verzoek.sortDescriptors = [NSSortDescriptor(key: "volgorde", ascending: true)]
        let voor = try context.fetch(verzoek)
        // Dranken (laatste) naar boven.
        try Bibliotheekbeheer.verplaats(voor, van: IndexSet(integer: 12), naar: 0)
        let na = try context.fetch(verzoek).compactMap(\.naam)
        #expect(na.first == "Dranken")
        #expect(na[1] == "Ontbijt & brunch")
        #expect(Set(try context.fetch(verzoek).map(\.volgorde)) == Set((0..<13).map(Int16.init)))
    }

    @Test func labelsToevoegenHernoemenVerwijderen() throws {
        let context = legeOpslag().context
        try Inrichting.zaaiStandaard(in: context)
        let kerst = try Bibliotheekbeheer.nieuwLabel(naam: "Kerst", in: context)
        #expect(throws: Bibliotheekbeheer.Fout.naamBestaatAl("Kerst")) {
            try Bibliotheekbeheer.nieuwLabel(naam: "kerst", in: context)
        }
        try Bibliotheekbeheer.hernoem(kerst, naar: "Kerstmis")
        #expect(kerst.naam == "Kerstmis")

        let recept = try maakRecept("Kerststol", labels: [kerst], in: context)
        try Bibliotheekbeheer.verwijder(kerst)
        #expect(recept.labels?.isEmpty ?? true)
        #expect(try context.count(for: ReceptLabel.verzoek()) == 7)
        #expect(try context.count(for: Recept.verzoek()) == 1)
    }

    @Test func symboolkeuzeHeeftGeenDubbelen() {
        #expect(Set(Bibliotheekbeheer.symbolen).count == Bibliotheekbeheer.symbolen.count)
        #expect(Bibliotheekbeheer.symbolen.count >= 20)
    }
}
