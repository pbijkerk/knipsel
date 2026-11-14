import Foundation

/// Wat de kok tegen Knipsel zei, als opdracht voor de kookmodus (K8).
enum Commando: Equatable, Sendable {
    case volgende
    case vorige
    case herhaal
    /// Stopt het voorlezen (direct).
    case stop
    /// Voorlezen hervatten, of de stap opnieuw voorlezen.
    case hervat
    case langzamer
    case sneller
    case ingredienten
    /// "Hoeveel bouillon?": de index van het ingrediënt in de lijst, `nil` als het niet in het recept
    /// staat. `gevraagd` is wat de kok noemde ("bouillon").
    case hoeveel(ingredient: Int?, gevraagd: String)
    /// Naar stap `nummer` (1 = stap 1), zoals de kok hem noemt.
    case naarStap(Int)
    case stoppenMetKoken
    /// Een impliciet signaal ("oké", "klaar") dat als volgende telt (B11). `woord` is wat er gezegd werd,
    /// voor de melding "Volgende (oké)".
    case impliciet(String)
}

/// Zet een (deel)transcript om in een `Commando`, of `nil` als het geen commando is. Puur en zonder
/// Speech-framework, zodat elke regel tegen vals alarm te testen is.
///
/// Regels tegen vals alarm (ontwerp §4):
/// - Zonder wekwoord telt alleen een korte uiting (≤ 4 woorden na het weglaten van stopwoordjes als
///   "eh" en "nou") die in zijn geheel een commando is. "Ik pak even de volgende pan erbij" en "stop de
///   ui in de pan" zijn dus geen commando.
/// - "Hoeveel …?" mag wat langer zijn (≤ 7 woorden): "hoeveel boter heb ik nodig".
/// - Met het wekwoord ("Knipsel, …") is de kok duidelijk aan het woord tegen Knipsel: dan mag de zin
///   langer zijn en zoekt de herkenner het commando ín de zin.
struct CommandoHerkenner: Sendable {
    struct Instellingen: Equatable, Sendable {
        /// "Oké", "klaar", "gedaan" = volgende (B11, standaard aan).
        var impliciet = true
        /// Alleen luisteren als de zin met "Knipsel" begint (of eindigt); standaard uit.
        var alleenMetWekwoord = false
    }

    /// Kernwoorden per ingrediënt (index = positie in de lijst), voor "hoeveel …".
    private let ingredientKernen: [[Set<String>]]
    var instellingen: Instellingen

    static let maxWoorden = 4
    static let maxWoordenHoeveel = 7
    static let maxWoordenMetWekwoord = 10

    init(ingredientnamen: [String] = [], instellingen: Instellingen = Instellingen()) {
        ingredientKernen = ingredientnamen.map(Ingredientkoppeling.kernwoorden)
        self.instellingen = instellingen
    }

    /// Het commando in `transcript`, of `nil`.
    func herken(_ transcript: String) -> Commando? {
        var woorden = Self.woorden(transcript)
        let metWekwoord = Self.haalWekwoordWeg(&woorden)
        if instellingen.alleenMetWekwoord && !metWekwoord { return nil }
        woorden.removeAll { Self.stopwoordjes.contains($0) }
        guard !woorden.isEmpty else { return nil }

        if metWekwoord {
            guard woorden.count <= Self.maxWoordenMetWekwoord else { return nil }
            return geheel(woorden) ?? zoekIn(woorden)
        }
        if woorden.first == "hoeveel" {
            guard woorden.count <= Self.maxWoordenHoeveel else { return nil }
            return hoeveel(Array(woorden.dropFirst()))
        }
        guard woorden.count <= Self.maxWoorden else { return nil }
        return geheel(woorden)
    }

    // MARK: - Hele uiting

    /// De hele uiting is een commando: "volgende", "nog een keer", "stap drie", "oké".
    private func geheel(_ woorden: [String]) -> Commando? {
        if let commando = Self.vastCommando(woorden) { return commando }
        if woorden.first == "hoeveel" { return hoeveel(Array(woorden.dropFirst())) }
        if let nummer = Self.stapnummer(woorden) { return .naarStap(nummer) }
        if woorden.allSatisfy(Self.impliciteWoorden.contains) {
            return instellingen.impliciet ? .impliciet(Self.weergave(woorden)) : nil
        }
        // "Oké, volgende" of "ja, stop": een bevestiging vooraf telt niet mee.
        if woorden.count > 1, Self.impliciteWoorden.contains(woorden[0]) {
            let rest = Array(woorden.drop { Self.impliciteWoorden.contains($0) })
            guard !rest.isEmpty else { return nil }
            if let commando = Self.vastCommando(rest) { return commando }
            if let nummer = Self.stapnummer(rest) { return .naarStap(nummer) }
            if rest.first == "hoeveel" { return hoeveel(Array(rest.dropFirst())) }
        }
        return nil
    }

    private static func vastCommando(_ woorden: [String]) -> Commando? {
        zinnen[woorden.joined(separator: " ")]
    }

    // MARK: - Met wekwoord: zoeken in de zin

    /// "Knipsel, wat is de volgende stap": het eerste herkenbare commando in de zin, langste zinsdeel eerst.
    private func zoekIn(_ woorden: [String]) -> Commando? {
        if let start = woorden.firstIndex(of: "hoeveel") {
            return hoeveel(Array(woorden[(start + 1)...]))
        }
        for start in woorden.indices where woorden[start] == "stap" || woorden[start] == "naar" {
            for lengte in stride(from: min(4, woorden.count - start), through: 2, by: -1) {
                if let nummer = Self.stapnummer(Array(woorden[start..<(start + lengte)])) { return .naarStap(nummer) }
            }
        }
        for lengte in stride(from: min(Self.langsteZin, woorden.count), through: 1, by: -1) {
            for start in 0...(woorden.count - lengte) {
                if let commando = Self.vastCommando(Array(woorden[start..<(start + lengte)])) { return commando }
            }
        }
        if instellingen.impliciet, let woord = woorden.first(where: Self.impliciteWoorden.contains) {
            return .impliciet(Self.weergave([woord]))
        }
        return nil
    }

    // MARK: - Hoeveel

    /// "hoeveel [van de] boter [heb ik nodig]": het ingrediënt opzoeken in het recept.
    private func hoeveel(_ rest: [String]) -> Commando? {
        // "van de" ervoor weg; vanaf "heb ik nodig", "moet erin", "gaat erbij" … hoort het niet meer bij
        // de naam.
        let woorden = Array(rest.drop { Self.lidwoorden.contains($0) }.prefix { !Self.hoeveelStaart.contains($0) })
        guard !woorden.isEmpty, !woorden.contains(where: Self.geenIngredient.contains) else { return nil }
        let gevraagd = woorden.joined(separator: " ")
        return .hoeveel(ingredient: ingredient(bij: woorden), gevraagd: gevraagd)
    }

    /// Het best passende ingrediënt, of `nil`. Tolerant voor kleine herkenningsfouten ("boulion").
    func ingredient(bij woorden: [String]) -> Int? {
        var beste: (index: Int, score: Int)?
        for (index, kernen) in ingredientKernen.enumerated() {
            var score = 0
            for woord in woorden where woord.count >= 2 {
                let vormen = Ingredientkoppeling.varianten(woord)
                score += kernen.map { Self.overeenkomst(vormen, $0) }.max() ?? 0
            }
            if score > 0, score > (beste?.score ?? 0) { beste = (index, score) }
        }
        return beste?.index
    }

    /// 3 = zelfde woord, 2 = samenstelling (bouillon ↔ groentebouillon), 1 = bijna (herkenningsfout).
    private static func overeenkomst(_ gevraagd: Set<String>, _ kern: Set<String>) -> Int {
        if !gevraagd.isDisjoint(with: kern) { return 3 }
        var beste = 0
        for g in gevraagd {
            for k in kern {
                let (kort, lang) = g.count <= k.count ? (g, k) : (k, g)
                if kort.count >= 4, lang.count > kort.count, lang.hasSuffix(kort) {
                    beste = max(beste, 2)
                } else if kort.count >= 5, lang.count > kort.count + 2, lang.hasPrefix(kort) {
                    // "kerrie" ↔ "kerriepoeder", "kokos" ↔ "kokosmelk".
                    beste = max(beste, 2)
                } else if isBijna(g, k) {
                    beste = max(beste, 1)
                } else if kort == g, kort.count >= 5, lang.count > kort.count + 2 {
                    // Samenstelling met herkenningsfout: "boulion" ↔ "groentebouillon".
                    let staart = String(lang.suffix(kort.count + 1))
                    if isBijna(kort, staart) || isBijna(kort, String(lang.suffix(kort.count))) {
                        beste = max(beste, 1)
                    }
                }
            }
        }
        return beste
    }

    /// Een of twee letters verschil, afhankelijk van de woordlengte (vanaf 4 letters).
    static func isBijna(_ a: String, _ b: String) -> Bool {
        let kortste = min(a.count, b.count)
        guard kortste >= 4 else { return false }
        let grens = kortste >= 7 ? 2 : 1
        guard abs(a.count - b.count) <= grens else { return false }
        return afstand(a, b) <= grens
    }

    /// Levenshtein-afstand, met verwisseling van twee buurletters als één fout.
    static func afstand(_ a: String, _ b: String) -> Int {
        let x = Array(a)
        let y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var d = Array(repeating: Array(repeating: 0, count: y.count + 1), count: x.count + 1)
        for i in 0...x.count { d[i][0] = i }
        for j in 0...y.count { d[0][j] = j }
        for i in 1...x.count {
            for j in 1...y.count {
                let kosten = x[i - 1] == y[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + kosten)
                if i > 1, j > 1, x[i - 1] == y[j - 2], x[i - 2] == y[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[x.count][y.count]
    }

    // MARK: - Stap n

    /// "stap 3", "stap drie", "ga naar stap drie", "naar stap 3", "de derde stap".
    static func stapnummer(_ woorden: [String]) -> Int? {
        var rest = woorden
        if rest.first == "ga" { rest.removeFirst() }
        if rest.first == "naar" { rest.removeFirst() }
        if rest.first == "de" { rest.removeFirst() }
        if rest.count == 2, rest[0] == "stap", let nummer = getal(rest[1]) { return nummer }
        if rest.count == 3, rest[0] == "stap", rest[1] == "nummer", let nummer = getal(rest[2]) { return nummer }
        if rest.count == 2, rest[1] == "stap", let nummer = rangtelwoorden.firstIndex(of: rest[0]) {
            return nummer + 1
        }
        return nil
    }

    /// "3", "drie", "één" → 3, 3, 1 (één t/m twintig).
    static func getal(_ woord: String) -> Int? {
        if let cijfer = Int(woord), cijfer > 0 { return cijfer }
        if woord == "een" || woord == "1e" { return 1 }
        return telwoorden.firstIndex(of: woord).map { $0 + 1 }
    }

    private static let telwoorden = [
        "een", "twee", "drie", "vier", "vijf", "zes", "zeven", "acht", "negen", "tien", "elf", "twaalf", "dertien",
        "veertien", "vijftien", "zestien", "zeventien", "achttien", "negentien", "twintig",
    ]

    private static let rangtelwoorden = [
        "eerste", "tweede", "derde", "vierde", "vijfde", "zesde", "zevende", "achtste", "negende", "tiende",
    ]

    // MARK: - Woorden

    /// Kleine letters, zonder accenten en leestekens: "Oké, volgende!" → ["oke", "volgende"].
    static func woorden(_ tekst: String) -> [String] {
        let gevouwen = IngredientParser.vouw(tekst)
            .replacingOccurrences(of: "o.k.", with: "ok")
            .replacingOccurrences(of: "o.k", with: "ok")
        return gevouwen.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    /// Haalt "Knipsel" aan het begin of eind weg (ook als de herkenner er "knipsels" of "knipsel" met
    /// één letter verschil van maakt). `true` als het er stond.
    static func haalWekwoordWeg(_ woorden: inout [String]) -> Bool {
        // "Hé Knipsel, volgende": een aanroep ervoor telt niet mee.
        let aanroep = woorden.prefix { aanroepen.contains($0) }.count
        if woorden.count > aanroep, isWekwoord(woorden[aanroep]) {
            woorden.removeFirst(aanroep + 1)
            return true
        }
        if let laatste = woorden.last, isWekwoord(laatste) {
            woorden.removeLast()
            return true
        }
        return false
    }

    static let wekwoord = "knipsel"

    private static let aanroepen: Set<String> = ["he", "hee", "hey", "hoi", "hallo", "ok", "oke"]

    static func isWekwoord(_ woord: String) -> Bool {
        woord == wekwoord || (woord.count >= 6 && woord.count <= 8 && afstand(woord, wekwoord) <= 1)
    }

    /// Alleen "Knipsel" (of "hé Knipsel"): de herkenner maakt van "Knipsel, … volgende" soms twee uitingen.
    static func isAlleenWekwoord(_ tekst: String) -> Bool {
        var woorden = Self.woorden(tekst)
        return haalWekwoordWeg(&woorden) && woorden.allSatisfy(stopwoordjes.contains)
    }

    /// "oke" → "oké" in de melding.
    private static func weergave(_ woorden: [String]) -> String {
        woorden.map { $0 == "oke" ? "oké" : $0 }.joined(separator: " ")
    }

    /// Woordjes die niets toevoegen en niet meetellen voor de lengte.
    static let stopwoordjes: Set<String> = [
        "eh", "ehm", "euh", "uh", "uhm", "hm", "hmm", "mm", "en", "nou", "dan", "maar", "even", "effe", "graag",
        "alsjeblieft", "alsjeblief", "alstublieft", "asjeblieft", "toch", "he", "hee", "oh", "o", "zo", "dus",
    ]

    static let impliciteWoorden: Set<String> = ["oke", "ok", "okay", "okee", "klaar", "gedaan", "ja", "jep", "jawel"]

    private static let lidwoorden: Set<String> = ["de", "het", "van", "aan", "een", "is", "er"]

    /// Wat na "hoeveel ‹ingrediënt›" kan volgen.
    private static let hoeveelStaart: Set<String> = [
        "heb", "ik", "nodig", "moet", "moeten", "er", "erin", "in", "erbij", "bij", "gaat", "gaan", "gebruik",
        "gebruiken", "hebben", "is", "het", "was", "zit", "daarin", "nog", "allemaal", "totaal", "we", "je", "dat",
        "dit", "die", "voor", "op", "om", "wel", "ongeveer",
    ]

    /// "Hoeveel minuten nog?" of "hoeveel stappen" gaat niet over een ingrediënt (timers zijn fase 7).
    private static let geenIngredient: Set<String> = [
        "minuten", "minuut", "tijd", "seconden", "stappen", "stap", "personen", "porties", "uur", "kwartier",
        "kost", "kosten", "duurt", "weegt", "mensen", "eters", "keer", "calorieen", "graden",
    ]

    /// Vaste uitingen → commando.
    private static let zinnen: [String: Commando] = {
        var tabel: [String: Commando] = [:]
        func voeg(_ commando: Commando, _ uitingen: [String]) {
            for uiting in uitingen { tabel[uiting] = commando }
        }
        voeg(
            .volgende,
            [
                "volgende", "volgende stap", "de volgende", "de volgende stap", "verder", "ga verder", "door",
                "door naar de volgende", "naar de volgende stap", "naar de volgende", "volgend", "volgende graag",
                "doorgaan", "next",
            ])
        voeg(
            .vorige,
            [
                "vorige", "vorige stap", "de vorige", "de vorige stap", "terug", "ga terug", "stap terug",
                "een stap terug", "terug naar de vorige", "naar de vorige stap", "ongedaan", "ongedaan maken",
            ])
        voeg(
            .herhaal,
            [
                "herhaal", "herhalen", "herhaal dat", "herhaal de stap", "herhaal deze stap", "herhaal maar",
                "nog een keer", "nog een keertje", "nog eens", "nog 1 keer", "wat zei je", "wat zeg je", "wat zei u",
                "pardon", "zeg het nog eens", "zeg dat nog eens", "kun je dat herhalen",
            ])
        voeg(
            .stop,
            [
                "stop", "stoppen", "stop maar", "stil", "stilte", "wees stil", "pauze", "pauzeer", "hou op", "houd op",
                "hou je mond", "ophouden", "kop dicht",
            ])
        voeg(
            .hervat,
            [
                "lees voor", "lees maar voor", "lees het voor", "lees de stap voor", "voorlezen", "ga door",
                "lees verder", "verder lezen", "verder voorlezen", "hervat", "hervatten", "ga door met lezen",
            ])
        voeg(
            .langzamer,
            [
                "langzamer", "langzaam", "wat langzamer", "iets langzamer", "trager", "rustiger", "praat langzamer",
                "lees langzamer", "langzamer praten", "langzamer lezen",
            ])
        voeg(
            .sneller,
            [
                "sneller", "wat sneller", "iets sneller", "vlugger", "praat sneller", "lees sneller", "sneller praten",
                "sneller lezen",
            ])
        voeg(
            .ingredienten,
            [
                "ingredienten", "de ingredienten", "welke ingredienten", "lees de ingredienten", "wat heb ik nodig",
                "wat moet ik hebben", "wat is er nodig", "wat hebben we nodig", "wat heb ik allemaal nodig",
                "boodschappen",
            ])
        voeg(
            .stoppenMetKoken,
            [
                "stoppen met koken", "klaar met koken", "ik ben klaar met koken", "stop met koken",
                "kookmodus sluiten", "sluit de kookmodus", "kookmodus uit", "sluit kookmodus",
            ])
        return tabel
    }()

    private static let langsteZin = zinnen.keys.map { $0.split(separator: " ").count }.max() ?? 1
}
