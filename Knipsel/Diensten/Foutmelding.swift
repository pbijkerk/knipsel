import CloudKit
import CoreData
import EventKit
import Foundation

/// Zet een fout om in een Nederlandse zin voor in beeld, met wat de gebruiker probeerde als
/// context: "Toevoegen lukte niet: er is geen internetverbinding."
///
/// Waarom: `localizedDescription` van systeemfouten is vaak Engels of technisch ("The operation
/// couldn't be completed. (NSCocoaErrorDomain error 134030.)"), en bij een Core Data-validatiefout
/// staat er een onvervangen plaatshouder in (zie `DeelFout`). In beeld komt daarom altijd een zin van
/// Knipsel zelf; een onbekende fout krijgt een algemene zin met de code erachter, zodat die door te
/// geven is. In de log mag `localizedDescription` wel.
enum Foutmelding {
    /// De melding voor in beeld.
    /// - Parameters:
    ///   - actie: wat er niet lukte, met hoofdletter ("Toevoegen", "Op de lijst zetten"); `nil` als de
    ///     titel van de melding dat al zegt.
    static func tekst(_ fout: any Error, actie: String? = nil) -> String {
        let uitleg = uitleg(fout)
        guard let actie else { return metHoofdletter(uitleg) }
        return "\(actie) lukte niet: \(naDubbelepunt(uitleg))"
    }

    /// Wat er misging, zonder de actie. Zinnen van Knipsel zelf (een eigen `LocalizedError`) komen
    /// ongewijzigd terug; vertaalde systeemfouten beginnen met een kleine letter, zoals bij `DeelFout`.
    static func uitleg(_ fout: any Error) -> String {
        let ns = fout as NSError
        if isEigenFout(ns), let eigen = (fout as? any LocalizedError)?.errorDescription, !eigen.isEmpty {
            return eigen
        }
        if let validatie = DeelFout.validaties(in: fout).first {
            return DeelFout.uitleg(validatie)
        }
        if let ck = zoek(in: ns, domein: CKError.errorDomain).flatMap({ ($0 as any Error) as? CKError }) {
            return DeelFout.uitleg(ck)
        }
        if let ek = zoek(in: ns, domein: EKErrorDomain) {
            return herinneringen(ek.code)
        }
        if let url = zoek(in: ns, domein: NSURLErrorDomain) {
            return netwerk(url.code)
        }
        if let status = zoek(in: ns, domein: NSOSStatusErrorDomain), let zin = sleutelhanger(status.code) {
            return zin
        }
        if ns.domain == NSCocoaErrorDomain, let zin = cocoa(ns.code) {
            return zin
        }
        return algemeen(ns)
    }

    /// "NSCocoaErrorDomain 134110": klein onder een melding, en om door te geven.
    static func code(_ fout: any Error) -> String {
        let ns = fout as NSError
        return "\(ns.domain) \(ns.code)"
    }

    /// De terugval: geen Engelse systeemtekst, wel de code.
    static func algemeen(_ fout: NSError) -> String {
        "er ging iets onverwachts mis (code \(fout.domain) \(fout.code))."
    }

    // MARK: - Per soort

    static func herinneringen(_ code: Int) -> String {
        switch EKError.Code(rawValue: code) {
        case .calendarReadOnly, .calendarIsImmutable:
            return "deze lijst in Herinneringen kan niet worden gewijzigd."
        case .noCalendar, .calendarHasNoSource, .objectBelongsToDifferentStore:
            return "de lijst in Herinneringen is niet gevonden. Kies of maak een lijst en probeer het opnieuw."
        case .calendarDoesNotAllowReminders, .sourceDoesNotAllowReminders, .sourceDoesNotAllowCalendarAddDelete:
            return
                "dit account in Herinneringen kan geen herinneringen bewaren. Kies een lijst van iCloud of Op mijn iPhone."
        default:
            return "Herinneringen gaf een fout (code \(EKErrorDomain) \(code))."
        }
    }

    static func netwerk(_ code: Int) -> String {
        switch URLError.Code(rawValue: code) {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            return "er is geen internetverbinding."
        case .timedOut:
            return "de verbinding duurde te lang. Probeer het straks nog eens."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return "de website is niet bereikbaar."
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
            .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected:
            return "er kon geen veilige verbinding met de website worden gemaakt."
        case .cancelled:
            return "het ophalen is afgebroken."
        default:
            return "de verbinding met internet lukte niet (code \(NSURLErrorDomain) \(code))."
        }
    }

    static func sleutelhanger(_ code: Int) -> String? {
        switch OSStatus(code) {
        case errSecItemNotFound:
            return "de sleutel staat niet in de sleutelhanger van dit toestel."
        case errSecInteractionNotAllowed:
            return "de sleutelhanger is op slot. Ontgrendel je toestel en probeer het opnieuw."
        case errSecDuplicateItem:
            return "de sleutel staat al in de sleutelhanger."
        case errSecAuthFailed:
            return "de sleutelhanger weigerde de toegang."
        default:
            return nil
        }
    }

    static func cocoa(_ code: Int) -> String? {
        switch code {
        case NSManagedObjectMergeError, NSPersistentStoreSaveConflictsError, NSManagedObjectConstraintMergeError:
            return "het is net op een ander toestel gewijzigd. Probeer het nog eens."
        case NSFileWriteOutOfSpaceError:
            return "er is te weinig ruimte op dit toestel."
        case NSFileReadNoSuchFileError, NSFileNoSuchFileError:
            return "het bestand is niet (meer) gevonden."
        case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
            return "Knipsel mag dit bestand niet openen."
        case 134_000...134_999:  // NSPersistentStore…Error: openen, bewaren, migreren
            return "de opslag van Knipsel is op dit moment niet beschikbaar (code \(NSCocoaErrorDomain) \(code))."
        default:
            return nil
        }
    }

    // MARK: - Hulp

    /// Een fout van Knipsel zelf (Swift-`enum` met eigen Nederlandse tekst): het domein is dan de
    /// modulenaam ("Knipsel.OphaalFout", in tests "KnipselTests.…").
    private static func isEigenFout(_ fout: NSError) -> Bool {
        fout.domain.hasPrefix("Knipsel")
    }

    /// De fout zelf of een onderliggende fout met dit domein.
    private static func zoek(in fout: NSError, domein: String) -> NSError? {
        var huidige: NSError? = fout
        for _ in 0..<6 {
            guard let fout = huidige else { return nil }
            if fout.domain == domein { return fout }
            huidige = fout.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return nil
    }

    /// Eigennamen houden hun hoofdletter; anders na een dubbelepunt met een kleine letter.
    static func naDubbelepunt(_ zin: String) -> String {
        guard let eerste = zin.first, !begintMetEigennaam(zin) else { return zin }
        return eerste.lowercased() + zin.dropFirst()
    }

    static func metHoofdletter(_ zin: String) -> String {
        guard let eerste = zin.first, !begintMetEigennaam(zin) else { return zin }
        return eerste.uppercased() + zin.dropFirst()
    }

    private static let eigennamen: Set<String> = ["Knipsel", "Thuis", "Herinneringen", "Claude", "Safari", "Foto's"]

    private static func begintMetEigennaam(_ zin: String) -> Bool {
        let woord = zin.prefix { !$0.isWhitespace && $0 != "," && $0 != ":" }
        if eigennamen.contains(String(woord)) { return true }
        // "iCloud", "iPhone": de tweede letter is een hoofdletter.
        let letters = Array(woord)
        return letters.count > 1 && letters[0].isLowercase && letters[1].isUppercase
    }
}
