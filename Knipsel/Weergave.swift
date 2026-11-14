import Foundation

/// Tekst voor tijden, hoeveelheden en bron, los van SwiftUI zodat het testbaar is.
enum Weergave {
    /// 45 → "45 min", 60 → "1 u", 135 → "2 u 15 min".
    static func tijd(minuten: Int) -> String? {
        guard minuten > 0 else { return nil }
        let uren = minuten / 60
        let rest = minuten % 60
        switch (uren, rest) {
        case (0, _): return "\(rest) min"
        case (_, 0): return "\(uren) u"
        default: return "\(uren) u \(rest) min"
        }
    }

    static func porties(_ aantal: Int) -> String? {
        guard aantal > 0 else { return nil }
        return aantal == 1 ? "1 persoon" : "\(aantal) personen"
    }

    /// Een blokje bovenaan een recept: "45 min" boven "bereiden".
    struct Tijdblok: Equatable {
        let waarde: String
        let omschrijving: String
    }

    /// De blokjes bovenaan een recept: bereidingstijd, totale tijd en personen, alleen wat er is.
    /// Is de totale tijd gelijk aan de bereidingstijd, dan alleen "totaal".
    static func tijdblokken(bereiding: Int, totaal: Int, porties: Int) -> [Tijdblok] {
        var blokken: [Tijdblok] = []
        if bereiding != totaal, let tijd = tijd(minuten: bereiding) {
            blokken.append(Tijdblok(waarde: tijd, omschrijving: "bereiden"))
        }
        if let tijd = tijd(minuten: totaal) {
            blokken.append(Tijdblok(waarde: tijd, omschrijving: "totaal"))
        }
        if porties > 0 {
            blokken.append(Tijdblok(waarde: "\(porties)", omschrijving: porties == 1 ? "persoon" : "personen"))
        }
        return blokken
    }

    /// 0,5 → "½", 1,5 → "1½", 2 → "2", 0,3 → "0,3"; met `tot` een bereik: "2–3".
    static func hoeveelheid(_ waarde: Double, tot: Double? = nil) -> String {
        let van = getal(waarde)
        guard let tot, tot > waarde else { return van }
        return "\(van)–\(getal(tot))"
    }

    private static func getal(_ waarde: Double) -> String {
        let breuken: [(Double, String)] = [(0.25, "¼"), (0.5, "½"), (0.75, "¾"), (1.0 / 3, "⅓"), (2.0 / 3, "⅔")]
        let geheel = waarde.rounded(.down)
        let deel = waarde - geheel
        if deel < 0.001 { return String(Int(geheel)) }
        if let breuk = breuken.first(where: { abs($0.0 - deel) < 0.01 }) {
            return geheel == 0 ? breuk.1 : "\(Int(geheel))\(breuk.1)"
        }
        return waarde.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "nl_NL")))
    }

    /// "Blad · 13 nov 2026 · p. 52", zonder lege delen.
    static func bron(naam: String?, datum: Date?, pagina: String?) -> String? {
        var delen: [String] = []
        if let naam, !naam.isEmpty { delen.append(naam) }
        if let datum {
            delen.append(
                datum.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "nl_NL"))))
        }
        if let pagina, !pagina.isEmpty { delen.append("p. \(pagina)") }
        return delen.isEmpty ? nil : delen.joined(separator: " · ")
    }
}
