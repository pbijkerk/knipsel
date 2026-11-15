import Foundation
import PDFKit
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import Knipsel

/// Een recept als in een gedeelde tekst of PDF (verzonnen).
private let smoothie = """
    Groene smoothie

    Voor 2 personen.

    1 banaan
    2 handjes spinazie
    250 ml amandelmelk

    1. Doe alles in de blender.
    2. Mix tot het glad is.
    """

private func tijdelijkeMap() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "DelenTest-\(UUID().uuidString)")
        .appending(path: "Inlezen", directoryHint: .isDirectory)
}

private func rodeAfbeelding() -> Data {
    UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30)).image { context in
        UIColor.red.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
    }.pngData()!
}

/// Een PDF met een tekstlaag, als bestand.
private func pdfBestand(tekst: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "DelenTest-\(UUID().uuidString).pdf")
    let data = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 420, height: 600)).pdfData { context in
        context.beginPage()
        (tekst as NSString).draw(
            in: CGRect(x: 20, y: 20, width: 380, height: 560), withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
    }
    try data.write(to: url)
    return url
}

struct DeelKeuzeTests {
    @Test func soortUitTypes() {
        #expect(DeelKeuze.soort([UTType.url.identifier]) == .link)
        #expect(DeelKeuze.soort(["public.url", "public.plain-text"]) == .link)
        #expect(DeelKeuze.soort(["public.utf8-plain-text"]) == .tekst)
        #expect(DeelKeuze.soort(["public.jpeg"]) == .afbeelding)
        #expect(DeelKeuze.soort(["public.heic", "public.file-url"]) == .afbeelding)
        #expect(DeelKeuze.soort(["com.adobe.pdf", "public.file-url"]) == .pdf)
        // Een bestandslink zonder bruikbaar type, of HTML zonder platte tekst: niets.
        #expect(DeelKeuze.soort(["public.file-url"]) == nil)
        #expect(DeelKeuze.soort(["public.html"]) == nil)
        #expect(DeelKeuze.soort(["com.apple.property-list"]) == nil)
    }

    @Test func volgorde() throws {
        let link = URL(string: "https://www.kookzender.test/recepten/soep")!
        let krant = URL(string: "https://krant.test/koken/stoof")!
        // Link gaat voor tekst.
        #expect(DeelKeuze.kies(links: [link], teksten: ["Soep"])?.bron == .link(link))
        // Een bestandslink is geen weblink.
        #expect(DeelKeuze.kies(links: [URL(filePath: "/tmp/x.txt")], teksten: ["Soep"])?.bron == .tekst("Soep"))
        // Korte tekst met een link erin (zoals een krantenapp deelt): de link.
        let bericht = "Bekijk dit recept: Stoofpot met pruimen https://krant.test/koken/stoof"
        #expect(DeelKeuze.kies(links: [], teksten: ["Soep", bericht])?.bron == .link(krant))
        // Alleen tekst.
        #expect(DeelKeuze.kies(links: [], teksten: ["  \(smoothie)\n "])?.bron == .tekst(smoothie))
        // Niets bruikbaars: nil (dan afbeeldingen of PDF).
        #expect(DeelKeuze.kies(links: [], teksten: ["  \n"]) == nil)
        #expect(DeelKeuze.kies(links: [URL(string: "mailto:a@b.test")!], teksten: []) == nil)
    }

    @Test func langeGeselecteerdeTekstGaatVoorDeLink() throws {
        let link = URL(string: "https://krant.test/koken/stoof")!
        let recept =
            smoothie
            + "\n3. Schenk in twee glazen en drink meteen op, dan blijft de kleur mooi groen.\n"
            + "Tip: lekker met een stukje verse gember erbij, of vervang de amandelmelk door havermelk.\n"
        #expect(DeelKeuze.isLangeTekst(recept))
        let keuze = try #require(DeelKeuze.kies(links: [link], teksten: [recept]))
        guard case .tekst = keuze.bron else {
            Issue.record("Geen tekst: \(keuze.bron)")
            return
        }
        #expect(keuze.bronURL == link)
        // Een kort deelbericht is geen lange tekst.
        #expect(!DeelKeuze.isLangeTekst("Stoofpot met pruimen\nVan de krant\nhttps://krant.test/koken/stoof"))
    }
}

@MainActor
struct DeelLezerTests {
    @Test func linkUitHetDeelmenu() async throws {
        let map = tijdelijkeMap()
        defer { try? FileManager.default.removeItem(at: map.deletingLastPathComponent()) }
        let url = URL(string: "https://www.kookzender.test/recepten/snelle-tomatensoep")!
        let post = try #require(await DeelLezer(bus: DeelBus(map: map)).lees([NSItemProvider(object: url as NSURL)]))
        #expect(post.bron == .link(url))
        #expect(DeelBus(map: map).posts().map(\.post.id) == [post.id])
        #expect(DeelBus(map: map).posts().first?.post.bron == .link(url))
    }

    @Test func tekstUitHetDeelmenu() async throws {
        let map = tijdelijkeMap()
        defer { try? FileManager.default.removeItem(at: map.deletingLastPathComponent()) }
        let post = try #require(
            await DeelLezer(bus: DeelBus(map: map)).lees([NSItemProvider(object: smoothie as NSString)]))
        #expect(post.bron == .tekst(smoothie))
    }

    @Test func afbeeldingenWordenBestanden() async throws {
        let map = tijdelijkeMap()
        defer { try? FileManager.default.removeItem(at: map.deletingLastPathComponent()) }
        let providers = (0..<6).map { _ in
            NSItemProvider(item: rodeAfbeelding() as NSData, typeIdentifier: UTType.png.identifier)
        }
        let post = try #require(await DeelLezer(bus: DeelBus(map: map)).lees(providers))
        guard case .afbeeldingen(let namen) = post.bron else {
            Issue.record("Geen afbeeldingen: \(post.bron)")
            return
        }
        #expect(namen.count == DeelKeuze.maxAfbeeldingen)
        for naam in namen {
            #expect(UIImage(data: try Data(contentsOf: map.appending(path: naam))) != nil)
        }
    }

    @Test func pdfWordtGekopieerd() async throws {
        let map = tijdelijkeMap()
        defer { try? FileManager.default.removeItem(at: map.deletingLastPathComponent()) }
        let bron = try pdfBestand(tekst: smoothie)
        defer { try? FileManager.default.removeItem(at: bron) }
        let provider = try #require(NSItemProvider(contentsOf: bron))
        let post = try #require(await DeelLezer(bus: DeelBus(map: map)).lees([provider]))
        guard case .pdf(let naam) = post.bron else {
            Issue.record("Geen PDF: \(post.bron)")
            return
        }
        #expect(naam.hasSuffix(".pdf"))
        #expect(try Data(contentsOf: map.appending(path: naam)) == Data(contentsOf: bron))
    }

    @Test func linkGaatVoorAfbeelding() async throws {
        let map = tijdelijkeMap()
        defer { try? FileManager.default.removeItem(at: map.deletingLastPathComponent()) }
        let url = URL(string: "https://www.kookzender.test/recepten/soep")!
        let post = try #require(
            await DeelLezer(bus: DeelBus(map: map)).lees([
                NSItemProvider(item: rodeAfbeelding() as NSData, typeIdentifier: UTType.png.identifier),
                NSItemProvider(object: url as NSURL),
            ]))
        #expect(post.bron == .link(url))
        // Geen afbeelding gekopieerd als hij niet nodig is.
        let bestanden = try FileManager.default.contentsOfDirectory(atPath: map.path())
        #expect(bestanden == [DeelGroep.postMap])
    }

    @Test func nietsBruikbaars() async {
        let map = tijdelijkeMap()
        defer { try? FileManager.default.removeItem(at: map.deletingLastPathComponent()) }
        let provider = NSItemProvider(item: Data([1, 2, 3]) as NSData, typeIdentifier: "com.example.onbekend")
        #expect(await DeelLezer(bus: DeelBus(map: map)).lees([provider]) == nil)
        #expect(await DeelLezer(bus: DeelBus(map: map)).lees([]) == nil)
        #expect(DeelBus(map: map).posts().isEmpty)
    }
}

@MainActor
struct GedeeldeInboxTests {
    /// Zoals de extensie het schrijft: bestanden en een `DeelPost` in de (groeps)map.
    private func deel(_ bron: (DeelBus) throws -> DeelBron, in map: URL, bronURL: URL? = nil) throws -> DeelPost {
        let bus = DeelBus(map: map)
        let post = DeelPost(bron: try bron(bus), bronURL: bronURL)
        try bus.schrijf(post)
        return post
    }

    @Test func gedeeldeItemsWordenOvergenomenEnVerwerkt() async throws {
        let map = tijdelijkeMap()
        defer { try? FileManager.default.removeItem(at: map.deletingLastPathComponent()) }
        let inbox = InleesInbox(map: map)
        let oud = inbox.voegToe(.tekst("Al in de inbox"), datum: .now.addingTimeInterval(-600))

        let url = URL(string: "https://www.kookzender.test/recepten/snelle-tomatensoep")!
        let link = try deel({ _ in .link(url) }, in: map)
        let tekst = try deel({ _ in .tekst(smoothie) }, in: map, bronURL: URL(string: "https://krant.test/koken/x"))
        let beeld = try deel({ .afbeeldingen([try $0.bewaarBestand(rodeAfbeelding(), extensie: "png")]) }, in: map)
        let pdfBron = try pdfBestand(tekst: smoothie)
        defer { try? FileManager.default.removeItem(at: pdfBron) }
        let pdf = try deel({ .pdf(try $0.kopieer(pdfBron, extensie: "pdf")) }, in: map)

        #expect(inbox.neemGedeeldOver() == 4)
        #expect(DeelBus(map: map).posts().isEmpty)
        #expect(Set(inbox.items.map(\.id)) == [oud.id, link.id, tekst.id, beeld.id, pdf.id])
        #expect(inbox.items.last?.id == oud.id)
        #expect(inbox.item(tekst.id)?.bronNaam == "krant.test")
        // Nog eens overnemen: niets dubbel; en het staat op schijf.
        #expect(inbox.neemGedeeldOver() == 0)
        #expect(InleesInbox(map: map).items.count == 5)

        let verwerker = InleesVerwerker(
            inbox: inbox, ophaler: NepOphaler(paginas: [url: try Fixture.html("kookzender")]),
            indeler: { RegelIndeler() },
            fotoBewaren: false)
        await verwerker.verwerkWachtende(categorieen: [], labels: [])

        guard case .klaar(let opgehaald) = inbox.item(link.id)?.status else {
            Issue.record("Link niet klaar: \(String(describing: inbox.item(link.id)?.status))")
            return
        }
        #expect(opgehaald.titel == "Snelle tomatensoep met basilicum")
        guard case .klaar(let gelezen) = inbox.item(tekst.id)?.status else {
            Issue.record("Tekst niet klaar: \(String(describing: inbox.item(tekst.id)?.status))")
            return
        }
        #expect(gelezen.titel == "Groene smoothie")
        #expect(gelezen.bronURL == URL(string: "https://krant.test/koken/x"))
        guard case .herkennen(let namen) = inbox.item(beeld.id)?.status else {
            Issue.record("Afbeelding niet naar herkennen")
            return
        }
        #expect(inbox.data(van: namen[0]).flatMap(UIImage.init(data:)) != nil)
        guard case .klaar(let uitPDF) = inbox.item(pdf.id)?.status else {
            Issue.record("PDF niet klaar: \(String(describing: inbox.item(pdf.id)?.status))")
            return
        }
        #expect(uitPDF.titel == "Groene smoothie")
    }

    @Test func bestandenWordenOpgeruimd() throws {
        let map = tijdelijkeMap()
        defer { try? FileManager.default.removeItem(at: map.deletingLastPathComponent()) }
        let inbox = InleesInbox(map: map)
        let beeld = try deel({ .afbeeldingen([try $0.bewaarBestand(rodeAfbeelding(), extensie: "png")]) }, in: map)
        inbox.neemGedeeldOver()
        guard case .afbeeldingen(let namen) = inbox.item(beeld.id)?.bron else {
            Issue.record("Geen afbeeldingen")
            return
        }
        // Een wees (een deelpoging die halverwege stopte) en een vers bestand van een lopende deling.
        let bus = DeelBus(map: map)
        let wees = try bus.bewaarBestand(Data([1]), extensie: "jpg")
        try FileManager.default.setAttributes(
            [.modificationDate: Date.now.addingTimeInterval(-7200)], ofItemAtPath: inbox.url(van: wees).path())
        let vers = try bus.bewaarBestand(Data([2]), extensie: "jpg")
        // Ook een oud bestand waar een nog niet overgenomen post naar verwijst, blijft staan.
        let wachtend = try bus.bewaarBestand(Data([3]), extensie: "pdf")
        try FileManager.default.setAttributes(
            [.modificationDate: Date.now.addingTimeInterval(-7200)], ofItemAtPath: inbox.url(van: wachtend).path())
        try bus.schrijf(DeelPost(bron: .pdf(wachtend)))

        inbox.ruimOp()
        let bestaat = { (naam: String) in FileManager.default.fileExists(atPath: inbox.url(van: naam).path()) }
        #expect(!bestaat(wees))
        #expect(bestaat(vers))
        #expect(bestaat(wachtend))
        #expect(bestaat(namen[0]))
        #expect(bestaat("inbox.json"))

        // Na bewaren of verwijderen gaat het gedeelde bestand mee.
        inbox.verwijder(beeld.id)
        #expect(!bestaat(namen[0]))
    }

    @Test func migratieUitDeOudeMap() throws {
        let basis = FileManager.default.temporaryDirectory.appending(path: "DelenMigratie-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: basis) }
        let oud = basis.appending(path: "AppSupport/Inlezen")
        let nieuw = basis.appending(path: "Groep/Inlezen")
        let oudeInbox = InleesInbox(map: oud)
        let tekst = oudeInbox.voegToe(.tekst("Soep"))
        let naam = try oudeInbox.bewaarBestand(rodeAfbeelding(), extensie: "png")
        let beeld = oudeInbox.voegToe(.afbeeldingen([naam]))

        InleesInbox.migreer(van: oud, naar: nieuw)
        #expect(!FileManager.default.fileExists(atPath: oud.path()))
        let verhuisd = InleesInbox(map: nieuw)
        #expect(verhuisd.items.map(\.id) == [beeld.id, tekst.id])
        #expect(verhuisd.data(van: naam) == rodeAfbeelding())

        // Nog eens (oude map bestaat niet meer): niets verandert.
        InleesInbox.migreer(van: oud, naar: nieuw)
        #expect(InleesInbox(map: nieuw).items.count == 2)
    }

    @Test func migratieVoegtSamenAlsDeNieuweMapAlEenInboxHeeft() {
        let basis = FileManager.default.temporaryDirectory.appending(path: "DelenMigratie-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: basis) }
        let oud = basis.appending(path: "AppSupport/Inlezen")
        let nieuw = basis.appending(path: "Groep/Inlezen")
        let eerder = InleesInbox(map: oud).voegToe(.tekst("Oud"), datum: .now.addingTimeInterval(-60))
        let later = InleesInbox(map: nieuw).voegToe(.tekst("Nieuw"))

        InleesInbox.migreer(van: oud, naar: nieuw)
        #expect(InleesInbox(map: nieuw).items.map(\.id) == [later.id, eerder.id])
    }
}
