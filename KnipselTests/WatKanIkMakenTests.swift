import CoreData
import Foundation
import Testing

@testable import Knipsel

// #44: "Wat kan ik maken?" — ingrediënten normaliseren en vergelijken (W1), rangschikken in groepen op
// wat er ontbreekt (W2), basis telt mee (W3), ontbrekende naar de lijst (W4), varianten tonen (W5) en
// Siri (W6). Plus de twee weergavefixes op de boodschappenlijst (meervoud -oen, ml/g naar l/kg).

private func regel(_ tekst: String, groep: String? = nil) -> WatKanIkMaken.Regel {
    WatKanIkMaken.Regel(BoodschappenInvoer(regel: tekst), groep: groep)
}

private func kandidaat(
    _ titel: String, _ regels: [String], minuten: Int = 0, gekookt: Date? = nil, kookboek: Kookboek = .mijn,
    erbij: [String] = []
) -> WatKanIkMaken.Kandidaat {
    WatKanIkMaken.Kandidaat(
        id: titel, titel: titel, minuten: minuten, laatstGekooktOp: gekookt, kookboek: kookboek,
        ingredienten: regels.map { regel($0) } + erbij.map { regel($0, groep: "Voor erbij") })
}

private let basis = MeestalInHuis.standaard
private let niets = MeestalInHuis(woorden: [])

/// Verzonnen recepten, zoals in de schets.
private let recepten: [WatKanIkMaken.Kandidaat] = [
    kandidaat(
        "Prei-quiche met oude kaas",
        ["2 preien", "4 eieren", "150 g geraspte oude kaas", "snufje zout", "peper naar smaak"],
        minuten: 60),
    kandidaat(
        "Preisoep met kaasstengels",
        ["3 preien, in ringen", "1 rol bladerdeeg", "100 g geraspte kaas", "1 el olijfolie"],
        minuten: 45),
    kandidaat("Omelet met prei en ham", ["1 prei", "3 eieren", "100 g ham"], minuten: 20, erbij: ["brood"]),
    kandidaat("Ovenschotel met prei", ["2 preien", "500 g aardappels", "200 ml kookroom"], minuten: 90),
    kandidaat("Pompoensoep", ["1 flespompoen", "1 ui", "1 l bouillon"], minuten: 40),
    kandidaat(
        "Groot preifeest", ["2 preien", "1 venkel", "200 g zalm", "1 citroen", "2 el kappertjes"], minuten: 30),
]

struct IngredientMatcherTests {
    private func naam(_ tekst: String) -> String { IngredientMatcher.begrip(tekst).naam }

    @Test func enkelvoudEnMeervoud() {
        #expect(naam("uien") == "ui")
        #expect(naam("ui") == "ui")
        #expect(naam("eieren") == "ei")
        #expect(naam("tomaten") == "tomaat")
        #expect(naam("tomaatjes") == "tomaat")
        #expect(naam("aardappels") == "aardappel")
        #expect(naam("aardappelen") == "aardappel")
        #expect(naam("preien") == "prei")
        #expect(naam("Uitjes") == "ui")
    }

    @Test func samenstellingenNaarKopwoord() {
        #expect(naam("preiringen") == "prei")
        #expect(naam("kipfiletreepjes") == "kipfilet")
        let dij = IngredientMatcher.begrip("kippendijen")
        #expect(dij.naam == "kippendij")
        #expect(dij.ouders.contains("kip"))
        #expect(IngredientMatcher.begrip("zeezout").ouders == ["zout"])
        #expect(IngredientMatcher.begrip("cherrytomaten").ouders == ["tomaat"])
        #expect(IngredientMatcher.begrip("olijfolie").ouders == ["olie"])
        // Lijkt een samenstelling, is het niet.
        #expect(IngredientMatcher.begrip("aardappel").ouders.isEmpty)
        #expect(IngredientMatcher.begrip("sinaasappel").ouders.isEmpty)
        #expect(IngredientMatcher.begrip("pindakaas").ouders.isEmpty)
    }

    @Test func bijvoeglijkeWoordenVallenWeg() {
        #expect(naam("verse gesnipperde ui") == "ui")
        #expect(naam("geraspte oude kaas") == "kaas")
        #expect(naam("jonge kaas") == "kaas")
        #expect(naam("belegen kaas") == "kaas")
        #expect(naam("fijngehakte verse peterselie") == "peterselie")
        #expect(naam("grote rijpe avocado's") == "avocado")
        // Gehakt (vlees) is geen bijvoeglijk woord.
        #expect(naam("gehakt") == "gehakt")
    }

    @Test func synoniemen() {
        #expect(naam("slagroom") == "room")
        #expect(naam("winterpeen") == "wortel")
        #expect(naam("roomboter") == "boter")
        #expect(naam("knoflookteen") == "knoflook")
        #expect(naam(IngredientParser.parse("2 teentjes knoflook").naam) == "knoflook")
        #expect(naam("parmezaanse kaas") == "parmezaan")
        #expect(naam("bosui") == "lente ui")
        #expect(naam("spaanse peper") == "rode peper")
    }

    @Test func variantenEnDeRegel() {
        func dekking(recept: String, inHuis: String) -> Dekking? {
            IngredientMatcher.vergelijk(
                recept: IngredientMatcher.begrip(recept), inHuis: IngredientMatcher.begrip(inHuis))
        }
        // Specifieker in huis dekt het algemene recept; andersom is het bijna.
        #expect(dekking(recept: "ui", inHuis: "rode ui") == .aanwezig(0))
        #expect(dekking(recept: "rode uien", inHuis: "ui") == .bijna(0))
        #expect(dekking(recept: "uien", inHuis: "ui") == .aanwezig(0))
        #expect(dekking(recept: "sjalotten", inHuis: "ui") == .bijna(0))
        #expect(dekking(recept: "ui", inHuis: "sjalot") == .bijna(0))
        #expect(dekking(recept: "kaas", inHuis: "parmezaan") == .aanwezig(0))
        #expect(dekking(recept: "parmezaan", inHuis: "oude kaas") == .bijna(0))
        #expect(dekking(recept: "geraspte kaas", inHuis: "oude kaas") == .aanwezig(0))
        #expect(dekking(recept: "kippendijen", inHuis: "kip") == .bijna(0))
        #expect(dekking(recept: "kip", inHuis: "kippendijfilet") == .aanwezig(0))
        #expect(dekking(recept: "kookroom", inHuis: "slagroom") == .bijna(0))
        #expect(dekking(recept: "spaghetti", inHuis: "pasta") == .bijna(0))
        #expect(dekking(recept: "rode paprika", inHuis: "paprika") == .bijna(0))
        #expect(dekking(recept: "preiringen", inHuis: "prei") == .aanwezig(0))
        // Geen valse zekerheid (W5).
        #expect(dekking(recept: "mozzarella", inHuis: "feta") == nil)
        #expect(dekking(recept: "rode peper", inHuis: "peper") == nil)
        #expect(dekking(recept: "aardappel", inHuis: "appel") == nil)
        #expect(dekking(recept: "zoete aardappel", inHuis: "aardappel") == nil)
        #expect(dekking(recept: "kokosmelk", inHuis: "melk") == nil)
        #expect(dekking(recept: "pindakaas", inHuis: "kaas") == nil)
    }

    @Test func naarSmaakOptioneelEnKopjesTellenNiet() {
        #expect(IngredientMatcher.telNiet(ruweTekst: "peterselie naar smaak", toelichting: nil, groep: nil))
        #expect(IngredientMatcher.telNiet(ruweTekst: "2 el kappertjes (optioneel)", toelichting: nil, groep: nil))
        #expect(IngredientMatcher.telNiet(ruweTekst: "evt. wat chilivlokken", toelichting: nil, groep: nil))
        #expect(IngredientMatcher.telNiet(ruweTekst: "Voor de saus:", toelichting: nil, groep: nil))
        #expect(IngredientMatcher.telNiet(ruweTekst: "stokbrood", toelichting: nil, groep: "Voor erbij"))
        #expect(IngredientMatcher.telNiet(ruweTekst: "1 citroen", toelichting: "om te serveren", groep: nil))
        #expect(!IngredientMatcher.telNiet(ruweTekst: "2 preien", toelichting: "in ringen", groep: "Voor de vulling"))
    }

    @Test func alternatievenEnDelen() {
        var matcher = IngredientMatcher()
        let chips = [matcher.begrip("olie")]
        // "boter of olie": één van beide volstaat.
        #expect(
            matcher.dekking(naam: "boter of olie", ruweTekst: "boter of olie", chips: chips, meestalInHuis: niets)
                == .aanwezig(0))
        // "peper en zout": beide basis.
        #expect(
            matcher.dekking(naam: "peper en zout", ruweTekst: "peper en zout", chips: [], meestalInHuis: basis)
                == .basis)
        #expect(
            matcher.dekking(
                naam: "kip en spek", ruweTekst: "kip en spek", chips: [matcher.begrip("kip")],
                meestalInHuis: niets) == .ontbreekt)
        #expect(IngredientMatcher.alternatieven("kant-en-klaar deeg") == [["kant-en-klaar deeg"]])
    }
}

struct WatKanIkMakenTests {
    @Test func groepenInDeVolgordeVanDeSchets() {
        let uit = WatKanIkMaken.zoek(["prei", "eieren", "oude kaas"], in: recepten, meestalInHuis: basis)
        let groepen = WatKanIkMaken.groepen(uit)
        #expect(groepen.map(\.groep) == [.allesInHuis, .nogEen, .nogTwee, .nogMeer])
        #expect(groepen[0].resultaten.map(\.recept.titel) == ["Prei-quiche met oude kaas"])
        // Beide gebruiken er twee van jou; de omelet is sneller.
        #expect(groepen[1].resultaten.map(\.recept.titel) == ["Omelet met prei en ham", "Preisoep met kaasstengels"])
        #expect(groepen[1].resultaten[0].ontbrekend == ["ham"])
        #expect(groepen[1].resultaten[1].mistTekst == "mist: bladerdeeg")
        #expect(groepen[2].resultaten[0].ontbrekend == ["aardappels", "kookroom"])
        #expect(groepen[3].resultaten.map(\.recept.titel) == ["Groot preifeest"])
        #expect(groepen[0].resultaten[0].mistTekst == "alles in huis")
        #expect(groepen[0].resultaten[0].aandeel == 1)
    }

    @Test func geenOverlapNietTonen() {
        let uit = WatKanIkMaken.zoek(["prei"], in: recepten, meestalInHuis: basis)
        #expect(!uit.contains { $0.recept.titel == "Pompoensoep" })
        #expect(WatKanIkMaken.zoek(["drop"], in: recepten, meestalInHuis: basis).isEmpty)
        #expect(WatKanIkMaken.zoek([], in: recepten, meestalInHuis: basis).isEmpty)
        // Alleen basis (zout) telt niet als "jouw ingrediënt".
        #expect(WatKanIkMaken.zoek(["  "], in: recepten, meestalInHuis: basis).isEmpty)
    }

    @Test func basisTeltAlsAanwezig() throws {
        let met = WatKanIkMaken.zoek(["prei", "eieren", "kaas"], in: recepten, meestalInHuis: basis)
        let quiche = try #require(met.first { $0.recept.titel == "Prei-quiche met oude kaas" })
        #expect(quiche.groep == .allesInHuis)
        let zonder = WatKanIkMaken.zoek(["prei", "eieren", "kaas"], in: recepten, meestalInHuis: niets)
        let kaal = zonder.first { $0.recept.titel == "Prei-quiche met oude kaas" }
        // Zout ontbreekt dan; "peper naar smaak" telt nooit mee.
        #expect(kaal?.ontbrekend == ["zout"])
        // Olijfolie in de soep: basis.
        #expect(met.first { $0.recept.titel == "Preisoep met kaasstengels" }?.ontbrekend == ["bladerdeeg"])
    }

    @Test func naarSmaakEnVoorErbijNietOntbrekend() {
        let uit = WatKanIkMaken.zoek(["prei", "eieren"], in: recepten, meestalInHuis: niets)
        let omelet = uit.first { $0.recept.titel == "Omelet met prei en ham" }
        #expect(omelet?.ontbrekend == ["ham"])
        #expect(omelet?.nodig == 3)
        let quiche = uit.first { $0.recept.titel == "Prei-quiche met oude kaas" }
        #expect(quiche?.ontbrekend.contains("peper") == false)
    }

    @Test func bijnaTeltMeeEnWordtGetoond() throws {
        let salade = kandidaat("Uiensalade", ["2 rode uien", "1 komkommer", "1 el azijn"], minuten: 10)
        let uit = WatKanIkMaken.zoek(["ui"], in: [salade], meestalInHuis: basis)
        let resultaat = try #require(uit.first)
        #expect(resultaat.groep == .nogEen)
        #expect(resultaat.ontbrekend == ["komkommer"])
        #expect(resultaat.varianten.map(\.tekst) == ["rode uien ≈ ui"])
        // Andersom: rode ui in huis, het recept vraagt ui → gewoon aanwezig.
        let soep = WatKanIkMaken.zoek(["rode ui"], in: recepten, meestalInHuis: basis)
        #expect(soep.first?.recept.titel == "Pompoensoep")
        #expect(soep.first?.varianten.isEmpty == true)
    }

    @Test func meesteVanJouwIngredientenEerst() {
        let a = kandidaat("Alleen prei", ["1 prei", "1 venkel"], minuten: 5)
        let b = kandidaat("Prei en ei", ["1 prei", "2 eieren", "1 venkel"], minuten: 50)
        let uit = WatKanIkMaken.zoek(["prei", "ei"], in: [a, b], meestalInHuis: basis)
        #expect(uit.map(\.recept.titel) == ["Prei en ei", "Alleen prei"])
    }

    @Test func eenChipSnelstOfLangNietGekookt() {
        let nu = Date(timeIntervalSince1970: 1_800_000_000)
        let a = kandidaat("Snel", ["1 prei"], minuten: 10, gekookt: nu.addingTimeInterval(-86_400))
        let b = kandidaat("Lang geleden", ["1 prei"], minuten: 40, gekookt: nu.addingTimeInterval(-60 * 86_400))
        let c = kandidaat("Nooit", ["1 prei"], minuten: 0)
        let snel = WatKanIkMaken.zoek(["prei"], in: [b, c, a], meestalInHuis: basis, sortering: .snelst)
        #expect(snel.map(\.recept.titel) == ["Snel", "Lang geleden", "Nooit"])
        let lang = WatKanIkMaken.zoek(["prei"], in: [a, b, c], meestalInHuis: basis, sortering: .langNietGekookt)
        #expect(lang.map(\.recept.titel) == ["Nooit", "Lang geleden", "Snel"])
        #expect(WatKanIkMakenRegel.geleden(nil, nu: nu) == "nooit gekookt")
        #expect(WatKanIkMakenRegel.geleden(nu.addingTimeInterval(-56 * 86_400), nu: nu) == "8 wk niet")
        #expect(WatKanIkMakenRegel.geleden(nu.addingTimeInterval(-3 * 86_400), nu: nu) == "3 dagen niet")
    }

    @Test func chipsUitTypenEnDicteren() {
        #expect(WatKanIkMaken.voegToe("prei, eieren en oude kaas", aan: []) == ["prei", "eieren", "oude kaas"])
        #expect(WatKanIkMaken.voegToe("Uien", aan: ["ui"]) == ["ui"])
        #expect(WatKanIkMaken.voegToe(" , ", aan: ["prei"]) == ["prei"])
        let defaults = UserDefaults(suiteName: "wkim-\(UUID().uuidString)")!
        WatKanIkMaken.bewaar(["prei", "kaas"], in: defaults)
        #expect(WatKanIkMaken.laadChips(uit: defaults) == ["prei", "kaas"])
        WatKanIkMaken.bewaar([], in: defaults)
        #expect(WatKanIkMaken.laadChips(uit: defaults).isEmpty)
    }

    @Test func suggestiesUitJeRecepten() {
        let bekend = WatKanIkMaken.bekendeIngredienten(in: recepten, meestalInHuis: basis)
        #expect(bekend.first == "prei")
        #expect(!bekend.contains("zout"))
        #expect(!bekend.contains("olijfolie"))
        #expect(WatKanIkMaken.suggesties(voor: "pr", bekend: bekend, gekozen: []) == ["prei"])
        #expect(WatKanIkMaken.suggesties(voor: "pr", bekend: bekend, gekozen: ["preien"]).isEmpty)
        #expect(WatKanIkMaken.suggesties(voor: "kaas", bekend: bekend, gekozen: []).contains("kaas"))
    }

    @Test func basisRegel() {
        #expect(WatKanIkMaken.basisRegel(basis) == "Zout, peper, olie… tellen als in huis.")
        #expect(WatKanIkMaken.basisRegel(MeestalInHuis(woorden: ["boter"])) == "Boter telt als in huis.")
    }

    @Test func snelGenoegVoor1000Recepten() {
        let pool = [
            "2 preien", "4 eieren", "150 g geraspte oude kaas", "1 rol bladerdeeg", "500 g kastanjechampignons",
            "2 rode uien", "3 teentjes knoflook", "1 flespompoen", "400 g kippendijen", "200 ml kookroom",
            "1 bosje verse koriander", "2 el olijfolie", "zout en peper naar smaak", "250 g spaghetti",
            "1 blik tomatenblokjes (400 g)", "100 g feta", "1 citroen", "3 cm verse gember", "2 wortels",
            "500 g kruimige aardappels",
        ]
        let veel = (0..<1000).map { index in
            kandidaat(
                "Recept \(index)",
                (0..<10).map { pool[($0 * 7 + index * 3) % pool.count] } + ["\(index % 50) g specerij\(index % 97)"],
                minuten: 10 + index % 80)
        }
        let begin = ContinuousClock.now
        let uit = WatKanIkMaken.zoek(["prei", "eieren", "kaas"], in: veel, meestalInHuis: basis)
        let duur = ContinuousClock.now - begin
        #expect(!uit.isEmpty)
        #expect(duur < .seconds(2), "duurde \(duur)")
    }

    @Test func siriAntwoord() {
        let uit = WatKanIkMaken.zoek(["prei"], in: recepten, meestalInHuis: basis, sortering: .snelst)
        #expect(
            WatKanIkMaken.siriAntwoord(ingredient: "Prei", resultaten: uit)
                == "Ik vond 5 recepten met prei. Het snelst is Omelet met prei en ham, 20 minuten.")
        #expect(
            WatKanIkMaken.siriAntwoord(ingredient: "drop", resultaten: [])
                == "Ik vond geen recepten met drop in Knipsel.")
        let een = WatKanIkMaken.zoek(["bladerdeeg"], in: recepten, meestalInHuis: basis)
        #expect(
            WatKanIkMaken.siriAntwoord(ingredient: "bladerdeeg", resultaten: een)
                == "Ik vond 1 recept met bladerdeeg: Preisoep met kaasstengels, 45 minuten.")
        let lang = [kandidaat("Stoofpot", ["1 kg prei"], minuten: 75)]
        #expect(
            WatKanIkMaken.siriAntwoord(
                ingredient: "prei", resultaten: WatKanIkMaken.zoek(["prei"], in: lang, meestalInHuis: basis))
                == "Ik vond 1 recept met prei: Stoofpot, 1 uur 15 minuten.")
    }
}

/// Met de opslag: de kandidaten uit Core Data, de ontbrekende op de lijst en de Siri-opdracht.
@MainActor
struct WatKanIkMakenOpslagTests {
    private func bibliotheek() throws -> NSManagedObjectContext {
        let context = legeOpslag().context
        let soep = try maakRecept(
            "Preisoep met kaasstengels", ingredienten: ["3 preien", "1 rol bladerdeeg", "100 g geraspte kaas"],
            in: context)
        soep.totaleTijdMinuten = 45
        let omelet = try maakRecept("Omelet met prei", ingredienten: ["1 prei", "3 eieren", "100 g ham"], in: context)
        omelet.bereidingstijdMinuten = 20
        let thuis = try maakRecept("Thuis-stamppot", ingredienten: ["1 kg aardappels", "2 preien"], in: context)
        thuis.kookboek = Kookboek.thuis.rawValue
        try maakRecept("Pompoensoep", ingredienten: ["1 flespompoen"], in: context)
        try context.save()
        return context
    }

    @Test func kandidatenVolgenHetKookboek() throws {
        let context = try bibliotheek()
        #expect(WatKanIkMakenOpslag.kandidaten(in: context, kookboek: nil).count == 4)
        let mijn = WatKanIkMakenOpslag.kandidaten(in: context, kookboek: .mijn)
        #expect(!mijn.contains { $0.titel == "Thuis-stamppot" })
        let omelet = try #require(mijn.first { $0.titel == "Omelet met prei" })
        #expect(omelet.minuten == 20)
        #expect(omelet.ingredienten.map(\.naam) == ["prei", "eieren", "ham"])
    }

    @Test func ontbrekendeOpDeLijst() throws {
        let context = try bibliotheek()
        let uit = WatKanIkMaken.zoek(
            ["prei", "kaas"], in: WatKanIkMakenOpslag.kandidaten(in: context, kookboek: nil), meestalInHuis: basis)
        let soep = try #require(uit.first { $0.recept.titel == "Preisoep met kaasstengels" })
        let (resultaat, kookboek) = try WatKanIkMakenOpslag.zetOntbrekendeOpLijst(
            soep, context: context, geheugen: AfdelingGeheugen())
        #expect(resultaat.toegevoegd == 1)
        #expect(kookboek == .mijn)
        let items = Boodschappenlijsten.items(in: .mijn, context: context)
        #expect(items.map(\.tekstOfNaam) == ["1 rol bladerdeeg"])
        #expect(items.first?.herkomst == "Preisoep met kaasstengels")
        #expect(items.first?.afdelingWaarde == .diepvries)
        // Een Thuis-recept gaat op de Thuis-lijst.
        let stamppot = try #require(uit.first { $0.recept.titel == "Thuis-stamppot" })
        let (_, boek) = try WatKanIkMakenOpslag.zetOntbrekendeOpLijst(
            stamppot, context: context, geheugen: AfdelingGeheugen())
        #expect(boek == .thuis)
        #expect(Boodschappenlijsten.items(in: .thuis, context: context).map(\.tekstOfNaam) == ["1 kg aardappels"])
    }

    @Test func siriZoektBewaartEnOpent() throws {
        let context = try bibliotheek()
        let defaults = UserDefaults(suiteName: "wkim-siri-\(UUID().uuidString)")!
        let router = WatKanIkMakenRouter()
        let zin = WatKanIkMakenIntent.start(ingredient: " Prei ", in: context, router: router, defaults: defaults)
        #expect(zin == "Ik vond 3 recepten met prei. Het snelst is Omelet met prei, 20 minuten.")
        #expect(WatKanIkMaken.laadChips(uit: defaults) == ["prei"])
        #expect(router.neemAf()?.ingredienten == ["prei"])
        #expect(router.verzoek == nil)
    }

    @Test func ingredientEntiteit() async throws {
        let query = IngredientQuery()
        #expect(try await query.entities(for: [" Prei "]).map(\.id) == ["prei"])
        #expect(try await query.entities(matching: "  ").isEmpty)
        #expect(try await query.entities(matching: "Bladerdeeg").first?.id == "bladerdeeg")
    }
}

/// De twee kleine fixes uit de renders van #41.
struct BoodschappenWeergaveFixTests {
    private func tekst(_ regels: [String], factor: Double = 1) -> [String] {
        BoodschappenLijst.regels(regels.map(BoodschappenInvoer.init(regel:)), factor: factor, meestalInHuis: niets)
            .map(\.tekst)
    }

    @Test func meervoudOpOen() {
        #expect(Portieschaling.getal("flespompoen", voor: 2) == "flespompoenen")
        #expect(Portieschaling.getal("flespompoenen", voor: 1) == "flespompoen")
        #expect(Portieschaling.getal("pompoen", voor: 3) == "pompoenen")
        #expect(Portieschaling.getal("cherrytomaat", voor: 2) == "cherrytomaten")
        #expect(Portieschaling.getal("cherrytomaten", voor: 1) == "cherrytomaat")
        #expect(Portieschaling.getal("groen", voor: 2) == "groen")
        // "prei" is geen samenstelling met "ei".
        #expect(Portieschaling.getal("prei", voor: 2) == "prei")
        let twee = BoodschappenLijst.regels(
            recepten: [
                ReceptBoodschappen(titel: "Soep", invoer: [BoodschappenInvoer(regel: "1 flespompoen")]),
                ReceptBoodschappen(titel: "Risotto", invoer: [BoodschappenInvoer(regel: "1 flespompoen")]),
            ], meestalInHuis: niets)
        #expect(twee.map(\.tekst) == ["2 flespompoenen"])
        #expect(tekst(["1 flespompoen"], factor: 2) == ["2 flespompoenen"])
    }

    @Test func groteMatenInLiterEnKilo() throws {
        #expect(tekst(["1600 ml bouillon"]) == ["1,6 l bouillon"])
        #expect(tekst(["1 l melk", "600 ml melk"]) == ["1,6 l melk"])
        #expect(tekst(["800 ml melk"]) == ["800 ml melk"])
        #expect(tekst(["1000 g bloem"]) == ["1 kg bloem"])
        #expect(tekst(["1500 g aardappels"]) == ["1½ kg aardappels"])
        #expect(tekst(["800 g aardappels"], factor: 2) == ["1,6 kg aardappels"])
        #expect(tekst(["15 dl room"]) == ["1½ l room"])
        let regel = try #require(LijstRegel(vrijeTekst: "1600 ml water"))
        #expect(regel.eenheid == "l")
        #expect(regel.hoeveelheid == 1.6)
    }
}
