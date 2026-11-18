import Foundation

/// Eén ingrediënt teruggebracht tot waar het om gaat (#44, W1): kleine letters zonder accenten,
/// enkelvoud, zonder bijvoeglijke woorden ("verse", "gesnipperde", "oude" bij kaas) en een
/// samenstelling op zijn kopwoord ("preiringen" → prei). `ouders` zijn algemenere begrippen
/// ("rode ui" → ui, "parmezaan" → kaas, "kippendij" → kip), dichtstbijzijnde eerst.
struct Begrip: Equatable, Hashable, Sendable {
    let naam: String
    var ouders: [String] = []
}

/// Hoe een ingrediënt uit een recept zich verhoudt tot wat je in huis hebt.
enum Dekking: Equatable, Sendable {
    /// Een ingrediënt dat je opgaf (index in je ingrediënten); ook als je iets specifiekers hebt
    /// ("rode ui" in huis, het recept vraagt "ui").
    case aanwezig(Int)
    /// Een variant: je hebt iets algemeners of verwants ("ui" in huis, het recept vraagt "rode ui";
    /// "sjalot" ≈ "ui"). Telt als aanwezig, maar wordt getoond (W5: geen valse zekerheid).
    case bijna(Int)
    /// Wat je meestal in huis hebt (#38): telt als aanwezig.
    case basis
    /// Kopje, "naar smaak", "optioneel", "voor erbij": telt niet mee.
    case telNiet
    case ontbreekt

    var isGedekt: Bool {
        switch self {
        case .aanwezig, .bijna, .basis, .telNiet: true
        case .ontbreekt: false
        }
    }

    /// Welk van je ingrediënten dit dekt.
    var chip: Int? {
        switch self {
        case .aanwezig(let index), .bijna(let index): index
        default: nil
        }
    }

    /// Hoe goed: hoger is beter (om tussen alternatieven te kiezen).
    fileprivate var rang: Int {
        switch self {
        case .aanwezig: 5
        case .basis: 4
        case .bijna: 3
        case .telNiet: 2
        case .ontbreekt: 0
        }
    }
}

/// Vergelijkt ingrediëntnamen uit recepten met wat je in huis hebt (#44). Puur en zonder netwerk:
/// een woordenlijst (de 580 ingrediënten uit `Afdelingen`, plus een klein lijstje synoniemen en
/// soorten) en de enkelvoud/meervoud-regels van `Afdelingen` en `Portieschaling`.
///
/// De regel voor varianten: wat je hebt dekt een recept als het hetzelfde is of specifieker
/// ("rode ui" in huis → een recept met "ui" kan). Heb je iets algemeners ("ui" in huis, het recept
/// vraagt "rode ui") of verwants (sjalot ≈ ui, room ≈ kookroom), dan is het *bijna*: het telt als
/// aanwezig, maar het resultaat toont "rode ui ≈ ui". Twee verschillende soorten van hetzelfde
/// (feta en mozzarella) tellen niet.
struct IngredientMatcher {
    private var cache: [String: Begrip] = [:]
    /// Per naam de delen ("peper en zout") als begrip; per deel of het basis is. Eén matcher hoort bij
    /// één `MeestalInHuis` (zoals in `WatKanIkMaken.zoek`).
    private var delenCache: [String: [[String]]] = [:]
    private var basisCache: [String: Bool] = [:]

    init() {}

    // MARK: - Begrip

    /// Het begrip bij een naam ("2 rode uien" mag ook: de parser haalt de hoeveelheid eraf).
    mutating func begrip(_ naam: String) -> Begrip {
        if let bekend = cache[naam] { return bekend }
        let uit = Self.begrip(naam)
        cache[naam] = uit
        return uit
    }

    static func begrip(_ naam: String) -> Begrip {
        var woorden = Afdelingen.woordenIn(naam).filter { !stopwoorden.contains($0) }
        // Een overgebleven hoeveelheid of maat vooraan ("snufje", "stuks").
        while let eerste = woorden.first, woorden.count > 1, maatwoorden.contains(eerste) { woorden.removeFirst() }
        guard !woorden.isEmpty else { return Begrip(naam: IngredientParser.vouw(naam.lowercased())) }
        let enkel = woorden.map(enkelvoud)

        // 1. Woordgroepen uit de woordenlijst, langste eerst: "zoete aardappel", "rode ui", "zure room".
        for lengte in stride(from: min(3, enkel.count), through: 2, by: -1) {
            let groep = enkel.suffix(lengte).joined(separator: " ")
            if Afdelingen.tabel[groep] != nil || gelijk[groep] != nil || vasteOuders[groep] != nil {
                return afgerond(groep, kop: enkel.last ?? groep, groep: true)
            }
        }
        let kop = kopwoord(enkel.last ?? "")
        // 2. Een kleur of "gerookte" vóór het kopwoord is een variant: "rode paprika" → paprika (bijna).
        if enkel.count > 1, let voor = enkel.dropLast().last, variantwoorden.contains(voor) {
            let groep = "\(voor) \(kop)"
            return afgerond(groep, kop: kop, groep: true)
        }
        return afgerond(kop, kop: kop, groep: false)
    }

    /// Synoniemen naar één naam, dan de ouders.
    private static func afgerond(_ naam: String, kop: String, groep: Bool) -> Begrip {
        let naam = gelijk[naam] ?? naam
        var ouders: [String] = []
        func erbij(_ ouder: String) {
            let ouder = gelijk[ouder] ?? ouder
            if ouder != naam, !ouders.contains(ouder) { ouders.append(ouder) }
        }
        vasteOuders[naam].map { $0.forEach(erbij) }
        guard !geenSoortVan.contains(naam) else { return Begrip(naam: naam, ouders: ouders) }
        if groep {
            // "rode ui" is een ui, "witte wijn" een wijn.
            erbij(kop)
        } else if let ouder = samenstellingsOuder(naam) {
            // "cherrytomaat" → tomaat, "zeezout" → zout, "geitenkaas" → kaas.
            erbij(ouder)
        }
        // De ouders van de ouders ("kippendijfilet" → kippendij → kip).
        for ouder in ouders {
            for verder in vasteOuders[ouder] ?? [] { erbij(verder) }
        }
        return Begrip(naam: naam, ouders: ouders)
    }

    // MARK: - Vergelijken

    /// Hoe `recept` gedekt wordt door één ding dat je in huis hebt; `nil` als het er niets mee te maken
    /// heeft.
    static func vergelijk(recept: Begrip, inHuis: Begrip) -> Dekking? {
        if recept.naam == inHuis.naam || inHuis.ouders.contains(recept.naam) { return .aanwezig(0) }
        if recept.ouders.contains(inHuis.naam) { return .bijna(0) }
        if verwant(recept.naam, inHuis.naam) { return .bijna(0) }
        return nil
    }

    static func verwant(_ a: String, _ b: String) -> Bool {
        verwanten.contains { ($0.0 == a && $0.1 == b) || ($0.0 == b && $0.1 == a) }
    }

    /// Hoe een receptingrediënt gedekt wordt door alles wat je in huis hebt (`chips`, al als begrip),
    /// je basis (`meestalInHuis`), of niet. Alternatieven ("boter of olie") tellen als het beste,
    /// delen ("peper en zout") als het slechtste.
    mutating func dekking(
        naam: String, ruweTekst: String, toelichting: String? = nil, groep: String? = nil, chips: [Begrip],
        meestalInHuis: MeestalInHuis
    ) -> Dekking {
        let naam = naam.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !naam.isEmpty else { return .telNiet }
        let delen: [[String]]
        if let bekend = delenCache[naam] {
            delen = bekend
        } else {
            delen = Self.alternatieven(naam)
            delenCache[naam] = delen
        }
        let alternatieven = delen.map { delen in
            delen.map { deel in dekkingVanDeel(deel, chips: chips, meestalInHuis: meestalInHuis) }
                .min { $0.rang < $1.rang } ?? .ontbreekt
        }
        let beste = alternatieven.max { $0.rang < $1.rang } ?? .ontbreekt
        if case .aanwezig = beste { return beste }
        if case .bijna = beste { return beste }
        if Self.telNiet(ruweTekst: ruweTekst, toelichting: toelichting, groep: groep) { return .telNiet }
        return beste
    }

    private mutating func dekkingVanDeel(_ deel: String, chips: [Begrip], meestalInHuis: MeestalInHuis)
        -> Dekking
    {
        let begrip = begrip(deel)
        var bijna: Int?
        for (index, chip) in chips.enumerated() {
            switch Self.vergelijk(recept: begrip, inHuis: chip) {
            case .aanwezig?: return .aanwezig(index)
            case .bijna?: if bijna == nil { bijna = index }
            default: break
            }
        }
        let isBasis: Bool
        if let bekend = basisCache[deel] {
            isBasis = bekend
        } else {
            isBasis = meestalInHuis.bevat(deel)
            basisCache[deel] = isBasis
        }
        if isBasis { return .basis }
        if let bijna { return .bijna(bijna) }
        return .ontbreekt
    }

    /// "boter of olie" → [[boter], [olie]]; "peper en zout" → [[peper, zout]]. Woordgroepen met "en"
    /// uit de woordenlijst ("kant en klaar deeg") blijven heel.
    static func alternatieven(_ naam: String) -> [[String]] {
        let klein = naam.lowercased()
        let gevouwen = Afdelingen.woordenIn(klein).joined(separator: " ")
        if heleGroepen.contains(where: { gevouwen.contains($0) }) { return [[klein]] }
        return
            klein
            .components(separatedBy: " of ").flatMap { $0.components(separatedBy: "/") }
            .map { alternatief in
                alternatief.components(separatedBy: " en ").flatMap { $0.components(separatedBy: " & ") }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
                    .filter { !$0.isEmpty }
            }
            .filter { !$0.isEmpty }
    }

    /// Naar smaak, optioneel, eventueel, voor erbij of om te garneren: telt niet als ontbrekend. Ook een
    /// kopje ("Voor de saus:") of een groep "Voor erbij".
    static func telNiet(ruweTekst: String, toelichting: String?, groep: String?) -> Bool {
        let regel = IngredientParser.zonderOpsommingsteken(ruweTekst)
        if !regel.isEmpty, IngredientParser.groepskop(regel) != nil || IngredientParser.isKopje(regel) { return true }
        let tekst = IngredientParser.vouw([regel, toelichting ?? ""].joined(separator: " ").lowercased())
        if nietNodig.contains(where: { tekst.contains($0) }) { return true }
        if tekst.range(of: #"\bevt\b"#, options: .regularExpression) != nil { return true }
        let kop = IngredientParser.vouw((groep ?? "").lowercased())
        return !kop.isEmpty && nietNodigGroep.contains { kop.contains($0) }
    }

    // MARK: - Woorden

    /// Het enkelvoud dat Knipsel kent: "uien" → ui, "tomaatjes" → tomaat, "eieren" → ei.
    static func enkelvoud(_ woord: String) -> String {
        if isBekend(woord) { return woord }
        let vormen = Afdelingen.enkelvouden(woord)
        if let bekend = vormen.dropFirst().first(where: isBekend) { return bekend }
        // Verkleinwoord: "tomaatjes", "uitjes", "krieltjes".
        for uitgang in ["tjes", "jes", "tje", "je"] where woord.hasSuffix(uitgang) && woord.count >= uitgang.count + 2 {
            let stam = String(woord.dropLast(uitgang.count))
            if isBekend(stam) { return stam }
            if let bekend = Afdelingen.enkelvouden(stam).first(where: isBekend) { return bekend }
        }
        let geteld = IngredientParser.vouw(Portieschaling.getal(woord, voor: 1))
        return geteld
    }

    private static func isBekend(_ woord: String) -> Bool {
        Afdelingen.tabel[woord] != nil || gelijk[woord] != nil || vasteOuders[woord] != nil
    }

    /// Een samenstelling die niet in de woordenlijst staat naar wat hij is: op het eerste deel als het
    /// achterste deel een vorm is ("preiringen" → prei, "kipfiletreepjes" → kipfilet, "citroensap" →
    /// citroen); anders blijft hij zoals hij is (en krijgt hij misschien een ouder op het kopwoord).
    static func kopwoord(_ woord: String) -> String {
        guard !isBekend(woord), !woord.isEmpty else { return woord }
        if samenstellingsOuder(woord) != nil { return woord }
        for sleutel in voorvoegsels where woord.count > sleutel.count && woord.hasPrefix(sleutel) {
            return gelijk[sleutel] ?? sleutel
        }
        return woord
    }

    /// Het langste bekende kopwoord achteraan ("zeezout" → zout); niet voor wat er alleen op lijkt
    /// (aardappel is geen appel).
    static func samenstellingsOuder(_ woord: String) -> String? {
        guard !geenSoortVan.contains(woord) else { return nil }
        return achtervoegsels.first { woord.count > $0.count && woord.hasSuffix($0) }
    }

    /// Enkele woorden uit de woordenlijst als kopwoord, langste eerst; korte die te veel vangen niet.
    private static let achtervoegsels: [String] = Set(
        Afdelingen.tabel.keys.filter { !$0.contains(" ") && $0.count >= 3 }
            + vasteOuders.keys.filter {
                !$0.contains(" ") && $0.count >= 3
            }
    )
    .subtracting(["sap", "spa", "mie", "port", "drop", "ijs", "pit"])
    .sorted { $0.count != $1.count ? $0.count > $1.count : $0 < $1 }

    /// Waar een samenstelling mee kan beginnen ("prei"ringen), langste eerst.
    private static let voorvoegsels: [String] = Set(
        Afdelingen.tabel.keys.filter { !$0.contains(" ") && $0.count >= 4 } + ["uien", "kippen"]
    )
    .sorted { $0.count != $1.count ? $0.count > $1.count : $0 < $1 }

    /// Woorden die niets zeggen over wat het ís: bereiding, maat, versheid, rijpheid, en "oude/jonge"
    /// bij kaas.
    static let stopwoorden: Set<String> = Set([
        "vers", "verse", "gesnipperd", "gesnipperde", "fijngesnipperde", "gehakte", "fijngehakte", "grofgehakte",
        "geraspt", "geraspte", "fijngeraspte", "gemalen", "gedroogd", "gedroogde", "groot", "grote", "klein",
        "kleine", "middelgrote", "flinke", "ruime", "hele", "heel", "rijp", "rijpe", "stevige",
        "koud", "koude", "zacht", "zachte", "gesmolten", "gekookt", "gekookte", "ongekookte", "gepeld", "gepelde",
        "ontdooid", "ontdooide", "biologisch", "biologische", "bio", "oud", "oude", "jong", "jonge", "belegen",
        "extra", "overjarige", "mager", "magere", "vol", "volle", "losse", "dunne", "dikke", "fijne", "grove",
        "platte", "in", "uit", "van", "de", "het", "een", "stukjes", "stukje", "blokjes", "plakjes", "reepjes",
        "schijfjes", "partjes", "ca", "circa", "ongeveer", "evt", "eventueel", "naar", "smaak", "wat", "beetje",
        "paar", "bevroren", "ontpit", "ontpitte", "geschild", "geschilde", "gewassen", "uitgelekt", "uitgelekte",
        "gehalveerd", "gehalveerde", "zoute", "ongezouten", "gezouten", "goede", "lekkere", "milde", "pittige",
        "grofgemalen", "versgemalen", "fijngemalen", "kleingesneden", "gesneden", "geplukt", "geplukte",
        "uitgeperst", "uitgeperste", "geroosterde", "geroosterd", "gegrilde", "gebakken", "verse", "blik",
    ])

    /// Telwoorden die soms in de naam blijven staan ("stuks prei").
    private static let maatwoorden: Set<String> = Set([
        "stuk", "stuks", "snufje", "snuf", "scheutje", "handje", "handvol", "bosje", "bos", "takje", "takjes",
        "blaadje", "blaadjes", "teen", "teentje", "tenen", "teentjes", "zakje", "pakje", "potje", "plak", "plakje",
    ])

    /// Een woord dat een variant maakt van het kopwoord: "rode ui" is een ui, maar niet zomaar dezelfde.
    static let variantwoorden: Set<String> = Set([
        "rode", "rood", "gele", "geel", "groene", "groen", "witte", "wit", "zwarte", "zwart", "oranje", "paarse",
        "bruine", "gerookte", "gerookt",
    ])

    /// Andere schrijfwijzen of namen voor hetzelfde: telt als gelijk.
    static let gelijk: [String: String] = Dictionary(
        [
            ("slagroom", "room"), ("peen", "wortel"), ("winterpeen", "wortel"), ("waspeen", "wortel"),
            ("roomboter", "boter"), ("knoflookteen", "knoflook"), ("knoflookteentje", "knoflook"),
            ("parmezaanse kaas", "parmezaan"), ("parmigiano", "parmezaan"), ("parmigiano reggiano", "parmezaan"),
            ("bosui", "lente ui"), ("lenteui", "lente ui"), ("eidooier", "ei"), ("eigeel", "ei"), ("eiwit", "ei"),
            ("dooier", "ei"), ("bouillonblokje", "bouillon"), ("bouillontablet", "bouillon"), ("spekje", "spek"),
            ("spekblokje", "spek"), ("aardappelen", "aardappel"), ("krieltje", "kriel"), ("zwarte peper", "peper"),
            ("vleestomaat", "tomaat"), ("spaanse peper", "rode peper"), ("chilipeper", "rode peper"),
            ("crème fraîche", "creme fraiche"), ("citroenrasp", "citroen"), ("limoenrasp", "limoen"),
            ("citroensap", "citroen"), ("limoensap", "limoen"),
        ], uniquingKeysWith: { eerste, _ in eerste })

    /// Soorten van iets algemeners die niet uit de naam blijken ("parmezaan" is kaas).
    static let vasteOuders: [String: [String]] = {
        var tabel: [String: [String]] = [:]
        func soort(_ woorden: [String], van ouder: String) {
            for woord in woorden where woord != ouder { tabel[woord, default: []].append(ouder) }
        }
        // Kaassoorten uit de woordenlijst, behalve wat je niet als kaas gebruikt.
        // Zachte en verse kazen vervangen geen "kaas" (oude kaas is geen feta).
        let geenKaas: Set<String> = [
            "roomkaas", "ricotta", "cottage cheese", "huttenkase", "kaas", "feta", "mozzarella", "buffelmozzarella",
            "burrata", "mascarpone", "halloumi", "paneer", "labneh", "geitenkaas", "stracchino", "kwark",
        ]
        let kazen = Afdelingen.woordenlijst.first { $0.0 == .kaas }?.1.map {
            Afdelingen.woordenIn($0).joined(separator: " ")
        }
        soort((kazen ?? []).filter { !geenKaas.contains($0) && !$0.hasSuffix(" kaas") }, van: "kaas")
        soort(
            [
                "kipfilet", "kippendij", "kippendijfilet", "kippenpoot", "kippenbout", "drumstick", "kippenvleugel",
                "kipdij", "kipdijfilet", "soepkip", "kippenborst",
            ], van: "kip")
        soort(["kippendijfilet", "kipdijfilet"], van: "kippendij")
        soort(
            [
                "spaghetti", "penne", "macaroni", "fusilli", "tagliatelle", "linguine", "rigatoni", "farfalle",
                "orzo", "lasagneblad", "lasagne", "pappardelle", "conchiglie", "spaghettini", "tortellini",
                "ravioli", "verse pasta",
            ], van: "pasta")
        soort(["kriel", "krieltje", "vastkokende aardappel", "kruimige aardappel"], van: "aardappel")
        soort(["kookroom", "zure room", "plantaardige room"], van: "room")
        soort(["half om half", "rundergehakt", "varkensgehakt", "kipgehakt", "lamsgehakt"], van: "gehakt")
        soort(["bacon", "ontbijtspek", "pancetta"], van: "spek")
        soort(["zalmfilet"], van: "zalm")
        soort(["kabeljauwfilet"], van: "kabeljauw")
        soort(["lente ui", "zilverui", "zilveruitje"], van: "ui")
        soort(["griekse yoghurt", "volle yoghurt"], van: "yoghurt")
        return tabel
    }()

    /// Verwant zonder dat het ene een soort van het andere is: telt als bijna, beide kanten op.
    static let verwanten: [(String, String)] = [
        ("sjalot", "ui"), ("rode ui", "sjalot"), ("creme fraiche", "zure room"), ("room", "kookroom"),
        ("citroen", "limoen"), ("bacon", "spek"), ("parmezaan", "pecorino"), ("parmezaan", "grana padano"),
        ("peterselie", "koriander"), ("boter", "margarine"), ("kipfilet", "kippendij"),
    ]

    /// Lijkt een soort, is het niet: zoete aardappel is geen aardappel, rode peper geen peper uit de
    /// molen, en een aardappel geen appel.
    static let geenSoortVan: Set<String> = Set([
        "zoete aardappel", "rode peper", "groene peper", "cayennepeper", "lange vinger", "aardappel",
        "sinaasappel", "granaatappel", "pindakaas", "roomkaas", "geitenkaas", "kokosmelk", "kokosroom", "karnemelk",
        "kikkererwt", "jeneverbes", "paneermeel", "amandelmeel", "zuiveringszout", "kokosnoot", "nootmuskaat",
        "rozenwater", "kokoswater", "bruiswater", "hamburger", "pindasaus", "vanillesuiker", "bloemkool",
        "boerenkool", "spruitkool", "kant en klaar deeg", "tomatenpuree", "appelstroop", "pompoenpit",
        "kippenbouillon", "runderbouillon", "groentebouillon", "kokosrasp", "maizena", "zeewier",
        "bataat", "waterkers", "sperzieboon", "snijboon", "tuinboon", "witlof", "oesterzwam", "erwtenscheut",
    ])

    /// Woordgroepen met "en" die één ingrediënt zijn.
    private static let heleGroepen = ["kant en klaar", "half om half"]

    /// Tekst in de regel of toelichting waardoor een ingrediënt niet nodig is.
    private static let nietNodig = [
        "naar smaak", "optioneel", "eventueel", "naar keuze", "voor erbij", "om te serveren", "ter garnering",
        "om te garneren", "om in te vetten", "voor het invetten", "om te bestuiven", "als je wilt", "indien gewenst",
    ]

    /// Een groep ("Voor erbij", "Garnering") waarvan niets nodig is.
    private static let nietNodigGroep = ["erbij", "serveren", "garner", "optioneel", "eventueel", "naar keuze"]
}
