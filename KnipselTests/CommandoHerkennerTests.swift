import Foundation
import Testing

@testable import Knipsel

/// Zinnen zoals de herkenner ze zou kunnen opleveren (verzonnen), en wat Knipsel ermee moet doen.
struct CommandoHerkennerTests {
    /// Ingrediënten van de pompoensoep plus boter en eieren; index = positie.
    static let namen = [
        "flespompoen", "uien", "verse gember", "olijfolie", "groentebouillon", "kokosmelk", "kerriepoeder",
        "peper en zout", "boter", "eieren",
    ]

    static func herkenner(impliciet: Bool = true, wekwoord: Bool = false) -> CommandoHerkenner {
        CommandoHerkenner(
            ingredientnamen: namen,
            instellingen: CommandoHerkenner.Instellingen(impliciet: impliciet, alleenMetWekwoord: wekwoord))
    }

    struct Geval: CustomTestStringConvertible, Sendable {
        let zin: String
        let verwacht: Commando
        init(_ zin: String, _ verwacht: Commando) {
            self.zin = zin
            self.verwacht = verwacht
        }
        var testDescription: String { "\"\(zin)\"" }
    }

    static let commandos: [Geval] = [
        // Volgende en vorige.
        Geval("volgende", .volgende),
        Geval("Volgende.", .volgende),
        Geval("Volgende stap", .volgende),
        Geval("verder", .volgende),
        Geval("door", .volgende),
        Geval("eh volgende", .volgende),
        Geval("nou, volgende dan", .volgende),
        Geval("Oké, volgende", .volgende),
        Geval("ja volgende graag", .volgende),
        Geval("vorige", .vorige),
        Geval("terug", .vorige),
        Geval("Ga terug", .vorige),
        Geval("vorige stap", .vorige),
        // Herhalen.
        Geval("herhaal", .herhaal),
        Geval("Herhaal dat", .herhaal),
        Geval("nog een keer", .herhaal),
        Geval("nog eens", .herhaal),
        Geval("Wat zei je?", .herhaal),
        Geval("eh, wat zei je", .herhaal),
        // Stoppen en hervatten.
        Geval("stop", .stop),
        Geval("Stop!", .stop),
        Geval("stil", .stop),
        Geval("pauze", .stop),
        Geval("hou op", .stop),
        Geval("stop maar", .stop),
        Geval("lees voor", .hervat),
        Geval("ga door", .hervat),
        Geval("lees maar voor", .hervat),
        // Tempo.
        Geval("langzamer", .langzamer),
        Geval("iets langzamer graag", .langzamer),
        Geval("sneller", .sneller),
        Geval("wat sneller", .sneller),
        // Ingrediënten.
        Geval("ingrediënten", .ingredienten),
        Geval("Ingredienten", .ingredienten),
        Geval("Wat heb ik nodig?", .ingredienten),
        // Hoeveel.
        Geval("hoeveel bouillon", .hoeveel(ingredient: 4, gevraagd: "bouillon")),
        Geval("Hoeveel boter heb ik nodig?", .hoeveel(ingredient: 8, gevraagd: "boter")),
        Geval("hoeveel groentebouillon", .hoeveel(ingredient: 4, gevraagd: "groentebouillon")),
        Geval("hoeveel olie", .hoeveel(ingredient: 3, gevraagd: "olie")),
        Geval("hoeveel gember moet erin", .hoeveel(ingredient: 2, gevraagd: "gember")),
        Geval("hoeveel ui", .hoeveel(ingredient: 1, gevraagd: "ui")),
        Geval("hoeveel uien", .hoeveel(ingredient: 1, gevraagd: "uien")),
        Geval("hoeveel van de kokosmelk", .hoeveel(ingredient: 5, gevraagd: "kokosmelk")),
        Geval("hoeveel kerrie", .hoeveel(ingredient: 6, gevraagd: "kerrie")),
        Geval("hoeveel zout", .hoeveel(ingredient: 7, gevraagd: "zout")),
        Geval("hoeveel eieren", .hoeveel(ingredient: 9, gevraagd: "eieren")),
        Geval("hoeveel pompoen", .hoeveel(ingredient: 0, gevraagd: "pompoen")),
        // Herkenningsfouten: één of twee letters anders.
        Geval("hoeveel boulion", .hoeveel(ingredient: 4, gevraagd: "boulion")),
        Geval("hoeveel bouilon", .hoeveel(ingredient: 4, gevraagd: "bouilon")),
        Geval("hoeveel gemer", .hoeveel(ingredient: 2, gevraagd: "gemer")),
        Geval("hoeveel kokosmelk heb ik", .hoeveel(ingredient: 5, gevraagd: "kokosmelk")),
        Geval("hoeveel saffraan", .hoeveel(ingredient: nil, gevraagd: "saffraan")),
        // Naar een stap, met cijfers en woorden.
        Geval("stap 3", .naarStap(3)),
        Geval("stap drie", .naarStap(3)),
        Geval("Stap één", .naarStap(1)),
        Geval("stap een", .naarStap(1)),
        Geval("ga naar stap twee", .naarStap(2)),
        Geval("naar stap 4", .naarStap(4)),
        Geval("stap twaalf", .naarStap(12)),
        Geval("stap twintig", .naarStap(20)),
        Geval("de derde stap", .naarStap(3)),
        // Stoppen met koken.
        Geval("stoppen met koken", .stoppenMetKoken),
        Geval("klaar met koken", .stoppenMetKoken),
        // Impliciet (standaard aan).
        Geval("oké", .impliciet("oké")),
        Geval("Oke.", .impliciet("oké")),
        Geval("OK", .impliciet("ok")),
        Geval("klaar", .impliciet("klaar")),
        Geval("gedaan", .impliciet("gedaan")),
        Geval("ja", .impliciet("ja")),
        Geval("ja klaar", .impliciet("ja klaar")),
        Geval("zo, klaar", .impliciet("klaar")),
    ]

    @Test(arguments: commandos)
    func herkent(_ geval: Geval) {
        #expect(Self.herkenner().herken(geval.zin) == geval.verwacht)
    }

    static let geenCommandos = [
        "ik pak even de volgende pan erbij",
        "stop de ui in de pan",
        "ja dat is lekker zeg dat het klaar is over tien minuten",
        "de volgende keer doe ik minder zout",
        "kun je de pan even pakken",
        "wat ruikt dat lekker",
        "is het al klaar",
        "ik ben er klaar mee",
        "terug naar de winkel",
        "stop maar in de oven",
        "hoeveel tijd nog",
        "hoeveel minuten moet het koken",
        "hoeveel kost dat",
        "nee",
        "volgende week koken we weer",
        "herhaal dat nooit meer",
        "zet de pan op het vuur",
        "mama waar is de schaar",
        "oké dan doen we dat zo",
        "",
        "eh",
        "ja nee weet ik niet",
        "lekker",
        "de ui is gedaan",
        "stap voor stap",
        "knipselkrant",
        "ik heb de stap overgeslagen",
        "verder roeren tot het kookt",
        "hoeveel",
        "stap",
        "ga even zitten",
    ]

    @Test(arguments: geenCommandos)
    func geenCommando(_ zin: String) {
        #expect(Self.herkenner().herken(zin) == nil)
    }

    @Test func genoegGevallen() {
        #expect(Self.commandos.count >= 40)
        #expect(Self.geenCommandos.count >= 20)
    }

    // MARK: - Lengte

    @Test func langeZinMetCommandowoordTeltNiet() {
        let h = Self.herkenner()
        #expect(h.herken("volgende") == .volgende)
        #expect(h.herken("en nou de volgende stap") == .volgende)  // stopwoordjes tellen niet mee
        #expect(h.herken("pak de volgende stap") == nil)
        #expect(h.herken("ik wil nu wel de volgende stap") == nil)
    }

    @Test func hoeveelMagLangerZijnMaarNietEindeloos() {
        let h = Self.herkenner()
        #expect(h.herken("hoeveel boter heb ik nodig voor dit") == .hoeveel(ingredient: 8, gevraagd: "boter"))
        #expect(h.herken("hoeveel boter heb ik nodig voor dit recept vandaag") == nil)
    }

    // MARK: - Impliciete signalen

    @Test func impliciteSignalenUit() {
        let h = Self.herkenner(impliciet: false)
        for zin in ["oké", "klaar", "gedaan", "ja", "ok", "ja klaar"] {
            #expect(h.herken(zin) == nil, "\(zin)")
        }
        // Expliciete commando's blijven werken, ook met een bevestiging ervoor.
        #expect(h.herken("oké volgende") == .volgende)
        #expect(h.herken("klaar met koken") == .stoppenMetKoken)
    }

    // MARK: - Wekwoord

    @Test func wekwoordIsOptioneel() {
        let h = Self.herkenner()
        #expect(h.herken("Knipsel, volgende") == .volgende)
        #expect(h.herken("volgende Knipsel") == .volgende)
        #expect(h.herken("Hé Knipsel, herhaal") == .herhaal)
    }

    @Test func alleenMetWekwoord() {
        let h = Self.herkenner(wekwoord: true)
        #expect(h.herken("volgende") == nil)
        #expect(h.herken("oké") == nil)
        #expect(h.herken("Knipsel, volgende") == .volgende)
        #expect(h.herken("Knipsels volgende") == .volgende)  // herkenningsfout in het wekwoord
        #expect(h.herken("Knipsel oké") == .impliciet("oké"))
        #expect(h.herken("Knipsel, stap drie") == .naarStap(3))
    }

    @Test func metWekwoordMagDeZinLangerZijn() {
        let h = Self.herkenner(wekwoord: true)
        #expect(h.herken("Knipsel, wil je de volgende stap voorlezen") == .volgende)
        #expect(h.herken("Knipsel, hoeveel boter moet er in de pan") == .hoeveel(ingredient: 8, gevraagd: "boter"))
        #expect(h.herken("Knipsel, ga eens naar stap vier") == .naarStap(4))
        #expect(h.herken("Knipsel, ik wil graag stoppen met koken") == .stoppenMetKoken)
        #expect(h.herken("Knipsel") == nil)
        #expect(h.isAlleenWekwoordVoorTest("Knipsel."))
        #expect(!h.isAlleenWekwoordVoorTest("Knipsel volgende"))
    }

    // MARK: - Getallen en fuzzy match

    @Test func getallenAlsWoord() {
        let woorden = [
            "een", "twee", "drie", "vier", "vijf", "zes", "zeven", "acht", "negen", "tien", "elf", "twaalf", "dertien",
            "veertien", "vijftien", "zestien", "zeventien", "achttien", "negentien", "twintig",
        ]
        for (index, woord) in woorden.enumerated() {
            #expect(CommandoHerkenner.getal(woord) == index + 1)
        }
        #expect(CommandoHerkenner.getal("7") == 7)
        #expect(CommandoHerkenner.getal("pan") == nil)
        #expect(CommandoHerkenner.getal("0") == nil)
    }

    @Test func bijnaGelijk() {
        #expect(CommandoHerkenner.isBijna("boulion", "bouillon"))
        #expect(CommandoHerkenner.isBijna("gemer", "gember"))
        #expect(!CommandoHerkenner.isBijna("boter", "water"))
        #expect(!CommandoHerkenner.isBijna("ui", "ei"))  // te kort om te raden
        #expect(CommandoHerkenner.afstand("kip", "kip") == 0)
        #expect(CommandoHerkenner.afstand("abcd", "abdc") == 1)  // verwisseling
    }

    @Test func zonderIngredientenIsElkeHoeveelOnbekend() {
        let h = CommandoHerkenner()
        #expect(h.herken("hoeveel boter") == .hoeveel(ingredient: nil, gevraagd: "boter"))
    }
}

extension CommandoHerkenner {
    fileprivate func isAlleenWekwoordVoorTest(_ tekst: String) -> Bool { Self.isAlleenWekwoord(tekst) }
}
