import CoreGraphics
import Foundation

/// Eén door Vision herkende tekstregel.
struct HerkendeRegel: Equatable, Sendable {
    var tekst: String
    /// Genormaliseerd (0–1) ten opzichte van de pagina, oorsprong linksboven.
    var kader: CGRect
    /// 0–1, van Vision.
    var betrouwbaarheid: Float
    /// Bij meerdere pagina's in één knipsel: 0, 1, …
    var pagina: Int = 0
}

/// Wat een regel in het recept is. Tik in het knipselscherm wisselt in deze volgorde.
enum Rol: String, CaseIterable, Sendable {
    case titel
    case intro
    case ingredient
    case stap
    case weg

    var volgende: Rol {
        let alle = Rol.allCases
        return alle[(alle.firstIndex(of: self)! + 1) % alle.count]
    }

    var naam: String {
        switch self {
        case .titel: "Titel"
        case .intro: "Intro"
        case .ingredient: "Ingrediënt"
        case .stap: "Bereiding"
        case .weg: "Weg"
        }
    }
}

/// De uitkomst van een `Indeler`: per regelnummer een rol, plus voorgestelde categorieën en labels
/// (gekozen uit de bestaande namen). De tekst zelf zit hier niet in: die blijft letterlijk.
struct Indeling: Equatable, Sendable {
    enum Bron: String, Sendable {
        case regels
        case claude
        case model

        var omschrijving: String {
            switch self {
            case .regels: "Ingedeeld op dit toestel"
            case .claude: "Ingedeeld met Claude"
            case .model: "Ingedeeld met Apple Intelligence"
            }
        }
    }

    /// Eén rol per herkende regel, in dezelfde volgorde.
    var rollen: [Rol]
    var categorieen: [String] = []
    var labels: [String] = []
    var bron: Bron = .regels

    init(rollen: [Rol], categorieen: [String] = [], labels: [String] = [], bron: Bron = .regels) {
        self.rollen = rollen
        self.categorieen = categorieen
        self.labels = labels
        self.bron = bron
    }

    /// Uit bloknummers per rol, zoals een taalmodel ze teruggeeft. Ongeldige nummers vallen weg;
    /// regels zonder rol zijn "weg". Bij dubbele toewijzing wint de eerste rol (titel vóór intro enz.).
    init(
        aantal: Int, titel: [Int] = [], intro: [Int] = [], ingredienten: [Int] = [], bereiding: [Int] = [],
        categorieen: [String] = [], labels: [String] = [], bron: Bron = .regels
    ) {
        var rollen = Array(repeating: Rol.weg, count: aantal)
        var toegewezen = Set<Int>()
        for (rol, nummers) in [(Rol.titel, titel), (.intro, intro), (.ingredient, ingredienten), (.stap, bereiding)] {
            for nummer in nummers where rollen.indices.contains(nummer) && !toegewezen.contains(nummer) {
                rollen[nummer] = rol
                toegewezen.insert(nummer)
            }
        }
        self.init(rollen: rollen, categorieen: categorieen, labels: labels, bron: bron)
    }

    /// Regelnummers met deze rol, oplopend.
    func blokken(_ rol: Rol) -> [Int] {
        rollen.indices.filter { rollen[$0] == rol }
    }

    /// Alleen namen die echt bestaan, in de schrijfwijze van de bestaande lijst.
    static func bestaande(_ namen: [String], uit lijst: [String]) -> [String] {
        var gezien = Set<String>()
        return namen.compactMap { naam in
            let sleutel = Inrichting.sleutel(naam)
            guard let bestaand = lijst.first(where: { Inrichting.sleutel($0) == sleutel }),
                gezien.insert(sleutel).inserted
            else { return nil }
            return bestaand
        }
    }
}

/// Deelt herkende regels in: welke regel is titel, intro, ingrediënt, stap of hoort er niet bij.
/// Implementaties herschrijven nooit tekst; ze geven alleen rollen terug (zie docs/ontwerp.md §3.1).
protocol Indeler: Sendable {
    func deelIn(_ regels: [HerkendeRegel], categorieen: [String], labels: [String]) async -> Indeling
}

/// Kiest de indeler: Claude als er een sleutel is, anders het on-device model als het toestel dat
/// heeft, anders de regels. Elke keuze valt bij een fout stil terug op de volgende.
enum IndelerKeuze {
    static func standaard(sleutel: String? = KeychainService.load(forKey: AppConfiguratie.sleutelClaude))
        -> any Indeler
    {
        var basis: any Indeler = RegelIndeler()
        #if canImport(FoundationModels)
            if ModelIndeler.isBeschikbaar {
                basis = ModelIndeler(terugval: basis)
            }
        #endif
        if let sleutel, !sleutel.isEmpty {
            return ClaudeIndeler(sleutel: { sleutel }, terugval: basis)
        }
        return basis
    }
}
