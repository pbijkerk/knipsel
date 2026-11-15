import AppIntents
import CoreData
import CoreSpotlight
import OSLog

/// Houdt de Spotlight-index van recepten (`ReceptEntiteit`) bij: bij het starten, en kort na elke
/// wijziging (bewaren, verwijderen, iCloud). Alleen titel en categorie, alleen op dit toestel.
/// Werkt ook de recepten bij die Siri herkent in "Kook … met Knipsel".
@MainActor
final class ReceptIndex {
    static let gedeeld = ReceptIndex()

    private let logger = Logger(subsystem: "com.peterbijkerk.knipsel", category: "Spotlight")
    private var taak: Task<Void, Never>?
    private var gestart = false
    /// Wat er de vorige keer in de index ging, om verwijderde recepten eruit te halen.
    private var geindexeerd: Set<String>?

    /// Eén keer, bij het starten van de app. Niet onder tests (de testhost heeft een lege opslag).
    func start(opslag: Opslag = .gedeeld) {
        guard !gestart, !Opslag.draaitOnderTests else { return }
        gestart = true
        NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave, object: opslag.context, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.plan(opslag: opslag) }
        }
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: opslag.container.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.plan(opslag: opslag) }
        }
        plan(opslag: opslag, na: .zero)
    }

    private func plan(opslag: Opslag, na wachttijd: Duration = .seconds(1)) {
        taak?.cancel()
        taak = Task { [weak self] in
            try? await Task.sleep(for: wachttijd)
            guard !Task.isCancelled, let self else { return }
            await self.werkBij(context: opslag.context)
        }
    }

    private func werkBij(context: NSManagedObjectContext) async {
        let index = CSSearchableIndex.default()
        do {
            let recepten = try ReceptZoeker.alle(in: context)
            let ids = Set(recepten.map(\.id))
            if let vorige = geindexeerd {
                let weg = Array(vorige.subtracting(ids))
                if !weg.isEmpty { try await index.deleteAppEntities(identifiedBy: weg, ofType: ReceptEntiteit.self) }
            } else {
                // Eerste keer in dit proces: begin schoon, zodat ook eerder verwijderde recepten verdwijnen.
                try await index.deleteAppEntities(ofType: ReceptEntiteit.self)
            }
            try await index.indexAppEntities(recepten)
            geindexeerd = ids
            KnipselOpdrachten.updateAppShortcutParameters()
        } catch {
            logger.error("Spotlight bijwerken mislukt: \(error.localizedDescription, privacy: .public)")
        }
    }
}
