import Foundation
import OSLog

/// Een opgehaalde webpagina.
struct OpgehaaldePagina: Sendable, Equatable {
    var html: String
    /// Na eventuele doorverwijzingen.
    var url: URL
}

/// Haalt pagina's en afbeeldingen op. Achter een protocol, zodat tests nooit het netwerk gebruiken.
protocol PaginaOphaler: Sendable {
    func pagina(_ url: URL) async throws -> OpgehaaldePagina
    func data(_ url: URL) async throws -> Data
}

enum OphaalFout: LocalizedError, Equatable {
    case geenWebadres
    case status(Int)
    case onleesbaar

    var errorDescription: String? {
        switch self {
        case .geenWebadres: "Dit is geen webadres (http of https)."
        case .status(let code): "De site gaf foutcode \(code)."
        case .onleesbaar: "De pagina kon niet gelezen worden."
        }
    }
}

/// Ophalen rechtstreeks vanaf het toestel met `URLSession` (geen eigen server), met een gewone
/// Safari-User-Agent zodat sites de normale pagina sturen, en een time-out van 20 seconden.
struct WebOphaler: PaginaOphaler {
    static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"
    static let timeout: TimeInterval = 20

    private let sessie: URLSession

    init() {
        let configuratie = URLSessionConfiguration.default
        configuratie.timeoutIntervalForRequest = Self.timeout
        configuratie.timeoutIntervalForResource = Self.timeout * 2
        configuratie.httpAdditionalHeaders = [
            "User-Agent": Self.userAgent,
            "Accept-Language": "nl-NL,nl;q=0.9,en;q=0.6",
        ]
        sessie = URLSession(configuration: configuratie)
    }

    func pagina(_ url: URL) async throws -> OpgehaaldePagina {
        let (data, antwoord) = try await haal(url, accept: "text/html,application/xhtml+xml,*/*;q=0.8")
        guard let html = Self.tekst(data, encoding: antwoord.textEncodingName) else { throw OphaalFout.onleesbaar }
        return OpgehaaldePagina(html: html, url: antwoord.url ?? url)
    }

    func data(_ url: URL) async throws -> Data {
        try await haal(url, accept: "image/*").0
    }

    private func haal(_ url: URL, accept: String) async throws -> (Data, URLResponse) {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { throw OphaalFout.geenWebadres }
        var verzoek = URLRequest(url: url, timeoutInterval: Self.timeout)
        verzoek.setValue(accept, forHTTPHeaderField: "Accept")
        let (data, antwoord) = try await sessie.data(for: verzoek)
        if let http = antwoord as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw OphaalFout.status(http.statusCode)
        }
        return (data, antwoord)
    }

    /// HTML-bytes naar tekst: de tekenset uit de HTTP-kop, anders UTF-8, anders Latin-1.
    static func tekst(_ data: Data, encoding naam: String?) -> String? {
        if let naam {
            let cf = CFStringConvertIANACharSetNameToEncoding(naam as CFString)
            if cf != kCFStringEncodingInvalidId {
                let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
                if let tekst = String(data: data, encoding: encoding) { return tekst }
            }
        }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
    }
}

/// Wat het inlezen oplevert, klaar voor het controlescherm. `Codable`: het staat in de inbox
/// ("Nog te controleren") tot je het controleert.
struct InleesResultaat: Codable, Equatable, Sendable {
    struct Stap: Codable, Equatable, Sendable {
        var tekst: String
        var groep: String?
    }

    enum Herkomst: String, Codable, Sendable {
        /// schema.org-receptgegevens van de site.
        case schema
        /// Leesbare tekst, ingedeeld met regels op het toestel.
        case regels
        /// Leesbare tekst, ingedeeld met Claude (alleen als die aan staat, B10).
        case claude
        case model
    }

    var titel = ""
    var intro = ""
    var porties = 0
    var minuten = 0
    var ingredienten: [String] = []
    var stappen: [Stap] = []
    /// Site (uitgever of host), bijvoorbeeld "Leuke Recepten" of "voorbeeldkeuken.nl".
    var bronNaam = ""
    var bronURL: URL?
    var afbeeldingURL: URL?
    var categorieen: [String] = []
    var labels: [String] = []
    var herkomst = Herkomst.schema

    var concept: ReceptConcept {
        var concept = ReceptConcept()
        concept.titel = titel
        concept.intro = intro
        concept.porties = porties
        concept.minuten = minuten
        concept.ingredienten = ingredienten.map { ConceptRegel(tekst: $0) }
        concept.stappen = stappen.map { ConceptRegel(tekst: $0.tekst, groep: $0.groep) }
        return concept
    }

    init() {}

    init(concept: ReceptConcept, herkomst: Herkomst) {
        titel = concept.titel
        intro = concept.intro
        porties = concept.porties
        minuten = concept.minuten
        ingredienten = concept.ingredienten.map(\.tekst)
        stappen = concept.stappen.map { Stap(tekst: $0.tekst, groep: $0.groep) }
        self.herkomst = herkomst
    }

    /// Te weinig om een recept te zijn: geen titel, of geen ingrediënten én geen stappen.
    var isTeKort: Bool {
        titel.trimmingCharacters(in: .whitespaces).isEmpty || (ingredienten.isEmpty && stappen.isEmpty)
    }
}

/// De uitkomst van één keer inlezen.
enum InleesUitkomst: Equatable, Sendable {
    case recept(InleesResultaat)
    /// Alleen een teaser: kies inloggen in Knipsel, tekst plakken of een schermafdruk (#18).
    case betaalmuur(redenen: [String])
    /// Geen recept gevonden in wat er wel stond.
    case geenRecept(String)
}

/// Leest een recept uit HTML of platte tekst: eerst schema.org, dan betaalmuur herkennen, dan de
/// leesbare tekst door de `Indeler`. Het ophalen zelf staat in `PaginaOphaler`.
enum ReceptInlezer {
    /// Een receptpagina heeft minstens zoveel ingrediënten en stappen nodig, anders is het waarschijnlijk
    /// een teaser of een overzichtspagina.
    static let minIngredienten = 2

    static func lees(
        html: String, url: URL?, categorieen: [String], labels: [String], indeler: any Indeler
    ) async -> InleesUitkomst {
        let site = siteNaam(html: html, url: url)
        if let schema = SchemaReceptLezer.lees(html: html, basis: url) {
            var resultaat = InleesResultaat(concept: SchemaReceptLezer.concept(schema), herkomst: .schema)
            resultaat.bronNaam = schema.uitgever ?? site ?? schema.auteur ?? ""
            resultaat.bronURL = url
            resultaat.afbeeldingURL = schema.afbeelding
            resultaat.categorieen = Voorstellen.categorieen(
                titel: schema.naam, intro: schema.beschrijving, uit: categorieen)
            resultaat.labels = Voorstellen.labels(
                ingredienten: schema.ingredienten, minuten: schema.minuten, uit: labels)
            return .recept(resultaat)
        }

        let blokken = PaginaLezer.blokken(html: html)
        let tekst = PaginaLezer.tekst(blokken)
        let oordeel = Betaalmuur.beoordeel(html: html, tekst: tekst)
        if oordeel.isBetaalmuur { return .betaalmuur(redenen: oordeel.redenen) }

        var resultaat = await deelIn(
            TekstRegels.regels(blokken), categorieen: categorieen, labels: labels, indeler: indeler)
        resultaat.bronNaam = site ?? ""
        resultaat.bronURL = url
        resultaat.afbeeldingURL = HTMLTekst.meta("og:image", in: html).flatMap {
            SchemaReceptLezer.afbeelding($0, basis: url)
        }
        guard !resultaat.isTeKort, resultaat.ingredienten.count >= minIngredienten else {
            return .geenRecept("Op deze pagina staat geen herkenbaar recept.")
        }
        return .recept(resultaat)
    }

    /// Geplakte of gedeelde tekst, of de tekstlaag van een PDF.
    static func lees(tekst: String, categorieen: [String], labels: [String], indeler: any Indeler) async
        -> InleesUitkomst
    {
        let regels = TekstRegels.regels(tekst: tekst)
        guard !regels.isEmpty else { return .geenRecept("Er staat geen tekst in.") }
        let resultaat = await deelIn(regels, categorieen: categorieen, labels: labels, indeler: indeler)
        guard !resultaat.isTeKort else { return .geenRecept("In deze tekst staat geen herkenbaar recept.") }
        return .recept(resultaat)
    }

    private static func deelIn(
        _ regels: [HerkendeRegel], categorieen: [String], labels: [String], indeler: any Indeler
    ) async -> InleesResultaat {
        guard !regels.isEmpty else { return InleesResultaat() }
        let indeling = await indeler.deelIn(regels, categorieen: categorieen, labels: labels)
        let herkomst: InleesResultaat.Herkomst =
            switch indeling.bron {
            case .regels: .regels
            case .claude: .claude
            case .model: .model
            }
        var resultaat = InleesResultaat(concept: ReceptOpbouw.bouw(regels, indeling: indeling), herkomst: herkomst)
        resultaat.categorieen = indeling.categorieen
        resultaat.labels = indeling.labels
        return resultaat
    }

    /// De naam van de site: `og:site_name`, anders de host zonder "www." (de uitgever uit schema.org
    /// gaat voor, zie `lees`).
    static func siteNaam(html: String, url: URL?) -> String? {
        if let naam = HTMLTekst.meta("og:site_name", in: html), !naam.isEmpty { return naam }
        return url.flatMap(host)
    }

    static func host(_ url: URL) -> String? {
        guard var host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    /// Een webadres in geplakte tekst: de hele tekst is één http(s)-link.
    static func link(in tekst: String) -> URL? {
        let schoon = tekst.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !schoon.contains(where: \.isWhitespace), let url = URL(string: schoon),
            ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host() != nil
        else { return nil }
        return url
    }
}
