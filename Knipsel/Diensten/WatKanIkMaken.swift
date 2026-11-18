import Foundation

/// "Wat kan ik maken?" (#44, schets A): recepten bij wat je in huis hebt, in groepen op hoeveel er
/// nog ontbreekt. Puur en zonder opslag; de weergave en Siri geven de recepten als waarden mee.
enum WatKanIkMaken {
    /// Een ingrediëntregel van een recept, met de groep waar hij in staat ("Voor erbij").
    struct Regel: Equatable, Sendable {
        var invoer: BoodschappenInvoer
        var groep: String?

        init(_ invoer: BoodschappenInvoer, groep: String? = nil) {
            self.invoer = invoer
            self.groep = groep
        }

        /// De naam zoals hij in het recept staat; oude recepten zonder geparste naam via de parser.
        var naam: String {
            if let naam = invoer.naam?.trimmingCharacters(in: .whitespacesAndNewlines), !naam.isEmpty { return naam }
            return IngredientParser.parse(invoer.ruweTekst).naam
        }
    }

    /// Een recept zoals de zoeker het nodig heeft.
    struct Kandidaat: Identifiable, Equatable, Sendable {
        /// Vrij te kiezen; de app gebruikt de objectID-URI.
        let id: String
        let titel: String
        /// Totale tijd, anders de bereidingstijd; 0 = onbekend.
        var minuten: Int = 0
        var laatstGekooktOp: Date?
        var kookboek: Kookboek = .mijn
        var ingredienten: [Regel]
    }

    /// Hoe de resultaten binnen een groep staan. Met precies één ingrediënt ("met prei", C) kies je
    /// tussen snelst en lang niet gekookt.
    enum Sortering: String, CaseIterable, Identifiable, Sendable {
        /// Meeste van je ingrediënten gebruikt, dan de kortste tijd.
        case passend
        case snelst
        case langNietGekookt

        var id: String { rawValue }

        var naam: String {
            switch self {
            case .passend: "Best passend"
            case .snelst: "Snelst"
            case .langNietGekookt: "Lang niet gekookt"
            }
        }
    }

    enum Groep: Int, CaseIterable, Identifiable, Sendable, Comparable {
        case allesInHuis = 0
        case nogEen
        case nogTwee
        case nogMeer

        var id: Int { rawValue }

        init(ontbrekend: Int) {
            self = Groep(rawValue: min(ontbrekend, 3)) ?? .nogMeer
        }

        var titel: String {
            switch self {
            case .allesInHuis: "Alles in huis"
            case .nogEen: "Nog 1 nodig"
            case .nogTwee: "Nog 2 nodig"
            case .nogMeer: "Nog 3 of meer nodig"
            }
        }

        static func < (a: Groep, b: Groep) -> Bool { a.rawValue < b.rawValue }
    }

    /// Een variant: het recept vraagt "rode ui", jij hebt "ui".
    struct Variant: Equatable, Sendable {
        let recept: String
        let inHuis: String

        /// "rode ui ≈ ui".
        var tekst: String { "\(recept) ≈ \(inHuis)" }
    }

    struct Resultaat: Identifiable, Equatable, Sendable {
        let recept: Kandidaat
        /// Namen zoals in het recept: "bladerdeeg".
        let ontbrekend: [String]
        let varianten: [Variant]
        /// Hoeveel van je ingrediënten het recept gebruikt.
        let gebruikt: Int
        /// Wat meetelt (zonder kopjes, naar smaak en optioneel) en daarvan in huis.
        let nodig: Int
        let inHuis: Int
        /// De ingrediënten die nog ontbreken, voor de boodschappenlijst.
        let ontbrekendeInvoer: [BoodschappenInvoer]

        var id: String { recept.id }
        var groep: Groep { Groep(ontbrekend: ontbrekend.count) }

        /// 0…1 voor de kleine meter.
        var aandeel: Double { nodig == 0 ? 1 : Double(inHuis) / Double(nodig) }

        /// "alles in huis" of "mist: bladerdeeg, room".
        var mistTekst: String {
            ontbrekend.isEmpty ? "alles in huis" : "mist: " + ontbrekend.joined(separator: ", ")
        }
    }

    // MARK: - Zoeken

    /// Alle recepten die minstens één van je ingrediënten gebruiken, op volgorde: eerst de groep (minst
    /// ontbrekend), dan de sortering. `ingredienten` zoals je ze intypte ("uien", "oude kaas").
    static func zoek(
        _ ingredienten: [String], in recepten: [Kandidaat], meestalInHuis: MeestalInHuis,
        sortering: Sortering = .passend
    ) -> [Resultaat] {
        let opgegeven = ingredienten.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !opgegeven.isEmpty else { return [] }
        var matcher = IngredientMatcher()
        let chips = opgegeven.map { matcher.begrip($0) }
        var uit: [Resultaat] = []
        for recept in recepten {
            if let resultaat = beoordeel(
                recept, chips: chips, opgegeven: opgegeven, meestalInHuis: meestalInHuis, matcher: &matcher)
            {
                uit.append(resultaat)
            }
        }
        return uit.sorted { volgorde($0, $1, sortering: sortering) }
    }

    /// Per groep, in vaste volgorde; lege groepen ontbreken.
    static func groepen(_ resultaten: [Resultaat]) -> [(groep: Groep, resultaten: [Resultaat])] {
        let perGroep = Dictionary(grouping: resultaten, by: \.groep)
        return Groep.allCases.compactMap { groep in
            guard let lijst = perGroep[groep], !lijst.isEmpty else { return nil }
            return (groep, lijst)
        }
    }

    private static func beoordeel(
        _ recept: Kandidaat, chips: [Begrip], opgegeven: [String], meestalInHuis: MeestalInHuis,
        matcher: inout IngredientMatcher
    ) -> Resultaat? {
        var ontbrekend: [String] = []
        var ontbrekendeInvoer: [BoodschappenInvoer] = []
        var varianten: [Variant] = []
        var gebruikt = Set<Int>()
        var nodig = 0
        var inHuis = 0
        for ingredient in recept.ingredienten {
            let naam = ingredient.naam
            let dekking = matcher.dekking(
                naam: naam, ruweTekst: ingredient.invoer.ruweTekst, toelichting: ingredient.invoer.toelichting,
                groep: ingredient.groep, chips: chips, meestalInHuis: meestalInHuis)
            if let chip = dekking.chip { gebruikt.insert(chip) }
            switch dekking {
            case .telNiet:
                continue
            case .ontbreekt:
                nodig += 1
                let tekst = naam.lowercased()
                if !ontbrekend.contains(tekst) { ontbrekend.append(tekst) }
                ontbrekendeInvoer.append(ingredient.invoer)
            case .bijna(let chip):
                nodig += 1
                inHuis += 1
                let variant = Variant(recept: naam.lowercased(), inHuis: opgegeven[chip])
                if !varianten.contains(variant) { varianten.append(variant) }
            case .aanwezig, .basis:
                nodig += 1
                inHuis += 1
            }
        }
        // Geen van je ingrediënten: niet tonen.
        guard !gebruikt.isEmpty else { return nil }
        return Resultaat(
            recept: recept, ontbrekend: ontbrekend, varianten: varianten, gebruikt: gebruikt.count, nodig: nodig,
            inHuis: inHuis, ontbrekendeInvoer: ontbrekendeInvoer)
    }

    private static func volgorde(_ a: Resultaat, _ b: Resultaat, sortering: Sortering) -> Bool {
        if a.groep != b.groep { return a.groep < b.groep }
        switch sortering {
        case .passend:
            if a.gebruikt != b.gebruikt { return a.gebruikt > b.gebruikt }
            if let tijd = snellerEerst(a, b) { return tijd }
        case .snelst:
            if let tijd = snellerEerst(a, b) { return tijd }
            if a.gebruikt != b.gebruikt { return a.gebruikt > b.gebruikt }
        case .langNietGekookt:
            // Nooit gekookt telt als het langst geleden.
            let da = a.recept.laatstGekooktOp ?? .distantPast
            let db = b.recept.laatstGekooktOp ?? .distantPast
            if da != db { return da < db }
        }
        if a.aandeel != b.aandeel { return a.aandeel > b.aandeel }
        return a.recept.titel.localizedStandardCompare(b.recept.titel) == .orderedAscending
    }

    /// Kortste tijd eerst; onbekende tijd achteraan. `nil` bij gelijk.
    private static func snellerEerst(_ a: Resultaat, _ b: Resultaat) -> Bool? {
        let ta = a.recept.minuten > 0 ? a.recept.minuten : Int.max
        let tb = b.recept.minuten > 0 ? b.recept.minuten : Int.max
        return ta == tb ? nil : ta < tb
    }

    // MARK: - Suggesties

    /// Bekende ingrediënten uit je recepten, het vaakst gebruikte eerst (zonder wat je meestal in huis
    /// hebt): de suggesties onder het invoerveld en voor Siri.
    static func bekendeIngredienten(in recepten: [Kandidaat], meestalInHuis: MeestalInHuis) -> [String] {
        var matcher = IngredientMatcher()
        var tellers: [String: Int] = [:]
        for recept in recepten {
            var inRecept = Set<String>()
            for ingredient in recept.ingredienten {
                let naam = ingredient.naam
                guard !naam.isEmpty,
                    !IngredientMatcher.telNiet(
                        ruweTekst: ingredient.invoer.ruweTekst, toelichting: nil, groep: nil),
                    !meestalInHuis.bevat(naam)
                else { continue }
                for deel in IngredientMatcher.alternatieven(naam).flatMap({ $0 }) {
                    let begrip = matcher.begrip(deel)
                    if begrip.naam.count > 1 { inRecept.insert(begrip.naam) }
                }
            }
            for naam in inRecept { tellers[naam, default: 0] += 1 }
        }
        return tellers.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
    }

    /// Wat je onder het invoerveld ziet bij `getypt`: bekende namen die zo beginnen (of een woord dat zo
    /// begint), niet wat je al hebt; hooguit `aantal`.
    static func suggesties(
        voor getypt: String, bekend: [String], gekozen: [String], aantal: Int = 8
    ) -> [String] {
        let zoek = IngredientParser.vouw(getypt.trimmingCharacters(in: .whitespaces).lowercased())
        var matcher = IngredientMatcher()
        let al = Set(gekozen.map { matcher.begrip($0).naam })
        let kandidaten = bekend.filter { !al.contains($0) }
        guard !zoek.isEmpty else { return Array(kandidaten.prefix(aantal)) }
        let begin = kandidaten.filter { $0.hasPrefix(zoek) }
        let woord = kandidaten.filter { naam in
            !naam.hasPrefix(zoek) && naam.split(separator: " ").contains { $0.hasPrefix(zoek) }
        }
        return Array((begin + woord).prefix(aantal))
    }

    // MARK: - Invoer als chips

    /// Getypte tekst naar chips: komma's (en "en" bij dicteren: "prei, eieren en kaas") scheiden.
    /// Dubbele (ook "uien" naast "ui") vallen weg.
    static func voegToe(_ tekst: String, aan chips: [String]) -> [String] {
        var uit = chips
        var matcher = IngredientMatcher()
        var bekend = Set(chips.map { matcher.begrip($0).naam })
        let delen = tekst.lowercased()
            .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .flatMap { $0.components(separatedBy: " en ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
            .filter { !$0.isEmpty }
        for deel in delen {
            let naam = matcher.begrip(deel).naam
            guard !bekend.contains(naam) else { continue }
            bekend.insert(naam)
            uit.append(deel)
        }
        return uit
    }

    /// Je chips blijven bewaard tot je ze wist, zodat je later verder kunt (alleen op dit toestel). Als
    /// één tekst met een regel per chip, zodat de rij in de bibliotheek ze via `@AppStorage` volgt.
    static func laadChips(uit defaults: UserDefaults = .standard) -> [String] {
        chips(uitTekst: defaults.string(forKey: AppConfiguratie.sleutelWatKanIkMaken) ?? "")
    }

    static func bewaar(_ chips: [String], in defaults: UserDefaults = .standard) {
        if chips.isEmpty {
            defaults.removeObject(forKey: AppConfiguratie.sleutelWatKanIkMaken)
        } else {
            defaults.set(chips.joined(separator: "\n"), forKey: AppConfiguratie.sleutelWatKanIkMaken)
        }
    }

    static func chips(uitTekst tekst: String) -> [String] {
        tekst.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    /// De regel onder de chips: "Zout, peper, olie… tellen als in huis."
    static func basisRegel(_ meestalInHuis: MeestalInHuis) -> String {
        let woorden = meestalInHuis.woorden
        guard !woorden.isEmpty else { return "Wat je meestal in huis hebt, kies je in Instellingen." }
        let getoond = woorden.prefix(3).enumerated().map { $0.offset == 0 ? $0.element.capitalizedEerste : $0.element }
        let rest = woorden.count > 3 ? "…" : ""
        return getoond.joined(separator: ", ") + rest
            + (woorden.count == 1 ? " telt als in huis." : " tellen als in huis.")
    }

    // MARK: - Siri

    /// "Ik vond 4 recepten met prei. Het snelst is Omelet met prei, 20 minuten."
    static func siriAntwoord(ingredient: String, resultaten: [Resultaat]) -> String {
        let naam = ingredient.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !resultaten.isEmpty else { return "Ik vond geen recepten met \(naam) in Knipsel." }
        let aantal = resultaten.count == 1 ? "1 recept" : "\(resultaten.count) recepten"
        let snelste = resultaten.filter { $0.recept.minuten > 0 }.min { a, b in
            a.recept.minuten != b.recept.minuten
                ? a.recept.minuten < b.recept.minuten : volgorde(a, b, sortering: .passend)
        }
        guard let snelste else {
            return "Ik vond \(aantal) met \(naam). Bijvoorbeeld \(resultaten[0].recept.titel)."
        }
        let tijd = Weergave.tijd(minuten: snelste.recept.minuten).map(siriTijd) ?? ""
        if resultaten.count == 1 { return "Ik vond 1 recept met \(naam): \(snelste.recept.titel), \(tijd)." }
        return "Ik vond \(aantal) met \(naam). Het snelst is \(snelste.recept.titel), \(tijd)."
    }

    /// "20 min" → "20 minuten", "1 u 15 min" → "1 uur 15 minuten": voor hardop.
    private static func siriTijd(_ tekst: String) -> String {
        tekst.replacingOccurrences(of: " min", with: " minuten").replacingOccurrences(of: " u", with: " uur")
    }
}

extension String {
    fileprivate var capitalizedEerste: String { prefix(1).uppercased() + dropFirst() }
}
