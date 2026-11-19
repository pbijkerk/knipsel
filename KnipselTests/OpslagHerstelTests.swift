import CoreData
import Foundation
import Testing

@testable import Knipsel

/// Audit v0.1, #1: als de opslag niet opengaat, is dat zichtbaar en is opnieuw proberen veilig.
private let fout = NSError(
    domain: NSCocoaErrorDomain, code: NSPersistentStoreIncompatibleVersionHashError,
    userInfo: [NSLocalizedDescriptionKey: "The model used to open the store is incompatible."])

@MainActor
struct OpslagHerstelTests {
    @Test func zonderFoutGaatAllesOpen() {
        let opslag = Opslag(inGeheugen: true)
        #expect(opslag.isGeopend)
        #expect(opslag.laadfouten.isEmpty)
        #expect(opslag.priveStore != nil)
        #expect(opslag.gedeeldeStore != nil)
        // De volgorde blijft privé, gedeeld (nieuwe objecten zonder store komen in de privéstore).
        let soorten = opslag.container.persistentStoreCoordinator.persistentStores.map(Kookboeken.soort(van:))
        #expect(soorten == [.prive, .gedeeld])
        #expect(opslag.container.persistentStoreDescriptions.count == 2)
    }

    @Test func privestoreFaaltGeeftHerstelschermEnGeenGedeeldeStore() {
        let opslag = Opslag(inGeheugen: true, laadfoutVoorTest: { $0 == .prive ? fout : nil })
        #expect(!opslag.isGeopend)
        #expect((opslag.laadfout as? NSError)?.code == NSPersistentStoreIncompatibleVersionHashError)
        #expect(opslag.priveStore == nil)
        // Zonder privéstore ook geen gedeelde: anders kwamen nieuwe objecten daar terecht.
        #expect(opslag.gedeeldeStore == nil)
        #expect(opslag.container.persistentStoreCoordinator.persistentStores.isEmpty)
    }

    @Test func opnieuwProberenOpentDeStoresInDeJuisteVolgorde() throws {
        var pogingen = 0
        let opslag = Opslag(
            inGeheugen: true,
            laadfoutVoorTest: { soort in
                guard soort == .prive else { return nil }
                pogingen += 1
                return pogingen <= 2 ? fout : nil
            })
        #expect(!opslag.isGeopend)
        #expect(!opslag.probeerOpnieuwTeOpenen())
        #expect(opslag.probeerOpnieuwTeOpenen())
        #expect(opslag.isGeopend)
        #expect(opslag.laadfout == nil)
        let soorten = opslag.container.persistentStoreCoordinator.persistentStores.map(Kookboeken.soort(van:))
        #expect(soorten == [.prive, .gedeeld])

        // De app werkt daarna gewoon: een nieuw recept komt in de privéstore.
        let recept = Recept(context: opslag.context)
        recept.titel = "Herstelsoep"
        try opslag.context.save()
        #expect(recept.objectID.persistentStore == opslag.priveStore)
    }

    @Test func opnieuwProberenLaatEenGeopendeStoreMetRust() throws {
        let opslag = Opslag(inGeheugen: true, laadfoutVoorTest: { $0 == .gedeeld ? fout : nil })
        let prive = try #require(opslag.priveStore)
        let recept = Recept(context: opslag.context)
        recept.titel = "Blijft staan"
        try opslag.context.save()

        opslag.probeerOpnieuwTeOpenen()
        #expect(opslag.priveStore === prive)
        #expect(try opslag.context.count(for: Recept.verzoek()) == 1)
    }

    @Test func alleenGedeeldeStoreFaaltDanWerktDeApp() throws {
        let opslag = Opslag(inGeheugen: true, laadfoutVoorTest: { $0 == .gedeeld ? fout : nil })
        #expect(opslag.isGeopend)
        #expect(opslag.laadfouten[.prive] == nil)
        #expect(opslag.laadfouten[.gedeeld] != nil)
        #expect(opslag.gedeeldeStore == nil)

        // Bewaren gaat naar de privéstore, ook voor Thuis (zoals voor een eigenaar).
        let recept = Recept(context: opslag.context)
        recept.titel = "Thuisrecept"
        recept.setValue(Kookboek.thuis.rawValue, forKey: "kookboek")
        try opslag.context.save()
        #expect(recept.objectID.persistentStore == opslag.priveStore)

        // De melding staat in Instellingen › Thuis delen, via ThuisDelen.opslag.
        let delen = ThuisDelen(opslag: opslag, dienst: GeenDeelDienst())
        #expect(delen.opslag.laadfouten[.gedeeld] != nil)
    }

    // MARK: Teksten

    @Test func uitlegStelGerustZonderAutomatischHerstel() {
        #expect(Herstel.titel == "Je recepten konden niet worden geopend")
        let metICloud = Herstel.uitleg(synchroniseert: true)
        #expect(metICloud.hasPrefix("Je recepten zijn niet weg."))
        #expect(metICloud.contains("in iCloud en op dit toestel"))
        #expect(!Herstel.uitleg(synchroniseert: false).contains("iCloud"))
        #expect(Herstel.nogSteedsNiet.contains("Sluit Knipsel helemaal af"))
        for tekst in [metICloud, Herstel.nogSteedsNiet, Herstel.thuisUitleg] {
            #expect(!tekst.contains("cruciaal") && !tekst.contains("naadloos"))
        }
    }

    @Test func kopieertekstNoemtStoreEnCode() {
        let tekst = Herstel.kopieertekst(
            fout: fout, store: .prive, versie: "1.2 (34)", toestel: "iPhone", systeem: "26.1")
        #expect(tekst.hasPrefix("Knipsel 1.2 (34), iPhone iOS 26.1"))
        #expect(tekst.contains("Mijn recepten (privéstore)"))
        #expect(tekst.contains("Code: NSCocoaErrorDomain 134100"))
        #expect(tekst.contains("domein=NSCocoaErrorDomain code=134100"))
        let thuis = Herstel.kopieertekst(fout: fout, store: .gedeeld, versie: "1", toestel: "iPad", systeem: "26")
        #expect(thuis.contains("gedeelde store"))
    }
}
