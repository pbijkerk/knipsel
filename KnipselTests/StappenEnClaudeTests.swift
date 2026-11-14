import Foundation
import Testing

@testable import Knipsel

/// De echte Volkskrant-foto (#17): verwachte stappen volgens de regels.
enum PerenVerwacht {
    static let stappen = [
        "Schil de peren, maar laat zo mogelijk het steeltje eraan zitten. Neem een hoog pannetje waar de peren krap aan in passen.",
        "Verwarm er de wijn met de specerijen in en los de suiker op",
        "Doe de peren in de pan en kook ze heel zachtjes een 20 minuten. Draai ze af en toe om.",
        "Haal de peren uit de pan en laat ze afkoelen.",
        "Roer het zetmeel los met een minidrupje water en voeg bij het kookvocht. Laat al roerend binden en kook zachtjes 1 minuut door.",
        "Laat afkoelen, zet een paar uur in de koelkast.",
        "Overgiet de peren vlak voor het serveren met de saus. Wie wil, doet er vanille-ijs of slagroom bij, maar eigenlijk is dat zonde. Wijn erbij? Welnee.",
    ]
    static let ingredienten = [
        "4 handperen (ze hoeven niet helemaal rijp te zijn)", "1 fles rode wijn", "1 kruidnagel", "½ steranijs",
        "snufje kaneel", "150 gram suiker", "1 dikke theel. aardappelzetmeel",
    ]
}

struct PerenInRodeWijnTests {
    /// Echte OCR → regels → recept: de column is intro, de bereiding begint zonder kopje bij "Schil de
    /// peren", de ingrediënten staan in een kader onderaan, het e-mailadres valt weg.
    @Test func eindTotEindMetDeRegels() {
        let regels = PerenInRodeWijn.regels
        let indeling = RegelIndeler.deelIn(regels, categorieen: Testpagina.categorieen, labels: Testpagina.labels)
        let concept = ReceptOpbouw.bouw(regels, indeling: indeling)
        #expect(concept.titel == "Peren in rode wijn")
        #expect(concept.porties == 4)
        #expect(concept.intro.hasPrefix("Nagerecht voor 4 personen lühwein, bisschopswijn"))
        #expect(concept.intro.contains("Onderdeel ervan was het inkoken van het kookvocht tot er stroop overbleef."))
        #expect(concept.intro.hasSuffix("Beslist niet minder lekker."))
        #expect(concept.ingredienten.map(\.tekst) == PerenVerwacht.ingredienten)
        #expect(concept.stappen.map(\.tekst) == PerenVerwacht.stappen)
        #expect(concept.stappen.first?.regels == [50, 51, 52, 53])
        let alles = ([concept.titel, concept.intro] + concept.ingredienten.map(\.tekst) + concept.stappen.map(\.tekst))
            .joined(separator: " ")
        #expect(!alles.contains("@"))
        #expect(indeling.rollen[71] == .weg)
        #expect(indeling.blokken(.stap) == Array(50...70))
        #expect(indeling.categorieen.contains("Nagerechten"))
    }

    @Test func bereidingBeginInEenColumn() {
        func r(_ t: String, _ y: CGFloat, x: CGFloat = 0.1, b: CGFloat = 0.28) -> HerkendeRegel {
            Testpagina.r(t, x, y, b, 0.013)
        }
        // Verhalende zinnen met kookwoorden, ook een gebiedende met "mijn" erin: geen bereiding.
        let column = [
            r("Kook ze nooit te hard, zei mijn moe-", 0.10), r("der altijd. Onderdeel ervan was het", 0.115),
            r("inkoken van het vocht. Laat ik eer-", 0.13), r("lijk zijn: ik vond het lekker.", 0.145, b: 0.2),
            r("Snijd je de peren, dan huil je.", 0.16, x: 0.12, b: 0.2),
        ]
        #expect(RegelIndeler.bereidingBegin(Array(0..<column.count), in: column) == nil)
        // Een nieuwe alinea met een gebiedende zin en daarna vooral handelingen: daar begint het.
        let metRecept =
            column + [
                r("Schil de peren. Neem een pan-", 0.175, x: 0.12), r("netje. Verwarm de wijn en los de", 0.19),
                r("suiker op. Doe de peren erin.", 0.205),
            ]
        #expect(RegelIndeler.bereidingBegin(Array(0..<metRecept.count), in: metRecept) == 5)
        #expect(RegelIndeler.isAfzender("volkskeuken@volkskrant.nl"))
        #expect(RegelIndeler.isAfzender("www.voorbeeld.nl"))
        #expect(!RegelIndeler.isAfzender("Schil de peren."))
        #expect(StapSplitser.isGebiedend("Schil de peren, maar laat zo mogelijk het steeltje eraan zitten."))
        #expect(!StapSplitser.isGebiedend("Onderdeel ervan was het inkoken van het kookvocht."))
        #expect(!StapSplitser.isGebiedend("Laat ik eerlijk zijn."))
        #expect(!StapSplitser.isGebiedend("Kook je de peren, dan huil je."))
        #expect(!StapSplitser.isGebiedend("Was het lekker?"))
    }
}

extension ClaudeIndelerTests {
    static func antwoord(stappen: String) -> String {
        """
        {"titel":[0],"intro":[\((1...49).map(String.init).joined(separator: ","))],\
        "ingredienten":[\((73...79).map(String.init).joined(separator: ","))],"stappen":\(stappen),\
        "categorieen":["Nagerechten"],"labels":[]}
        """
    }

    static let claudeStappen = """
        [{"regels":[50,51,52,53],"begin":"Schil de peren, maar"},{"regels":[54,55],"begin":"Verwarm er de wijn"},\
        {"regels":[56,57,58],"begin":"Doe de peren in"},{"regels":[58],"begin":"Draai ze af en"},\
        {"regels":[58,59,60],"begin":"Haal de peren uit"},{"regels":[60,61,62,63,64],"begin":"Roer het zetmeel los"},\
        {"regels":[64,65],"begin":"Laat afkoelen, zet een"},{"regels":[66,67,68,69,70],"begin":"Overgiet de peren vlak"}]
        """

    func bouw(_ tekst: String) async -> (Indeling, ReceptConcept) {
        NepAnthropic.zet(tekst: tekst)
        let indeling = await indeler().deelIn(
            PerenInRodeWijn.regels, categorieen: Testpagina.categorieen, labels: Testpagina.labels)
        return (indeling, ReceptOpbouw.bouw(PerenInRodeWijn.regels, indeling: indeling))
    }

    @Test func stappenOpBeginwoordenVanClaude() async throws {
        let (indeling, concept) = await bouw(Self.antwoord(stappen: Self.claudeStappen))
        #expect(indeling.bron == .claude)
        #expect(indeling.stapBeginnen.count == 8)
        #expect(indeling.blokken(.stap) == Array(50...70))
        #expect(concept.stappen.count == 8)
        #expect(concept.stappen[3].tekst == "Draai ze af en toe om.")
        #expect(concept.stappen[3].regels == [58])
        #expect(concept.stappen[4].regels == [58, 59, 60])
        #expect(
            StapSplitser.isLetterlijk(concept.stappen.map(\.tekst), bron: PerenVerwacht.stappen.joined(separator: " ")))
        // De opdracht vraagt om beginwoorden en noemt de column vooraf.
        let (_, body) = try #require(NepAnthropic.verzoeken.first)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let systeem = try #require(json["system"] as? String)
        #expect(systeem.contains("\"begin\""))
        #expect(systeem.contains("zonder kopje"))
        #expect(json["max_tokens"] as? Int == 2048)
    }

    @Test func ontbrekendBeginGeeftDeRegels() async {
        let zonderBegin = Self.claudeStappen.replacingOccurrences(of: #","begin":"Draai ze af en""#, with: "")
        let (indeling, concept) = await bouw(Self.antwoord(stappen: zonderBegin))
        #expect(indeling.bron == .claude)
        #expect(indeling.stapBeginnen.isEmpty)
        #expect(concept.stappen.map(\.tekst) == PerenVerwacht.stappen)
    }

    @Test func beginwoordenDieNietMatchenGevenDeRegels() async {
        let verzonnen = Self.claudeStappen.replacingOccurrences(of: "Draai ze af en", with: "Keer de peren om")
        let (indeling, concept) = await bouw(Self.antwoord(stappen: verzonnen))
        #expect(indeling.stapBeginnen.count == 8)
        #expect(concept.stappen.map(\.tekst) == PerenVerwacht.stappen)
    }

    @Test func oudFormaatMetBereidingWerktNog() async {
        let oud = """
            {"titel":[0],"intro":[1],"ingredienten":[73,74,75,76,77,78,79],\
            "bereiding":[\((50...70).map(String.init).joined(separator: ","))]}
            """
        let (indeling, concept) = await bouw(oud)
        #expect(indeling.bron == .claude)
        #expect(indeling.stapBeginnen.isEmpty)
        #expect(concept.stappen.map(\.tekst) == PerenVerwacht.stappen)
    }

    // MARK: - Stappen opnieuw indelen

    static let bestaand =
        "Verwarm de oven voor op 200 °C. Snijd de pompoen in blokjes van ca. 2 cm en verdeel ze over een bakplaat met bakpapier. Rooster ca. 25 min. tot ze gaar zijn.\n\nPureer de pompoen met de bouillon."

    @MainActor @Test func opnieuwIndelenMetDeRegels() async {
        NepAnthropic.zet(tekst: "{}")
        let model = StappenHerindeling(stappenTekst: Self.bestaand)
        #expect(model.voor.count == 2)
        #expect(
            model.na == [
                "Verwarm de oven voor op 200 °C.",
                "Snijd de pompoen in blokjes van ca. 2 cm en verdeel ze over een bakplaat met bakpapier. Rooster ca. 25 min. tot ze gaar zijn.",
                "Pureer de pompoen met de bouillon.",
            ])
        #expect(model.isGewijzigd)
        await model.deelInMetClaude(sleutel: nil, sessie: NepAnthropic.sessie)
        #expect(NepAnthropic.verzoeken.isEmpty)
        #expect(model.bron == .regels)

        // Annuleer: het formulier blijft zoals het was. Bewaar: de nieuwe stappen erin.
        var invoer = ReceptInvoer()
        invoer.titel = "Pompoen"
        invoer.stappenTekst = Self.bestaand
        let ongewijzigd = invoer
        #expect(invoer == ongewijzigd)
        model.pasToe(op: &invoer)
        #expect(ReceptInvoer.regels(invoer.stappenTekst) == model.na)
        #expect(invoer.titel == "Pompoen")
    }

    @MainActor @Test func opnieuwIndelenMetClaude() async throws {
        NepAnthropic.zet(
            tekst:
                #"{"stappen":["Verwarm de oven voor","Snijd de pompoen in","Rooster ca. 25 min.","Pureer de pompoen met"]}"#
        )
        let model = StappenHerindeling(stappenTekst: Self.bestaand)
        await model.deelInMetClaude(sleutel: "test-sleutel-niet-echt", sessie: NepAnthropic.sessie)
        #expect(model.bron == .claude)
        #expect(model.na.count == 4)
        #expect(model.na[2] == "Rooster ca. 25 min. tot ze gaar zijn.")
        // Alleen de bereidingstekst gaat mee, als één blok.
        let (_, body) = try #require(NepAnthropic.verzoeken.first)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let berichten = try #require(json["messages"] as? [[String: Any]])
        let inhoud = try #require(berichten.first?["content"] as? String)
        #expect(inhoud.hasPrefix("Bereiding:\nVerwarm de oven"))
        #expect(json["system"] as? String == ClaudeIndeler.opdrachtStappen)
    }

    @MainActor @Test func opnieuwIndelenValtTerug() async {
        let regels = StappenHerindeling(stappenTekst: Self.bestaand).na
        for (status, tekst) in [
            (200, #"{"stappen":["Verwarm de oven voor","Bak de taart"]}"#), (200, "Sorry."), (500, "{}"),
            (200, #"{"stappen":[]}"#),
        ] {
            NepAnthropic.zet(status: status, tekst: tekst)
            let model = StappenHerindeling(stappenTekst: Self.bestaand)
            await model.deelInMetClaude(sleutel: "test-sleutel-niet-echt", sessie: NepAnthropic.sessie)
            #expect(model.bron == .regels, "\(tekst)")
            #expect(model.na == regels)
            #expect(!model.isBezig)
        }
    }
}
