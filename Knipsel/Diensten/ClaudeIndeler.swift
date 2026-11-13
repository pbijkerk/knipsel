import Foundation
import OSLog

/// Indelen met Claude (optioneel, B10): de herkende tekstregels met hun nummer gaan naar de
/// Anthropic Messages API; Claude geeft alleen regelnummers per rol terug. Nooit de foto.
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
        een nummer tussen haken. Je herschrijft niets: je geeft alleen regelnummers terug. Regels die niet \
        bij het recept horen (advertenties, andere artikelen, lezersbrieven, losse kopjes als \
        "Ingrediënten" of "Bereiding") laat je weg. Een stap die over meerdere regels loopt, geef je met \
        al zijn regelnummers. Kies categorieën en labels alleen uit de gegeven lijsten (meerdere mag). \
        Antwoord met alleen JSON, zonder uitleg en zonder markdown, precies in deze vorm: \
        {"titel":[0],"intro":[1],"ingredienten":[3,4],"bereiding":[5,6],"categorieen":["…"],"labels":["…"]}
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
        var verzoek = URLRequest(url: endpoint, timeoutInterval: 30)
        verzoek.httpMethod = "POST"
        verzoek.setValue("application/json", forHTTPHeaderField: "content-type")
        verzoek.setValue(sleutel, forHTTPHeaderField: "x-api-key")
        verzoek.setValue(apiVersie, forHTTPHeaderField: "anthropic-version")
        verzoek.httpBody = try JSONEncoder().encode(
            Verzoek(
                model: model, max_tokens: 1024, system: opdracht,
                messages: [Bericht(role: "user", content: vraag)]))
        return verzoek
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
        var titel: [Int]?
        var intro: [Int]?
        var ingredienten: [Int]?
        var bereiding: [Int]?
        var categorieen: [String]?
        var labels: [String]?
    }

    static func indeling(uitAntwoord data: Data, aantal: Int, categorieen: [String], labels: [String]) throws
        -> Indeling
    {
        let antwoord = try JSONDecoder().decode(Antwoord.self, from: data)
        guard let tekst = antwoord.content.first(where: { $0.type == "text" })?.text,
            let begin = tekst.firstIndex(of: "{"), let eind = tekst.lastIndex(of: "}"), begin < eind
        else { throw Fout.onbruikbaarAntwoord }
        let uitkomst = try JSONDecoder().decode(Uitkomst.self, from: Data(tekst[begin...eind].utf8))
        let indeling = Indeling(
            aantal: aantal, titel: uitkomst.titel ?? [], intro: uitkomst.intro ?? [],
            ingredienten: uitkomst.ingredienten ?? [], bereiding: uitkomst.bereiding ?? [],
            categorieen: Indeling.bestaande(uitkomst.categorieen ?? [], uit: categorieen),
            labels: Indeling.bestaande(uitkomst.labels ?? [], uit: labels), bron: .claude)
        // Zonder titel of zonder ingrediënten én stappen is het geen bruikbare indeling.
        guard !indeling.blokken(.titel).isEmpty,
            !indeling.blokken(.ingredient).isEmpty || !indeling.blokken(.stap).isEmpty
        else { throw Fout.onbruikbaarAntwoord }
        return indeling
    }
}
