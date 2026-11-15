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
/// PDF's, receptfoto's) in één map. Die map staat in de App Group, zodat de deel-extensie er items
/// in kan zetten (`DeelPost`, #18); zonder App Group (een build zonder signing) is het Application
/// Support van de app.
@MainActor
@Observable
final class InleesInbox {
    static let gedeeld: InleesInbox = {
        let map = standaardMap
        if !Opslag.draaitOnderTests, map != oudeMap {
            migreer(van: oudeMap, naar: map)
        }
        return InleesInbox(map: map)
    }()

    static var standaardMap: URL {
        if Opslag.draaitOnderTests {
            return FileManager.default.temporaryDirectory.appending(path: "KnipselTestInbox-\(UUID().uuidString)")
                .appending(path: "Inlezen", directoryHint: .isDirectory)
        }
        return DeelGroep.inboxMap ?? oudeMap
    }

    /// Waar de inbox stond vóór de deel-extensie (deel 1 van #18).
    static var oudeMap: URL {
        URL.applicationSupportDirectory.appending(path: "Inlezen", directoryHint: .isDirectory)
    }

    /// Eenmalig: items en bestanden uit de oude map naar de nieuwe. Staat er in de nieuwe map al een
    /// inbox, dan worden de items samengevoegd (op id). Daarna is de oude map weg.
    static func migreer(van oud: URL, naar nieuw: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: oud.path()) else { return }
        let logger = Logger(subsystem: "com.peterbijkerk.knipsel", category: "Inlezen")
        do {
            try fm.createDirectory(at: nieuw, withIntermediateDirectories: true)
            for bestand in try fm.contentsOfDirectory(at: oud, includingPropertiesForKeys: nil) {
                let doel = nieuw.appending(path: bestand.lastPathComponent)
                if bestand.lastPathComponent == "inbox.json", fm.fileExists(atPath: doel.path()) {
                    let oudeItems =
                        (try? Data(contentsOf: bestand)).flatMap { try? decoder.decode([InleesItem].self, from: $0) }
                        ?? []
                    let nieuweItems =
                        (try? Data(contentsOf: doel)).flatMap { try? decoder.decode([InleesItem].self, from: $0) } ?? []
                    let bekend = Set(nieuweItems.map(\.id))
                    let samen = (nieuweItems + oudeItems.filter { !bekend.contains($0.id) }).sorted {
                        $0.datum > $1.datum
                    }
                    try encoder.encode(samen).write(to: doel, options: .atomic)
                } else if !fm.fileExists(atPath: doel.path()) {
                    try fm.moveItem(at: bestand, to: doel)
                }
            }
            try fm.removeItem(at: oud)
        } catch {
            logger.error("Inbox verhuizen mislukt: \(error.localizedDescription, privacy: .public)")
        }
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

    // MARK: - Uit het deelmenu

    /// Neemt wat via het deelmenu binnenkwam over als wachtend item (de verwerker leest het daarna
    /// in). Geeft het aantal nieuwe items terug.
    @discardableResult
    func neemGedeeldOver() -> Int {
        let bus = DeelBus(map: map)
        var nieuw = 0
        for (post, bestand) in bus.posts() {
            if item(post.id) == nil {
                var item = InleesItem(id: post.id, bron: Self.bron(post.bron), datum: post.datum)
                item.bronURL = post.bronURL
                item.bronNaam = post.bronURL.flatMap(ReceptInlezer.host)
                let plek = items.firstIndex { $0.datum < item.datum } ?? items.endIndex
                items.insert(item, at: plek)
                nieuw += 1
            }
            try? FileManager.default.removeItem(at: bestand)
        }
        if nieuw > 0 { bewaar() }
        return nieuw
    }

    static func bron(_ bron: DeelBron) -> InleesItem.Bron {
        switch bron {
        case .link(let url): .link(url)
        case .tekst(let tekst): .tekst(tekst)
        case .afbeeldingen(let namen): .afbeeldingen(namen)
        case .pdf(let naam): .pdf(naam)
        }
    }

    /// Bestanden waar geen item (meer) naar verwijst, bijvoorbeeld van een deelpoging die halverwege
    /// stopte. Alleen ouder dan `grens`: de extensie schrijft het bestand vóór haar item.
    func ruimOp(ouderDan grens: Date = .now.addingTimeInterval(-3600)) {
        let bus = DeelBus(map: map)
        var inGebruik = Set(items.flatMap(bestanden(van:)))
        for (post, _) in bus.posts() {
            switch post.bron {
            case .afbeeldingen(let namen): inGebruik.formUnion(namen)
            case .pdf(let naam): inGebruik.insert(naam)
            default: break
            }
        }
        let fm = FileManager.default
        let inhoud =
            (try? fm.contentsOfDirectory(
                at: map, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey]))
            ?? []
        for url in inhoud {
            let waarden = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isDirectoryKey])
            guard waarden?.isDirectory != true, url.lastPathComponent != "inbox.json",
                !inGebruik.contains(url.lastPathComponent), let datum = waarden?.contentModificationDate, datum < grens
            else { continue }
            try? fm.removeItem(at: url)
        }
        bus.ruimOnleesbareOp(ouderDan: .now.addingTimeInterval(-86_400))
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
