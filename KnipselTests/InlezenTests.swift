import Foundation
import Testing
import UIKit

@testable import Knipsel

/// Vaste HTML-fixtures (verzonnen inhoud, met de structuur van Nederlandse receptsites) uit
/// KnipselTests/Resources/Inlezen. Nooit het netwerk.
enum Fixture {
    private final class Sleutel {}

    static func html(_ naam: String) throws -> String {
        let bundel = Bundle(for: Sleutel.self)
        let url = try #require(
            bundel.url(forResource: naam, withExtension: "html", subdirectory: "Inlezen")
                ?? bundel.url(forResource: naam, withExtension: "html"))
        return try String(contentsOf: url, encoding: .utf8)
    }
}

/// Een ophaler die alleen fixtures teruggeeft; elk ander adres is een fout.
struct NepOphaler: PaginaOphaler {
    var paginas: [URL: String] = [:]
    var afbeeldingen: [URL: Data] = [:]

    func pagina(_ url: URL) async throws -> OpgehaaldePagina {
        guard let html = paginas[url] else { throw OphaalFout.status(404) }
        return OpgehaaldePagina(html: html, url: url)
    }

    func data(_ url: URL) async throws -> Data {
        guard let data = afbeeldingen[url] else { throw OphaalFout.status(404) }
        return data
    }
}

@MainActor
struct SchemaReceptLezerTests {
    let categorieen = StandaardCategorieen.alle.map(\.naam)
    let labels = StandaardCategorieen.labels

    @Test func graphMetVerwijzingen() throws {
        let html = try Fixture.html("graph-supermarkt")
        let recept = try #require(
            SchemaReceptLezer.lees(
                html: html, basis: URL(string: "https://www.voorbeeld-supermarkt.test/recepten/R-123")))
        #expect(recept.naam == "Ovenschotel met pompoen & linzen")
        #expect(recept.beschrijving.contains("krémige saus"))
        #expect(recept.porties == 4)
        #expect(recept.voorbereidingMinuten == 15)
        #expect(recept.kookMinuten == 30)
        #expect(recept.minuten == 45)
        #expect(recept.ingredienten.count == 7)
        #expect(recept.ingredienten.last == "½ tl gemalen komijn")
        #expect(recept.stappen.count == 4)
        #expect(
            recept.stappen[0] == "Verwarm de oven voor op 200 °C. Schil de pompoen en snijd hem in blokjes van 2 cm.")
        #expect(recept.stapgroepen.count == 1 && recept.stapgroepen[0].naam == nil)
        #expect(
            recept.afbeelding?.absoluteString
                == "https://static.voorbeeld-supermarkt.test/recepten/R-123/ovenschotel-1200.jpg")
        #expect(recept.uitgever == "Verzonnen Supermarkt")
    }

    @Test func kookzenderMetDagenEnStapnamen() throws {
        let recept = try #require(SchemaReceptLezer.lees(html: try Fixture.html("kookzender")))
        #expect(recept.naam == "Snelle tomatensoep met basilicum")
        #expect(recept.porties == 4)
        #expect(recept.totaalMinuten == 30)
        #expect(recept.voorbereidingMinuten == 10)
        // "Stap 1" is de naam; de tekst is de stap. Harde spaties worden gewone.
        #expect(recept.stappen.first == "Snipper de ui en hak de knoflook fijn.")
        #expect(!recept.stappen.contains { $0.hasPrefix("Stap ") })
        #expect(recept.beschrijving == "Klaar in een half uur. Met verse basilicum en een scheut room.")
        #expect(recept.afbeelding?.absoluteString == "https://img.kookzender.test/soep-16x9.jpg")
        #expect(recept.uitgever == "Verzonnen Kookzender")
        #expect(recept.auteur == "Verzonnen Kok")
    }

    @Test func receptAlsLijstEnStappenAlsHTMLTekst() throws {
        let recept = try #require(SchemaReceptLezer.lees(html: try Fixture.html("supermarkt-lijst")))
        #expect(recept.naam == "Bananenbrood zonder suiker")
        #expect(recept.porties == 8)
        #expect(recept.minuten == 75)
        #expect(
            recept.stappen == [
                "Verwarm de oven voor op 180 graden.",
                "Prak de bananen en klop de eieren en de olie erdoor.",
                "Meng het meel, het bakpoeder en het zout erdoor.",
                "Bak het brood 55 minuten in een ingevette cakevorm.",
            ])
        #expect(recept.afbeelding?.absoluteString == "https://beeld.buurtsuper.test/bananenbrood.jpg")
        #expect(recept.auteur == "Verzonnen Buurtsuper")
    }

    @Test func blogMetTweeBlokkenEnEntiteiten() throws {
        let recept = try #require(SchemaReceptLezer.lees(html: try Fixture.html("receptenblog")))
        #expect(recept.naam == "Wraps met kip en mango")
        // De losse regelovergang in de JSON-string maakt het blok niet onleesbaar.
        #expect(recept.beschrijving == "Frisse wraps voor de lunch. Klaar in twintig minuten.")
        #expect(recept.porties == 2)
        #expect(recept.minuten == 20)
        #expect(recept.ingredienten.contains("200 g kipfilet (in reepjes)"))
        #expect(recept.ingredienten.contains("2 el yoghurt's saus"))
        #expect(recept.ingredienten.contains("peper & zout"))
        // Dubbel gecodeerd (&amp;amp;) wordt ook gewoon "&".
        #expect(recept.stappen[0] == "Bak de kip in 6 minuten gaar en breng op smaak met peper & zout.")
        #expect(recept.afbeelding?.absoluteString == "https://www.receptenblog.test/uploads/wraps.jpg")
        #expect(recept.auteur == "Verzonnen Blogger")
    }

    @Test func howToSectionsWordenStapgroepen() throws {
        let recept = try #require(
            SchemaReceptLezer.lees(
                html: try Fixture.html("secties"), basis: URL(string: "https://pastakeuken.test/lasagne")))
        #expect(recept.stapgroepen.map(\.naam) == ["Voor de saus", "Voor de vulling", "Afmaken"])
        #expect(recept.stapgroepen.map(\.stappen.count) == [2, 1, 1])
        #expect(recept.minuten == 75)
        #expect(recept.porties == 6)
        // Relatieve afbeelding: tegen het adres van de pagina.
        #expect(recept.afbeelding?.absoluteString == "https://pastakeuken.test/beeld/lasagne.jpg")

        let concept = SchemaReceptLezer.concept(recept)
        #expect(concept.stappen.map(\.groep) == ["Voor de saus", "Voor de saus", "Voor de vulling", "Afmaken"])
        // De kopjes in de ingrediënten blijven staan; bij bewaren worden ze groepen.
        #expect(concept.ingredienten.first?.tekst == "Voor de saus:")
    }

    @Test func microdataAlsTerugval() throws {
        let recept = try #require(
            SchemaReceptLezer.lees(
                html: try Fixture.html("microdata"), basis: URL(string: "https://kookschrift.test/crumble")))
        #expect(recept.naam == "Appelcrumble met kaneel")
        #expect(recept.beschrijving == "Een warme crumble voor koude zondagen.")
        #expect(recept.porties == 6)
        #expect(recept.voorbereidingMinuten == 20)
        #expect(recept.kookMinuten == 35)
        #expect(
            recept.ingredienten == [
                "4 zure appels", "1 tl kaneel", "150 g bloem", "100 g koude boter", "100 g bruine suiker",
            ])
        #expect(recept.stappen.count == 4)
        #expect(recept.stappen[0] == "Verwarm de oven voor op 190 °C.")
        #expect(recept.afbeelding?.absoluteString == "https://kookschrift.test/fotos/crumble.jpg")
        #expect(recept.auteur == "Verzonnen Oma")
    }

    @Test func geenReceptGeenSchema() throws {
        #expect(SchemaReceptLezer.lees(html: try Fixture.html("zonder-schema")) == nil)
        #expect(SchemaReceptLezer.lees(html: try Fixture.html("betaalmuur-krant")) == nil)
        #expect(SchemaReceptLezer.lees(html: "<html><body>Hallo</body></html>") == nil)
        #expect(SchemaReceptLezer.lees(html: "<script type=\"application/ld+json\">{kapot</script>") == nil)
    }

    // MARK: - Velden

    @Test(arguments: [
        ("PT1H15M", 75), ("PT45M", 45), ("PT2H", 120), ("P0DT0H20M", 20), ("PT90M", 90), ("PT30S", 1),
        ("P1D", 1440), ("PT1.5H", 90), ("pt10m", 10), ("", 0), ("30 minuten", 0), ("PT", 0),
    ])
    func isoDuur(_ iso: String, _ minuten: Int) {
        #expect(SchemaReceptLezer.minuten(iso) == minuten)
    }

    @Test func portiesVarianten() {
        #expect(SchemaReceptLezer.porties("4") == 4)
        #expect(SchemaReceptLezer.porties("4 personen") == 4)
        #expect(SchemaReceptLezer.porties("Voor 4-6 personen") == 4)
        #expect(SchemaReceptLezer.porties(["4", "4 servings"]) == 4)
        #expect(SchemaReceptLezer.porties(["", "6 stuks"]) == 6)
        #expect(SchemaReceptLezer.porties(NSNumber(value: 2)) == 2)
        #expect(SchemaReceptLezer.porties("een paar") == 0)
        #expect(SchemaReceptLezer.porties(nil) == 0)
    }

    @Test func typeAlsTekstLijstOfURL() {
        #expect(SchemaReceptLezer.heeftType(["@type": "Recipe"], "recipe"))
        #expect(SchemaReceptLezer.heeftType(["@type": ["NewsArticle", "Recipe"]], "recipe"))
        #expect(SchemaReceptLezer.heeftType(["@type": "http://schema.org/Recipe"], "recipe"))
        #expect(SchemaReceptLezer.heeftType(["@type": "schema:Recipe"], "recipe"))
        #expect(!SchemaReceptLezer.heeftType(["@type": "RecipeCollection"], "recipe"))
    }

    @Test func stappenAlsLosseTekstenEnLangeLap() {
        let teksten = SchemaReceptLezer.stapgroepen(["1. Snijd de ui.", "2) Bak de ui.", "  "])
        #expect(teksten.flatMap(\.stappen) == ["Snijd de ui.", "Bak de ui."])
        let regels = SchemaReceptLezer.stapgroepen("Snijd de ui.\nBak de ui.\n\nServeer.")
        #expect(regels.flatMap(\.stappen) == ["Snijd de ui.", "Bak de ui.", "Serveer."])
        let lap = Array(
            repeating: "Roer de saus goed door en laat hem nog even zachtjes pruttelen op laag vuur.", count: 8
        )
        .joined(separator: " ")
        #expect(SchemaReceptLezer.stapgroepen(lap).flatMap(\.stappen).count > 1)
    }

    @Test func entiteitenEnTags() {
        #expect(HTMLTekst.entiteiten("Cr&egrave;me br&ucirc;l&eacute;e &amp; co") == "Crème brûlée & co")
        #expect(HTMLTekst.entiteiten("&#233;&#xE9;&#8217;&frac12;&deg;") == "éé’½°")
        #expect(HTMLTekst.entiteiten("&amp;eacute;") == "é")
        #expect(HTMLTekst.entiteiten("Tom &onbekend; Jerry") == "Tom &onbekend; Jerry")
        #expect(HTMLTekst.schoon("<b>2&nbsp;el</b>  <i>olie</i>\n") == "2 el olie")
        #expect(HTMLTekst.platteTekst("<p>Een</p><p>Twee<br>Drie</p>") == "Een\nTwee\nDrie")
        #expect(
            HTMLTekst.meta("og:site_name", in: "<meta content=\"Site &amp; Zo\" property='og:site_name'>")
                == "Site & Zo")
    }

    @Test func isGratis() throws {
        #expect(SchemaReceptLezer.isGratis(in: try Fixture.html("betaalmuur-krant")) == false)
        #expect(SchemaReceptLezer.isGratis(in: try Fixture.html("kookzender")) == nil)
        let gratis =
            "<script type=\"application/ld+json\">{\"@type\":\"Article\",\"isAccessibleForFree\":true}</script>"
        #expect(SchemaReceptLezer.isGratis(in: gratis) == true)
    }
}

@MainActor
struct ReceptInlezerTests {
    let categorieen = StandaardCategorieen.alle.map(\.naam)
    let labels = StandaardCategorieen.labels

    @Test func schemaWordtResultaatMetBronEnVoorstellen() async throws {
        let url = try #require(URL(string: "https://www.voorbeeld-supermarkt.test/recepten/R-123"))
        let uitkomst = await ReceptInlezer.lees(
            html: try Fixture.html("graph-supermarkt"), url: url, categorieen: categorieen, labels: labels,
            indeler: RegelIndeler())
        guard case .recept(let resultaat) = uitkomst else {
            Issue.record("Geen recept: \(uitkomst)")
            return
        }
        #expect(resultaat.herkomst == .schema)
        #expect(resultaat.bronNaam == "Verzonnen Supermarkt")
        #expect(resultaat.bronURL == url)
        #expect(resultaat.porties == 4)
        #expect(resultaat.minuten == 45)
        #expect(resultaat.categorieen.contains("Hoofdgerechten"))
        #expect(resultaat.labels.contains("Vegetarisch"))
        #expect(resultaat.afbeeldingURL != nil)
    }

    @Test func zonderSchemaViaDeIndeler() async throws {
        let url = try #require(URL(string: "https://kookdagboek.test/linzensoep"))
        let uitkomst = await ReceptInlezer.lees(
            html: try Fixture.html("zonder-schema"), url: url, categorieen: categorieen, labels: labels,
            indeler: RegelIndeler())
        guard case .recept(let resultaat) = uitkomst else {
            Issue.record("Geen recept: \(uitkomst)")
            return
        }
        #expect(resultaat.herkomst == .regels)
        #expect(resultaat.titel == "Linzensoep met koriander")
        #expect(resultaat.porties == 4)
        #expect(resultaat.minuten == 40)
        #expect(resultaat.ingredienten.count == 7)
        #expect(resultaat.ingredienten.first == "250 g rode linzen")
        // Menu, "Lees ook" en voettekst vallen weg.
        #expect(!resultaat.ingredienten.contains { $0.contains("Home") || $0.contains("soepen voor") })
        #expect(
            resultaat.stappen.map(\.tekst) == [
                "Snipper de ui en snijd de wortels in kleine blokjes.",
                "Fruit de ui met het komijnzaad 3 minuten in de olie.",
                "Voeg de wortel, de linzen en de bouillon toe en laat 25 minuten zachtjes koken.",
                "Pureer de soep en schep de gehakte koriander erdoor.",
            ])
        #expect(resultaat.bronNaam == "Verzonnen Kookdagboek")
        #expect(resultaat.afbeeldingURL?.absoluteString == "https://kookdagboek.test/fotos/linzensoep.jpg")
        #expect(resultaat.categorieen.contains("Soepen"))
    }

    @Test func betaalmuurWordtHerkend() async throws {
        let html = try Fixture.html("betaalmuur-krant")
        let oordeel = Betaalmuur.beoordeel(html: html, tekst: PaginaLezer.tekst(PaginaLezer.blokken(html: html)))
        #expect(oordeel.isBetaalmuur)
        #expect(oordeel.redenen.contains("isAccessibleForFree: false"))
        #expect(oordeel.redenen.contains("tekst: word abonnee"))
        #expect(oordeel.redenen.contains("klasse: paywall"))
        let uitkomst = await ReceptInlezer.lees(
            html: html, url: URL(string: "https://dagblad.test/stoofpot"), categorieen: categorieen, labels: labels,
            indeler: RegelIndeler())
        guard case .betaalmuur = uitkomst else {
            Issue.record("Geen betaalmuur: \(uitkomst)")
            return
        }
    }

    @Test func betaalmuurZonderSchemaMaarMetTekstEnKlasse() {
        let html = """
            <html><body><article><h1>Verzonnen kop</h1><p>Een korte inleiding van twee zinnen. Meer volgt.</p>
            <div id="regwall-blok"><p>Log in om verder te lezen.</p></div></article></body></html>
            """
        let tekst = PaginaLezer.tekst(PaginaLezer.blokken(html: html))
        #expect(Betaalmuur.beoordeel(html: html, tekst: tekst).isBetaalmuur)
    }

    @Test func gewoneReceptpaginaIsGeenBetaalmuur() throws {
        let html = try Fixture.html("zonder-schema")
        let tekst = PaginaLezer.tekst(PaginaLezer.blokken(html: html))
        #expect(!Betaalmuur.beoordeel(html: html, tekst: tekst).isBetaalmuur)
        // Eén keer "abonneer" in een lange, gratis pagina is nog geen betaalmuur.
        let lang = String(repeating: "Roer de soep goed door en proef. ", count: 80) + " Abonneer je op de nieuwsbrief."
        #expect(!Betaalmuur.beoordeel(html: "<p>\(lang)</p>", tekst: lang).isBetaalmuur)
    }

    @Test func pagineZonderReceptIsGeenRecept() async {
        let html =
            "<html><body><article><h1>Over ons</h1><p>Wij zijn een verzonnen bedrijf.</p></article></body></html>"
        let uitkomst = await ReceptInlezer.lees(
            html: html, url: nil, categorieen: categorieen, labels: labels, indeler: RegelIndeler())
        if case .recept = uitkomst { Issue.record("Onterecht een recept") }
    }

    @Test func geplakteTekst() async {
        let tekst = """
            Groene smoothie

            Voor 2 personen.

            1 banaan
            2 handjes spinazie
            250 ml amandelmelk

            1. Doe alles in de blender.
            2. Mix tot het glad is.
            """
        let uitkomst = await ReceptInlezer.lees(
            tekst: tekst, categorieen: categorieen, labels: labels, indeler: RegelIndeler())
        guard case .recept(let resultaat) = uitkomst else {
            Issue.record("Geen recept: \(uitkomst)")
            return
        }
        #expect(resultaat.titel == "Groene smoothie")
        #expect(resultaat.porties == 2)
        #expect(resultaat.ingredienten == ["1 banaan", "2 handjes spinazie", "250 ml amandelmelk"])
        #expect(resultaat.stappen.map(\.tekst) == ["Doe alles in de blender.", "Mix tot het glad is."])
    }

    @Test func linkInTekst() {
        #expect(
            ReceptInlezer.link(in: "  https://www.kookzender.test/recepten/soep \n")?.host() == "www.kookzender.test")
        #expect(ReceptInlezer.link(in: "Kijk eens: https://x.test") == nil)
        #expect(ReceptInlezer.link(in: "ftp://x.test/a") == nil)
        #expect(ReceptInlezer.host(URL(string: "https://www.Kookzender.test/a")!) == "kookzender.test")
    }

    @Test func tekstRegelsBrekenAfZonderTekstVerlies() {
        let alinea = String(repeating: "Snijd de groente in stukjes en bak alles goudbruin. ", count: 4)
            .trimmingCharacters(in: .whitespaces)
        let delen = TekstRegels.breek(alinea)
        #expect(delen.count > 1)
        #expect(delen.allSatisfy { $0.count <= TekstRegels.maxTekens })
        #expect(delen.joined(separator: " ") == alinea)
    }
}

@MainActor
struct InleesInboxTests {
    func tijdelijkeMap() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "InboxTest-\(UUID().uuidString)")
    }

    @Test func opslaanLadenEnVerwijderen() throws {
        let map = tijdelijkeMap()
        defer { try? FileManager.default.removeItem(at: map) }
        let inbox = InleesInbox(map: map)
        #expect(inbox.items.isEmpty)

        let link = inbox.voegToe(.link(URL(string: "https://kookzender.test/soep")!))
        let tekst = inbox.voegToe(.tekst("Soep\n1 ui"))
        var resultaat = InleesResultaat()
        resultaat.titel = "Soep"
        resultaat.stappen = [.init(tekst: "Kook.", groep: "Voor de soep")]
        inbox.werkBij(tekst.id) { $0.status = .klaar(resultaat) }
        inbox.werkBij(link.id) { $0.status = .mislukt("Niet gevonden") }
        let naam = try inbox.bewaarBestand(Data([1, 2, 3]), extensie: "jpg")
        inbox.werkBij(link.id) { $0.foto = naam }

        // Opnieuw van schijf: zelfde items, nieuwste bovenaan.
        let opnieuw = InleesInbox(map: map)
        #expect(opnieuw.items.map(\.id) == [tekst.id, link.id])
        #expect(opnieuw.item(tekst.id)?.status == .klaar(resultaat))
        #expect(opnieuw.item(link.id)?.status == .mislukt("Niet gevonden"))
        #expect(opnieuw.data(van: naam) == Data([1, 2, 3]))

        // Verwijderen haalt ook het bestand weg.
        opnieuw.verwijder(link.id)
        #expect(opnieuw.items.map(\.id) == [tekst.id])
        #expect(!FileManager.default.fileExists(atPath: opnieuw.url(van: naam).path()))
        #expect(InleesInbox(map: map).items.map(\.id) == [tekst.id])
    }

    @Test func bezigWordtWeerWachtenNaHerstart() {
        let map = tijdelijkeMap()
        defer { try? FileManager.default.removeItem(at: map) }
        let inbox = InleesInbox(map: map)
        let item = inbox.voegToe(.tekst("x"))
        inbox.werkBij(item.id) { $0.status = .bezig }
        #expect(InleesInbox(map: map).item(item.id)?.status == .wachten)
    }

    @Test func verwerkLinkMetFotoViaNepOphaler() async throws {
        let map = tijdelijkeMap()
        defer { try? FileManager.default.removeItem(at: map) }
        let inbox = InleesInbox(map: map)
        let url = URL(string: "https://www.kookzender.test/recepten/snelle-tomatensoep")!
        let fotoURL = URL(string: "https://img.kookzender.test/soep-16x9.jpg")!
        let beeld = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 48)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        }
        let ophaler = NepOphaler(
            paginas: [url: try Fixture.html("kookzender")], afbeeldingen: [fotoURL: beeld.pngData()!])
        let item = inbox.voegToe(.link(url))
        let verwerker = InleesVerwerker(inbox: inbox, ophaler: ophaler, indeler: { RegelIndeler() }, fotoBewaren: true)
        await verwerker.verwerk(item.id, categorieen: [], labels: [])
        let klaar = try #require(inbox.item(item.id))
        guard case .klaar(let resultaat) = klaar.status else {
            Issue.record("Niet klaar: \(klaar.status)")
            return
        }
        #expect(resultaat.titel == "Snelle tomatensoep met basilicum")
        #expect(resultaat.bronURL == url)
        #expect(resultaat.bronNaam == "Verzonnen Kookzender")
        let foto = try #require(klaar.foto.flatMap { inbox.data(van: $0) })
        #expect(UIImage(data: foto) != nil)

        // Zonder foto-instelling: geen foto.
        let tweede = inbox.voegToe(.link(url))
        var zonderFoto = verwerker
        zonderFoto.fotoBewaren = false
        await zonderFoto.verwerk(tweede.id, categorieen: [], labels: [])
        #expect(inbox.item(tweede.id)?.foto == nil)
    }

    @Test func mislukteOphaalpoging() async {
        let map = tijdelijkeMap()
        defer { try? FileManager.default.removeItem(at: map) }
        let inbox = InleesInbox(map: map)
        let item = inbox.voegToe(.link(URL(string: "https://bestaat-niet.test/")!))
        await InleesVerwerker(inbox: inbox, ophaler: NepOphaler(), indeler: { RegelIndeler() })
            .verwerk(item.id, categorieen: [], labels: [])
        guard case .mislukt(let reden) = inbox.item(item.id)?.status else {
            Issue.record("Niet mislukt")
            return
        }
        #expect(reden.contains("404"))
        #expect(inbox.item(item.id)?.bronURL != nil)
    }

    @Test func geplakteLinkWordtLink() async {
        let map = tijdelijkeMap()
        defer { try? FileManager.default.removeItem(at: map) }
        let inbox = InleesInbox(map: map)
        let item = inbox.voegToe(.tekst("https://bestaat-niet.test/x"))
        await InleesVerwerker(inbox: inbox, ophaler: NepOphaler(), indeler: { RegelIndeler() })
            .verwerk(item.id, categorieen: [], labels: [])
        #expect(inbox.item(item.id)?.bron == .link(URL(string: "https://bestaat-niet.test/x")!))
    }
}

@MainActor
struct InleesBewarenTests {
    @Test func stapgroepenEnLinkBlijvenBewaard() throws {
        let context = legeOpslag().context
        var resultaat = InleesResultaat()
        resultaat.titel = "Lasagne"
        resultaat.ingredienten = ["Voor de saus:", "50 g boter", "12 lasagnebladen"]
        resultaat.stappen = [
            .init(tekst: "Smelt de boter.", groep: "Voor de saus"), .init(tekst: "Roer.", groep: "Voor de saus"),
            .init(tekst: "Bak 45 minuten.", groep: "Afmaken"),
        ]
        var invoer = ControleInvoer(concept: resultaat.concept, soort: .website)
        invoer.bronNaam = "Verzonnen Pastakeuken"
        invoer.bronPagina = "https://pastakeuken.test/lasagne"
        let recept = try invoer.receptInvoer.bewaar(in: context)
        #expect(recept.gesorteerdeStappen.map(\.tekst) == ["Smelt de boter.", "Roer.", "Bak 45 minuten."])
        #expect(recept.gesorteerdeStappen.map(\.groep) == ["Voor de saus", "Voor de saus", "Afmaken"])
        #expect(recept.gesorteerdeIngredienten.first?.groep == "Voor de saus")
        #expect(recept.bronPagina == "https://pastakeuken.test/lasagne")

        // Terug in het invoerformulier en opnieuw bewaard: de groepen blijven.
        let opnieuw = ReceptInvoer(recept: recept)
        #expect(opnieuw.stappenTekst.hasPrefix("Voor de saus:\n\nSmelt de boter."))
        try opnieuw.bewaar(in: context, recept: recept)
        #expect(recept.gesorteerdeStappen.map(\.groep) == ["Voor de saus", "Voor de saus", "Afmaken"])

        // De bron toont geen "p. https://…"; de link is los te openen.
        #expect(Weergave.bron(naam: recept.bronNaam, datum: nil, pagina: recept.bronPagina) == "Verzonnen Pastakeuken")
        #expect(Weergave.link(pagina: recept.bronPagina)?.host() == "pastakeuken.test")
        #expect(Weergave.link(pagina: "12") == nil)
    }

    @Test func stapEindigendOpDubbelePuntMetZinBlijftStap() {
        #expect(ReceptInvoer.stapGroepskop("Voor de saus:") == "Voor de saus")
        #expect(ReceptInvoer.stapGroepskop("Meng alles. Dan:") == nil)
        #expect(ReceptInvoer.stapGroepskop("Snijd de ui") == nil)
    }
}
