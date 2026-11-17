import Foundation

/// Instellingen › Boodschappen › Standaard bestemming (#39): waar de hoofdknop van het vel heen gaat.
enum BoodschappenStandaard: String, CaseIterable, Identifiable, Sendable {
    case knipsel
    case herinneringen

    var id: String { rawValue }

    var naam: String {
        switch self {
        case .knipsel: "Knipsel-lijst"
        case .herinneringen: "Herinneringen"
        }
    }

    static func laad(uit defaults: UserDefaults = .standard) -> BoodschappenStandaard {
        defaults.string(forKey: AppConfiguratie.sleutelBoodschappenBestemming).flatMap(Self.init(rawValue:)) ?? .knipsel
    }
}

/// Waar de boodschappen uit het vel heen gaan.
enum VelBestemming: Equatable, Sendable {
    /// De eigen lijst in Knipsel van dit kookboek.
    case lijst(Kookboek)
    case herinneringen

    /// De hoofdknop: met de Knipsel-lijst als standaard de lijst van het kookboek van het recept (een
    /// Thuis-recept gaat op de Thuis-lijst, zonder te vragen); anders Herinneringen.
    static func hoofd(standaard: BoodschappenStandaard, kookboek: Kookboek) -> VelBestemming {
        switch standaard {
        case .knipsel: .lijst(kookboek)
        case .herinneringen: .herinneringen
        }
    }

    /// Bij meerdere recepten (#40): de lijst van het kookboek waar de meeste recepten in staan; bij
    /// gelijkspel Mijn lijst.
    static func kookboek(voor kookboeken: [Kookboek]) -> Kookboek {
        let thuis = kookboeken.filter { $0 == .thuis }.count
        return thuis > kookboeken.count - thuis ? .thuis : .mijn
    }

    /// Of het vel voor meerdere recepten "Zet op: Mijn lijst | Thuis" toont: alleen als Thuis bestaat
    /// (gedeeld, of er staat al iets in), en niet als alles naar Herinneringen gaat.
    static func toonKookboekKeuze(meerdere: Bool, thuisBestaat: Bool) -> Bool { meerdere && thuisBestaat }

    /// "Zet 5 op mijn lijst", "Zet 5 op de Thuis-lijst", "Zet 5 in Herinneringen".
    func knop(aantal: Int) -> String {
        guard aantal > 0 else { return "Niets op de lijst" }
        switch self {
        case .lijst(.mijn): return "Zet \(aantal) op mijn lijst"
        case .lijst(.thuis): return "Zet \(aantal) op de Thuis-lijst"
        case .herinneringen: return "Zet \(aantal) op de lijst"
        }
    }

    /// Bevestiging: "5 items op je lijst in Knipsel".
    func bevestiging(aantal: Int) -> String {
        let items = aantal == 1 ? "1 item" : "\(aantal) items"
        switch self {
        case .lijst(.mijn): return "\(items) op je lijst in Knipsel"
        case .lijst(.thuis): return "\(items) op de Thuis-lijst"
        case .herinneringen: return "\(items) in Herinneringen › Boodschappen"
        }
    }
}
