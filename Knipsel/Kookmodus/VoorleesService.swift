import Foundation
import Observation

/// Instellingen voor het voorlezen, bij elke uitspraak opnieuw gelezen zodat een wijziging in
/// Instellingen meteen geldt.
struct Voorleesinstellingen: Equatable, Sendable {
    /// `nil` = automatisch de beste Nederlandse stem.
    var stem: String?
    var tempo = Voorleestempo.standaard
    var ingredientenMeelezen = false

    static func huidig(_ standaarden: UserDefaults = .standard) -> Voorleesinstellingen {
        Voorleesinstellingen(
            stem: standaarden.string(forKey: AppConfiguratie.sleutelVoorleesStem).flatMap { $0.isEmpty ? nil : $0 },
            tempo: standaarden.object(forKey: AppConfiguratie.sleutelVoorleesTempo) as? Double
                ?? Voorleestempo.standaard,
            ingredientenMeelezen: standaarden.bool(forKey: AppConfiguratie.sleutelIngredientenMeelezen))
    }

    /// "Voorlezen standaard aan"; aan als het nog nooit is ingesteld.
    static func standaardAan(_ standaarden: UserDefaults = .standard) -> Bool {
        standaarden.object(forKey: AppConfiguratie.sleutelVoorlezenAan) as? Bool ?? true
    }
}

/// Wat er voorgelezen wordt, als uitspreekbare tekst (via `Uitspraakregels`). Puur.
enum Voorleestekst {
    /// "Stap 2. Verhit de olie … Je hebt nodig: twee eetlepels olijfolie, 3 centimeter verse gember."
    /// Elke zin en elke ingrediëntregel apart door de uitspraakregels: een afkortingspunt aan het eind
    /// ("1 kg.") is dan herkenbaar als slot van de regel.
    static func stap(nummer: Int, tekst: String, ingredienten: [String] = []) -> String {
        var zinnen = ["Stap \(nummer).", spreekbaar(zin(tekst))]
        if !ingredienten.isEmpty {
            zinnen.append("Je hebt nodig: " + ingredienten.map { spreekbaar(regel($0)) }.joined(separator: ", ") + ".")
        }
        return zinnen.joined(separator: " ")
    }

    /// De hele lijst, met groepen ("Voor de saus") als tussenkop.
    static func ingredienten(_ regels: [(groep: String?, tekst: String)], porties: Int?) -> String {
        var zinnen = [
            porties.map { "Ingrediënten voor \($0 == 1 ? "1 persoon" : "\($0) personen")." } ?? "Ingrediënten."
        ]
        var vorigeGroep: String?
        for (groep, tekst) in regels {
            if let groep, !groep.isEmpty, groep != vorigeGroep { zinnen.append(zin(groep)) }
            vorigeGroep = groep
            zinnen.append(zin(spreekbaar(regel(tekst))))
        }
        return zinnen.joined(separator: " ")
    }

    private static func spreekbaar(_ tekst: String) -> String { Uitspraakregels.uitspreekbaar(tekst) }

    static let afgerond = "Klaar. Eet smakelijk!"

    /// Een ingrediëntregel zonder slotteken, zodat hij in een opsomming past.
    private static func regel(_ tekst: String) -> String {
        tekst.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".;:")))
    }

    /// Met een punt erachter, zodat de stem even pauzeert.
    private static func zin(_ tekst: String) -> String {
        let schoon = tekst.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let laatste = schoon.last else { return schoon }
        return ".!?:".contains(laatste) ? schoon : schoon + "."
    }
}

extension Voorleestekst {
    /// De huidige stap van een kookbeurt, met (geschaalde) ingrediënten als dat aan staat.
    @MainActor
    static func huidigeStap(van sessie: KookSessie, metIngredienten: Bool) -> String? {
        if sessie.isAfgerond { return afgerond }
        guard let stap = sessie.huidigeStap else { return nil }
        // Alleen maat en naam: een toelichting ("gesnipperd") maakt de opsomming onduidelijk.
        let nodig: [String] =
            metIngredienten ? sessie.ingredientenInHuidigeStap.map { kortTekst(van: $0, in: sessie) } : []
        return Voorleestekst.stap(nummer: sessie.stapNummer, tekst: stap.tekst, ingredienten: nodig)
    }

    /// "2 el olijfolie", geschaald; een regel zonder hoeveelheid zoals hij er staat.
    @MainActor
    private static func kortTekst(van ingredient: KookIngredient, in sessie: KookSessie) -> String {
        guard let maat = sessie.maat(van: ingredient), let naam = ingredient.naam else { return ingredient.ruweTekst }
        return "\(maat) \(naam)"
    }

    @MainActor
    static func alleIngredienten(van sessie: KookSessie) -> String {
        ingredienten(
            sessie.ingredienten.map { ($0.groep, sessie.tekst(van: $0)) },
            porties: sessie.receptPorties > 0 ? sessie.porties : nil)
    }
}

/// Voorlezen in de kookmodus (K9): bij elke stapwissel de nieuwe stap, en daarna wachten. Nooit
/// automatisch doorgaan; "verder" komt altijd van de kok (tik, veeg, toets, later spraak en Siri).
@MainActor
@Observable
final class VoorleesService {
    enum Status: Equatable, Sendable {
        case stil
        case spreekt
        case gepauzeerd
    }

    private(set) var status: Status = .stil
    /// De luidspreker in de kookmodus. Uit = niets voorlezen.
    private(set) var isAan: Bool

    @ObservationIgnored private let spreker: any Spreker
    @ObservationIgnored private let instellingen: () -> Voorleesinstellingen
    @ObservationIgnored private var onderbrekingswacht: Onderbrekingswacht?

    init(
        spreker: any Spreker = SysteemSpreker(), isAan: Bool = Voorleesinstellingen.standaardAan(),
        instellingen: @escaping () -> Voorleesinstellingen = { .huidig() }
    ) {
        self.spreker = spreker
        self.isAan = isAan
        self.instellingen = instellingen
        spreker.klaar = { [weak self] in self?.status = .stil }
        onderbrekingswacht = Onderbrekingswacht { [weak self] in self?.onderbroken() }
    }

    var spreekt: Bool { status != .stil }

    // MARK: - Kookmodus

    /// Reageert op wat er in de kookbeurt gebeurde: een nieuwe stap (of herhaal) wordt voorgelezen,
    /// de vorige uitspraak stopt eerst. Een grens (geen stap meer) zegt niets.
    func reageer(op gebeurtenis: KookSessie.Gebeurtenis?, in sessie: KookSessie) {
        guard isAan, let gebeurtenis else { return }
        switch gebeurtenis {
        case .volgende, .vorige, .naarStap, .herhaal, .afgerond:
            leesHuidigeStap(van: sessie)
        case .grens:
            break
        }
    }

    /// Leest de huidige stap; daarna wacht de service. Werkt ook als voorlezen uit staat (knop).
    func leesHuidigeStap(van sessie: KookSessie) {
        let instellingen = instellingen()
        guard let tekst = Voorleestekst.huidigeStap(van: sessie, metIngredienten: instellingen.ingredientenMeelezen)
        else { return }
        spreek(tekst, met: instellingen)
        // TODO(fase 7): heeft de stap een tijd (`huidigeStap.timerSeconden > 0`), vraag dan na het
        // voorlezen "Zal ik een timer van 20 minuten zetten?" (K11). Nu nog niet uitspreken.
    }

    func leesIngredienten(van sessie: KookSessie) {
        spreek(Voorleestekst.alleIngredienten(van: sessie), met: instellingen())
    }

    /// Luidspreker aan of uit. Aan leest meteen de huidige stap; uit stopt direct.
    func zetAan(_ aan: Bool, sessie: KookSessie? = nil) {
        isAan = aan
        if aan {
            if let sessie { leesHuidigeStap(van: sessie) }
        } else {
            stop()
        }
    }

    // MARK: - Bediening

    /// Spreekt `tekst` uit; wat er nog liep, stopt eerst.
    func spreek(_ tekst: String, met instellingen: Voorleesinstellingen? = nil) {
        let instellingen = instellingen ?? self.instellingen()
        if spreekt { spreker.stop() }
        spreker.spreek(tekst, stem: instellingen.stem, tempo: instellingen.tempo)
        status = .spreekt
    }

    /// Stopt direct, ook midden in een zin.
    func stop() {
        guard spreekt else { return }
        spreker.stop()
        status = .stil
    }

    func pauzeer() {
        guard status == .spreekt else { return }
        spreker.pauzeer()
        status = .gepauzeerd
    }

    func hervat() {
        guard status == .gepauzeerd else { return }
        spreker.hervat()
        status = .spreekt
    }

    /// Telefoontje of Siri: stoppen, en daarna niet vanzelf verder praten.
    func onderbroken() {
        stop()
    }
}
