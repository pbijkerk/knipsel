import Foundation

/// Knipt lopende bereidingstekst in stappen (#17). Puur en op het toestel. De tekst blijft
/// letterlijk (K2): de splitser kiest alleen waar een stap begint, altijd aan het begin van een zin.
///
/// Zinsgrenzen: een punt, uitroepteken of vraagteken gevolgd door een hoofdletter, behalve na een
/// afkorting ("ca.", "bijv.", "o.a.") of voorletter; "180 °C." en "10 min." sluiten wel een zin af.
/// Mist de punt (vaak aan het eind van een herkende regel) en volgt een kookwerkwoord met een
/// hoofdletter ("… los de suiker op" / "Doe de peren …"), dan is dat ook een zinsgrens.
///
/// Een nieuwe stap begint bij
/// - een nieuwe alinea (of een nieuw blok op de foto) na een afgesloten zin;
/// - een kopje als "Voor de saus:" (het kopje hoort bij de stap eronder);
/// - een signaalwoord: intussen, ondertussen, daarna, vervolgens, tot slot, ten slotte, als laatste,
///   serveer; ook "Verwarm de oven …" is altijd een eigen stap;
/// - een handeling: een zin die met een bevelend kookwerkwoord begint ("Snijd …", "Voeg … toe") of,
///   in de stijl van sommige bladen, op een kookwerkwoord in de onbepaalde wijs eindigt
///   ("Ui pellen en snipperen.").
///
/// Groeperen: een handeling blijft bij de vorige stap als hij kort is (< `korteZin` tekens) en de
/// stap dan niet langer wordt dan `doelLengte` tekens of `maxZinnen` zinnen. Opdienen ("… vlak voor
/// het serveren …") begint altijd een nieuwe stap. Een afmaakzin
/// ("Breng op smaak …", "Bestrooi met …", "Garneer met …") blijft bij de vorige stap tot
/// `maxAfmaak` tekens. Een beschrijvende zin ("Het deeg moet glanzen.") hoort altijd bij de vorige;
/// een stap met alleen een inleidende zin krijgt de volgende zin er altijd bij.
enum StapSplitser {
    /// Een stap van ongeveer 1–3 zinnen (Mayer 2009: segmenteren; Ganier 2004: één actie per stap).
    static let doelLengte = 280
    /// Een kortere handeling ("Fruit de ui 3 min.") mag bij de vorige stap blijven.
    static let korteZin = 60
    /// Een korte handeling voegt zich alleen bij een stap van één zin: "Schil de peren. Neem een
    /// pannetje." wel, een derde korte handeling niet (Peters proef met "Peren in rode wijn").
    static let maxZinnen = 2
    /// Een afmaakzin blijft bij de vorige stap, tenzij die daarmee erg lang wordt.
    static let maxAfmaak = 400

    /// Een stuk brontekst: een herkende regel of een alinea.
    struct Stuk: Equatable, Sendable {
        var tekst: String
        /// Regelnummer in de herkenning, voor de uitsnede en de twijfel.
        var regel: Int? = nil
        var laagVertrouwen = false
        /// Begint een nieuwe alinea of een nieuw blok op de foto.
        var nieuweAlinea = false
    }

    struct Stap: Equatable, Sendable {
        var tekst: String
        /// Indices van de stukken waar deze stap (deels) uit komt. Een stap die halverwege een regel
        /// begint, deelt die regel met de vorige stap.
        var stukken: [Int]
    }

    // MARK: - Indelen

    /// De stappen volgens de regels hierboven.
    static func stappen(_ stukken: [Stuk]) -> [Stap] {
        let bron = Bron(stukken)
        return maak(groepeer(zinnen(bron), in: bron.tekens), bron)
    }

    /// Voor een bestaand recept: de stappen als tekst, één per alinea, opnieuw ingedeeld.
    static func stappen(in tekst: String) -> [String] {
        stappen(alineas(tekst)).map(\.tekst)
    }

    /// Knipt de letterlijke tekst op de beginwoorden van elke stap, zoals een taalmodel die geeft.
    /// Hoofdletters, accenten, leestekens en afbreekstreepjes tellen niet mee. `nil` als een begin
    /// niet (op volgorde) te vinden is of de stappen samen niet precies de bron zijn.
    static func knip(_ stukken: [Stuk], opBeginnen beginnen: [String]) -> [Stap]? {
        let bron = Bron(stukken)
        guard !beginnen.isEmpty, !bron.tekens.isEmpty else { return nil }
        let zinsbegins = zinnen(bron).map(\.bereik.lowerBound)
        let genormaliseerd = Genormaliseerd(bron.tekens)
        var sneden: [Int] = []
        for begin in beginnen {
            let vanaf = (sneden.last ?? -1) + 1
            guard let plek = genormaliseerd.zoek(begin, vanaf: vanaf, voorkeur: zinsbegins) else { return nil }
            sneden.append(sneden.isEmpty ? 0 : plek)
        }
        var bereiken: [Range<Int>] = []
        for (n, snede) in sneden.enumerated() {
            let eind = n + 1 < sneden.count ? sneden[n + 1] : bron.tekens.count
            guard let bereik = zonderWitruimte(snede..<eind, in: bron.tekens) else { return nil }
            bereiken.append(bereik)
        }
        let stappen = maak(bereiken, bron)
        guard isLetterlijk(stappen.map(\.tekst), bron: String(bron.tekens)) else { return nil }
        return stappen
    }

    static func knip(_ tekst: String, opBeginnen beginnen: [String]) -> [String]? {
        knip(alineas(tekst), opBeginnen: beginnen)?.map(\.tekst)
    }

    /// Stappen voor het controlescherm: op de beginwoorden van het taalmodel als die kloppen,
    /// anders met de regels. Twijfel en regelnummers gaan mee per stap.
    static func conceptStappen(_ stukken: [Stuk], beginnen: [String] = []) -> [ConceptRegel] {
        let stappen = (beginnen.isEmpty ? nil : knip(stukken, opBeginnen: beginnen)) ?? stappen(stukken)
        return stappen.map { stap in
            ConceptRegel(
                tekst: stap.tekst, laagVertrouwen: stap.stukken.contains { stukken[$0].laagVertrouwen },
                regels: stap.stukken.compactMap { stukken[$0].regel })
        }
    }

    // MARK: - Letterlijk

    /// Zijn de stappen samen woord voor woord de bron? Witruimte telt niet; een afgebroken woord
    /// wordt heel zoals bij `ReceptOpbouw.plak`.
    static func isLetterlijk(_ stappen: [String], bron: String) -> Bool {
        witruimte(ReceptOpbouw.plak(stappen)) == witruimte(bron)
    }

    static func isLetterlijk(_ stappen: [String], bron stukken: [Stuk]) -> Bool {
        isLetterlijk(stappen, bron: String(Bron(stukken).tekens))
    }

    private static func witruimte(_ tekst: String) -> String {
        tekst.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: - Zinnen (voor "Splits hier")

    /// De zinnen van een stap, letterlijk en op volgorde.
    static func zinnen(in tekst: String) -> [String] {
        let bron = Bron([Stuk(tekst: tekst)])
        return zinnen(bron).map { String(bron.tekens[$0.bereik]) }
    }

    /// Splitst een stap vóór zin `index` (1 = vóór de tweede zin). `nil` als dat niet kan.
    static func splits(_ tekst: String, voorZin index: Int) -> (String, String)? {
        let bron = Bron([Stuk(tekst: tekst)])
        let zinnen = zinnen(bron)
        guard index > 0, index < zinnen.count else { return nil }
        let snede = zinnen[index].bereik.lowerBound
        guard let eerste = zonderWitruimte(0..<snede, in: bron.tekens),
            let tweede = zonderWitruimte(snede..<bron.tekens.count, in: bron.tekens)
        else { return nil }
        return (String(bron.tekens[eerste]), String(bron.tekens[tweede]))
    }

    // MARK: - Bron

    /// De stukken aan elkaar zoals `ReceptOpbouw.plak`, met per stuk waar het staat.
    struct Bron {
        var tekens: [Character] = []
        /// Per stuk zijn plek in `tekens` (leeg voor een leeg stuk).
        var bereik: [Range<Int>] = []
        /// Plekken waar een nieuwe alinea begint.
        var alineas: Set<Int> = []
        /// Einde van een losse kopregel zonder dubbele punt ("Voor de saus").
        var kopEinden: Set<Int> = []

        init(_ stukken: [Stuk]) {
            for stuk in stukken {
                let deel = Array(stuk.tekst.trimmingCharacters(in: .whitespacesAndNewlines))
                guard let eerste = deel.first else {
                    bereik.append(tekens.count..<tekens.count)
                    continue
                }
                let begin: Int
                if tekens.last == "-", eerste.isLowercase, tekens.count >= 2, tekens[tekens.count - 2].isLetter {
                    // Afgebroken woord ("groente-" + "bouillon"): weer heel.
                    tekens.removeLast()
                    if let vorige = bereik.lastIndex(where: { !$0.isEmpty }) {
                        bereik[vorige] = bereik[vorige].lowerBound..<tekens.count
                    }
                    begin = tekens.count
                } else {
                    if !tekens.isEmpty { tekens.append(" ") }
                    begin = tekens.count
                    if stuk.nieuweAlinea { alineas.insert(begin) }
                }
                tekens += deel
                bereik.append(begin..<tekens.count)
                if StapSplitser.isLosKopje(String(deel)) { kopEinden.insert(tekens.count) }
            }
        }
    }

    private static func alineas(_ tekst: String) -> [Stuk] {
        ReceptInvoer.regels(tekst).map { Stuk(tekst: $0, nieuweAlinea: true) }
    }

    private static func maak(_ bereiken: [Range<Int>], _ bron: Bron) -> [Stap] {
        bereiken.map { bereik in
            Stap(
                tekst: String(bron.tekens[bereik]),
                stukken: bron.bereik.indices.filter { !bron.bereik[$0].isEmpty && bron.bereik[$0].overlaps(bereik) })
        }
    }

    private static func zonderWitruimte(_ bereik: Range<Int>, in tekens: [Character]) -> Range<Int>? {
        var begin = bereik.lowerBound
        var eind = bereik.upperBound
        while begin < eind, tekens[begin].isWhitespace { begin += 1 }
        while eind > begin, tekens[eind - 1].isWhitespace { eind -= 1 }
        return begin < eind ? begin..<eind : nil
    }

    // MARK: - Zinsgrenzen

    struct Zin: Equatable {
        var bereik: Range<Int>
        var isKopje = false
        var isAlinea = false
    }

    private static let afsluiters: Set<Character> = [".", "!", "?", "…"]
    private static let naAfsluiter: Set<Character> = [".", "!", "?", "…", ")", "\"", "'", "”", "’", "»"]
    private static let openers: Set<Character> = ["\"", "'", "‘", "“", "(", "„", "«"]

    /// Afkortingen die nooit een zin afsluiten. Eenheden ("min.", "gr.", "el.") wel: na
    /// "Bak 10 min. Laat afkoelen." begint een nieuwe zin; vóór een kleine letter nooit.
    private static let afkortingen: Set<String> = [
        "ca", "bijv", "bv", "b.v", "evt", "resp", "incl", "excl", "ong", "nl", "vgl", "zgn", "max", "gem",
        "mr", "dhr", "mevr", "nr", "o.a", "m.b.v", "d.w.z", "i.p.v", "m.u.v", "z.s.m", "t.z.t", "a.u.b", "e.d",
        "o.i.d", "e.a", "t.o.v", "i.c.m",
    ]

    static func zinnen(_ bron: Bron) -> [Zin] {
        let t = bron.tekens
        var zinnen: [Zin] = []
        var begin = 0
        while begin < t.count, t[begin].isWhitespace { begin += 1 }
        var i = begin
        while i < t.count {
            var einde: Int?
            var kop = false
            if afsluiters.contains(t[i]) {
                var j = i + 1
                while j < t.count, naAfsluiter.contains(t[j]) { j += 1 }
                if j < t.count, t[j].isWhitespace, t[i] != "." || !isAfkorting(t, punt: i) { einde = j }
            } else if t[i] == ":", i + 1 < t.count, t[i + 1].isWhitespace, isKoptekst(t[begin..<i]) {
                einde = i + 1
                kop = true
            } else if bron.kopEinden.contains(i + 1), i + 1 < t.count {
                einde = i + 1
                kop = true
            } else if t[i].isLetter, i + 2 < t.count, t[i + 1].isWhitespace, t[i + 2].isUppercase,
                bevelen.contains(woord(in: t, vanaf: i + 2))
            {
                // De punt viel weg bij het herkennen: "… los de suiker op" + "Doe de peren …". Midden
                // in een zin staat een kookwerkwoord nooit met een hoofdletter.
                einde = i + 1
            }
            if let einde {
                var volgende = einde
                while volgende < t.count, t[volgende].isWhitespace { volgende += 1 }
                if volgende < t.count, begintZin(t, volgende) {
                    zinnen.append(Zin(bereik: begin..<einde, isKopje: kop, isAlinea: bron.alineas.contains(begin)))
                    begin = volgende
                    i = volgende
                    continue
                }
            }
            i += 1
        }
        var eind = t.count
        while eind > begin, t[eind - 1].isWhitespace { eind -= 1 }
        if begin < eind {
            zinnen.append(Zin(bereik: begin..<eind, isAlinea: bron.alineas.contains(begin)))
        }
        return zinnen
    }

    private static func woord(in t: [Character], vanaf k: Int) -> String {
        var eind = k
        while eind < t.count, t[eind].isLetter { eind += 1 }
        return String(t[k..<eind]).lowercased()
    }

    private static func begintZin(_ t: [Character], _ k: Int) -> Bool {
        if t[k].isUppercase { return true }
        return openers.contains(t[k]) && k + 1 < t.count && t[k + 1].isUppercase
    }

    /// Is de punt op `punt` het eind van een afkorting ("ca.", "o.a.", een voorletter)?
    private static func isAfkorting(_ t: [Character], punt: Int) -> Bool {
        var begin = punt
        while begin > 0, t[begin - 1].isLetter || t[begin - 1] == "." { begin -= 1 }
        let woord = String(t[begin..<punt])
        guard !woord.isEmpty else { return false }
        if woord.count == 1, woord.first!.isUppercase {
            // Een voorletter ("J. Oliver"), maar niet "200 °C." of "180 C."
            guard begin == 0 || t[begin - 1].isWhitespace else { return false }
            var vorige = begin - 1
            while vorige >= 0, t[vorige].isWhitespace { vorige -= 1 }
            return vorige < 0 || !t[vorige].isNumber
        }
        return afkortingen.contains(woord.lowercased())
    }

    /// "Voor de saus", "Tip", "Saus": kort, geen cijfers, geen zin.
    private static func isKoptekst(_ tekst: ArraySlice<Character>) -> Bool {
        let woorden = String(tekst).split(whereSeparator: \.isWhitespace)
        return !woorden.isEmpty && woorden.count <= 5
            && !tekst.contains(where: { $0.isNumber || afsluiters.contains($0) || $0 == "," })
    }

    /// Een losse regel als "Voor de saus" (zonder dubbele punt) is een kopje.
    static func isLosKopje(_ regel: String) -> Bool {
        guard let laatste = regel.last, !afsluiters.contains(laatste), laatste != ":" else { return false }
        let woorden = regel.split(whereSeparator: \.isWhitespace)
        return woorden.count <= 5 && !regel.contains(where: \.isNumber)
            && regel.range(of: #"^voor (de|het|een) "#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    // MARK: - Groeperen

    static func groepeer(_ zinnen: [Zin], in t: [Character]) -> [Range<Int>] {
        var stappen: [Range<Int>] = []
        var huidig: Range<Int>?
        var aantal = 0
        var vorigeIsKop = false
        var heeftHandeling = false
        for zin in zinnen {
            let tekst = String(t[zin.bereik])
            if let stap = huidig {
                let samen = zin.bereik.upperBound - stap.lowerBound
                let nieuw: Bool
                if vorigeIsKop {
                    nieuw = false
                } else if zin.isAlinea || zin.isKopje {
                    nieuw = true
                } else if !heeftHandeling {
                    // Een inleidende zin ("Het geheim zit in het geduld.") is geen eigen stap.
                    nieuw = false
                } else if isSignaal(tekst) {
                    nieuw = true
                } else if isAfmaakzin(tekst) {
                    nieuw = samen > maxAfmaak
                } else if isHandeling(tekst) {
                    nieuw = !(tekst.count < korteZin && samen <= doelLengte && aantal < maxZinnen)
                } else {
                    nieuw = false
                }
                if nieuw {
                    stappen.append(stap)
                    huidig = zin.bereik
                    aantal = 0
                    heeftHandeling = false
                } else {
                    huidig = stap.lowerBound..<zin.bereik.upperBound
                }
            } else {
                huidig = zin.bereik
            }
            if !zin.isKopje { aantal += 1 }
            if isHandeling(tekst) || isSignaal(tekst) { heeftHandeling = true }
            vorigeIsKop = zin.isKopje
        }
        if let huidig { stappen.append(huidig) }
        return stappen
    }

    // MARK: - Woorden

    private static func woorden(_ zin: String) -> [String] {
        zin.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
    }

    static func isSignaal(_ zin: String) -> Bool {
        let w = woorden(zin)
        guard let eerste = w.first else { return false }
        if ["intussen", "ondertussen", "daarna", "vervolgens", "tenslotte", "serveer"].contains(eerste) { return true }
        if w.contains(where: { ["serveren", "opdienen", "uitserveren"].contains($0) }) && !w.contains("tot") {
            return true
        }
        let twee = w.prefix(2).joined(separator: " ")
        if ["tot slot", "ten slotte", "als laatste", "tot besluit"].contains(twee) { return true }
        // De oven aanzetten is altijd een eigen stap.
        let drie = w.prefix(3).joined(separator: " ")
        return ["verwarm de oven", "verwarm de grill", "zet de oven", "oven voorverwarmen"].contains(where: {
            drie.hasPrefix($0)
        })
    }

    static func isAfmaakzin(_ zin: String) -> Bool {
        let w = woorden(zin)
        guard let eerste = w.first else { return false }
        let tekst = w.joined(separator: " ")
        if eerste == "breng" && tekst.contains("op smaak") { return true }
        if ["bestrooi", "garneer", "bestuif", "besprenkel", "bedruppel"].contains(eerste) { return true }
        return tekst.hasPrefix("maak af") || tekst.hasPrefix("proef en") || tekst.hasPrefix("proef of")
    }

    /// Een zin die een handeling is: begint met een bevelend kookwerkwoord, of eindigt op een
    /// kookwerkwoord in de onbepaalde wijs zonder hulpwerkwoord ("Ui pellen en snipperen.").
    static func isHandeling(_ zin: String) -> Bool {
        let w = woorden(zin)
        guard let eerste = w.first, let laatste = w.last else { return false }
        if bevelen.contains(eerste) { return true }
        return infinitieven.contains(laatste) && !w.contains(where: hulpwerkwoorden.contains)
    }

    /// Strenger dan `isHandeling`, om in een column het begin van de bereiding te vinden: een
    /// bevelend werkwoord vooraan en geen ik, je, we ("Laat ik eerlijk zijn", "Kook je …") of
    /// verhalende woorden ("mijn", "ons").
    static func isGebiedend(_ zin: String) -> Bool {
        let w = woorden(zin)
        guard let eerste = w.first, bevelen.contains(eerste), eerste != "was" else { return false }
        if w.count > 1, ["ik", "je", "jij", "we", "wij", "u", "hij", "men"].contains(w[1]) { return false }
        return !w.contains(where: { ["ik", "mijn", "me", "mij", "we", "wij", "ons", "onze"].contains($0) })
    }

    private static let hulpwerkwoorden: Set<String> = [
        "mag", "moet", "kan", "kunt", "kun", "mogen", "moeten", "kunnen", "zal", "zult", "wil", "wilt", "gaat",
        "is", "zijn", "wordt", "worden", "blijft", "hoeft", "hoeven", "begint", "lijkt",
    ]

    /// Bevelende kookwerkwoorden aan het begin van een zin (ook van scheidbare werkwoorden:
    /// "Voeg … toe", "Dek … af"). Alleen woorden die aan het begin van een zin geen zelfstandig
    /// naamwoord of lidwoord zijn.
    static let bevelen: Set<String> = [
        "verwarm", "verhit", "snijd", "snij", "hak", "snipper", "pel", "schil", "rasp", "pers", "week", "spoel",
        "was", "dep", "droog", "kneed", "rol", "vorm", "bestrijk", "fruit", "smoor", "stoof", "blancheer", "gril",
        "grill", "rooster", "bak", "braad", "kook", "pocheer", "stoom", "frituur", "sudder", "laat", "neem",
        "maak", "houd", "hou", "doe", "leg", "zet", "haal", "breng", "voeg", "schenk", "giet", "roer", "meng",
        "vermeng", "klop", "schep", "strooi", "bestrooi", "garneer", "serveer", "proef", "dek", "verdeel",
        "pureer", "mix", "blend", "zeef", "druppel", "besprenkel", "sprenkel", "bedruppel", "beleg", "vul",
        "bedek", "wikkel", "rijg", "prik", "steek", "kerf", "trancheer", "plet", "kneus", "maal", "stamp",
        "wrijf", "smelt", "verwijder", "halveer", "ontpit", "ontdooi", "marineer", "kruid", "bestuif", "paneer",
        "wentel", "keer", "draai", "schud", "spatel", "vouw", "spuit", "druk", "pak", "plaats", "schuif",
        "gebruik", "bewaar", "koel", "warm", "lepel", "reduceer", "bind", "verdun", "verkruimel", "kruimel",
        "brokkel", "trek", "scheur", "pluk", "ris", "ontvel", "fileer", "karamelliseer", "flambeer",
        "gratineer", "glaceer", "schaaf", "smeer", "besmeer", "vet", "bebloem", "bekleed", "overgiet", "schik",
        "stapel", "knip", "hussel", "controleer", "zorg", "begin", "herhaal", "ga", "wacht", "passeer",
        "dien", "presenteer", "vries", "rits", "blus", "veeg", "pof", "gaar", "brand",
        "dresseer", "portioneer", "prak", "roerbak", "wok", "los",
    ]

    /// Kookwerkwoorden in de onbepaalde wijs, voor recepten in de stijl "Ui pellen en snipperen."
    static let infinitieven: Set<String> = [
        "verwarmen", "voorverwarmen", "verhitten", "snijden", "hakken", "fijnhakken", "snipperen", "pellen",
        "schillen", "raspen", "persen", "uitpersen", "weken", "spoelen", "afspoelen", "wassen", "deppen",
        "droogdeppen", "drogen", "kneden", "rollen", "uitrollen", "vormen", "bestrijken", "fruiten", "smoren",
        "stoven", "blancheren", "grillen", "roosteren", "bakken", "aanbakken", "opbakken", "braden", "aanbraden",
        "koken", "pocheren", "stomen", "frituren", "sudderen", "toevoegen", "schenken", "gieten", "afgieten",
        "roeren", "doorroeren", "omroeren", "mengen", "vermengen", "kloppen", "loskloppen", "opkloppen",
        "stijfkloppen", "scheppen", "omscheppen", "strooien", "bestrooien", "garneren", "serveren", "opdienen",
        "proeven", "afdekken", "verdelen", "pureren", "mixen", "zeven", "uitlekken", "smelten", "afkoelen",
        "opwarmen", "verwijderen", "halveren", "marineren", "kruiden", "paneren", "keren", "omkeren", "draaien",
        "vouwen", "spuiten", "plaatsen", "inkoken", "rusten", "trekken", "schikken", "beleggen", "vullen",
        "bedekken", "insmeren", "invetten", "bekleden", "besprenkelen", "afblussen", "blussen", "glaceren",
        "gratineren", "karamelliseren", "afmaken", "afsnijden", "schoonmaken", "ontpitten", "ontdooien",
        "garen", "laten", "leggen", "zetten", "doen", "halen", "brengen", "afbakken", "opstijven",
        "opzetten", "aanzetten", "fijnsnijden", "pruttelen", "fijnsnipperen", "roerbakken", "prakken", "doorkoken",
        "meebakken", "meekoken", "opdrogen", "uitsnijden", "inwrijven",
    ]
}

// MARK: - Zoeken op beginwoorden

/// De bron met alleen letters en cijfers, zonder hoofdletters en accenten, met per teken de plek
/// in de bron. Zo vindt "voeg de groentebouillon" ook "Voeg de groente-bouillon".
private struct Genormaliseerd {
    let tekens: [Character]
    let plek: [Int]
    let woordbegin: Set<Int>

    init(_ bron: [Character]) {
        var tekens: [Character] = []
        var plek: [Int] = []
        var woordbegin = Set<Int>()
        for (index, teken) in bron.enumerated() where teken.isLetter || teken.isNumber {
            if index == 0 || !(bron[index - 1].isLetter || bron[index - 1].isNumber) { woordbegin.insert(index) }
            for gevouwen in Self.vouw(String(teken)) {
                tekens.append(gevouwen)
                plek.append(index)
            }
        }
        self.tekens = tekens
        self.plek = plek
        self.woordbegin = woordbegin
    }

    static func vouw(_ tekst: String) -> [Character] {
        Array(
            tekst.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "nl_NL"))
                .filter { $0.isLetter || $0.isNumber })
    }

    /// De plek (in de bron) waar `begin` begint, vanaf `vanaf`. Eerst op een zinsbegin, dan op een
    /// woordbegin; lukt het niet met alle woorden, dan met de eerste drie.
    func zoek(_ begin: String, vanaf: Int, voorkeur zinsbegins: [Int]) -> Int? {
        let woorden = begin.split(whereSeparator: \.isWhitespace)
        var pogingen = [Self.vouw(begin)]
        if woorden.count > 3 { pogingen.append(Self.vouw(woorden.prefix(3).joined(separator: " "))) }
        for gezocht in pogingen where !gezocht.isEmpty {
            let kandidaten = tekens.indices.filter {
                plek[$0] >= vanaf && woordbegin.contains(plek[$0]) && ($0 == 0 || plek[$0 - 1] != plek[$0])
            }
            let zinsbegin = Set(zinsbegins)
            for alleenZinsbegin in [true, false] {
                for index in kandidaten where !alleenZinsbegin || zinsbegin.contains(plek[index]) {
                    if index + gezocht.count <= tekens.count, Array(tekens[index..<(index + gezocht.count)]) == gezocht
                    {
                        return plek[index]
                    }
                }
            }
        }
        return nil
    }
}

// MARK: - Splitsen en samenvoegen in het controlescherm

extension ReceptConcept {
    /// "Splits hier": stap `index` in tweeën vóór zin `zin`. Beide delen houden de regelnummers
    /// van de stap (voor de uitsnede) en de twijfel, zolang de tekst niet is aangepast.
    mutating func splitsStap(_ index: Int, voorZin zin: Int) {
        guard stappen.indices.contains(index),
            let (eerste, tweede) = StapSplitser.splits(stappen[index].tekst, voorZin: zin)
        else { return }
        let stap = stappen[index]
        let twijfel = stap.laagVertrouwen && stap.tekst == stap.herkend
        stappen.replaceSubrange(
            index...index,
            with: [
                ConceptRegel(tekst: eerste, laagVertrouwen: twijfel, regels: stap.regels),
                ConceptRegel(tekst: tweede, laagVertrouwen: twijfel, regels: stap.regels),
            ])
    }

    /// "Voeg samen met vorige": stap `index` achter de stap ervoor. Regelnummers en twijfel samen.
    mutating func voegStapSamenMetVorige(_ index: Int) {
        guard index > 0, stappen.indices.contains(index) else { return }
        let vorige = stappen[index - 1]
        let stap = stappen[index]
        var regels = vorige.regels
        for regel in stap.regels where !regels.contains(regel) { regels.append(regel) }
        let samen = ConceptRegel(
            tekst: ReceptOpbouw.plak([vorige.tekst, stap.tekst]),
            laagVertrouwen: ReceptOpbouw.isTwijfel(vorige, isIngredient: false)
                || ReceptOpbouw.isTwijfel(stap, isIngredient: false),
            regels: regels)
        stappen.replaceSubrange((index - 1)...index, with: [samen])
    }
}
