import CoreData
import Foundation
import Testing

@testable import Knipsel

// #39: de eigen boodschappenlijst in Knipsel. Optellen, afdelingen, twee lijsten (Mijn lijst en
// Thuis) in twee stores, migratie naar modelversie 4, het vel en de tekstexport.

private func lijstDefaults() -> UserDefaults {
    let naam = "boodschappenlijst-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: naam)!
    defaults.removePersistentDomain(forName: naam)
    return defaults
}

private func regel(_ tekst: String) -> LijstRegel {
    LijstRegel(vrijeTekst: tekst)!
}

@MainActor
struct LijstOptellenTests {
    @Test func uienTweePlusEen() throws {
        let samen = try #require(BoodschappenLijst.samengevoegd(regel("2 uien"), regel("1 ui")))
        #expect(samen.tekst == "3 uien")
        #expect(samen.hoeveelheid == 3)
        #expect(samen.sleutel == "ui")
    }

    @Test func milliliterEnLiter() throws {
        let samen = try #require(BoodschappenLijst.samengevoegd(regel("500 ml melk"), regel("1 l melk")))
        #expect(samen.eenheid == "l")
        #expect(samen.hoeveelheid == 1.5)
        #expect(samen.tekst == "1½ l melk")
        let klein = try #require(BoodschappenLijst.samengevoegd(regel("200 ml room"), regel("1 dl room")))
        #expect(klein.tekst == "300 ml room")
    }

    @Test func stuksNaarBoven() throws {
        let halve = LijstRegel(naam: "citroen", hoeveelheid: 0.5)
        let samen = try #require(BoodschappenLijst.samengevoegd(halve, regel("1 citroen")))
        #expect(samen.hoeveelheid == 2)
        #expect(samen.tekst == "2 citroenen")
    }

    @Test func grammenEnLepelsNietSamen() {
        #expect(BoodschappenLijst.samengevoegd(regel("50 g boter"), regel("1 el boter")) == nil)
        #expect(BoodschappenLijst.samengevoegd(regel("2 uien"), regel("2 tomaten")) == nil)
        #expect(BoodschappenLijst.samengevoegd(regel("2 uien"), regel("ui")) == nil)
    }

    @Test func tekstZonderHoeveelheidEenKeer() throws {
        let samen = try #require(BoodschappenLijst.samengevoegd(regel("peper en zout"), regel("Peper en zout")))
        #expect(samen.tekst == "peper en zout")
    }

    @Test func herkomstZonderDubbele() {
        #expect(BoodschappenLijst.herkomst(nil, plus: "Pompoensoep") == "Pompoensoep")
        #expect(BoodschappenLijst.herkomst("Pompoensoep", plus: "Linzensalade") == "Pompoensoep, Linzensalade")
        #expect(
            BoodschappenLijst.herkomst("Pompoensoep, Linzensalade", plus: "Pompoensoep") == "Pompoensoep, Linzensalade")
        #expect(BoodschappenLijst.herkomst(nil, plus: nil) == nil)
    }

    @Test func vrijeTekst() {
        let uien = regel("2 uien")
        #expect(uien.naam == "uien")
        #expect(uien.hoeveelheid == 2)
        let papier = regel("wc-papier")
        #expect(papier.hoeveelheid == nil)
        #expect(papier.tekst == "wc-papier")
        #expect(LijstRegel(vrijeTekst: "   ") == nil)
    }

    @Test func tekstExportPerAfdeling() {
        let tekst = BoodschappenLijst.tekst(
            titel: "Boodschappen",
            perAfdeling: [
                (.groenteFruit, ["3 uien", "1 flespompoen"]), (.zuivel, []), (.houdbaar, ["200 ml kokosmelk"]),
            ])
        #expect(tekst == "Boodschappen\n\nGroente & fruit\n• 3 uien\n• 1 flespompoen\n\nHoudbaar\n• 200 ml kokosmelk")
    }

    @Test func siriSomtOp() {
        #expect(BoodschappenSiri.opsomming(mijn: [], thuis: []) == "Je boodschappenlijst is leeg.")
        #expect(BoodschappenSiri.opsomming(mijn: ["3 uien"], thuis: []) == "Op je lijst: 3 uien.")
        #expect(
            BoodschappenSiri.opsomming(mijn: ["3 uien", "melk", "brood"], thuis: ["koffie"])
                == "Op je lijst: 3 uien, melk en brood. Op de Thuis-lijst: koffie.")
    }

    @Test func hoeveelheidBewerken() {
        #expect(BoodschappenItemBewerken.hoeveelheid(uit: "1,5") == 1.5)
        #expect(BoodschappenItemBewerken.hoeveelheid(uit: "½") == 0.5)
        #expect(BoodschappenItemBewerken.hoeveelheid(uit: "") == nil)
        #expect(BoodschappenItemBewerken.getal(1.5) == "1,5")
        #expect(BoodschappenItemBewerken.getal(3) == "3")
    }
}

@MainActor
struct AfdelingenTests {
    @Test func woordenlijstIsGrootGenoegEnZonderDubbele() {
        #expect(Afdelingen.aantalWoorden >= 250)
        #expect(Afdelingen.dubbeleWoorden.isEmpty, "\(Afdelingen.dubbeleWoorden)")
        // Elke afdeling behalve Overig heeft woorden.
        let gebruikt = Set(Afdelingen.tabel.values)
        #expect(gebruikt == Set(Afdeling.allCases).subtracting([.overig]))
    }

    @Test(arguments: [
        ("uien", Afdeling.groenteFruit), ("Rode uien", .groenteFruit), ("tomaten", .groenteFruit),
        ("sjalotten", .groenteFruit), ("druiven", .groenteFruit), ("wortels", .groenteFruit),
        ("wortelen", .groenteFruit), ("paprika's", .groenteFruit), ("champignons", .groenteFruit),
        ("verse gember", .groenteFruit), ("preiringen", .groenteFruit), ("bloemkoolroosjes", .groenteFruit),
        ("rode peper", .groenteFruit), ("platte peterselie", .groenteFruit), ("stokbrood", .brood),
        ("kipfiletreepjes", .vleesVis), ("rundergehakt", .vleesVis), ("gerookte zalm", .vleesVis),
        ("eieren", .zuivel), ("halfvolle melk", .zuivel), ("crème fraîche", .zuivel), ("geraspte oude kaas", .kaas),
        ("feta", .kaas), ("spekjes", .koeling), ("diepvriesspinazie", .diepvries), ("doperwten", .diepvries),
        ("spaghetti", .houdbaar), ("linzen", .houdbaar), ("witte bonen", .houdbaar), ("kidneybonen", .houdbaar),
        ("kokosmelk", .houdbaar), ("zonnebloemolie", .houdbaar), ("druivenpitolie", .houdbaar),
        ("zwarte peper", .kruiden), ("zeezout", .kruiden), ("gerookte paprikapoeder", .kruiden),
        ("bloem", .bakken), ("poedersuiker", .bakken), ("havermout", .ontbijt), ("stroopwafels", .snoep),
        ("droge witte wijn", .dranken),
    ])
    func varianten(naam: String, verwacht: Afdeling) {
        #expect(Afdelingen.afdeling(voor: naam) == verwacht, "\(naam)")
    }

    @Test func onbekendIsOverig() {
        #expect(Afdelingen.uitWoordenlijst("wc-papier") == nil)
        #expect(Afdelingen.afdeling(voor: "afwasmiddel") == .overig)
        #expect(Afdelingen.afdeling(voor: "") == .overig)
    }

    @Test func winkelvolgorde() {
        #expect(Afdeling.allCases.first == .groenteFruit)
        #expect(Afdeling.allCases.last == .overig)
        #expect(
            Afdeling.allCases.map(\.naam) == [
                "Groente & fruit", "Brood & bakkerij", "Vlees & vis", "Zuivel & eieren", "Kaas",
                "Koeling & vleeswaren", "Diepvries", "Houdbaar", "Kruiden & specerijen", "Bakken", "Ontbijt",
                "Snoep & koek", "Dranken", "Overig",
            ])
        #expect(Afdeling.groenteFruit.plek < Afdeling.zuivel.plek)
        #expect(Afdeling(veld: nil) == .overig)
        #expect(Afdeling(veld: "onzin") == .overig)
    }

    @Test func gebruikerGaatVoorWoordenlijstEnClaude() {
        var geheugen = AfdelingGeheugen()
        #expect(geheugen.afdeling(naam: "tonijn", sleutel: "tonijn") == .houdbaar)
        geheugen.claude["zakdoekje"] = .overig
        geheugen.claude["kattenvoer"] = .dranken
        #expect(geheugen.afdeling(naam: "kattenvoer", sleutel: "kattenvoer") == .dranken)
        #expect(!geheugen.isOnbekend(naam: "kattenvoer", sleutel: "kattenvoer"))
        #expect(geheugen.isOnbekend(naam: "afwasmiddel", sleutel: "afwasmiddel"))
        #expect(!geheugen.isOnbekend(naam: "uien", sleutel: "ui"))
        geheugen.kies(.vleesVis, voor: "tonijn")
        #expect(geheugen.afdeling(naam: "tonijn", sleutel: "tonijn") == .vleesVis)
        let defaults = lijstDefaults()
        geheugen.bewaar(in: defaults)
        #expect(AfdelingGeheugen.laad(uit: defaults) == geheugen)
    }

    @Test func claudeAntwoordLezen() throws {
        let antwoord =
            #"{"content":[{"type":"text","text":"```json\n{\"kattenvoer\":\"dranken\",\"zakdoekjes\":\"overig\",\"raar\":\"maan\"}\n```"}]}"#
        let afdelingen = try ClaudeAfdelingen.afdelingen(uitAntwoord: Data(antwoord.utf8))
        #expect(afdelingen == ["kattenvoer": .dranken, "zakdoekjes": .overig])
    }

    @Test func claudeKrijgtAlleenDeNamen() throws {
        let verzoek = try ClaudeAfdelingen.verzoek(namen: ["kattenvoer", "zakdoekjes"], sleutel: "sk-test")
        let body = try #require(verzoek.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let berichten = try #require(json["messages"] as? [[String: Any]])
        #expect(berichten.count == 1)
        #expect(berichten.first?["content"] as? String == "kattenvoer\nzakdoekjes")
        #expect(verzoek.value(forHTTPHeaderField: "x-api-key") == "sk-test")
    }

    @Test func zonderSleutelGeenClaude() async {
        let claude = ClaudeAfdelingen(sleutel: { nil })
        #expect(await claude.deelIn(["kattenvoer"]).isEmpty)
    }
}

@MainActor
struct BoodschappenlijstModelTests {
    private func items(_ kookboek: Kookboek, _ opslag: Opslag) -> [String] {
        Boodschappenlijsten.items(in: kookboek, context: opslag.context).map(\.tekstOfNaam)
    }

    @Test func optellenOpDeLijstMetHerkomst() throws {
        let opslag = legeOpslag()
        let context = opslag.context
        try Boodschappenlijsten.zetOpLijst(
            [regel("2 uien"), regel("500 ml melk")], herkomst: "Pompoensoep", kookboek: .mijn, context: context,
            geheugen: AfdelingGeheugen())
        let resultaat = try Boodschappenlijsten.zetOpLijst(
            [regel("1 ui"), regel("1 l melk"), regel("100 g feta")], herkomst: "Linzensalade", kookboek: .mijn,
            context: context, geheugen: AfdelingGeheugen())
        #expect(resultaat.bijgewerkt == 2)
        #expect(resultaat.toegevoegd == 1)
        let lijst = Boodschappenlijsten.items(in: .mijn, context: context)
        #expect(lijst.map(\.tekstOfNaam) == ["3 uien", "1½ l melk", "100 g feta"])
        let uien = try #require(lijst.first)
        #expect(uien.herkomst == "Pompoensoep, Linzensalade")
        #expect(uien.afdelingWaarde == .groenteFruit)
        #expect(lijst.last?.herkomst == "Linzensalade")
    }

    @Test func afgevinktTeltNietMee() throws {
        let opslag = legeOpslag()
        let context = opslag.context
        try Boodschappenlijsten.zetOpLijst(
            [regel("2 uien")], herkomst: "Soep", kookboek: .mijn, context: context, geheugen: AfdelingGeheugen())
        let eerste = try #require(Boodschappenlijsten.items(in: .mijn, context: context).first)
        try Boodschappenlijsten.vink(eerste, af: true)
        #expect(eerste.afgevinktOp != nil)
        try Boodschappenlijsten.zetOpLijst(
            [regel("1 ui")], herkomst: "Salade", kookboek: .mijn, context: context, geheugen: AfdelingGeheugen())
        let lijst = Boodschappenlijsten.items(in: .mijn, context: context)
        #expect(lijst.count == 2)
        #expect(Boodschappenlijsten.secties(lijst).flatMap(\.items).map(\.tekstOfNaam) == ["1 ui"])
        #expect(Boodschappenlijsten.afgevinkt(lijst).map(\.tekstOfNaam) == ["2 uien"])
        #expect(Boodschappenlijsten.aantalOpen(in: context) == 1)
        #expect(try Boodschappenlijsten.wisAfgevinkt(in: .mijn, context: context) == 1)
        #expect(items(.mijn, opslag) == ["1 ui"])
    }

    @Test func sectiesInWinkelvolgordeEnTekstExport() throws {
        let opslag = legeOpslag()
        let context = opslag.context
        for tekst in ["wc-papier", "200 ml kokosmelk", "1 l melk", "3 uien", "1 flespompoen"] {
            try Boodschappenlijsten.voegToe(
                tekst: tekst, kookboek: .mijn, context: context, geheugen: AfdelingGeheugen())
        }
        let lijst = Boodschappenlijsten.items(in: .mijn, context: context)
        let secties = Boodschappenlijsten.secties(lijst)
        #expect(secties.map(\.afdeling) == [.groenteFruit, .zuivel, .houdbaar, .overig])
        #expect(secties.first?.items.map(\.tekstOfNaam) == ["3 uien", "1 flespompoen"])
        #expect(
            Boodschappenlijsten.tekst(lijst, kookboek: .mijn)
                == "Boodschappen\n\nGroente & fruit\n• 3 uien\n• 1 flespompoen\n\nZuivel & eieren\n• 1 l melk\n\nHoudbaar\n• 200 ml kokosmelk\n\nOverig\n• wc-papier"
        )
    }

    @Test func afdelingWijzigenWordtOnthouden() throws {
        let opslag = legeOpslag()
        let context = opslag.context
        let defaults = lijstDefaults()
        try Boodschappenlijsten.voegToe(
            tekst: "zakdoekjes", kookboek: .mijn, context: context, geheugen: .laad(uit: defaults))
        let item = try #require(Boodschappenlijsten.items(in: .mijn, context: context).first)
        #expect(item.afdelingWaarde == .overig)
        var geheugen = AfdelingGeheugen.laad(uit: defaults)
        try Boodschappenlijsten.wijzig(
            item, naam: "zakdoekjes", hoeveelheid: 2, eenheid: "pak", afdeling: .snoep, geheugen: &geheugen,
            defaults: defaults)
        #expect(item.tekstOfNaam == "2 pakken zakdoekjes")
        #expect(item.afdelingWaarde == .snoep)
        // De volgende keer (ook na afvinken en wissen) staat hij meteen goed.
        try Boodschappenlijsten.vink(item, af: true)
        try Boodschappenlijsten.wisAfgevinkt(in: .mijn, context: context)
        try Boodschappenlijsten.voegToe(
            tekst: "zakdoekjes", kookboek: .mijn, context: context, geheugen: .laad(uit: defaults))
        #expect(Boodschappenlijsten.items(in: .mijn, context: context).first?.afdelingWaarde == .snoep)
    }

    @Test func claudeAfdelingenGeldenVoorOverig() throws {
        let opslag = legeOpslag()
        let context = opslag.context
        try Boodschappenlijsten.voegToe(
            tekst: "kattenvoer", kookboek: .mijn, context: context, geheugen: AfdelingGeheugen())
        #expect(OnbekendeAfdelingen.onbekend(in: context, geheugen: AfdelingGeheugen()) == ["kattenvoer": "kattenvoer"])
        try Boodschappenlijsten.pasToe(["kattenvoer": .dranken], context: context)
        #expect(Boodschappenlijsten.items(in: .mijn, context: context).first?.afdelingWaarde == .dranken)
    }

    /// Mijn lijst en Thuis: elk in de store van hun kookboek, en ze zien elkaar niet.
    @Test func tweeLijstenInTweeStores() throws {
        let opslag = legeOpslag()
        let context = opslag.context
        // Uitgenodigd: Thuis staat in de gedeelde store.
        let thuisCategorie = Categorie(context: context)
        thuisCategorie.naam = "Soepen"
        thuisCategorie.kookboek = Kookboek.thuis.rawValue
        context.assign(thuisCategorie, to: try #require(opslag.gedeeldeStore))
        try context.save()

        try Boodschappenlijsten.zetOpLijst(
            [regel("2 uien")], herkomst: "Soep", kookboek: .mijn, context: context, geheugen: AfdelingGeheugen())
        try Boodschappenlijsten.zetOpLijst(
            [regel("1 ui"), regel("koffie")], herkomst: "Stoofpot", kookboek: .thuis, context: context,
            geheugen: AfdelingGeheugen())
        let mijn = Boodschappenlijsten.items(in: .mijn, context: context)
        let thuis = Boodschappenlijsten.items(in: .thuis, context: context)
        #expect(mijn.map(\.tekstOfNaam) == ["2 uien"])
        #expect(thuis.map(\.tekstOfNaam) == ["1 ui", "koffie"])
        #expect(mijn.allSatisfy { Kookboeken.soort(van: $0.objectID.persistentStore) == .prive })
        #expect(thuis.allSatisfy { Kookboeken.soort(van: $0.objectID.persistentStore) == .gedeeld })
        #expect(Boodschappenlijsten.aantalOpen(in: context, kookboek: .thuis) == 2)
        #expect(Boodschappenlijsten.aantalOpen(in: context) == 3)
    }

    /// Eigenaar (of nog niet gedeeld): de Thuis-lijst staat in de privéstore, zoals de Thuis-recepten.
    @Test func thuisLijstVanDeEigenaarInDePriveStore() throws {
        let opslag = legeOpslag()
        try Boodschappenlijsten.voegToe(
            tekst: "melk", kookboek: .thuis, context: opslag.context, geheugen: AfdelingGeheugen())
        let item = try #require(Boodschappenlijsten.items(in: .thuis, context: opslag.context).first)
        #expect(Kookboeken.soort(van: item.objectID.persistentStore) == .prive)
        #expect(item.kookboekWaarde == .thuis)
    }

    @Test func thuisItemsGaanInDeShareEnTerugBijStoppen() async throws {
        let opslag = legeOpslag()
        let dienst = NepDeelDienst()
        dienst.context = opslag.context
        let delen = ThuisDelen(opslag: opslag, dienst: dienst)
        try Boodschappenlijsten.zetOpLijst(
            [regel("2 uien")], herkomst: "Soep", kookboek: .thuis, context: opslag.context,
            geheugen: AfdelingGeheugen())
        try Boodschappenlijsten.zetOpLijst(
            [regel("1 ui")], herkomst: "Salade", kookboek: .mijn, context: opslag.context,
            geheugen: AfdelingGeheugen())
        let thuisItem = try #require(Boodschappenlijsten.items(in: .thuis, context: opslag.context).first)
        await delen.deelOpenstaande()
        #expect(dienst.gedeeld.contains(thuisItem.objectID))

        try await delen.stopMetDelen()
        #expect(Boodschappenlijsten.items(in: .thuis, context: opslag.context).isEmpty)
        let mijn = Boodschappenlijsten.items(in: .mijn, context: opslag.context)
        #expect(mijn.map(\.tekstOfNaam) == ["3 uien"])
        #expect(mijn.first?.herkomst == "Salade, Soep")
    }

    @Test func schakelaarAlleenMetThuis() {
        #expect(!BoodschappenSchakelaar.toon(rol: .nietGedeeld, thuisItems: 0, thuisRecepten: 0))
        #expect(BoodschappenSchakelaar.toon(rol: .eigenaar, thuisItems: 0, thuisRecepten: 0))
        #expect(BoodschappenSchakelaar.toon(rol: .deelnemer, thuisItems: 0, thuisRecepten: 0))
        #expect(BoodschappenSchakelaar.toon(rol: .nietGedeeld, thuisItems: 1, thuisRecepten: 0))
        #expect(BoodschappenSchakelaar.toon(rol: .nietGedeeld, thuisItems: 0, thuisRecepten: 2))
    }

    @Test func velBestemmingVolgtHetKookboek() {
        #expect(VelBestemming.hoofd(standaard: .knipsel, kookboek: .mijn) == .lijst(.mijn))
        #expect(VelBestemming.hoofd(standaard: .knipsel, kookboek: .thuis) == .lijst(.thuis))
        #expect(VelBestemming.hoofd(standaard: .herinneringen, kookboek: .thuis) == .herinneringen)
        #expect(VelBestemming.lijst(.mijn).knop(aantal: 5) == "Zet 5 op mijn lijst")
        #expect(VelBestemming.lijst(.thuis).knop(aantal: 5) == "Zet 5 op de Thuis-lijst")
        #expect(VelBestemming.herinneringen.knop(aantal: 0) == "Niets op de lijst")
        let defaults = lijstDefaults()
        #expect(BoodschappenStandaard.laad(uit: defaults) == .knipsel)
        defaults.set("herinneringen", forKey: AppConfiguratie.sleutelBoodschappenBestemming)
        #expect(BoodschappenStandaard.laad(uit: defaults) == .herinneringen)
    }

    /// Een bestaande database van modelversie 3 opent met modelversie 4: recepten intact, de lijst leeg.
    @Test func bestaandeV3DatabaseOpent() throws {
        let momd = try #require(Bundle(for: Recept.self).url(forResource: "Knipsel", withExtension: "momd"))
        let v3 = try #require(NSManagedObjectModel(contentsOf: momd.appendingPathComponent("Knipsel 3.mom")))
        #expect(v3.entitiesByName["BoodschappenItem"] == nil)
        #expect(Opslag.model.entitiesByName["BoodschappenItem"] != nil)

        let map = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: map, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: map) }
        let oud = NSPersistentContainer(name: "Knipsel", managedObjectModel: v3)
        oud.persistentStoreDescriptions = [
            NSPersistentStoreDescription(url: map.appendingPathComponent("Knipsel.sqlite"))
        ]
        var fout: (any Error)?
        oud.loadPersistentStores { _, error in fout = error }
        #expect(fout == nil)
        let c = oud.viewContext
        let uuid = UUID()
        let recept = NSEntityDescription.insertNewObject(forEntityName: "Recept", into: c)
        recept.setValue("Oude pompoensoep", forKey: "titel")
        recept.setValue(uuid, forKey: "uuid")
        recept.setValue("thuis", forKey: "kookboek")
        let ingredient = NSEntityDescription.insertNewObject(forEntityName: "Ingredient", into: c)
        ingredient.setValue("2 uien", forKey: "ruweTekst")
        ingredient.setValue(recept, forKey: "recept")
        try c.save()
        for store in oud.persistentStoreCoordinator.persistentStores {
            try oud.persistentStoreCoordinator.remove(store)
        }

        let nieuw = Opslag(map: map, cloudKitContainer: nil)
        #expect(nieuw.laadfout == nil)
        let recepten = try nieuw.context.fetch(Recept.verzoek())
        #expect(recepten.map(\.titel) == ["Oude pompoensoep"])
        #expect(recepten.first?.uuid == uuid)
        #expect(recepten.first?.isThuis == true)
        #expect(recepten.first?.gesorteerdeIngredienten.map(\.ruweTekst) == ["2 uien"])
        #expect(Boodschappenlijsten.items(in: .mijn, context: nieuw.context).isEmpty)
        try Boodschappenlijsten.voegToe(
            tekst: "2 uien", kookboek: .mijn, context: nieuw.context, geheugen: AfdelingGeheugen())
        #expect(Boodschappenlijsten.aantalOpen(in: nieuw.context) == 1)
    }

    @Test func modelversie4() throws {
        let entiteit = try #require(Opslag.model.entitiesByName["BoodschappenItem"])
        #expect(entiteit.relationshipsByName.isEmpty)
        #expect(entiteit.attributesByName["kookboek"]?.defaultValue as? String == "mijn")
        #expect(entiteit.attributesByName["afgevinkt"]?.defaultValue as? Bool == false)
        for naam in [
            "uuid", "naam", "sleutel", "hoeveelheid", "eenheid", "tekst", "afdeling", "afgevinkt", "aangemaaktOp",
            "afgevinktOp", "volgorde", "herkomst", "kookboek",
        ] {
            #expect(entiteit.attributesByName[naam] != nil, "\(naam)")
        }
    }
}
