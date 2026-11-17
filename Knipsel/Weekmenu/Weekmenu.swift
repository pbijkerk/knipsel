import CoreData
import Foundation

/// Het weekmenu in Core Data (#41): één week per kookboek (Mijn week of Thuis). Nieuwe maaltijden komen
/// via `Kookboeken.herstel` in de store van hun kookboek; `ThuisDelen` zet ze daarna in de share. De
/// rekenregels staan in `Weekplanning`; hier alleen lezen, omzetten en terugschrijven.
///
/// Gepland is niet gekookt: niets hier raakt `laatstGekooktOp` of het kooklog.
@MainActor
enum Weekmenu {
    // MARK: - Lezen

    static func alle(in kookboek: Kookboek, context: NSManagedObjectContext) -> [Maaltijd] {
        let verzoek = Maaltijd.verzoek()
        verzoek.predicate = NSPredicate(format: "kookboek == %@", kookboek.rawValue)
        verzoek.sortDescriptors = sortering
        return ((try? context.fetch(verzoek)) ?? []).filter { !$0.isDeleted }
    }

    static let sortering = [
        NSSortDescriptor(key: "datum", ascending: true), NSSortDescriptor(key: "aangemaaktOp", ascending: true),
    ]

    /// Als waarde voor `Weekplanning`; zonder uuid of datum (kapotte data) niet.
    static func waarde(_ maaltijd: Maaltijd) -> GeplandeMaaltijd? {
        guard let id = maaltijd.uuid, let datum = maaltijd.datum, !maaltijd.isDeleted else { return nil }
        return GeplandeMaaltijd(
            id: id, dag: datum, receptUUID: maaltijd.receptUUID.flatMap(UUID.init(uuidString:)),
            titel: maaltijd.titel ?? "", porties: Int(maaltijd.porties), notitie: maaltijd.notitie,
            restjesVan: maaltijd.restjesVanUUID.flatMap(UUID.init(uuidString:)),
            aangemaaktOp: maaltijd.aangemaaktOp ?? .distantPast)
    }

    static func waarden(_ maaltijden: [Maaltijd]) -> [GeplandeMaaltijd] { maaltijden.compactMap(waarde) }

    /// De maaltijd van vandaag in een kookboek.
    static func vandaag(
        in kookboek: Kookboek, context: NSManagedObjectContext, nu: Date = .now, kalender: Calendar
    ) -> GeplandeMaaltijd? {
        Weekplanning.vandaag(waarden(alle(in: kookboek, context: context)), nu: nu, kalender: kalender)
    }

    /// Het recept bij een maaltijd: zijn eigen, of bij restjes dat van de bron.
    static func recept(
        bij maaltijd: GeplandeMaaltijd, alle: [GeplandeMaaltijd], context: NSManagedObjectContext
    ) -> Recept? {
        let uuid = maaltijd.receptUUID ?? alle.first { $0.id == maaltijd.restjesVan }?.receptUUID
        return uuid.flatMap { ReceptZoeker.recept(id: $0.uuidString, in: context) }.flatMap {
            $0.isDeleted ? nil : $0
        }
    }

    // MARK: - Wijzigen

    /// Zet een recept op een dag (in het kookboek van het recept, tenzij anders gekozen); wat er
    /// stond verdwijnt. Porties: zoals gekozen, anders die van het recept. Bewaart.
    @discardableResult
    static func plan(
        _ recept: Recept, op dag: Date, porties: Int? = nil, kookboek: Kookboek? = nil,
        context: NSManagedObjectContext, kalender: Calendar
    ) throws -> GeplandeMaaltijd? {
        guard let uuid = recept.uuid else { return nil }
        let nieuw = GeplandeMaaltijd(
            dag: kalender.startOfDay(for: dag), receptUUID: uuid, titel: recept.titelOfStandaard,
            porties: porties ?? Int(recept.porties), aangemaaktOp: .now)
        try werkBij(kookboek ?? recept.kookboekWaarde, context: context) {
            Weekplanning.plan(nieuw, in: $0, kalender: kalender)
        }
        return nieuw
    }

    /// Een vrije notitie op een dag ("Uit eten"). Bewaart.
    static func planNotitie(
        _ tekst: String, op dag: Date, kookboek: Kookboek, context: NSManagedObjectContext, kalender: Calendar
    ) throws {
        let tekst = tekst.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tekst.isEmpty else { return }
        let nieuw = GeplandeMaaltijd(dag: kalender.startOfDay(for: dag), notitie: tekst, aangemaaktOp: .now)
        try werkBij(kookboek, context: context) { Weekplanning.plan(nieuw, in: $0, kalender: kalender) }
    }

    static func wis(_ id: UUID, kookboek: Kookboek, context: NSManagedObjectContext) throws {
        try werkBij(kookboek, context: context) { Weekplanning.wis(id, uit: $0) }
    }

    static func zetPorties(_ porties: Int, voor id: UUID, kookboek: Kookboek, context: NSManagedObjectContext) throws {
        try werkBij(kookboek, context: context) { maaltijden in
            maaltijden.map { maaltijd in
                var maaltijd = maaltijd
                if maaltijd.id == id { maaltijd.porties = min(99, max(1, porties)) }
                return maaltijd
            }
        }
    }

    /// Naar een andere dag; staat daar iets, dan ruilen ze.
    static func verplaats(
        _ id: UUID, naar dag: Date, kookboek: Kookboek, context: NSManagedObjectContext, kalender: Calendar
    ) throws {
        try werkBij(kookboek, context: context) {
            Weekplanning.verplaats(id, naar: dag, in: $0, kalender: kalender)
        }
    }

    /// Kook dubbel; bij `.bezet` verandert er niets (eerst vragen).
    @discardableResult
    static func kookDubbel(
        _ id: UUID, op dag: Date? = nil, vervang: Bool = false, kookboek: Kookboek, context: NSManagedObjectContext,
        kalender: Calendar
    ) throws -> Weekplanning.KookDubbelUitkomst {
        let uitkomst = Weekplanning.kookDubbel(
            id, op: dag, vervang: vervang, in: waarden(alle(in: kookboek, context: context)), kalender: kalender)
        if case .klaar(let nieuw) = uitkomst {
            try werkBij(kookboek, context: context) { _ in nieuw }
        }
        return uitkomst
    }

    /// Bij stoppen met delen of vertrekken: de Thuis-week naar Mijn week. Dagen die in het doel al
    /// bezet zijn, houden wat daar stond. `verwijderBron`: de originelen weg (stoppen) of laten staan
    /// (die verdwijnen met de share).
    static func verplaatsAlles(
        van bron: Kookboek, naar doel: Kookboek, verwijderBron: Bool, context: NSManagedObjectContext
    ) throws {
        let kalender = Weekplanning.kalender()
        let weg = alle(in: bron, context: context)
        let bezet = Set(alle(in: doel, context: context).compactMap { $0.datum.map(kalender.startOfDay) })
        let mee = waarden(weg).filter { !bezet.contains(kalender.startOfDay(for: $0.dag)) }
        if verwijderBron { weg.forEach(context.delete) }
        for waarde in mee {
            let maaltijd = Maaltijd(context: context)
            maaltijd.kookboek = doel.rawValue
            zet(waarde, op: maaltijd)
        }
        try context.bewaarIndienNodig()
    }

    // MARK: - Terugschrijven

    /// Rekent met de waarden van één kookboek en schrijft de uitkomst terug: gewijzigd bijwerken,
    /// verdwenen weg, nieuw erbij. Bewaart.
    static func werkBij(
        _ kookboek: Kookboek, context: NSManagedObjectContext,
        _ wijziging: ([GeplandeMaaltijd]) -> [GeplandeMaaltijd]
    ) throws {
        let objecten = alle(in: kookboek, context: context)
        let nieuw = wijziging(waarden(objecten))
        let perID = Dictionary(nieuw.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var gezien = Set<UUID>()
        for object in objecten {
            guard let id = object.uuid, let waarde = perID[id] else {
                // Zonder uuid of datum (kapotte data) laten staan; wat uit de uitkomst verdween weg.
                if let id = object.uuid, object.datum != nil, perID[id] == nil { context.delete(object) }
                continue
            }
            gezien.insert(id)
            if waarde != Self.waarde(object) { zet(waarde, op: object) }
        }
        for waarde in nieuw where !gezien.contains(waarde.id) {
            let maaltijd = Maaltijd(context: context)
            maaltijd.kookboek = kookboek.rawValue
            zet(waarde, op: maaltijd)
        }
        try context.bewaarIndienNodig()
    }

    private static func zet(_ waarde: GeplandeMaaltijd, op maaltijd: Maaltijd) {
        maaltijd.uuid = waarde.id
        maaltijd.datum = waarde.dag
        maaltijd.receptUUID = waarde.receptUUID?.uuidString
        maaltijd.titel = waarde.titel.isEmpty ? nil : waarde.titel
        maaltijd.porties = Int16(clamping: waarde.porties)
        maaltijd.notitie = waarde.notitie
        maaltijd.restjesVanUUID = waarde.restjesVan?.uuidString
        if waarde.aangemaaktOp != .distantPast { maaltijd.aangemaaktOp = waarde.aangemaaktOp }
    }
}
