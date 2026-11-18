import CloudKit
import CoreData
import Foundation
import Testing

@testable import Knipsel

// Fase 8 (#9): Thuis delen. Twee stores zonder CloudKit (privé en gedeeld, in het geheugen of als
// tijdelijk bestand); de CloudKit-kant zit achter `DeelDienst` en is hier een nep.

/// Nep voor de CloudKit-kant: onthoudt wat er gedeeld, gestopt en verlaten is.
@MainActor
final class NepDeelDienst: DeelDienst {
    var isBeschikbaar = true
    var nepStatus = ThuisStatus.nietGedeeld
    private(set) var gedeeld: [NSManagedObjectID] = []
    private(set) var gestopt = false
    private(set) var verlaten = false
    /// Hoeveel Thuis-recepten er nog waren op het moment van stoppen of vertrekken.
    private(set) var thuisBijStoppen: Int?
    var context: NSManagedObjectContext?
    /// Laat `deel` falen zodra er een object van deze entiteit bij zit (entiteitnaam → fout).
    var faaltVoor: [String: any Error] = [:]
    /// Elke aanroep van `deel`, met de entiteiten erin.
    private(set) var aanroepen: [Set<String>] = []

    func status() async throws -> ThuisStatus { nepStatus }
    func deel(_ objecten: [NSManagedObjectID]) async throws {
        let entiteiten = Set(objecten.compactMap(\.entity.name))
        aanroepen.append(entiteiten)
        if let fout = entiteiten.lazy.compactMap({ self.faaltVoor[$0] }).first { throw fout }
        gedeeld += objecten
    }
    func nietGedeeld(_ objecten: [NSManagedObjectID]) -> [NSManagedObjectID] {
        objecten.filter { !gedeeld.contains($0) }
    }
    func uitnodiging() async throws -> (share: CKShare, container: CKContainer)? { nil }
    func stopMetDelen() async throws {
        gestopt = true
        thuisBijStoppen = try context.map { try Kookboeken.recepten(in: .thuis, context: $0).count }
    }
    func verlaat() async throws { verlaten = true }
    func accepteer(_ metadata: CKShare.Metadata) async throws {}

    static func eigenaarMetHuisgenoot() -> ThuisStatus {
        ThuisStatus(
            rol: .eigenaar,
            deelnemers: [
                ThuisDeelnemer(
                    id: "a", naam: "Peter Voorbeeld", contact: "peter@example.com", status: .doetMee, isEigenaar: true,
                    isIkZelf: true, magBewerken: true),
                ThuisDeelnemer(
                    id: "b", naam: "Sam Huisgenoot", contact: "sam@example.com", status: .doetMee, isEigenaar: false,
                    isIkZelf: false, magBewerken: true),
            ])
    }
}

@MainActor
struct ThuisTests {
    // MARK: Hulp

    /// Een opslag met de standaardcategorieën in Mijn recepten.
    private func opslag() throws -> Opslag {
        let opslag = legeOpslag()
        try Inrichting.zaaiStandaard(in: opslag.context)
        return opslag
    }

    /// Doet alsof je bent uitgenodigd: Thuis staat dan in de gedeelde store (er staat iets in).
    @discardableResult
    private func alsDeelnemer(_ opslag: Opslag, categorie naam: String = "Soepen") throws -> Categorie {
        let context = opslag.context
        let categorie = Categorie(context: context)
        categorie.naam = naam
        categorie.symbool = "cup.and.saucer"
        categorie.kookboek = Kookboek.thuis.rawValue
        context.assign(categorie, to: try #require(opslag.gedeeldeStore))
        try context.save()
        return categorie
    }

    /// Een volledig recept: ingrediënten, stappen, foto, kooklog, beoordeling, notities, categorieën
    /// en labels.
    private func volRecept(_ titel: String, in context: NSManagedObjectContext) throws -> Recept {
        var invoer = ReceptInvoer()
        invoer.titel = titel
        invoer.intro = "Verzonnen intro."
        invoer.porties = 4
        invoer.bereidingstijdMinuten = 25
        invoer.notities = "Minder zout."
        invoer.bronNaam = "Testblad"
        invoer.ingredientenTekst = "Voor de soep:\n1 ui\n500 g pompoen"
        invoer.stappenTekst = "Snipper de ui.\n\nKook de pompoen gaar."
        invoer.categorieen = [
            try categorie("Soepen", in: context).objectID, try categorie("Lunch", in: context).objectID,
        ]
        invoer.labels = [try label("Vegetarisch", in: context).objectID]
        let recept = try invoer.bewaar(in: context)
        recept.beoordeling = 4
        try recept.zetFoto(Data([1, 2, 3]), op: Date(timeIntervalSince1970: 1000))
        try recept.legGekooktVast(op: Date(timeIntervalSince1970: 2000))
        try recept.legGekooktVast(op: Date(timeIntervalSince1970: 3000))
        return recept
    }

    private func store(van object: NSManagedObject) -> Kookboeken.StoreSoort? {
        Kookboeken.soort(van: object.objectID.persistentStore)
    }

    // MARK: Stores

    @Test func opslagHeeftEenPriveEnEenGedeeldeStore() throws {
        let opslag = legeOpslag()
        let prive = try #require(opslag.priveStore)
        let gedeeld = try #require(opslag.gedeeldeStore)
        #expect(prive !== gedeeld)
        #expect(opslag.container.persistentStoreDescriptions.count == 2)
        for beschrijving in opslag.container.persistentStoreDescriptions {
            #expect(beschrijving.options[NSPersistentHistoryTrackingKey] as? NSNumber == true)
            #expect(beschrijving.options[NSPersistentStoreRemoteChangeNotificationPostOptionKey] as? NSNumber == true)
            #expect(beschrijving.cloudKitContainerOptions == nil)
        }
        // Zonder Thuis-deelname komen nieuwe recepten, ook in Thuis, in de privéstore.
        let recept = try maakRecept("Soep", in: opslag.context)
        #expect(store(van: recept) == .prive)
    }

    /// Een bestaande database (modelversie 2, één store) opent na de update met alle recepten in
    /// Mijn recepten; de gedeelde store komt er leeg naast.
    @Test func bestaandeV2DatabaseOpentMetAllesInMijnRecepten() throws {
        let momd = try #require(Bundle(for: Recept.self).url(forResource: "Knipsel", withExtension: "momd"))
        let v2 = try #require(NSManagedObjectModel(contentsOf: momd.appendingPathComponent("Knipsel 2.mom")))
        #expect(v2.entitiesByName["Categorie"]?.attributesByName["kookboek"] == nil)

        let map = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: map, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: map) }

        let oud = NSPersistentContainer(name: "Knipsel", managedObjectModel: v2)
        oud.persistentStoreDescriptions = [
            NSPersistentStoreDescription(url: map.appendingPathComponent("Knipsel.sqlite"))
        ]
        var fout: (any Error)?
        oud.loadPersistentStores { _, error in fout = error }
        #expect(fout == nil)
        let c = oud.viewContext
        let soepen = NSEntityDescription.insertNewObject(forEntityName: "Categorie", into: c)
        soepen.setValue("Soepen", forKey: "naam")
        soepen.setValue(UUID(), forKey: "uuid")
        let vega = NSEntityDescription.insertNewObject(forEntityName: "Label", into: c)
        vega.setValue("Vegetarisch", forKey: "naam")
        let uuid = UUID()
        for titel in ["Oude erwtensoep", "Oude stoofpot"] {
            let recept = NSEntityDescription.insertNewObject(forEntityName: "Recept", into: c)
            recept.setValue(titel, forKey: "titel")
            recept.setValue(titel == "Oude erwtensoep" ? uuid : UUID(), forKey: "uuid")
            recept.setValue(Set([soepen]), forKey: "categorieen")
            recept.setValue(Set([vega]), forKey: "labels")
            let ingredient = NSEntityDescription.insertNewObject(forEntityName: "Ingredient", into: c)
            ingredient.setValue("1 ui", forKey: "ruweTekst")
            ingredient.setValue(recept, forKey: "recept")
        }
        try c.save()
        for store in oud.persistentStoreCoordinator.persistentStores {
            try oud.persistentStoreCoordinator.remove(store)
        }

        let nieuw = Opslag(map: map, cloudKitContainer: nil)
        #expect(nieuw.laadfout == nil)
        #expect(!nieuw.synchroniseert)
        let context = nieuw.context
        let recepten = try context.fetch(ReceptFilter().verzoek())
        #expect(recepten.map(\.titel) == ["Oude erwtensoep", "Oude stoofpot"])
        #expect(recepten.allSatisfy { $0.kookboekWaarde == .mijn && store(van: $0) == .prive })
        #expect(recepten.first?.uuid == uuid)
        #expect(recepten.allSatisfy { $0.gesorteerdeIngredienten.count == 1 })
        let categorie = try #require(recepten.first?.categorieen?.first)
        #expect(categorie.kookboekWaarde == .mijn)
        #expect(recepten.first?.labels?.first?.kookboekWaarde == .mijn)
        #expect(FileManager.default.fileExists(atPath: map.appendingPathComponent(Opslag.gedeeldeStoreNaam).path))
        let inGedeeld = Recept.verzoek()
        inGedeeld.affectedStores = [try #require(nieuw.gedeeldeStore)]
        #expect(try context.count(for: inGedeeld) == 0)
        for store in nieuw.container.persistentStoreCoordinator.persistentStores {
            try nieuw.container.persistentStoreCoordinator.remove(store)
        }
    }

    // MARK: Verplaatsen

    @Test func naarThuisBehoudtAlleInhoudUuidFotoEnCategorieenOpNaam() throws {
        let opslag = try opslag()
        let context = opslag.context
        let origineel = try volRecept("Pompoensoep", in: context)
        let uuid = try #require(origineel.uuid)
        let priveSoepen = try categorie("Soepen", in: context)

        let thuis = try Kookboeken.verplaats(origineel, naar: .thuis)

        #expect(thuis.isThuis)
        #expect(thuis.uuid == uuid)
        #expect(thuis.titel == "Pompoensoep")
        #expect(thuis.intro == "Verzonnen intro.")
        #expect(thuis.porties == 4)
        #expect(thuis.bereidingstijdMinuten == 25)
        #expect(thuis.notities == "Minder zout.")
        #expect(thuis.bronNaam == "Testblad")
        #expect(thuis.beoordeling == 4)
        #expect(thuis.fotoData == Data([1, 2, 3]))
        #expect(thuis.fotoGewijzigdOp == Date(timeIntervalSince1970: 1000))
        #expect(thuis.aantalKeerGekookt == 2)
        #expect(thuis.laatstGekooktOp == Date(timeIntervalSince1970: 3000))
        #expect(thuis.gesorteerdeIngredienten.map(\.ruweTekst) == ["1 ui", "500 g pompoen"])
        #expect(thuis.gesorteerdeIngredienten.map(\.groep) == ["Voor de soep", "Voor de soep"])
        #expect(thuis.gesorteerdeIngredienten.last?.naam == "pompoen")
        #expect(thuis.gesorteerdeStappen.map(\.tekst) == ["Snipper de ui.", "Kook de pompoen gaar."])
        #expect(Set(thuis.gesorteerdeCategorieen.map(\.naamOfStandaard)) == ["Soepen", "Lunch"])
        #expect(thuis.gesorteerdeLabels.map(\.naamOfStandaard) == ["Vegetarisch"])
        // Eigen Thuis-categorieën: een Thuis-recept hangt nooit aan een privécategorie.
        #expect(thuis.gesorteerdeCategorieen.allSatisfy { $0.kookboekWaarde == .thuis })
        #expect(thuis.gesorteerdeLabels.allSatisfy { $0.kookboekWaarde == .thuis })
        #expect(!(thuis.categorieen ?? []).contains(priveSoepen))
        #expect(priveSoepen.kookboekWaarde == .mijn)
        // Het origineel is weg, de rest is één keer bewaard.
        #expect(try context.count(for: Recept.verzoek()) == 1)
        #expect(try context.count(for: Ingredient.verzoek()) == 2)
        #expect(try context.count(for: Kooklog.verzoek()) == 2)
        #expect(!context.hasChanges)
        // Eigenaar of nog niet gedeeld: in de privéstore (de share zet hem in zijn zone).
        #expect(store(van: thuis) == .prive)
        #expect((thuis.ingredienten ?? []).allSatisfy { store(van: $0) == .prive })
    }

    @Test func alsDeelnemerKomtThuisInDeGedeeldeStoreEnHergebruiktCategorieen() throws {
        let opslag = try opslag()
        let context = opslag.context
        let thuisSoepen = try alsDeelnemer(opslag)
        let recept = try volRecept("Pompoensoep", in: context)

        let thuis = try Kookboeken.verplaats(recept, naar: .thuis)

        #expect(store(van: thuis) == .gedeeld)
        for onderdeel in Array(thuis.ingredienten ?? []) as [NSManagedObject] + Array(thuis.stappen ?? [])
            + Array(thuis.kooklog ?? [])
        {
            #expect(store(van: onderdeel) == .gedeeld)
        }
        // "Soepen" bestond al in Thuis: hergebruikt. "Lunch" en "Vegetarisch" zijn nieuw in Thuis.
        #expect((thuis.categorieen ?? []).contains(thuisSoepen))
        let thuisCategorieen = Categorie.verzoek()
        thuisCategorieen.affectedStores = [try #require(opslag.gedeeldeStore)]
        #expect(Set(try context.fetch(thuisCategorieen).compactMap(\.naam)) == ["Soepen", "Lunch"])
        #expect(thuis.gesorteerdeCategorieen.allSatisfy { store(van: $0) == .gedeeld })
        #expect(thuis.gesorteerdeLabels.allSatisfy { store(van: $0) == .gedeeld })
    }

    @Test func terugNaarMijnReceptenGebruiktDePrivecategorieen() throws {
        let opslag = try opslag()
        let context = opslag.context
        try alsDeelnemer(opslag)
        let aantalPrive = try context.count(for: Categorie.verzoek()) - 1
        let thuis = try Kookboeken.verplaats(try volRecept("Pompoensoep", in: context), naar: .thuis)
        let uuid = thuis.uuid

        let terug = try Kookboeken.verplaats(thuis, naar: .mijn)

        #expect(terug.kookboekWaarde == .mijn)
        #expect(store(van: terug) == .prive)
        #expect(terug.uuid == uuid)
        #expect(terug.aantalKeerGekookt == 2)
        #expect(terug.fotoData == Data([1, 2, 3]))
        #expect(terug.gesorteerdeCategorieen.allSatisfy { $0.kookboekWaarde == .mijn && store(van: $0) == .prive })
        #expect(terug.categorieen?.contains(try categorie("Soepen", in: context)) == true)
        // Geen nieuwe privécategorieën: de bestaande zijn hergebruikt.
        let prive = Categorie.verzoek()
        prive.affectedStores = [try #require(opslag.priveStore)]
        #expect(try context.count(for: prive) == aantalPrive)
        #expect(try context.count(for: Recept.verzoek()) == 1)
    }

    @Test func verplaatsenNaarHetzelfdeKookboekDoetNiets() throws {
        let context = try opslag().context
        let recept = try maakRecept("Soep", in: context)
        #expect(try Kookboeken.verplaats(recept, naar: .mijn) === recept)
    }

    // MARK: Categorieën en labels per kookboek

    @Test func standaardsetAlleenInMijnRecepten() throws {
        let opslag = legeOpslag()
        try alsDeelnemer(opslag, categorie: "Soepen")
        try Inrichting.zaaiStandaard(in: opslag.context)
        let alle = try opslag.context.fetch(Categorie.verzoek())
        let mijn = alle.filter { $0.kookboekWaarde == .mijn }
        #expect(mijn.count == StandaardCategorieen.alle.count)
        #expect(mijn.allSatisfy { store(van: $0) == .prive })
        // De Thuis-"Soepen" telt niet mee voor de privéset, en krijgt geen standaardset erbij.
        #expect(mijn.contains { $0.naam == "Soepen" })
        #expect(alle.filter { $0.kookboekWaarde == .thuis }.map(\.naam) == ["Soepen"])
        let labels = try opslag.context.fetch(ReceptLabel.verzoek())
        #expect(labels.allSatisfy { $0.kookboekWaarde == .mijn && store(van: $0) == .prive })
        // Nog eens zaaien (tweede toestel) maakt niets dubbel.
        try Inrichting.zaaiStandaard(in: opslag.context)
        #expect(try opslag.context.count(for: Categorie.verzoek()) == alle.count)
    }

    /// Twee huisgenoten maken tegelijk een Thuis-"Soepen" aan: na sync blijft er één (de laagste
    /// uuid, op elk toestel dezelfde) met beide recepten. De privé-"Soepen" blijft.
    @Test func ontdubbelenInThuisOpNaamPerKookboek() throws {
        let opslag = try opslag()
        let context = opslag.context
        let gedeeld = try #require(opslag.gedeeldeStore)
        var dubbelen: [Categorie] = []
        for naam in ["Soepen", "soepen "] {
            let categorie = Categorie(context: context)
            categorie.naam = naam
            categorie.kookboek = Kookboek.thuis.rawValue
            context.assign(categorie, to: gedeeld)
            dubbelen.append(categorie)
        }
        try context.save()
        for (index, categorie) in dubbelen.enumerated() {
            let recept = Recept(context: context)
            recept.titel = "Thuissoep \(index)"
            recept.kookboek = Kookboek.thuis.rawValue
            recept.categorieen = [categorie]
        }
        try context.save()
        let blijver = try #require(dubbelen.min { $0.uuid!.uuidString < $1.uuid!.uuidString })

        let verwijderd = try Inrichting.ontdubbel(in: context)

        #expect(verwijderd == 1)
        let soepen = try context.fetch(Categorie.verzoek()).filter {
            Inrichting.sleutel($0.naamOfStandaard) == "soepen"
        }
        #expect(soepen.count == 2)
        #expect(Set(soepen.map(\.kookboekWaarde)) == [.mijn, .thuis])
        #expect(blijver.aantalRecepten == 2)
        #expect(!blijver.isDeleted)
    }

    @Test func eenKeuzeUitHetAndereKookboekWordtDeGelijknamige() throws {
        let opslag = try opslag()
        let context = opslag.context
        try alsDeelnemer(opslag)
        // Bewaar in Thuis met privécategorieën gekozen (de keuzelijst toont één per naam).
        var invoer = ControleInvoer(concept: ReceptConcept())
        invoer.concept.titel = "Linzensoep"
        invoer.categorieen = [try categorie("Soepen", in: context).objectID]
        invoer.labels = [try label("Vegetarisch", in: context).objectID]
        invoer.kookboek = .thuis
        let recept = try invoer.receptInvoer.bewaar(in: context)
        #expect(recept.isThuis)
        #expect(store(van: recept) == .gedeeld)
        #expect(recept.gesorteerdeCategorieen.map(\.naamOfStandaard) == ["Soepen"])
        #expect(recept.gesorteerdeCategorieen.allSatisfy { $0.kookboekWaarde == .thuis && store(van: $0) == .gedeeld })
        #expect(recept.gesorteerdeLabels.allSatisfy { $0.kookboekWaarde == .thuis && store(van: $0) == .gedeeld })

        // Bewerken met een privécategorie erbij: wordt een Thuis-"Lunch".
        var bewerk = ReceptInvoer(recept: recept)
        #expect(bewerk.kookboek == .thuis)
        bewerk.categorieen.insert(try categorie("Lunch", in: context).objectID)
        try bewerk.bewaar(in: context, recept: recept)
        #expect(Set(recept.gesorteerdeCategorieen.map(\.naamOfStandaard)) == ["Soepen", "Lunch"])
        #expect(recept.gesorteerdeCategorieen.allSatisfy { $0.kookboekWaarde == .thuis })
        // En de privé-"Lunch" heeft geen Thuis-recept gekregen.
        #expect(try categorie("Lunch", in: context).aantalRecepten == 0)
    }

    @Test func nieuweOnderdelenVanEenThuisReceptVolgenHunStore() throws {
        let opslag = try opslag()
        try alsDeelnemer(opslag)
        let thuis = try Kookboeken.verplaats(try maakRecept("Soep", in: opslag.context), naar: .thuis)
        // "Gekookt" na de kookmodus en een stap erbij: anders zou het bewaren mislukken (relatie
        // tussen stores).
        let log = try thuis.legGekooktVast()
        #expect(store(van: log) == .gedeeld)
        var invoer = ReceptInvoer(recept: thuis)
        invoer.stappenTekst = "Nieuwe stap."
        try invoer.bewaar(in: opslag.context, recept: thuis)
        #expect(thuis.gesorteerdeStappen.allSatisfy { store(van: $0) == .gedeeld })
    }

    @Test func keuzelijstToontEenPerNaam() throws {
        let opslag = try opslag()
        let context = opslag.context
        let thuisSoepen = try alsDeelnemer(opslag)
        let priveSoepen = try categorie("Soepen", in: context)
        let alle = try context.fetch(Categorie.verzoek())
        let mijn = Keuzeopties.uniek(alle)
        #expect(mijn.filter { $0.naam == "Soepen" } == [priveSoepen])
        #expect(mijn.count == StandaardCategorieen.alle.count)
        // Voor een Thuis-recept wint de Thuis-categorie, en een gekozen object wint altijd.
        #expect(Keuzeopties.uniek(alle, kookboek: .thuis).contains(thuisSoepen))
        #expect(Keuzeopties.uniek(alle, gekozen: [thuisSoepen.objectID]).contains(thuisSoepen))
    }

    // MARK: Bibliotheek

    @Test func bibliotheekZietBeideStoresEnFiltertOpKookboek() throws {
        let opslag = try opslag()
        let context = opslag.context
        try alsDeelnemer(opslag)
        try maakRecept("Mijn stoofpot", in: context)
        try Kookboeken.verplaats(try maakRecept("Thuis-soep", in: context), naar: .thuis)

        #expect(try context.fetch(ReceptFilter().verzoek()).map(\.titel) == ["Mijn stoofpot", "Thuis-soep"])
        var filter = ReceptFilter()
        filter.kookboek = .thuis
        #expect(!filter.isLeeg)
        #expect(try context.fetch(filter.verzoek()).map(\.titel) == ["Thuis-soep"])
        filter.kookboek = .mijn
        #expect(try context.fetch(filter.verzoek()).map(\.titel) == ["Mijn stoofpot"])
        #expect(Bibliotheekkookboeken.toon(aantalThuis: 1, gekozen: nil))
        #expect(!Bibliotheekkookboeken.toon(aantalThuis: 0, gekozen: nil))
        #expect(Bibliotheekkookboeken.toon(aantalThuis: 0, gekozen: .thuis))
    }

    @Test func chipsVoegenGelijknamigeCategorieenEnLabelsSamen() throws {
        let opslag = try opslag()
        let context = opslag.context
        try alsDeelnemer(opslag)
        let soepen = try categorie("Soepen", in: context)
        let vega = try label("Vegetarisch", in: context)
        try maakRecept("Mijn erwtensoep", categorieen: [soepen], labels: [vega], in: context)
        for titel in ["Thuis-tomatensoep", "Thuis-uiensoep"] {
            try Kookboeken.verplaats(
                try maakRecept(titel, categorieen: [soepen], labels: [vega], in: context), naar: .thuis)
        }
        let categorieen = try context.fetch(Categorie.verzoek())
        #expect(categorieen.filter { $0.naam == "Soepen" }.count == 2)

        let groepen = CategorieGroep.groepeer(categorieen)
        let soepGroep = try #require(groepen.first { $0.naam == "Soepen" })
        #expect(groepen.filter { $0.naam == "Soepen" }.count == 1)
        #expect(soepGroep.aantal == 3)
        #expect(soepGroep.categorieen.first === soepen)
        #expect(CategorieGroep.groepeer(categorieen, kookboek: .thuis).first { $0.naam == "Soepen" }?.aantal == 2)
        // Lege categorieën blijven uit de rij (#29/#32), ook na samenvoegen.
        let lunch = try #require(groepen.first { $0.naam == "Lunch" })
        #expect(!FilterChips.toonInRij(aantal: lunch.aantal, gekozen: false))

        var filter = ReceptFilter()
        filter.categorie = soepGroep.keuze
        #expect(try context.fetch(filter.verzoek()).count == 3)
        filter.kookboek = .thuis
        #expect(try context.fetch(filter.verzoek()).count == 2)

        let labelGroepen = LabelGroep.groepeer(try context.fetch(ReceptLabel.verzoek()))
        #expect(labelGroepen.filter { $0.naam == "Vegetarisch" }.map(\.aantal) == [3])
        var opLabel = ReceptFilter()
        opLabel.labels = ["vegetarisch"]
        #expect(try context.fetch(opLabel.verzoek()).count == 3)
    }

    @Test func verborgenCategorieVerbergtDeHeleGroep() throws {
        let opslag = try opslag()
        let context = opslag.context
        try alsDeelnemer(opslag)
        let soepen = try categorie("Soepen", in: context)
        try Bibliotheekbeheer.wijzig(soepen, naam: "Soepen", symbool: "cup.and.saucer", verborgen: true)
        #expect(!CategorieGroep.groepeer(try context.fetch(Categorie.verzoek())).contains { $0.naam == "Soepen" })
    }

    @Test func hernoemenInBeheerNeemtDeThuisCategorieMee() throws {
        let opslag = try opslag()
        let context = opslag.context
        let thuisSoepen = try alsDeelnemer(opslag)
        try Bibliotheekbeheer.wijzig(
            try categorie("Soepen", in: context), naam: "Soep & bouillon", symbool: "flame", verborgen: false)
        #expect(thuisSoepen.naam == "Soep & bouillon")
        #expect(thuisSoepen.symbool == "flame")
        // Beheer kijkt alleen naar Mijn recepten: een nieuwe privé-"Ovenschotels" mag naast een Thuis-exemplaar.
        try alsDeelnemer(opslag, categorie: "Ovenschotels")
        #expect(throws: Never.self) {
            try Bibliotheekbeheer.nieuweCategorie(naam: "Ovenschotels", symbool: "flame", in: context)
        }
    }

    // MARK: Verder met… en Siri

    @Test func kookVoortgangMigreertVanObjectIDNaarUuid() throws {
        let context = try opslag().context
        let recept = try maakRecept("Stoofpot", in: context)
        let weg = try maakRecept("Weg", in: context)
        let wegURI = weg.objectID.uriRepresentation()
        context.delete(weg)
        try context.save()
        let defaults = try #require(UserDefaults(suiteName: "ThuisTests-\(UUID().uuidString)"))
        let voortgang = KookVoortgang(defaults: defaults)
        let nu = Date.now
        voortgang.bewaar(
            .init(recept: recept.objectID.uriRepresentation(), stapIndex: 2, aantalStappen: 5, porties: 4, datum: nu))
        voortgang.bewaar(.init(recept: wegURI, stapIndex: 1, aantalStappen: 3, porties: 2, datum: nu))

        #expect(voortgang.migreer(in: context) == 1)

        #expect(voortgang.alle.map(\.recept) == [recept.verwijzing])
        #expect(voortgang.alle.first?.stapIndex == 2)
        #expect(VerderKeuze.recept(bij: try #require(recept.verwijzing), in: context) == recept)
        // Nog eens migreren verandert niets.
        #expect(voortgang.migreer(in: context) == 0)
    }

    @Test func verderMetOverleeftVerplaatsenNaarThuis() throws {
        let opslag = try opslag()
        let context = opslag.context
        try alsDeelnemer(opslag)
        var invoer = ReceptInvoer()
        invoer.titel = "Lasagne"
        invoer.stappenTekst = "Een.\n\nTwee.\n\nDrie."
        let recept = try invoer.bewaar(in: context)
        let sleutel = recept.sleutelURL
        #expect(Recept.uuid(uitVerwijzing: sleutel) == recept.uuid)

        let thuis = try Kookboeken.verplaats(recept, naar: .thuis)

        #expect(thuis.sleutelURL == sleutel)
        #expect(VerderKeuze.recept(bij: sleutel, in: context) === thuis)
        let router = KookRouter()
        router.kook(recept: sleutel)
        let verzoek = try #require(router.neemKookVerzoekAf())
        #expect(KookRouter.keuze(voor: verzoek, in: context)?.recept === thuis)
        #expect(ReceptZoeker.recept(id: try #require(thuis.uuid?.uuidString), in: context) === thuis)
    }

    /// Stopt het delen, dan haalt CloudKit de zone weg en verdwijnen de Thuis-recepten uit de
    /// gedeelde store. Open recept, "Verder met…", Siri en Spotlight moeten daar heel tegen kunnen.
    @Test func verdwenenThuisReceptenLatenDeAppHeel() throws {
        let opslag = try opslag()
        let context = opslag.context
        let gedeeld = try #require(opslag.gedeeldeStore)
        try alsDeelnemer(opslag)
        var invoer = ReceptInvoer()
        invoer.titel = "Thuis-curry"
        invoer.stappenTekst = "Een.\n\nTwee."
        invoer.kookboek = .thuis
        let thuis = try invoer.bewaar(in: context)
        try thuis.zetFoto(Data([7]))
        let mijn = try maakRecept("Mijn soep", in: context)
        let id = thuis.objectID
        let uuid = try #require(thuis.uuid?.uuidString)
        let defaults = try #require(UserDefaults(suiteName: "ThuisTests-\(UUID().uuidString)"))
        let voortgang = KookVoortgang(defaults: defaults)
        voortgang.bewaar(.init(recept: thuis.sleutelURL, stapIndex: 1, aantalStappen: 2, porties: 4, datum: .now))

        // Zoals de CloudKit-import na het verwijderen van de zone: alles uit de gedeelde store weg,
        // buiten de viewContext om, en daarna samengevoegd.
        try wisStore(gedeeld, in: opslag)

        #expect(VerderKeuze.recept(bij: thuis.sleutelURL, in: context) == nil)
        #expect(voortgang.meestRecente(bestaat: { VerderKeuze.recept(bij: $0, in: context) != nil }) == nil)
        voortgang.ruimOp(bestaat: { VerderKeuze.recept(bij: $0, in: context) != nil })
        #expect(voortgang.alle.isEmpty)
        #expect(ReceptZoeker.recept(id: uuid, in: context) == nil)
        #expect(try ReceptZoeker.alle(in: context).map(\.titel) == ["Mijn soep"])
        #expect(try context.fetch(ReceptFilter().verzoek()) == [mijn])
        // Het open recept: het oude object crasht niet en het scherm vindt het niet meer.
        #expect(!thuis.isThuis)
        _ = thuis.titelOfStandaard
        let nogDaar = try? context.existingObject(with: id) as? Recept
        #expect(
            nogDaar == nil || nogDaar?.isDeleted == true || nogDaar?.managedObjectContext == nil
                || nogDaar?.isFault == true)
        // De bibliotheek telt verder gewoon.
        #expect(CategorieGroep.groepeer(try context.fetch(Categorie.verzoek())).allSatisfy { $0.aantal >= 0 })
    }

    private func wisStore(_ store: NSPersistentStore, in opslag: Opslag) throws {
        var verwijderd: [NSManagedObjectID] = []
        for entiteit in ["Ingredient", "Stap", "Kooklog", "Recept", "Categorie", "Label"] {
            let verzoek = NSFetchRequest<NSFetchRequestResult>(entityName: entiteit)
            verzoek.affectedStores = [store]
            let wis = NSBatchDeleteRequest(fetchRequest: verzoek)
            wis.affectedStores = [store]
            wis.resultType = .resultTypeObjectIDs
            let resultaat = try opslag.container.persistentStoreCoordinator.execute(wis, with: opslag.context)
            verwijderd += ((resultaat as? NSBatchDeleteResult)?.result as? [NSManagedObjectID]) ?? []
        }
        NSManagedObjectContext.mergeChanges(
            fromRemoteContextSave: [NSDeletedObjectsKey: verwijderd], into: [opslag.context])
    }

    // MARK: Delen, stoppen, vertrekken (met nepdienst)

    @Test func verplaatsenNaarThuisZetHetReceptInDeShare() async throws {
        let opslag = try opslag()
        let dienst = NepDeelDienst()
        let delen = ThuisDelen(opslag: opslag, dienst: dienst)
        let thuis = try delen.verplaats(try maakRecept("Soep", in: opslag.context), naar: .thuis)
        await delen.deelOpenstaande()
        #expect(dienst.gedeeld == [thuis.objectID])
        // Al gedeeld: niet nog eens.
        await delen.deelOpenstaande()
        #expect(dienst.gedeeld == [thuis.objectID])
        #expect(delen.aantalThuis == 1)
    }

    @Test func stopMetDelenZetEerstAllesTerugInMijnRecepten() async throws {
        let opslag = try opslag()
        let context = opslag.context
        let dienst = NepDeelDienst()
        dienst.context = context
        dienst.nepStatus = NepDeelDienst.eigenaarMetHuisgenoot()
        let delen = ThuisDelen(opslag: opslag, dienst: dienst)
        let uuids = try ["Soep", "Curry"].map { try delen.verplaats(try volRecept($0, in: context), naar: .thuis).uuid }

        try await delen.stopMetDelen()

        #expect(dienst.gestopt)
        #expect(dienst.thuisBijStoppen == 0)
        let recepten = try context.fetch(ReceptFilter().verzoek())
        #expect(recepten.count == 2)
        #expect(recepten.allSatisfy { $0.kookboekWaarde == .mijn && store(van: $0) == .prive })
        #expect(Set(recepten.map(\.uuid)) == Set(uuids))
        #expect(recepten.allSatisfy { $0.aantalKeerGekookt == 2 && $0.heeftFoto })
        #expect(delen.status.huisgenoten.count == 1)
    }

    @Test func verlaatThuisMetKopieHoudtDeRecepten() async throws {
        let opslag = try opslag()
        let context = opslag.context
        try alsDeelnemer(opslag)
        let dienst = NepDeelDienst()
        let delen = ThuisDelen(opslag: opslag, dienst: dienst)
        let thuis = try delen.verplaats(try volRecept("Pompoensoep", in: context), naar: .thuis)
        #expect(store(van: thuis) == .gedeeld)

        try await delen.verlaat(kopieer: true)
        #expect(dienst.verlaten)
        // Daarna verdwijnt de gedeelde store-inhoud (zone weg); de kopie blijft.
        try wisStore(try #require(opslag.gedeeldeStore), in: opslag)

        let recepten = try context.fetch(ReceptFilter().verzoek())
        let kopie = try #require(recepten.first)
        #expect(recepten.count == 1)
        #expect(kopie.kookboekWaarde == .mijn)
        #expect(store(van: kopie) == .prive)
        #expect(kopie.uuid == thuis.uuid)
        #expect(kopie.gesorteerdeIngredienten.count == 2)
        #expect(kopie.aantalKeerGekookt == 2)
        #expect(kopie.fotoData == Data([1, 2, 3]))
        #expect(kopie.gesorteerdeCategorieen.allSatisfy { $0.kookboekWaarde == .mijn })
    }

    @Test func verlaatThuisZonderKopie() async throws {
        let opslag = try opslag()
        let context = opslag.context
        try alsDeelnemer(opslag)
        let dienst = NepDeelDienst()
        let delen = ThuisDelen(opslag: opslag, dienst: dienst)
        try delen.verplaats(try maakRecept("Soep", in: context), naar: .thuis)
        try await delen.verlaat(kopieer: false)
        try wisStore(try #require(opslag.gedeeldeStore), in: opslag)
        #expect(dienst.verlaten)
        #expect(try context.count(for: Recept.verzoek()) == 0)
    }

    @Test func zonderICloudDeeltNiets() async throws {
        let opslag = try opslag()
        let delen = ThuisDelen(opslag: opslag, dienst: GeenDeelDienst())
        try delen.verplaats(try maakRecept("Soep", in: opslag.context), naar: .thuis)
        await delen.deelOpenstaande()
        await delen.vernieuw()
        #expect(delen.status == .nietGedeeld)
        #expect(delen.aantalThuis == 1)
        #expect(ThuisDelen.gedeeld.dienst is GeenDeelDienst)
    }

    @Test func teksten() {
        #expect(ReceptVerplaatsen.menu(naar: .thuis) == "Verplaats naar Thuis")
        #expect(ReceptVerplaatsen.menu(naar: .mijn) == "Verplaats naar Mijn recepten")
        #expect(
            ReceptVerplaatsen.uitleg(naar: .thuis, eersteKeer: true).count
                > ReceptVerplaatsen.uitleg(naar: .thuis, eersteKeer: false).count)
        #expect(Kookboek(veld: nil) == .mijn)
        #expect(Kookboek(veld: "onzin") == .mijn)
        #expect(Kookboek(veld: "thuis") == .thuis)
        #expect(CloudKitDeelDienst.titel == "Knipsel · Thuis")
    }

    @Test func infoPlistOndersteuntCloudKitDelen() {
        #expect(Bundle(for: Recept.self).object(forInfoDictionaryKey: "CKSharingSupported") as? Bool == true)
    }

    @Test func modelversie3HeeftKookboekOpCategorieEnLabel() throws {
        for entiteit in ["Categorie", "Label", "Recept"] {
            let attribuut = try #require(Opslag.model.entitiesByName[entiteit]?.attributesByName["kookboek"])
            #expect(attribuut.defaultValue as? String == "mijn")
        }
    }
}
