import Foundation
import Observation
import OSLog

/// Eén item in "Nog te controleren": iets om in te lezen (een link, tekst, afbeeldingen of een PDF)
/// en hoe ver dat is. Niets hiervan is al een recept: dat wordt het pas na het controlescherm.
struct InleesItem: Codable, Identifiable, Equatable, Sendable {
    enum Bron: Codable, Equatable, Sendable {
        case link(URL)
        case tekst(String)
        /// Bestandsnamen in de map van de inbox.
        case afbeeldingen([String])
        case pdf(String)
    }

    enum Status: Codable, Equatable, Sendable {
        case wachten
        case bezig
        case klaar(InleesResultaat)
        /// Alleen een teaser: kies hoe je verder wilt (inloggen, tekst plakken, schermafdruk).
        case betaalmuur
        /// Afbeeldingen (of een PDF zonder tekstlaag): door de tekstherkenning en het knipselscherm.
        case herkennen([String])
        case mislukt(String)
    }

    var id = UUID()
    var bron: Bron
    var status = Status.wachten
    var datum = Date.now
    /// De receptfoto van de site (al verkleind, `GerechtFoto`), als bestand in de inbox.
    var foto: String?
    /// Naam en link van de site, ook als het recept via de betaalmuur-route alsnog binnenkomt.
    var bronNaam: String?
    var bronURL: URL?

    /// Kort, voor in de lijst.
    var titel: String {
        if case .klaar(let resultaat) = status, !resultaat.titel.isEmpty { return resultaat.titel }
        switch bron {
        case .link(let url): return bronNaam ?? ReceptInlezer.host(url) ?? url.absoluteString
        case .tekst(let tekst):
            let eerste = tekst.split(whereSeparator: \.isNewline).first.map(String.init) ?? tekst
            return eerste.count > 60 ? String(eerste.prefix(60)) + "…" : eerste
        case .afbeeldingen(let namen): return namen.count == 1 ? "Schermafdruk" : "\(namen.count) afbeeldingen"
        case .pdf: return "PDF"
        }
    }
}

/// "Nog te controleren": een kleine inbox als JSON-bestand plus losse bestanden (afbeeldingen,
/// PDF's, receptfoto's) in één map. De map is in te stellen, zodat de deel-extensie (deel 2 van #18)
/// hem later via een App Group kan vullen; nu is het Application Support van de app.
@MainActor
@Observable
final class InleesInbox {
    static let gedeeld = InleesInbox(map: standaardMap)

    static var standaardMap: URL {
        let basis =
            Opslag.draaitOnderTests
            ? FileManager.default.temporaryDirectory.appending(path: "KnipselTestInbox-\(UUID().uuidString)")
            : URL.applicationSupportDirectory
        return basis.appending(path: "Inlezen", directoryHint: .isDirectory)
    }

    let map: URL
    private(set) var items: [InleesItem] = []
    private let logger = Logger(subsystem: "com.peterbijkerk.knipsel", category: "Inlezen")

    init(map: URL) {
        self.map = map
        laad(naHerstart: true)
    }

    private var bestand: URL { map.appending(path: "inbox.json") }

    /// Wat nog aandacht vraagt (alles behalve een item dat nu verwerkt wordt telt mee).
    var aantal: Int { items.count }

    func item(_ id: InleesItem.ID) -> InleesItem? {
        items.first { $0.id == id }
    }

    // MARK: - Wijzigen

    @discardableResult
    func voegToe(_ bron: InleesItem.Bron, datum: Date = .now) -> InleesItem {
        let item = InleesItem(bron: bron, datum: datum)
        items.insert(item, at: 0)
        bewaar()
        return item
    }

    func werkBij(_ id: InleesItem.ID, _ wijzig: (inout InleesItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        wijzig(&items[index])
        bewaar()
    }

    /// Weg uit de inbox, met de bestanden erbij (afbeeldingen, PDF, foto).
    func verwijder(_ id: InleesItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: index)
        for naam in bestanden(van: item) {
            try? FileManager.default.removeItem(at: url(van: naam))
        }
        bewaar()
    }

    private func bestanden(van item: InleesItem) -> [String] {
        var namen: [String] = item.foto.map { [$0] } ?? []
        switch item.bron {
        case .afbeeldingen(let lijst): namen += lijst
        case .pdf(let naam): namen.append(naam)
        default: break
        }
        if case .herkennen(let lijst) = item.status { namen += lijst }
        return namen
    }

    // MARK: - Bestanden

    /// Bewaart `data` als nieuw bestand in de inbox en geeft de naam terug.
    func bewaarBestand(_ data: Data, extensie: String) throws -> String {
        try maakMap()
        let naam = "\(UUID().uuidString).\(extensie)"
        try data.write(to: url(van: naam), options: .atomic)
        return naam
    }

    func url(van naam: String) -> URL {
        map.appending(path: naam)
    }

    func data(van naam: String) -> Data? {
        try? Data(contentsOf: url(van: naam))
    }

    // MARK: - Opslag

    /// Opnieuw lezen van schijf (bijvoorbeeld als de deel-extensie iets heeft toegevoegd). Na een
    /// herstart wacht een item dat "bezig" was weer; tijdens het gebruik blijft het bezig.
    func laad(naHerstart: Bool = false) {
        guard let data = try? Data(contentsOf: bestand) else {
            items = []
            return
        }
        do {
            items = try Self.decoder.decode([InleesItem].self, from: data).map { item in
                var item = item
                if naHerstart, item.status == .bezig { item.status = .wachten }
                return item
            }
        } catch {
            logger.error("Inbox onleesbaar: \(error.localizedDescription, privacy: .public)")
            items = []
        }
    }

    private func bewaar() {
        do {
            try maakMap()
            try Self.encoder.encode(items).write(to: bestand, options: .atomic)
        } catch {
            logger.error("Inbox bewaren mislukt: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func maakMap() throws {
        try FileManager.default.createDirectory(at: map, withIntermediateDirectories: true)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
