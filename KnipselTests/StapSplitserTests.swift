import CoreGraphics
import Foundation
import Testing

@testable import Knipsel

/// Verzonnen lopende bereidingsteksten in de stijl van verschillende bladen (#17), met de verwachte
/// stapgrenzen. Afkortingen ("ca.", "bijv."), "180 °C.", "1.5 el", een kopje, een korte afsluitende zin.
enum Bereidingen {
    struct Voorbeeld {
        let blad: String
        let tekst: String
        let verwacht: [String]
    }

    static let alle: [Voorbeeld] = [
        Voorbeeld(
            blad: "AH Allerhande",
            tekst:
                "Verwarm de oven voor op 200 °C. Snijd de zoete aardappel in parten van ca. 2 cm en verdeel over een met bakpapier beklede bakplaat. Besprenkel met de olie en bestrooi met de paprikapoeder, peper en zout. Rooster ca. 25 min. in het midden van de oven tot ze gaar en goudbruin zijn. Snijd intussen de rode ui in dunne ringen en meng met het limoensap. Meng de yoghurt met de knoflook. Verdeel de aardappelparten over 4 borden, schep de yoghurtsaus erover en garneer met de ui en de koriander.",
            verwacht: [
                "Verwarm de oven voor op 200 °C.",
                "Snijd de zoete aardappel in parten van ca. 2 cm en verdeel over een met bakpapier beklede bakplaat. Besprenkel met de olie en bestrooi met de paprikapoeder, peper en zout.",
                "Rooster ca. 25 min. in het midden van de oven tot ze gaar en goudbruin zijn.",
                "Snijd intussen de rode ui in dunne ringen en meng met het limoensap. Meng de yoghurt met de knoflook.",
                "Verdeel de aardappelparten over 4 borden, schep de yoghurtsaus erover en garneer met de ui en de koriander.",
            ]),
        Voorbeeld(
            blad: "de Volkskrant",
            tekst:
                "Zet een grote pan water op het vuur voor de pasta. Verhit intussen de olijfolie in een hapjespan en bak de pancetta in ca. 5 minuten krokant. Haal het vlees uit de pan en laat uitlekken op keukenpapier. Fruit in hetzelfde vet de sjalot en de knoflook zachtjes glazig, dat duurt een minuut of vier. Blus af met de witte wijn en laat die bijna helemaal verdampen. Kook de pasta volgens de aanwijzingen op de verpakking beetgaar. Schep de pasta met een schuimspaan direct in de hapjespan, met een flinke scheut kookwater. Roer de Parmezaanse kaas erdoor tot er een glanzende saus ontstaat. Breng op smaak met zwarte peper. Lekker met een groene salade.",
            verwacht: [
                "Zet een grote pan water op het vuur voor de pasta.",
                "Verhit intussen de olijfolie in een hapjespan en bak de pancetta in ca. 5 minuten krokant.",
                "Haal het vlees uit de pan en laat uitlekken op keukenpapier.",
                "Fruit in hetzelfde vet de sjalot en de knoflook zachtjes glazig, dat duurt een minuut of vier.",
                "Blus af met de witte wijn en laat die bijna helemaal verdampen.",
                "Kook de pasta volgens de aanwijzingen op de verpakking beetgaar.",
                "Schep de pasta met een schuimspaan direct in de hapjespan, met een flinke scheut kookwater.",
                "Roer de Parmezaanse kaas erdoor tot er een glanzende saus ontstaat. Breng op smaak met zwarte peper. Lekker met een groene salade.",
            ]),
        Voorbeeld(
            blad: "Libelle (onbepaalde wijs)",
            tekst:
                "Oven voorverwarmen op 180 °C. Ui en knoflook pellen en fijnsnijden. Boter in een koekenpan smelten en ui en knoflook in 3 min. zachtjes fruiten. Gehakt toevoegen en rul bakken. Tomatenblokjes en Italiaanse kruiden erdoor roeren en 10 min. laten pruttelen. Ondertussen de courgette in plakjes snijden. Een ovenschaal invetten en de helft van het gehakt erin scheppen. Courgette erop leggen en bedekken met de rest van het gehakt. Kaas erover strooien en ca. 25 min. in de oven bakken. Lekker met stokbrood.",
            verwacht: [
                "Oven voorverwarmen op 180 °C. Ui en knoflook pellen en fijnsnijden.",
                "Boter in een koekenpan smelten en ui en knoflook in 3 min. zachtjes fruiten. Gehakt toevoegen en rul bakken.",
                "Tomatenblokjes en Italiaanse kruiden erdoor roeren en 10 min. laten pruttelen.",
                "Ondertussen de courgette in plakjes snijden.",
                "Een ovenschaal invetten en de helft van het gehakt erin scheppen. Courgette erop leggen en bedekken met de rest van het gehakt.",
                "Kaas erover strooien en ca. 25 min. in de oven bakken. Lekker met stokbrood.",
            ]),
        Voorbeeld(
            blad: "NRC (met \"Voor de saus:\")",
            tekst:
                "Leg de kippendijen in een schaal, wrijf ze in met de kruidenpasta en laat ze minstens een uur marineren, liefst een nacht. Verwarm de oven tot 220 °C. Leg de kip met de huid naar boven in een ovenschaal en rooster ca. 35 min., tot het vel knapperig is.\nVoor de saus: Smelt de boter in een steelpan en roer de bloem erdoor. Schenk er al roerend de kippenbouillon bij en laat de saus 5 min. zachtjes inkoken. Breng op smaak met citroenrasp, peper en zout. Snijd de kip in stukken en serveer met de saus en gekookte krieltjes.",
            verwacht: [
                "Leg de kippendijen in een schaal, wrijf ze in met de kruidenpasta en laat ze minstens een uur marineren, liefst een nacht.",
                "Verwarm de oven tot 220 °C.",
                "Leg de kip met de huid naar boven in een ovenschaal en rooster ca. 35 min., tot het vel knapperig is.",
                "Voor de saus: Smelt de boter in een steelpan en roer de bloem erdoor.",
                "Schenk er al roerend de kippenbouillon bij en laat de saus 5 min. zachtjes inkoken. Breng op smaak met citroenrasp, peper en zout.",
                "Snijd de kip in stukken en serveer met de saus en gekookte krieltjes.",
            ]),
        Voorbeeld(
            blad: "Margriet",
            tekst:
                "Kook de eieren in 8 min. hard. Laat ze schrikken onder koud water en pel ze. Snijd de eieren in de lengte doormidden en schep de dooiers eruit. Prak de dooiers met de mayonaise, mosterd en kerriepoeder tot een glad mengsel. Breng op smaak met peper en zout. Schep of spuit het mengsel terug in de eiwitten. Bestrooi met paprikapoeder en bieslook.",
            verwacht: [
                "Kook de eieren in 8 min. hard. Laat ze schrikken onder koud water en pel ze.",
                "Snijd de eieren in de lengte doormidden en schep de dooiers eruit.",
                "Prak de dooiers met de mayonaise, mosterd en kerriepoeder tot een glad mengsel. Breng op smaak met peper en zout.",
                "Schep of spuit het mengsel terug in de eiwitten. Bestrooi met paprikapoeder en bieslook.",
            ]),
        Voorbeeld(
            blad: "Delicious (1.5 el, bijv.)",
            tekst:
                "Week de rijstnoedels ca. 10 min. in heet water en laat ze uitlekken. Meng voor de dressing het limoensap, de vissaus, 1.5 el suiker en de fijngehakte rode peper. Snijd de komkommer, wortel en bosui in dunne reepjes, bijv. met een julienneschiller. Verhit een wok tot hij bijna rookt en roerbak de garnalen in 2 min. roze. Schep de noedels, groente en garnalen om met de dressing. Tot slot: bestrooi met gehakte pinda's, munt en koriander.",
            verwacht: [
                "Week de rijstnoedels ca. 10 min. in heet water en laat ze uitlekken.",
                "Meng voor de dressing het limoensap, de vissaus, 1.5 el suiker en de fijngehakte rode peper.",
                "Snijd de komkommer, wortel en bosui in dunne reepjes, bijv. met een julienneschiller.",
                "Verhit een wok tot hij bijna rookt en roerbak de garnalen in 2 min. roze. Schep de noedels, groente en garnalen om met de dressing.",
                "Tot slot: bestrooi met gehakte pinda's, munt en koriander.",
            ]),
        Voorbeeld(
            blad: "Libelle (uitroepteken)",
            tekst:
                "Snijd de prei in ringen. Was goed! Smoor de prei met een klontje boter 10 min. in een afgedekte pan. Klop de eieren los met de room en de geraspte kaas. Bekleed een quichevorm met het bladerdeeg en prik er met een vork gaatjes in. Verdeel de prei over de bodem en giet het eimengsel erover. Bak de quiche in ca. 35 min. goudbruin en gaar. Serveer warm of koud.",
            verwacht: [
                "Snijd de prei in ringen. Was goed!",
                "Smoor de prei met een klontje boter 10 min. in een afgedekte pan. Klop de eieren los met de room en de geraspte kaas.",
                "Bekleed een quichevorm met het bladerdeeg en prik er met een vork gaatjes in. Verdeel de prei over de bodem en giet het eimengsel erover.",
                "Bak de quiche in ca. 35 min. goudbruin en gaar.",
                "Serveer warm of koud.",
            ]),
        Voorbeeld(
            blad: "NRC (inleidende zin)",
            tekst:
                "Het geheim van deze stoofpot zit in het geduld. Bestuif het vlees met bloem en braad het in porties bruin in een braadpan met boter; doe niet te veel tegelijk, anders gaat het koken in plaats van braden. Haal het vlees eruit en fruit de uien in het braadvet tot ze diep goudbruin zijn, dat duurt zeker een kwartier. Doe het vlees terug in de pan, schenk het bier erbij en voeg de laurier, tijm en kruidnagel toe. Laat met het deksel op de pan op heel laag vuur ca. 3 uur stoven. Het vlees moet uit elkaar vallen. Roer op het laatst de mosterd erdoor.",
            verwacht: [
                "Het geheim van deze stoofpot zit in het geduld. Bestuif het vlees met bloem en braad het in porties bruin in een braadpan met boter; doe niet te veel tegelijk, anders gaat het koken in plaats van braden.",
                "Haal het vlees eruit en fruit de uien in het braadvet tot ze diep goudbruin zijn, dat duurt zeker een kwartier.",
                "Doe het vlees terug in de pan, schenk het bier erbij en voeg de laurier, tijm en kruidnagel toe.",
                "Laat met het deksel op de pan op heel laag vuur ca. 3 uur stoven. Het vlees moet uit elkaar vallen.",
                "Roer op het laatst de mosterd erdoor.",
            ]),
        Voorbeeld(
            blad: "Volkskrant, Peren in rode wijn (zoals Peter het overtypte)",
            tekst:
                "Schil de peren, maar laat zo mogelijk het steeltje eraan zitten. Neem een hoog pannetje waar de peren krap aan in passen. Verwarm er de wijn met de specerijen in en los de suiker op. Doe de peren in de pan en kook ze heel zachtjes een 20 minuten. Draai ze af en toe om. Haal de peren uit de pan en laat ze afkoelen. Roer het zetmeel los met een minidrupje water en voeg dit het kookvocht toe. Laat al roerend binden en kook zachtjes 1 minuut door. Laat afkoelen, zet een paar uur in de koelkast. Overgiet de peren vlak voor het serveren met de saus. Wie wil, doet er vanille-ijs of slagroom bij, maar eigenlijk is dat zonde. Wijn erbij? Welnee.",
            verwacht: [
                "Schil de peren, maar laat zo mogelijk het steeltje eraan zitten. Neem een hoog pannetje waar de peren krap aan in passen.",
                "Verwarm er de wijn met de specerijen in en los de suiker op.",
                "Doe de peren in de pan en kook ze heel zachtjes een 20 minuten. Draai ze af en toe om.",
                "Haal de peren uit de pan en laat ze afkoelen.",
                "Roer het zetmeel los met een minidrupje water en voeg dit het kookvocht toe. Laat al roerend binden en kook zachtjes 1 minuut door.",
                "Laat afkoelen, zet een paar uur in de koelkast.",
                "Overgiet de peren vlak voor het serveren met de saus. Wie wil, doet er vanille-ijs of slagroom bij, maar eigenlijk is dat zonde. Wijn erbij? Welnee.",
            ]),
    ]

    /// Knipt tekst in OCR-regels van ±`breedte` tekens, zoals in een smalle krantenkolom. Lange woorden
    /// worden afgebroken met een streepje ("aardap-" / "pel"); een alinea ("\n") begint een nieuw blok.
    static func ocrRegels(_ tekst: String, breedte: Int = 30) -> [StapSplitser.Stuk] {
        var stukken: [StapSplitser.Stuk] = []
        for (nummer, alinea) in tekst.components(separatedBy: "\n").enumerated() {
            var regel = ""
            var eersteVanAlinea = true
            func sluit() {
                stukken.append(
                    StapSplitser.Stuk(
                        tekst: regel, regel: stukken.count, nieuweAlinea: eersteVanAlinea && nummer > 0))
                eersteVanAlinea = false
                regel = ""
            }
            for woord in alinea.split(separator: " ").map(String.init) {
                let erbij = regel.isEmpty ? woord : regel + " " + woord
                if erbij.count <= breedte {
                    regel = erbij
                    continue
                }
                let ruimte = breedte - regel.count - (regel.isEmpty ? 1 : 2)
                if woord.count >= 8, woord.allSatisfy(\.isLetter), ruimte >= 3, ruimte <= woord.count - 3,
                    woord[woord.index(woord.startIndex, offsetBy: ruimte)].isLowercase
                {
                    let knip = woord.index(woord.startIndex, offsetBy: ruimte)
                    regel = (regel.isEmpty ? "" : regel + " ") + woord[..<knip] + "-"
                    sluit()
                    regel = String(woord[knip...])
                } else {
                    if !regel.isEmpty { sluit() }
                    regel = woord
                }
            }
            if !regel.isEmpty { sluit() }
        }
        return stukken
    }
}

struct StapSplitserTests {
    @Test(arguments: Bereidingen.alle.indices)
    func lopendeTekstInStappen(_ index: Int) {
        let voorbeeld = Bereidingen.alle[index]
        #expect(StapSplitser.stappen(in: voorbeeld.tekst) == voorbeeld.verwacht, "\(voorbeeld.blad)")
        // Hetzelfde over smalle OCR-regels met afgebroken woorden.
        let stukken = Bereidingen.ocrRegels(voorbeeld.tekst)
        #expect(StapSplitser.stappen(stukken).map(\.tekst) == voorbeeld.verwacht, "\(voorbeeld.blad), OCR-regels")
    }

    @Test func achtVoorbeeldenOfMeer() {
        #expect(Bereidingen.alle.count >= 8)
        #expect(Bereidingen.alle.allSatisfy { $0.verwacht.count >= 3 })
        // De OCR-variant breekt echt woorden af.
        let afgebroken = Bereidingen.alle.filter {
            Bereidingen.ocrRegels($0.tekst).contains { $0.tekst.hasSuffix("-") }
        }
        #expect(afgebroken.count >= 5)
    }

    /// Eigenschap: de stappen samen zijn woord voor woord de bron, voor alle voorbeelden en voor
    /// willekeurige teksten (vaste seed), ook met afgebroken OCR-regels.
    @Test func samenWoordVoorWoordDeBron() {
        var generator = Willekeur(seed: 17)
        var teksten = Bereidingen.alle.map(\.tekst)
        for _ in 0..<300 { teksten.append(Willekeur.tekst(&generator)) }
        for tekst in teksten {
            let stappen = StapSplitser.stappen(in: tekst)
            #expect(StapSplitser.isLetterlijk(stappen, bron: tekst), "\(tekst)")
            #expect(stappen.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            for breedte in [18, 30, 45] {
                let stukken = Bereidingen.ocrRegels(tekst, breedte: breedte)
                let ocr = StapSplitser.stappen(stukken)
                #expect(StapSplitser.isLetterlijk(ocr.map(\.tekst), bron: stukken), "\(tekst) / \(breedte)")
                // Elke regel hoort bij minstens één stap; regelnummers op volgorde.
                let regels = ocr.flatMap(\.stukken)
                #expect(Set(regels) == Set(stukken.indices.filter { !stukken[$0].tekst.isEmpty }))
                #expect(regels == regels.sorted())
            }
        }
        #expect(!StapSplitser.isLetterlijk(["Snijd de ui."], bron: "Snijd de ui fijn."))
        #expect(
            StapSplitser.isLetterlijk(
                ["Schenk de groente-", "bouillon erbij."], bron: "Schenk de groentebouillon erbij."))
    }

    @Test func zinsgrenzen() {
        #expect(
            StapSplitser.zinnen(in: "Bak ca. 10 min. op 180 °C. Laat o.a. de ui bijv. 2 min. meegaren. Klaar!")
                == ["Bak ca. 10 min. op 180 °C.", "Laat o.a. de ui bijv. 2 min. meegaren.", "Klaar!"])
        #expect(
            StapSplitser.zinnen(in: "Meng 1.5 el suiker met 2,5 dl melk. Roer.") == [
                "Meng 1.5 el suiker met 2,5 dl melk.", "Roer.",
            ])
        #expect(StapSplitser.zinnen(in: "Bak 10 min. Laat afkoelen.") == ["Bak 10 min.", "Laat afkoelen."])
        #expect(StapSplitser.zinnen(in: "Voor de saus: Smelt de boter.") == ["Voor de saus:", "Smelt de boter."])
        #expect(StapSplitser.zinnen(in: "Recept van J. Jansen. Snijd.") == ["Recept van J. Jansen.", "Snijd."])
    }

    @Test func puntDieWegviel() {
        // Echte OCR: "… los de suiker op" zonder punt, volgende regel "Doe de peren …".
        let stukken = [
            "Verwarm de wijn en los de suiker op", "Doe de peren in de pan en kook ze heel zachtjes een 20 minuten.",
        ]
        .map { StapSplitser.Stuk(tekst: $0) }
        #expect(
            StapSplitser.stappen(stukken).map(\.tekst) == [
                "Verwarm de wijn en los de suiker op",
                "Doe de peren in de pan en kook ze heel zachtjes een 20 minuten.",
            ])
        // Ook midden in een alinea.
        #expect(StapSplitser.zinnen(in: "Verwarm de wijn en los de suiker op Doe de peren erin.").count == 2)
        // Maar een gewone afgebroken zin loopt door.
        let doorlopend = ["Breng op smaak met", "Parmezaanse kaas."].map { StapSplitser.Stuk(tekst: $0) }
        #expect(StapSplitser.stappen(doorlopend).count == 1)
    }

    @Test func regelsEnTwijfelPerStap() {
        let stukken = [
            StapSplitser.Stuk(tekst: "Verwarm de oven voor op 200 °C. Snijd", regel: 10),
            StapSplitser.Stuk(tekst: "de pompoen in blokjes van ca. 2 cm en ver-", regel: 11, laagVertrouwen: true),
            StapSplitser.Stuk(tekst: "deel ze over een bakplaat met bakpapier.", regel: 12),
        ]
        let stappen = StapSplitser.conceptStappen(stukken)
        #expect(
            stappen.map(\.tekst) == [
                "Verwarm de oven voor op 200 °C.",
                "Snijd de pompoen in blokjes van ca. 2 cm en verdeel ze over een bakplaat met bakpapier.",
            ])
        // De tweede stap begint halverwege regel 10: die regel hoort bij beide stappen.
        #expect(stappen[0].regels == [10])
        #expect(stappen[1].regels == [10, 11, 12])
        #expect(!stappen[0].laagVertrouwen)
        #expect(stappen[1].laagVertrouwen)
    }

    @Test func genummerdBlijftZoalsHetWas() {
        let regels = [
            Testpagina.r("Snelle soep", 0.05, 0.05, 0.6, 0.05),
            Testpagina.r("1. Verhit de olie. Fruit de ui. Voeg de tomaten toe", 0.35, 0.15, 0.4, 0.015),
            Testpagina.r("en laat 10 minuten koken. Pureer de soep.", 0.35, 0.17, 0.4, 0.015),
            Testpagina.r("2. Serveer met brood.", 0.35, 0.19, 0.4, 0.015),
        ]
        let concept = ReceptOpbouw.bouw(regels, indeling: Indeling(aantal: 4, titel: [0], bereiding: [1, 2, 3]))
        #expect(
            concept.stappen.map(\.tekst) == [
                "Verhit de olie. Fruit de ui. Voeg de tomaten toe en laat 10 minuten koken. Pureer de soep.",
                "Serveer met brood.",
            ])
    }

    // MARK: - Knippen op beginwoorden (Claude)

    @Test func knipOpBeginwoorden() throws {
        let tekst = Bereidingen.alle[0].tekst
        let stappen = try #require(
            StapSplitser.knip(
                tekst,
                opBeginnen: [
                    "Verwarm de oven voor", "snijd de zoete AARDAPPEL", "Rooster ca 25",
                    "Verdeel de aardappelparten over",
                ]))
        #expect(stappen.count == 4)
        #expect(stappen[1].hasPrefix("Snijd de zoete aardappel"))
        #expect(stappen[1].hasSuffix("peper en zout."))
        #expect(stappen[2].hasSuffix("Meng de yoghurt met de knoflook."))
        #expect(StapSplitser.isLetterlijk(stappen, bron: tekst))
        // Afgebroken woord over twee regels: "groente-" / "bouillon".
        let stukken = ["Fruit de ui. Schenk de groente-", "bouillon erbij en kook 10 min."].map {
            StapSplitser.Stuk(tekst: $0)
        }
        let geknipt = try #require(
            StapSplitser.knip(stukken, opBeginnen: ["Fruit de ui", "Schenk de groentebouillon erbij"]))
        #expect(geknipt.map(\.tekst) == ["Fruit de ui.", "Schenk de groentebouillon erbij en kook 10 min."])
        #expect(geknipt[1].stukken == [0, 1])
    }

    @Test func beginwoordenDieNietKloppen() {
        let tekst = Bereidingen.alle[0].tekst
        #expect(StapSplitser.knip(tekst, opBeginnen: ["Verwarm de oven voor", "Bak de taart"]) == nil)
        // Verkeerde volgorde.
        #expect(StapSplitser.knip(tekst, opBeginnen: ["Rooster ca. 25 min.", "Verwarm de oven voor"]) == nil)
        #expect(StapSplitser.knip(tekst, opBeginnen: []) == nil)
        #expect(StapSplitser.knip(tekst, opBeginnen: ["Verwarm", "  "]) == nil)
        // Dan de regels.
        let stukken = Bereidingen.ocrRegels(tekst)
        #expect(
            StapSplitser.conceptStappen(stukken, beginnen: ["Bak de taart"]).map(\.tekst)
                == Bereidingen.alle[0].verwacht)
    }

    // MARK: - Splitsen en samenvoegen in het controlescherm

    @Test func splitsEnVoegSamen() {
        var concept = ReceptConcept()
        concept.stappen = [
            ConceptRegel(
                tekst: "Verwarm de oven voor op 200 °C. Snijd de ui. Bak ca. 5 min.", laagVertrouwen: true,
                regels: [3, 4]),
            ConceptRegel(tekst: "Serveer warm.", regels: [5]),
        ]
        #expect(StapSplitser.zinnen(in: concept.stappen[0].tekst).count == 3)
        concept.splitsStap(0, voorZin: 2)
        #expect(
            concept.stappen.map(\.tekst) == [
                "Verwarm de oven voor op 200 °C. Snijd de ui.", "Bak ca. 5 min.", "Serveer warm.",
            ])
        #expect(concept.stappen[0].regels == [3, 4] && concept.stappen[1].regels == [3, 4])
        #expect(ReceptOpbouw.isTwijfel(concept.stappen[1], isIngredient: false))
        concept.splitsStap(0, voorZin: 1)
        #expect(concept.stappen.count == 4)
        // Ongeldig: niets.
        concept.splitsStap(3, voorZin: 1)
        concept.splitsStap(9, voorZin: 1)
        concept.voegStapSamenMetVorige(0)
        #expect(concept.stappen.count == 4)

        concept.voegStapSamenMetVorige(3)
        #expect(concept.stappen.last?.tekst == "Bak ca. 5 min. Serveer warm.")
        #expect(concept.stappen.last?.regels == [3, 4, 5])
        #expect(concept.stappen.last?.laagVertrouwen == true)
        concept.voegStapSamenMetVorige(1)
        concept.voegStapSamenMetVorige(1)
        #expect(
            concept.stappen.map(\.tekst) == [
                "Verwarm de oven voor op 200 °C. Snijd de ui. Bak ca. 5 min. Serveer warm."
            ])
    }
}

/// Een eenvoudige, herhaalbare toevalsgenerator voor de eigenschapstest.
struct Willekeur: RandomNumberGenerator {
    var toestand: UInt64
    init(seed: UInt64) { toestand = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        toestand &+= 0x9E37_79B9_7F4A_7C15
        var z = toestand
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    static let begin = [
        "Snijd", "Verwarm", "Doe", "Het deeg", "Intussen", "Laat", "Voeg", "De saus", "Tot slot", "Wie wil",
        "Voor de saus:", "Serveer", "Breng", "Ui", "Meng", "Daarna", "Ik",
    ]
    static let woorden = [
        "de", "ui", "ca.", "10", "min.", "180", "°C.", "bijv.", "o.a.", "1.5", "el", "boter-", "melk", "aardappelpuree",
        "groentebouillon", "fijn", "toe", "op", "smaak", "met", "peper", "en", "zout", "Parmezaanse", "kaas", "(evt.",
        "room)", "J.", "vanille-ijs", "snipperen", "bakken", "goudbruin", "zachtjes", "\"lekker\"", "is", "dat",
    ]
    static let einde = [".", ".", ".", "!", "?", ":", ""]

    static func tekst(_ g: inout Willekeur) -> String {
        var zinnen: [String] = []
        for _ in 0..<Int.random(in: 1...9, using: &g) {
            var zin = [begin.randomElement(using: &g)!]
            for _ in 0..<Int.random(in: 0...14, using: &g) { zin.append(woorden.randomElement(using: &g)!) }
            zinnen.append(zin.joined(separator: " ") + einde.randomElement(using: &g)!)
        }
        return zinnen.joined(separator: Bool.random(using: &g) ? " " : "\n")
    }
}
