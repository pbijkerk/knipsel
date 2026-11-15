import Foundation

/// Wat de deel-extensie ("Knipsel" in het deelmenu, #18) en de app delen: de App Group, en per
/// gedeeld item één klein JSON-bestand in `Gedeeld/` naast de bestanden (afbeeldingen, PDF).
/// Dit bestand compileert in de app én in de extensie; het gebruikt alleen Foundation.
///
/// Waarom een los bestand per item en niet direct `inbox.json`: de app kan tegelijk met de extensie
/// de inbox bijwerken. Zo schrijft de extensie nooit in het bestand van de app, en neemt de app de
/// gedeelde items over zodra hij (weer) op de voorgrond komt.
enum DeelGroep {
    static let identifier = "group.com.peterbijkerk.knipsel"
    /// Submap van de inbox met de nog niet overgenomen items.
    static let postMap = "Gedeeld"

    /// `Inlezen` in de gedeelde container, of nil als de App Group niet beschikbaar is (bijvoorbeeld
    /// een build zonder signing).
    static var inboxMap: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)?
            .appending(path: "Inlezen", directoryHint: .isDirectory)
    }
}

/// Wat er gedeeld is. Spiegelt `InleesItem.Bron`; bestandsnamen staan in de map van de inbox.
enum DeelBron: Codable, Equatable, Sendable {
    case link(URL)
    case tekst(String)
    case afbeeldingen([String])
    case pdf(String)
}

/// Eén gedeeld item, zoals de extensie het schrijft. Alleen de bron: ophalen, inlezen en indelen
/// doet de app (de extensie heeft weinig geheugen en mag niet lang bezig zijn).
struct DeelPost: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var datum = Date.now
    var bron: DeelBron
    /// De pagina waar gedeelde tekst vandaan kwam (Safari stuurt de link mee).
    var bronURL: URL?
}

/// Lezen en schrijven van `DeelPost`s in een map (in de app: de map van de inbox).
struct DeelBus: Sendable {
    let map: URL

    var postMap: URL { map.appending(path: DeelGroep.postMap, directoryHint: .isDirectory) }

    /// Een bestand (afbeelding, PDF) in de map zetten; geeft de bestandsnaam terug.
    func bewaarBestand(_ data: Data, extensie: String) throws -> String {
        try FileManager.default.createDirectory(at: map, withIntermediateDirectories: true)
        let naam = "\(UUID().uuidString).\(extensie)"
        try data.write(to: map.appending(path: naam), options: .atomic)
        return naam
    }

    /// Een bestaand bestand (van de deelbron) naar de map kopiëren, zonder het in te lezen.
    func kopieer(_ bestand: URL, extensie: String) throws -> String {
        try FileManager.default.createDirectory(at: map, withIntermediateDirectories: true)
        let naam = "\(UUID().uuidString).\(extensie.isEmpty ? "dat" : extensie.lowercased())"
        try FileManager.default.copyItem(at: bestand, to: map.appending(path: naam))
        return naam
    }

    /// Als laatste: pas als het JSON-bestand er staat, ziet de app het item.
    func schrijf(_ post: DeelPost) throws {
        try FileManager.default.createDirectory(at: postMap, withIntermediateDirectories: true)
        try Self.encoder.encode(post).write(to: postMap.appending(path: "\(post.id.uuidString).json"), options: .atomic)
    }

    /// Alle wachtende posts, oudste eerst, met hun bestand (om na overnemen te verwijderen).
    func posts() -> [(post: DeelPost, bestand: URL)] {
        let bestanden =
            (try? FileManager.default.contentsOfDirectory(at: postMap, includingPropertiesForKeys: nil)) ?? []
        return bestanden.filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                    let post = try? Self.decoder.decode(DeelPost.self, from: data)
                else { return nil }
                return (post, url)
            }
            .sorted { $0.post.datum < $1.post.datum }
    }

    /// Een onleesbaar bestand in `Gedeeld/` (half geschreven of kapot): weg na een dag.
    func ruimOnleesbareOp(ouderDan grens: Date) {
        let leesbaar = Set(posts().map(\.bestand.lastPathComponent))
        let bestanden =
            (try? FileManager.default.contentsOfDirectory(
                at: postMap, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for url in bestanden where !leesbaar.contains(url.lastPathComponent) {
            let datum = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let datum, datum < grens { try? FileManager.default.removeItem(at: url) }
        }
    }

    private static let encoder: JSONEncoder = {
        // Standaard datumcodering (een getal, tot op de microseconde): twee items die vlak na elkaar
        // gedeeld zijn, houden hun volgorde.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()
}
