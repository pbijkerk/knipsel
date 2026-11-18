import CoreData

/// Wat `ThuisDelen` nodig heeft om alleen te delen wat al in iCloud staat.
///
/// Waarom: `NSPersistentCloudKitContainer.share(_:to:)` verhuist objecten naar de zone van de share en
/// legt daarvoor intern een `NSCKRecordZoneMoveReceipt` vast, met een verplichte verwijzing naar de
/// `NSCKRecordMetadata` van het object. Die metadata bestaat pas als het object (en alles waar het aan
/// vastzit) één keer naar CloudKit is geëxporteerd. Een recept dat net in Thuis kwam, of waarvan de
/// export eerder mislukte, geeft anders fout 1570 op `recordMetadata`.
enum ThuisExport {
    /// Hoe vaak Knipsel per app-start één object opnieuw probeert na een fout op `recordMetadata`.
    static let maxPogingen = 3
    /// Grens voor `graaf(van:)`: een Thuis-graaf is in de praktijk een paar honderd objecten.
    static let maxGraaf = 5000

    // MARK: Graaf

    /// Het object en alles wat `share(_:to:)` meeneemt: de hele samenhangende groep via alle relaties
    /// (een recept → zijn ingrediënten, stappen, kooklog, categorieën en labels → de andere recepten in
    /// die categorieën → …). Pas als die hele groep geëxporteerd is, kan het object veilig de share in.
    static func graaf(van object: NSManagedObject) -> Set<NSManagedObjectID> {
        var gezien: Set<NSManagedObjectID> = [object.objectID]
        var rij: [NSManagedObject] = [object]
        while let huidig = rij.popLast(), gezien.count < maxGraaf {
            for naam in huidig.entity.relationshipsByName.keys {
                for buur in buren(van: huidig, via: naam) where !buur.isDeleted {
                    if gezien.insert(buur.objectID).inserted { rij.append(buur) }
                }
            }
        }
        return gezien
    }

    private static func buren(van object: NSManagedObject, via relatie: String) -> [NSManagedObject] {
        switch object.value(forKey: relatie) {
        case let enkel as NSManagedObject: [enkel]
        case let set as Set<NSManagedObject>: Array(set)
        case let set as NSSet: set.allObjects.compactMap { $0 as? NSManagedObject }
        case let geordend as NSOrderedSet: geordend.array.compactMap { $0 as? NSManagedObject }
        default: []
        }
    }

    // MARK: Opnieuw laten exporteren

    /// Tekstvelden die `raakAan` even mag aanvullen; nooit `kookboek` (bepaalt de store en de zone).
    static let tekstvelden = ["naam", "tekst", "titel", "notitie", "notities", "ruweTekst"]

    /// Laat Core Data dit object opnieuw naar iCloud exporteren door een onschuldig veld écht te
    /// wijzigen. Hetzelfde veld op dezelfde waarde zetten telt niet: dan komt er niets in de persistent
    /// history en exporteert CloudKit niets (gemeten in een proef met een sqlite-store).
    ///
    /// - `Recept`: `gewijzigdOp = nu`.
    /// - Een object met een gevulde datum (kookbeurt, boodschap, maaltijd): die datum 1 ms later.
    /// - Anders (ingrediënt, stap, categorie, label): een tekstveld kort met een spatie erachter
    ///   bewaren en meteen terugzetten — twee wijzigingen in de history, de inhoud blijft gelijk.
    ///
    /// Bewaart zelf. Geeft `false` als er niets aan te raken viel.
    @discardableResult
    static func raakAan(_ object: NSManagedObject) throws -> Bool {
        guard let context = object.managedObjectContext, !object.isDeleted else { return false }
        let attributen = object.entity.attributesByName
        if attributen["gewijzigdOp"]?.attributeType == .dateAttributeType {
            object.setValue(Date.now, forKey: "gewijzigdOp")
            try context.save()
            return true
        }
        if let datum = attributen.keys.sorted().first(where: {
            attributen[$0]?.attributeType == .dateAttributeType && object.value(forKey: $0) is Date
        }), let waarde = object.value(forKey: datum) as? Date {
            object.setValue(waarde.addingTimeInterval(0.001), forKey: datum)
            try context.save()
            return true
        }
        if let veld = tekstvelden.first(where: {
            attributen[$0]?.attributeType == .stringAttributeType && object.value(forKey: $0) is String
        }), let waarde = object.value(forKey: veld) as? String {
            object.setValue(waarde + " ", forKey: veld)
            try context.save()
            object.setValue(waarde, forKey: veld)
            try context.save()
            return true
        }
        return false
    }

    // MARK: iCloud-gebeurtenissen

    /// Een export naar iCloud die klaar is en lukte: dan kan wat wachtte misschien de share in.
    static func isGeslaagdeExport(_ soort: NSPersistentCloudKitContainer.EventType, eind: Date?, gelukt: Bool) -> Bool {
        soort == .export && eind != nil && gelukt
    }

    // MARK: Melding

    /// De rustige regel in Instellingen › Thuis delen, of `nil` als er niets wacht.
    /// "2 recepten wachten op iCloud — ze worden gedeeld zodra ze geüpload zijn."
    static func wachtMelding(_ aantallen: [ThuisSoort: Int]) -> String? {
        let delen = ThuisSoort.allCases.compactMap { soort -> String? in
            guard let aantal = aantallen[soort], aantal > 0 else { return nil }
            return "\(aantal) \(aantal == 1 ? soort.enkelvoud : soort.meervoud)"
        }
        guard !delen.isEmpty else { return nil }
        let opsomming =
            delen.count == 1 ? delen[0] : delen.dropLast().joined(separator: ", ") + " en " + (delen.last ?? "")
        let totaal = aantallen.values.reduce(0, +)
        return totaal == 1
            ? "\(opsomming) wacht op iCloud — het wordt gedeeld zodra het geüpload is."
            : "\(opsomming) wachten op iCloud — ze worden gedeeld zodra ze geüpload zijn."
    }
}

extension ThuisSoort {
    var enkelvoud: String {
        switch self {
        case .recepten: "recept"
        case .boodschappen: "boodschap"
        case .maaltijden: "maaltijd"
        }
    }

    var meervoud: String {
        switch self {
        case .recepten: "recepten"
        case .boodschappen: "boodschappen"
        case .maaltijden: "maaltijden"
        }
    }
}
