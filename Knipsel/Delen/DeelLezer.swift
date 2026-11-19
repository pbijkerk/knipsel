import Foundation
import OSLog
import UIKit
import UniformTypeIdentifiers

/// Wat één `NSItemProvider` uit het deelmenu levert.
enum DeelSoort: Sendable, Equatable {
    case link
    case tekst
    case afbeelding
    case pdf
}

/// De keuze wat er van een gedeeld item in Knipsel komt. Puur (alleen types, links en tekst), zodat
/// het zonder deelmenu te testen is. Volgorde tussen items: link > korte tekst met een link erin >
/// tekst > afbeelding(en) > PDF. Uitzondering: een lange geselecteerde tekst (een heel recept) gaat
/// vóór een meegestuurde link; die link blijft dan de bron.
enum DeelKeuze {
    static let maxAfbeeldingen = 5
    /// Meer dan dit geldt als een geselecteerd recept, niet als een deelbericht met een link.
    static let langeTekstRegels = 8
    static let langeTekstTekens = 300
    static let maxTekstTekens = 100_000

    /// Wat een item is, op grond van zijn types. Binnen één item gaat de inhoud vóór het adres: een
    /// gedeelde afbeelding of PDF met ook een (bestands)link is een afbeelding of PDF.
    static func soort(_ typeIdentifiers: [String]) -> DeelSoort? {
        let types = typeIdentifiers.compactMap { UTType($0) }
        if types.contains(where: { $0.conforms(to: .pdf) }) { return .pdf }
        if types.contains(where: { $0.conforms(to: .image) }) { return .afbeelding }
        if types.contains(where: { $0.conforms(to: .url) && !$0.conforms(to: .fileURL) }) { return .link }
        if types.contains(where: { $0.conforms(to: .plainText) }) { return .tekst }
        if types.contains(where: { $0.conforms(to: .text) && !$0.conforms(to: .html) }) { return .tekst }
        return nil
    }

    /// Uit links en teksten de bron (en bij tekst de pagina waar hij vandaan komt); nil als er geen
    /// bruikbare link of tekst bij zit (dan komen afbeeldingen en PDF aan de beurt).
    static func kies(links: [URL], teksten: [String]) -> (bron: DeelBron, bronURL: URL?)? {
        let webLinks = links.filter(isWebLink)
        let teksten = teksten.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxTekstTekens)) }
            .filter { !$0.isEmpty }
        if let lang = teksten.first(where: isLangeTekst) {
            return (.tekst(lang), webLinks.first ?? eersteLink(in: lang))
        }
        if let link = webLinks.first { return (.link(link), nil) }
        if let link = teksten.lazy.compactMap(eersteLink).first { return (.link(link), nil) }
        if let tekst = teksten.first { return (.tekst(tekst), nil) }
        return nil
    }

    static func isWebLink(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host() != nil
    }

    /// De eerste http(s)-link in een tekst ("Lees dit recept: https://…").
    static func eersteLink(in tekst: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let bereik = NSRange(tekst.startIndex..., in: tekst)
        return detector.matches(in: tekst, range: bereik).lazy.compactMap(\.url).first(where: isWebLink)
    }

    /// Een heel recept (veel regels tekst), geen deelbericht met een link.
    static func isLangeTekst(_ tekst: String) -> Bool {
        var zonderLinks = tekst
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            zonderLinks = detector.stringByReplacingMatches(
                in: tekst, range: NSRange(tekst.startIndex..., in: tekst), withTemplate: "")
        }
        let regels = zonderLinks.split(whereSeparator: \.isNewline)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return regels.count >= langeTekstRegels && zonderLinks.count >= langeTekstTekens
    }
}

/// Hoe het delen afliep: wat de extensie daarna toont (audit v0.1, #5).
enum DeelUitkomst: Equatable {
    case toegevoegd(DeelPost)
    /// Er zat niets bruikbaars bij (geen link, tekst, afbeelding of PDF).
    case niets
    /// Er zaten afbeeldingen of een PDF bij, maar het kopiëren naar Knipsel lukte niet.
    case nietOvergenomen(DeelSoort, aantal: Int)
    /// Wel gelezen, maar het bewaren in de map voor Knipsel lukte niet.
    case nietBewaard

    var post: DeelPost? {
        if case .toegevoegd(let post) = self { return post }
        return nil
    }

    /// Puur: uit wat er gelezen is en wat erbij zat.
    static func bepaal(post: DeelPost?, soorten: [DeelSoort?], schrijvenMislukt: Bool) -> DeelUitkomst {
        if schrijvenMislukt { return .nietBewaard }
        if let post { return .toegevoegd(post) }
        let afbeeldingen = soorten.filter { $0 == .afbeelding }.count
        if afbeeldingen > 0 {
            return .nietOvergenomen(.afbeelding, aantal: min(afbeeldingen, DeelKeuze.maxAfbeeldingen))
        }
        if soorten.contains(.pdf) { return .nietOvergenomen(.pdf, aantal: 1) }
        return .niets
    }
}

/// Leest de `NSItemProvider`s van het deelmenu en zet het resultaat als `DeelPost` in de map. Doet
/// niets zwaars: geen netwerk, geen tekstherkenning; afbeeldingen en PDF's worden als bestand
/// gekopieerd (alleen een los aangeleverd beeld wordt als JPEG bewaard).
@MainActor
struct DeelLezer {
    let bus: DeelBus

    /// Alleen soorten en foutcodes, nooit inhoud, adressen of bestandsnamen.
    nonisolated static let logger = Logger(subsystem: "com.peterbijkerk.knipsel", category: "Delen")

    /// Leest, schrijft en geeft het item terug; nil als er niets bruikbaars bij zat of iets mislukte.
    func lees(_ providers: [NSItemProvider]) async -> DeelPost? {
        await verwerk(providers).post
    }

    /// Leest en schrijft, en zegt hoe het afliep.
    func verwerk(_ providers: [NSItemProvider]) async -> DeelUitkomst {
        let ingedeeld = providers.map { ($0, DeelKeuze.soort($0.registeredTypeIdentifiers)) }
        let bus = bus
        var links: [URL] = []
        var teksten: [String] = []
        for (provider, soort) in ingedeeld {
            switch soort {
            case .link:
                var url = await withCheckedContinuation { vervolg in
                    Self.laadURL(provider) { vervolg.resume(returning: $0) }
                }
                if url == nil {
                    url = await withCheckedContinuation { vervolg in
                        Self.laadURLItem(provider) { vervolg.resume(returning: $0) }
                    }
                }
                if let url { links.append(url) }
            case .tekst:
                let tekst = await withCheckedContinuation { vervolg in
                    Self.laadTekst(provider) { vervolg.resume(returning: $0) }
                }
                if let tekst { teksten.append(tekst) }
            default: break
            }
        }
        var post: DeelPost?
        if let keuze = DeelKeuze.kies(links: links, teksten: teksten) {
            post = DeelPost(bron: keuze.bron, bronURL: keuze.bronURL)
        } else {
            var namen: [String] = []
            for (provider, soort) in ingedeeld where soort == .afbeelding && namen.count < DeelKeuze.maxAfbeeldingen {
                let type = Self.afbeeldingType(provider)
                var naam = await withCheckedContinuation { vervolg in
                    Self.kopieerBestand(provider, type: type, bus: bus) { vervolg.resume(returning: $0) }
                }
                if naam == nil {
                    naam = await withCheckedContinuation { vervolg in
                        Self.laadAfbeeldingItem(provider, type: type, bus: bus) { vervolg.resume(returning: $0) }
                    }
                }
                if let naam { namen.append(naam) }
            }
            if !namen.isEmpty {
                post = DeelPost(bron: .afbeeldingen(namen))
            } else {
                for (provider, soort) in ingedeeld where soort == .pdf {
                    let naam = await withCheckedContinuation { vervolg in
                        Self.kopieerBestand(provider, type: .pdf, bus: bus) { vervolg.resume(returning: $0) }
                    }
                    if let naam {
                        post = DeelPost(bron: .pdf(naam))
                        break
                    }
                }
            }
        }
        guard let post else {
            let uitkomst = DeelUitkomst.bepaal(post: nil, soorten: ingedeeld.map(\.1), schrijvenMislukt: false)
            if case .nietOvergenomen(let soort, let aantal) = uitkomst {
                Self.logger.error("Delen: \(aantal) \(String(describing: soort), privacy: .public) niet overgenomen")
            }
            return uitkomst
        }
        do {
            try bus.schrijf(post)
            return .toegevoegd(post)
        } catch {
            Self.log(error, bij: "bewaren van het gedeelde item")
            return .nietBewaard
        }
    }

    /// Type, domein en code van een fout; geen inhoud.
    nonisolated static func log(_ fout: any Error, bij wat: String) {
        let ns = fout as NSError
        logger.error(
            "Delen: \(wat, privacy: .public) mislukt: \(String(describing: type(of: fout)), privacy: .public) \(ns.domain, privacy: .public) \(ns.code)"
        )
    }

    /// `try?` met een logregel bij een fout.
    nonisolated static func probeer<T>(_ wat: String, _ werk: () throws -> T) -> T? {
        do {
            return try werk()
        } catch {
            log(error, bij: wat)
            return nil
        }
    }

    // De completion handlers van NSItemProvider komen op een achtergrondrij: daarom synchrone
    // `nonisolated` helpers met een `@Sendable` terugroep, zodat geen closure aan de main actor vastzit.

    nonisolated static func laadURL(_ provider: NSItemProvider, klaar: @escaping @Sendable (URL?) -> Void) {
        // Een als object geregistreerde URL (de meeste apps) komt via loadObject goed terug; loadItem
        // geeft dan alleen de gecodeerde data.
        guard provider.canLoadObject(ofClass: NSURL.self) else { return klaar(nil) }
        _ = provider.loadObject(ofClass: NSURL.self) { object, fout in
            if let fout { log(fout, bij: "link laden") }
            klaar(object as? URL)
        }
    }

    nonisolated static func laadURLItem(_ provider: NSItemProvider, klaar: @escaping @Sendable (URL?) -> Void) {
        provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, fout in
            if let fout { log(fout, bij: "link laden (item)") }
            switch item {
            case let url as URL: klaar(url)
            case let data as Data: klaar(URL(dataRepresentation: data, relativeTo: nil))
            case let tekst as String: klaar(URL(string: tekst))
            default: klaar(nil)
            }
        }
    }

    nonisolated static func laadTekst(_ provider: NSItemProvider, klaar: @escaping @Sendable (String?) -> Void) {
        let type =
            provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
            ? UTType.plainText.identifier
            : provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .text) == true }
        guard let type else { return klaar(nil) }
        provider.loadItem(forTypeIdentifier: type, options: nil) { item, fout in
            if let fout { log(fout, bij: "tekst laden") }
            switch item {
            case let tekst as String: klaar(tekst)
            case let tekst as NSAttributedString: klaar(tekst.string)
            case let data as Data: klaar(String(data: data, encoding: .utf8))
            case let url as URL where url.isFileURL:
                klaar(probeer("tekstbestand lezen") { try String(contentsOf: url, encoding: .utf8) })
            default: klaar(nil)
            }
        }
    }

    nonisolated static func afbeeldingType(_ provider: NSItemProvider) -> UTType {
        provider.registeredTypeIdentifiers.compactMap { UTType($0) }.first { $0.conforms(to: .image) } ?? .image
    }

    /// Terugval als er geen bestand is: sommige apps (Markeringen, schermafdruk) leveren alleen een
    /// beeld in het geheugen of als data.
    nonisolated static func laadAfbeeldingItem(
        _ provider: NSItemProvider, type: UTType, bus: DeelBus, klaar: @escaping @Sendable (String?) -> Void
    ) {
        provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, fout in
            if let fout { log(fout, bij: "afbeelding laden (item)") }
            switch item {
            case let url as URL where url.isFileURL:
                klaar(probeer("afbeelding kopiëren") { try bus.kopieer(url, extensie: url.pathExtension) })
            case let data as Data:
                klaar(
                    probeer("afbeelding bewaren") {
                        try bus.bewaarBestand(data, extensie: type.preferredFilenameExtension ?? "jpg")
                    })
            case let beeld as UIImage:
                guard let jpeg = beeld.jpegData(compressionQuality: 0.9) else {
                    logger.error("Delen: afbeelding omzetten naar JPEG mislukt")
                    return klaar(nil)
                }
                klaar(probeer("afbeelding bewaren") { try bus.bewaarBestand(jpeg, extensie: "jpg") })
            case nil:
                klaar(nil)
            case let ander?:
                logger.error(
                    "Delen: afbeelding als onbekend type: \(String(describing: Swift.type(of: ander)), privacy: .public)"
                )
                klaar(nil)
            }
        }
    }

    /// Het bestand zelf kopiëren (zonder het in te lezen: zuinig met geheugen).
    nonisolated static func kopieerBestand(
        _ provider: NSItemProvider, type: UTType, bus: DeelBus, klaar: @escaping @Sendable (String?) -> Void
    ) {
        guard provider.hasItemConformingToTypeIdentifier(type.identifier) else { return klaar(nil) }
        _ = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, fout in
            if let fout { log(fout, bij: "bestand laden (\(type.identifier))") }
            // Het tijdelijke bestand bestaat alleen binnen deze handler.
            klaar(
                url.flatMap { url in
                    probeer("bestand kopiëren (\(type.identifier))") {
                        try bus.kopieer(
                            url,
                            extensie: url.pathExtension.isEmpty
                                ? (type.preferredFilenameExtension ?? "dat") : url.pathExtension)
                    }
                })
        }
    }
}
