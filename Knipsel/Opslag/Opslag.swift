import CoreData
import OSLog

/// De Core Data-opslag van Knipsel.
///
/// `NSPersistentCloudKitContainer` (niet SwiftData), omdat alleen Core Data later een gedeelde
/// CloudKit-database met een andere Apple ID ondersteunt (fase 8, docs/ontwerp.md §7). Sync met
/// iCloud gaat pas aan als `AppConfiguratie.cloudKitContainer` gezet is én er een iCloud-account
/// op het toestel is; anders werkt de container als gewone lokale store.
@MainActor
final class Opslag {
    static let gedeeld = Opslag()

    /// Eén modelinstantie per proces: meerdere kopieën van hetzelfde model laten Core Data twijfelen
    /// welke entiteit bij een klasse hoort.
    static let model: NSManagedObjectModel = {
        guard let url = Bundle(for: Recept.self).url(forResource: "Knipsel", withExtension: "momd"),
            let model = NSManagedObjectModel(contentsOf: url)
        else { fatalError("Datamodel Knipsel.momd ontbreekt in de app") }
        return model
    }()

    let container: NSPersistentCloudKitContainer
    /// `true` als deze opslag met iCloud synchroniseert.
    let synchroniseert: Bool
    private(set) var laadfout: (any Error)?

    private let logger = Logger(subsystem: "com.peterbijkerk.knipsel", category: "Opslag")
    private var ontdubbelTaak: Task<Void, Never>?

    var context: NSManagedObjectContext { container.viewContext }

    /// - Parameters:
    ///   - inGeheugen: voor tests en previews; niets wordt bewaard.
    ///   - cloudKitContainer: identifier van de CloudKit-container, of `nil` voor alleen lokaal.
    init(inGeheugen: Bool = false, cloudKitContainer: String? = AppConfiguratie.cloudKitContainer) {
        container = NSPersistentCloudKitContainer(name: "Knipsel", managedObjectModel: Self.model)

        let beschrijving = container.persistentStoreDescriptions.first ?? NSPersistentStoreDescription()
        if inGeheugen {
            // SQLite in het geheugen: ondersteunt (anders dan NSInMemoryStoreType) persistent history.
            beschrijving.url = URL(fileURLWithPath: "/dev/null")
        }
        beschrijving.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        beschrijving.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        // Zonder expliciete `nil` pakt de container zelf de eerste container uit de entitlements.
        if !inGeheugen, let cloudKitContainer, FileManager.default.ubiquityIdentityToken != nil {
            beschrijving.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: cloudKitContainer)
            synchroniseert = true
        } else {
            beschrijving.cloudKitContainerOptions = nil
            synchroniseert = false
        }
        container.persistentStoreDescriptions = [beschrijving]

        var fout: (any Error)?
        container.loadPersistentStores { _, error in
            fout = error
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

    /// Eerste start: standaardcategorieën en -labels aanmaken (één keer per toestel) en ontdubbelen.
    func richIn(defaults: UserDefaults = .standard) {
        do {
            if !defaults.bool(forKey: AppConfiguratie.sleutelStandaardIngericht) {
                try Inrichting.zaaiStandaard(in: context)
                defaults.set(true, forKey: AppConfiguratie.sleutelStandaardIngericht)
            }
            try Inrichting.ontdubbel(in: context)
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
