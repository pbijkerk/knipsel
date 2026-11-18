import CloudKit
import CoreData
import Foundation
import Testing

@testable import Knipsel

// Thuis bijwerken in iCloud: foutmeldingen in gewone taal, apart delen per soort, "Jij" voor jezelf,
// het CloudKit-schema in Development klaarzetten, en geen verplichte velden leeg na migratie of
// verplaatsen naar Thuis.

@MainActor
struct ThuisDelenFoutTests {
    // MARK: Hulp

    private func opslagMetStandaard() throws -> Opslag {
        let opslag = legeOpslag()
        try Inrichting.zaaiStandaard(in: opslag.context)
        return opslag
    }

    /// Een echte Core Data-validatiefout: een verplicht veld leeg gemaakt.
    private func validatiefout(entiteit: String, in context: NSManagedObjectContext) throws -> NSError {
        let object = NSEntityDescription.insertNewObject(forEntityName: entiteit, into: context)
        object.setValue(nil, forKey: "kookboek")
        defer { context.delete(object) }
        do {
            try object.validateForInsert()
        } catch {
            return error as NSError
        }
        Issue.record("Geen validatiefout voor \(entiteit)")
        return NSError(domain: "geen", code: 0)
    }

    /// Thuis met van elke soort één: een recept, een boodschap en een maaltijd.
    private func thuisMetAlleSoorten(_ opslag: Opslag, delen: ThuisDelen) throws {
        let context = opslag.context
        try delen.verplaats(try maakRecept("Pompoensoep", ingredienten: ["1 ui"], in: context), naar: .thuis)
        try Boodschappenlijsten.voegToe(
            tekst: "2 uien", kookboek: .thuis, context: context, geheugen: AfdelingGeheugen())
        try Weekmenu.planNotitie(
            "Uit eten", op: .now, kookboek: .thuis, context: context, kalender: Weekplanning.kalender())
    }

    // MARK: Foutmelding

    @Test func validatiefoutNoemtSoortEnVeld() throws {
        let context = legeOpslag().context
        let fout = try validatiefout(entiteit: "BoodschappenItem", in: context)
        #expect(fout.code == NSValidationMissingMandatoryPropertyError)
        // Hier vult Core Data het veld in; op het toestel kwam de fout zonder veld binnen
        // ("%{PROPERTY}@ is een vereiste waarde."), zie interneEntiteitEnOnbekendVeld.
        #expect(fout.userInfo[NSValidationKeyErrorKey] as? String == "kookboek")

        #expect(DeelFout.validaties(in: fout) == [.init(entiteit: "BoodschappenItem", veld: "kookboek", code: 1570)])
        #expect(DeelFout.uitleg(fout) == "bij een boodschap ontbreekt 'kookboek'.")
        #expect(
            DeelFout.melding(fout, soort: .boodschappen)
                == "Thuis bijwerken lukte niet voor de boodschappen: bij een boodschap ontbreekt 'kookboek'.")
        #expect(
            DeelFout.uitleg(try validatiefout(entiteit: "Maaltijd", in: context))
                == "bij een maaltijd ontbreekt 'kookboek'.")
        #expect(
            DeelFout.uitleg(try validatiefout(entiteit: "Recept", in: context))
                == "bij een recept ontbreekt 'kookboek'.")
    }

    @Test func meerdereValidatiefoutenViaDetails() throws {
        let context = legeOpslag().context
        let recept = Recept(context: context)
        recept.titel = "Geheime oma-soep"
        recept.setValue(nil, forKey: "kookboek")
        let maaltijd = Maaltijd(context: context)
        maaltijd.setValue(nil, forKey: "kookboek")
        var opgevangen: NSError?
        do { try context.save() } catch { opgevangen = error as NSError }
        let fout = try #require(opgevangen)
        context.rollback()

        #expect(fout.code == NSValidationMultipleErrorsError)
        let validaties = DeelFout.validaties(in: fout)
        #expect(Set(validaties.compactMap(\.entiteit)) == ["Recept", "Maaltijd"])
        #expect(validaties.allSatisfy { $0.veld == "kookboek" })
        // Ook als de validatiefout onder een andere fout zit.
        let ingepakt = NSError(
            domain: "NSCloudKitMirroringDelegate", code: 134_400, userInfo: [NSUnderlyingErrorKey: fout])
        #expect(DeelFout.uitleg(ingepakt).hasSuffix("ontbreekt 'kookboek'."))

        // De log noemt entiteit en veld, maar geen inhoud (titels kunnen persoonlijk zijn).
        let log = DeelFout.logregel(fout)
        #expect(log.contains("domein=NSCocoaErrorDomain"))
        #expect(log.contains("code=1560"))
        #expect(log.contains("Recept.kookboek(1570)"))
        #expect(!log.contains("Geheime"))
    }

    @Test func interneEntiteitEnOnbekendVeld() {
        // Zoals op het toestel: alleen de tekst met de plaatshouder, zonder veld of object.
        let fout = NSError(
            domain: NSCocoaErrorDomain, code: NSValidationMissingMandatoryPropertyError,
            userInfo: [NSLocalizedDescriptionKey: "%{PROPERTY}@ is een vereiste waarde."])
        #expect(DeelFout.uitleg(fout) == "bij een gegeven ontbreekt een verplicht veld.")
        #expect(
            DeelFout.uitleg(.init(entiteit: "NSCKRecordMetadata", veld: "recordZone", code: 1570))
                == "bij een intern iCloud-gegeven (NSCKRecordMetadata) ontbreekt 'recordZone'.")
        #expect(
            DeelFout.uitleg(.init(entiteit: "Categorie", veld: "naam", code: NSValidationStringTooLongError))
                == "bij een categorie is 'naam' ongeldig.")
    }

    @Test func cloudKitFoutInGewoneTaal() {
        #expect(DeelFout.uitleg(CKError(.serverRejectedRequest)).contains("Deploy Schema Changes nodig"))
        #expect(DeelFout.uitleg(CKError(.invalidArguments)).contains("iCloud-schema ontbreekt"))
        #expect(DeelFout.uitleg(CKError(.unknownItem)).contains("Deploy Schema Changes nodig"))
        #expect(DeelFout.uitleg(CKError(.networkUnavailable)).contains("geen verbinding"))
        #expect(DeelFout.uitleg(CKError(.quotaExceeded)) == "je iCloud-opslag is vol.")
        #expect(DeelFout.uitleg(CKError(.notAuthenticated)) == "je bent niet ingelogd bij iCloud.")
        #expect(DeelFout.uitleg(CKError(.internalError)) == "iCloud gaf een fout (CloudKit-fout 1).")

        // Gedeeltelijke fout: de echte deelfout telt, niet "Batch Request Failed".
        let id1 = CKRecord.ID(recordName: "a")
        let id2 = CKRecord.ID(recordName: "b")
        let deel = CKError(
            .partialFailure,
            userInfo: [
                CKPartialErrorsByItemIDKey: [id1: CKError(.batchRequestFailed), id2: CKError(.invalidArguments)]
            ])
        #expect(DeelFout.uitleg(deel).contains("Deploy Schema Changes nodig"))
        #expect(DeelFout.logregel(deel).contains("ckCode=2"))
        #expect(DeelFout.logregel(deel).contains("ckDeelCodes=[12, 22]"))

        // Andere fouten: hun eigen beschrijving.
        #expect(DeelFout.uitleg(Kookboeken.Fout.geenStore) == "De opslag voor dit kookboek is niet beschikbaar.")
    }

    // MARK: Apart delen per soort

    @Test func elkeSoortApartGedeeld() async throws {
        let opslag = try opslagMetStandaard()
        let dienst = NepDeelDienst()
        let delen = ThuisDelen(opslag: opslag, dienst: dienst)
        try thuisMetAlleSoorten(opslag, delen: delen)

        await delen.deelOpenstaande()

        #expect(dienst.aanroepen == [["Recept"], ["BoodschappenItem"], ["Maaltijd"]])
        #expect(dienst.gedeeld.count == 3)
        #expect(delen.fout == nil)
    }

    @Test func eenSoortFaaltDeAndereGaanDoor() async throws {
        let opslag = try opslagMetStandaard()
        let context = opslag.context
        let dienst = NepDeelDienst()
        dienst.faaltVoor["BoodschappenItem"] = try validatiefout(entiteit: "BoodschappenItem", in: context)
        let delen = ThuisDelen(opslag: opslag, dienst: dienst)
        try thuisMetAlleSoorten(opslag, delen: delen)

        await delen.deelOpenstaande()

        let gedeeld = Set(dienst.gedeeld.compactMap(\.entity.name))
        #expect(gedeeld == ["Recept", "Maaltijd"])
        #expect(
            delen.fout == "Thuis bijwerken lukte niet voor de boodschappen: bij een boodschap ontbreekt 'kookboek'.")
        #expect(delen.mislukt == [.boodschappen])
    }

    @Test func mislukteSoortNietEindeloosOpnieuw() async throws {
        let opslag = try opslagMetStandaard()
        let context = opslag.context
        let dienst = NepDeelDienst()
        dienst.faaltVoor["Maaltijd"] = CKError(.serverRejectedRequest)
        let delen = ThuisDelen(opslag: opslag, dienst: dienst)
        try thuisMetAlleSoorten(opslag, delen: delen)

        await delen.deelOpenstaande()
        #expect(dienst.aanroepen.filter { $0.contains("Maaltijd") }.count == 1)
        let melding = try #require(delen.fout)
        #expect(melding.hasPrefix("Thuis bijwerken lukte niet voor het weekmenu: iCloud-schema ontbreekt"))

        // Nieuwe Thuis-dingen: recepten en boodschappen wel, het weekmenu deze app-start niet meer.
        try Boodschappenlijsten.voegToe(
            tekst: "1 prei", kookboek: .thuis, context: context, geheugen: AfdelingGeheugen())
        try Weekmenu.planNotitie(
            "Pizza", op: .now.addingTimeInterval(86_400), kookboek: .thuis, context: context,
            kalender: Weekplanning.kalender())
        await delen.deelOpenstaande()
        await delen.deelOpenstaande()
        #expect(dienst.aanroepen.filter { $0.contains("Maaltijd") }.count == 1)
        #expect(dienst.aanroepen.filter { $0.contains("BoodschappenItem") }.count == 2)
        #expect(delen.fout == melding)

        // "Probeer opnieuw": nog één poging; nu lukt het en is de melding weg.
        dienst.faaltVoor = [:]
        await delen.probeerOpnieuw()
        #expect(dienst.aanroepen.filter { $0.contains("Maaltijd") }.count == 2)
        #expect(delen.fout == nil)
        #expect(delen.mislukt.isEmpty)
    }

    @Test func tweeSoortenFalenTweeRegels() async throws {
        let opslag = try opslagMetStandaard()
        let dienst = NepDeelDienst()
        dienst.faaltVoor["Recept"] = CKError(.quotaExceeded)
        dienst.faaltVoor["Maaltijd"] = CKError(.networkFailure)
        let delen = ThuisDelen(opslag: opslag, dienst: dienst)
        try thuisMetAlleSoorten(opslag, delen: delen)

        await delen.deelOpenstaande()

        #expect(Set(dienst.gedeeld.compactMap(\.entity.name)) == ["BoodschappenItem"])
        let regels = try #require(delen.fout).components(separatedBy: "\n")
        #expect(regels.count == 2)
        #expect(regels.first == "Thuis bijwerken lukte niet voor de recepten: je iCloud-opslag is vol.")
        #expect(regels.last?.hasPrefix("Thuis bijwerken lukte niet voor het weekmenu: geen verbinding") == true)
    }

    // MARK: "Jij"

    @Test func naamVanDeelnemer() {
        var peter = PersonNameComponents()
        peter.givenName = "Peter"
        peter.familyName = "Voorbeeld"
        #expect(
            CloudKitDeelDienst.naam(componenten: peter, email: nil, telefoon: nil, isIkZelf: true) == "Peter Voorbeeld")
        #expect(
            CloudKitDeelDienst.naam(
                componenten: PersonNameComponents(), email: "sam@example.com", telefoon: nil, isIkZelf: false)
                == "sam@example.com")
        #expect(
            CloudKitDeelDienst.naam(componenten: nil, email: nil, telefoon: "+31600000000", isIkZelf: false)
                == "+31600000000")
        // Zonder naam: jezelf heet "Jij", een ander "Onbekend".
        #expect(CloudKitDeelDienst.naam(componenten: nil, email: nil, telefoon: nil, isIkZelf: true) == "Jij")
        #expect(CloudKitDeelDienst.naam(componenten: nil, email: "", telefoon: nil, isIkZelf: false) == "Onbekend")
    }

    @Test func weergaveNaamInDeLijst() {
        func deelnemer(_ naam: String, ikZelf: Bool) -> ThuisDeelnemer {
            ThuisDeelnemer(
                id: naam, naam: naam, contact: nil, status: .doetMee, isEigenaar: ikZelf, isIkZelf: ikZelf,
                magBewerken: true)
        }
        #expect(deelnemer("Jij", ikZelf: true).weergaveNaam == "Jij")
        #expect(deelnemer("Peter Voorbeeld", ikZelf: true).weergaveNaam == "Peter Voorbeeld (jij)")
        #expect(deelnemer("Onbekend", ikZelf: false).weergaveNaam == "Onbekend")
        #expect(deelnemer("Sam", ikZelf: false).weergaveNaam == "Sam")
    }

    // MARK: CloudKit-schema (Development)

    @Test func schemaEenKeerPerModelversie() throws {
        #expect(CloudKitSchema.modelversie == "5")
        #expect(CloudKitSchema.sleutel(modelversie: "5") == "cloudkitSchemaGeinitialiseerd-5")
        #expect(CloudKitSchema.moetVanzelf(synchroniseert: true, onderTests: false, inPreview: false, alGedaan: false))
        #expect(!CloudKitSchema.moetVanzelf(synchroniseert: true, onderTests: false, inPreview: false, alGedaan: true))
        #expect(
            !CloudKitSchema.moetVanzelf(synchroniseert: false, onderTests: false, inPreview: false, alGedaan: false))
        #expect(!CloudKitSchema.moetVanzelf(synchroniseert: true, onderTests: true, inPreview: false, alGedaan: false))
        #expect(!CloudKitSchema.moetVanzelf(synchroniseert: true, onderTests: false, inPreview: true, alGedaan: false))

        // Zonder iCloud (zoals hier) start niets en kan de knop niet.
        let defaults = try #require(UserDefaults(suiteName: "schema-\(UUID().uuidString)"))
        let schema = CloudKitSchema(opslag: legeOpslag(), defaults: defaults)
        schema.startVanzelf()
        #expect(schema.toestand == .nietGestart)
        #expect(!schema.kanStarten)
        defaults.set(true, forKey: CloudKitSchema.sleutel(modelversie: CloudKitSchema.modelversie))
        #expect(CloudKitSchema(opslag: legeOpslag(), defaults: defaults).toestand == .klaar)
    }

    /// Het model is ook voor CloudKit zelf geldig (de proef van `initializeCloudKitSchema` zonder
    /// uploaden kan zonder iCloud-account niet; dit zijn de regels die het controleert).
    @Test func elkVerplichtVeldHeeftEenStandaardInAlleModelversies() throws {
        let momd = try #require(Bundle(for: Recept.self).url(forResource: "Knipsel", withExtension: "momd"))
        for bestand in ["Knipsel", "Knipsel 2", "Knipsel 3", "Knipsel 4", "Knipsel 5"] {
            let model = try #require(NSManagedObjectModel(contentsOf: momd.appendingPathComponent("\(bestand).mom")))
            for entiteit in model.entities {
                for attribuut in entiteit.attributesByName.values where !attribuut.isOptional {
                    #expect(attribuut.defaultValue != nil, "\(bestand): \(entiteit.name ?? "").\(attribuut.name)")
                }
                for relatie in entiteit.relationshipsByName.values {
                    #expect(relatie.isOptional, "\(bestand): \(entiteit.name ?? "").\(relatie.name)")
                }
            }
        }
    }

    // MARK: Geen lege verplichte velden (zoals share(_:to:) ze valideert)

    /// Alle objecten in beide stores: zoals `share(_:to:)` ze bij het verhuizen naar de zone bewaart,
    /// moeten ze door de validatie van Core Data komen.
    private func valideerAlles(in opslag: Opslag, _ moment: String) throws -> Int {
        let context = opslag.context
        var aantal = 0
        for entiteit in Opslag.model.entities.compactMap(\.name) {
            let verzoek = NSFetchRequest<NSManagedObject>(entityName: entiteit)
            verzoek.returnsObjectsAsFaults = false
            for object in try context.fetch(verzoek) {
                aantal += 1
                do {
                    try object.validateForUpdate()
                } catch {
                    Issue.record("\(moment): \(entiteit) ongeldig — \(DeelFout.logregel(error))")
                }
                for (naam, attribuut) in object.entity.attributesByName where !attribuut.isOptional {
                    #expect(object.value(forKey: naam) != nil, "\(moment): \(entiteit).\(naam) is leeg")
                }
            }
        }
        return aantal
    }

    @Test func naMigratieVanV1EnVerplaatsenNaarThuisIsAllesGeldig() async throws {
        let momd = try #require(Bundle(for: Recept.self).url(forResource: "Knipsel", withExtension: "momd"))
        let v1 = try #require(NSManagedObjectModel(contentsOf: momd.appendingPathComponent("Knipsel.mom")))
        let map = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: map, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: map) }

        // Modelversie 1: alles wat er toen kon, met zo weinig mogelijk ingevuld.
        let oud = NSPersistentContainer(name: "Knipsel", managedObjectModel: v1)
        oud.persistentStoreDescriptions = [
            NSPersistentStoreDescription(url: map.appendingPathComponent("Knipsel.sqlite"))
        ]
        var laadfout: (any Error)?
        oud.loadPersistentStores { _, error in laadfout = error }
        #expect(laadfout == nil)
        let c = oud.viewContext
        let soepen = NSEntityDescription.insertNewObject(forEntityName: "Categorie", into: c)
        soepen.setValue("Soepen", forKey: "naam")
        let vega = NSEntityDescription.insertNewObject(forEntityName: "Label", into: c)
        vega.setValue("Vegetarisch", forKey: "naam")
        for titel in ["Oude erwtensoep", "Leeg recept"] {
            let recept = NSEntityDescription.insertNewObject(forEntityName: "Recept", into: c)
            recept.setValue(titel == "Leeg recept" ? nil : titel, forKey: "titel")
            recept.setValue(Set([soepen]), forKey: "categorieen")
            recept.setValue(Set([vega]), forKey: "labels")
            for soort in ["Ingredient", "Stap", "Kooklog"] {
                let deel = NSEntityDescription.insertNewObject(forEntityName: soort, into: c)
                deel.setValue(recept, forKey: "recept")
            }
        }
        try c.save()
        for store in oud.persistentStoreCoordinator.persistentStores {
            try oud.persistentStoreCoordinator.remove(store)
        }

        // Nu modelversie 5 (lichte migratie), beide stores.
        let opslag = Opslag(map: map, cloudKitContainer: nil)
        #expect(opslag.laadfout == nil)
        #expect(try valideerAlles(in: opslag, "na migratie") == 10)

        // Naar Thuis verplaatsen, plus een Thuis-boodschap en -maaltijd, en delen (nep).
        let dienst = NepDeelDienst()
        let delen = ThuisDelen(opslag: opslag, dienst: dienst)
        for recept in try opslag.context.fetch(Recept.verzoek()) {
            try delen.verplaats(recept, naar: .thuis)
        }
        try Boodschappenlijsten.voegToe(
            tekst: "2 uien", kookboek: .thuis, context: opslag.context, geheugen: AfdelingGeheugen())
        try Weekmenu.planNotitie(
            "Uit eten", op: .now, kookboek: .thuis, context: opslag.context, kalender: Weekplanning.kalender())
        await delen.deelOpenstaande()
        #expect(delen.fout == nil)
        #expect(try valideerAlles(in: opslag, "na verplaatsen naar Thuis") > 10)
        let thuis = try Kookboeken.recepten(in: .thuis, context: opslag.context)
        #expect(thuis.count == 2)
        #expect(thuis.allSatisfy { $0.gesorteerdeCategorieen.allSatisfy { $0.kookboekWaarde == .thuis } })

        for store in opslag.container.persistentStoreCoordinator.persistentStores {
            try opslag.container.persistentStoreCoordinator.remove(store)
        }
    }
}
