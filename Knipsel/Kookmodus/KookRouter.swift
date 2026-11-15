import CoreData
import Observation
import SwiftUI

/// Eén plek die de kookmodus opent (fase 6): "Kook dit" in het recept, *Verder met…* en Siri
/// (`KookReceptIntent`) zetten hier een verzoek neer; de bibliotheek (`VerderMet`) neemt het af en
/// toont de kookmodus als volledig scherm. Ook "open dit recept" (Spotlight) loopt hierlangs.
@MainActor
@Observable
final class KookRouter {
    static let gedeeld = KookRouter()

    struct Verzoek: Identifiable, Equatable, Sendable {
        let id = UUID()
        /// `Recept.verwijzing` (op de uuid; oude objectID-URI's werken ook).
        let recept: URL
        /// Voor hoeveel personen; `nil` = zoals in het recept.
        var porties: Int?
    }

    /// Kookmodus openen voor dit recept (stap 1).
    private(set) var kookVerzoek: Verzoek?
    /// Het recept tonen in de bibliotheek.
    private(set) var toonVerzoek: Verzoek?

    func kook(recept: URL, porties: Int? = nil) {
        kookVerzoek = Verzoek(recept: recept, porties: porties.map { max(1, $0) })
    }

    func toon(recept: URL) {
        toonVerzoek = Verzoek(recept: recept)
    }

    /// Haalt het openstaande kookverzoek weg en geeft het terug (één venster pakt het op).
    func neemKookVerzoekAf() -> Verzoek? {
        defer { kookVerzoek = nil }
        return kookVerzoek
    }

    func neemToonVerzoekAf() -> Verzoek? {
        defer { toonVerzoek = nil }
        return toonVerzoek
    }

    /// Wat de kookmodus opent voor `verzoek`: het recept, vanaf stap 1, met de gevraagde porties.
    /// `nil` als het recept niet (meer) bestaat of geen stappen heeft.
    static func keuze(voor verzoek: Verzoek, in context: NSManagedObjectContext, nu: Date = .now) -> VerderKeuze? {
        guard let recept = VerderKeuze.recept(bij: verzoek.recept, in: context) else { return nil }
        let aantal = recept.gesorteerdeStappen.count
        guard aantal > 0 else { return nil }
        return VerderKeuze(
            recept: recept,
            stand: KookVoortgang.Stand(
                recept: verzoek.recept, stapIndex: 0, aantalStappen: aantal, porties: verzoek.porties ?? 0, datum: nu))
    }
}

extension View {
    /// Opent het recept uit `KookRouter.toonVerzoek` in de navigatiestapel van de bibliotheek.
    func toonReceptVerzoek(pad: Binding<[NSManagedObjectID]>) -> some View {
        modifier(ToonReceptVerzoek(pad: pad))
    }
}

private struct ToonReceptVerzoek: ViewModifier {
    @Environment(\.managedObjectContext) private var context
    @Binding var pad: [NSManagedObjectID]

    func body(content: Content) -> some View {
        content.onChange(of: KookRouter.gedeeld.toonVerzoek?.id, initial: true) {
            guard let verzoek = KookRouter.gedeeld.neemToonVerzoekAf(),
                let recept = VerderKeuze.recept(bij: verzoek.recept, in: context)
            else { return }
            pad = [recept.objectID]
        }
    }
}

// MARK: - De lopende kookbeurt

/// De kookbeurt die nu open staat, voor wie van buiten de kookmodus bedient: Siri en Opdrachten
/// (`VolgendeStapIntent` …) en AirPods/Watch (`NuSpeeltBediening`). Die draaien in hetzelfde proces,
/// ook als de app op de achtergrond staat, en vinden de sessie hier.
@MainActor
final class ActieveKookSessie {
    static let gedeeld = ActieveKookSessie()

    /// Dezelfde bediening als spraak: commando's lopen via `Spraakbediening.voerUit`.
    private(set) var bediening: Spraakbediening?

    var sessie: KookSessie? { bediening?.sessie }
    var voorlezer: VoorleesService? { bediening?.voorlezer }

    /// De kookmodus is open: elke gebeurtenis gaat meteen naar de voorlezer (ook op de achtergrond),
    /// daarna `naGebeurtenis` (bijv. Nu speelt bijwerken).
    func registreer(_ bediening: Spraakbediening, naGebeurtenis: @escaping () -> Void = {}) {
        let voorlezer = bediening.voorlezer
        bediening.sessie.opGebeurtenis = { [weak sessie = bediening.sessie] gebeurtenis in
            guard let sessie else { return }
            voorlezer.reageer(op: gebeurtenis, in: sessie)
            naGebeurtenis()
        }
        self.bediening = bediening
    }

    /// De kookmodus gaat dicht. Een andere (nieuwere) sessie blijft staan.
    func meldAf(_ sessie: KookSessie) {
        sessie.opGebeurtenis = nil
        if bediening?.sessie === sessie { bediening = nil }
    }
}

/// Wat Siri, Opdrachten en AirPods in de kookmodus kunnen.
enum KookOpdracht: String, Sendable, CaseIterable {
    case volgende
    case vorige
    case herhaal
    case ingredienten
}

/// Voert een `KookOpdracht` uit op de lopende kookbeurt, langs hetzelfde pad als spraak
/// (`Spraakbediening.voerUit` → `KookSessie`-gebeurtenis → voorlezer), en geeft de korte zin terug
/// die Siri toont en zegt. Leest Knipsel zelf voor, dan blijft die zin kort ("Stap 3 van 7."), zodat
/// Siri en Knipsel niet hetzelfde over elkaar heen zeggen.
@MainActor
enum KookOpdrachtUitvoerder {
    static let geenSessie = "Er is geen recept aan het koken in Knipsel."
    static let alKlaar = "Het recept is klaar. Eet smakelijk!"

    static func voerUit(_ opdracht: KookOpdracht, in houder: ActieveKookSessie = .gedeeld) -> String {
        guard let bediening = houder.bediening else { return geenSessie }
        let sessie = bediening.sessie
        let leestVoor = bediening.voorlezer.isAan
        switch opdracht {
        case .volgende:
            if sessie.isAfgerond { return alKlaar }
            bediening.voerUit(.volgende)
            return sessie.isAfgerond ? Voorleestekst.afgerond : stap(sessie, kort: leestVoor)
        case .vorige:
            if sessie.isEersteStap, !sessie.isAfgerond {
                return "Je bent al bij de eerste stap. " + stap(sessie, kort: leestVoor)
            }
            bediening.voerUit(.vorige)
            return stap(sessie, kort: leestVoor)
        case .herhaal:
            // Herhalen leest altijd voor, ook met de luidspreker uit (zoals "herhaal" via spraak).
            bediening.voerUit(.herhaal)
            return sessie.isAfgerond ? Voorleestekst.afgerond : stap(sessie, kort: true)
        case .ingredienten:
            bediening.voerUit(.ingredienten)
            if sessie.isAfgerond || sessie.ingredientenInHuidigeStap.isEmpty {
                return "Alle ingrediënten van \(sessie.titel)."
            }
            return "Wat je nodig hebt voor stap \(sessie.stapNummer)."
        }
    }

    /// "Stap 3 van 7." of, als Knipsel niet voorleest, met de tekst erbij.
    static func stap(_ sessie: KookSessie, kort: Bool) -> String {
        guard let huidige = sessie.huidigeStap else { return geenSessie }
        let kop = "Stap \(sessie.stapNummer) van \(sessie.aantalStappen)"
        return kort ? kop + "." : kop + ": " + huidige.tekst
    }
}
