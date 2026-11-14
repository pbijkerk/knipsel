import Foundation
import OSLog

/// Indelen met Claude (optioneel, B10): de herkende tekstregels met hun nummer gaan naar de
/// Anthropic Messages API; Claude geeft alleen regelnummers per rol terug, plus de beginwoorden van
/// elke stap (#17). Knipsel knipt de letterlijke tekst daarop; klopt dat niet, dan deelt
/// `StapSplitser` de stappen in. Nooit de foto.
/// Zonder sleutel, zonder netwerk of bij een onbruikbaar antwoord valt hij stil terug.
struct ClaudeIndeler: Indeler {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let model = "claude-haiku-4-5"
    static let apiVersie = "2023-06-01"

    /// Leest de sleutel pas bij het indelen (hij kan intussen verwijderd zijn).
    var sleutel: @Sendable () -> String?
    var sessie: URLSession = .shared
    var terugval: any Indeler = RegelIndeler()

    private static let logger = Logger(subsystem: "com.peterbijkerk.knipsel", category: "Claude")

    enum Fout: Error {
        case geenSleutel
        case http(Int)
        case onbruikbaarAntwoord
    }

    func deelIn(_ regels: [HerkendeRegel], categorieen: [String], labels: [String]) async -> Indeling {
        do {
            guard let sleutel = sleutel(), !sleutel.isEmpty else { throw Fout.geenSleutel }
            let verzoek = try Self.verzoek(regels: regels, categorieen: categorieen, labels: labels, sleutel: sleutel)
            let (data, antwoord) = try await sessie.data(for: verzoek)
            let status = (antwoord as? HTTPURLResponse)?.statusCode ?? -1
            guard (200...299).contains(status) else { throw Fout.http(status) }
            return try Self.indeling(
                uitAntwoord: data, aantal: regels.count, categorieen: categorieen, labels: labels)
        } catch {
            Self.logger.info(
                "Claude niet gebruikt, terug naar de regels: \(String(describing: error), privacy: .public)")
            return await terugval.deelIn(regels, categorieen: categorieen, labels: labels)
        }
    }

    // MARK: - Verzoek

    private struct Bericht: Encodable {
        let role: String
        let content: String
    }

    private struct Verzoek: Encodable {
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Bericht]
    }

    static let opdracht = """
        Je deelt OCR-tekst van een krant- of tijdschriftpagina in voor een receptenapp. Elke regel heeft \
        een nummer tussen haken. Je herschrijft niets: je geeft alleen regelnummers en de letterlijke \
        beginwoorden van stappen terug. Regels die niet bij het recept horen (advertenties, andere \
        artikelen, lezersbrieven, e-mailadressen, losse kopjes als "Ingrediënten" of "Bereiding") laat je weg. \
        Een column of verhaal vóór het recept is intro, ook als het over koken gaat ("ik kookte", "we \
        lieten inkoken"). De bereiding begint vaak zonder kopje en zonder nummers midden in de tekst, bij \
        de eerste alinea met een gebiedende zin ("Schil de peren, …"); de ingrediënten kunnen daarna nog \
        in een apart blok staan. Deel de bereiding in stappen: één handeling of een paar samenhangende \
        handelingen per stap (1 tot 3 zinnen). Een stap begint altijd aan het begin van een zin. Zijn de \
        stappen genummerd, volg dan de nummering. Geef per stap alle regelnummers (een regel waarin een \
        stap begint én een vorige eindigt, hoort bij beide) en de eerste vier woorden van de stap, \
        letterlijk zoals in de tekst. Kies categorieën en labels alleen uit de gegeven lijsten (meerdere \
        mag). Antwoord met alleen JSON, zonder uitleg en zonder markdown, precies in deze vorm: \
        {"titel":[0],"intro":[1],"ingredienten":[3,4],"stappen":[{"regels":[5,6],"begin":"Verwarm de oven \
        voor"},{"regels":[6,7],"begin":"Snijd de pompoen in"}],"categorieen":["…"],"labels":["…"]}
        """

    /// Voor "Stappen opnieuw indelen": alleen de bereidingstekst, in één blok.
    static let opdrachtStappen = """
        Je deelt de bereiding van een recept in stappen voor een receptenapp. Je herschrijft niets. Eén \
        handeling of een paar samenhangende handelingen per stap (1 tot 3 zinnen); een stap begint altijd \
        aan het begin van een zin. Geef van elke stap, op volgorde, de eerste vier woorden, letterlijk \
        zoals in de tekst. Antwoord met alleen JSON, zonder uitleg en zonder markdown, precies in deze \
        vorm: {"stappen":["Verwarm de oven voor","Snijd de pompoen in"]}
        """

    /// Alleen tekst: regelnummers, regels en de lijsten met namen. Geen beeld, geen kaders.
    static func verzoek(regels: [HerkendeRegel], categorieen: [String], labels: [String], sleutel: String) throws
        -> URLRequest
    {
        let tekstregels = regels.enumerated().map { "[\($0.offset)] \($0.element.tekst)" }.joined(separator: "\n")
        let vraag = """
            Categorieën: \(categorieen.joined(separator: ", "))
            Labels: \(labels.joined(separator: ", "))

            Tekstregels:
            \(tekstregels)
            """
        return try verzoek(systeem: opdracht, vraag: vraag, sleutel: sleutel)
    }

    /// Voor "Stappen opnieuw indelen": alleen de bereidingstekst.
    static func verzoek(stappenVan tekst: String, sleutel: String) throws -> URLRequest {
        try verzoek(systeem: opdrachtStappen, vraag: "Bereiding:\n\(tekst)", sleutel: sleutel)
    }

    private static func verzoek(systeem: String, vraag: String, sleutel: String) throws -> URLRequest {
        var verzoek = URLRequest(url: endpoint, timeoutInterval: 30)
        verzoek.httpMethod = "POST"
        verzoek.setValue("application/json", forHTTPHeaderField: "content-type")
        verzoek.setValue(sleutel, forHTTPHeaderField: "x-api-key")
        verzoek.setValue(apiVersie, forHTTPHeaderField: "anthropic-version")
        verzoek.httpBody = try JSONEncoder().encode(
            Verzoek(
                model: model, max_tokens: maxTokens, system: systeem,
                messages: [Bericht(role: "user", content: vraag)]))
        return verzoek
    }

    /// Ruim genoeg voor regelnummers én beginwoorden van een lang recept.
    static let maxTokens = 2048

    // MARK: - Stappen opnieuw indelen

    /// De beginwoorden van elke stap volgens Claude. Gooit bij een fout of een onbruikbaar antwoord;
    /// de letterlijkheid controleert `StapSplitser.knip`.
    static func stapBeginnen(voor tekst: String, sleutel: String, sessie: URLSession = .shared) async throws
        -> [String]
    {
        let (data, antwoord) = try await sessie.data(for: verzoek(stappenVan: tekst, sleutel: sleutel))
        let status = (antwoord as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(status) else { throw Fout.http(status) }
        struct Stappen: Decodable { var stappen: [String] }
        let beginnen = try JSONDecoder().decode(Stappen.self, from: json(uitAntwoord: data)).stappen
        guard !beginnen.isEmpty, beginnen.allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
            throw Fout.onbruikbaarAntwoord
        }
        return beginnen
    }

    // MARK: - Antwoord

    private struct Antwoord: Decodable {
        struct Blok: Decodable {
            let type: String
            let text: String?
        }
        let content: [Blok]
    }

    private struct Uitkomst: Decodable {
        struct Stap: Decodable {
            var regels: [Int]?
            var begin: String?
        }
        var titel: [Int]?
        var intro: [Int]?
        var ingredienten: [Int]?
        /// Oud formaat: alleen de regels van de bereiding.
        var bereiding: [Int]?
        var stappen: [Stap]?
        var categorieen: [String]?
        var labels: [String]?
    }

    /// Het JSON-object uit het antwoord (Claude zet er soms ```json omheen).
    private static func json(uitAntwoord data: Data) throws -> Data {
        let antwoord = try JSONDecoder().decode(Antwoord.self, from: data)
        guard let tekst = antwoord.content.first(where: { $0.type == "text" })?.text,
            let begin = tekst.firstIndex(of: "{"), let eind = tekst.lastIndex(of: "}"), begin < eind
        else { throw Fout.onbruikbaarAntwoord }
        return Data(tekst[begin...eind].utf8)
    }

    static func indeling(uitAntwoord data: Data, aantal: Int, categorieen: [String], labels: [String]) throws
        -> Indeling
    {
        let uitkomst = try JSONDecoder().decode(Uitkomst.self, from: json(uitAntwoord: data))
        let stappen = uitkomst.stappen ?? []
        // Beginwoorden alleen als élke stap er een heeft; anders deelt StapSplitser in.
        let beginnen = stappen.compactMap { $0.begin?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let indeling = Indeling(
            aantal: aantal, titel: uitkomst.titel ?? [], intro: uitkomst.intro ?? [],
            ingredienten: uitkomst.ingredienten ?? [],
            bereiding: (uitkomst.bereiding ?? []) + stappen.flatMap { $0.regels ?? [] },
            categorieen: Indeling.bestaande(uitkomst.categorieen ?? [], uit: categorieen),
            labels: Indeling.bestaande(uitkomst.labels ?? [], uit: labels), bron: .claude,
            stapBeginnen: beginnen.count == stappen.count ? beginnen : [])
        // Zonder titel of zonder ingrediënten én stappen is het geen bruikbare indeling.
        guard !indeling.blokken(.titel).isEmpty,
            !indeling.blokken(.ingredient).isEmpty || !indeling.blokken(.stap).isEmpty
        else { throw Fout.onbruikbaarAntwoord }
        return indeling
    }
}
