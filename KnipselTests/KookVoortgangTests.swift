import CoreData
import Foundation
import Testing

@testable import Knipsel

@MainActor
struct KookVoortgangTests {
    private let nu = Date(timeIntervalSince1970: 1_800_000_000)
    private let soep = URL(string: "x-coredata://test/Recept/p1")!
    private let stoofpot = URL(string: "x-coredata://test/Recept/p2")!

    /// Een eigen, lege `UserDefaults`-suite per test.
    private func voortgang() -> KookVoortgang {
        let naam = "KookVoortgangTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: naam)!
        defaults.removePersistentDomain(forName: naam)
        return KookVoortgang(defaults: defaults)
    }

    @Test func sluitenVanafStapTweeBewaartDeStap() {
        let v = voortgang()
        v.naSluiten(recept: soep, stapIndex: 3, aantalStappen: 7, porties: 6, gekookt: false, nu: nu)
        let stand = v.meestRecente(nu: nu)
        #expect(
            stand == KookVoortgang.Stand(recept: soep, stapIndex: 3, aantalStappen: 7, porties: 6, datum: nu))
        #expect(stand?.stapNummer == 4)
    }

    @Test func sluitenOpStapEenBewaartNiets() {
        let v = voortgang()
        v.naSluiten(recept: soep, stapIndex: 0, aantalStappen: 7, porties: 4, gekookt: false, nu: nu)
        #expect(v.meestRecente(nu: nu) == nil)
    }

    @Test func sluitenOpStapEenLaatEenEerdereStandStaan() {
        let v = voortgang()
        v.naSluiten(recept: soep, stapIndex: 3, aantalStappen: 7, porties: 4, gekookt: false, nu: nu)
        v.naSluiten(recept: soep, stapIndex: 0, aantalStappen: 7, porties: 4, gekookt: false, nu: nu + 60)
        #expect(v.meestRecente(nu: nu + 60)?.stapIndex == 3)
    }

    @Test func gekooktWistDeStand() {
        let v = voortgang()
        v.naSluiten(recept: soep, stapIndex: 3, aantalStappen: 7, porties: 4, gekookt: false, nu: nu)
        v.naSluiten(recept: soep, stapIndex: 6, aantalStappen: 7, porties: 4, gekookt: true, nu: nu + 600)
        #expect(v.meestRecente(nu: nu + 600) == nil)
        #expect(v.alle.isEmpty)
    }

    @Test func perReceptEenStand() {
        let v = voortgang()
        v.naSluiten(recept: soep, stapIndex: 2, aantalStappen: 7, porties: 4, gekookt: false, nu: nu)
        v.naSluiten(recept: soep, stapIndex: 5, aantalStappen: 7, porties: 4, gekookt: false, nu: nu + 60)
        #expect(v.alle.count == 1)
        #expect(v.stand(voor: soep)?.stapIndex == 5)
    }

    @Test func ouderDanZevenDagenTeltNietEnWordtOpgeruimd() {
        let v = voortgang()
        v.naSluiten(recept: soep, stapIndex: 3, aantalStappen: 7, porties: 4, gekookt: false, nu: nu)
        #expect(v.meestRecente(nu: nu + 7 * 24 * 3600 - 1) != nil)
        let later = nu + 7 * 24 * 3600 + 1
        #expect(v.meestRecente(nu: later) == nil)
        v.ruimOp(nu: later)
        #expect(v.alle.isEmpty)
    }

    @Test func alleenDeMeestRecente() {
        let v = voortgang()
        v.naSluiten(recept: soep, stapIndex: 3, aantalStappen: 7, porties: 4, gekookt: false, nu: nu)
        v.naSluiten(recept: stoofpot, stapIndex: 1, aantalStappen: 5, porties: 2, gekookt: false, nu: nu + 3600)
        #expect(v.meestRecente(nu: nu + 7200)?.recept == stoofpot)
        // De oudere blijft bewaard: wis je de nieuwste, dan komt hij terug.
        v.wis(recept: stoofpot)
        #expect(v.meestRecente(nu: nu + 7200)?.recept == soep)
    }

    @Test func onbekendReceptWordtGenegeerd() {
        let v = voortgang()
        v.naSluiten(recept: soep, stapIndex: 3, aantalStappen: 7, porties: 4, gekookt: false, nu: nu)
        v.naSluiten(recept: stoofpot, stapIndex: 1, aantalStappen: 5, porties: 2, gekookt: false, nu: nu + 3600)
        // De stoofpot is verwijderd: dan de soep, niet de stoofpot.
        #expect(v.meestRecente(nu: nu + 7200, bestaat: { $0 != stoofpot })?.recept == soep)
        #expect(v.meestRecente(nu: nu + 7200, bestaat: { _ in false }) == nil)
    }

    @Test func omschrijving() {
        var kalender = Calendar(identifier: .gregorian)
        kalender.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        let stand = KookVoortgang.Stand(recept: soep, stapIndex: 3, aantalStappen: 7, porties: 4, datum: nu)
        #expect(KookVoortgang.omschrijving(stand, nu: nu, kalender: kalender) == "Stap 4 van 7 · vandaag")
        #expect(
            KookVoortgang.omschrijving(stand, nu: nu + 24 * 3600, kalender: kalender) == "Stap 4 van 7 · gisteren")
        #expect(KookVoortgang.wanneer(nu, nu: nu + 2 * 24 * 3600, kalender: kalender) == "eergisteren")
        #expect(KookVoortgang.wanneer(nu, nu: nu + 5 * 24 * 3600, kalender: kalender) == "5 dagen geleden")
    }

    // MARK: - Met een echte kookbeurt

    @Test func afbrekenBijStapVierEnVerderOpStapVier() throws {
        let v = voortgang()
        let opslag = legeOpslag()
        let recept = try pompoensoep(in: opslag.context)
        let uri = recept.objectID.uriRepresentation()

        let sessie = KookSessie(recept: recept, porties: 6)
        sessie.volgende()
        sessie.volgende()
        sessie.volgende()
        #expect(sessie.stapNummer == 4)
        v.naSluiten(sessie, recept: uri, nu: nu)

        let stand = try #require(v.meestRecente(nu: nu))
        #expect(stand.stapNummer == 4)
        #expect(stand.aantalStappen == 4)
        #expect(VerderKeuze.recept(bij: stand.recept, in: opslag.context) == recept)

        let verder = KookSessie(recept: recept, stand: stand)
        #expect(verder.stapNummer == 4)
        #expect(verder.porties == 6)

        // "Gekookt" in de hervatte kookbeurt: weg.
        verder.volgende()
        verder.markeerGekookt()
        v.naSluiten(verder, recept: uri, nu: nu + 60)
        #expect(v.meestRecente(nu: nu + 60) == nil)
    }

    @Test func verwijderdReceptBestaatNietMeer() throws {
        let opslag = legeOpslag()
        let recept = try pompoensoep(in: opslag.context)
        let uri = recept.objectID.uriRepresentation()
        #expect(VerderKeuze.recept(bij: uri, in: opslag.context) != nil)
        opslag.context.delete(recept)
        try opslag.context.save()
        #expect(VerderKeuze.recept(bij: uri, in: opslag.context) == nil)
    }
}
