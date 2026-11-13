import CoreData
import Foundation
import Testing

@testable import Knipsel

@MainActor
struct InrichtingTests {
    @Test func zaaienMaaktStandaardsetAan() throws {
        let context = legeOpslag().context
        try Inrichting.zaaiStandaard(in: context)
        let categorieen = try context.fetch(Categorie.verzoek())
        #expect(categorieen.count == StandaardCategorieen.alle.count)
        #expect(categorieen.allSatisfy { $0.isStandaard })
        #expect(Set(categorieen.compactMap(\.naam)) == Set(StandaardCategorieen.alle.map(\.naam)))
        #expect(try context.count(for: ReceptLabel.verzoek()) == StandaardCategorieen.labels.count)
        // Volgorde zoals in StandaardCategorieen.
        let soepen = try categorie("Soepen", in: context)
        #expect(soepen.volgorde == 2)
        #expect(soepen.symbool == "cup.and.saucer")
    }

    @Test func zaaienIsIdempotent() throws {
        let context = legeOpslag().context
        try Inrichting.zaaiStandaard(in: context)
        try Inrichting.zaaiStandaard(in: context)
        try Inrichting.zaaiStandaard(in: context)
        #expect(try context.count(for: Categorie.verzoek()) == 13)
        #expect(try context.count(for: ReceptLabel.verzoek()) == 7)
    }

    @Test func zaaienSlaatHernoemdeHoofdletterVariantOver() throws {
        let context = legeOpslag().context
        try Bibliotheekbeheer.nieuweCategorie(naam: "soepen", symbool: "drop", in: context)
        try Inrichting.zaaiStandaard(in: context)
        #expect(try context.count(for: Categorie.verzoek()) == 13)
    }

    @Test func richInGebeurtEenKeerPerToestel() throws {
        let defaults = try #require(UserDefaults(suiteName: "knipsel-test-\(UUID().uuidString)"))
        let opslag = legeOpslag()
        opslag.richIn(defaults: defaults)
        #expect(try opslag.context.count(for: Categorie.verzoek()) == 13)

        // De gebruiker verwijdert een standaardcategorie; bij een volgende start komt hij niet terug.
        try Bibliotheekbeheer.verwijder(try categorie("Dranken", in: opslag.context))
        opslag.richIn(defaults: defaults)
        #expect(try opslag.context.count(for: Categorie.verzoek()) == 12)
    }

    /// Twee toestellen die tegelijk voor het eerst starten: na sync staat alles dubbel.
    @Test func ontdubbelenNaTweeToestellen() throws {
        let context = legeOpslag().context
        try Inrichting.zaaiStandaard(in: context)
        let toestelA = try context.fetch(Categorie.verzoek())
        let soepenA = try #require(toestelA.first { $0.naam == "Soepen" })

        // "Toestel B" zaait opnieuw (zonder de controle op naam) en maakt een recept in zijn Soepen.
        for standaard in StandaardCategorieen.alle {
            let dubbel = Categorie(context: context)
            dubbel.naam = standaard.naam
            dubbel.symbool = standaard.symbool
            dubbel.isStandaard = true
        }
        for naam in StandaardCategorieen.labels {
            ReceptLabel(context: context).naam = naam
        }
        try context.save()
        let soepenB = try #require(
            try context.fetch(Categorie.verzoek()).first { $0.naam == "Soepen" && $0 != soepenA })
        let vegetarischB = try #require(
            try context.fetch(ReceptLabel.verzoek()).filter { $0.naam == "Vegetarisch" }.last)
        let recept = try maakRecept("Linzensoep", categorieen: [soepenB], labels: [vegetarischB], in: context)
        #expect(try context.count(for: Categorie.verzoek()) == 26)

        let verwacht = [soepenA, soepenB].min { $0.uuid!.uuidString < $1.uuid!.uuidString }!

        let verwijderd = try Inrichting.ontdubbel(in: context)
        #expect(verwijderd == 13 + 7)
        #expect(try context.count(for: Categorie.verzoek()) == 13)
        #expect(try context.count(for: ReceptLabel.verzoek()) == 7)

        // Het recept staat nu in de overgebleven Soepen, en die is op elk toestel dezelfde.
        let soepen = try categorie("Soepen", in: context)
        #expect(soepen == verwacht)
        #expect(recept.categorieen == [soepen])
        #expect(recept.labels?.compactMap(\.naam) == ["Vegetarisch"])

        // Nog een keer ontdubbelen verandert niets.
        #expect(try Inrichting.ontdubbel(in: context) == 0)
    }

    @Test func ontdubbelenNegeertHoofdlettersEnSpaties() throws {
        let context = legeOpslag().context
        try Bibliotheekbeheer.nieuweCategorie(naam: "Indonesisch", symbool: "flame", in: context)
        let dubbel = Categorie(context: context)
        dubbel.naam = " indonesisch "
        let recept = try maakRecept("Sateh", categorieen: [dubbel], in: context)

        #expect(try Inrichting.ontdubbel(in: context) == 1)
        #expect(try context.count(for: Categorie.verzoek()) == 1)
        #expect(recept.categorieen?.count == 1)
    }

    @Test func receptInBeideDubbelenHoudtEenCategorie() throws {
        let context = legeOpslag().context
        let eerste = try Bibliotheekbeheer.nieuweCategorie(naam: "Brood", symbool: "basket", in: context)
        let tweede = Categorie(context: context)
        tweede.naam = "Brood"
        let recept = try maakRecept("Focaccia", categorieen: [eerste, tweede], in: context)

        try Inrichting.ontdubbel(in: context)
        #expect(recept.categorieen?.count == 1)
        #expect(recept.categorieen?.first?.naam == "Brood")
    }
}
