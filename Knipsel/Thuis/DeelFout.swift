import CloudKit
import CoreData

/// Wat `ThuisDelen` apart in de share zet: als één soort niet lukt, gaan de andere door, en de
/// foutmelding zegt welke soort het was.
enum ThuisSoort: String, CaseIterable, Sendable {
    case recepten
    case boodschappen
    case maaltijden

    /// Voor in de foutmelding: "Thuis bijwerken lukte niet voor de boodschappen: …".
    var naam: String {
        switch self {
        case .recepten: "de recepten"
        case .boodschappen: "de boodschappen"
        case .maaltijden: "het weekmenu"
        }
    }
}

/// Zet een fout van het delen om in gewone taal, en in een logregel zonder persoonsgegevens.
///
/// Waarom: Core Data geeft bij een validatiefout (code 1550–1680) een `localizedDescription` met een
/// onvervangen plaatshouder ("%{PROPERTY}@ is een vereiste waarde."). Welk veld en welke entiteit het
/// is, staat alleen in de `userInfo` (`NSValidationKeyErrorKey`, `NSValidationObjectErrorKey`), bij
/// meerdere fouten in `NSDetailedErrorsKey`.
enum DeelFout {
    /// Eén ontbrekend of ongeldig veld uit een Core Data-validatiefout.
    struct Validatie: Equatable, Sendable {
        /// Entiteitnaam (`Recept`, `BoodschappenItem`, of een interne van CloudKit zoals `NSCKRecordMetadata`).
        var entiteit: String?
        var veld: String?
        var code: Int
    }

    static let validatieCodes = 1550...1680

    /// De sleutel zoals Core Data hem echt in `userInfo` zet. In Swift heet de constante
    /// `NSDetailedErrorsKey` op iOS 26/27 letterlijk "NSDetailedErrorsKey" en vindt hij niets (gemeten in
    /// de tests); daarom beide.
    static let detailsSleutel = "NSDetailedErrors"

    // MARK: - Uitleg voor in beeld

    /// De melding in Instellingen › Thuis delen voor een fout bij het delen van één soort.
    static func melding(_ fout: any Error, soort: ThuisSoort) -> String {
        if isOntbrekendeRecordMetadata(fout) { return nogNietInICloud(soort.enkelvoud) }
        return "Thuis bijwerken lukte niet voor \(soort.naam): \(uitleg(fout))"
    }

    /// Het veld van `NSCKRecordZoneMoveReceipt` dat leeg blijft als een object de share in gaat
    /// voordat het naar iCloud is geëxporteerd (zie `ThuisExport`).
    static let recordMetadataVeld = "recordMetadata"

    /// Fout 1570 op `recordMetadata` (bij `NSCKRecordZoneMoveReceipt`): het object staat nog niet in
    /// iCloud. Geen echte fout — wachten op de export en het dan opnieuw proberen.
    static func isOntbrekendeRecordMetadata(_ fout: any Error) -> Bool {
        if validaties(in: fout).contains(where: {
            $0.veld == recordMetadataVeld || ($0.entiteit == "NSCKRecordZoneMoveReceipt" && $0.veld == nil)
        }) {
            return true
        }
        let ns = fout as NSError
        return ns.domain == NSCocoaErrorDomain && ns.code == NSValidationMissingMandatoryPropertyError
            && ns.localizedDescription.contains(recordMetadataVeld)
    }

    /// "Een recept is nog niet in iCloud bewaard. Knipsel probeert het opnieuw zodra dat gebeurd is."
    static func nogNietInICloud(_ wat: String = ThuisSoort.recepten.enkelvoud) -> String {
        "Een \(wat) is nog niet in iCloud bewaard. Knipsel probeert het opnieuw zodra dat gebeurd is."
    }

    /// Wat er misging, in gewone taal (zonder "Thuis bijwerken lukte niet").
    static func uitleg(_ fout: any Error) -> String {
        if isOntbrekendeRecordMetadata(fout) { return nogNietInICloud() }
        if let validatie = validaties(in: fout).first {
            return uitleg(validatie)
        }
        if let ck = ckFout(in: fout) {
            return uitleg(ck)
        }
        return (fout as NSError).localizedDescription
    }

    static func uitleg(_ validatie: Validatie) -> String {
        let wat = lidwoordEnNaam(entiteit: validatie.entiteit)
        let veld = validatie.veld.map { "'\($0)'" }
        switch validatie.code {
        case NSValidationMissingMandatoryPropertyError:
            return "bij \(wat) ontbreekt \(veld ?? "een verplicht veld")."
        case NSValidationRelationshipLacksMinimumCountError, NSValidationRelationshipExceedsMaximumCountError,
            NSValidationRelationshipDeniedDeleteError:
            return "bij \(wat) klopt de koppeling \(veld ?? "met een ander gegeven") niet."
        default:
            return "bij \(wat) is \(veld ?? "een veld") ongeldig."
        }
    }

    static func uitleg(_ fout: CKError) -> String {
        // Bij een gedeeltelijke fout is de echte oorzaak de eerste deelfout die niet "Batch Request
        // Failed" is (de rest van de batch valt mee om).
        if fout.code == .partialFailure,
            let echt = fout.partialErrorsByItemID?.values.compactMap({ $0 as? CKError })
                .first(where: { $0.code != .batchRequestFailed && $0.code != .partialFailure })
        {
            return uitleg(echt)
        }
        switch fout.code {
        case .serverRejectedRequest, .invalidArguments:
            return
                "iCloud-schema ontbreekt of is niet bijgewerkt — Deploy Schema Changes nodig (CloudKit-fout \(fout.code.rawValue))."
        case .unknownItem:
            return
                "iCloud kent een gegeven niet; waarschijnlijk ontbreekt het iCloud-schema — Deploy Schema Changes nodig (CloudKit-fout \(fout.code.rawValue))."
        case .networkUnavailable, .networkFailure:
            return "geen verbinding met iCloud. Knipsel probeert het later opnieuw."
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return "iCloud is even niet bereikbaar. Knipsel probeert het later opnieuw."
        case .notAuthenticated:
            return "je bent niet ingelogd bij iCloud."
        case .quotaExceeded:
            return "je iCloud-opslag is vol."
        case .permissionFailure:
            return "je mag Thuis niet wijzigen (geen toestemming)."
        case .zoneNotFound, .userDeletedZone:
            return "de gedeelde Thuis-zone bestaat niet meer in iCloud."
        case .participantMayNeedVerification:
            return "je huisgenoot moet de uitnodiging nog bevestigen."
        default:
            return "iCloud gaf een fout (CloudKit-fout \(fout.code.rawValue))."
        }
    }

    private static func lidwoordEnNaam(entiteit: String?) -> String {
        switch entiteit {
        case "Recept": "een recept"
        case "BoodschappenItem": "een boodschap"
        case "Maaltijd": "een maaltijd"
        case "Categorie": "een categorie"
        case "Label": "een label"
        case "Ingredient": "een ingrediënt"
        case "Stap": "een stap"
        case "Kooklog": "een kookbeurt"
        case let naam? where naam.hasPrefix("NSCK"): "een intern iCloud-gegeven (\(naam))"
        case let naam?: "een \(naam)"
        case nil: "een gegeven"
        }
    }

    // MARK: - Uit de fout halen

    /// Alle validatiefouten, ook genest in `NSDetailedErrorsKey` en `NSUnderlyingErrorKey`.
    static func validaties(in fout: any Error) -> [Validatie] {
        var gevonden: [Validatie] = []
        verzamel(fout as NSError, in: &gevonden, diepte: 0)
        return gevonden
    }

    private static func verzamel(_ fout: NSError, in gevonden: inout [Validatie], diepte: Int) {
        guard diepte < 6 else { return }
        if let details = (fout.userInfo[NSDetailedErrorsKey] ?? fout.userInfo[detailsSleutel]) as? [Any] {
            for case let detail as NSError in details { verzamel(detail, in: &gevonden, diepte: diepte + 1) }
        }
        if fout.domain == NSCocoaErrorDomain, validatieCodes.contains(fout.code),
            fout.code != NSValidationMultipleErrorsError
        {
            let object = fout.userInfo[NSValidationObjectErrorKey] as? NSManagedObject
            gevonden.append(
                Validatie(
                    entiteit: object?.entity.name, veld: fout.userInfo[NSValidationKeyErrorKey] as? String,
                    code: fout.code))
        }
        if let onder = fout.userInfo[NSUnderlyingErrorKey] as? NSError {
            verzamel(onder, in: &gevonden, diepte: diepte + 1)
        }
    }

    private static func ckFout(in fout: any Error) -> CKError? {
        var huidige: NSError? = fout as NSError
        for _ in 0..<6 {
            guard let fout = huidige else { return nil }
            if fout.domain == CKError.errorDomain, let ck = (fout as any Error) as? CKError { return ck }
            huidige = fout.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return nil
    }

    // MARK: - Log

    /// Domein, code, de sleutels van `userInfo` (geen waarden: daar kunnen recepttitels in staan) en
    /// per validatiefout entiteit en veld. Veilig voor `privacy: .public`.
    static func logregel(_ fout: any Error) -> String {
        let ns = fout as NSError
        var delen = ["domein=\(ns.domain)", "code=\(ns.code)", "sleutels=\(ns.userInfo.keys.sorted())"]
        let validaties = validaties(in: fout)
        if !validaties.isEmpty {
            delen.append(
                "validatie=["
                    + validaties.map { "\($0.entiteit ?? "?").\($0.veld ?? "?")(\($0.code))" }.joined(separator: ", ")
                    + "]")
        }
        if let ck = ckFout(in: fout) {
            delen.append("ckCode=\(ck.code.rawValue)")
            if let deel = ck.partialErrorsByItemID?.values {
                let codes = deel.compactMap { ($0 as? CKError)?.code.rawValue }
                delen.append("ckDeelCodes=\(Array(Set(codes)).sorted())")
            }
        }
        if let onder = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            delen.append("onderliggend=\(onder.domain)/\(onder.code)")
        }
        return delen.joined(separator: " ")
    }
}
