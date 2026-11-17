import CoreData
import Foundation
import Testing

@testable import Knipsel

// #41: het weekmenu. Weken en dagen (begindag, jaargrens, zomertijd), verplaatsen en ruilen, kook dubbel,
// boodschappen met restjes, vandaag, een verwijderd recept, Mijn week en Thuis in twee stores, migratie
// naar modelversie 5 en het Siri-antwoord.

private let amsterdam = TimeZone(identifier: "Europe/Amsterdam")!

private func kal(_ begin: Weekbegin = .maandag) -> Calendar {
    Weekplanning.kalender(weekBegin: begin, tijdzone: amsterdam)
}

private func dag(_ jaar: Int, _ maand: Int, _ dag: Int, uur: Int = 0) -> Date {
    kal().date(from: DateComponents(year: jaar, month: maand, day: dag, hour: uur))!
}

/// Week van ma 23 t/m zo 29 november 2026.
private let ma = dag(2026, 11, 23)
private let di = dag(2026, 11, 24)
private let wo = dag(2026, 11, 25)
private let dond = dag(2026, 11, 26)
private let vr = dag(2026, 11, 27)
private let za = dag(2026, 11, 28)
private let zo = dag(2026, 11, 29)

private let soep = UUID()
private let quiche = UUID()
private let stoof = UUID()

private func maaltijd(
    _ dag: Date, recept: UUID? = nil, titel: String = "", porties: Int = 0, notitie: String? = nil,
    restjesVan: UUID? = nil, id: UUID = UUID()
) -> GeplandeMaaltijd {
    GeplandeMaaltijd(
        id: id, dag: dag, receptUUID: recept, titel: titel, porties: porties, notitie: notitie, restjesVan: restjesVan)
}

struct WeekberekeningTests {
    @Test func weekBegintOpDeGekozenDag() {
        let woensdagMiddag = dag(2026, 11, 25, uur: 15)
        #expect(Weekplanning.weekStart(voor: woensdagMiddag, kalender: kal(.maandag)) == ma)
        #expect(Weekplanning.weekStart(voor: woensdagMiddag, kalender: kal(.zondag)) == dag(2026, 11, 22))
        #expect(Weekplanning.weekStart(voor: woensdagMiddag, kalender: kal(.zaterdag)) == dag(2026, 11, 21))
        // De begindag zelf is het begin.
        #expect(Weekplanning.weekStart(voor: ma, kalender: kal()) == ma)
        #expect(Weekplanning.weekStart(voor: dag(2026, 11, 29, uur: 23), kalender: kal()) == ma)
        #expect(Weekplanning.dagen(vanaf: ma, kalender: kal()) == [ma, di, wo, dond, vr, za, zo])
    }

    @Test func overDeJaargrens() {
        let start = Weekplanning.weekStart(voor: dag(2026, 12, 31, uur: 20), kalender: kal())
        #expect(start == dag(2026, 12, 28))
        let dagen = Weekplanning.dagen(vanaf: start, kalender: kal())
        #expect(dagen.last == dag(2027, 1, 3))
        #expect(Weekplanning.weekTitel(start, kalender: kal()) == "28 dec – 3 jan")
        #expect(Weekplanning.week(start, verschoven: 1, kalender: kal()) == dag(2027, 1, 4))
        #expect(Weekplanning.week(start, verschoven: -1, kalender: kal()) == dag(2026, 12, 21))
    }

    @Test func zomertijdEnWintertijd() {
        let k = kal()
        // Zomertijd begint zo 28 maart 2027, wintertijd zo 31 oktober 2027.
        for start in [dag(2027, 3, 22), dag(2027, 10, 25)] {
            let dagen = Weekplanning.dagen(vanaf: start, kalender: k)
            #expect(dagen.count == 7)
            #expect(Set(dagen).count == 7)
            #expect(dagen.allSatisfy { k.component(.hour, from: $0) == 0 })
            #expect(
                dagen.map { k.component(.day, from: $0) }
                    == Array(k.component(.day, from: start)...(k.component(.day, from: start) + 6)))
            let volgende = Weekplanning.week(start, verschoven: 1, kalender: k)
            #expect(k.component(.hour, from: volgende) == 0)
            #expect(Weekplanning.weekStart(voor: volgende.addingTimeInterval(3600 * 30), kalender: k) == volgende)
        }
        // Een dag van 23 uur blijft één dag.
        #expect(Weekplanning.volgendeDag(dag(2027, 3, 28), kalender: k) == dag(2027, 3, 29))
    }

    @Test func tekstenInHetNederlands() {
        let k = kal()
        #expect(Weekplanning.weekTitel(ma, kalender: k) == "23 – 29 nov")
        #expect(Weekplanning.weekTitel(dag(2026, 11, 30), kalender: k) == "30 nov – 6 dec")
        #expect(Weekplanning.afkorting(wo, kalender: k) == "wo")
        #expect(Weekplanning.dagnaam(ma, kalender: k) == "maandag")
        #expect(Weekplanning.langeDag(dond, kalender: k) == "Donderdag 26 nov")
        #expect(Weekplanning.boodschappenKnop(vanaf: wo, tot: za, kalender: k) == "Boodschappen voor wo – za")
        #expect(Weekplanning.boodschappenKnop(vanaf: zo, tot: zo, kalender: k) == "Boodschappen voor zo")
        #expect(Weekplanning.teller(gepland: 5) == "5 van 7 gepland")
        #expect(Weekplanning.teller(gepland: 0) == "Nog niets gepland")
        #expect(Weekplanning.restjesTitel(bronDag: ma, kalender: k) == "Restjes van maandag")
    }

    @Test func weekbeginStandaardMaandag() {
        let naam = "weekbegin-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: naam)!
        defer { defaults.removePersistentDomain(forName: naam) }
        #expect(Weekbegin.laad(uit: defaults) == .maandag)
        defaults.set(Weekbegin.zaterdag.rawValue, forKey: AppConfiguratie.sleutelWeekBegin)
        #expect(Weekbegin.laad(uit: defaults) == .zaterdag)
    }
}

struct WeekplanningTests {
    @Test func verplaatsNaarEenLegeDag() {
        let a = maaltijd(ma, recept: soep, titel: "Soep")
        let uit = Weekplanning.verplaats(a.id, naar: dag(2026, 11, 26, uur: 18), in: [a], kalender: kal())
        #expect(uit.first?.dag == dond)
    }

    @Test func verplaatsNaarEenBezetteDagRuilt() {
        let a = maaltijd(ma, recept: soep, titel: "Soep")
        let b = maaltijd(wo, recept: quiche, titel: "Quiche")
        let uit = Weekplanning.verplaats(a.id, naar: wo, in: [a, b], kalender: kal())
        #expect(uit.first { $0.id == a.id }?.dag == wo)
        #expect(uit.first { $0.id == b.id }?.dag == ma)
        // Naar dezelfde dag: niets.
        #expect(Weekplanning.verplaats(a.id, naar: ma, in: [a, b], kalender: kal()) == [a, b])
    }

    @Test func eenAvondetenPerDag() {
        let a = maaltijd(ma, recept: soep, titel: "Soep")
        let b = maaltijd(ma, notitie: "Uit eten")
        let uit = Weekplanning.plan(b, in: [a], kalender: kal())
        #expect(uit == [b])
    }

    @Test func kookDubbelZetDeVolgendeDagOpRestjes() throws {
        let a = maaltijd(ma, recept: soep, titel: "Pompoensoep", porties: 4)
        let id = UUID()
        guard case .klaar(let uit) = Weekplanning.kookDubbel(a.id, in: [a], nieuweID: id, kalender: kal()) else {
            Issue.record("geen restjes")
            return
        }
        let restjes = try #require(uit.first { $0.id == id })
        #expect(restjes.dag == di)
        #expect(restjes.soort == .restjes)
        #expect(restjes.restjesVan == a.id)
        #expect(restjes.porties == 4)
        #expect(Weekplanning.inhoud(restjes, alle: uit) { _ in true } == .restjes(titel: "Pompoensoep", bronDag: ma))
        // Nog een keer: niets nieuws.
        #expect(Weekplanning.kookDubbel(a.id, in: uit, kalender: kal()) == .klaar(uit))
    }

    @Test func kookDubbelOpEenBezetteDagVraagtEerst() {
        let a = maaltijd(ma, recept: soep, titel: "Pompoensoep", porties: 4)
        let b = maaltijd(di, recept: quiche, titel: "Prei-quiche", porties: 2)
        #expect(Weekplanning.kookDubbel(a.id, in: [a, b], kalender: kal()) == .bezet(dag: di, door: b))
        // Vervangen.
        guard case .klaar(let vervangen) = Weekplanning.kookDubbel(a.id, vervang: true, in: [a, b], kalender: kal())
        else {
            Issue.record("niet vervangen")
            return
        }
        #expect(!vervangen.contains { $0.id == b.id })
        #expect(vervangen.contains { $0.restjesVan == a.id && $0.dag == di })
        // Of een andere dag.
        guard case .klaar(let anders) = Weekplanning.kookDubbel(a.id, op: wo, in: [a, b], kalender: kal()) else {
            Issue.record("geen andere dag")
            return
        }
        #expect(anders.contains { $0.id == b.id })
        #expect(anders.contains { $0.restjesVan == a.id && $0.dag == wo })
        // Een notitie kun je niet dubbel koken.
        let notitie = maaltijd(vr, notitie: "Uit eten")
        #expect(Weekplanning.kookDubbel(notitie.id, in: [notitie], kalender: kal()) == .kanNiet)
    }

    @Test func wisHaaltOokDeRestjesWeg() {
        let a = maaltijd(ma, recept: soep, titel: "Soep", porties: 4)
        let r = maaltijd(di, titel: "Soep", porties: 4, restjesVan: a.id)
        let b = maaltijd(wo, recept: quiche, titel: "Quiche")
        #expect(Weekplanning.wis(a.id, uit: [a, r, b]) == [b])
        #expect(Weekplanning.wis(r.id, uit: [a, r, b]) == [a, b])
    }

    /// De week uit de schets: soep (4 p, kook dubbel), quiche, uit eten, stoofvlees.
    private var schetsweek: [GeplandeMaaltijd] {
        let a = maaltijd(ma, recept: soep, titel: "Pompoensoep", porties: 4)
        return [
            a,
            maaltijd(di, titel: "Pompoensoep", porties: 4, restjesVan: a.id),
            maaltijd(wo, recept: quiche, titel: "Prei-quiche", porties: 2),
            maaltijd(vr, notitie: "Uit eten"),
            maaltijd(za, recept: stoof, titel: "Stoofvlees met bier", porties: 6),
        ]
    }

    @Test func boodschappenMetRestjesDubbelEnZonderNotities() {
        let k = kal()
        let hele = Weekplanning.boodschappen(schetsweek, vanaf: ma, tot: zo, kalender: k)
        #expect(
            hele == [
                .init(receptUUID: soep, titel: "Pompoensoep", porties: 8),
                .init(receptUUID: quiche, titel: "Prei-quiche", porties: 2),
                .init(receptUUID: stoof, titel: "Stoofvlees met bier", porties: 6),
            ])
        // Vanaf dinsdag: de restjes zijn al gekookt, dus geen soep.
        let vanafDi = Weekplanning.boodschappen(schetsweek, vanaf: di, tot: zo, kalender: k)
        #expect(vanafDi.map(\.receptUUID) == [quiche, stoof])
        // Tot en met vrijdag: zonder stoofvlees.
        #expect(Weekplanning.boodschappen(schetsweek, vanaf: wo, tot: vr, kalender: k).map(\.receptUUID) == [quiche])
    }

    @Test func hetzelfdeReceptTweeKeerIsEenPaar() {
        let week = [
            maaltijd(ma, recept: quiche, titel: "Prei-quiche", porties: 2),
            maaltijd(dond, recept: quiche, titel: "Prei-quiche", porties: 3),
        ]
        #expect(
            Weekplanning.boodschappen(week, vanaf: ma, tot: zo, kalender: kal()) == [
                .init(receptUUID: quiche, titel: "Prei-quiche", porties: 5)
            ])
    }

    @Test func vandaagEnTeller() {
        let k = kal()
        let week = schetsweek
        #expect(Weekplanning.vandaag(week, nu: dag(2026, 11, 25, uur: 17), kalender: k)?.titel == "Prei-quiche")
        #expect(Weekplanning.vandaag(week, nu: dag(2026, 11, 26, uur: 9), kalender: k) == nil)
        #expect(
            Weekplanning.aantalGepland(week, dagen: Weekplanning.dagen(vanaf: ma, kalender: k), kalender: k) == 5)
        #expect(Weekplanning.korteTitel(week[1]) == "Restjes Pompoensoep")
        #expect(Weekplanning.korteTitel(week[3]) == "Uit eten")
    }

    @Test func verwijderdReceptToontDeTerugval() {
        let a = maaltijd(wo, recept: quiche, titel: "Prei-quiche", porties: 2)
        #expect(
            Weekplanning.inhoud(a, alle: [a]) { _ in false }
                == .recept(titel: "Prei-quiche", porties: 2, verwijderd: true))
        #expect(
            Weekplanning.inhoud(a, alle: [a]) { _ in true }
                == .recept(titel: "Prei-quiche", porties: 2, verwijderd: false))
        #expect(Weekplanning.inhoud(nil, alle: []) { _ in true } == .leeg)
    }

    @Test func siriTekst() {
        #expect(Weekplanning.siriVandaag(mijn: nil, thuis: nil) == "Niets gepland voor vandaag.")
        #expect(Weekplanning.siriVandaag(mijn: "Prei-quiche", thuis: nil) == "Vandaag op het menu: Prei-quiche.")
        #expect(Weekplanning.siriVandaag(mijn: nil, thuis: "Stoofvlees") == "Vandaag op het menu: Stoofvlees.")
        #expect(
            Weekplanning.siriVandaag(mijn: "Prei-quiche", thuis: "Stoofvlees")
                == "Vandaag op je menu: Prei-quiche. In Thuis: Stoofvlees.")
        #expect(Weekplanning.siriVandaag(mijn: "Soep", thuis: "Soep") == "Vandaag op het menu: Soep.")
    }
}

@MainActor
struct WeekmenuOpslagTests {
    private func recept(
        _ titel: String, porties: Int = 4, kookboek: Kookboek = .mijn, in context: NSManagedObjectContext
    ) throws -> Recept {
        let recept = try maakRecept(titel, ingredienten: ["2 uien", "500 ml bouillon"], in: context)
        recept.porties = Int16(porties)
        recept.kookboek = kookboek.rawValue
        try context.save()
        return recept
    }

    @Test func plannenTeltNietAlsGekookt() throws {
        let context = legeOpslag().context
        let soep = try recept("Pompoensoep", in: context)
        let gepland = try #require(try Weekmenu.plan(soep, op: wo, context: context, kalender: kal()))
        #expect(gepland.porties == 4)
        #expect(soep.laatstGekooktOp == nil)
        #expect(soep.aantalKeerGekookt == 0)
        let alle = Weekmenu.alle(in: .mijn, context: context)
        #expect(alle.count == 1)
        #expect(alle.first?.receptUUID == soep.uuid?.uuidString)
        #expect(alle.first?.titel == "Pompoensoep")
        #expect(alle.first?.datum == wo)
    }

    @Test func eenPerDagEnRuilenInDeOpslag() throws {
        let context = legeOpslag().context
        let soep = try recept("Pompoensoep", in: context)
        let quiche = try recept("Prei-quiche", porties: 2, in: context)
        try Weekmenu.plan(soep, op: ma, context: context, kalender: kal())
        try Weekmenu.plan(quiche, op: ma, porties: 3, context: context, kalender: kal())
        var week = Weekmenu.waarden(Weekmenu.alle(in: .mijn, context: context))
        #expect(week.map(\.titel) == ["Prei-quiche"])
        #expect(week.first?.porties == 3)
        try Weekmenu.plan(soep, op: wo, context: context, kalender: kal())
        let quicheID = try #require(week.first?.id)
        try Weekmenu.verplaats(quicheID, naar: wo, kookboek: .mijn, context: context, kalender: kal())
        week = Weekmenu.waarden(Weekmenu.alle(in: .mijn, context: context))
        #expect(week.first { $0.titel == "Prei-quiche" }?.dag == wo)
        #expect(week.first { $0.titel == "Pompoensoep" }?.dag == ma)
        try Weekmenu.zetPorties(5, voor: quicheID, kookboek: .mijn, context: context)
        #expect(Weekmenu.waarden(Weekmenu.alle(in: .mijn, context: context)).first { $0.id == quicheID }?.porties == 5)
    }

    @Test func kookDubbelEnNotitieInDeOpslag() throws {
        let context = legeOpslag().context
        let soep = try recept("Pompoensoep", in: context)
        let bron = try #require(try Weekmenu.plan(soep, op: ma, context: context, kalender: kal()))
        try Weekmenu.planNotitie("Uit eten", op: di, kookboek: .mijn, context: context, kalender: kal())
        let uitkomst = try Weekmenu.kookDubbel(bron.id, kookboek: .mijn, context: context, kalender: kal())
        guard case .bezet(let bezetDag, _) = uitkomst else {
            Issue.record("niet bezet")
            return
        }
        #expect(bezetDag == di)
        #expect(Weekmenu.alle(in: .mijn, context: context).count == 2)
        try Weekmenu.kookDubbel(bron.id, vervang: true, kookboek: .mijn, context: context, kalender: kal())
        let week = Weekmenu.waarden(Weekmenu.alle(in: .mijn, context: context))
        #expect(week.count == 2)
        #expect(week.first { $0.dag == di }?.restjesVan == bron.id)
        #expect(Weekplanning.boodschappen(week, vanaf: ma, tot: zo, kalender: kal()).first?.porties == 8)
        // Het recept bij de restjes is de bron.
        let restjes = try #require(week.first { $0.dag == di })
        #expect(Weekmenu.recept(bij: restjes, alle: week, context: context) == soep)
        // Wissen van de bron neemt de restjes mee.
        try Weekmenu.wis(bron.id, kookboek: .mijn, context: context)
        #expect(Weekmenu.alle(in: .mijn, context: context).isEmpty)
    }

    @Test func verwijderdReceptBlijftAlsTerugval() throws {
        let context = legeOpslag().context
        let quiche = try recept("Prei-quiche", in: context)
        let gepland = try #require(try Weekmenu.plan(quiche, op: wo, context: context, kalender: kal()))
        context.delete(quiche)
        try context.save()
        let week = Weekmenu.waarden(Weekmenu.alle(in: .mijn, context: context))
        #expect(week.count == 1)
        #expect(Weekmenu.recept(bij: gepland, alle: week, context: context) == nil)
        let inhoud = Weekplanning.inhoud(week.first, alle: week) {
            ReceptZoeker.recept(id: $0.uuidString, in: context) != nil
        }
        #expect(inhoud == .recept(titel: "Prei-quiche", porties: 4, verwijderd: true))
    }

    /// Mijn week en Thuis: elk in de store van hun kookboek, en ze zien elkaar niet.
    @Test func tweeWekenInTweeStores() throws {
        let opslag = legeOpslag()
        let context = opslag.context
        // Uitgenodigd: Thuis staat in de gedeelde store.
        let thuisCategorie = Categorie(context: context)
        thuisCategorie.naam = "Soepen"
        thuisCategorie.kookboek = Kookboek.thuis.rawValue
        context.assign(thuisCategorie, to: try #require(opslag.gedeeldeStore))
        try context.save()

        let mijnSoep = try recept("Linzensoep", in: context)
        let thuisStoof = try recept("Stoofvlees", kookboek: .thuis, in: context)
        try Weekmenu.plan(mijnSoep, op: wo, context: context, kalender: kal())
        try Weekmenu.plan(thuisStoof, op: wo, context: context, kalender: kal())
        try Weekmenu.planNotitie("Uit eten", op: vr, kookboek: .thuis, context: context, kalender: kal())

        let mijn = Weekmenu.alle(in: .mijn, context: context)
        let thuis = Weekmenu.alle(in: .thuis, context: context)
        #expect(mijn.map(\.titel) == ["Linzensoep"])
        #expect(thuis.compactMap { $0.titel ?? $0.notitie } == ["Stoofvlees", "Uit eten"])
        #expect(mijn.allSatisfy { Kookboeken.soort(van: $0.objectID.persistentStore) == .prive })
        #expect(thuis.allSatisfy { Kookboeken.soort(van: $0.objectID.persistentStore) == .gedeeld })
        // Op dezelfde dag elk een eigen avondeten.
        #expect(Weekmenu.vandaag(in: .mijn, context: context, nu: wo, kalender: kal())?.titel == "Linzensoep")
        #expect(Weekmenu.vandaag(in: .thuis, context: context, nu: wo, kalender: kal())?.titel == "Stoofvlees")
    }

    @Test func thuisWeekGaatInDeShareEnTerugBijStoppen() async throws {
        let opslag = legeOpslag()
        let dienst = NepDeelDienst()
        dienst.context = opslag.context
        let delen = ThuisDelen(opslag: opslag, dienst: dienst)
        let stoof = try recept("Stoofvlees", kookboek: .thuis, in: opslag.context)
        try Weekmenu.plan(stoof, op: za, context: opslag.context, kalender: kal())
        let maaltijd = try #require(Weekmenu.alle(in: .thuis, context: opslag.context).first)
        #expect(Kookboeken.soort(van: maaltijd.objectID.persistentStore) == .prive)
        await delen.deelOpenstaande()
        #expect(dienst.gedeeld.contains(maaltijd.objectID))

        try await delen.stopMetDelen()
        #expect(Weekmenu.alle(in: .thuis, context: opslag.context).isEmpty)
        let mijn = Weekmenu.alle(in: .mijn, context: opslag.context)
        #expect(mijn.map(\.titel) == ["Stoofvlees"])
        // Het recept verhuisde mee (zelfde uuid), dus de maaltijd vindt het terug.
        let waarden = Weekmenu.waarden(mijn)
        let eerste = try #require(waarden.first)
        #expect(Weekmenu.recept(bij: eerste, alle: waarden, context: opslag.context) != nil)
    }

    @Test func siriAntwoordUitDeOpslag() throws {
        let context = legeOpslag().context
        let nu = dag(2026, 11, 25, uur: 17)
        #expect(VandaagIntent.antwoord(in: context, nu: nu, kalender: kal()) == "Niets gepland voor vandaag.")
        let quiche = try recept("Prei-quiche", in: context)
        try Weekmenu.plan(quiche, op: wo, context: context, kalender: kal())
        #expect(VandaagIntent.antwoord(in: context, nu: nu, kalender: kal()) == "Vandaag op het menu: Prei-quiche.")
        #expect(
            VandaagIntent.antwoord(in: context, nu: dag(2026, 11, 26, uur: 17), kalender: kal())
                == "Niets gepland voor vandaag.")
    }

    @Test func velBegintMetDeGeplandePorties() throws {
        let context = legeOpslag().context
        let soep = try recept("Pompoensoep", in: context)
        let vel = VelRecept(soep, porties: 8)
        #expect(vel.standaard == 4)
        #expect(vel.start == 8)
        #expect(VelRecept(soep).start == nil)
    }

    @Test func modelversie5() throws {
        let entiteit = try #require(Opslag.model.entitiesByName["Maaltijd"])
        #expect(entiteit.relationshipsByName.isEmpty)
        #expect(entiteit.attributesByName["kookboek"]?.defaultValue as? String == "mijn")
        for naam in [
            "uuid", "datum", "receptUUID", "titel", "porties", "notitie", "restjesVanUUID", "kookboek", "aangemaaktOp",
        ] {
            #expect(entiteit.attributesByName[naam] != nil, "\(naam)")
        }
    }

    /// Een bestaande database van modelversie 4 opent met modelversie 5: recepten en de
    /// boodschappenlijst intact, het weekmenu leeg.
    @Test func bestaandeV4DatabaseOpent() throws {
        let momd = try #require(Bundle(for: Recept.self).url(forResource: "Knipsel", withExtension: "momd"))
        let v4 = try #require(NSManagedObjectModel(contentsOf: momd.appendingPathComponent("Knipsel 4.mom")))
        #expect(v4.entitiesByName["Maaltijd"] == nil)
        #expect(v4.entitiesByName["BoodschappenItem"] != nil)

        let map = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: map, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: map) }
        let oud = NSPersistentContainer(name: "Knipsel", managedObjectModel: v4)
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
        recept.setValue(Int16(4), forKey: "porties")
        let item = NSEntityDescription.insertNewObject(forEntityName: "BoodschappenItem", into: c)
        item.setValue("3 uien", forKey: "tekst")
        item.setValue("mijn", forKey: "kookboek")
        try c.save()
        for store in oud.persistentStoreCoordinator.persistentStores {
            try oud.persistentStoreCoordinator.remove(store)
        }

        let nieuw = Opslag(map: map, cloudKitContainer: nil)
        #expect(nieuw.laadfout == nil)
        let recepten = try nieuw.context.fetch(Recept.verzoek())
        #expect(recepten.map(\.titel) == ["Oude pompoensoep"])
        #expect(recepten.first?.uuid == uuid)
        #expect(Boodschappenlijsten.items(in: .mijn, context: nieuw.context).map(\.tekstOfNaam) == ["3 uien"])
        #expect(Weekmenu.alle(in: .mijn, context: nieuw.context).isEmpty)
        let oudRecept = try #require(recepten.first)
        try Weekmenu.plan(oudRecept, op: wo, context: nieuw.context, kalender: kal())
        #expect(Weekmenu.alle(in: .mijn, context: nieuw.context).first?.porties == 4)
    }
}
