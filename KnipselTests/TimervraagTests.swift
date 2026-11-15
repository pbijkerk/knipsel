import Foundation
import Testing

@testable import Knipsel

/// Fase 7: de timervraag na het voorlezen ("Zal ik een timer van 20 minuten zetten?"), de
/// timercommando's van de spraakbediening en de Siri-opdrachten voor timers.
///
/// De toestand "timervraag": na het uitspreken van de vraag telt "ja"/"oké"/"klaar" `Timervraag.venster`
/// (8 s) lang als ja. Een uiting die in dat venster begon, telt ook als het eindresultaat (± 2 s later)
/// erna binnenkomt. Daarbuiten is "oké" weer "volgende".
@MainActor
struct TimervraagTests {
    struct Opzet {
        let spraak: Spraakbediening
        let sessie: KookSessie
        let voorlezer: VoorleesService
        let spreker: NepSpreker
        let timers: TimerService
        let wekker: NepWekker
        let klok: NepKlok
    }

    private func opzet(impliciet: Bool = true, stap: Int = 2) throws -> Opzet {
        let sessie = KookSessie(recept: try pompoensoep(in: legeOpslag().context))
        let spreker = NepSpreker()
        let klok = NepKlok()
        let voorlezer = VoorleesService(
            spreker: spreker, isAan: true, instellingen: { Voorleesinstellingen() }, bewaarTempo: { _ in },
            klok: { klok.nu })
        let wekker = NepWekker()
        let timers = TimerService(wekker: wekker, klok: { klok.nu })
        let spraak = Spraakbediening(
            sessie: sessie, voorlezer: voorlezer, instellingen: .init(impliciet: impliciet), timers: timers)
        voorlezer.magTimerVragen = { sessie, stap in !timers.heeftTimer(recept: sessie.titel, stapIndex: stap.id) }
        sessie.naarStap(stap)
        return Opzet(
            spraak: spraak, sessie: sessie, voorlezer: voorlezer, spreker: spreker, timers: timers, wekker: wekker,
            klok: klok)
    }

    /// Leest de stap voor en spreekt hem helemaal uit; daarna klinkt de vraag (ook uitgesproken).
    private func leesStapEnVraag(_ o: Opzet) {
        o.voorlezer.leesHuidigeStap(van: o.sessie)
        o.spreker.spreekUit()
        o.spreker.spreekUit()
    }

    /// De Task die de timer zet, even laten lopen.
    private func wachtOpTimer(_ o: Opzet) async {
        for _ in 0..<100 where o.timers.timers.isEmpty { await Task.yield() }
    }

    @Test func naHetVoorlezenVraagtKnipselOmEenTimer() throws {
        let o = try opzet()
        o.voorlezer.leesHuidigeStap(van: o.sessie)
        #expect(o.spreker.uitspraken.count == 1)
        #expect(o.voorlezer.timervraag == nil)
        o.spreker.spreekUit()
        #expect(o.spreker.uitspraken.last == "Zal ik een timer van 20 minuten zetten?")
        #expect(o.voorlezer.timervraag?.seconden == 1200)
        #expect(o.voorlezer.timervraag?.uitgesprokenOp == nil)
        #expect(o.voorlezer.openTimervraag() != nil)
        o.spreker.spreekUit()
        #expect(o.voorlezer.timervraag?.uitgesprokenOp == o.klok.nu)
        // Daarna niets meer: Knipsel wacht.
        #expect(o.spreker.uitspraken.count == 2)
    }

    @Test func stapZonderTijdVraagtNiets() throws {
        let o = try opzet(stap: 0)
        leesStapEnVraag(o)
        #expect(o.spreker.uitspraken.count == 1)
        #expect(o.voorlezer.timervraag == nil)
    }

    @Test func jaBinnenHetVensterZetDeTimer() async throws {
        let o = try opzet()
        leesStapEnVraag(o)
        o.klok.verder(3)
        o.spraak.verwerk("Ja", segment: 1, definitief: true, nu: 3)
        await wachtOpTimer(o)
        #expect(o.sessie.stapNummer == 3)
        #expect(o.timers.timers.map(\.naam) == ["Stap 3: laat 20 minuten zachtjes koken"])
        #expect(o.wekker.gepland.first?.titel == "Pompoensoep met gember · Stap 3: laat 20 minuten zachtjes koken")
        #expect(o.spraak.melding?.tekst == "✓ Timer 20 min")
        #expect(o.voorlezer.timervraag == nil)
        // Een tweede keer voorlezen vraagt niet opnieuw: er loopt al een timer voor deze stap.
        o.spreker.wis()
        leesStapEnVraag(o)
        #expect(o.spreker.uitspraken.count == 1)
    }

    @Test func okeBinnenHetVensterIsJaDaarnaWeerVolgende() async throws {
        let o = try opzet()
        leesStapEnVraag(o)
        o.klok.verder(Timervraag.venster + 1)
        #expect(o.voorlezer.openTimervraag() == nil)
        o.spraak.verwerk("oké", segment: 1, definitief: true, nu: 9)
        #expect(o.sessie.stapNummer == 4)
        #expect(o.timers.timers.isEmpty)
        #expect(o.spraak.melding?.tekst == "✓ Volgende (oké)")
    }

    @Test func okeDatInHetVensterBegonTeltAlsHetEindresultaatLaterKomt() async throws {
        let o = try opzet()
        leesStapEnVraag(o)
        o.klok.verder(7)
        o.spraak.verwerk("oké", segment: 1, definitief: false, nu: 7)
        o.klok.verder(3)
        #expect(o.voorlezer.openTimervraag() == nil)
        o.spraak.verwerk("Oké.", segment: 1, definitief: true, nu: 10)
        await wachtOpTimer(o)
        #expect(o.sessie.stapNummer == 3)
        #expect(o.timers.timers.count == 1)
        // Vlak na het antwoord telt een tweede "oké" niet als "volgende"; daarna weer wel.
        o.spraak.verwerk("oké", segment: 2, definitief: true, nu: 11)
        #expect(o.sessie.stapNummer == 3)
        o.klok.verder(Spraakbediening.naAntwoordNegeren + 1)
        o.spraak.verwerk("klaar", segment: 3, definitief: true, nu: 14)
        #expect(o.sessie.stapNummer == 4)
    }

    @Test func jaWerktOokAlsImplicieteSignalenUitStaan() async throws {
        let o = try opzet(impliciet: false)
        leesStapEnVraag(o)
        o.spraak.verwerk("ja graag", segment: 1, definitief: true, nu: 1)
        await wachtOpTimer(o)
        #expect(o.timers.timers.count == 1)
        // Zonder vraag doet "oké" dan niets.
        o.spraak.verwerk("oké", segment: 2, definitief: true, nu: 20)
        #expect(o.sessie.stapNummer == 3)
    }

    @Test func neeSluitDeVraag() throws {
        let o = try opzet()
        leesStapEnVraag(o)
        o.spraak.verwerk("nee hoor", segment: 1, definitief: true, nu: 1)
        #expect(o.voorlezer.timervraag == nil)
        #expect(o.sessie.stapNummer == 3)
        #expect(o.spraak.melding?.tekst == "✓ geen timer")
        // Buiten de vraag is "nee" geen commando.
        o.spraak.verwerk("nee", segment: 2, definitief: true, nu: 20)
        #expect(o.sessie.stapNummer == 3)
    }

    @Test func tikOpJaInDeBanner() async throws {
        let o = try opzet()
        leesStapEnVraag(o)
        o.spraak.beantwoordTimervraag(ja: true)
        await wachtOpTimer(o)
        #expect(o.timers.timers.first?.totaal == 1200)
        // Daarna nog "ja" zeggen gaat niet naar de volgende stap.
        o.spraak.verwerk("ja", segment: 1, definitief: true, nu: 1)
        #expect(o.sessie.stapNummer == 3)
    }

    @Test func stopTijdensDeStapSlaatDeVraagOver() throws {
        let o = try opzet()
        o.voorlezer.leesHuidigeStap(van: o.sessie)
        o.spraak.verwerk("stop", segment: 1, definitief: true, nu: 1)
        o.spreker.spreekUit()
        #expect(o.spreker.uitspraken.count == 1)
        #expect(o.voorlezer.timervraag == nil)
    }

    @Test func eenNieuweStapSluitDeVraag() throws {
        let o = try opzet()
        leesStapEnVraag(o)
        o.spraak.verwerk("volgende", segment: 1, definitief: true, nu: 1)
        o.voorlezer.reageer(op: o.sessie.gebeurtenis, in: o.sessie)
        #expect(o.sessie.stapNummer == 4)
        #expect(o.voorlezer.timervraag == nil)
    }

    @Test func verlopenVraagWordtOpgeruimd() throws {
        let o = try opzet()
        leesStapEnVraag(o)
        o.klok.verder(Timervraag.venster + 1)
        o.voorlezer.ruimTimervraagOp()
        #expect(o.voorlezer.timervraag != nil)
        o.klok.verder(VoorleesService.naloopAntwoord + 1)
        o.voorlezer.ruimTimervraagOp()
        #expect(o.voorlezer.timervraag == nil)
    }

    // MARK: - Timercommando's

    @Test func zetDeTimerGebruiktDeTijdVanDeStap() async throws {
        let o = try opzet()
        o.spraak.verwerk("zet de timer", segment: 1, definitief: true, nu: 0)
        await wachtOpTimer(o)
        #expect(o.timers.timers.first?.totaal == 1200)
        #expect(o.timers.timers.first?.stapIndex == 2)
    }

    @Test func timerMetEigenTijd() async throws {
        let o = try opzet()
        o.spraak.verwerk("timer twee minuten", segment: 1, definitief: true, nu: 0)
        await wachtOpTimer(o)
        // Twee minuten staat in deze stap: de naam komt uit dat zinsdeel.
        #expect(o.timers.timers.first?.naam == "Stap 3: bak 2 minuten mee")
        o.spraak.verwerk("zet een timer van 7 minuten", segment: 2, definitief: true, nu: 5)
        for _ in 0..<100 where o.timers.timers.count < 2 { await Task.yield() }
        #expect(o.timers.timers.map(\.naam).contains("Timer 7 min"))
    }

    @Test func zetDeTimerZonderTijdZegtDatEnZetNiets() throws {
        let o = try opzet(stap: 0)
        o.spraak.verwerk("zet de timer", segment: 1, definitief: true, nu: 0)
        #expect(o.spreker.uitspraken.last == Timerzinnen.geenTijdInStap)
        #expect(o.timers.timers.isEmpty)
    }

    @Test func hoeLangNogEnStopDeTimer() async throws {
        let o = try opzet()
        o.spraak.verwerk("zet de timer", segment: 1, definitief: true, nu: 0)
        await wachtOpTimer(o)
        o.klok.verder(8 * 60)
        o.spraak.verwerk("hoe lang nog?", segment: 2, definitief: true, nu: 2)
        #expect(o.spreker.uitspraken.last == "Stap 3: nog 12 minuten.")
        o.spraak.verwerk("stop de timer", segment: 3, definitief: true, nu: 4)
        #expect(o.timers.timers.isEmpty)
        #expect(o.wekker.acties.last == "annuleer")
        #expect(o.spraak.melding?.tekst == "✓ timer stap 3 gestopt")
    }

    // MARK: - Siri

    @Test func siriZetTimerZonderMinutenNeemtDeStap() async throws {
        let o = try opzet()
        let houder = ActieveKookSessie()
        houder.registreer(o.spraak)
        let uitkomst = await TimerOpdrachtUitvoerder.zet(minuten: nil, houder: houder, timers: o.timers)
        #expect(uitkomst == .gezet("Timer van 20 minuten loopt."))
        #expect(o.timers.timers.first?.naam == "Stap 3: laat 20 minuten zachtjes koken")
        #expect(TimerOpdrachtUitvoerder.hoeLangNog(timers: o.timers, nu: o.klok.nu) == "Stap 3: nog 20 minuten.")
    }

    @Test func siriZetTimerMetMinutenEnZonderKookmodus() async throws {
        let o = try opzet()
        let leeg = ActieveKookSessie()
        #expect(await TimerOpdrachtUitvoerder.zet(minuten: nil, houder: leeg, timers: o.timers) == .geenTijd)
        #expect(
            await TimerOpdrachtUitvoerder.zet(minuten: 5, houder: leeg, timers: o.timers)
                == .gezet(
                    "Timer van 5 minuten loopt."))
        #expect(o.timers.timers.first?.naam == "Timer 5 min")
        #expect(o.timers.timers.first?.recept == "")
        #expect(o.wekker.gepland.first?.titel == "Timer 5 min")
        o.wekker.maximum = 1
        #expect(
            await TimerOpdrachtUitvoerder.zet(minuten: 3, houder: leeg, timers: o.timers)
                == .mislukt(TimerOpdrachtUitvoerder.mislukt))
    }
}

/// De timerzinnen in de herkenner en de beslisser.
@MainActor
struct TimerCommandoTests {
    private func herken(_ zin: String, antwoord: Bool = false, impliciet: Bool = true) -> Commando? {
        CommandoHerkenner(
            instellingen: .init(impliciet: impliciet, alleenMetWekwoord: false, antwoordVerwacht: antwoord)
        ).herken(zin)
    }

    @Test func zetten() {
        #expect(herken("Zet de timer") == .zetTimer(seconden: nil))
        #expect(herken("timer") == .zetTimer(seconden: nil))
        #expect(herken("start de timer maar") == .zetTimer(seconden: nil))
        #expect(herken("Timer 10 minuten") == .zetTimer(seconden: 600))
        #expect(herken("zet een timer van vijfentwintig minuten") == .zetTimer(seconden: 1500))
        #expect(herken("zet de timer op anderhalf uur") == .zetTimer(seconden: 5400))
        #expect(herken("Knipsel, timer 45 seconden") == .zetTimer(seconden: 45))
        // Een lange zin met "timer" erin is geen opdracht.
        #expect(herken("ik weet niet waar de timer van mijn oven ligt") == nil)
    }

    @Test func vragenEnStoppen() {
        #expect(herken("Hoe lang nog?") == .hoeLangNog)
        #expect(herken("hoelang nog") == .hoeLangNog)
        #expect(herken("hoeveel minuten nog") == .hoeLangNog)
        // Was tot fase 7 "geen commando".
        #expect(herken("hoeveel tijd nog") == .hoeLangNog)
        #expect(herken("hoe lang duurt het nog") == .hoeLangNog)
        #expect(herken("stop de timer") == .stopTimer)
        #expect(herken("alarm uit") == .stopTimer)
        #expect(herken("zet de wekker uit") == .stopTimer)
        // "Stop" alleen blijft het voorlezen stoppen.
        #expect(herken("stop") == .stop)
    }

    @Test func antwoordAlleenAlsDeVraagOpenStaat() {
        #expect(herken("ja", antwoord: true) == .impliciet("ja"))
        #expect(herken("doe maar", antwoord: true) == .impliciet("doe"))
        #expect(herken("ja graag", antwoord: true, impliciet: false) == .impliciet("ja graag"))
        #expect(herken("nee hoor", antwoord: true) == .weiger)
        #expect(herken("hoeft niet", antwoord: true) == .weiger)
        #expect(herken("geen timer", antwoord: true) == .weiger)
        #expect(herken("nee", antwoord: false) == nil)
        #expect(herken("ja", antwoord: false, impliciet: false) == nil)
        #expect(herken("oké volgende", antwoord: true) == .volgende)
    }

    @Test func stopDieUitgroeitTotStopDeTimer() {
        var b = Uitingbeslisser(herkenner: CommandoHerkenner())
        // Voorlopig "stop": meteen stil.
        #expect(b.verwerk("stop", segment: 1, definitief: false, nu: 0) == .stop)
        // Groeit uit tot "stop de timer": de timer stopt er alsnog bij.
        #expect(b.verwerk("stop de timer", segment: 1, definitief: false, nu: 0.4) == .stopTimer)
        #expect(b.verwerk("Stop de timer.", segment: 1, definitief: true, nu: 2) == nil)
        // Een gewone "stop" in dezelfde uiting telt niet nog eens.
        #expect(b.verwerk("stop", segment: 2, definitief: false, nu: 5) == .stop)
        #expect(b.verwerk("stop", segment: 2, definitief: true, nu: 6) == nil)
    }

    @Test func zetDeTimerWachtOpHetEindresultaat() {
        var b = Uitingbeslisser(herkenner: CommandoHerkenner())
        #expect(b.verwerk("zet de timer", segment: 1, definitief: false, nu: 0) == nil)
        #expect(b.controleer(nu: 1) == nil)
        #expect(
            b.verwerk("zet de timer op 10 minuten", segment: 1, definitief: true, nu: 2) == .zetTimer(seconden: 600))
    }
}
