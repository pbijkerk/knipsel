import CloudKit
import CoreData
import EventKit
import Foundation
import Testing
import UniformTypeIdentifiers

@testable import Knipsel

/// Audit v0.1, #6: fouten in beeld altijd in het Nederlands, met de actie als context.
@MainActor
struct FoutmeldingTests {
    private enum EigenFout: LocalizedError {
        case naam
        case knipsel
        var errorDescription: String? {
            switch self {
            case .naam: "Er bestaat al een \u{201C}Soepen\u{201D}."
            case .knipsel: "Knipsel heeft geen toegang tot Herinneringen."
            }
        }
    }

    @Test func eigenFoutBlijftEenZinVanKnipsel() {
        #expect(Foutmelding.tekst(EigenFout.naam) == "Er bestaat al een \u{201C}Soepen\u{201D}.")
        #expect(
            Foutmelding.tekst(EigenFout.naam, actie: "Bewaren")
                == "Bewaren lukte niet: er bestaat al een \u{201C}Soepen\u{201D}.")
        // Een eigennaam houdt zijn hoofdletter na de dubbelepunt.
        #expect(
            Foutmelding.tekst(EigenFout.knipsel, actie: "Op de lijst zetten")
                == "Op de lijst zetten lukte niet: Knipsel heeft geen toegang tot Herinneringen.")
        #expect(
            Foutmelding.tekst(Bibliotheekbeheer.Fout.legeNaam, actie: "Toevoegen")
                == "Toevoegen lukte niet: geef een naam op.")
        #expect(Foutmelding.tekst(OphaalFout.status(404)) == "De site gaf foutcode 404.")
    }

    @Test func coreDataValidatie() throws {
        let context = legeOpslag().context
        let item = NSEntityDescription.insertNewObject(forEntityName: "BoodschappenItem", into: context)
        item.setValue(nil, forKey: "kookboek")
        var opgevangen: (any Error)?
        do { try item.validateForInsert() } catch { opgevangen = error }
        let fout = try #require(opgevangen)
        context.delete(item)
        #expect(
            Foutmelding.tekst(fout, actie: "Toevoegen")
                == "Toevoegen lukte niet: bij een boodschap ontbreekt 'kookboek'.")
        #expect(!Foutmelding.tekst(fout).contains("%{PROPERTY}"))
        #expect(Foutmelding.tekst(fout).hasPrefix("Bij een boodschap"))
    }

    @Test func coreDataOverig() {
        #expect(
            Foutmelding.tekst(NSError(domain: NSCocoaErrorDomain, code: NSManagedObjectMergeError), actie: "Bewaren")
                == "Bewaren lukte niet: het is net op een ander toestel gewijzigd. Probeer het nog eens.")
        #expect(
            Foutmelding.tekst(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError))
                == "Er is te weinig ruimte op dit toestel.")
        #expect(
            Foutmelding.tekst(NSError(domain: NSCocoaErrorDomain, code: NSPersistentStoreSaveError))
                .contains("opslag van Knipsel is op dit moment niet beschikbaar (code NSCocoaErrorDomain 134030)"))
    }

    @Test func cloudKit() {
        #expect(
            Foutmelding.tekst(CKError(.quotaExceeded), actie: "Uitnodigen")
                == "Uitnodigen lukte niet: je iCloud-opslag is vol.")
        #expect(Foutmelding.tekst(CKError(.notAuthenticated)) == "Je bent niet ingelogd bij iCloud.")
        // "iCloud" houdt zijn kleine letter, ook vooraan.
        #expect(Foutmelding.tekst(CKError(.internalError)) == "iCloud gaf een fout (CloudKit-fout 1).")
        // Ook als de CloudKit-fout onder een andere fout zit.
        let ingepakt = NSError(
            domain: NSCocoaErrorDomain, code: 134_400,
            userInfo: [NSUnderlyingErrorKey: CKError(.networkFailure) as NSError])
        #expect(Foutmelding.uitleg(ingepakt).hasPrefix("geen verbinding met iCloud"))
    }

    @Test func herinneringen() {
        let fout = NSError(domain: EKErrorDomain, code: EKError.Code.calendarReadOnly.rawValue)
        #expect(
            Foutmelding.tekst(fout, actie: "Naar Herinneringen")
                == "Naar Herinneringen lukte niet: deze lijst in Herinneringen kan niet worden gewijzigd.")
        let onbekend = NSError(domain: EKErrorDomain, code: EKError.Code.invalidSpan.rawValue)
        #expect(Foutmelding.tekst(onbekend).hasPrefix("Herinneringen gaf een fout (code EKErrorDomain"))
    }

    @Test func netwerk() {
        #expect(
            Foutmelding.tekst(URLError(.notConnectedToInternet), actie: "Ophalen")
                == "Ophalen lukte niet: er is geen internetverbinding.")
        #expect(Foutmelding.tekst(URLError(.timedOut)).hasPrefix("De verbinding duurde te lang."))
        #expect(Foutmelding.tekst(URLError(.cannotFindHost)) == "De website is niet bereikbaar.")
        #expect(Foutmelding.tekst(URLError(.badServerResponse)).contains("code NSURLErrorDomain -1011"))
    }

    @Test func sleutelhanger() {
        let fout = NSError(domain: NSOSStatusErrorDomain, code: Int(errSecInteractionNotAllowed))
        #expect(Foutmelding.tekst(fout).hasPrefix("De sleutelhanger is op slot."))
        let onbekend = NSError(domain: NSOSStatusErrorDomain, code: -99_999)
        #expect(Foutmelding.tekst(onbekend) == "Er ging iets onverwachts mis (code NSOSStatusErrorDomain -99999).")
    }

    @Test func terugvalZonderEngelseTekst() {
        let fout = NSError(
            domain: "com.apple.vreemd", code: 42,
            userInfo: [NSLocalizedDescriptionKey: "The operation couldn't be completed."])
        let tekst = Foutmelding.tekst(fout, actie: "Plannen")
        #expect(tekst == "Plannen lukte niet: er ging iets onverwachts mis (code com.apple.vreemd 42).")
        #expect(!tekst.contains("operation"))
        #expect(Foutmelding.code(fout) == "com.apple.vreemd 42")
        // Ook de Thuis-meldingen vallen niet meer terug op de systeemtekst.
        #expect(DeelFout.uitleg(fout) == "er ging iets onverwachts mis (code com.apple.vreemd 42).")
    }
}

/// Audit v0.1, #5: de deel-extensie zegt wat er misging als een kopie niet lukt.
@MainActor
struct DeelUitkomstTests {
    @Test func keuzeVanDeUitkomst() {
        let post = DeelPost(bron: .link(URL(string: "https://example.com/soep")!))
        #expect(DeelUitkomst.bepaal(post: post, soorten: [.link], schrijvenMislukt: false) == .toegevoegd(post))
        #expect(DeelUitkomst.bepaal(post: post, soorten: [.link], schrijvenMislukt: true) == .nietBewaard)
        #expect(DeelUitkomst.bepaal(post: nil, soorten: [nil], schrijvenMislukt: false) == .niets)
        #expect(DeelUitkomst.bepaal(post: nil, soorten: [], schrijvenMislukt: false) == .niets)
        #expect(
            DeelUitkomst.bepaal(post: nil, soorten: [.afbeelding], schrijvenMislukt: false)
                == .nietOvergenomen(.afbeelding, aantal: 1))
        #expect(
            DeelUitkomst.bepaal(post: nil, soorten: Array(repeating: .afbeelding, count: 8), schrijvenMislukt: false)
                == .nietOvergenomen(.afbeelding, aantal: DeelKeuze.maxAfbeeldingen))
        #expect(
            DeelUitkomst.bepaal(post: nil, soorten: [.pdf, nil], schrijvenMislukt: false)
                == .nietOvergenomen(.pdf, aantal: 1))
    }

    @Test func meldingPerUitkomst() {
        #expect(
            DeelBevestiging.toestand(na: .nietOvergenomen(.afbeelding, aantal: 1))
                == .mislukt(
                    "De afbeelding kon niet worden overgenomen. Probeer het nog eens, of bewaar haar eerst in Foto's."))
        guard case .mislukt(let meer) = DeelBevestiging.toestand(na: .nietOvergenomen(.afbeelding, aantal: 3)) else {
            Issue.record("geen melding")
            return
        }
        #expect(meer.hasPrefix("De afbeeldingen konden niet worden overgenomen."))
        guard case .mislukt(let pdf) = DeelBevestiging.toestand(na: .nietOvergenomen(.pdf, aantal: 1)) else {
            Issue.record("geen melding")
            return
        }
        #expect(pdf.hasPrefix("De PDF kon niet worden overgenomen."))
        guard case .mislukt(let bewaren) = DeelBevestiging.toestand(na: .nietBewaard) else {
            Issue.record("geen melding")
            return
        }
        #expect(bewaren.hasPrefix("Knipsel kon het gedeelde item niet bewaren."))
        #expect(DeelBevestiging.toestand(na: .niets) == .niets)
        let post = DeelPost(bron: .pdf("a.pdf"))
        #expect(DeelBevestiging.toestand(na: .toegevoegd(post)) == .toegevoegd("De PDF"))
    }

    @Test func afbeeldingDieNietLaadtGeeftMeldingInPlaatsVanNiets() async {
        // Een provider die zegt een afbeelding te hebben, maar niets levert.
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { klaar in
            klaar(nil, NSError(domain: NSCocoaErrorDomain, code: NSFileReadUnknownError))
            return nil
        }
        let map = FileManager.default.temporaryDirectory.appending(path: "DeelUitkomst-\(UUID().uuidString)")
        let uitkomst = await DeelLezer(bus: DeelBus(map: map)).verwerk([provider])
        #expect(uitkomst == .nietOvergenomen(.afbeelding, aantal: 1))
        #expect(DeelBevestiging.toestand(na: uitkomst) != .niets)
    }
}
