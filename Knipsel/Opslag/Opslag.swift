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
    static let gedeeld = Opslag(inGeheugen: draaitOnderTests)

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
    private(set) var laadfout: (any Error)?

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
    init(map: URL? = nil, inGeheugen: Bool = false, cloudKitContainer: String? = AppConfiguratie.cloudKitContainer) {
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

        var fout: (any Error)?
        container.loadPersistentStores { _, error in
            if let error { fout = fout ?? error }
        }
        laadfout = fout
        if let fout {
            logger.error("Opslag laden mislukt: \(fout.localizedDescription, privacy: .public)")
        }

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
