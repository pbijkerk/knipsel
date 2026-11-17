import Foundation

/// Afdeling in de supermarkt, in de volgorde waarin je er doorheen loopt (#39). Een Nederlandse
/// supermarkt begint met groente en fruit en eindigt bij de dranken; Overig staat altijd achteraan.
enum Afdeling: String, CaseIterable, Identifiable, Sendable, Codable {
    case groenteFruit = "groente"
    case brood
    case vleesVis = "vlees"
    case zuivel
    case kaas
    case koeling
    case diepvries
    case houdbaar
    case kruiden
    case bakken
    case ontbijt
    case snoep
    case dranken
    case overig

    var id: String { rawValue }

    var naam: String {
        switch self {
        case .groenteFruit: "Groente & fruit"
        case .brood: "Brood & bakkerij"
        case .vleesVis: "Vlees & vis"
        case .zuivel: "Zuivel & eieren"
        case .kaas: "Kaas"
        case .koeling: "Koeling & vleeswaren"
        case .diepvries: "Diepvries"
        case .houdbaar: "Houdbaar"
        case .kruiden: "Kruiden & specerijen"
        case .bakken: "Bakken"
        case .ontbijt: "Ontbijt"
        case .snoep: "Snoep & koek"
        case .dranken: "Dranken"
        case .overig: "Overig"
        }
    }

    var symbool: String {
        switch self {
        case .groenteFruit: "carrot"
        case .brood: "birthday.cake"
        case .vleesVis: "fish"
        case .zuivel: "drop"
        case .kaas: "triangle"
        case .koeling: "refrigerator"
        case .diepvries: "snowflake"
        case .houdbaar: "shippingbox"
        case .kruiden: "leaf"
        case .bakken: "frying.pan"
        case .ontbijt: "sunrise"
        case .snoep: "gift"
        case .dranken: "wineglass"
        case .overig: "basket"
        }
    }

    /// Plek in de winkel: 0 = Groente & fruit.
    var plek: Int { Self.allCases.firstIndex(of: self) ?? Self.allCases.count }

    /// Een lege of onbekende waarde telt als Overig.
    init(veld: String?) {
        self = veld.flatMap(Afdeling.init(rawValue:)) ?? .overig
    }
}

/// Bij welke afdeling een ingrediënt hoort, uit een vaste woordenlijst (puur, geen netwerk).
/// Meervoud en enkelvoud tellen gelijk ("uien" = "ui"), net als samenstellingen: op het kopwoord
/// ("zonnebloemolie" → olie) en anders op het eerste deel ("preiringen" → prei).
enum Afdelingen {
    /// De afdeling uit de woordenlijst, of `nil` als het woord onbekend is.
    static func uitWoordenlijst(_ naam: String) -> Afdeling? {
        let woorden = woordenIn(naam)
        guard !woorden.isEmpty else { return nil }
        let kandidaten = woorden.map(enkelvouden)

        // 1. Woordgroepen, langste eerst en van achteren: "zure room", "rode peper", "witte bonen".
        if woorden.count > 1 {
            for lengte in stride(from: woorden.count, through: 2, by: -1) {
                for begin in stride(from: woorden.count - lengte, through: 0, by: -1) {
                    let deel = begin..<(begin + lengte)
                    let letterlijk = woorden[deel].joined(separator: " ")
                    if let afdeling = tabel[letterlijk] { return afdeling }
                    let enkelvoud = kandidaten[deel].map { $0.first ?? "" }
                    for variant in varianten(kandidaten[deel].map { $0 }) where variant != enkelvoud {
                        if let afdeling = tabel[variant.joined(separator: " ")] { return afdeling }
                    }
                    if let afdeling = tabel[enkelvoud.joined(separator: " ")] { return afdeling }
                }
            }
        }
        // 2. Losse woorden, van achteren (het kopwoord staat achteraan: "verse gember").
        for opties in kandidaten.reversed() {
            for woord in opties {
                if let afdeling = tabel[woord] { return afdeling }
            }
        }
        // 3. Samenstelling op het kopwoord: "zeezout" → zout, "soepkip" → kip.
        for opties in kandidaten.reversed() {
            if let afdeling = langste(in: opties, past: { $0.count > $1.count && $0.hasSuffix($1) }, minimaal: 3) {
                return afdeling
            }
        }
        // 4. Samenstelling op het eerste deel: "preiringen" → prei, "kipfiletreepjes" → kipfilet.
        for opties in kandidaten.reversed() {
            if let afdeling = langste(in: opties, past: { $0.count > $1.count && $0.hasPrefix($1) }, minimaal: 4) {
                return afdeling
            }
        }
        return nil
    }

    /// Een eenheid die op een blik wijst: groente daaruit staat bij Houdbaar.
    static func isBlik(_ eenheid: String?) -> Bool {
        guard let eenheid = eenheid?.lowercased() else { return false }
        return ["blik", "blikken", "blikje", "blikjes"].contains(eenheid)
    }

    /// De afdeling zonder geheugen: woordenlijst, anders Overig.
    static func afdeling(voor naam: String) -> Afdeling { uitWoordenlijst(naam) ?? .overig }

    // MARK: - Woorden

    /// Kleine letters, zonder accenten, alleen letters; losse letters (de "s" van "paprika's") vallen weg.
    static func woordenIn(_ naam: String) -> [String] {
        IngredientParser.vouw(naam.lowercased())
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count > 1 }
    }

    /// Het woord zelf en mogelijke enkelvouden: "tomaten" → tomaat, "sjalotten" → sjalot, "eieren" → ei,
    /// "druiven" → druif, "linzen" → linze, "wortels" → wortel.
    static func enkelvouden(_ woord: String) -> [String] {
        var uit = [woord]
        func erbij(_ vorm: String) {
            if vorm.count > 1, !uit.contains(vorm) { uit.append(vorm) }
        }
        erbij(IngredientParser.vouw(Portieschaling.getal(woord, voor: 1)))
        if woord.hasSuffix("eren") { erbij(String(woord.dropLast(4))) }
        if woord.hasSuffix("en"), woord.count > 4 {
            let stam = String(woord.dropLast(2))
            erbij(stam)
            erbij(stam + "e")
            if let laatste = stam.last, let voorlaatste = stam.dropLast().last, laatste == voorlaatste {
                erbij(String(stam.dropLast()))
            }
            if stam.hasSuffix("v") { erbij(String(stam.dropLast()) + "f") }
            if stam.hasSuffix("z") { erbij(String(stam.dropLast()) + "s") }
            // "tomat" → tomaat, "bon" → boon, "peultjes" niet.
            let klinkers: Set<Character> = ["a", "e", "o", "u"]
            let tekens = Array(stam)
            if tekens.count >= 2, klinkers.contains(tekens[tekens.count - 2]),
                !klinkers.contains(tekens[tekens.count - 1]),
                tekens.count < 3 || !klinkers.contains(tekens[tekens.count - 3])
            {
                var langer = tekens
                langer.insert(tekens[tekens.count - 2], at: tekens.count - 1)
                erbij(String(langer))
            }
        }
        if woord.hasSuffix("s"), woord.count > 3 { erbij(String(woord.dropLast())) }
        return uit
    }

    /// Alle combinaties van enkelvoudsvormen voor een woordgroep (kort: hooguit een paar woorden).
    private static func varianten(_ opties: [[String]]) -> [[String]] {
        opties.reduce([[]]) { reeksen, vormen in
            reeksen.flatMap { reeks in vormen.prefix(4).map { reeks + [$0] } }
        }
    }

    private static func langste(
        in opties: [String], past: (String, String) -> Bool, minimaal: Int
    ) -> Afdeling? {
        var beste: (lengte: Int, afdeling: Afdeling)?
        for woord in opties {
            for (sleutel, afdeling) in enkeleWoorden where sleutel.count >= minimaal && past(woord, sleutel) {
                if sleutel.count > (beste?.lengte ?? 0) { beste = (sleutel.count, afdeling) }
            }
        }
        return beste?.afdeling
    }

    /// Opzoektabel: gevouwen woord(groep) → afdeling.
    static let tabel: [String: Afdeling] = {
        var tabel: [String: Afdeling] = [:]
        for (afdeling, woorden) in woordenlijst {
            for woord in woorden { tabel[woordenIn(woord).joined(separator: " ")] = afdeling }
        }
        return tabel
    }()

    private static let enkeleWoorden: [(String, Afdeling)] = tabel.filter { !$0.key.contains(" ") }.map {
        ($0.key, $0.value)
    }

    /// Woorden die in meer dan één afdeling staan (moet leeg zijn; getest).
    static var dubbeleWoorden: [String] {
        var gezien: [String: Int] = [:]
        for (_, woorden) in woordenlijst {
            for woord in woorden { gezien[woordenIn(woord).joined(separator: " "), default: 0] += 1 }
        }
        return gezien.filter { $0.value > 1 }.map(\.key).sorted()
    }

    static var aantalWoorden: Int { tabel.count }

    // MARK: - De woordenlijst

    /// Enkelvoud, zoals je het in een recept ziet. Woordgroepen alleen waar ze iets anders betekenen dan
    /// het kopwoord ("rode peper" is groente, "peper" een specerij).
    static let woordenlijst: [(Afdeling, [String])] = [
        (
            .groenteFruit,
            [
                "ui", "rode ui", "sjalot", "knoflook", "knoflookteen", "prei", "wortel", "winterpeen", "peen",
                "aardappel", "kriel", "krieltje", "zoete aardappel", "bataat", "pompoen", "flespompoen", "butternut",
                "courgette", "aubergine", "paprika", "puntpaprika", "tomaat", "cherrytomaat", "trostomaat",
                "romatomaat", "komkommer", "sla", "ijsbergsla", "kropsla", "rucola", "veldsla", "spinazie",
                "andijvie", "boerenkool", "spitskool", "witte kool", "rode kool", "savooiekool", "bloemkool",
                "broccoli", "broccolini", "spruitje", "sperzieboon", "snijboon", "tuinboon", "peultje", "sugarsnap",
                "maiskolf", "champignon", "kastanjechampignon", "paddenstoel", "oesterzwam", "shiitake",
                "portobello", "venkel", "selderij", "bleekselderij", "knolselderij", "pastinaak", "raap", "koolraap",
                "radijs", "biet", "rode biet", "asperge", "artisjok", "avocado", "gember", "citroengras",
                "rode peper", "groene peper", "chilipeper", "spaanse peper", "lente ui", "bosui", "tauge",
                "paksoi", "chinese kool", "witlof", "rabarber", "appel", "peer", "banaan", "sinaasappel",
                "mandarijn", "citroen", "limoen", "grapefruit", "druif", "aardbei", "framboos", "blauwe bes", "bes",
                "braam", "kers", "pruim", "perzik", "nectarine", "abrikoos", "mango", "ananas", "kiwi", "meloen",
                "watermeloen", "granaatappel", "vijg", "passievrucht", "peterselie", "koriander", "basilicum",
                "munt", "dille", "bieslook", "rozemarijn", "tijm", "salie", "dragon", "kervel", "groente",
                "fruit", "kool", "erwtenscheut", "jalapeno",
            ]
        ),
        (
            .brood,
            [
                "brood", "stokbrood", "ciabatta", "pistolet", "bolletje", "broodje", "pita", "pitabroodje", "wrap",
                "tortilla", "naan", "naanbrood", "focaccia", "croissant", "krentenbol", "zuurdesembrood",
                "volkorenbrood", "brioche", "bagel", "turks brood", "hamburgerbroodje",
            ]
        ),
        (
            .vleesVis,
            [
                "kip", "kipfilet", "kippendij", "kippendijfilet", "kippenpoot", "kippenbout", "drumstick",
                "gehakt", "rundergehakt", "half om half", "varkensgehakt", "biefstuk", "entrecote", "ribeye",
                "runderlap", "sukadelap", "riblap", "stoofvlees", "rundvlees", "varkensvlees", "varkenshaas",
                "varkensfilet", "karbonade", "speklap", "procureur", "lamsvlees", "lamsrack", "lamskotelet",
                "lamsbout", "kalfsvlees", "eendenborst", "kalkoen", "kalkoenfilet", "worst", "braadworst",
                "chipolata", "saucijs", "slavink", "hamburger", "shoarma", "zalm", "zalmfilet", "gerookte zalm",
                "kabeljauw", "koolvis", "tilapia", "pangasius", "makreel", "haring", "garnaal", "gamba", "mossel",
                "inktvis", "sint jakobsschelp", "scampi", "vis", "visfilet", "schelvis", "zeebaars", "dorade",
                "forel", "schol", "kreeft", "krab", "vlees", "ossenhaas", "spareribs",
            ]
        ),
        (
            .zuivel,
            [
                "melk", "volle melk", "halfvolle melk", "karnemelk", "yoghurt", "griekse yoghurt", "kwark", "vla",
                "room", "slagroom", "kookroom", "zure room", "creme fraiche", "boter", "roomboter", "margarine",
                "ei", "eidooier", "eigeel", "eiwit", "havermelk", "sojamelk", "amandelmelk", "skyr", "kefir",
                "mascarpone", "plantaardige room",
            ]
        ),
        (
            .kaas,
            [
                "kaas", "jonge kaas", "belegen kaas", "oude kaas", "geraspte kaas", "parmezaan", "parmezaanse kaas",
                "parmigiano", "pecorino", "grana padano", "mozzarella", "buffelmozzarella", "burrata", "feta",
                "geitenkaas", "brie", "camembert", "gorgonzola", "roquefort", "blauwe kaas", "cheddar", "gruyere",
                "emmentaler", "comte", "manchego", "halloumi", "ricotta", "roomkaas", "cottage cheese",
                "huttenkase", "raclettekaas", "gouda", "edammer", "taleggio",
            ]
        ),
        (
            .koeling,
            [
                "ham", "achterham", "rauwe ham", "serranoham", "parmaham", "prosciutto", "spek", "spekje",
                "ontbijtspek", "bacon", "pancetta", "chorizo", "salami", "rookworst", "tofu", "tempeh", "falafel",
                "hummus", "verse pasta", "gnocchi", "pizzadeeg", "filodeeg", "yufka", "tortellini", "ravioli",
                "vegetarisch gehakt", "vegaburger", "zuurkool", "tzatziki", "guacamole", "kruidenboter",
                "deeg", "kant en klaar deeg",
            ]
        ),
        (
            .diepvries,
            [
                "doperwt", "erwt", "diepvriesspinazie", "edamame", "diepvriesgroente", "bladerdeeg", "ijs",
                "roomijs", "ijsblokje", "diepvriesfruit", "frites", "patat", "visstick", "tuinerwt", "diepvries",
                "bevroren fruit", "bevroren erwt", "roerbakgroente",
            ]
        ),
        (
            .houdbaar,
            [
                "pasta", "spaghetti", "penne", "macaroni", "fusilli", "tagliatelle", "lasagne", "lasagneblad",
                "linguine", "orzo", "rigatoni", "farfalle", "noedel", "mie", "rijstnoedel", "udon", "rijst",
                "basmatirijst", "risottorijst", "arborio", "zilvervliesrijst", "sushirijst", "couscous", "bulgur",
                "quinoa", "parelcouscous", "gierst", "polenta", "linze", "rode linze", "kikkererwt", "kidneyboon",
                "witte boon", "zwarte boon", "bruine boon", "kapucijner", "spliterwt", "tomatenblokje",
                "gepelde tomaat", "tomatenpuree", "passata", "tomatensaus", "kokosmelk", "kokosroom", "bouillon",
                "bouillonblokje", "groentebouillon", "kippenbouillon", "runderbouillon", "fond", "olie",
                "olijfolie", "zonnebloemolie", "sesamolie", "arachideolie", "azijn", "wijnazijn", "balsamico",
                "balsamicoazijn", "appelazijn", "rijstazijn", "sojasaus", "ketjap", "vissaus", "oestersaus",
                "sambal", "sriracha", "mosterd", "mayonaise", "ketchup", "tahin", "currypasta", "harissa",
                "kappertje", "olijf", "augurk", "zongedroogde tomaat", "tonijn", "mais", "ansjovis", "walnoot",
                "pecannoot", "hazelnoot", "cashewnoot", "pinda", "amandel", "pijnboompit", "pistache",
                "zonnebloempit", "pompoenpit", "sesamzaad", "chiazaad", "lijnzaad", "rozijn", "krent", "dadel",
                "cranberry", "paneermeel", "panko", "pesto", "pastasaus", "mirin", "worcestersaus", "tabasco",
                "nori", "zeewier", "noot", "kokosnoot", "gedroogde abrikoos", "wijnsteenazijn", "tomaat uit blik",
                "bonen in tomatensaus", "sushi azijn",
            ]
        ),
        (
            .kruiden,
            [
                "zout", "zeezout", "peper", "zwarte peper", "witte peper", "paprikapoeder", "gerookte paprikapoeder",
                "komijn", "komijnzaad", "kurkuma", "kerrie", "kerriepoeder", "garam masala", "kaneel",
                "nootmuskaat", "kruidnagel", "kardemom", "steranijs", "laurier", "laurierblad", "oregano",
                "gedroogde tijm", "gedroogde oregano", "chilivlok", "cayennepeper", "chilipoeder", "korianderzaad",
                "venkelzaad", "mosterdzaad", "saffraan", "ras el hanout", "zaatar", "sumak", "italiaanse kruiden",
                "provencaalse kruiden", "knoflookpoeder", "uienpoeder", "gemberpoeder", "piment", "jeneverbes",
                "fenegriek", "vijfkruidenpoeder", "dukkah", "kerrieblad", "tandoori", "specerij", "kruidenmix",
                "gedroogde kruiden",
            ]
        ),
        (
            .bakken,
            [
                "bloem", "tarwebloem", "patentbloem", "zelfrijzend bakmeel", "volkorenmeel", "speltmeel", "maizena",
                "suiker", "kristalsuiker", "basterdsuiker", "poedersuiker", "rietsuiker", "bruine suiker",
                "vanillesuiker", "gist", "droge gist", "bakpoeder", "baksoda", "zuiveringszout", "cacao",
                "cacaopoeder", "chocolade", "pure chocolade", "chocoladestukje", "vanille", "vanillestokje",
                "vanille extract", "amandelmeel", "kokosrasp", "gelatine", "agar", "marsepein", "meel",
                "bakmeel", "lange vinger",
            ]
        ),
        (
            .ontbijt,
            [
                "havermout", "muesli", "granola", "cornflakes", "ontbijtgranen", "pindakaas", "jam", "hagelslag",
                "honing", "stroop", "appelstroop", "beschuit", "ontbijtkoek", "chocopasta", "cracker", "rijstwafel",
                "cruesli", "ahornsiroop", "agavesiroop",
            ]
        ),
        (
            .snoep,
            [
                "chips", "tortillachips", "nacho", "koek", "koekje", "biscuit", "speculaas", "stroopwafel", "snoep",
                "drop", "popcorn", "amaretti", "toastje", "borrelnoot",
            ]
        ),
        (
            .dranken,
            [
                "water", "bruiswater", "spa", "wijn", "rode wijn", "witte wijn", "port", "sherry", "bier", "cider",
                "cognac", "rum", "wodka", "likeur", "amaretto", "frisdrank", "cola", "tonic", "sap",
                "sinaasappelsap", "appelsap", "koffie", "espresso", "thee", "limonade", "prosecco", "champagne",
                "marsala", "vermout", "ginger beer", "kokoswater",
            ]
        ),
    ]
}
