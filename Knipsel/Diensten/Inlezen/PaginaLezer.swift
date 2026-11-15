import CoreGraphics
import Foundation

/// De leesbare tekst van een webpagina zonder receptgegevens: koppen, alinea's en lijstitems, in
/// volgorde. Scripts, stijlen, menu's, voetteksten en formulieren vallen weg. Gaat daarna als
/// "herkende regels" naar de bestaande `Indeler` (regels, of Claude als die aan staat, B10).
enum PaginaLezer {
    /// Eén blok tekst op de pagina.
    struct Blok: Equatable, Sendable {
        enum Soort: Equatable, Sendable {
            /// `h1`…`h6`: 1 is de grootste.
            case kop(Int)
            case alinea
            /// Een lijstitem; `lijst` nummert de lijst waar het in staat (opeenvolgende items in
            /// dezelfde lijst vormen één blok, zoals een ingrediëntenlijst op papier). In een
            /// genummerde lijst (`<ol>`) is `nummer` het volgnummer.
            case item(lijst: Int, nummer: Int? = nil)
        }

        var tekst: String
        var soort: Soort
    }

    /// Elementen die nooit recepttekst bevatten.
    static let weg = [
        "script", "style", "noscript", "template", "svg", "nav", "footer", "aside", "form", "iframe", "button",
        "select", "dialog", "figure",
    ]

    /// Maximaal aantal blokken: een lange pagina met honderden links maakt het indelen traag.
    static let maxBlokken = 300

    static func blokken(html: String) -> [Blok] {
        var schoon = HTMLTekst.zonder(weg, in: html)
        schoon = schoon.replacingOccurrences(of: #"<!--[\s\S]*?-->"#, with: " ", options: .regularExpression)
        // Liefst alleen het artikel: `<article>` of `<main>`, als daar genoeg tekst in staat.
        for kern in ["article", "main"] {
            let kandidaten = HTMLTekst.elementen(in: schoon) { naam, _ in naam == kern }
            if let grootste = kandidaten.max(by: { $0.binnen.count < $1.binnen.count }),
                HTMLTekst.platteTekst(grootste.binnen).count > 200
            {
                // De paginatitel staat soms boven het artikel.
                let kop = HTMLTekst.elementen(in: schoon) { naam, _ in naam == "h1" }.first
                let binnen = grootste.binnen
                schoon =
                    (kop.map { binnen.contains($0.binnen) ? "" : "<h1>\($0.binnen)</h1>" } ?? "") + binnen
                break
            }
        }

        let ns = schoon as NSString
        let regex = try! NSRegularExpression(
            pattern: #"<(h[1-6]|p|li|dt|dd|blockquote|td|ul|ol|/ul|/ol)\b[^>]*>"#, options: .caseInsensitive)
        var blokken: [Blok] = []
        var lijstNummer = 0
        var lijstDiepte = 0
        // Per open lijst: genummerd (`<ol>`)? En het volgnummer van het laatste item.
        var genummerd: [Bool] = []
        var teller = 0
        for treffer in regex.matches(in: schoon, range: NSRange(location: 0, length: ns.length)) {
            let naam = ns.substring(with: treffer.range(at: 1)).lowercased()
            switch naam {
            case "ul", "ol":
                if lijstDiepte == 0 {
                    lijstNummer += 1
                    teller = 0
                }
                lijstDiepte += 1
                genummerd.append(naam == "ol")
                continue
            case "/ul", "/ol":
                lijstDiepte = max(0, lijstDiepte - 1)
                if !genummerd.isEmpty { genummerd.removeLast() }
                continue
            default:
                break
            }
            let start = treffer.range.location + treffer.range.length
            let rest = ns.substring(from: start) as NSString
            // Tot de sluittag, of tot het volgende blokelement (slordige HTML zonder `</p>`).
            let einde = rest.range(
                of: #"</\#(naam)\s*>|<(h[1-6]|p|li|ul|ol|div|table|section|dt|dd)\b"#,
                options: [.regularExpression, .caseInsensitive])
            let binnen = einde.location == NSNotFound ? rest as String : rest.substring(to: einde.location)
            let tekst = HTMLTekst.schoon(binnen)
            guard !tekst.isEmpty else { continue }
            let soort: Blok.Soort
            if naam.hasPrefix("h"), let niveau = Int(naam.dropFirst()) {
                soort = .kop(niveau)
            } else if naam == "li" {
                if genummerd.last == true {
                    teller += 1
                    soort = .item(lijst: lijstNummer, nummer: teller)
                } else {
                    soort = .item(lijst: lijstNummer)
                }
            } else {
                soort = .alinea
            }
            if let vorige = blokken.last, vorige.tekst == tekst { continue }
            blokken.append(Blok(tekst: tekst, soort: soort))
            if blokken.count >= maxBlokken { break }
        }
        return blokken
    }

    /// Alle tekst achter elkaar, voor de betaalmuurherkenning en de lengtecontrole.
    static func tekst(_ blokken: [Blok]) -> String {
        blokken.map(\.tekst).joined(separator: "\n")
    }
}

/// Zet tekst zonder bladspiegel (een webpagina, geplakte tekst, de tekstlaag van een PDF) om in
/// "herkende regels" met verzonnen kaders, zodat de bestaande `Indeler` en `ReceptOpbouw` er zonder
/// aanpassing mee werken: kopjes groter, lange alinea's afgebroken op ±48 tekens zoals een
/// krantenkolom, een lege regel = een nieuw blok, de regels van één lijst vlak onder elkaar.
enum TekstRegels {
    static let regelhoogte: CGFloat = 0.012
    static let kophoogte: CGFloat = 0.026
    /// Ruimte tussen regels van één blok (kleiner dan een regel: zelfde blok in `Opmaak`).
    static let binnenBlok: CGFloat = 0.004
    /// Ruimte tussen blokken (groter dan een regel: nieuw blok).
    static let tussenBlokken: CGFloat = 0.02
    static let maxTekens = 48

    /// Uit de blokken van een webpagina.
    static func regels(_ blokken: [PaginaLezer.Blok]) -> [HerkendeRegel] {
        var resultaat: [HerkendeRegel] = []
        var y: CGFloat = 0.02
        var vorigeLijst: Int?
        for blok in blokken {
            let hoogte: CGFloat
            switch blok.soort {
            case .kop(let niveau): hoogte = niveau == 1 ? kophoogte : regelhoogte * 1.25
            default: hoogte = regelhoogte
            }
            var lijst: Int?
            var tekst = blok.tekst
            if case .item(let nummer, let volgnummer) = blok.soort {
                lijst = nummer
                // Een stap uit een genummerde lijst krijgt zijn nummer terug, zoals op papier; de
                // `RegelIndeler` herkent zo de bereiding en `ReceptOpbouw` haalt het er weer af.
                if let volgnummer, !IngredientParser.isGenummerd(tekst) { tekst = "\(volgnummer). " + tekst }
            }
            if !resultaat.isEmpty {
                y += lijst != nil && lijst == vorigeLijst ? binnenBlok : tussenBlokken
            }
            vorigeLijst = lijst
            let delen = lijst != nil ? [tekst] : breek(tekst)
            for (index, deel) in delen.enumerated() {
                if index > 0 { y += binnenBlok }
                resultaat.append(regel(deel, y: y, hoogte: hoogte))
                y += hoogte
            }
        }
        return resultaat
    }

    /// Uit platte tekst: elke regel een regel, een lege regel tussen alinea's een nieuw blok. De
    /// eerste korte regel wordt als kop (groter) gezien, zoals de titel bovenaan een recept.
    static func regels(tekst: String) -> [HerkendeRegel] {
        var blokken: [PaginaLezer.Blok] = []
        var lijst = 0
        var inBlok = false
        for ruw in tekst.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let regel = ruw.trimmingCharacters(in: .whitespaces)
            if regel.isEmpty {
                inBlok = false
                continue
            }
            if !inBlok { lijst += 1 }
            inBlok = true
            let isKop = blokken.isEmpty && regel.count <= 80 && !regel.hasSuffix(".")
            blokken.append(PaginaLezer.Blok(tekst: regel, soort: isKop ? .kop(1) : .item(lijst: lijst)))
        }
        // Lange regels in een blok van één zijn alinea's: die worden afgebroken.
        let aantalPerLijst = Dictionary(
            grouping: blokken,
            by: { blok -> Int in
                if case .item(let nummer, _) = blok.soort { return nummer }
                return -1
            }
        ).mapValues(\.count)
        let blokkenMetAlineas = blokken.map { blok -> PaginaLezer.Blok in
            if case .item(let nummer, _) = blok.soort, aantalPerLijst[nummer] == 1, blok.tekst.count > maxTekens {
                return PaginaLezer.Blok(tekst: blok.tekst, soort: .alinea)
            }
            return blok
        }
        return regels(blokkenMetAlineas)
    }

    private static func regel(_ tekst: String, y: CGFloat, hoogte: CGFloat) -> HerkendeRegel {
        let breedte = min(0.9, max(0.05, CGFloat(tekst.count) * 0.0085))
        return HerkendeRegel(
            tekst: tekst, kader: CGRect(x: 0.05, y: y, width: breedte, height: hoogte), betrouwbaarheid: 1)
    }

    /// Breekt een alinea op woordgrenzen af in regels van hooguit `maxTekens` tekens. Samen weer
    /// geplakt (met spaties) is het dezelfde tekst.
    static func breek(_ tekst: String) -> [String] {
        guard tekst.count > maxTekens else { return [tekst] }
        var regels: [String] = []
        var huidig = ""
        for woord in tekst.split(separator: " ") {
            if !huidig.isEmpty, huidig.count + 1 + woord.count > maxTekens {
                regels.append(huidig)
                huidig = String(woord)
            } else {
                huidig += huidig.isEmpty ? String(woord) : " " + woord
            }
        }
        if !huidig.isEmpty { regels.append(huidig) }
        return regels
    }
}

/// Herkent een betaalmuur: de pagina zegt het zelf (`isAccessibleForFree: false`), of er staat
/// weinig tekst met typische zinnen ("Word abonnee", "Log in om verder te lezen") of
/// betaalmuur-klassen in de HTML. Een heuristiek: liever één keer te vaak de keuze tonen dan een
/// teaser als recept aanbieden.
enum Betaalmuur {
    struct Oordeel: Equatable, Sendable {
        var isBetaalmuur: Bool
        var redenen: [String]
    }

    /// Minder woorden dan dit is "weinig tekst" voor een receptpagina.
    static let weinigWoorden = 220

    static let zinnen = [
        "word abonnee", "neem een abonnement", "abonneer je", "abonneer nu", "alleen voor abonnees",
        "exclusief voor abonnees", "voor abonnees", "log in om verder te lezen", "log in om dit artikel",
        "lees verder met", "lees het hele artikel", "lees dit artikel met", "al abonnee", "je hebt een abonnement",
        "u heeft een abonnement", "dit is een premium", "premium artikel", "plus-artikel", "registreer om verder",
        "maak een gratis account", "subscribe to continue", "sign in to continue", "subscribers only",
    ]

    static let klassen = [
        "paywall", "regwall", "piano-", "tp-modal", "tp-container", "premium-content", "subscriber-only",
        "article-locked", "is-locked", "metered", "abo-wall", "plus-content",
    ]

    static func beoordeel(html: String, tekst: String) -> Oordeel {
        var redenen: [String] = []
        let gratis = SchemaReceptLezer.isGratis(in: html)
        if gratis == false { redenen.append("isAccessibleForFree: false") }
        let gevouwen = IngredientParser.vouw(tekst)
        let gevondenZinnen = zinnen.filter { gevouwen.contains($0) }
        redenen += gevondenZinnen.map { "tekst: \($0)" }
        let html = html.lowercased()
        let gevondenKlassen = klassen.filter { klasse in
            html.range(
                of: #"(class|id)\s*=\s*["'][^"']*"# + NSRegularExpression.escapedPattern(for: klasse),
                options: .regularExpression) != nil
        }
        redenen += gevondenKlassen.map { "klasse: \($0)" }
        let woorden = tekst.split(whereSeparator: \.isWhitespace).count
        let weinig = woorden < weinigWoorden
        if weinig { redenen.append("weinig tekst (\(woorden) woorden)") }

        let isBetaalmuur =
            gratis == false || (weinig && (!gevondenZinnen.isEmpty || !gevondenKlassen.isEmpty))
            || gevondenZinnen.count >= 2
        return Oordeel(isBetaalmuur: isBetaalmuur, redenen: redenen)
    }
}
