import Foundation
import OSLog

/// Wat Knipsel per ingrediënt (`BoodschappenLijst.sleutel`) over de afdeling onthoudt, alleen op dit
/// toestel (UserDefaults): wat de gebruiker zelf koos, en wat Claude voor een onbekende naam zei.
struct AfdelingGeheugen: Codable, Equatable, Sendable {
    /// Gekozen door de gebruiker: gaat altijd voor.
    var keuzes: [String: Afdeling] = [:]
    /// Antwoorden van Claude voor namen die niet in de woordenlijst staan.
    var claude: [String: Afdeling] = [:]

    /// Gebruikerskeuze, dan de woordenlijst, dan Claude, anders Overig. Uit blik ("1 blik tomaten") is
    /// groente houdbaar.
    func afdeling(naam: String, sleutel: String, eenheid: String? = nil) -> Afdeling {
        if let keuze = keuzes[sleutel] { return keuze }
        if let bekend = Afdelingen.uitWoordenlijst(naam) {
            return bekend == .groenteFruit && Afdelingen.isBlik(eenheid) ? .houdbaar : bekend
        }
        return claude[sleutel] ?? .overig
    }

    /// Mag Claude naar deze naam kijken? Alleen als niets anders iets weet.
    func isOnbekend(naam: String, sleutel: String) -> Bool {
        keuzes[sleutel] == nil && claude[sleutel] == nil && Afdelingen.uitWoordenlijst(naam) == nil
    }

    mutating func kies(_ afdeling: Afdeling, voor sleutel: String) {
        guard !sleutel.isEmpty else { return }
        keuzes[sleutel] = afdeling
    }

    static func laad(uit defaults: UserDefaults = .standard) -> AfdelingGeheugen {
        guard let data = defaults.data(forKey: AppConfiguratie.sleutelAfdelingen),
            let geheugen = try? JSONDecoder().decode(AfdelingGeheugen.self, from: data)
        else { return AfdelingGeheugen() }
        return geheugen
    }

    func bewaar(in defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: AppConfiguratie.sleutelAfdelingen)
    }
}

/// Onbekende ingrediëntnamen indelen met Claude (optioneel, alleen met een eigen sleutel). Alleen de
/// namen gaan naar Anthropic, niets anders. Zonder sleutel of bij een fout blijft het Overig.
struct ClaudeAfdelingen: Sendable {
    var sleutel: @Sendable () -> String?
    var sessie: URLSession = .shared

    private static let logger = Logger(subsystem: "com.peterbijkerk.knipsel", category: "Claude")

    static let opdracht = """
        Je deelt ingrediënten in naar de afdeling van een Nederlandse supermarkt. Kies per naam precies één \
        code uit: \(Afdeling.allCases.map(\.rawValue).joined(separator: ", ")). Antwoord met alleen JSON, \
        zonder uitleg en zonder markdown, met de naam letterlijk als sleutel: {"naam":"code"}.
        """

    /// Per naam de afdeling; namen waar Claude niets bruikbaars voor gaf ontbreken. Gooit niet.
    func deelIn(_ namen: [String]) async -> [String: Afdeling] {
        guard !namen.isEmpty, let sleutel = sleutel(), !sleutel.isEmpty else { return [:] }
        do {
            let (data, antwoord) = try await sessie.data(for: Self.verzoek(namen: namen, sleutel: sleutel))
            let status = (antwoord as? HTTPURLResponse)?.statusCode ?? -1
            guard (200...299).contains(status) else { throw ClaudeIndeler.Fout.http(status) }
            return try Self.afdelingen(uitAntwoord: data)
        } catch {
            Self.logger.info("Afdelingen niet via Claude: \(String(describing: error), privacy: .public)")
            return [:]
        }
    }

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

    /// Alleen de namen, één per regel.
    static func verzoek(namen: [String], sleutel: String) throws -> URLRequest {
        var verzoek = URLRequest(url: ClaudeIndeler.endpoint, timeoutInterval: 30)
        verzoek.httpMethod = "POST"
        verzoek.setValue("application/json", forHTTPHeaderField: "content-type")
        verzoek.setValue(sleutel, forHTTPHeaderField: "x-api-key")
        verzoek.setValue(ClaudeIndeler.apiVersie, forHTTPHeaderField: "anthropic-version")
        verzoek.httpBody = try JSONEncoder().encode(
            Verzoek(
                model: ClaudeIndeler.model, max_tokens: 512, system: opdracht,
                messages: [Bericht(role: "user", content: namen.joined(separator: "\n"))]))
        return verzoek
    }

    private struct Antwoord: Decodable {
        struct Blok: Decodable {
            let type: String
            let text: String?
        }
        let content: [Blok]
    }

    static func afdelingen(uitAntwoord data: Data) throws -> [String: Afdeling] {
        let antwoord = try JSONDecoder().decode(Antwoord.self, from: data)
        guard let tekst = antwoord.content.first(where: { $0.type == "text" })?.text,
            let begin = tekst.firstIndex(of: "{"), let eind = tekst.lastIndex(of: "}"), begin < eind
        else { throw ClaudeIndeler.Fout.onbruikbaarAntwoord }
        let ruw = try JSONDecoder().decode([String: String].self, from: Data(tekst[begin...eind].utf8))
        return ruw.compactMapValues { Afdeling(rawValue: $0.trimmingCharacters(in: .whitespaces).lowercased()) }
    }
}
