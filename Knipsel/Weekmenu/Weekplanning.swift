import Foundation

/// Op welke dag de week begint (Instellingen › Weekmenu). De ruwe waarde is het weekdagnummer van
/// `Calendar` (1 = zondag).
enum Weekbegin: Int, CaseIterable, Identifiable, Sendable {
    case maandag = 2
    case zondag = 1
    case zaterdag = 7

    var id: Int { rawValue }

    var naam: String {
        switch self {
        case .maandag: "Maandag"
        case .zondag: "Zondag"
        case .zaterdag: "Zaterdag"
        }
    }

    static func laad(uit defaults: UserDefaults = .standard) -> Weekbegin {
        Weekbegin(rawValue: defaults.integer(forKey: AppConfiguratie.sleutelWeekBegin)) ?? .maandag
    }
}

/// Een maaltijd in het weekmenu als waarde, los van Core Data: de pure logica (`Weekplanning`)
/// rekent hiermee, `Weekmenu` zet het om.
struct GeplandeMaaltijd: Equatable, Identifiable, Sendable {
    enum Soort: Equatable, Sendable {
        case recept
        case notitie
        case restjes
    }

    var id: UUID
    /// Begin van de dag in de lokale tijd.
    var dag: Date
    var receptUUID: UUID?
    var titel: String
    var porties: Int
    var notitie: String?
    var restjesVan: UUID?
    var aangemaaktOp: Date

    init(
        id: UUID = UUID(), dag: Date, receptUUID: UUID? = nil, titel: String = "", porties: Int = 0,
        notitie: String? = nil, restjesVan: UUID? = nil, aangemaaktOp: Date = .distantPast
    ) {
        self.id = id
        self.dag = dag
        self.receptUUID = receptUUID
        self.titel = titel
        self.porties = porties
        self.notitie = notitie
        self.restjesVan = restjesVan
        self.aangemaaktOp = aangemaaktOp
    }

    var soort: Soort {
        if restjesVan != nil { return .restjes }
        if receptUUID != nil { return .recept }
        return .notitie
    }
}

/// Wat een dag in het weekoverzicht toont.
enum Daginhoud: Equatable {
    case leeg
    /// `verwijderd`: het recept staat niet meer in Knipsel; dan de titel doorgehaald + "kies opnieuw".
    case recept(titel: String, porties: Int, verwijderd: Bool)
    case notitie(String)
    /// Restjes van een eerdere dag ("Restjes van maandag"); `bronDag` nil als die maaltijd weg is.
    case restjes(titel: String, bronDag: Date?)
}

/// De pure rekenregels van het weekmenu (#41): weken en dagen, verplaatsen en ruilen, kook dubbel,
/// de boodschappen voor de rest van de week en "vandaag". Eén avondeten per dag.
enum Weekplanning {
    // MARK: - Kalender

    /// Gregoriaans, Nederlands, met de gekozen eerste dag van de week.
    static func kalender(weekBegin: Weekbegin = .maandag, tijdzone: TimeZone = .current) -> Calendar {
        var kalender = Calendar(identifier: .gregorian)
        kalender.locale = Locale(identifier: "nl_NL")
        kalender.timeZone = tijdzone
        kalender.firstWeekday = weekBegin.rawValue
        kalender.minimumDaysInFirstWeek = 4
        return kalender
    }

    static func dag(_ datum: Date, kalender: Calendar) -> Date { kalender.startOfDay(for: datum) }

    /// Het begin van de week waar `datum` in valt.
    static func weekStart(voor datum: Date, kalender: Calendar) -> Date {
        let dag = kalender.startOfDay(for: datum)
        let weekdag = kalender.component(.weekday, from: dag)
        let terug = (weekdag - kalender.firstWeekday + 7) % 7
        return kalender.date(byAdding: .day, value: -terug, to: dag).map { kalender.startOfDay(for: $0) } ?? dag
    }

    /// De zeven dagen vanaf `start`, elk het begin van die dag (ook rond de zomertijd).
    static func dagen(vanaf start: Date, kalender: Calendar) -> [Date] {
        (0..<7).compactMap { kalender.date(byAdding: .day, value: $0, to: start).map(kalender.startOfDay) }
    }

    /// `aantal` weken verder (of terug, negatief).
    static func week(_ start: Date, verschoven aantal: Int, kalender: Calendar) -> Date {
        kalender.date(byAdding: .day, value: 7 * aantal, to: start).map(kalender.startOfDay) ?? start
    }

    static func volgendeDag(_ dag: Date, kalender: Calendar) -> Date {
        kalender.date(byAdding: .day, value: 1, to: dag).map(kalender.startOfDay) ?? dag
    }

    // MARK: - Lezen

    /// De maaltijd op een dag; bij dubbelen (twee toestellen tegelijk, iCloud) de nieuwste.
    static func maaltijd(op dag: Date, in maaltijden: [GeplandeMaaltijd], kalender: Calendar) -> GeplandeMaaltijd? {
        maaltijden.filter { kalender.isDate($0.dag, inSameDayAs: dag) }
            .max { ($0.aangemaaktOp, $0.id.uuidString) < ($1.aangemaaktOp, $1.id.uuidString) }
    }

    static func vandaag(_ maaltijden: [GeplandeMaaltijd], nu: Date = .now, kalender: Calendar) -> GeplandeMaaltijd? {
        maaltijd(op: nu, in: maaltijden, kalender: kalender)
    }

    static func aantalGepland(_ maaltijden: [GeplandeMaaltijd], dagen: [Date], kalender: Calendar) -> Int {
        dagen.filter { maaltijd(op: $0, in: maaltijden, kalender: kalender) != nil }.count
    }

    /// Wat een dag toont. `bestaat`: staat dit recept (nog) in Knipsel?
    static func inhoud(
        _ maaltijd: GeplandeMaaltijd?, alle: [GeplandeMaaltijd], bestaat: (UUID) -> Bool
    ) -> Daginhoud {
        guard let maaltijd else { return .leeg }
        switch maaltijd.soort {
        case .recept:
            let verwijderd = maaltijd.receptUUID.map { !bestaat($0) } ?? true
            return .recept(titel: maaltijd.titel, porties: maaltijd.porties, verwijderd: verwijderd)
        case .notitie:
            return .notitie(maaltijd.notitie ?? "")
        case .restjes:
            let bron = alle.first { $0.id == maaltijd.restjesVan }
            return .restjes(titel: bron?.titel ?? maaltijd.titel, bronDag: bron?.dag)
        }
    }

    // MARK: - Wijzigen

    /// Zet `nieuw` op zijn dag; wat daar stond verdwijnt (met de restjes ervan).
    static func plan(_ nieuw: GeplandeMaaltijd, in maaltijden: [GeplandeMaaltijd], kalender: Calendar)
        -> [GeplandeMaaltijd]
    {
        var uit = maaltijden
        for bezet in maaltijden where kalender.isDate(bezet.dag, inSameDayAs: nieuw.dag) && bezet.id != nieuw.id {
            uit = wis(bezet.id, uit: uit)
        }
        uit.removeAll { $0.id == nieuw.id }
        uit.append(nieuw)
        return uit
    }

    /// Haalt een maaltijd weg, en de restjes ervan (die hebben zonder bron geen zin).
    static func wis(_ id: UUID, uit maaltijden: [GeplandeMaaltijd]) -> [GeplandeMaaltijd] {
        maaltijden.filter { $0.id != id && $0.restjesVan != id }
    }

    /// Verplaatst een maaltijd naar een andere dag; staat daar al iets, dan ruilen ze van dag.
    static func verplaats(
        _ id: UUID, naar dag: Date, in maaltijden: [GeplandeMaaltijd], kalender: Calendar
    ) -> [GeplandeMaaltijd] {
        guard let bron = maaltijden.first(where: { $0.id == id }) else { return maaltijden }
        let doel = kalender.startOfDay(for: dag)
        guard !kalender.isDate(bron.dag, inSameDayAs: doel) else { return maaltijden }
        let bezet = maaltijd(op: doel, in: maaltijden.filter { $0.id != id }, kalender: kalender)
        return maaltijden.map { maaltijd in
            var maaltijd = maaltijd
            if maaltijd.id == id {
                maaltijd.dag = doel
            } else if maaltijd.id == bezet?.id {
                maaltijd.dag = bron.dag
            }
            return maaltijd
        }
    }

    enum KookDubbelUitkomst: Equatable {
        case klaar([GeplandeMaaltijd])
        /// Op die dag staat al iets: eerst vragen of dat vervangen mag (of een andere dag kiezen).
        case bezet(dag: Date, door: GeplandeMaaltijd)
        /// Alleen een recept kun je dubbel koken.
        case kanNiet
    }

    /// Kook dubbel: de volgende dag (of `dag`) wordt "Restjes van …" met dezelfde porties; op de
    /// boodschappenlijst tellen de porties dan dubbel bij het recept.
    static func kookDubbel(
        _ id: UUID, op dag: Date? = nil, vervang: Bool = false, in maaltijden: [GeplandeMaaltijd],
        nieuweID: UUID = UUID(), nu: Date = .now, kalender: Calendar
    ) -> KookDubbelUitkomst {
        guard let bron = maaltijden.first(where: { $0.id == id }), bron.soort == .recept else { return .kanNiet }
        let doel = dag.map(kalender.startOfDay) ?? volgendeDag(bron.dag, kalender: kalender)
        guard !kalender.isDate(doel, inSameDayAs: bron.dag) else { return .kanNiet }
        if let bezet = maaltijd(op: doel, in: maaltijden, kalender: kalender) {
            if bezet.restjesVan == id { return .klaar(maaltijden) }
            if !vervang { return .bezet(dag: doel, door: bezet) }
        }
        let restjes = GeplandeMaaltijd(
            id: nieuweID, dag: doel, titel: bron.titel, porties: bron.porties, restjesVan: id, aangemaaktOp: nu)
        return .klaar(plan(restjes, in: maaltijden, kalender: kalender))
    }

    // MARK: - Boodschappen

    /// Eén recept voor het boodschappenvel (#40) met het totaal aantal personen.
    struct Boodschappenpaar: Equatable, Sendable {
        let receptUUID: UUID
        let titel: String
        let porties: Int
    }

    /// De recepten van `vanaf` t/m `tot` (hele dagen), elk met zijn porties plus die van zijn
    /// restjes; hetzelfde recept twee keer is één paar. Notities en restjes-dagen zelf leveren
    /// niets op (de restjes zijn al gekookt, ook als de brondag vóór `vanaf` ligt).
    static func boodschappen(
        _ maaltijden: [GeplandeMaaltijd], vanaf: Date, tot: Date, kalender: Calendar
    ) -> [Boodschappenpaar] {
        let begin = kalender.startOfDay(for: vanaf)
        let eind = kalender.startOfDay(for: tot)
        let perDag = Dictionary(grouping: maaltijden) { kalender.startOfDay(for: $0.dag) }
            .compactMapValues { maaltijd(op: $0.first?.dag ?? begin, in: $0, kalender: kalender) }
        let zichtbaar = Array(perDag.values)
        var volgorde: [UUID] = []
        var totaal: [UUID: (titel: String, porties: Int)] = [:]
        for maaltijd in zichtbaar.sorted(by: { $0.dag < $1.dag }) {
            guard maaltijd.soort == .recept, let recept = maaltijd.receptUUID,
                maaltijd.dag >= begin, maaltijd.dag <= eind
            else { continue }
            let restjes = zichtbaar.filter { $0.restjesVan == maaltijd.id }.reduce(0) { $0 + $1.porties }
            if totaal[recept] == nil { volgorde.append(recept) }
            totaal[recept] = (
                totaal[recept]?.titel ?? maaltijd.titel, (totaal[recept]?.porties ?? 0) + maaltijd.porties + restjes
            )
        }
        return volgorde.compactMap { uuid in
            totaal[uuid].map { Boodschappenpaar(receptUUID: uuid, titel: $0.titel, porties: $0.porties) }
        }
    }

    // MARK: - Teksten

    /// "ma", "di" …
    static func afkorting(_ dag: Date, kalender: Calendar) -> String {
        kalender.shortWeekdaySymbols[kalender.component(.weekday, from: dag) - 1]
    }

    /// "maandag" …
    static func dagnaam(_ dag: Date, kalender: Calendar) -> String {
        kalender.weekdaySymbols[kalender.component(.weekday, from: dag) - 1]
    }

    private static func maand(_ dag: Date, kalender: Calendar) -> String {
        kalender.shortMonthSymbols[kalender.component(.month, from: dag) - 1]
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    /// "23 – 29 nov", over een maandgrens "30 nov – 6 dec".
    static func weekTitel(_ start: Date, kalender: Calendar) -> String {
        let eind = dagen(vanaf: start, kalender: kalender).last ?? start
        let d1 = kalender.component(.day, from: start)
        let d2 = kalender.component(.day, from: eind)
        if kalender.isDate(start, equalTo: eind, toGranularity: .month) {
            return "\(d1) – \(d2) \(maand(eind, kalender: kalender))"
        }
        return "\(d1) \(maand(start, kalender: kalender)) – \(d2) \(maand(eind, kalender: kalender))"
    }

    /// "7 dec".
    static func korteDatum(_ dag: Date, kalender: Calendar) -> String {
        "\(kalender.component(.day, from: dag)) \(maand(dag, kalender: kalender))"
    }

    /// "Donderdag 26 nov".
    static func langeDag(_ dag: Date, kalender: Calendar) -> String {
        let naam = dagnaam(dag, kalender: kalender)
        return
            "\(naam.prefix(1).uppercased())\(naam.dropFirst()) \(kalender.component(.day, from: dag)) \(maand(dag, kalender: kalender))"
    }

    /// "5 van 7 gepland"; niets gepland zonder schuldgevoel.
    static func teller(gepland: Int) -> String {
        gepland == 0 ? "Nog niets gepland" : "\(gepland) van 7 gepland"
    }

    /// "Boodschappen voor wo – za" (of één dag: "voor zo").
    static func boodschappenKnop(vanaf: Date, tot: Date, kalender: Calendar) -> String {
        let van = afkorting(vanaf, kalender: kalender)
        if kalender.isDate(vanaf, inSameDayAs: tot) { return "Boodschappen voor \(van)" }
        return "Boodschappen voor \(van) – \(afkorting(tot, kalender: kalender))"
    }

    /// "Restjes van maandag" (zonder brondag: "Restjes").
    static func restjesTitel(bronDag: Date?, kalender: Calendar) -> String {
        bronDag.map { "Restjes van \(dagnaam($0, kalender: kalender))" } ?? "Restjes"
    }

    /// Kort, voor "Vandaag: …" en Siri.
    static func korteTitel(_ maaltijd: GeplandeMaaltijd) -> String {
        switch maaltijd.soort {
        case .recept: maaltijd.titel
        case .notitie: maaltijd.notitie ?? ""
        case .restjes: "Restjes \(maaltijd.titel)"
        }
    }

    /// Wat Siri zegt op "Wat eten we vandaag in Knipsel".
    static func siriVandaag(mijn: String?, thuis: String?) -> String {
        switch (mijn, thuis) {
        case (nil, nil):
            return "Niets gepland voor vandaag."
        case (let mijn?, nil):
            return "Vandaag op het menu: \(mijn)."
        case (nil, let thuis?):
            return "Vandaag op het menu: \(thuis)."
        case (let mijn?, let thuis?):
            if mijn == thuis { return "Vandaag op het menu: \(mijn)." }
            return "Vandaag op je menu: \(mijn). In Thuis: \(thuis)."
        }
    }
}
