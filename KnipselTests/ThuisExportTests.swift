import CloudKit
import CoreData
import Foundation
import Testing

@testable import Knipsel

// Thuis delen na de export naar iCloud: alleen delen wat (met zijn hele graaf) al geëxporteerd is,
// opnieuw proberen na een geslaagde export, één voor één bij fout 1570 op `recordMetadata`, en wachten
// rustig melden in plaats van als fout.

@MainActor
struct ThuisExportTests {
    // MARK: Hulp

    private func thuisRecept(_ titel: String, _ delen: ThuisDelen, categorieen: [Categorie] = []) throws -> Recept {
        let context = delen.context
        return try delen.verplaats(
            try maakRecept(titel, ingredienten: ["1 ui", "2 wortels"], categorieen: categorieen, in: context),
            naar: .thuis)
    }

    private func ingredienten(van recept: Recept) -> [NSManagedObject] {
        ((recept.value(forKey: "ingredienten") as? Set<NSManagedObject>) ?? []).sorted {
            ($0.value(forKey: "volgorde") as? Int ?? 0) < ($1.value(forKey: "volgorde") as? Int ?? 0)
        }
    }

    /// Updates in de persistent history voor dit object sinds `sinds` (wat CloudKit exporteert).
    private func updates(van id: NSManagedObjectID, sinds: Date, in context: NSManagedObjectContext) throws -> Int {
        let verzoek = NSPersistentHistoryChangeRequest.fetchHistory(after: sinds)
        let resultaat = try #require(try context.execute(verzoek) as? NSPersistentHistoryResult)
        let transacties = (resultaat.result as? [NSPersistentHistoryTransaction]) ?? []
        return transacties.flatMap { $0.changes ?? [] }
            .filter { $0.changeType == .update && $0.changedObjectID == id }.count
    }

    // MARK: Alleen geëxporteerd delen

    @Test func alleenWatGeexporteerdIsGaatDeShareIn() async throws {
        let opslag = legeOpslag()
        let dienst = NepDeelDienst()
        let delen = ThuisDelen(opslag: opslag, dienst: dienst)
        let soep = try thuisRecept("Soep", delen)
        let stamppot = try thuisRecept("Stamppot", delen)
        // Eén ingrediënt van de stamppot staat nog niet in iCloud: de hele stamppot wacht.
        dienst.nietGeexporteerd = [try #require(ingredienten(van: stamppot).first).objectID]

        await delen.deelOpenstaande()

        #expect(dienst.gedeeld == [soep.objectID])
        #expect(delen.wachtend[.recepten] == [stamppot.objectID])
        #expect(delen.fout == nil)
        #expect(delen.wachtMelding == "1 recept wacht op iCloud — het wordt gedeeld zodra het geüpload is.")
        #expect(dienst.isGeexporteerd(soep.objectID))
        #expect(!dienst.isGeexporteerd(try #require(ingredienten(van: stamppot).first).objectID))
    }

    @Test func nietGeexporteerdReceptZelfWacht() async throws {
        let opslag = legeOpslag()
        let dienst = NepDeelDienst()
        let delen = ThuisDelen(opslag: opslag, dienst: dienst)
        let soep = try thuisRecept("Soep", delen)
        let taart = try thuisRecept("Taart", delen)
        dienst.nietGeexporteerd = [soep.objectID, taart.objectID]

        await delen.deelOpenstaande()

        #expect(dienst.aanroepen.isEmpty)
        #expect(delen.fout == nil)
        #expect(delen.wachtMelding == "2 recepten wachten op iCloud — ze worden gedeeld zodra ze geüpload zijn.")
    }

    @Test func graafLooptViaDeCategorieNaarAndereRecepten() async throws {
        let opslag = legeOpslag()
        try Inrichting.zaaiStandaard(in: opslag.context)
        let soepen = try categorie("Soepen", in: opslag.context)
        let dienst = NepDeelDienst()
        let delen = ThuisDelen(opslag: opslag, dienst: dienst)
        let erwtensoep = try thuisRecept("Erwtensoep", delen, categorieen: [soepen])
        let tomatensoep = try thuisRecept("Tomatensoep", delen, categorieen: [soepen])
        let los = try thuisRecept("Pannenkoeken", delen)

        // Eén graaf: recept, ingrediënten, de Thuis-categorie Soepen en via die het andere soeprecept.
        let graaf = ThuisExport.graaf(van: erwtensoep)
        let thuisSoepen = try #require(erwtensoep.gesorteerdeCategorieen.first)
        #expect(thuisSoepen.kookboekWaarde == .thuis)
        #expect(graaf.contains(thuisSoepen.objectID))
        #expect(graaf.contains(tomatensoep.objectID))
        #expect(ingredienten(van: tomatensoep).allSatisfy { graaf.contains($0.objectID) })
        #expect(!graaf.contains(los.objectID))

        // De tomatensoep is nog niet geëxporteerd: share(_:to:) zou hem met de erwtensoep meenemen,
        // dus wachten ze allebei. De pannenkoeken gaan wel.
        dienst.nietGeexporteerd = [tomatensoep.objectID]
        await delen.deelOpenstaande()
        #expect(dienst.gedeeld == [los.objectID])
        #expect(delen.wachtend[.recepten] == [erwtensoep.objectID, tomatensoep.objectID])
    }

    // MARK: Opnieuw na export

    @Test func naGeslaagdeExportWordtWatWachtteGedeeld() async throws {
        let opslag = legeOpslag()
        let dienst = NepDeelDienst()
        let delen = ThuisDelen(opslag: opslag, dienst: dienst)
        let soep = try thuisRecept("Soep", delen)
        let ui = try #require(ingredienten(van: soep).first)
        dienst.nietGeexporteerd = [ui.objectID]
        try Boodschappenlijsten.voegToe(
            tekst: "2 uien", kookboek: .thuis, context: opslag.context, geheugen: AfdelingGeheugen())

        await delen.deelOpenstaande()
        #expect(Set(dienst.gedeeld.compactMap(\.entity.name)) == ["BoodschappenItem"])
        #expect(delen.wachtMelding != nil)

        // De export is klaar: nu wel, en de wachtregel is weg.
        dienst.nietGeexporteerd = []
        await delen.naExport()
        #expect(dienst.gedeeld.contains(soep.objectID))
        #expect(delen.wachtMelding == nil)
        #expect(delen.fout == nil)
        #expect(delen.aangestoten.isEmpty)
    }

    @Test func blijftHetNaEenExportWachtenDanEenKeerAanstoten() async throws {
        let opslag = legeOpslag()
        let context = opslag.context
        let dienst = NepDeelDienst()
        let delen = ThuisDelen(opslag: opslag, dienst: dienst)
        let soep = try thuisRecept("Soep", delen)
        let ui = try #require(ingredienten(van: soep).first)
        let naam = ui.value(forKey: "naam") as? String
        dienst.nietGeexporteerd = [ui.objectID]
        await delen.deelOpenstaande()

        // Een export lukte, maar de ui staat er nog steeds niet bij (bijv. een eerder mislukte export):
        // Knipsel raakt hem één keer aan zodat Core Data hem opnieuw exporteert.
        let voor = Date.now
        await delen.naExport()
        #expect(delen.aangestoten == [ui.objectID])
        #expect(try updates(van: ui.objectID, sinds: voor, in: context) > 0)
        #expect(ui.value(forKey: "naam") as? String == naam)
        #expect(!context.hasChanges)

        // Niet nog eens deze app-start.
        let daarna = Date.now
        await delen.naExport()
        #expect(try updates(van: ui.objectID, sinds: daarna, in: context) == 0)
        #expect(delen.wachtend[.recepten] == [soep.objectID])
        #expect(dienst.aanroepen.isEmpty)
    }

    @Test func echteFoutBlijftGeblokkeerdNaExport() async throws {
        let opslag = legeOpslag()
        let dienst = NepDeelDienst()
        dienst.faaltVoor["Recept"] = CKError(.quotaExceeded)
        let delen = ThuisDelen(opslag: opslag, dienst: dienst)
        _ = try thuisRecept("Soep", delen)

        await delen.deelOpenstaande()
        await delen.naExport()
        await delen.naExport()
        #expect(dienst.aanroepen.count == 1)
        #expect(delen.mislukt == [.recepten])
        #expect(delen.fout == "Thuis bijwerken lukte niet voor de recepten: je iCloud-opslag is vol.")
    }

    @Test func geslaagdeExportHerkennen() {
        #expect(ThuisExport.isGeslaagdeExport(.export, eind: .now, gelukt: true))
        #expect(!ThuisExport.isGeslaagdeExport(.export, eind: nil, gelukt: false))
        #expect(!ThuisExport.isGeslaagdeExport(.export, eind: .now, gelukt: false))
        #expect(!ThuisExport.isGeslaagdeExport(.import, eind: .now, gelukt: true))
        #expect(!ThuisExport.isGeslaagdeExport(.setup, eind: .now, gelukt: true))
    }

    // MARK: Vangnet bij 1570 op recordMetadata

    @Test func eenVoorEenBijOntbrekendeRecordMetadata() async throws {
        let opslag = legeOpslag()
        let context = opslag.context
        let dienst = NepDeelDienst()
        let delen = ThuisDelen(opslag: opslag, dienst: dienst)
        let soep = try thuisRecept("Soep", delen)
        let taart = try thuisRecept("Taart", delen)
        let stamppot = try thuisRecept("Stamppot", delen)
        dienst.metadataOntbreektVoor = [taart.objectID]
        let gewijzigd = taart.gewijzigdOp

        await delen.deelOpenstaande()

        // Eerst alles samen (faalt), dan één voor één: de taart houdt de rest niet tegen.
        #expect(dienst.aanroepIDs.first?.count == 3)
        #expect(dienst.aanroepIDs.dropFirst().allSatisfy { $0.count == 1 })
        #expect(Set(dienst.gedeeld) == [soep.objectID, stamppot.objectID])
        #expect(delen.pogingen[taart.objectID] == 1)
        #expect(delen.wachtOpExport == [taart.objectID])
        // Aangeraakt om opnieuw te exporteren, en geen fout in beeld: alleen de wachtregel.
        #expect(taart.gewijzigdOp != gewijzigd)
        #expect(!context.hasChanges)
        #expect(delen.fout == nil)
        #expect(delen.wachtMelding == "1 recept wacht op iCloud — het wordt gedeeld zodra het geüpload is.")
        #expect(delen.mislukt.isEmpty)

        // Zonder nieuwe export niet nog eens proberen.
        let aantal = dienst.aanroepen.count
        await delen.deelOpenstaande()
        #expect(dienst.aanroepen.count == aantal)

        // Na de export wel; lukt het dan, dan is alles weg.
        dienst.metadataOntbreektVoor = []
        await delen.naExport()
        #expect(dienst.gedeeld.contains(taart.objectID))
        #expect(delen.wachtMelding == nil)
        #expect(delen.fout == nil)
    }

    @Test func maximaalDriePogingenPerObject() async throws {
        let opslag = legeOpslag()
        let dienst = NepDeelDienst()
        let delen = ThuisDelen(opslag: opslag, dienst: dienst)
        let soep = try thuisRecept("Soep", delen)
        let taart = try thuisRecept("Taart", delen)
        dienst.metadataOntbreektVoor = [taart.objectID]

        await delen.deelOpenstaande()
        #expect(delen.pogingen[taart.objectID] == 1)
        await delen.naExport()
        #expect(delen.pogingen[taart.objectID] == 2)
        #expect(delen.fout == nil)
        await delen.naExport()
        #expect(delen.pogingen[taart.objectID] == ThuisExport.maxPogingen)

        // Opgegeven: nu wel een melding, in gewone taal, en geen wachtregel meer.
        #expect(
            delen.fout == "Een recept is nog niet in iCloud bewaard. Knipsel probeert het opnieuw zodra dat gebeurd is."
        )
        #expect(delen.wachtMelding == nil)
        let pogingenTaart = { dienst.aanroepIDs.filter { $0.contains(taart.objectID) }.count }
        let gedaan = pogingenTaart()
        await delen.naExport()
        await delen.deelOpenstaande()
        #expect(pogingenTaart() == gedaan)
        #expect(delen.fout != nil)
        #expect(dienst.gedeeld == [soep.objectID])

        // Probeer opnieuw: tellers weer op nul; nu lukt het.
        dienst.metadataOntbreektVoor = []
        await delen.probeerOpnieuw()
        #expect(dienst.gedeeld.contains(taart.objectID))
        #expect(delen.fout == nil)
        #expect(delen.pogingen.isEmpty)
    }

    @Test func andereFoutTijdensEenVoorEenBlokkeertDeSoort() async throws {
        let opslag = legeOpslag()
        let dienst = NepDeelDienst()
        let delen = ThuisDelen(opslag: opslag, dienst: dienst)
        let soep = try thuisRecept("Soep", delen)
        _ = try thuisRecept("Taart", delen)
        dienst.metadataOntbreektVoor = [soep.objectID]
        dienst.faaltVoorAanroep = { ids in ids.count == 1 && ids != [soep.objectID] ? CKError(.quotaExceeded) : nil }

        await delen.deelOpenstaande()

        #expect(delen.mislukt == [.recepten])
        #expect(delen.fout == "Thuis bijwerken lukte niet voor de recepten: je iCloud-opslag is vol.")
    }

    // MARK: Aanraken

    @Test func aanrakenIsEenEchteWijzigingZonderInhoudTeVeranderen() throws {
        let opslag = legeOpslag()
        let context = opslag.context
        try Inrichting.zaaiStandaard(in: context)
        let soepen = try categorie("Soepen", in: context)
        let recept = try maakRecept("Soep", ingredienten: ["1 ui"], categorieen: [soepen], in: context)
        let ui = try #require(ingredienten(van: recept).first)
        let log = NSEntityDescription.insertNewObject(forEntityName: "Kooklog", into: context)
        let gekookt = Date(timeIntervalSince1970: 1_800_000_000)
        log.setValue(gekookt, forKey: "datum")
        log.setValue(recept, forKey: "recept")
        try context.save()

        let voor = Date.now
        let gewijzigd = recept.gewijzigdOp
        for object in [recept, ui, log, soepen] as [NSManagedObject] {
            #expect(try ThuisExport.raakAan(object))
            #expect(try updates(van: object.objectID, sinds: voor, in: context) > 0, "\(object.entity.name ?? "")")
        }
        #expect(recept.gewijzigdOp != gewijzigd)
        #expect(ui.value(forKey: "naam") as? String == "ui")
        #expect(soepen.naam == "Soepen")
        let nieuweDatum = try #require(log.value(forKey: "datum") as? Date)
        #expect(abs(nieuweDatum.timeIntervalSince(gekookt)) < 0.01)
        #expect(!context.hasChanges)
    }

    // MARK: Melding en foutvertaling

    @Test func wachtMeldingTeltPerSoort() {
        #expect(ThuisExport.wachtMelding([:]) == nil)
        #expect(ThuisExport.wachtMelding([.recepten: 0]) == nil)
        #expect(
            ThuisExport.wachtMelding([.recepten: 2])
                == "2 recepten wachten op iCloud — ze worden gedeeld zodra ze geüpload zijn.")
        #expect(
            ThuisExport.wachtMelding([.recepten: 1])
                == "1 recept wacht op iCloud — het wordt gedeeld zodra het geüpload is.")
        #expect(
            ThuisExport.wachtMelding([.boodschappen: 1, .recepten: 2])
                == "2 recepten en 1 boodschap wachten op iCloud — ze worden gedeeld zodra ze geüpload zijn.")
        #expect(
            ThuisExport.wachtMelding([.recepten: 1, .boodschappen: 3, .maaltijden: 1])
                == "1 recept, 3 boodschappen en 1 maaltijd wachten op iCloud — ze worden gedeeld zodra ze geüpload zijn."
        )
    }

    @Test func recordMetadataFoutInGewoneTaal() {
        let fout = NepDeelDienst.recordMetadataFout()
        let tekst = "Een recept is nog niet in iCloud bewaard. Knipsel probeert het opnieuw zodra dat gebeurd is."
        #expect(DeelFout.isOntbrekendeRecordMetadata(fout))
        #expect(DeelFout.uitleg(fout) == tekst)
        #expect(DeelFout.melding(fout, soort: .recepten) == tekst)
        #expect(DeelFout.melding(fout, soort: .boodschappen).hasPrefix("Een boodschap is nog niet in iCloud bewaard."))

        // Ook ingepakt, zoals CloudKit-mirroring het teruggeeft.
        let meerdere = NSError(
            domain: NSCocoaErrorDomain, code: NSValidationMultipleErrorsError,
            userInfo: [DeelFout.detailsSleutel: [fout]])
        let ingepakt = NSError(
            domain: "NSCloudKitMirroringDelegate", code: 134_400, userInfo: [NSUnderlyingErrorKey: meerdere])
        #expect(DeelFout.isOntbrekendeRecordMetadata(ingepakt))
        #expect(DeelFout.uitleg(ingepakt) == tekst)

        // Alleen de tekst, zonder veld in userInfo.
        let alleenTekst = NSError(
            domain: NSCocoaErrorDomain, code: NSValidationMissingMandatoryPropertyError,
            userInfo: [NSLocalizedDescriptionKey: "recordMetadata is een vereiste waarde."])
        #expect(DeelFout.isOntbrekendeRecordMetadata(alleenTekst))

        // Een ander leeg veld is wél een echte fout.
        let anders = NSError(
            domain: NSCocoaErrorDomain, code: NSValidationMissingMandatoryPropertyError,
            userInfo: [NSValidationKeyErrorKey: "kookboek"])
        #expect(!DeelFout.isOntbrekendeRecordMetadata(anders))
        #expect(!DeelFout.isOntbrekendeRecordMetadata(CKError(.quotaExceeded)))
    }

    @Test func zonderICloudIsAllesGeexporteerdEnWachtNiets() async throws {
        let opslag = legeOpslag()
        let dienst = GeenDeelDienst()
        let delen = ThuisDelen(opslag: opslag, dienst: dienst)
        let soep = try thuisRecept("Soep", delen)
        #expect(dienst.isGeexporteerd(soep.objectID))
        await delen.deelOpenstaande()
        await delen.naExport()
        #expect(delen.wachtMelding == nil)
        #expect(delen.fout == nil)
    }
}
