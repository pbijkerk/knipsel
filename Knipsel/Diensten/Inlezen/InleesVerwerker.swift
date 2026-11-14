import Foundation
import OSLog
import PDFKit
import UIKit

/// Verwerkt items in "Nog te controleren": ophalen, inlezen, de receptfoto van de site (als dat aan
/// staat) en de uitkomst terug in de inbox. Niets wordt hier als recept bewaard; dat gebeurt pas na
/// het controlescherm.
@MainActor
struct InleesVerwerker {
    let inbox: InleesInbox
    var ophaler: any PaginaOphaler = WebOphaler()
    var indeler: @MainActor () -> any Indeler = { IndelerKeuze.standaard() }
    var fotoBewaren: Bool = InleesVerwerker.fotoBewarenStandaard

    private let logger = Logger(subsystem: "com.peterbijkerk.knipsel", category: "Inlezen")

    /// Instellingen › Inlezen: "Foto van receptsites bewaren" (standaard aan, #18 besluit 1).
    static var fotoBewarenStandaard: Bool {
        UserDefaults.standard.object(forKey: AppConfiguratie.sleutelWebFotoBewaren) as? Bool ?? true
    }

    /// Alles wat nog wacht (bij het openen van de app).
    func verwerkWachtende(categorieen: [String], labels: [String]) async {
        for item in inbox.items where item.status == .wachten {
            await verwerk(item.id, categorieen: categorieen, labels: labels)
        }
    }

    func verwerk(_ id: InleesItem.ID, categorieen: [String], labels: [String]) async {
        guard let item = inbox.item(id), item.status != .bezig else { return }
        inbox.werkBij(id) { $0.status = .bezig }
        switch item.bron {
        case .link(let url):
            do {
                let pagina = try await ophaler.pagina(url)
                await verwerk(html: pagina.html, url: pagina.url, id: id, categorieen: categorieen, labels: labels)
            } catch {
                logger.info("Ophalen mislukt: \(error.localizedDescription, privacy: .public)")
                inbox.werkBij(id) {
                    $0.bronNaam = ReceptInlezer.host(url)
                    $0.bronURL = url
                    $0.status = .mislukt("De pagina kon niet worden opgehaald. \(Self.melding(error))")
                }
            }
        case .tekst(let tekst):
            if let url = ReceptInlezer.link(in: tekst) {
                inbox.werkBij(id) {
                    $0.bron = .link(url)
                    $0.status = .wachten
                }
                await verwerk(id, categorieen: categorieen, labels: labels)
                return
            }
            let uitkomst = await ReceptInlezer.lees(
                tekst: tekst, categorieen: categorieen, labels: labels, indeler: indeler())
            await pasToe(uitkomst, id: id)
        case .pdf(let naam):
            guard let data = inbox.data(van: naam), let document = PDFDocument(data: data) else {
                inbox.werkBij(id) { $0.status = .mislukt("De PDF kon niet worden geopend.") }
                return
            }
            let tekst = PDFLezer.tekst(document)
            if tekst.count >= PDFLezer.minTekens {
                let uitkomst = await ReceptInlezer.lees(
                    tekst: tekst, categorieen: categorieen, labels: labels, indeler: indeler())
                await pasToe(uitkomst, id: id)
            } else {
                // Geen tekstlaag (een scan): pagina's als afbeelding door de tekstherkenning.
                let namen = PDFLezer.paginas(document).compactMap { beeld in
                    beeld.jpegData(compressionQuality: 0.85).flatMap { try? inbox.bewaarBestand($0, extensie: "jpg") }
                }
                inbox.werkBij(id) {
                    $0.status =
                        namen.isEmpty
                        ? .mislukt("In deze PDF staat geen tekst die Knipsel kan lezen.") : .herkennen(namen)
                }
            }
        case .afbeeldingen(let namen):
            inbox.werkBij(id) { $0.status = .herkennen(namen) }
        }
    }

    /// Een pagina die al binnen is: opgehaald, of gelezen uit de inlogweergave in Knipsel.
    func verwerk(html: String, url: URL?, id: InleesItem.ID, categorieen: [String], labels: [String]) async {
        inbox.werkBij(id) { $0.status = .bezig }
        let uitkomst = await ReceptInlezer.lees(
            html: html, url: url, categorieen: categorieen, labels: labels, indeler: indeler())
        inbox.werkBij(id) {
            $0.bronURL = url ?? $0.bronURL
            $0.bronNaam = ReceptInlezer.siteNaam(html: html, url: url) ?? $0.bronNaam
        }
        await pasToe(uitkomst, id: id)
    }

    private func pasToe(_ uitkomst: InleesUitkomst, id: InleesItem.ID) async {
        switch uitkomst {
        case .recept(var resultaat):
            let item = inbox.item(id)
            if resultaat.bronNaam.isEmpty, let naam = item?.bronNaam { resultaat.bronNaam = naam }
            if resultaat.bronURL == nil { resultaat.bronURL = item?.bronURL }
            var foto: String?
            if fotoBewaren, item?.foto == nil, let url = resultaat.afbeeldingURL {
                foto = await haalFoto(url)
            }
            inbox.werkBij(id) {
                if let foto { $0.foto = foto }
                $0.status = .klaar(resultaat)
            }
        case .betaalmuur:
            inbox.werkBij(id) { $0.status = .betaalmuur }
        case .geenRecept(let reden):
            inbox.werkBij(id) { $0.status = .mislukt(reden) }
        }
    }

    /// Eén receptfoto van de site, bijgesneden en verkleind zoals een eigen gerechtfoto.
    private func haalFoto(_ url: URL) async -> String? {
        do {
            let data = try await ophaler.data(url)
            guard let jpeg = GerechtFoto.maakData(van: data) else { return nil }
            return try inbox.bewaarBestand(jpeg, extensie: "jpg")
        } catch {
            logger.info("Receptfoto niet opgehaald: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func melding(_ fout: any Error) -> String {
        if let fout = fout as? OphaalFout { return fout.errorDescription ?? "" }
        if (fout as? URLError)?.code == .timedOut { return "De site reageerde niet binnen 20 seconden." }
        if (fout as? URLError)?.code == .notConnectedToInternet { return "Er is geen internetverbinding." }
        return ""
    }
}

/// Tekst uit een PDF (PDFKit); zonder tekstlaag de pagina's als afbeelding voor Vision.
enum PDFLezer {
    /// Minder tekens dan dit: geen bruikbare tekstlaag.
    static let minTekens = 40
    static let maxPaginas = 4

    static func tekst(_ document: PDFDocument) -> String {
        (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// De eerste pagina's als beeld, lange zijde ± `AppConfiguratie.maxFotoZijde`.
    static func paginas(_ document: PDFDocument) -> [UIImage] {
        (0..<min(document.pageCount, maxPaginas)).compactMap { index in
            guard let pagina = document.page(at: index) else { return nil }
            let kader = pagina.bounds(for: .mediaBox)
            guard kader.width > 0, kader.height > 0 else { return nil }
            let schaal = AppConfiguratie.maxFotoZijde / max(kader.width, kader.height)
            return pagina.thumbnail(
                of: CGSize(width: kader.width * schaal, height: kader.height * schaal), for: .mediaBox)
        }
    }
}
