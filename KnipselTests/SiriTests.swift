import CoreData
import Foundation
import MediaPlayer
import Testing

@testable import Knipsel

/// Fase 6: recepten zoeken voor Siri, de kookmodus starten via `KookRouter`, Siri-opdrachten op de
/// lopende kookbeurt, en de AirPods-knoppen en Nu speelt (proef S3), zonder Siri of MediaPlayer.
@MainActor
struct SiriTests {
    // MARK: - ReceptEntiteit en zoeken

    private func bibliotheek() throws -> NSManagedObjectContext {
        let context = legeOpslag().context
        try Inrichting.zaaiStandaard(in: context)
        let soepen = try categorie("Soepen", in: context)
        let soep = try maakRecept(
            "Pompoensoep", ingredienten: ["1 kg pompoen", "1 l bouillon"], categorieen: [soepen], in: context)
        let stamppot = try maakRecept(
            "Stamppot andijvie", ingredienten: ["1 kg aardappels", "300 g andijvie"], in: context)
        let quiche = try maakRecept("Prei-quiche", ingredienten: ["2 stengels prei"], in: context)
        try maakRecept("Losse notitie", in: context)
        for (recept, stappen) in [
            (soep, ["Snijd de pompoen.", "Kook 20 minuten."]), (stamppot, ["Kook de aardappels."]),
            (quiche, ["Bak de prei."]),
        ] {
            for (index, tekst) in stappen.enumerated() {
                let stap = Stap(context: context)
                stap.volgorde = Int16(index)
                stap.tekst = tekst
                stap.recept = recept
            }
        }
        let nu = Date(timeIntervalSince1970: 1_800_000_000)
        soep.aangemaaktOp = nu.addingTimeInterval(-30 * 86_400)
        soep.laatstGekooktOp = nu.addingTimeInterval(-86_400)
        stamppot.aangemaaktOp = nu.addingTimeInterval(-3 * 86_400)
        quiche.aangemaaktOp = nu.addingTimeInterval(-60 * 86_400)
        try context.save()
        return context
    }

    private func recept(_ titel: String, in context: NSManagedObjectContext) throws -> Recept {
        let verzoek = Recept.verzoek()
        verzoek.predicate = NSPredicate(format: "titel == %@", titel)
        return try #require(try context.fetch(verzoek).first)
    }

    @Test func entiteitHeeftUuidTitelEnCategorie() throws {
        let context = try bibliotheek()
        let soep = try recept("Pompoensoep", in: context)
        let entiteit = try #require(ReceptEntiteit(recept: soep))
        #expect(entiteit.id == soep.uuid?.uuidString)
        #expect(entiteit.titel == "Pompoensoep")
        #expect(entiteit.categorie == "Soepen")
        #expect(entiteit.symbool == soep.gesorteerdeCategorieen.first?.symboolOfStandaard)
        let zonder = try #require(ReceptEntiteit(recept: try recept("Prei-quiche", in: context)))
        #expect(zonder.categorie == nil)
        #expect(zonder.symbool == "fork.knife")
    }

    @Test func zoektOpTitelEnIngredient() throws {
        let context = try bibliotheek()
        #expect(try ReceptZoeker.zoek("pompoen", in: context).map(\.titel) == ["Pompoensoep"])
        #expect(try ReceptZoeker.zoek("SOEP", in: context).map(\.titel) == ["Pompoensoep"])
        // Op ingrediënt, net als het zoekveld van de bibliotheek.
        #expect(try ReceptZoeker.zoek("andijvie", in: context).map(\.titel) == ["Stamppot andijvie"])
        #expect(try ReceptZoeker.zoek("prei", in: context).map(\.titel) == ["Prei-quiche"])
        #expect(try ReceptZoeker.zoek("kg", in: context).map(\.titel) == ["Pompoensoep", "Stamppot andijvie"])
        #expect(try ReceptZoeker.zoek("lasagne", in: context).isEmpty)
    }

    @Test func vindtEntiteitenOpIdInGevraagdeVolgorde() throws {
        let context = try bibliotheek()
        let soep = try #require(try recept("Pompoensoep", in: context).uuid?.uuidString)
        let quiche = try #require(try recept("Prei-quiche", in: context).uuid?.uuidString)
        let gevonden = try ReceptZoeker.entiteiten(voor: [quiche, "geen-uuid", UUID().uuidString, soep], in: context)
        #expect(gevonden.map(\.titel) == ["Prei-quiche", "Pompoensoep"])
        #expect(ReceptZoeker.recept(id: soep, in: context)?.titel == "Pompoensoep")
        #expect(ReceptZoeker.recept(id: "onzin", in: context) == nil)
    }

    @Test func suggestiesRecentGekooktOfNieuwMetStappen() throws {
        let context = try bibliotheek()
        // Soep gisteren gekookt, stamppot 3 dagen geleden gemaakt, quiche 60 dagen; de notitie heeft
        // geen stappen en komt er niet in.
        #expect(
            try ReceptZoeker.suggesties(in: context).map(\.titel) == [
                "Pompoensoep", "Stamppot andijvie", "Prei-quiche",
            ])
        #expect(try ReceptZoeker.suggesties(in: context, aantal: 1).map(\.titel) == ["Pompoensoep"])
    }

    @Test func suggestieMomentIsHetRecentste() {
        let oud = Date(timeIntervalSince1970: 0)
        let nieuw = Date(timeIntervalSince1970: 1000)
        #expect(ReceptZoeker.suggestieMoment(gekookt: oud, aangemaakt: nieuw) == nieuw)
        #expect(ReceptZoeker.suggestieMoment(gekookt: nieuw, aangemaakt: nil) == nieuw)
        #expect(ReceptZoeker.suggestieMoment(gekookt: nil, aangemaakt: nil) == .distantPast)
    }

    // MARK: - KookRouter en KookReceptIntent

    @Test func kookReceptIntentStartJuisteReceptMetPorties() throws {
        let context = try bibliotheek()
        let soep = try recept("Pompoensoep", in: context)
        soep.porties = 4
        let router = KookRouter()
        let zin = KookReceptIntent.start(
            recept: try #require(soep.uuid?.uuidString), porties: 6, in: context, router: router)
        #expect(zin == "Kookmodus voor Pompoensoep.")

        let verzoek = try #require(router.neemKookVerzoekAf())
        #expect(router.kookVerzoek == nil)
        #expect(verzoek.recept == soep.objectID.uriRepresentation())
        #expect(verzoek.porties == 6)

        let keuze = try #require(KookRouter.keuze(voor: verzoek, in: context))
        #expect(keuze.recept == soep)
        let sessie = KookSessie(recept: keuze.recept, stand: keuze.stand)
        #expect(sessie.titel == "Pompoensoep")
        #expect(sessie.porties == 6)
        #expect(sessie.receptPorties == 4)
        #expect(sessie.huidigeIndex == 0)
        #expect(sessie.aantalStappen == 2)
    }

    @Test func zonderPortiesZoalsInHetRecept() throws {
        let context = try bibliotheek()
        let soep = try recept("Pompoensoep", in: context)
        soep.porties = 4
        let router = KookRouter()
        router.kook(recept: soep.objectID.uriRepresentation())
        let verzoek = try #require(router.neemKookVerzoekAf())
        let keuze = try #require(KookRouter.keuze(voor: verzoek, in: context))
        #expect(KookSessie(recept: keuze.recept, stand: keuze.stand).porties == 4)
        // Nul of minder personen wordt 1.
        router.kook(recept: soep.objectID.uriRepresentation(), porties: 0)
        #expect(router.kookVerzoek?.porties == 1)
    }

    @Test func kookReceptIntentZonderStappenOfOnbekend() throws {
        let context = try bibliotheek()
        let router = KookRouter()
        let notitie = try #require(try recept("Losse notitie", in: context).uuid?.uuidString)
        #expect(
            KookReceptIntent.start(recept: notitie, porties: nil, in: context, router: router)
                == "Losse notitie heeft nog geen stappen om te koken.")
        #expect(
            KookReceptIntent.start(recept: UUID().uuidString, porties: nil, in: context, router: router)
                == "Dat recept staat niet (meer) in Knipsel.")
        #expect(router.kookVerzoek == nil)
    }

    @Test func toonVerzoekWordtEenKeerAfgenomen() throws {
        let context = try bibliotheek()
        let router = KookRouter()
        let uri = try recept("Prei-quiche", in: context).objectID.uriRepresentation()
        router.toon(recept: uri)
        #expect(router.neemToonVerzoekAf()?.recept == uri)
        #expect(router.neemToonVerzoekAf() == nil)
    }

    // MARK: - Opdrachten op de lopende kookbeurt

    private func lopend(voorlezenAan: Bool = true) -> (ActieveKookSessie, KookSessie, NepSpreker) {
        let sessie = KookSessie(
            titel: "Pompoensoep",
            ingredienten: [
                KookIngredient(id: 0, ruweTekst: "1 kg pompoen", hoeveelheid: 1, eenheid: "kg", naam: "pompoen")
            ],
            stappen: [
                KookStap(id: 0, tekst: "Snijd de pompoen in blokjes."), KookStap(id: 1, tekst: "Kook de pompoen gaar."),
                KookStap(id: 2, tekst: "Pureer de soep."),
            ], receptPorties: 4)
        let spreker = NepSpreker()
        let voorlezer = VoorleesService(
            spreker: spreker, isAan: voorlezenAan, instellingen: { Voorleesinstellingen() }, bewaarTempo: { _ in })
        let houder = ActieveKookSessie()
        houder.registreer(Spraakbediening(sessie: sessie, voorlezer: voorlezer))
        return (houder, sessie, spreker)
    }

    @Test func zonderKookbeurtEenNetteMelding() {
        let houder = ActieveKookSessie()
        for opdracht in KookOpdracht.allCases {
            #expect(
                KookOpdrachtUitvoerder.voerUit(opdracht, in: houder) == "Er is geen recept aan het koken in Knipsel.")
        }
    }

    @Test func volgendeEnVorigeLezenVoor() {
        let (houder, sessie, spreker) = lopend()
        #expect(KookOpdrachtUitvoerder.voerUit(.volgende, in: houder) == "Stap 2 van 3.")
        #expect(sessie.stapNummer == 2)
        // Hetzelfde pad als spraak: de gebeurtenis gaat meteen naar de voorlezer.
        #expect(spreker.uitspraken.last?.hasPrefix("Stap 2. Kook de pompoen gaar.") == true)
        #expect(KookOpdrachtUitvoerder.voerUit(.vorige, in: houder) == "Stap 1 van 3.")
        #expect(sessie.stapNummer == 1)
        #expect(spreker.uitspraken.last?.hasPrefix("Stap 1. Snijd de pompoen in blokjes.") == true)
    }

    @Test func zonderVoorlezenZegtSiriDeHeleStap() {
        let (houder, sessie, spreker) = lopend(voorlezenAan: false)
        #expect(KookOpdrachtUitvoerder.voerUit(.volgende, in: houder) == "Stap 2 van 3: Kook de pompoen gaar.")
        #expect(sessie.stapNummer == 2)
        #expect(spreker.uitspraken.isEmpty)
    }

    @Test func randenEersteEnLaatsteStap() {
        let (houder, sessie, _) = lopend()
        #expect(KookOpdrachtUitvoerder.voerUit(.vorige, in: houder) == "Je bent al bij de eerste stap. Stap 1 van 3.")
        #expect(sessie.stapNummer == 1)
        _ = KookOpdrachtUitvoerder.voerUit(.volgende, in: houder)
        _ = KookOpdrachtUitvoerder.voerUit(.volgende, in: houder)
        #expect(sessie.isLaatsteStap)
        #expect(KookOpdrachtUitvoerder.voerUit(.volgende, in: houder) == "Klaar. Eet smakelijk!")
        #expect(sessie.isAfgerond)
        #expect(KookOpdrachtUitvoerder.voerUit(.volgende, in: houder) == "Het recept is klaar. Eet smakelijk!")
        // Vanuit "Klaar" terug naar de laatste stap.
        #expect(KookOpdrachtUitvoerder.voerUit(.vorige, in: houder) == "Stap 3 van 3.")
        #expect(!sessie.isAfgerond)
    }

    @Test func herhaalLeestDeStapOpnieuw() {
        for aan in [true, false] {
            let (houder, sessie, spreker) = lopend(voorlezenAan: aan)
            #expect(KookOpdrachtUitvoerder.voerUit(.herhaal, in: houder) == "Stap 1 van 3.")
            #expect(sessie.stapNummer == 1)
            #expect(spreker.uitspraken.last?.hasPrefix("Stap 1. Snijd de pompoen") == true)
        }
    }

    @Test func ingredientenVanDezeStapOfAlles() {
        let (houder, sessie, spreker) = lopend()
        #expect(KookOpdrachtUitvoerder.voerUit(.ingredienten, in: houder) == "Wat je nodig hebt voor stap 1.")
        #expect(spreker.uitspraken.last?.hasPrefix("Je hebt nodig:") == true)
        sessie.naarStap(2)
        // Stap 3 noemt geen ingrediënt: dan de hele lijst.
        #expect(KookOpdrachtUitvoerder.voerUit(.ingredienten, in: houder) == "Alle ingrediënten van Pompoensoep.")
        #expect(spreker.uitspraken.last?.hasPrefix("Ingrediënten voor 4 personen.") == true)
    }

    @Test func afmeldenAlleenVoorDezelfdeSessie() {
        let (houder, sessie, spreker) = lopend()
        let ander = KookSessie(
            titel: "Ander", ingredienten: [], stappen: [KookStap(id: 0, tekst: "Iets.")], receptPorties: 0)
        houder.meldAf(ander)
        #expect(houder.sessie === sessie)
        houder.meldAf(sessie)
        #expect(houder.sessie == nil)
        // Na afmelden leest de voorlezer niet meer mee met de sessie.
        let voor = spreker.uitspraken.count
        sessie.volgende()
        #expect(spreker.uitspraken.count == voor)
    }

    // MARK: - AirPods en Watch (proef S3)

    @Test func afstandsknoppen() {
        #expect(AfstandsBediening.actie(voor: .volgende, spreekt: false) == .opdracht(.volgende))
        #expect(AfstandsBediening.actie(voor: .vorige, spreekt: true) == .opdracht(.vorige))
        #expect(AfstandsBediening.actie(voor: .speel, spreekt: false) == .opdracht(.herhaal))
        #expect(AfstandsBediening.actie(voor: .pauze, spreekt: true) == .stopVoorlezen)
        #expect(AfstandsBediening.actie(voor: .speelPauze, spreekt: true) == .stopVoorlezen)
        #expect(AfstandsBediening.actie(voor: .speelPauze, spreekt: false) == .opdracht(.herhaal))
    }

    @Test func afstandsknopOpLopendeKookbeurt() {
        let (houder, sessie, spreker) = lopend()
        #expect(AfstandsBediening.verwerk(.volgende, in: houder))
        #expect(sessie.stapNummer == 2)
        #expect(houder.voorlezer?.status == .spreekt)
        // Steeltje één keer tijdens het voorlezen: stoppen.
        #expect(AfstandsBediening.verwerk(.speelPauze, in: houder))
        #expect(spreker.acties.last == .stop)
        #expect(houder.voorlezer?.status == .stil)
        // Nog een keer: de stap opnieuw.
        #expect(AfstandsBediening.verwerk(.speelPauze, in: houder))
        #expect(spreker.uitspraken.last?.hasPrefix("Stap 2.") == true)
        #expect(AfstandsBediening.verwerk(.vorige, in: houder))
        #expect(sessie.stapNummer == 1)
        #expect(!AfstandsBediening.verwerk(.volgende, in: ActieveKookSessie()))
    }

    @Test func nuSpeeltGegevens() {
        let (_, sessie, _) = lopend()
        let gegevens = NuSpeeltGegevens(sessie: sessie, spreekt: true)
        #expect(gegevens.titel == "Pompoensoep")
        #expect(gegevens.ondertitel == "Stap 1 van 3")
        let info = gegevens.woordenboek
        #expect(info[MPMediaItemPropertyTitle] as? String == "Pompoensoep")
        #expect(info[MPMediaItemPropertyArtist] as? String == "Stap 1 van 3")
        #expect(info[MPMediaItemPropertyAlbumTitle] as? String == "Knipsel")
        #expect(info[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 1)
        sessie.naarStap(2)
        sessie.volgende()
        let klaar = NuSpeeltGegevens(sessie: sessie, spreekt: false)
        #expect(klaar.ondertitel == "Klaar")
        #expect(klaar.woordenboek[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 0)
    }

    @Test func nuSpeeltAfbeeldingEnAudiosessie() throws {
        let symbool = try #require(NuSpeeltBediening.afbeelding(fotoData: nil, symbool: "leaf"))
        #expect(symbool.size == CGSize(width: 600, height: 600))
        #expect(NuSpeeltBediening.afbeelding(fotoData: nil, symbool: "bestaat.niet") != nil)
        #expect(NuSpeeltBediening.spraakOpties(proefAan: false) == [.duckOthers])
        #expect(NuSpeeltBediening.spraakOpties(proefAan: true).isEmpty)
    }
}
