import Foundation

/// Waar je bent gebleven in een afgebroken kookmodus, per recept (U8). Lokaal in `UserDefaults`
/// (hoeft niet te syncen); de sleutel is de `URIRepresentation` van het recept-objectID.
struct KookVoortgang {
    /// Eén afgebroken kookbeurt.
    struct Stand: Codable, Equatable, Sendable {
        let recept: URL
        /// Index van de stap waar je stopte (0 = stap 1).
        let stapIndex: Int
        let aantalStappen: Int
        let porties: Int
        let datum: Date

        /// 1-gebaseerd, zoals de kok het noemt.
        var stapNummer: Int { stapIndex + 1 }
    }

    /// Ouder dan dit telt een afgebroken kookbeurt niet meer.
    static let geldigheid: TimeInterval = 7 * 24 * 60 * 60
    /// Pas vanaf stap 2 (index 1) is er iets om naar terug te keren.
    static let minimaleIndex = 1

    private let defaults: UserDefaults
    private let sleutel: String

    init(defaults: UserDefaults = .standard, sleutel: String = AppConfiguratie.sleutelKookVoortgang) {
        self.defaults = defaults
        self.sleutel = sleutel
    }

    // MARK: - Lezen

    /// Alle bewaarde standen, ook verlopen; per recept één.
    var alle: [Stand] {
        guard let data = defaults.data(forKey: sleutel),
            let standen = try? JSONDecoder().decode([Stand].self, from: data)
        else { return [] }
        return standen
    }

    func stand(voor recept: URL) -> Stand? {
        alle.first { $0.recept == recept }
    }

    /// De meest recente geldige stand: niet ouder dan 7 dagen en van een recept dat nog bestaat.
    func meestRecente(nu: Date = .now, bestaat: (URL) -> Bool = { _ in true }) -> Stand? {
        alle
            .filter { Self.isGeldig($0, nu: nu) && bestaat($0.recept) }
            .max { $0.datum < $1.datum }
    }

    static func isGeldig(_ stand: Stand, nu: Date) -> Bool {
        nu.timeIntervalSince(stand.datum) <= geldigheid && stand.stapIndex >= 0
            && stand.stapIndex < stand.aantalStappen
    }

    // MARK: - Schrijven

    func bewaar(_ stand: Stand) {
        schrijf(alle.filter { $0.recept != stand.recept } + [stand])
    }

    func wis(recept: URL) {
        let standen = alle
        let over = standen.filter { $0.recept != recept }
        if over.count != standen.count { schrijf(over) }
    }

    /// Haalt verlopen standen weg (en, met `bestaat`, die van verwijderde recepten).
    func ruimOp(nu: Date = .now, bestaat: (URL) -> Bool = { _ in true }) {
        let standen = alle
        let over = standen.filter { Self.isGeldig($0, nu: nu) && bestaat($0.recept) }
        if over.count != standen.count { schrijf(over) }
    }

    /// Na het sluiten van de kookmodus: na "Gekookt" wissen; vanaf stap 2 de stap bewaren. Sluit je
    /// op stap 1, dan blijft een eerdere stand van dit recept staan.
    func naSluiten(
        recept: URL, stapIndex: Int, aantalStappen: Int, porties: Int, gekookt: Bool, nu: Date = .now
    ) {
        if gekookt {
            wis(recept: recept)
        } else if stapIndex >= Self.minimaleIndex, stapIndex < aantalStappen {
            bewaar(
                Stand(recept: recept, stapIndex: stapIndex, aantalStappen: aantalStappen, porties: porties, datum: nu))
        }
    }

    private func schrijf(_ standen: [Stand]) {
        if standen.isEmpty {
            defaults.removeObject(forKey: sleutel)
        } else if let data = try? JSONEncoder().encode(standen) {
            defaults.set(data, forKey: sleutel)
        }
    }
}

extension KookVoortgang {
    /// Na het sluiten van de kookmodus voor `sessie`.
    @MainActor
    func naSluiten(_ sessie: KookSessie, recept: URL, nu: Date = .now) {
        naSluiten(
            recept: recept, stapIndex: sessie.huidigeIndex, aantalStappen: sessie.aantalStappen,
            porties: sessie.porties, gekookt: sessie.isGekookt, nu: nu)
    }

    /// "Stap 4 van 7 · gisteren".
    static func omschrijving(_ stand: Stand, nu: Date = .now, kalender: Calendar = .current) -> String {
        "Stap \(stand.stapNummer) van \(stand.aantalStappen) · \(wanneer(stand.datum, nu: nu, kalender: kalender))"
    }

    /// "vandaag", "gisteren", "eergisteren" of "3 dagen geleden".
    static func wanneer(_ datum: Date, nu: Date = .now, kalender: Calendar = .current) -> String {
        let dagen =
            kalender.dateComponents(
                [.day], from: kalender.startOfDay(for: datum), to: kalender.startOfDay(for: nu)
            ).day ?? 0
        switch dagen {
        case ...0: return "vandaag"
        case 1: return "gisteren"
        case 2: return "eergisteren"
        default: return "\(dagen) dagen geleden"
        }
    }
}
