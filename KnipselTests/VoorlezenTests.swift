import Foundation
import Testing

@testable import Knipsel

/// Nep-spreker: houdt bij wat er gezegd, gestopt en gepauzeerd is, zonder geluid.
@MainActor
final class NepSpreker: Spreker {
    enum Actie: Equatable {
        case spreek(String)
        case stop
        case pauzeer
        case hervat
    }

    var klaar: (() -> Void)?
    private(set) var acties: [Actie] = []
    private(set) var laatsteStem: String?
    private(set) var laatsteTempo: Double?

    var uitspraken: [String] {
        acties.compactMap {
            if case .spreek(let tekst) = $0 { return tekst }
            return nil
        }
    }

    func spreek(_ tekst: String, stem: String?, tempo: Double) {
        acties.append(.spreek(tekst))
        laatsteStem = stem
        laatsteTempo = tempo
    }

    func stop() { acties.append(.stop) }
    func pauzeer() { acties.append(.pauzeer) }
    func hervat() { acties.append(.hervat) }

    /// Alsof de stem klaar is met de zin.
    func spreekUit() { klaar?() }

    func wis() { acties = [] }
}

@MainActor
struct VoorlezenTests {
    private func opzet(
        porties: Int? = nil, instellingen: Voorleesinstellingen = Voorleesinstellingen(), aan: Bool = true
    ) throws -> (KookSessie, VoorleesService, NepSpreker) {
        let sessie = KookSessie(recept: try pompoensoep(in: legeOpslag().context), porties: porties)
        let spreker = NepSpreker()
        let voorlezer = VoorleesService(spreker: spreker, isAan: aan, instellingen: { instellingen })
        return (sessie, voorlezer, spreker)
    }

    /// Zoals de kookmodus het doet: na elke gebeurtenis reageert de voorlezer.
    private func volgende(_ sessie: KookSessie, _ voorlezer: VoorleesService) {
        sessie.volgende()
        voorlezer.reageer(op: sessie.gebeurtenis, in: sessie)
    }

    // MARK: - Voorleestekst

    @Test func stapZonderIngredienten() throws {
        let (sessie, _, _) = try opzet()
        sessie.naarStap(1)
        #expect(
            Voorleestekst.huidigeStap(van: sessie, metIngredienten: false)
                == "Stap 2. Verhit de olie in een soeppan en fruit de ui en gember 5 minuten op middelhoog vuur.")
    }

    @Test func stapMetIngredienten() throws {
        let (sessie, _, _) = try opzet()
        sessie.naarStap(1)
        #expect(
            Voorleestekst.huidigeStap(van: sessie, metIngredienten: true)
                == "Stap 2. Verhit de olie in een soeppan en fruit de ui en gember 5 minuten op middelhoog vuur. Je hebt nodig: 2 uien, 3 centimeter verse gember, twee eetlepels olijfolie."
        )
    }

    @Test func stapMetGeschaaldeIngredienten() throws {
        let (sessie, _, _) = try opzet(porties: 6)
        sessie.naarStap(2)
        let tekst = try #require(Voorleestekst.huidigeStap(van: sessie, metIngredienten: true))
        #expect(tekst.hasPrefix("Stap 3. Voeg de pompoen en het kerriepoeder toe en bak 2 minuten mee."))
        #expect(
            tekst.hasSuffix(
                "Je hebt nodig: anderhalve flespompoen, anderhalve liter groentebouillon, driekwart theelepel kerriepoeder."
            ))
    }

    @Test func naDeLaatsteStapEetSmakelijk() throws {
        let (sessie, _, _) = try opzet()
        sessie.naarStap(3)
        sessie.volgende()
        #expect(Voorleestekst.huidigeStap(van: sessie, metIngredienten: true) == Voorleestekst.afgerond)
    }

    @Test func alleIngredientenGeschaald() throws {
        let (sessie, _, _) = try opzet(porties: 2)
        let tekst = Voorleestekst.alleIngredienten(van: sessie)
        #expect(tekst.hasPrefix("Ingrediënten voor 2 personen. "))
        #expect(tekst.contains("een halve flespompoen, circa een halve kilo. "))
        #expect(tekst.contains("een halve liter groentebouillon."))
        #expect(tekst.contains("een kwart theelepel kerriepoeder."))
        #expect(tekst.contains("één eetlepel olijfolie."))
        #expect(tekst.hasSuffix("peper en zout."))
    }

    @Test func ingredientenMetGroepen() {
        let tekst = Voorleestekst.ingredienten(
            [("Voor de saus", "2 el boter"), ("Voor de saus", "1 el bloem"), (nil, "zout")], porties: nil)
        #expect(tekst == "Ingrediënten. Voor de saus. twee eetlepels boter. één eetlepel bloem. zout.")
    }

    // MARK: - Stapwissel

    @Test func stapwisselStartPreciesEenUitspraakEnStoptDeVorige() throws {
        let (sessie, voorlezer, spreker) = try opzet()
        voorlezer.leesHuidigeStap(van: sessie)
        #expect(spreker.uitspraken.count == 1)
        #expect(voorlezer.status == .spreekt)
        spreker.wis()

        // Midden in stap 1 tikt de kok verder.
        volgende(sessie, voorlezer)
        #expect(spreker.acties.count == 2)
        #expect(spreker.acties.first == .stop)
        #expect(spreker.uitspraken.count == 1)
        #expect(spreker.uitspraken[0].hasPrefix("Stap 2."))
        #expect(voorlezer.status == .spreekt)
    }

    @Test func stapwisselNaHetUitsprekenStoptNiets() throws {
        let (sessie, voorlezer, spreker) = try opzet()
        voorlezer.leesHuidigeStap(van: sessie)
        spreker.spreekUit()
        #expect(voorlezer.status == .stil)
        spreker.wis()
        volgende(sessie, voorlezer)
        #expect(spreker.acties == [.spreek(spreker.uitspraken[0])])
    }

    @Test func naEenStapWachtHij() throws {
        let (sessie, voorlezer, spreker) = try opzet()
        voorlezer.leesHuidigeStap(van: sessie)
        spreker.spreekUit()
        // Klaar met spreken: niet doorgaan naar stap 2, en niets meer zeggen.
        #expect(sessie.stapNummer == 1)
        #expect(sessie.gebeurtenisNummer == 0)
        #expect(spreker.uitspraken.count == 1)
        #expect(voorlezer.status == .stil)
    }

    @Test func herhaalLeestDezelfdeStapOpnieuw() throws {
        let (sessie, voorlezer, spreker) = try opzet()
        sessie.naarStap(2)
        voorlezer.reageer(op: sessie.gebeurtenis, in: sessie)
        sessie.herhaal()
        voorlezer.reageer(op: sessie.gebeurtenis, in: sessie)
        #expect(spreker.uitspraken.count == 2)
        #expect(spreker.uitspraken[0] == spreker.uitspraken[1])
        #expect(sessie.stapNummer == 3)
    }

    @Test func grensZegtNiets() throws {
        let (sessie, voorlezer, spreker) = try opzet()
        sessie.vorige()
        voorlezer.reageer(op: sessie.gebeurtenis, in: sessie)
        #expect(spreker.acties.isEmpty)
    }

    @Test func uitLeestNietsVoor() throws {
        let (sessie, voorlezer, spreker) = try opzet(aan: false)
        volgende(sessie, voorlezer)
        #expect(spreker.acties.isEmpty)
        voorlezer.zetAan(true, sessie: sessie)
        #expect(spreker.uitspraken.count == 1)
        #expect(spreker.uitspraken[0].hasPrefix("Stap 2."))
        voorlezer.zetAan(false)
        #expect(spreker.acties.last == .stop)
        #expect(voorlezer.status == .stil)
    }

    @Test func instellingenGaanMee() throws {
        let instellingen = Voorleesinstellingen(stem: "xander", tempo: 0.9, ingredientenMeelezen: true)
        let (sessie, voorlezer, spreker) = try opzet(instellingen: instellingen)
        voorlezer.leesHuidigeStap(van: sessie)
        #expect(spreker.laatsteStem == "xander")
        #expect(spreker.laatsteTempo == 0.9)
        #expect(spreker.uitspraken[0].contains("Je hebt nodig:"))
    }

    @Test func stopPauzeEnHervat() throws {
        let (sessie, voorlezer, spreker) = try opzet()
        voorlezer.leesHuidigeStap(van: sessie)
        voorlezer.pauzeer()
        #expect(voorlezer.status == .gepauzeerd)
        voorlezer.hervat()
        #expect(voorlezer.status == .spreekt)
        voorlezer.stop()
        #expect(voorlezer.status == .stil)
        #expect(spreker.acties.dropFirst() == [.pauzeer, .hervat, .stop])
        // Stil: nogmaals stoppen doet niets.
        voorlezer.stop()
        #expect(spreker.acties.count == 4)
    }

    @Test func onderbrekingStoptEnPraatNietDoor() throws {
        let (sessie, voorlezer, spreker) = try opzet()
        voorlezer.leesHuidigeStap(van: sessie)
        voorlezer.onderbroken()
        #expect(voorlezer.status == .stil)
        #expect(spreker.acties.last == .stop)
        #expect(spreker.uitspraken.count == 1)
    }

    // MARK: - Tempo en stem

    @Test func tempo() {
        #expect(Voorleestempo.snelheid(1, normaal: 0.5, minimaal: 0, maximaal: 1) == 0.5)
        #expect(abs(Voorleestempo.snelheid(0.8, normaal: 0.5, minimaal: 0, maximaal: 1) - 0.4) < 0.0001)
        #expect(abs(Voorleestempo.snelheid(1.2, normaal: 0.5, minimaal: 0, maximaal: 1) - 0.6) < 0.0001)
        // Buiten 0,8–1,2 begrensd.
        #expect(abs(Voorleestempo.snelheid(3, normaal: 0.5, minimaal: 0, maximaal: 1) - 0.6) < 0.0001)
        #expect(abs(Voorleestempo.snelheid(0.1, normaal: 0.5, minimaal: 0, maximaal: 1) - 0.4) < 0.0001)
        #expect(Voorleestempo.label(1.1) == "1,1×")
    }

    @Test func stemkeuzeBesteEerst() {
        let stemmen = [
            Stem(id: "ellen", naam: "Ellen", taal: "nl-BE", kwaliteit: .premium),
            Stem(id: "xander", naam: "Xander", taal: "nl-NL", kwaliteit: .standaard),
            Stem(id: "claire-v", naam: "Claire", taal: "nl-NL", kwaliteit: .verbeterd),
            Stem(id: "anna", naam: "Anna", taal: "de-DE", kwaliteit: .premium),
            Stem(id: "xander-p", naam: "Xander", taal: "nl-NL", kwaliteit: .premium),
        ]
        #expect(Stemkeuze.gesorteerd(stemmen).map(\.id) == ["xander-p", "claire-v", "xander", "ellen"])
        #expect(Stemkeuze.kies(uit: stemmen, voorkeur: nil)?.id == "xander-p")
        // Eigen keuze gaat voor, ook een mindere of Vlaamse stem.
        #expect(Stemkeuze.kies(uit: stemmen, voorkeur: "ellen")?.id == "ellen")
        // Niet (meer) geïnstalleerd of geen Nederlands: terug naar de beste.
        #expect(Stemkeuze.kies(uit: stemmen, voorkeur: "weg")?.id == "xander-p")
        #expect(Stemkeuze.kies(uit: stemmen, voorkeur: "anna")?.id == "xander-p")
        #expect(Stemkeuze.kies(uit: [], voorkeur: nil) == nil)
    }

    @Test func stemkeuzeZonderVerbeterdeStem() {
        let alleenStandaard = [
            Stem(id: "xander", naam: "Xander", taal: "nl-NL", kwaliteit: .standaard),
            Stem(id: "ellen", naam: "Ellen", taal: "nl-BE", kwaliteit: .standaard),
        ]
        #expect(Stemkeuze.kies(uit: alleenStandaard, voorkeur: nil)?.id == "xander")
        #expect(!Stemkeuze.heeftVerbeterdeStem(alleenStandaard))
        #expect(
            Stemkeuze.heeftVerbeterdeStem(
                alleenStandaard + [Stem(id: "c", naam: "Claire", taal: "nl-NL", kwaliteit: .verbeterd)]))
    }

    @Test func instellingenUitDefaults() throws {
        let standaarden = try #require(UserDefaults(suiteName: "VoorlezenTests"))
        standaarden.removePersistentDomain(forName: "VoorlezenTests")
        #expect(Voorleesinstellingen.huidig(standaarden) == Voorleesinstellingen())
        #expect(Voorleesinstellingen.standaardAan(standaarden))
        standaarden.set(false, forKey: AppConfiguratie.sleutelVoorlezenAan)
        standaarden.set(1.2, forKey: AppConfiguratie.sleutelVoorleesTempo)
        standaarden.set("xander", forKey: AppConfiguratie.sleutelVoorleesStem)
        standaarden.set(true, forKey: AppConfiguratie.sleutelIngredientenMeelezen)
        #expect(!Voorleesinstellingen.standaardAan(standaarden))
        #expect(
            Voorleesinstellingen.huidig(standaarden)
                == Voorleesinstellingen(stem: "xander", tempo: 1.2, ingredientenMeelezen: true))
        standaarden.removePersistentDomain(forName: "VoorlezenTests")
    }
}
