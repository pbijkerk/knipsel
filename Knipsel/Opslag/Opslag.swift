import CoreData
import OSLog

/// De Core Data-opslag van Knipsel.
///
/// `NSPersistentCloudKitContainer` (niet SwiftData), omdat alleen Core Data een gedeelde
/// CloudKit-database met een andere Apple ID ondersteunt (docs/ontwerp.md §7). Twee stores in één
/// container (fase 8, zoals Apple's voorbeeld *Sharing Core Data objects between iCloud users*):
///
/// - **privé** (`Knipsel.sqlite`, de bestaande store; CloudKit `databaseScope = .private`): je eigen
///   recepten, en als je Thuis zelf deelt (eigenaar) ook de Thuis-recepten — die staan dan in de
///   record zone van de share in je privédatabase;
/// - **gedeeld** (`Knipsel-gedeeld.sqlite`, nieuw; `databaseScope = .shared`): de Thuis-recepten van
///   iemand anders die jou heeft uitgenodigd (deelnemer).
///
/// Sync met iCloud gaat aan als `AppConfiguratie.cloudKitContainer` gezet is én er een iCloud-account
/// op het toestel is; anders (en altijd in het geheugen) werken beide als gewone lokale stores.
@MainActor
final class Opslag {
    /// Onder unit-tests start de app (testhost) met een lege opslag in het geheugen, zonder iCloud.
    static let gedeeld = Opslag(inGeheugen: draaitOnderTests, laadfoutVoorTest: debugLaadfout())

    static var draaitOnderTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Eén modelinstantie per proces: meerdere kopieën van hetzelfde model laten Core Data twijfelen
    /// welke entiteit bij een klasse hoort.
    static let model: NSManagedObjectModel = {
        guard let url = Bundle(for: Recept.self).url(forResource: "Knipsel", withExtension: "momd"),
            let model = NSManagedObjectModel(contentsOf: url)
        else { fatalError("Datamodel Knipsel.momd ontbreekt in de app") }
        return model
    }()

    /// Bestandsnaam van de gedeelde store, naast de bestaande `Knipsel.sqlite`.
    static let gedeeldeStoreNaam = "Knipsel-gedeeld.sqlite"

    let container: NSPersistentCloudKitContainer
    /// `true` als deze opslag met iCloud synchroniseert.
    let synchroniseert: Bool
    /// Per store waarom hij niet openging (audit v0.1, #1). Faalt de privéstore, dan probeert Knipsel
    /// de gedeelde niet en toont het herstelscherm; faalt alleen de gedeelde, dan werkt de app en
    /// staat er een melding in Instellingen › Thuis delen.
    private(set) var laadfouten: [Kookboeken.StoreSoort: any Error] = [:]
    /// De eerste fout bij het openen, of `nil` als alles openging.
    var laadfout: (any Error)? { laadfouten[.prive] ?? laadfouten[.gedeeld] }
    /// De privéstore is open: de app kan de bibliotheek tonen.
    var isGeopend: Bool { laadfouten[.prive] == nil && priveStore != nil }

    private let beschrijvingen: [(Kookboeken.StoreSoort, NSPersistentStoreDescription)]
    private let laadfoutVoorTest: ((Kookboeken.StoreSoort) -> (any Error)?)?

    private let logger = Logger(subsystem: "com.peterbijkerk.knipsel", category: "Opslag")
    private var ontdubbelTaak: Task<Void, Never>?

    var context: NSManagedObjectContext { container.viewContext }

    /// De privéstore ("Mijn recepten", en Thuis als je zelf de eigenaar bent).
    var priveStore: NSPersistentStore? { Kookboeken.store(.prive, in: container.persistentStoreCoordinator) }
    /// De gedeelde store (Thuis van een ander).
    var gedeeldeStore: NSPersistentStore? { Kookboeken.store(.gedeeld, in: container.persistentStoreCoordinator) }

    /// - Parameters:
    ///   - map: map voor de twee sqlite-bestanden; `nil` = de standaardmap van Core Data (waar de
    ///     bestaande `Knipsel.sqlite` al staat). Voor tests met echte bestanden.
    ///   - inGeheugen: voor tests en previews; niets wordt bewaard.
    ///   - cloudKitContainer: identifier van de CloudKit-container, of `nil` voor alleen lokaal.
    ///   - laadfoutVoorTest: geeft per store een fout terug om het openen te laten mislukken (tests en
    ///     de Debug-schakelaar `KNIPSEL_TEST_LAADFOUT`); die store wordt dan niet geopend.
    init(
        map: URL? = nil, inGeheugen: Bool = false, cloudKitContainer: String? = AppConfiguratie.cloudKitContainer,
        laadfoutVoorTest: ((Kookboeken.StoreSoort) -> (any Error)?)? = nil
    ) {
        container = NSPersistentCloudKitContainer(name: "Knipsel", managedObjectModel: Self.model)

        let prive = container.persistentStoreDescriptions.first ?? NSPersistentStoreDescription()
        if inGeheugen {
            // SQLite in het geheugen: ondersteunt (anders dan NSInMemoryStoreType) persistent history.
            prive.url = URL(fileURLWithPath: "/dev/null")
        } else if let map {
            prive.url = map.appendingPathComponent("Knipsel.sqlite")
        }
        let gedeeld = NSPersistentStoreDescription()
        if inGeheugen {
            // Een tweede store op /dev/null mag niet ("Can't add the same store twice"); met een
            // fragment is het een andere URL en blijft het SQLite in het geheugen.
            gedeeld.url = URL(string: "file:///dev/null#gedeeld")
        } else {
            let basis = prive.url?.deletingLastPathComponent() ?? NSPersistentContainer.defaultDirectoryURL()
            gedeeld.url = basis.appendingPathComponent(Self.gedeeldeStoreNaam)
        }

        for (beschrijving, soort) in [(prive, Kookboeken.StoreSoort.prive), (gedeeld, .gedeeld)] {
            beschrijving.type = NSSQLiteStoreType
            beschrijving.shouldMigrateStoreAutomatically = true
            beschrijving.shouldInferMappingModelAutomatically = true
            beschrijving.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            beschrijving.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
            beschrijving.setOption(soort.rawValue as NSString, forKey: Kookboeken.storeOptie)
        }

        // Zonder expliciete `nil` pakt de container zelf de eerste container uit de entitlements.
        if !inGeheugen, let cloudKitContainer, FileManager.default.ubiquityIdentityToken != nil {
            let priveOpties = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudKitContainer)
            priveOpties.databaseScope = .private
            prive.cloudKitContainerOptions = priveOpties
            let gedeeldOpties = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudKitContainer)
            gedeeldOpties.databaseScope = .shared
            gedeeld.cloudKitContainerOptions = gedeeldOpties
            synchroniseert = true
        } else {
            prive.cloudKitContainerOptions = nil
            gedeeld.cloudKitContainerOptions = nil
            synchroniseert = false
        }
        // De privéstore eerst: objecten zonder expliciete store komen daar (zoals vóór fase 8).
        container.persistentStoreDescriptions = [prive, gedeeld]
        beschrijvingen = [(.prive, prive), (.gedeeld, gedeeld)]
        self.laadfoutVoorTest = laadfoutVoorTest
        laadStores()

        let context = container.viewContext
        context.automaticallyMergesChangesFromParent = true
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        context.transactionAuthor = AppConfiguratie.transactieAuteur
        context.name = "viewContext"

        // Vóór elke bewaarbeurt van de app: nieuwe objecten in de juiste store, en een Thuis-recept
        // alleen aan Thuis-categorieën en -labels (Core Data kent geen relaties tussen stores, en
        // CloudKit deelt alles waar een recept aan vastzit). Alleen de viewContext: de contexten
        // van de CloudKit-import blijven ongemoeid.
        NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextWillSave, object: context, queue: nil
        ) { melding in
            guard let context = melding.object as? NSManagedObjectContext else { return }
            Kookboeken.herstel(in: context)
        }

        // Een toestel dat via iCloud de categorieën van een ander toestel binnenkrijgt, kan dubbelen
        // hebben (beide hebben bij de eerste start gezaaid). Na elke wijziging van buiten ontdubbelen.
        // De observer leeft zo lang als het proces; `weak self` maakt hem onschadelijk daarna.
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: container.persistentStoreCoordinator, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.planOntdubbelen()
            }
        }
    }

    // MARK: - Openen

    /// Opent de stores die nog niet open zijn, in de vaste volgorde privé, gedeeld. Eén aanroep van
    /// `loadPersistentStores`, zoals vóór de audit. Gaat de privéstore niet open, dan gaat een al
    /// geopende gedeelde store weer dicht: zonder privéstore zou Core Data nieuwe objecten in de
    /// gedeelde zetten. Er wordt niets gewist of hersteld.
    private func laadStores() {
        let coordinator = container.persistentStoreCoordinator
        var teLaden: [NSPersistentStoreDescription] = []
        for (soort, beschrijving) in beschrijvingen where Kookboeken.store(soort, in: coordinator) == nil {
            if let fout = laadfoutVoorTest?(soort) {
                laadfouten[soort] = fout
            } else {
                laadfouten[soort] = nil
                teLaden.append(beschrijving)
            }
        }
        if !teLaden.isEmpty {
            var fouten: [Kookboeken.StoreSoort: any Error] = [:]
            container.persistentStoreDescriptions = teLaden
            container.loadPersistentStores { beschrijving, error in
                guard let error else { return }
                let soort =
                    (beschrijving.options[Kookboeken.storeOptie] as? String)
                    .flatMap(Kookboeken.StoreSoort.init(rawValue:)) ?? .prive
                fouten[soort] = error
            }
            laadfouten.merge(fouten) { _, nieuw in nieuw }
            container.persistentStoreDescriptions = beschrijvingen.map(\.1)
        }
        if laadfouten[.prive] != nil, let gedeeld = Kookboeken.store(.gedeeld, in: coordinator) {
            do {
                try coordinator.remove(gedeeld)
            } catch {
                logger.error("Gedeelde store sluiten mislukt: \(DeelFout.logregel(error), privacy: .public)")
            }
        }
        for (soort, fout) in laadfouten.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            logger.error(
                "Store \(soort.rawValue, privacy: .public) openen mislukt: \(DeelFout.logregel(fout), privacy: .public) \(fout.localizedDescription, privacy: .public)"
            )
        }
    }

    /// "Probeer opnieuw" op het herstelscherm: de stores die niet open zijn nog eens openen, zonder
    /// de app te herstarten. Wat al open is blijft open. Geeft `true` als de privéstore nu open is.
    @discardableResult
    func probeerOpnieuwTeOpenen() -> Bool {
        laadStores()
        if isGeopend { logger.info("Opslag geopend na opnieuw proberen") }
        return isGeopend
    }

    #if DEBUG
        /// Debug-schakelaar om het herstelscherm op een toestel te zien (Xcode › Scheme › Run ›
        /// Environment): `KNIPSEL_TEST_LAADFOUT=prive` faalt één keer (Probeer opnieuw lukt dan),
        /// `prive-blijft` blijft falen, `gedeeld` laat alleen Thuis van een ander falen.
        private static func debugLaadfout() -> ((Kookboeken.StoreSoort) -> (any Error)?)? {
            guard !draaitOnderTests, let waarde = ProcessInfo.processInfo.environment["KNIPSEL_TEST_LAADFOUT"]
            else { return nil }
            let fout = NSError(
                domain: NSCocoaErrorDomain, code: NSPersistentStoreIncompatibleVersionHashError,
                userInfo: [NSLocalizedDescriptionKey: "Testfout via KNIPSEL_TEST_LAADFOUT"])
            var keer = 0
            return { soort in
                switch (waarde, soort) {
                case ("prive", .prive):
                    keer += 1
                    return keer == 1 ? fout : nil
                case ("prive-blijft", .prive), ("gedeeld", .gedeeld): return fout
                default: return nil
                }
            }
        }
    #else
        private static func debugLaadfout() -> ((Kookboeken.StoreSoort) -> (any Error)?)? { nil }
    #endif

    // MARK: - Inrichten

    /// Eerste start: standaardcategorieën en -labels aanmaken (één keer per toestel, alleen in
    /// "Mijn recepten") en ontdubbelen.
    func richIn(defaults: UserDefaults = .standard) {
        do {
            if !defaults.bool(forKey: AppConfiguratie.sleutelStandaardIngericht) {
                try Inrichting.zaaiStandaard(in: context)
                defaults.set(true, forKey: AppConfiguratie.sleutelStandaardIngericht)
            }
            try Inrichting.ontdubbel(in: context)
            try Inrichting.structureerIngredienten(in: context)
        } catch {
            logger.error("Inrichten mislukt: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func planOntdubbelen() {
        ontdubbelTaak?.cancel()
        ontdubbelTaak = Task { [weak self] in
            try? await Task.sleep(for: AppConfiguratie.ontdubbelVertraging)
            guard !Task.isCancelled, let self else { return }
            do {
                let verwijderd = try Inrichting.ontdubbel(in: self.context)
                if verwijderd > 0 {
                    self.logger.info("Ontdubbeld na iCloud-wijziging: \(verwijderd) dubbelen")
                }
            } catch {
                self.logger.error("Ontdubbelen mislukt: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

extension NSManagedObjectContext {
    /// Bewaart alleen als er iets veranderd is.
    func bewaarIndienNodig() throws {
        if hasChanges { try save() }
    }
}
