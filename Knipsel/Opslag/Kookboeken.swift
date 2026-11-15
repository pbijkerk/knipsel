import CoreData

/// Welke store en welke objecten bij "Mijn recepten" en "Thuis" horen, en recepten verplaatsen of
/// kopiëren tussen de twee (fase 8, B8).
///
/// Waar een Thuis-recept staat, hangt af van je rol (zoals in Apple's voorbeeld *Sharing Core Data
/// objects between iCloud users*):
/// - wie Thuis deelt (eigenaar), of nog niemand heeft uitgenodigd: in de **privéstore**, met
///   `kookboek = "thuis"`; `NSPersistentCloudKitContainer.share(_:to:)` zet het daarna in de record
///   zone van de share;
/// - wie is uitgenodigd (deelnemer): in de **gedeelde store** (de gedeelde database van de eigenaar).
///
/// Core Data kent geen relaties tussen stores, en CloudKit deelt een recept met alles waar het aan
/// vastzit (ook de categorie en via die categorie álle andere recepten erin). Daarom heeft elk
/// kookboek eigen categorieën en labels met dezelfde namen; de weergave voegt ze op naam samen.
enum Kookboeken {
    /// Optie in de store-beschrijving die zegt welke store het is.
    static let storeOptie = "KnipselStore"

    enum StoreSoort: String, Sendable {
        case prive
        case gedeeld
    }

    // MARK: - Stores

    static func store(_ soort: StoreSoort, in coordinator: NSPersistentStoreCoordinator?) -> NSPersistentStore? {
        coordinator?.persistentStores.first { self.soort(van: $0) == soort }
    }

    static func soort(van store: NSPersistentStore?) -> StoreSoort? {
        (store?.options?[storeOptie] as? String).flatMap(StoreSoort.init(rawValue:))
    }

    /// Staat Thuis op dit toestel in de gedeelde store (je bent uitgenodigd)? Dat is zo zodra daar
    /// iets staat: een share van een ander kan niet leeg beginnen.
    static func thuisIsGedeeldeStore(in context: NSManagedObjectContext) -> Bool {
        guard let gedeeld = store(.gedeeld, in: context.persistentStoreCoordinator) else { return false }
        for entiteit in ["Recept", "Categorie", "Label"] {
            let verzoek = NSFetchRequest<NSManagedObject>(entityName: entiteit)
            verzoek.affectedStores = [gedeeld]
            verzoek.fetchLimit = 1
            if ((try? context.count(for: verzoek)) ?? 0) > 0 { return true }
        }
        return false
    }

    /// De store voor nieuwe objecten van dit kookboek.
    static func store(voor kookboek: Kookboek, in context: NSManagedObjectContext) -> NSPersistentStore? {
        let coordinator = context.persistentStoreCoordinator
        switch kookboek {
        case .mijn:
            return store(.prive, in: coordinator)
        case .thuis:
            if thuisIsGedeeldeStore(in: context) { return store(.gedeeld, in: coordinator) }
            return store(.prive, in: coordinator)
        }
    }

    // MARK: - Vóór het bewaren

    /// Aangeroepen vóór elke bewaarbeurt van de viewContext (`Opslag`): nieuwe objecten krijgen de
    /// store van hun kookboek (ingrediënten, stappen en kooklog die van hun recept), en een recept
    /// hangt alleen aan categorieën en labels van zijn eigen kookboek in zijn eigen store — een
    /// keuze uit het andere kookboek wordt de gelijknamige (die zo nodig ontstaat).
    static func herstel(in context: NSManagedObjectContext) {
        guard store(.prive, in: context.persistentStoreCoordinator) != nil else { return }
        let ingevoegd = context.insertedObjects
        var thuisStore: NSPersistentStore??
        func storeVoor(_ kookboek: Kookboek) -> NSPersistentStore? {
            if kookboek == .mijn { return store(.prive, in: context.persistentStoreCoordinator) }
            if thuisStore == nil { thuisStore = .some(store(voor: .thuis, in: context)) }
            return thuisStore ?? nil
        }

        // 1. Nieuwe recepten.
        for recept in ingevoegd.compactMap({ $0 as? Recept }) where recept.objectID.persistentStore == nil {
            if let doel = storeVoor(recept.kookboekWaarde) { context.assign(recept, to: doel) }
        }
        // 2. Nieuwe onderdelen volgen hun recept.
        for object in ingevoegd where object.objectID.persistentStore == nil {
            let recept: Recept? =
                switch object {
                case let ingredient as Ingredient: ingredient.recept
                case let stap as Stap: stap.recept
                case let log as Kooklog: log.recept
                default: nil
                }
            if let doel = recept?.objectID.persistentStore { context.assign(object, to: doel) }
        }
        // 3. Categorieën en labels van nieuwe en gewijzigde recepten.
        var cache = Naamgenoten()
        let recepten = (ingevoegd.union(context.updatedObjects)).compactMap { $0 as? Recept }.filter { !$0.isDeleted }
        for recept in recepten {
            guard let doel = recept.objectID.persistentStore else { continue }
            let kookboek = recept.kookboekWaarde
            let categorieen = recept.categorieen ?? []
            if categorieen.contains(where: { !hoortBij($0, kookboek: kookboek, store: doel, context: context) }) {
                recept.categorieen = Set(
                    categorieen.map { categorie in
                        hoortBij(categorie, kookboek: kookboek, store: doel, context: context)
                            ? categorie
                            : cache.categorie(zoals: categorie, kookboek: kookboek, store: doel, in: context)
                    })
            }
            let labels = recept.labels ?? []
            if labels.contains(where: { !hoortBij($0, kookboek: kookboek, store: doel, context: context) }) {
                recept.labels = Set(
                    labels.map { label in
                        hoortBij(label, kookboek: kookboek, store: doel, context: context)
                            ? label
                            : cache.label(zoals: label, kookboek: kookboek, store: doel, in: context)
                    })
            }
        }
        // 4. Overige nieuwe categorieën en labels (beheer, inrichting): de store van hun kookboek.
        for object in context.insertedObjects where object.objectID.persistentStore == nil {
            if object is Categorie || object is ReceptLabel,
                let doel = storeVoor(Kookboek(veld: object.kookboekVeld))
            {
                context.assign(object, to: doel)
            }
        }
    }

    /// Mag `object` (categorie of label) aan een recept van `kookboek` in `store` hangen? Een nieuw
    /// object zonder store dat nog nergens anders aan hangt, wordt hier meteen goed gezet.
    private static func hoortBij(
        _ object: NSManagedObject, kookboek: Kookboek, store: NSPersistentStore, context: NSManagedObjectContext
    ) -> Bool {
        if object.objectID.persistentStore == nil, object.isInserted {
            object.setValue(kookboek.rawValue, forKey: "kookboek")
            context.assign(object, to: store)
            return true
        }
        return Kookboek(veld: object.kookboekVeld) == kookboek && object.objectID.persistentStore === store
    }

    /// Zoekt (en maakt zo nodig) de gelijknamige categorie of het gelijknamige label in een
    /// kookboek en store; onthoudt wat het binnen één bewerking al vond.
    struct Naamgenoten {
        private var categorieen: [String: Categorie] = [:]
        private var labels: [String: ReceptLabel] = [:]

        private func sleutel(_ naam: String?, _ kookboek: Kookboek, _ store: NSPersistentStore) -> String {
            "\(store.identifier ?? "")|\(kookboek.rawValue)|\(Inrichting.sleutel(naam ?? ""))"
        }

        mutating func categorie(
            zoals bron: Categorie, kookboek: Kookboek, store: NSPersistentStore, in context: NSManagedObjectContext
        ) -> Categorie {
            let sleutel = sleutel(bron.naam, kookboek, store)
            if let bekend = categorieen[sleutel] { return bekend }
            let gevonden = Kookboeken.zoek(
                Categorie.verzoek(), naam: bron.naam, kookboek: kookboek, store: store, in: context)
            let categorie =
                gevonden
                ?? {
                    let nieuw = Categorie(context: context)
                    nieuw.naam = bron.naam
                    nieuw.symbool = bron.symbool
                    nieuw.volgorde = bron.volgorde
                    nieuw.isStandaard = bron.isStandaard
                    nieuw.kookboek = kookboek.rawValue
                    context.assign(nieuw, to: store)
                    return nieuw
                }()
            categorieen[sleutel] = categorie
            return categorie
        }

        mutating func label(
            zoals bron: ReceptLabel, kookboek: Kookboek, store: NSPersistentStore, in context: NSManagedObjectContext
        ) -> ReceptLabel {
            let sleutel = sleutel(bron.naam, kookboek, store)
            if let bekend = labels[sleutel] { return bekend }
            let gevonden = Kookboeken.zoek(
                ReceptLabel.verzoek(), naam: bron.naam, kookboek: kookboek, store: store, in: context)
            let label =
                gevonden
                ?? {
                    let nieuw = ReceptLabel(context: context)
                    nieuw.naam = bron.naam
                    nieuw.kookboek = kookboek.rawValue
                    context.assign(nieuw, to: store)
                    return nieuw
                }()
            labels[sleutel] = label
            return label
        }
    }

    /// De gelijknamige (hoofdletters en accenten tellen niet) in `store` en `kookboek`; bij dubbelen
    /// die met de laagste uuid, zoals `Inrichting.ontdubbel` hem laat staan.
    static func zoek<T: NSManagedObject>(
        _ verzoek: NSFetchRequest<T>, naam: String?, kookboek: Kookboek, store: NSPersistentStore,
        in context: NSManagedObjectContext
    ) -> T? {
        let doel = Inrichting.sleutel(naam ?? "")
        verzoek.affectedStores = [store]
        let opgeslagen = (try? context.fetch(verzoek)) ?? []
        // Nog niet bewaarde objecten die al aan deze store zijn toegewezen.
        let nieuw = context.insertedObjects.compactMap { $0 as? T }.filter { $0.objectID.persistentStore === store }
        return (opgeslagen + nieuw)
            .filter {
                !$0.isDeleted && Kookboek(veld: $0.kookboekVeld) == kookboek
                    && Inrichting.sleutel($0.value(forKey: "naam") as? String ?? "") == doel
            }
            .min {
                (($0.value(forKey: "uuid") as? UUID)?.uuidString ?? "~")
                    < (($1.value(forKey: "uuid") as? UUID)?.uuidString ?? "~")
            }
    }

    // MARK: - Verplaatsen en kopiëren

    enum Fout: LocalizedError {
        case geenStore

        var errorDescription: String? {
            switch self {
            case .geenStore: "De opslag voor dit kookboek is niet beschikbaar."
            }
        }
    }

    /// Verplaatst een recept naar het andere kookboek: een volledige kopie (ingrediënten, stappen,
    /// foto, kooklog, beoordeling, dezelfde `uuid`) in de store van het doel, aan de gelijknamige
    /// categorieën en labels daar, en het origineel weg — in één bewaarbeurt, dus alles of niets.
    /// Geeft het nieuwe recept terug (ander objectID; de `uuid` blijft).
    @discardableResult
    static func verplaats(_ recept: Recept, naar kookboek: Kookboek) throws -> Recept {
        guard let context = recept.managedObjectContext else { throw Fout.geenStore }
        guard recept.kookboekWaarde != kookboek else { return recept }
        do {
            var cache = Naamgenoten()
            let kopie = try kopieer(recept, naar: kookboek, cache: &cache)
            context.delete(recept)
            try context.save()
            return kopie
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Verplaatst alle recepten van het ene kookboek naar het andere (bij "Stop met delen").
    @discardableResult
    static func verplaatsAlles(van bron: Kookboek, naar doel: Kookboek, in context: NSManagedObjectContext) throws
        -> [Recept]
    {
        let recepten = try recepten(in: bron, context: context)
        do {
            var cache = Naamgenoten()
            let kopieen = try recepten.map { try kopieer($0, naar: doel, cache: &cache) }
            recepten.forEach(context.delete)
            try context.bewaarIndienNodig()
            return kopieen
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Kopieert alle recepten van een kookboek naar een ander; de originelen blijven (bij "Verlaat
    /// Thuis": die verdwijnen daarna met de share). De kopieën houden hun `uuid`.
    @discardableResult
    static func kopieerAlles(van bron: Kookboek, naar doel: Kookboek, in context: NSManagedObjectContext) throws
        -> [Recept]
    {
        let recepten = try recepten(in: bron, context: context)
        do {
            var cache = Naamgenoten()
            let kopieen = try recepten.map { try kopieer($0, naar: doel, cache: &cache) }
            try context.bewaarIndienNodig()
            return kopieen
        } catch {
            context.rollback()
            throw error
        }
    }

    static func recepten(in kookboek: Kookboek, context: NSManagedObjectContext) throws -> [Recept] {
        let verzoek = Recept.verzoek()
        verzoek.predicate = NSPredicate(format: "kookboek == %@", kookboek.rawValue)
        verzoek.sortDescriptors = ReceptFilter.sortering
        return try context.fetch(verzoek)
    }

    /// Een diepe kopie in de store van `kookboek`, niet bewaard.
    static func kopieer(_ bron: Recept, naar kookboek: Kookboek, cache: inout Naamgenoten) throws -> Recept {
        guard let context = bron.managedObjectContext, let doel = store(voor: kookboek, in: context) else {
            throw Fout.geenStore
        }
        let kopie = Recept(context: context)
        kopieerAttributen(van: bron, naar: kopie, behalve: ["kookboek"])
        kopie.kookboek = kookboek.rawValue
        context.assign(kopie, to: doel)

        for ingredient in bron.ingredienten ?? [] {
            let nieuw = Ingredient(context: context)
            kopieerAttributen(van: ingredient, naar: nieuw)
            nieuw.recept = kopie
            context.assign(nieuw, to: doel)
        }
        for stap in bron.stappen ?? [] {
            let nieuw = Stap(context: context)
            kopieerAttributen(van: stap, naar: nieuw)
            nieuw.recept = kopie
            context.assign(nieuw, to: doel)
        }
        for log in bron.kooklog ?? [] {
            let nieuw = Kooklog(context: context)
            kopieerAttributen(van: log, naar: nieuw)
            nieuw.recept = kopie
            context.assign(nieuw, to: doel)
        }
        kopie.categorieen = Set(
            (bron.categorieen ?? []).map { cache.categorie(zoals: $0, kookboek: kookboek, store: doel, in: context) })
        kopie.labels = Set(
            (bron.labels ?? []).map { cache.label(zoals: $0, kookboek: kookboek, store: doel, in: context) })
        return kopie
    }

    private static func kopieerAttributen(
        van bron: NSManagedObject, naar doel: NSManagedObject, behalve: Set<String> = []
    ) {
        for naam in bron.entity.attributesByName.keys where !behalve.contains(naam) {
            doel.setValue(bron.value(forKey: naam), forKey: naam)
        }
    }
}
