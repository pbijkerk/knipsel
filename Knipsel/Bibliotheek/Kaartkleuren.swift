import SwiftUI
import UIKit

/// Een sRGB-kleur als 0xRRGGBB, met de relatieve luminantie en het contrast volgens WCAG 2.x.
/// Puur, zodat de contrasteis (≥ 4,5:1) per paletkleur testbaar is.
struct Hexkleur: Hashable, Sendable {
    let waarde: UInt32

    init(_ waarde: UInt32) { self.waarde = waarde }

    var rood: Double { Double((waarde >> 16) & 0xFF) / 255 }
    var groen: Double { Double((waarde >> 8) & 0xFF) / 255 }
    var blauw: Double { Double(waarde & 0xFF) / 255 }

    /// WCAG: L = 0,2126 R + 0,7152 G + 0,0722 B, met gelineariseerde kanalen.
    var relatieveLuminantie: Double {
        func lineair(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lineair(rood) + 0.7152 * lineair(groen) + 0.0722 * lineair(blauw)
    }

    /// (L1 + 0,05) / (L2 + 0,05), lichtste boven; 1 … 21.
    static func contrast(_ a: Hexkleur, _ b: Hexkleur) -> Double {
        let (la, lb) = (a.relatieveLuminantie, b.relatieveLuminantie)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    var uiColor: UIColor { UIColor(red: rood, green: groen, blue: blauw, alpha: 1) }
}

/// Een kleur voor licht en donker; in donker een gedempte variant van dezelfde tint.
struct Kleurpaar: Hashable, Sendable {
    let licht: Hexkleur
    let donker: Hexkleur

    init(licht: UInt32, donker: UInt32) {
        self.licht = Hexkleur(licht)
        self.donker = Hexkleur(donker)
    }

    var kleur: Color {
        let (licht, donker) = (licht.uiColor, donker.uiColor)
        return Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? donker : licht })
    }
}

/// Kleuren van de receptkaarten (U1): een vaste pastel per standaardcategorie, een stabiele
/// terugval voor eigen categorieën (hash van de naam) en een neutrale kaart zonder categorie.
/// Titel en ondertekst halen op elke kaartkleur ≥ 4,5:1 (`KaartkleurenTests`).
enum Kaartkleuren {
    /// Inkt op de kaart (gelijk aan de kookmodus).
    static let titel = Kleurpaar(licht: 0x2B2622, donker: 0xF6EFE4)
    /// Tijd en "n× gekookt".
    static let ondertekst = Kleurpaar(licht: 0x5A5148, donker: 0xCFC4B6)
    /// Recept zonder categorie: de papierkleur van de kookmodus.
    static let neutraal = Kleurpaar(licht: 0xF0E8DC, donker: 0x2C2622)

    /// Per standaardcategorie (op naam, zie `StandaardCategorieen`).
    static let palet: [String: Kleurpaar] = [
        "Ontbijt & brunch": Kleurpaar(licht: 0xF7E8BE, donker: 0x4A3F22),
        "Lunch": Kleurpaar(licht: 0xEFEBC2, donker: 0x434022),
        "Soepen": Kleurpaar(licht: 0xF6DEC4, donker: 0x4D3825),
        "Voorgerechten": Kleurpaar(licht: 0xE3E1F3, donker: 0x37354D),
        "Salades": Kleurpaar(licht: 0xDCEACB, donker: 0x2F3F28),
        "Hoofdgerechten": Kleurpaar(licht: 0xEDD1C8, donker: 0x4C2E27),
        "Bijgerechten": Kleurpaar(licht: 0xF5D8BC, donker: 0x4E3522),
        "Nagerechten": Kleurpaar(licht: 0xEADAF0, donker: 0x41324A),
        "Gebak & taarten": Kleurpaar(licht: 0xF3D6DE, donker: 0x4A2D36),
        "Brood": Kleurpaar(licht: 0xEBDDCB, donker: 0x433629),
        "Sauzen & dressings": Kleurpaar(licht: 0xD3E8E2, donker: 0x253F39),
        "Borrelhapjes": Kleurpaar(licht: 0xF0D3D3, donker: 0x4A2B2D),
        "Dranken": Kleurpaar(licht: 0xD3E3F0, donker: 0x263849),
    ]

    /// Vaste volgorde voor de terugval (een `Dictionary` heeft geen vaste volgorde).
    static let terugval: [Kleurpaar] = StandaardCategorieen.alle.compactMap { palet[$0.naam] }

    /// De kaartkleur bij een categorienaam; `nil` of leeg = neutraal.
    static func kleur(voorCategorie naam: String?) -> Kleurpaar {
        guard let naam = naam?.trimmingCharacters(in: .whitespacesAndNewlines), !naam.isEmpty else {
            return neutraal
        }
        if let vast = palet[naam] { return vast }
        return terugval[Int(stabieleHash(naam.lowercased()) % UInt64(terugval.count))]
    }

    /// FNV-1a over UTF-8: op elk toestel en bij elke start gelijk (`hashValue` is per start anders).
    static func stabieleHash(_ tekst: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in tekst.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }
}

extension Recept {
    /// De categorie die kleur en symbool van de kaart bepaalt: de eerste op categorie-volgorde.
    var kaartCategorie: Categorie? { gesorteerdeCategorieen.first }

    var kaartkleur: Kleurpaar { Kaartkleuren.kleur(voorCategorie: kaartCategorie?.naam) }

    /// Symbool van de eerste categorie; zonder categorie het schaartje (een knipsel).
    var kaartSymbool: String { kaartCategorie?.symboolOfStandaard ?? "scissors" }

    /// Totale tijd, anders de bereidingstijd.
    var weergaveMinuten: Int {
        Int(totaleTijdMinuten > 0 ? totaleTijdMinuten : bereidingstijdMinuten)
    }
}
