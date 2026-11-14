import CoreData
import Foundation
import Testing

@testable import Knipsel

@MainActor
struct ReceptFilterTests {
    /// Drie verzonnen recepten met verschillende categorieën, labels en ingrediënten.
    private func bibliotheek() throws -> NSManagedObjectContext {
        let context = legeOpslag().context
        try Inrichting.zaaiStandaard(in: context)
        let soepen = try categorie("Soepen", in: context)
        let hoofd = try categorie("Hoofdgerechten", in: context)
        let lunch = try categorie("Lunch", in: context)
        let vega = try label("Vegetarisch", in: context)
        let snel = try label("Snel (< 30 min)", in: context)
        try maakRecept(
            "Romige aardappelsoep", ingredienten: ["500 g kruimige aardappels", "2 stengels prei", "1 l bouillon"],
            categorieen: [soepen], labels: [vega], in: context)
        try maakRecept(
            "Stamppot andijvie", ingredienten: ["1 kg aardappels", "300 g andijvie", "150 g spekjes"],
            categorieen: [hoofd], labels: [snel], in: context)
        try maakRecept(
            "Prei-quiche", ingredienten: ["1 rol bladerdeeg", "4 eieren"], categorieen: [hoofd, lunch],
            labels: [vega, snel], in: context)
        try maakRecept("Losse notitie", in: context)
        return context
    }

    private func titels(_ filter: ReceptFilter, _ context: NSManagedObjectContext) throws -> [String] {
        try context.fetch(filter.verzoek()).compactMap(\.titel)
    }

    @Test func zonderFilterAllesOpTitel() throws {
        let context = try bibliotheek()
        #expect(
            try titels(ReceptFilter(), context) == [
                "Losse notitie", "Prei-quiche", "Romige aardappelsoep", "Stamppot andijvie",
            ])
    }

    @Test func zoekenOpIngredientVindtPrei() throws {
        let context = try bibliotheek()
        var filter = ReceptFilter()
        filter.zoekterm = "prei"
        // Op ingrediënt (soep) én op titel (quiche).
        #expect(try titels(filter, context) == ["Prei-quiche", "Romige aardappelsoep"])
        filter.zoekterm = "  PREI "
        #expect(try titels(filter, context).count == 2)
    }

    @Test func zoekenOpIngredientZonderTitelTreffer() throws {
        let context = try bibliotheek()
        var filter = ReceptFilter()
        filter.zoekterm = "andijvie"
        #expect(try titels(filter, context) == ["Stamppot andijvie"])
        filter.zoekterm = "spekjes"
        #expect(try titels(filter, context) == ["Stamppot andijvie"])
        filter.zoekterm = "bouillon"
        #expect(try titels(filter, context) == ["Romige aardappelsoep"])
    }

    @Test func meerdereWoordenMoetenAllemaalVoorkomen() throws {
        let context = try bibliotheek()
        var filter = ReceptFilter()
        filter.zoekterm = "aardappels prei"
        #expect(try titels(filter, context) == ["Romige aardappelsoep"])
    }

    @Test func zoekenOpGestructureerdeNaam() throws {
        let context = try bibliotheek()
        let ingredient = try #require(try context.fetch(Ingredient.verzoek()).first { $0.ruweTekst == "4 eieren" })
        ingredient.naam = "scharreleieren"
        try context.save()
        var filter = ReceptFilter()
        filter.zoekterm = "scharrel"
        #expect(try titels(filter, context) == ["Prei-quiche"])
    }

    @Test func categorieEnLabelCombineren() throws {
        let context = try bibliotheek()
        var filter = ReceptFilter()
        filter.categorie = .categorie(try categorie("Hoofdgerechten", in: context).objectID)
        #expect(try titels(filter, context) == ["Prei-quiche", "Stamppot andijvie"])

        filter.labels = [try label("Vegetarisch", in: context).objectID]
        #expect(try titels(filter, context) == ["Prei-quiche"])

        // Labels zijn EN: vegetarisch én snel.
        filter.categorie = .alles
        filter.labels.insert(try label("Snel (< 30 min)", in: context).objectID)
        #expect(try titels(filter, context) == ["Prei-quiche"])

        // Met zoekterm erbij.
        filter.labels = [try label("Vegetarisch", in: context).objectID]
        filter.zoekterm = "aardappel"
        #expect(try titels(filter, context) == ["Romige aardappelsoep"])
    }

    @Test func zonderCategorieFilter() throws {
        let context = try bibliotheek()
        var filter = ReceptFilter()
        filter.categorie = .zonderCategorie
        #expect(try titels(filter, context) == ["Losse notitie"])
    }

    @Test func isLeeg() {
        var filter = ReceptFilter()
        #expect(filter.isLeeg)
        #expect(filter.predicaat == nil)
        filter.zoekterm = "  "
        #expect(filter.isLeeg)
        filter.categorie = .zonderCategorie
        #expect(!filter.isLeeg)
    }
}

@MainActor
struct ChiprijTests {
    @Test func legeCategorieStaatNietInDeRij() {
        #expect(!FilterChips.toonInRij(aantal: 0, gekozen: false))
        #expect(FilterChips.toonInRij(aantal: 1, gekozen: false))
    }

    @Test func gekozenCategorieBlijftStaanAlsHijLeegIs() {
        #expect(FilterChips.toonInRij(aantal: 0, gekozen: true))
    }
}
