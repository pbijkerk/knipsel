import EventKit
import Foundation
import OSLog

/// Mag Knipsel in Herinneringen schrijven?
enum HerinneringenToegang: Equatable, Sendable {
    case nietGevraagd
    case toegestaan
    case geweigerd
}

/// Een open herinnering in de boodschappenlijst.
struct HerinneringItem: Equatable, Sendable {
    let id: String
    var titel: String
}

/// Een regel die al (open) op de lijst staat, met wat er bij optellen van zou worden.
struct DubbelItem: Equatable, Sendable {
    let bestaand: HerinneringItem
    /// "5 uien" als "3 uien" en "2 uien" op te tellen zijn; anders `nil`.
    let opgeteld: String?
}

/// Wat te doen met een regel die al op de lijst staat. Standaard overslaan.
enum DubbelKeuze: Equatable, Sendable {
    case overslaan
    /// De titel van de bestaande herinnering bijwerken naar het totaal.
    case bijtellen
    /// Toch als losse herinnering erbij.
    case losToevoegen
}

/// Uitkomst van "Zet op de lijst".
struct Boodschappenresultaat: Equatable, Sendable {
    var toegevoegd = 0
    var bijgewerkt = 0
    var overgeslagen = 0
    /// Knipsel maakte de lijst "Boodschappen" net aan (uitleg over het lijsttype tonen).
    var lijstAangemaakt = false

    var aantal: Int { toegevoegd + bijgewerkt }
}

enum BoodschappenFout: LocalizedError {
    case geenToegang
    case geenBron

    var errorDescription: String? {
        switch self {
        case .geenToegang: "Knipsel heeft geen toegang tot Herinneringen."
        case .geenBron: "Er is geen account voor Herinneringen om de lijst in te maken."
        }
    }
}

/// Waar de boodschappen heen gaan. In de app Herinneringen; in tests en renders een nep.
@MainActor protocol Boodschappenbestemming: AnyObject {
    var toegang: HerinneringenToegang { get }
    func vraagToegang() async -> HerinneringenToegang
    /// Per regel-id: staat dit ingrediënt al open op de lijst?
    func dubbele(in regels: [BoodschappenRegel]) async -> [String: DubbelItem]
    func zetOpLijst(_ regels: [BoodschappenRegel], keuzes: [String: DubbelKeuze], notitie: String) async throws
        -> Boodschappenresultaat
}

/// De bewerkingen op Herinneringen die de dienst nodig heeft; dun laagje over `EKEventStore`, zodat de
/// logica (lijst zoeken of maken, geen dubbele, bijtellen) met een nep te testen is.
@MainActor protocol HerinneringenOpslag: AnyObject {
    var toegang: HerinneringenToegang { get }
    func vraagToegang() async -> HerinneringenToegang
    /// Id van een lijst met een van deze titels (hoofdletterongevoelig), liefst in de standaardbron.
    func zoekLijst(titels: [String]) -> String?
    func maakLijst(titel: String) throws -> String
    func openItems(inLijst id: String) async -> [HerinneringItem]
    func voegToe(titel: String, notitie: String, aanLijst id: String) throws
    func wijzigTitel(van id: String, naar titel: String) throws
    func bewaar() throws
}

/// Zet boodschappen in de lijst "Boodschappen" van Herinneringen (2B). Alles via EventKit op het
/// toestel (L6); iCloud synct de lijst zoals Apple dat doet.
@MainActor final class HerinneringenDienst: Boodschappenbestemming {
    static let gedeeld = HerinneringenDienst()

    /// Ook een bestaande "Boodschappenlijst" telt.
    static let lijstTitels = [AppConfiguratie.boodschappenLijstNaam, "Boodschappenlijst"]

    private let opslag: HerinneringenOpslag

    init(opslag: HerinneringenOpslag? = nil) {
        self.opslag = opslag ?? EventKitOpslag()
    }

    var toegang: HerinneringenToegang { opslag.toegang }

    func vraagToegang() async -> HerinneringenToegang {
        guard opslag.toegang == .nietGevraagd else { return opslag.toegang }
        return await opslag.vraagToegang()
    }

    func dubbele(in regels: [BoodschappenRegel]) async -> [String: DubbelItem] {
        guard opslag.toegang == .toegestaan, let lijst = opslag.zoekLijst(titels: Self.lijstTitels) else {
            return [:]
        }
        return Self.dubbele(regels, bestaand: await opslag.openItems(inLijst: lijst))
    }

    func zetOpLijst(_ regels: [BoodschappenRegel], keuzes: [String: DubbelKeuze], notitie: String) async throws
        -> Boodschappenresultaat
    {
        guard opslag.toegang == .toegestaan else { throw BoodschappenFout.geenToegang }
        var resultaat = Boodschappenresultaat()
        let lijst: String
        if let bestaand = opslag.zoekLijst(titels: Self.lijstTitels) {
            lijst = bestaand
        } else {
            lijst = try opslag.maakLijst(titel: AppConfiguratie.boodschappenLijstNaam)
            resultaat.lijstAangemaakt = true
        }
        // Opnieuw ophalen: de lijst kan veranderd zijn sinds het vel openging.
        let dubbele = Self.dubbele(regels, bestaand: await opslag.openItems(inLijst: lijst))
        for regel in regels {
            guard let dubbel = dubbele[regel.id] else {
                try opslag.voegToe(titel: regel.tekst, notitie: notitie, aanLijst: lijst)
                resultaat.toegevoegd += 1
                continue
            }
            switch keuzes[regel.id] ?? .overslaan {
            case .overslaan:
                resultaat.overgeslagen += 1
            case .bijtellen:
                if let opgeteld = dubbel.opgeteld {
                    try opslag.wijzigTitel(van: dubbel.bestaand.id, naar: opgeteld)
                    resultaat.bijgewerkt += 1
                } else {
                    resultaat.overgeslagen += 1
                }
            case .losToevoegen:
                try opslag.voegToe(titel: regel.tekst, notitie: notitie, aanLijst: lijst)
                resultaat.toegevoegd += 1
            }
        }
        try opslag.bewaar()
        return resultaat
    }

    /// Notitie bij elk item: "Pompoensoep met gember · Knipsel".
    static func notitie(recept: String) -> String { "\(recept) · Knipsel" }

    /// Meerdere recepten (#40): "Pompoensoep, Linzensalade · Knipsel".
    static func notitie(recepten: [String]) -> String { notitie(recept: recepten.joined(separator: ", ")) }

    /// Regels waarvan de genormaliseerde naam al open op de lijst staat ("Uien" of "2 uien" bij "3 uien").
    static func dubbele(_ regels: [BoodschappenRegel], bestaand: [HerinneringItem]) -> [String: DubbelItem] {
        var perSleutel: [String: HerinneringItem] = [:]
        for item in bestaand {
            let invoer = BoodschappenInvoer(regel: item.titel)
            let naam = invoer.hoeveelheid == nil ? item.titel : (invoer.naam ?? item.titel)
            let sleutel = BoodschappenLijst.sleutel(naam)
            if !sleutel.isEmpty, perSleutel[sleutel] == nil { perSleutel[sleutel] = item }
        }
        var uitkomst: [String: DubbelItem] = [:]
        for regel in regels {
            guard let item = perSleutel[regel.sleutel] else { continue }
            uitkomst[regel.id] = DubbelItem(
                bestaand: item, opgeteld: BoodschappenLijst.opgeteld(bestaand: item.titel, plus: regel))
        }
        return uitkomst
    }
}

// MARK: - EventKit

/// De echte opslag: `EKEventStore`, volledige toegang tot Herinneringen (iOS 17+).
@MainActor final class EventKitOpslag: HerinneringenOpslag {
    private let store = EKEventStore()
    private let log = Logger(subsystem: "com.peterbijkerk.knipsel", category: "Boodschappen")

    var toegang: HerinneringenToegang {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: .toegestaan
        case .notDetermined: .nietGevraagd
        default: .geweigerd
        }
    }

    func vraagToegang() async -> HerinneringenToegang {
        do {
            _ = try await store.requestFullAccessToReminders()
        } catch {
            log.error("Toegang tot Herinneringen mislukt: \(error.localizedDescription, privacy: .public)")
        }
        return toegang
    }

    func zoekLijst(titels: [String]) -> String? {
        let gezocht = titels.map { $0.lowercased() }
        let lijsten = store.calendars(for: .reminder).filter {
            $0.allowsContentModifications && gezocht.contains($0.title.lowercased())
        }
        let standaardBron = store.defaultCalendarForNewReminders()?.source?.sourceIdentifier
        // Eerst de exacte naam, en binnen een naam de standaardbron (meestal iCloud).
        for titel in gezocht {
            let passend = lijsten.filter { $0.title.lowercased() == titel }
            if let lijst = passend.first(where: { $0.source?.sourceIdentifier == standaardBron }) ?? passend.first {
                return lijst.calendarIdentifier
            }
        }
        return nil
    }

    func maakLijst(titel: String) throws -> String {
        // EventKit heeft geen API voor het lijsttype "Boodschappen": het wordt een gewone lijst, die de
        // gebruiker in Herinneringen kan omzetten (Toon lijstinfo › Lijsttype).
        let lijst = EKCalendar(for: .reminder, eventStore: store)
        lijst.title = titel
        guard
            let bron = store.defaultCalendarForNewReminders()?.source
                ?? store.sources.first(where: { $0.sourceType == .calDAV || $0.sourceType == .local })
        else { throw BoodschappenFout.geenBron }
        lijst.source = bron
        try store.saveCalendar(lijst, commit: true)
        return lijst.calendarIdentifier
    }

    func openItems(inLijst id: String) async -> [HerinneringItem] {
        guard let lijst = store.calendar(withIdentifier: id) else { return [] }
        let predicaat = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: [lijst])
        return await withCheckedContinuation { vervolg in
            Self.haalOp(predicaat, uit: store) { vervolg.resume(returning: $0) }
        }
    }

    /// Buiten de main actor gebouwd: EventKit roept de afhandeling op een eigen thread aan.
    nonisolated private static func haalOp(
        _ predicaat: NSPredicate, uit store: EKEventStore, klaar: @escaping @Sendable ([HerinneringItem]) -> Void
    ) {
        _ = store.fetchReminders(matching: predicaat) { herinneringen in
            klaar(
                (herinneringen ?? []).map { HerinneringItem(id: $0.calendarItemIdentifier, titel: $0.title ?? "") })
        }
    }

    func voegToe(titel: String, notitie: String, aanLijst id: String) throws {
        guard let lijst = store.calendar(withIdentifier: id) else { return }
        let herinnering = EKReminder(eventStore: store)
        herinnering.title = titel
        herinnering.notes = notitie
        herinnering.calendar = lijst
        try store.save(herinnering, commit: false)
    }

    func wijzigTitel(van id: String, naar titel: String) throws {
        guard let herinnering = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
        herinnering.title = titel
        try store.save(herinnering, commit: false)
    }

    func bewaar() throws {
        try store.commit()
    }
}
