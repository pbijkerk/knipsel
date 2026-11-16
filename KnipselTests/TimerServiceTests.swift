import Foundation
import Testing

@testable import Knipsel

/// Nep-alarmklok: houdt bij wat er gepland, gepauzeerd en gestopt is, zonder AlarmKit.
@MainActor
final class NepWekker: Wekker {
    var toegestaan = true
    var maximum = 10
    private(set) var gepland: [KookTimer] = []
    private(set) var acties: [String] = []
    private(set) var standen: [WekkerStand] = []
    private var vervolg: AsyncStream<[WekkerStand]>.Continuation?

    func vraagToestemming() async -> Bool { toegestaan }

    func plan(_ timer: KookTimer) async throws {
        guard standen.count < maximum else { throw TimerFout.teVeel }
        gepland.append(timer)
        acties.append("plan \(timer.naam)")
        standen.append(WekkerStand(id: timer.id, toestand: .loopt))
    }

    func pauzeer(_ id: UUID) throws {
        acties.append("pauzeer")
        zet(id, .gepauzeerd)
    }
    func hervat(_ id: UUID) throws {
        acties.append("hervat")
        zet(id, .loopt)
    }
    func annuleer(_ id: UUID) throws {
        acties.append("annuleer")
        standen.removeAll { $0.id == id }
    }
    func stop(_ id: UUID) throws {
        acties.append("stop")
        standen.removeAll { $0.id == id }
    }

    func huidige() -> [WekkerStand] { standen }

    func wijzigingen() -> AsyncStream<[WekkerStand]> {
        AsyncStream { self.vervolg = $0 }
    }

    /// Van buiten de app: knop op het vergrendelscherm, of het alarm gaat af.
    func zet(_ id: UUID, _ toestand: WekkerStand.Toestand) {
        standen = standen.map { $0.id == id ? WekkerStand(id: id, toestand: toestand) : $0 }
    }

    func haalWeg(_ id: UUID) { standen.removeAll { $0.id == id } }
}

/// Een klok die de test zelf verzet.
@MainActor
final class NepKlok {
    var nu = Date(timeIntervalSince1970: 1_800_000_000)
    func verder(_ seconden: TimeInterval) { nu = nu.addingTimeInterval(seconden) }
}

@MainActor
struct TimerServiceTests {
    private func opzet(standaarden: UserDefaults? = nil) -> (TimerService, NepWekker, NepKlok) {
        let wekker = NepWekker()
        let klok = NepKlok()
        return (TimerService(wekker: wekker, standaarden: standaarden, klok: { klok.nu }), wekker, klok)
    }

    @Test func tweeTimersTegelijkElkMetEigenNaam() async throws {
        let (service, wekker, klok) = opzet()
        let soep = try #require(
            await service.start(
                seconden: 1200, naam: "Stap 3: laat 20 minuten zachtjes koken", kort: "Stap 3", recept: "Pompoensoep",
                stapIndex: 2))
        klok.verder(30)
        let brood = try #require(
            await service.start(seconden: 300, naam: "Stap 4: bak 5 minuten", kort: "Stap 4", recept: "Pompoensoep"))
        #expect(service.timers.count == 2)
        // Het eerst aflopende eerst.
        #expect(service.timers.map(\.id) == [brood.id, soep.id])
        #expect(
            wekker.gepland.map(\.titel) == [
                "Pompoensoep · Stap 3: laat 20 minuten zachtjes koken", "Pompoensoep · Stap 4: bak 5 minuten",
            ])
        #expect(service.timer(soep.id)?.resterend(op: klok.nu) == 1170)
        #expect(service.heeftTimer(recept: "Pompoensoep", stapIndex: 2))
        #expect(!service.heeftTimer(recept: "Pompoensoep", stapIndex: 1))
        #expect(service.eerstvolgende?.id == brood.id)
    }

    @Test func alarmKitConfiguratieDraagtDeNamen() {
        let timer = KookTimer(
            id: UUID(), naam: "Stap 3: laat 20 minuten zachtjes koken", kort: "Stap 3", recept: "Pompoensoep",
            stapIndex: 2, totaal: 1200, eindigtOp: nil, gestartOp: .now)
        let configuratie = AlarmKitWekker.configuratie(voor: timer)
        _ = configuratie
        #expect(AlarmKitWekker.nogEenMinuut == 60)
    }

    @Test func pauzerenHervattenEnStoppen() async throws {
        let (service, wekker, klok) = opzet()
        let timer = try #require(await service.start(seconden: 600, naam: "Stap 1", kort: "Stap 1", recept: "Soep"))
        klok.verder(100)
        service.pauzeer(timer.id)
        #expect(service.timer(timer.id)?.isGepauzeerd == true)
        klok.verder(1000)
        // Gepauzeerd: de tijd staat stil.
        #expect(service.timer(timer.id)?.resterend(op: klok.nu) == 500)
        service.hervat(timer.id)
        klok.verder(200)
        #expect(service.timer(timer.id)?.resterend(op: klok.nu) == 300)
        service.stop(timer.id)
        #expect(service.timers.isEmpty)
        #expect(wekker.acties == ["plan Stap 1", "pauzeer", "hervat", "annuleer"])
    }

    @Test func wijzigingenVanBuitenHoudenDeLijstGelijk() async throws {
        let (service, wekker, klok) = opzet()
        var afgegaan: [String] = []
        service.naAfloop = { afgegaan.append($0.naam) }
        let eerste = try #require(await service.start(seconden: 600, naam: "Stap 1", kort: "Stap 1", recept: "Soep"))
        let tweede = try #require(await service.start(seconden: 900, naam: "Stap 2", kort: "Stap 2", recept: "Soep"))
        klok.verder(60)
        // Pauze op het vergrendelscherm.
        wekker.zet(eerste.id, .gepauzeerd)
        service.verwerk(wekker.huidige())
        #expect(service.timer(eerste.id)?.resterendBijPauze == 540)
        // Verder op het vergrendelscherm.
        klok.verder(30)
        wekker.zet(eerste.id, .loopt)
        service.verwerk(wekker.huidige())
        #expect(service.timer(eerste.id)?.resterend(op: klok.nu) == 540)
        // De tweede gaat af: bovenaan, en Knipsel hoort het één keer.
        wekker.zet(tweede.id, .gaatAf)
        service.verwerk(wekker.huidige())
        service.verwerk(wekker.huidige())
        #expect(service.timers.first?.id == tweede.id)
        #expect(service.timers.first?.gaatAf == true)
        #expect(afgegaan == ["Stap 2"])
        // "Nog 1 min": AlarmKit telt weer af.
        wekker.zet(tweede.id, .loopt)
        service.verwerk(wekker.huidige())
        #expect(service.timer(tweede.id)?.resterend(op: klok.nu) == 60)
        // Gestopt op het vergrendelscherm: weg uit de lijst.
        wekker.haalWeg(tweede.id)
        service.verwerk(wekker.huidige())
        #expect(service.timers.map(\.id) == [eerste.id])
    }

    @Test func netGezetVerdwijntNietDoorEenVerouderdeUpdate() async throws {
        let (service, _, klok) = opzet()
        let timer = try #require(await service.start(seconden: 600, naam: "Stap 1", kort: "Stap 1", recept: "Soep"))
        service.verwerk([])
        #expect(service.timer(timer.id) != nil)
        klok.verder(TimerService.aanloop + 1)
        service.verwerk([])
        #expect(service.timers.isEmpty)
    }

    @Test func eenAfgaandAlarmStoppenIsStopNietAnnuleren() async throws {
        let (service, wekker, _) = opzet()
        let timer = try #require(await service.start(seconden: 60, naam: "Stap 1", kort: "Stap 1", recept: "Soep"))
        wekker.zet(timer.id, .gaatAf)
        service.verwerk(wekker.huidige())
        service.stop(timer.id)
        #expect(wekker.acties.last == "stop")
        #expect(service.timers.isEmpty)
    }

    @Test func teVeelAlarmenGeeftNil() async {
        let (service, wekker, _) = opzet()
        wekker.maximum = 1
        #expect(await service.start(seconden: 60, naam: "A", kort: "A", recept: "") != nil)
        #expect(await service.start(seconden: 60, naam: "B", kort: "B", recept: "") == nil)
        #expect(service.timers.count == 1)
        #expect(await service.start(seconden: 0, naam: "C", kort: "C", recept: "") == nil)
    }

    @Test func zonderToestemmingLooptHijInDeApp() async throws {
        let (service, wekker, klok) = opzet()
        wekker.toegestaan = false
        var afgelopen: [String] = []
        service.naAfloop = { afgelopen.append(Timerzinnen.afgelopen($0)) }
        let timer = try #require(await service.start(seconden: 60, naam: "Stap 2", kort: "Stap 2", recept: "Soep"))
        #expect(timer.isLokaal)
        #expect(service.alleenInApp)
        #expect(wekker.gepland.isEmpty)
        // AlarmKit kent hem niet, maar hij blijft.
        klok.verder(10)
        service.verwerk([])
        #expect(service.timers.count == 1)
        service.tik(nu: klok.nu.addingTimeInterval(30))
        #expect(afgelopen.isEmpty)
        service.tik(nu: klok.nu.addingTimeInterval(60))
        #expect(service.timers.first?.gaatAf == true)
        #expect(afgelopen == ["De timer van stap 2 is klaar."])
        service.tik(nu: klok.nu.addingTimeInterval(90))
        #expect(afgelopen.count == 1)
    }

    @Test func bewaardEnOpgeruimdNaHerstart() async throws {
        let naam = "TimerServiceTests-\(UUID().uuidString)"
        let standaarden = try #require(UserDefaults(suiteName: naam))
        defer { standaarden.removePersistentDomain(forName: naam) }
        let (service, wekker, klok) = opzet(standaarden: standaarden)
        let blijft = try #require(await service.start(seconden: 600, naam: "Stap 1", kort: "Stap 1", recept: "Soep"))
        let weg = try #require(await service.start(seconden: 900, naam: "Stap 2", kort: "Stap 2", recept: "Soep"))

        // De app start opnieuw; AlarmKit kent alleen de eerste nog (de tweede ging af en is gestopt).
        let nieuweKlok = NepKlok()
        nieuweKlok.nu = klok.nu.addingTimeInterval(120)
        let opnieuw = TimerService(wekker: wekker, standaarden: standaarden, klok: { nieuweKlok.nu })
        #expect(opnieuw.timers.count == 2)
        wekker.haalWeg(weg.id)
        opnieuw.begin()
        #expect(opnieuw.timers.map(\.id) == [blijft.id])
        #expect(opnieuw.timers.first?.naam == "Stap 1")
        #expect(opnieuw.timers.first?.resterend(op: nieuweKlok.nu) == 480)
    }

    @Test func hoeLangNogZinnen() {
        let nu = Date(timeIntervalSince1970: 0)
        let loopt = KookTimer(
            id: UUID(), naam: "Stap 3: koken", kort: "Stap 3", recept: "Soep", totaal: 1200,
            eindigtOp: nu.addingTimeInterval(722), gestartOp: nu)
        var pauze = KookTimer(
            id: UUID(), naam: "Stap 5", kort: "Stap 5", recept: "Soep", totaal: 300, eindigtOp: nil, gestartOp: nu)
        pauze.resterendBijPauze = 80
        var klaar = pauze
        klaar.gaatAf = true
        #expect(Timerzinnen.hoeLangNog([], nu: nu) == "Er loopt geen timer.")
        #expect(Timerzinnen.hoeLangNog([loopt], nu: nu) == "Stap 3: nog 12 minuten.")
        #expect(
            Timerzinnen.hoeLangNog([loopt, pauze], nu: nu)
                == "Stap 3: nog 12 minuten. Stap 5: gepauzeerd, nog 1 minuut en 20 seconden.")
        #expect(Timerzinnen.hoeLangNog([klaar], nu: nu) == "Stap 5: klaar.")
        #expect(Timerzinnen.vraag(seconden: 1200) == "Zal ik een timer van 20 minuten zetten?")
    }
}

// MARK: - Live Activity

@MainActor
final class NepActivityMotor: KookActivityMotor {
    private(set) var gestart: [KookActivityAttributes] = []
    private(set) var updates: [KookActivityAttributes.ContentState] = []
    private(set) var gestopt = 0

    func start(_ attributen: KookActivityAttributes, staat: KookActivityAttributes.ContentState) {
        gestart.append(attributen)
        updates.append(staat)
    }

    func werkBij(_ staat: KookActivityAttributes.ContentState) { updates.append(staat) }
    func stop() { gestopt += 1 }
}

@MainActor
struct KookActivityTests {
    private let nu = Date(timeIntervalSince1970: 1_800_000_000)

    private func timer(_ kort: String, over seconden: TimeInterval?, gaatAf: Bool = false) -> KookTimer {
        var timer = KookTimer(
            id: UUID(), naam: kort, kort: kort, recept: "Soep", totaal: 600,
            eindigtOp: seconden.map { nu.addingTimeInterval($0) }, gestartOp: nu)
        if seconden == nil { timer.resterendBijPauze = 90 }
        timer.gaatAf = gaatAf
        if gaatAf { timer.eindigtOp = nil }
        return timer
    }

    @Test func inhoudMetDeEerstvolgendeTimer() {
        let staat = KookActivityInhoud.staat(
            stapNummer: 3, aantalStappen: 7, stapTekst: "Laat 20 minuten zachtjes koken.", isAfgerond: false,
            timers: [timer("Stap 5", over: 600), timer("Stap 3", over: 120), timer("Stap 1", over: nil)], nu: nu)
        #expect(staat.kop == "Stap 3 van 7")
        #expect(staat.stapTekst == "Laat 20 minuten zachtjes koken.")
        #expect(staat.aantalTimers == 3)
        #expect(staat.timer?.naam == "Stap 3")
        #expect(staat.timer?.einde == nu.addingTimeInterval(120))
        #expect(staat.timer?.begin == nu)
    }

    @Test func afgaandGaatVoorEnGepauzeerdAlsLaatste() {
        let afgaand = KookActivityInhoud.eerstvolgende(
            [timer("Stap 2", over: 30), timer("Stap 4", over: nil, gaatAf: true)], nu: nu)
        #expect(afgaand == .init(naam: "Stap 4", gaatAf: true))
        let gepauzeerd = KookActivityInhoud.eerstvolgende([timer("Stap 1", over: nil)], nu: nu)
        #expect(gepauzeerd == .init(naam: "Stap 1", resterend: 90))
        #expect(KookActivityInhoud.eerstvolgende([], nu: nu) == nil)
    }

    @Test func langeStapWordtIngekort() {
        let lang = String(repeating: "Roer de saus regelmatig door ", count: 10)
        let kort = KookActivityInhoud.ingekort(lang)
        #expect(kort.count <= KookActivityInhoud.maximaleTekst)
        #expect(kort.hasSuffix("…"))
        #expect(
            KookActivityInhoud.staat(
                stapNummer: 7, aantalStappen: 7, stapTekst: "", isAfgerond: true, timers: [], nu: nu
            ).kop == "Klaar")
    }

    @Test func beheerStartWerktBijAlleenBijVeranderingEnStopt() throws {
        let motor = NepActivityMotor()
        let beheer = KookActivityBeheer(motor: motor)
        let sessie = KookSessie(recept: try pompoensoep(in: legeOpslag().context))
        beheer.start(sessie, timers: [], nu: nu)
        #expect(motor.gestart.map(\.titel) == ["Pompoensoep met gember"])
        #expect(beheer.isActief)
        // Niets veranderd: geen update (ook niet als de tijd verstrijkt).
        beheer.werkBij(sessie, timers: [], nu: nu.addingTimeInterval(5))
        #expect(motor.updates.count == 1)
        sessie.volgende()
        beheer.werkBij(sessie, timers: [], nu: nu)
        #expect(motor.updates.last?.stapNummer == 2)
        let loopt = timer("Stap 2", over: 300)
        beheer.werkBij(sessie, timers: [loopt], nu: nu)
        beheer.werkBij(sessie, timers: [loopt], nu: nu.addingTimeInterval(10))
        #expect(motor.updates.count == 3)
        #expect(motor.updates.last?.timer?.naam == "Stap 2")
        // Een andere (oude) sessie doet niets.
        let ander = KookSessie(recept: try pompoensoep(in: legeOpslag().context))
        beheer.werkBij(ander, timers: [], nu: nu)
        beheer.stop(ander)
        #expect(motor.updates.count == 3)
        #expect(motor.gestopt == 0)
        // Sluiten (of Gekookt): stoppen, en daarna niets meer.
        beheer.stop(sessie)
        beheer.stop(sessie)
        beheer.werkBij(sessie, timers: [], nu: nu)
        #expect(motor.gestopt == 1)
        #expect(!beheer.isActief)
    }
}
