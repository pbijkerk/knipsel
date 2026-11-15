import Foundation
import Testing

@testable import Knipsel

/// Fase 7 (K11): tijden uit staptekst. Zinnen in de stijl van krantenrecepten en receptsites, verzonnen.
struct TijdHerkennerTests {
    struct Geval: CustomTestStringConvertible, Sendable {
        let zin: String
        /// Per gevonden tijd: (letterlijke tekst, seconden, ondergrens bij een bereik).
        let tijden: [(String, Int, Int?)]
        var testDescription: String { zin }
    }

    static let gevallen: [Geval] = [
        Geval(zin: "Laat de soep 20 minuten zachtjes koken.", tijden: [("20 minuten", 1200, nil)]),
        Geval(zin: "Bak de uien 20 min. op middelhoog vuur.", tijden: [("20 min", 1200, nil)]),
        Geval(zin: "Dek af en laat het deeg 1 uur rijzen op een warme plek.", tijden: [("1 uur", 3600, nil)]),
        Geval(zin: "Stoof het vlees 1½ uur met de deksel op de pan.", tijden: [("1½ uur", 5400, nil)]),
        Geval(zin: "Laat de stoofpot anderhalf uur pruttelen.", tijden: [("anderhalf uur", 5400, nil)]),
        Geval(zin: "Rooster de bieten 1 uur en 15 minuten in de oven.", tijden: [("1 uur en 15 minuten", 4500, nil)]),
        Geval(zin: "Kook de pasta in 10-15 min beetgaar.", tijden: [("10-15 min", 900, 600)]),
        Geval(zin: "Laat de thee 10 à 15 minuten trekken.", tijden: [("10 à 15 minuten", 900, 600)]),
        Geval(zin: "Klop het eiwit 45 seconden op de hoogste stand.", tijden: [("45 seconden", 45, nil)]),
        Geval(zin: "Laat de taart een half uur afkoelen op een rooster.", tijden: [("een half uur", 1800, nil)]),
        Geval(zin: "Zet de kom een kwartier in de koelkast.", tijden: [("een kwartier", 900, nil)]),
        Geval(zin: "Marineer de kip minimaal twee uur.", tijden: [("twee uur", 7200, nil)]),
        Geval(
            zin:
                "Voeg de pompoen toe en bak 2 minuten mee. Schenk de bouillon erbij en laat 20 minuten zachtjes koken.",
            tijden: [("2 minuten", 120, nil), ("20 minuten", 1200, nil)]),
        Geval(zin: "Laat het vlees 24 uur van tevoren marineren in de yoghurt.", tijden: [("24 uur", 86_400, nil)]),
        Geval(zin: "Keer de vis na 5 minuten voorzichtig om.", tijden: [("5 minuten", 300, nil)]),
        Geval(zin: "Kook de eieren een minuut of zeven.", tijden: [("een minuut of zeven", 420, nil)]),
        Geval(zin: "Laat de rijst drie kwartier wellen.", tijden: [("drie kwartier", 2700, nil)]),
        Geval(zin: "Bak de quiche 1 u 15 min in het midden van de oven.", tijden: [("1 u 15 min", 4500, nil)]),
        Geval(zin: "Laat de linzen vijfentwintig minuten garen.", tijden: [("vijfentwintig minuten", 1500, nil)]),
        Geval(zin: "Gaar de bloemkool in tweeëntwintig minuten.", tijden: [("tweeëntwintig minuten", 1320, nil)]),
        Geval(zin: "Grill de courgette 2-3 minuten per kant.", tijden: [("2-3 minuten", 180, 120)]),
        Geval(zin: "Stoof de rode kool 1,5 uur.", tijden: [("1,5 uur", 5400, nil)]),
        Geval(zin: "Laat de bouillon 2 1/2 uur trekken.", tijden: [("2 1/2 uur", 9000, nil)]),
        Geval(zin: "Laat de pannenkoekbeslag een uurtje rusten.", tijden: [("een uurtje", 3600, nil)]),
        Geval(
            zin: "Laat het deeg 1 uur rijzen en bak daarna 30 minuten.",
            tijden: [("1 uur", 3600, nil), ("30 minuten", 1800, nil)]),
        Geval(zin: "Laat de saus 1 uur en een kwartier sudderen.", tijden: [("1 uur en een kwartier", 4500, nil)]),
        Geval(zin: "Kook de broccoli 2 minuten en 30 seconden.", tijden: [("2 minuten en 30 seconden", 150, nil)]),
        Geval(zin: "Blancheer de boontjes 5 of 6 minuten.", tijden: [("5 of 6 minuten", 360, 300)]),
        Geval(zin: "Laat ½ uur staan voor het aansnijden.", tijden: [("½ uur", 1800, nil)]),
        Geval(zin: "Laat het geheel 10 tot 12 minuten in de oven.", tijden: [("10 tot 12 minuten", 720, 600)]),
        // Geen tijden.
        Geval(zin: "Verwarm de oven voor op 180 °C.", tijden: []),
        Geval(zin: "Voeg 2 el olijfolie en 3 tl komijn toe.", tijden: []),
        Geval(zin: "Dit recept stond in 2019 in de zaterdagkrant.", tijden: []),
        Geval(zin: "Snijd 2 uien en 3 teentjes knoflook fijn.", tijden: []),
        Geval(zin: "Om 18.00 uur aan tafel: begin dus op tijd.", tijden: []),
        Geval(zin: "Zet om 3 uur de oven aan.", tijden: []),
        Geval(zin: "Verdeel over 4 borden en garneer met 1 takje munt.", tijden: []),
        Geval(zin: "Bak op 200-220 °C tot de korst goudbruin is.", tijden: []),
    ]

    @Test(arguments: gevallen)
    func herkent(_ geval: Geval) {
        let gevonden = TijdHerkenner.tijden(in: geval.zin)
        #expect(gevonden.map(\.tekst) == geval.tijden.map { $0.0 })
        #expect(gevonden.map(\.seconden) == geval.tijden.map { $0.1 })
        #expect(gevonden.map(\.vanaf) == geval.tijden.map { $0.2 })
        // Het bereik wijst naar de letterlijke tekst.
        for tijd in gevonden {
            #expect(String(geval.zin[tijd.bereik]) == tijd.tekst)
        }
    }

    @Test func hoofdtijdIsDeLangste() {
        let zin =
            "Voeg de pompoen toe en bak 2 minuten mee. Schenk de bouillon erbij en laat 20 minuten zachtjes koken."
        #expect(TijdHerkenner.hoofdtijd(in: zin)?.seconden == 1200)
        #expect(TijdHerkenner.timerSeconden(in: zin) == 1200)
        #expect(TijdHerkenner.timerSeconden(in: "Verwarm de oven voor op 180 °C.") == 0)
        // Bij gelijke tijden de eerste.
        let gelijk = TijdHerkenner.hoofdtijd(in: "Bak 5 minuten, keer om en bak nog 5 minuten.")
        #expect(gelijk?.bereik.lowerBound == "Bak 5 minuten, keer om en bak nog 5 minuten.".range(of: "5")?.lowerBound)
    }

    @Test func bereikGeeftDeBovengrensMetBereikInBeeld() throws {
        let tijd = try #require(TijdHerkenner.tijden(in: "Kook 10-15 min.").first)
        #expect(tijd.seconden == 900)
        #expect(tijd.isBereik)
        #expect(tijd.label == "10–15 min")
    }

    @Test func belachelijkLangTeltNiet() {
        #expect(TijdHerkenner.tijden(in: "Laat 100 uur staan.").isEmpty)
    }

    @Test func waardenInWoordenEnBreuken() {
        #expect(TijdHerkenner.waarde("anderhalf") == 1.5)
        #expect(TijdHerkenner.waarde("1½") == 1.5)
        #expect(TijdHerkenner.waarde("1 1/2") == 1.5)
        #expect(TijdHerkenner.waarde("2,5") == 2.5)
        #expect(TijdHerkenner.waarde("twintig") == 20)
        #expect(TijdHerkenner.waarde("drieënveertig") == 43)
        #expect(TijdHerkenner.waarde("een half") == 0.5)
        #expect(TijdHerkenner.waarde("onzin") == nil)
    }

    // MARK: - Weergave

    @Test func labels() {
        #expect(Tijdweergave.kort(45) == "45 sec")
        #expect(Tijdweergave.kort(90) == "1 min 30 sec")
        #expect(Tijdweergave.kort(1200) == "20 min")
        #expect(Tijdweergave.kort(3600) == "1 u")
        #expect(Tijdweergave.kort(4500) == "1 u 15 min")
        #expect(Tijdweergave.label(seconden: 10_800, vanaf: 7200) == "2–3 u")
        #expect(Tijdweergave.label(seconden: 5400, vanaf: 3600) == "1 u–1 u 30 min")
    }

    @Test func gesproken() {
        #expect(Tijdweergave.gesproken(1200) == "20 minuten")
        #expect(Tijdweergave.gesproken(60) == "1 minuut")
        #expect(Tijdweergave.gesproken(5400) == "anderhalf uur")
        #expect(Tijdweergave.gesproken(1800) == "een half uur")
        #expect(Tijdweergave.gesproken(4500) == "1 uur en 15 minuten")
        #expect(Tijdweergave.gesproken(45) == "45 seconden")
        #expect(Tijdweergave.resterendGesproken(80) == "1 minuut en 20 seconden")
        #expect(Tijdweergave.resterendGesproken(722) == "12 minuten")
    }

    @Test func klok() {
        #expect(Tijdweergave.klok(1122.3) == "18:43")
        #expect(Tijdweergave.klok(59) == "00:59")
        #expect(Tijdweergave.klok(3909) == "1:05:09")
        #expect(Tijdweergave.klok(-5) == "00:00")
    }

    // MARK: - Timernaam

    @Test func timernaamIsHetZinsdeelMetDeTijd() throws {
        let zin =
            "Voeg de pompoen toe en bak 2 minuten mee. Schenk de bouillon erbij en laat 20 minuten zachtjes koken."
        let tijd = try #require(TijdHerkenner.hoofdtijd(in: zin))
        #expect(Timernaam.naam(stapNummer: 3, tekst: zin, tijd: tijd) == "Stap 3: laat 20 minuten zachtjes koken")
        let eerste = try #require(TijdHerkenner.tijden(in: zin).first)
        #expect(Timernaam.naam(stapNummer: 3, tekst: zin, tijd: eerste) == "Stap 3: bak 2 minuten mee")
        #expect(Timernaam.naam(stapNummer: 2, tekst: "Kook de aardappels.", tijd: nil) == "Stap 2")
        #expect(Timernaam.kort(stapNummer: 2) == "Stap 2")
    }

    @Test func langeTimernaamWordtIngekort() throws {
        let zin =
            "Zet de schaal met de groenten, de kikkererwten en de feta 35 minuten in het midden van de voorverwarmde oven."
        let tijd = try #require(TijdHerkenner.hoofdtijd(in: zin))
        let naam = Timernaam.naam(stapNummer: 4, tekst: zin, tijd: tijd)
        #expect(naam.hasPrefix("Stap 4: de feta 35 minuten"))
        #expect(naam.hasSuffix("…"))
        #expect(naam.count <= "Stap 4: ".count + Timernaam.maximaleLengte)
    }

    // MARK: - Opslaan

    @Test @MainActor func bewarenZetTimerSecondenUitDeTekst() throws {
        let context = legeOpslag().context
        let recept = try pompoensoep(in: context)
        #expect(recept.gesorteerdeStappen.map(\.timerSeconden) == [0, 300, 1200, 0])
        // Bewerken: de tijd volgt de tekst.
        var invoer = ReceptInvoer(recept: recept)
        invoer.stappenTekst = invoer.stappenTekst.replacingOccurrences(of: "20 minuten", with: "anderhalf uur")
        try invoer.bewaar(in: context, recept: recept)
        #expect(recept.gesorteerdeStappen[2].timerSeconden == 5400)
        // Een oud recept zonder timerSeconden: de kookmodus haalt de tijd uit de tekst.
        recept.gesorteerdeStappen[1].timerSeconden = 0
        #expect(recept.gesorteerdeStappen[1].hoofdtijdSeconden == 300)
        let sessie = KookSessie(recept: recept)
        #expect(sessie.stappen.map(\.timerSeconden) == [0, 300, 5400, 0])
        #expect(sessie.stappen[2].tijden.map(\.seconden) == [120, 5400])
        #expect(sessie.stappen[2].hoofdtijd?.seconden == 5400)
    }
}
