import CoreData
import Foundation
import Testing

@testable import Knipsel

/// Hulp voor tests: een lege opslag in het geheugen.
@MainActor
func legeOpslag() -> Opslag {
    let opslag = Opslag(inGeheugen: true)
    #expect(opslag.laadfout == nil)
    return opslag
}

@MainActor
func categorie(_ naam: String, in context: NSManagedObjectContext) throws -> Categorie {
    let verzoek = Categorie.verzoek()
    verzoek.predicate = NSPredicate(format: "naam == %@", naam)
    return try #require(try context.fetch(verzoek).first)
}

@MainActor
func label(_ naam: String, in context: NSManagedObjectContext) throws -> ReceptLabel {
    let verzoek = ReceptLabel.verzoek()
    verzoek.predicate = NSPredicate(format: "naam == %@", naam)
    return try #require(try context.fetch(verzoek).first)
}

@MainActor
@discardableResult
func maakRecept(
    _ titel: String, ingredienten: [String] = [], categorieen: [Categorie] = [], labels: [ReceptLabel] = [],
    in context: NSManagedObjectContext
) throws -> Recept {
    var invoer = ReceptInvoer()
    invoer.titel = titel
    invoer.ingredientenTekst = ingredienten.joined(separator: "\n")
    invoer.categorieen = Set(categorieen.map(\.objectID))
    invoer.labels = Set(labels.map(\.objectID))
    return try invoer.bewaar(in: context)
}

@MainActor
struct ModelTests {
    /// CloudKit weigert een model met verplichte attributen zonder standaardwaarde, unieke
    /// constraints, verplichte of geordende relaties, of relaties zonder inverse.
    @Test func modelVoldoetAanCloudKitRegels() {
        let model = Opslag.model
        #expect(
            Set(model.entities.compactMap(\.name)) == ["Recept", "Ingredient", "Stap", "Categorie", "Label", "Kooklog"])
        for entiteit in model.entities {
            #expect(entiteit.uniquenessConstraints.isEmpty, "\(entiteit.name ?? "")")
            for attribuut in entiteit.attributesByName.values {
                #expect(
                    attribuut.isOptional || attribuut.defaultValue != nil, "\(entiteit.name ?? "").\(attribuut.name)")
            }
            for relatie in entiteit.relationshipsByName.values {
                #expect(relatie.isOptional, "\(entiteit.name ?? "").\(relatie.name)")
                #expect(relatie.inverseRelationship != nil, "\(entiteit.name ?? "").\(relatie.name)")
                #expect(!relatie.isOrdered, "\(entiteit.name ?? "").\(relatie.name)")
            }
        }
    }

    @Test func nieuwReceptStaatInMijnRecepten() throws {
        let context = legeOpslag().context
        let recept = try maakRecept("Testsoep", in: context)
        #expect(recept.kookboek == Kookboek.mijn.rawValue)
        #expect(recept.uuid != nil)
        #expect(recept.aangemaaktOp != nil)
    }

    @Test func opslagInGeheugenSynchroniseertNiet() {
        let opslag = Opslag(inGeheugen: true, cloudKitContainer: "iCloud.com.peterbijkerk.knipsel")
        #expect(!opslag.synchroniseert)
        #expect(opslag.container.persistentStoreDescriptions.first?.cloudKitContainerOptions == nil)
    }

    @Test func historyTrackingEnWijzigingsmeldingenStaanAan() throws {
        let beschrijving = try #require(legeOpslag().container.persistentStoreDescriptions.first)
        #expect(beschrijving.options[NSPersistentHistoryTrackingKey] as? NSNumber == true)
        #expect(beschrijving.options[NSPersistentStoreRemoteChangeNotificationPostOptionKey] as? NSNumber == true)
    }

    @Test func receptVerwijderenRuimtIngredientenEnStappenOp() throws {
        let context = legeOpslag().context
        var invoer = ReceptInvoer()
        invoer.titel = "Weg ermee"
        invoer.ingredientenTekst = "1 ui\n2 tenen knoflook"
        invoer.stappenTekst = "Snipper de ui."
        let recept = try invoer.bewaar(in: context)
        context.delete(recept)
        try context.save()
        #expect(try context.count(for: Ingredient.verzoek()) == 0)
        #expect(try context.count(for: Stap.verzoek()) == 0)
    }
}
