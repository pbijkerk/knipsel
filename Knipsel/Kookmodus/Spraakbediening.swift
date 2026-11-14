import Foundation
import Observation

/// Instellingen › Spraakbediening, bij elke start van het luisteren opnieuw gelezen.
enum Spraakinstellingen {
    /// Luisteren in de kookmodus; aan als het nog nooit is ingesteld.
    static func aan(_ standaarden: UserDefaults = .standard) -> Bool {
        standaarden.object(forKey: AppConfiguratie.sleutelSpraakAan) as? Bool ?? true
    }

    static func herkenner(_ standaarden: UserDefaults = .standard) -> CommandoHerkenner.Instellingen {
        CommandoHerkenner.Instellingen(
            impliciet: standaarden.object(forKey: AppConfiguratie.sleutelSpraakImpliciet) as? Bool ?? true,
            alleenMetWekwoord: standaarden.bool(forKey: AppConfiguratie.sleutelSpraakWekwoord))
    }
}

/// Koppelt gesproken commando's aan de kookbeurt en het voorlezen (K8). Krijgt de (deel)resultaten van
/// `LuisterService`, laat `Uitingbeslisser` kiezen wat er uitgevoerd wordt en voert dat uit. Het
/// voorlezen van een nieuwe stap gebeurt, net als na een tik, in de kookmodus op `sessie.gebeurtenis`.
@MainActor
@Observable
final class Spraakbediening {
    /// Korte bevestiging onderin ("✓ volgende"), 1,5 s in beeld.
    struct Melding: Equatable {
        let tekst: String
        let nummer: Int
    }

    /// Antwoord op "hoeveel …?" als kaartje in beeld.
    struct Antwoord: Equatable {
        /// "Groentebouillon" of wat er gevraagd werd.
        let titel: String
        /// "1½ l groentebouillon", of "Dat staat niet in dit recept".
        let tekst: String
        let gevonden: Bool
        let nummer: Int
    }

    private(set) var melding: Melding?
    private(set) var antwoord: Antwoord?
    private(set) var laatsteCommando: Commando?

    @ObservationIgnored let sessie: KookSessie
    @ObservationIgnored let voorlezer: VoorleesService
    @ObservationIgnored private var beslisser: Uitingbeslisser
    /// "Stoppen met koken": de kookmodus sluiten.
    @ObservationIgnored var sluit: () -> Void = {}
    /// Zacht tikgeluid bij elk begrepen commando.
    @ObservationIgnored var tik: () -> Void = {}
    @ObservationIgnored private var teller = 0

    static let tempoStap = 0.1

    init(
        sessie: KookSessie, voorlezer: VoorleesService,
        instellingen: CommandoHerkenner.Instellingen = Spraakinstellingen.herkenner()
    ) {
        self.sessie = sessie
        self.voorlezer = voorlezer
        beslisser = Uitingbeslisser(
            herkenner: CommandoHerkenner(
                ingredientnamen: sessie.ingredienten.map(\.koppelnaam), instellingen: instellingen))
    }

    var instellingen: CommandoHerkenner.Instellingen {
        get { beslisser.herkenner.instellingen }
        set { beslisser.herkenner.instellingen = newValue }
    }

    /// Woorden die de herkenner extra kans geeft: commando's en de ingrediënten van dit recept.
    var contextwoorden: [String] {
        let namen = sessie.ingredienten.compactMap(\.naam).filter { !$0.isEmpty }
        return Self.commandowoorden + namen.map { "hoeveel \($0)" } + namen
    }

    static let commandowoorden = [
        "volgende", "vorige", "terug", "herhaal", "nog een keer", "stop", "stil", "pauze", "lees voor", "ga door",
        "langzamer", "sneller", "ingrediënten", "wat heb ik nodig", "hoeveel", "stap", "stoppen met koken", "oké",
        "klaar", "gedaan", "Knipsel",
    ]

    // MARK: - Resultaten van de herkenner

    /// Een (deel)resultaat. `nu` in seconden (monotone klok).
    func verwerk(_ tekst: String, segment: Int, definitief: Bool, nu: TimeInterval) {
        if let commando = beslisser.verwerk(
            tekst, segment: segment, definitief: definitief, nu: nu, voorgelezen: voorlezer.voorgelezenTekst())
        {
            voerUit(commando)
        }
    }

    /// Periodiek: een voorlopig resultaat dat stabiel bleef.
    func controleer(nu: TimeInterval) {
        if let commando = beslisser.controleer(nu: nu) { voerUit(commando) }
    }

    // MARK: - Uitvoeren

    func voerUit(_ commando: Commando) {
        laatsteCommando = commando
        switch commando {
        case .volgende:
            sessie.volgende()
            meld("✓ volgende")
        case .impliciet(let woord):
            sessie.volgende()
            meld("✓ Volgende (\(woord))")
        case .vorige:
            sessie.vorige()
            meld("✓ vorige")
        case .herhaal:
            if voorlezer.isAan {
                sessie.herhaal()
            } else {
                voorlezer.leesHuidigeStap(van: sessie)
            }
            meld("✓ herhaal")
        case .stop:
            voorlezer.stop()
            meld("✓ stop")
        case .hervat:
            if voorlezer.status == .gepauzeerd {
                voorlezer.hervat()
            } else {
                voorlezer.leesHuidigeStap(van: sessie)
            }
            meld("✓ lees voor")
        case .langzamer, .sneller:
            pasTempoAan(commando == .langzamer ? -Self.tempoStap : Self.tempoStap)
        case .ingredienten:
            voorlezer.leesIngredientenVanStap(van: sessie)
            meld("✓ ingrediënten")
        case .hoeveel(let index, let gevraagd):
            beantwoordHoeveel(index, gevraagd: gevraagd)
        case .naarStap(let nummer):
            if sessie.naarStap(nummer - 1) {
                meld("✓ stap \(nummer)")
            } else {
                meld("Stap \(nummer) bestaat niet")
            }
        case .stoppenMetKoken:
            voorlezer.stop()
            meld("✓ stoppen met koken")
            sluit()
        }
        if !isHoeveel(commando) { antwoord = nil }
    }

    private func isHoeveel(_ commando: Commando) -> Bool {
        if case .hoeveel = commando { return true }
        return false
    }

    private func pasTempoAan(_ stap: Double) {
        let wasAanHetSpreken = voorlezer.status == .spreekt
        let nieuw = voorlezer.pasTempoAan(met: stap)
        let label = Voorleestempo.label(nieuw)
        let grens = stap < 0 ? nieuw <= Voorleestempo.minimum : nieuw >= Voorleestempo.maximum
        let woord = stap < 0 ? "langzamer" : "sneller"
        meld(grens ? "✓ \(woord) · \(label) (grens)" : "✓ \(woord) · \(label)")
        // Opnieuw beginnen in het nieuwe tempo; het tempo geldt per uitspraak.
        if wasAanHetSpreken { voorlezer.leesHuidigeStap(van: sessie) }
    }

    private func beantwoordHoeveel(_ index: Int?, gevraagd: String) {
        teller += 1
        if let index, sessie.ingredienten.indices.contains(index) {
            let ingredient = sessie.ingredienten[index]
            let titel = (ingredient.naam ?? gevraagd).capitalizedEerste
            antwoord = Antwoord(titel: titel, tekst: sessie.tekst(van: ingredient), gevonden: true, nummer: teller)
            voorlezer.spreek(Voorleestekst.hoeveelheid(van: ingredient, in: sessie))
            meld("✓ hoeveel \(ingredient.naam ?? gevraagd)?")
        } else {
            antwoord = Antwoord(
                titel: gevraagd.capitalizedEerste, tekst: Voorleestekst.nietInRecept, gevonden: false, nummer: teller)
            voorlezer.spreek(Voorleestekst.nietInRecept)
            meld("✓ hoeveel \(gevraagd)?")
        }
    }

    func sluitAntwoord() {
        antwoord = nil
    }

    private func meld(_ tekst: String) {
        teller += 1
        melding = Melding(tekst: tekst, nummer: teller)
        tik()
    }
}

extension String {
    /// "groentebouillon" → "Groentebouillon".
    fileprivate var capitalizedEerste: String {
        prefix(1).uppercased() + dropFirst()
    }
}
