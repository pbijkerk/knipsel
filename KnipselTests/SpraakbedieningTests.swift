import Foundation
import Testing

@testable import Knipsel

/// Uitingbeslisser (debounce, stabiliteit, echo) en de koppeling van commando's aan de kookbeurt en het
/// voorlezen, met een nep-spreker.
@MainActor
struct SpraakbedieningTests {
    // MARK: - Uitingbeslisser

    private func beslisser(impliciet: Bool = true) -> Uitingbeslisser {
        Uitingbeslisser(herkenner: CommandoHerkennerTests.herkenner(impliciet: impliciet))
    }

    /// Zoals de herkenner het echt aanlevert: voorlopig resultaat, ± 2 s later het eindresultaat van
    /// dezelfde uiting (met een ander tijdbereik). Elk commando telt één keer.
    @Test func eindresultaatNaVoorlopigVoertNietNogEensUit() {
        var b = beslisser()
        var teller = Uitingteller()
        var nu: TimeInterval = 0
        for (gezegd, verwacht) in [("Volgende", Commando.volgende), ("Vorige", .vorige), ("Herhaal", .herhaal)] {
            #expect(b.verwerk(gezegd, segment: teller.segment(definitief: false), definitief: false, nu: nu) == nil)
            #expect(b.controleer(nu: nu + 0.6) == verwacht)
            #expect(b.verwerk(gezegd, segment: teller.segment(definitief: true), definitief: true, nu: nu + 2) == nil)
            #expect(b.controleer(nu: nu + 2.2) == nil)
            nu += 5
        }
        // Dezelfde opdracht opnieuw, in een nieuwe uiting, telt wel.
        #expect(b.verwerk("Volgende", segment: teller.segment(definitief: true), definitief: true, nu: nu) == .volgende)
    }

    @Test func uitingtellerNummertPerEindresultaat() {
        var teller = Uitingteller()
        #expect(teller.segment(definitief: false) == 0)
        #expect(teller.segment(definitief: false) == 0)
        #expect(teller.segment(definitief: true) == 0)
        #expect(teller.segment(definitief: false) == 1)
        #expect(teller.segment(definitief: true) == 1)
        #expect(teller.segment(definitief: true) == 2)
    }

    @Test func eindresultaatVoertDirectUit() {
        var b = beslisser()
        #expect(b.verwerk("volgende", segment: 1, definitief: true, nu: 0) == .volgende)
    }

    @Test func voorlopigResultaatPasAlsHetStabielIs() {
        var b = beslisser()
        #expect(b.verwerk("volgende", segment: 1, definitief: false, nu: 0) == nil)
        #expect(b.controleer(nu: 0.3) == nil)
        #expect(b.controleer(nu: 0.6) == .volgende)
        // Het eindresultaat van hetzelfde segment voert niet nog eens uit.
        #expect(b.verwerk("volgende", segment: 1, definitief: true, nu: 2) == nil)
    }

    @Test func voorlopigResultaatDatDoorgroeitTeltNiet() {
        var b = beslisser()
        #expect(b.verwerk("volgende", segment: 1, definitief: false, nu: 0) == nil)
        #expect(b.verwerk("volgende pan", segment: 1, definitief: false, nu: 0.3) == nil)
        #expect(b.controleer(nu: 1) == nil)
        #expect(b.verwerk("volgende pan erbij", segment: 1, definitief: true, nu: 2) == nil)
    }

    @Test func stopGaatMeteenOokVoorlopig() {
        var b = beslisser()
        #expect(b.verwerk("stop", segment: 1, definitief: false, nu: 0) == .stop)
        #expect(b.verwerk("stop", segment: 1, definitief: true, nu: 1.5) == nil)
    }

    @Test func impliciteSignalenPasBijHetEindresultaat() {
        var b = beslisser()
        #expect(b.verwerk("ja", segment: 1, definitief: false, nu: 0) == nil)
        #expect(b.controleer(nu: 1) == nil)
        #expect(b.verwerk("ja dat is lekker zeg", segment: 1, definitief: true, nu: 2) == nil)
        #expect(b.verwerk("oké", segment: 2, definitief: true, nu: 3) == .impliciet("oké"))
    }

    @Test func debounceVoorkomtDubbeleUitvoering() {
        var b = beslisser()
        #expect(b.verwerk("volgende", segment: 1, definitief: true, nu: 0) == .volgende)
        // Herkenner splitst dezelfde uiting in twee segmenten: binnen een seconde telt hij niet nog eens.
        #expect(b.verwerk("volgende", segment: 2, definitief: true, nu: 0.6) == nil)
        #expect(b.verwerk("volgende", segment: 3, definitief: true, nu: 2.0) == .volgende)
        // Een ander commando mag wel direct.
        #expect(b.verwerk("terug", segment: 4, definitief: true, nu: 2.2) == .vorige)
    }

    @Test func eigenVoorleestekstTeltNiet() {
        var b = beslisser()
        let voorgelezen = "Stap 2. Verhit de olie in een soeppan en fruit de ui en gember 5 minuten."
        #expect(b.verwerk("stap twee", segment: 1, definitief: true, nu: 0, voorgelezen: voorgelezen) == nil)
        #expect(b.verwerk("Stap 2", segment: 2, definitief: true, nu: 0, voorgelezen: voorgelezen) == nil)
        // Wat Knipsel niet zegt, telt wel.
        #expect(b.verwerk("volgende", segment: 3, definitief: true, nu: 0, voorgelezen: voorgelezen) == .volgende)
        // En "stop" altijd.
        #expect(b.verwerk("stop", segment: 4, definitief: true, nu: 1, voorgelezen: voorgelezen) == .stop)
    }

    @Test func stopInDeVoorleestekstWachtOpDeRestVanDeZin() {
        var b = beslisser()
        let voorgelezen = "Stap 3. Stop de ui in de pan."
        // Knipsel zegt zelf "stop": niet meteen, eerst zien of de zin doorgaat.
        #expect(b.verwerk("stop", segment: 1, definitief: false, nu: 0, voorgelezen: voorgelezen) == nil)
        #expect(b.verwerk("stop de ui", segment: 1, definitief: false, nu: 0.2, voorgelezen: voorgelezen) == nil)
        #expect(b.controleer(nu: 1) == nil)
        // De kok zegt los "stop": dat telt (stabiel of als eindresultaat).
        #expect(b.verwerk("stop", segment: 2, definitief: false, nu: 2, voorgelezen: voorgelezen) == nil)
        #expect(b.controleer(nu: 2.6) == .stop)
    }

    @Test func echofilter() {
        let tekst = "Stap 1. Schil de pompoen, verwijder de pitten en snijd het vruchtvlees in blokjes van 2 cm."
        #expect(Echofilter.isEcho("schil de pompoen", voorgelezen: tekst))
        #expect(Echofilter.isEcho("stap een", voorgelezen: tekst))
        #expect(Echofilter.isEcho("verwijder de pitjes en snijd", voorgelezen: tekst))  // één woord anders
        #expect(!Echofilter.isEcho("volgende", voorgelezen: tekst))
        #expect(!Echofilter.isEcho("stop", voorgelezen: "Stop de ui in de pan."))
        #expect(!Echofilter.isEcho("herhaal", voorgelezen: ""))
    }

    @Test func losWekwoordGeldtVoorDeVolgendeUiting() {
        var b = Uitingbeslisser(
            herkenner: CommandoHerkenner(
                ingredientnamen: [], instellingen: CommandoHerkenner.Instellingen(alleenMetWekwoord: true)))
        #expect(b.verwerk("volgende", segment: 1, definitief: true, nu: 0) == nil)
        // De herkenner maakt van "Knipsel, … herhaal" twee uitingen.
        #expect(b.verwerk("Knipsel", segment: 2, definitief: true, nu: 1) == nil)
        #expect(b.verwerk("herhaal", segment: 3, definitief: true, nu: 2) == .herhaal)
        // Daarna weer zonder wekwoord: niets.
        #expect(b.verwerk("volgende", segment: 4, definitief: true, nu: 4) == nil)
        // En te lang na het wekwoord ook niet.
        #expect(b.verwerk("Knipsel", segment: 5, definitief: true, nu: 10) == nil)
        #expect(b.verwerk("volgende", segment: 6, definitief: true, nu: 20) == nil)
    }

    // MARK: - Koppeling met kookbeurt en voorlezen

    private final class Tempo {
        var waarde = Voorleestempo.standaard
    }

    private func opzet(porties: Int? = nil, aan: Bool = true) throws -> (
        Spraakbediening, KookSessie, VoorleesService, NepSpreker, Tempo
    ) {
        let sessie = KookSessie(recept: try pompoensoep(in: legeOpslag().context), porties: porties)
        let spreker = NepSpreker()
        let tempo = Tempo()
        let voorlezer = VoorleesService(
            spreker: spreker, isAan: aan, instellingen: { Voorleesinstellingen(tempo: tempo.waarde) },
            bewaarTempo: { tempo.waarde = $0 })
        let spraak = Spraakbediening(sessie: sessie, voorlezer: voorlezer, instellingen: .init())
        return (spraak, sessie, voorlezer, spreker, tempo)
    }

    /// Zoals de kookmodus: commando uitvoeren, daarna reageert de voorlezer op de gebeurtenis.
    private func zeg(_ zin: String, _ spraak: Spraakbediening, segment: Int, nu: TimeInterval) {
        let nummer = spraak.sessie.gebeurtenisNummer
        spraak.verwerk(zin, segment: segment, definitief: true, nu: nu)
        if spraak.sessie.gebeurtenisNummer != nummer {
            spraak.voorlezer.reageer(op: spraak.sessie.gebeurtenis, in: spraak.sessie)
        }
    }

    @Test func volgendeLeestDeNieuweStapVoor() throws {
        let (spraak, sessie, _, spreker, _) = try opzet()
        var tikken = 0
        spraak.tik = { tikken += 1 }
        zeg("volgende", spraak, segment: 1, nu: 0)
        #expect(sessie.stapNummer == 2)
        #expect(spreker.uitspraken.last?.hasPrefix("Stap 2.") == true)
        #expect(spraak.melding?.tekst == "✓ volgende")
        #expect(tikken == 1)
        zeg("vorige", spraak, segment: 2, nu: 2)
        #expect(sessie.stapNummer == 1)
        #expect(spreker.uitspraken.last?.hasPrefix("Stap 1.") == true)
    }

    @Test func stopStoptDirect() throws {
        let (spraak, sessie, voorlezer, spreker, _) = try opzet()
        voorlezer.leesHuidigeStap(van: sessie)
        #expect(voorlezer.spreekt)
        spreker.wis()
        spraak.verwerk("stop", segment: 1, definitief: false, nu: 0)
        #expect(spreker.acties == [.stop])
        #expect(!voorlezer.spreekt)
        #expect(sessie.stapNummer == 1)
    }

    @Test func herhaalLeestOpnieuwOokMetLuidsprekerUit() throws {
        let (spraak, _, _, spreker, _) = try opzet(aan: false)
        zeg("herhaal", spraak, segment: 1, nu: 0)
        #expect(spreker.uitspraken.count == 1)
        #expect(spreker.uitspraken.first?.hasPrefix("Stap 1.") == true)
    }

    @Test func langzamerEnSnellerBinnenDeGrenzen() throws {
        let (spraak, _, _, spreker, tempo) = try opzet()
        zeg("langzamer", spraak, segment: 1, nu: 0)
        #expect(tempo.waarde == 0.9)
        #expect(spraak.melding?.tekst.hasPrefix("✓ langzamer") == true)
        zeg("langzamer", spraak, segment: 2, nu: 2)
        zeg("langzamer", spraak, segment: 3, nu: 4)
        #expect(tempo.waarde == 0.8)
        zeg("sneller", spraak, segment: 4, nu: 6)
        zeg("sneller", spraak, segment: 5, nu: 8)
        zeg("sneller", spraak, segment: 6, nu: 10)
        zeg("sneller", spraak, segment: 7, nu: 12)
        zeg("sneller", spraak, segment: 8, nu: 14)
        #expect(tempo.waarde == 1.2)
        // Er werd niet voorgelezen, dus ook niets opnieuw gestart.
        #expect(spreker.uitspraken.isEmpty)
    }

    @Test func tempoTijdensVoorlezenBegintOpnieuw() throws {
        let (spraak, sessie, voorlezer, spreker, _) = try opzet()
        voorlezer.leesHuidigeStap(van: sessie)
        spreker.wis()
        spraak.voerUit(.sneller)
        #expect(spreker.acties.first == .stop)
        #expect(spreker.laatsteTempo == 1.1)
        #expect(spreker.uitspraken.count == 1)
    }

    @Test func hoeveelGeeftGeschaaldeHoeveelheidInBeeldEnHardop() throws {
        let (spraak, _, _, spreker, _) = try opzet(porties: 6)
        zeg("hoeveel bouillon", spraak, segment: 1, nu: 0)
        #expect(spraak.antwoord?.tekst == "1½ l groentebouillon")
        #expect(spraak.antwoord?.titel == "Groentebouillon")
        #expect(spraak.antwoord?.gevonden == true)
        #expect(spreker.uitspraken.last == "anderhalve liter groentebouillon")
    }

    @Test func hoeveelMetHerkenningsfout() throws {
        let (spraak, _, _, spreker, _) = try opzet()
        zeg("hoeveel boulion heb ik nodig", spraak, segment: 1, nu: 0)
        #expect(spraak.antwoord?.tekst == "1 l groentebouillon")
        #expect(spreker.uitspraken.last == "1 liter groentebouillon")
    }

    @Test func hoeveelOnbekendIngredient() throws {
        let (spraak, _, _, spreker, _) = try opzet()
        zeg("hoeveel saffraan", spraak, segment: 1, nu: 0)
        #expect(spraak.antwoord?.gevonden == false)
        #expect(spraak.antwoord?.tekst == Voorleestekst.nietInRecept)
        #expect(spreker.uitspraken.last == "Dat staat niet in dit recept.")
        // Het volgende commando haalt het kaartje weg.
        zeg("volgende", spraak, segment: 2, nu: 2)
        #expect(spraak.antwoord == nil)
    }

    @Test func impliciteOkeEnTerugHerstelt() throws {
        let (spraak, sessie, _, _, _) = try opzet()
        zeg("oké", spraak, segment: 1, nu: 0)
        #expect(sessie.stapNummer == 2)
        #expect(spraak.melding?.tekst == "✓ Volgende (oké)")
        zeg("terug", spraak, segment: 2, nu: 1)
        #expect(sessie.stapNummer == 1)
    }

    @Test func impliciteSignalenUitInInstellingen() throws {
        let (spraak, sessie, _, _, _) = try opzet()
        spraak.instellingen = CommandoHerkenner.Instellingen(impliciet: false)
        zeg("oké", spraak, segment: 1, nu: 0)
        #expect(sessie.stapNummer == 1)
        #expect(spraak.melding == nil)
    }

    @Test func naarStapEnNietBestaandeStap() throws {
        let (spraak, sessie, _, spreker, _) = try opzet()
        zeg("stap drie", spraak, segment: 1, nu: 0)
        #expect(sessie.stapNummer == 3)
        #expect(spreker.uitspraken.last?.hasPrefix("Stap 3.") == true)
        zeg("stap negen", spraak, segment: 2, nu: 2)
        #expect(sessie.stapNummer == 3)
        #expect(spraak.melding?.tekst == "Stap 9 bestaat niet")
    }

    @Test func ingredientenVanDezeStap() throws {
        let (spraak, sessie, _, spreker, _) = try opzet()
        sessie.naarStap(1)
        zeg("wat heb ik nodig", spraak, segment: 1, nu: 0)
        #expect(
            spreker.uitspraken.last == "Je hebt nodig: 2 uien, 3 centimeter verse gember, twee eetlepels olijfolie.")
    }

    @Test func stoppenMetKokenSluit() throws {
        let (spraak, _, _, _, _) = try opzet()
        var gesloten = false
        spraak.sluit = { gesloten = true }
        zeg("stoppen met koken", spraak, segment: 1, nu: 0)
        #expect(gesloten)
    }

    @Test func eigenStemWordtNietAlsCommandoGehoord() throws {
        let (spraak, sessie, voorlezer, _, _) = try opzet()
        voorlezer.leesHuidigeStap(van: sessie)
        // De microfoon vangt het begin van de eigen uitspraak op: "Stap 1".
        zeg("stap een", spraak, segment: 1, nu: 0)
        #expect(sessie.gebeurtenisNummer == 0)
        #expect(spraak.laatsteCommando == nil)
    }

    @Test func hetzelfdeCommandoNietTweeKeerKortNaElkaar() throws {
        let (spraak, sessie, _, _, _) = try opzet()
        zeg("volgende", spraak, segment: 1, nu: 0)
        zeg("volgende", spraak, segment: 2, nu: 0.4)
        #expect(sessie.stapNummer == 2)
        zeg("volgende", spraak, segment: 3, nu: 1.5)
        #expect(sessie.stapNummer == 3)
    }

    @Test func contextwoordenBevattenIngredienten() throws {
        let (spraak, _, _, _, _) = try opzet()
        #expect(spraak.contextwoorden.contains("groentebouillon"))
        #expect(spraak.contextwoorden.contains("volgende"))
    }

    @Test func spraakinstellingenStandaard() {
        let standaarden = UserDefaults(suiteName: "spraak-\(UUID().uuidString)")!
        #expect(Spraakinstellingen.aan(standaarden))
        #expect(Spraakinstellingen.herkenner(standaarden) == CommandoHerkenner.Instellingen())
        standaarden.set(false, forKey: AppConfiguratie.sleutelSpraakImpliciet)
        standaarden.set(true, forKey: AppConfiguratie.sleutelSpraakWekwoord)
        #expect(
            Spraakinstellingen.herkenner(standaarden)
                == CommandoHerkenner.Instellingen(impliciet: false, alleenMetWekwoord: true))
    }
}
