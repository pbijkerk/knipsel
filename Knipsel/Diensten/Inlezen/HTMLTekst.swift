import Foundation

/// Kleine, pure hulpmiddelen voor HTML van receptsites: entiteiten omzetten, tags weghalen en
/// elementen vinden. Geen WebKit en geen netwerk, zodat alles met vaste fixtures te testen is.
enum HTMLTekst {
    // MARK: - Entiteiten

    /// Benoemde entiteiten die op Nederlandse receptsites voorkomen. Onbekende blijven staan.
    private static let benoemd: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "shy": "",
        "eacute": "é", "egrave": "è", "ecirc": "ê", "euml": "ë", "aacute": "á", "agrave": "à", "acirc": "â",
        "auml": "ä", "iacute": "í", "igrave": "ì", "icirc": "î", "iuml": "ï", "oacute": "ó", "ograve": "ò",
        "ocirc": "ô", "ouml": "ö", "uacute": "ú", "ugrave": "ù", "ucirc": "û", "uuml": "ü", "ccedil": "ç",
        "ntilde": "ñ", "Eacute": "É", "Euml": "Ë", "Iuml": "Ï", "Ouml": "Ö", "Uuml": "Ü", "szlig": "ß",
        "deg": "°", "frac12": "½", "frac14": "¼", "frac34": "¾", "frac13": "⅓", "frac23": "⅔", "times": "×",
        "ndash": "–", "mdash": "—", "hellip": "…", "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”",
        "bdquo": "„", "laquo": "«", "raquo": "»", "euro": "€", "middot": "·", "bull": "•", "copy": "©",
        "reg": "®", "trade": "™", "minus": "−", "frasl": "⁄", "thinsp": " ", "ensp": " ", "emsp": " ",
        "zwj": "", "zwnj": "",
    ]

    private static let entiteitRegex = try! NSRegularExpression(
        pattern: "&(#[xX][0-9a-fA-F]{1,6}|#[0-9]{1,7}|[a-zA-Z][a-zA-Z0-9]{1,31});")

    /// `&amp;` → `&`, `&#233;` → `é`, `&#x2019;` → `’`. Ook dubbel gecodeerd (`&amp;eacute;`), wat
    /// in JSON-LD van sommige sites voorkomt.
    static func entiteiten(_ tekst: String) -> String {
        guard tekst.contains("&") else { return tekst }
        var resultaat = vervangEntiteiten(tekst)
        if resultaat.contains("&"), resultaat != tekst {
            resultaat = vervangEntiteiten(resultaat)
        }
        return resultaat
    }

    private static func vervangEntiteiten(_ tekst: String) -> String {
        let ns = tekst as NSString
        var resultaat = ""
        var positie = 0
        for treffer in entiteitRegex.matches(in: tekst, range: NSRange(location: 0, length: ns.length)) {
            resultaat += ns.substring(with: NSRange(location: positie, length: treffer.range.location - positie))
            let naam = ns.substring(with: treffer.range(at: 1))
            resultaat += teken(voor: naam) ?? ns.substring(with: treffer.range)
            positie = treffer.range.location + treffer.range.length
        }
        resultaat += ns.substring(from: positie)
        return resultaat
    }

    private static func teken(voor naam: String) -> String? {
        if naam.hasPrefix("#") {
            let cijfers = naam.dropFirst()
            let waarde =
                cijfers.first == "x" || cijfers.first == "X"
                ? UInt32(cijfers.dropFirst(), radix: 16) : UInt32(cijfers, radix: 10)
            guard let waarde, let scalar = Unicode.Scalar(waarde) else { return nil }
            // Een harde spatie of zachte afbreking wordt een gewone spatie of niets.
            if waarde == 0xA0 { return " " }
            if waarde == 0xAD { return "" }
            return String(Character(scalar))
        }
        return benoemd[naam]
    }

    // MARK: - Tags weg

    /// Platte tekst uit een stukje HTML: `<br>` en blokelementen worden een regeleinde, andere tags
    /// verdwijnen, entiteiten worden tekens, witruimte per regel wordt één spatie.
    static func platteTekst(_ html: String) -> String {
        var tekst = html
        tekst = tekst.replacingOccurrences(of: #"<!--[\s\S]*?-->"#, with: " ", options: .regularExpression)
        tekst = tekst.replacingOccurrences(
            of: #"(?i)<(br|/p|/li|/h[1-6]|/div|/tr|/dt|/dd)\b[^>]*>"#, with: "\n", options: .regularExpression)
        tekst = tekst.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        tekst = entiteiten(tekst)
        return
            tekst
            .components(separatedBy: .newlines)
            .map(schoonRegel)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// Eén regel: tags en entiteiten weg, alle witruimte (ook harde spaties) één spatie.
    static func schoon(_ tekst: String) -> String {
        schoonRegel(platteTekst(tekst).replacingOccurrences(of: "\n", with: " "))
    }

    /// Harde en smalle spaties: in een recept gewone spaties.
    private static let harde: Set<Character> = ["\u{00A0}", "\u{2007}", "\u{2009}", "\u{202F}"]

    private static func schoonRegel(_ regel: String) -> String {
        String(regel.map { harde.contains($0) ? " " : $0 })
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Elementen

    /// Een HTML-element: de attributen en de HTML ertussen.
    struct Element: Equatable {
        var naam: String
        var attributen: [String: String]
        var binnen: String
    }

    private static let attribuutRegex = try! NSRegularExpression(
        pattern: #"([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*(?:=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?"#)

    /// `class="a b" itemprop='name'` → ["class": "a b", "itemprop": "name"]; namen in kleine letters.
    static func attributen(_ tekst: String) -> [String: String] {
        let ns = tekst as NSString
        var resultaat: [String: String] = [:]
        for treffer in attribuutRegex.matches(in: tekst, range: NSRange(location: 0, length: ns.length)) {
            let naam = ns.substring(with: treffer.range(at: 1)).lowercased()
            var waarde = ""
            for groep in 2...4 where treffer.range(at: groep).location != NSNotFound {
                waarde = ns.substring(with: treffer.range(at: groep))
            }
            if resultaat[naam] == nil { resultaat[naam] = entiteiten(waarde) }
        }
        return resultaat
    }

    /// Elementen zonder sluittag.
    private static let leeg: Set<String> = [
        "meta", "link", "img", "br", "hr", "input", "source", "area", "base", "col", "embed", "wbr",
    ]

    /// Alle elementen waarvan de openingstag aan `filter` voldoet, met hun inhoud tot de bijbehorende
    /// sluittag (geneste elementen met dezelfde naam tellen mee). Lege elementen (`<meta>`,
    /// `<img>`) hebben een lege inhoud.
    static func elementen(in html: String, waar filter: (String, [String: String]) -> Bool) -> [Element] {
        let ns = html as NSString
        let openRegex = try! NSRegularExpression(pattern: #"<([a-zA-Z][a-zA-Z0-9]*)\b([^>]*)>"#)
        var resultaat: [Element] = []
        for treffer in openRegex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let naam = ns.substring(with: treffer.range(at: 1)).lowercased()
            let rauw = ns.substring(with: treffer.range(at: 2))
            let attributen = attributen(rauw)
            guard filter(naam, attributen) else { continue }
            let einde = treffer.range.location + treffer.range.length
            if leeg.contains(naam) || rauw.hasSuffix("/") {
                resultaat.append(Element(naam: naam, attributen: attributen, binnen: ""))
                continue
            }
            let binnen = inhoud(van: naam, vanaf: einde, in: ns)
            resultaat.append(Element(naam: naam, attributen: attributen, binnen: binnen))
        }
        return resultaat
    }

    /// De HTML vanaf `start` tot de sluittag die bij `naam` hoort.
    private static func inhoud(van naam: String, vanaf start: Int, in ns: NSString) -> String {
        guard
            let regex = try? NSRegularExpression(
                pattern: "<(/?)\(NSRegularExpression.escapedPattern(for: naam))\\b[^>]*>", options: .caseInsensitive)
        else { return "" }
        var diepte = 1
        for treffer in regex.matches(in: ns as String, range: NSRange(location: start, length: ns.length - start)) {
            let sluit = treffer.range(at: 1).length > 0
            diepte += sluit ? -1 : 1
            if diepte == 0 {
                return ns.substring(with: NSRange(location: start, length: treffer.range.location - start))
            }
        }
        return ns.substring(from: start)
    }

    /// Haalt hele elementen (met inhoud) weg, bijvoorbeeld `script`, `style` en `nav`.
    static func zonder(_ namen: [String], in html: String) -> String {
        var tekst = html
        for naam in namen {
            tekst = tekst.replacingOccurrences(
                of: "(?is)<\(naam)\\b[^>]*>.*?</\(naam)\\s*>", with: " ", options: .regularExpression)
            tekst = tekst.replacingOccurrences(of: "(?is)<\(naam)\\b[^>]*/>", with: " ", options: .regularExpression)
        }
        return tekst
    }

    /// De inhoud van `<meta property|name="…" content="…">`, bijvoorbeeld `og:site_name`.
    static func meta(_ sleutel: String, in html: String) -> String? {
        let sleutel = sleutel.lowercased()
        let treffers = elementen(in: html) { naam, attributen in
            naam == "meta"
                && (attributen["property"]?.lowercased() == sleutel || attributen["name"]?.lowercased() == sleutel)
        }
        return treffers.compactMap { $0.attributen["content"].map(schoon) }.first { !$0.isEmpty }
    }

    /// De tekst van `<title>`.
    static func titel(in html: String) -> String? {
        guard let bereik = html.range(of: #"(?is)<title\b[^>]*>(.*?)</title>"#, options: .regularExpression) else {
            return nil
        }
        let titel = schoon(String(html[bereik]))
        return titel.isEmpty ? nil : titel
    }
}
