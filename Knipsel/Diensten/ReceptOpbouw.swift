import CoreGraphics
import Foundation

/// Een regel in het controlescherm: een ingrediënt of een stap, met waar hij vandaan komt.
struct ConceptRegel: Identifiable, Equatable, Sendable {
    let id = UUID()
    var tekst: String
    /// De tekst zoals herkend; als de gebruiker hem wijzigt, vervalt de twijfel over de herkenning.
    let herkend: String
    /// Vision was niet zeker van (een deel van) deze regel.
    let laagVertrouwen: Bool
    /// Regelnummers in de herkenning, voor de uitsnede uit de foto.
    let regels: [Int]

    init(tekst: String, laagVertrouwen: Bool = false, regels: [Int] = []) {
        self.tekst = tekst
        self.herkend = tekst
        self.laagVertrouwen = laagVertrouwen
        self.regels = regels
    }
}

/// Het recept zoals het uit de indeling komt, nog niet bewaard.
struct ReceptConcept: Equatable, Sendable {
    var titel = ""
    var intro = ""
    var porties = 0
    var minuten = 0
    var ingredienten: [ConceptRegel] = []
    var stappen: [ConceptRegel] = []
}

/// Voegt ingedeelde regels samen tot een recept. Alleen code, geen taalmodel: de tekst blijft
/// letterlijk. Genummerde stapregels gaan aan elkaar tot een nieuw nummer begint; lopende bereiding
/// knipt `StapSplitser` in stappen. Elke ingrediëntregel blijft een eigen regel (een afgebroken
/// regel wordt weer heel).
enum ReceptOpbouw {
    static func bouw(_ regels: [HerkendeRegel], indeling: Indeling) -> ReceptConcept {
        let opmaak = Opmaak(regels)
        let volgorde = opmaak.leesvolgorde
        func inVolgorde(_ rol: Rol) -> [Int] {
            volgorde.filter { indeling.rollen.indices.contains($0) && indeling.rollen[$0] == rol }
        }

        var concept = ReceptConcept()
        concept.titel = inVolgorde(.titel).map { regels[$0].tekst }.joined(separator: " ")
        concept.intro = plak(inVolgorde(.intro).map { regels[$0].tekst })
        concept.porties = porties(in: concept.intro)
        concept.minuten = minuten(in: concept.intro)

        // Ingrediënten: een regel per ingrediënt; kopjes ("Ingrediënten") vallen weg.
        for nummer in inVolgorde(.ingredient) {
            let regel = regels[nummer]
            // Een opsommingsteken ("• 1 fles rode wijn") hoort niet bij het ingrediënt.
            let tekst = IngredientParser.zonderOpsommingsteken(regel.tekst)
            guard !tekst.isEmpty, !IngredientParser.isKopje(tekst) else { continue }
            if let vorige = concept.ingredienten.last, loopDoor(vorige.tekst, met: tekst) {
                concept.ingredienten[concept.ingredienten.count - 1] = ConceptRegel(
                    tekst: plak([vorige.tekst, tekst]),
                    laagVertrouwen: vorige.laagVertrouwen || isOnzeker(regel),
                    regels: vorige.regels + [nummer])
            } else {
                concept.ingredienten.append(
                    ConceptRegel(tekst: tekst, laagVertrouwen: isOnzeker(regel), regels: [nummer]))
            }
        }

        // Stappen: genummerd → samenvoegen tot een nieuw nummer begint (blijft zoals het was).
        // Lopende tekst → `StapSplitser` (op de beginwoorden van het taalmodel, als die kloppen).
        let stapRegels = inVolgorde(.stap).filter { !IngredientParser.isKopje(regels[$0].tekst) }
        let genummerd = stapRegels.contains { IngredientParser.isGenummerd(regels[$0].tekst) }
        if genummerd {
            for nummer in stapRegels {
                let regel = regels[nummer]
                if concept.stappen.isEmpty || IngredientParser.isGenummerd(regel.tekst) {
                    concept.stappen.append(
                        ConceptRegel(
                            tekst: zonderNummer(regel.tekst), laagVertrouwen: isOnzeker(regel), regels: [nummer]))
                } else {
                    let vorige = concept.stappen.removeLast()
                    concept.stappen.append(
                        ConceptRegel(
                            tekst: plak([vorige.tekst, regel.tekst]),
                            laagVertrouwen: vorige.laagVertrouwen || isOnzeker(regel), regels: vorige.regels + [nummer])
                    )
                }
            }
        } else {
            var stukken: [StapSplitser.Stuk] = []
            var vorigBlok: Int?
            for nummer in stapRegels {
                let blok = opmaak.blokVanRegel[nummer]
                // Nieuwe alinea: een ander blok (witruimte, andere kolom) of een ingesprongen regel.
                let ingesprongen =
                    regels[nummer].kader.minX - opmaak.blokken[blok].kader.minX > Self.inspringing
                stukken.append(
                    StapSplitser.Stuk(
                        tekst: regels[nummer].tekst, regel: nummer, laagVertrouwen: isOnzeker(regels[nummer]),
                        nieuweAlinea: (vorigBlok != nil && blok != vorigBlok) || ingesprongen))
                vorigBlok = blok
            }
            concept.stappen = StapSplitser.conceptStappen(stukken, beginnen: indeling.stapBeginnen)
        }
        return concept
    }

    /// Een regel die zoveel verder naar rechts begint (deel van de paginabreedte) springt in: een
    /// nieuwe alinea. Vision-kaders van gewone regels in één kolom wijken tot ±0,012 af.
    static let inspringing: CGFloat = 0.015

    // MARK: - Twijfel

    static func isOnzeker(_ regel: HerkendeRegel) -> Bool {
        regel.betrouwbaarheid < AppConfiguratie.twijfelDrempel
    }

    /// Oranje in het controlescherm: de herkenning was onzeker (en de gebruiker heeft de regel nog
    /// niet aangepast), of een ingrediënt mist waarschijnlijk zijn eenheid.
    static func isTwijfel(_ regel: ConceptRegel, isIngredient: Bool) -> Bool {
        if regel.laagVertrouwen && regel.tekst == regel.herkend { return true }
        return isIngredient && IngredientParser.mistEenheid(regel.tekst)
    }

    // MARK: - Samenvoegen

    /// Plakt regels aan elkaar. Een afgebroken woord ("groente-" + "bouillon") wordt weer heel.
    static func plak(_ delen: [String]) -> String {
        var resultaat = ""
        for deel in delen.map({ $0.trimmingCharacters(in: .whitespaces) }) where !deel.isEmpty {
            if resultaat.hasSuffix("-"), let eerste = deel.first, eerste.isLowercase,
                let voorLaatste = resultaat.dropLast().last, voorLaatste.isLetter
            {
                resultaat = String(resultaat.dropLast()) + deel
            } else {
                resultaat += resultaat.isEmpty ? deel : " " + deel
            }
        }
        return resultaat
    }

    /// Loopt een ingrediëntregel door op de volgende regel? Bij een open haakje, een komma of een
    /// afbreekstreepje aan het eind.
    private static func loopDoor(_ vorige: String, met volgende: String) -> Bool {
        let open = vorige.filter { $0 == "(" }.count > vorige.filter { $0 == ")" }.count
        return open || vorige.hasSuffix(",") || (vorige.hasSuffix("-") && volgende.first?.isLowercase == true)
    }

    /// "3. Voeg de pompoen …" → "Voeg de pompoen …": de app nummert de stappen zelf.
    static func zonderNummer(_ tekst: String) -> String {
        guard let bereik = tekst.range(of: #"^\s*\d{1,2}\s*[.)]\s*"#, options: .regularExpression),
            IngredientParser.isGenummerd(tekst)
        else { return tekst }
        return String(tekst[bereik.upperBound...])
    }

    // MARK: - Porties en tijd

    /// "Voor 4 personen" → 4.
    static func porties(in tekst: String) -> Int {
        let patronen = [#"(\d+)\s*(personen|persoon|pers\b|porties|portie)"#, #"voor\s+(\d+)\b"#]
        for patroon in patronen {
            if let getal = eersteGetal(patroon, in: tekst) { return getal }
        }
        return 0
    }

    /// "45 minuten" → 45, "1 uur" → 60, "1 uur 15 min" → 75.
    static func minuten(in tekst: String) -> Int {
        let uren = eersteGetal(#"(\d+)\s*(uur|uren|u\b)"#, in: tekst) ?? 0
        let minuten = eersteGetal(#"(\d+)\s*(minuten|minuut|min\b)"#, in: tekst) ?? 0
        return uren * 60 + minuten
    }

    private static func eersteGetal(_ patroon: String, in tekst: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: patroon, options: .caseInsensitive),
            let treffer = regex.firstMatch(in: tekst, range: NSRange(tekst.startIndex..., in: tekst)),
            let bereik = Range(treffer.range(at: 1), in: tekst)
        else { return nil }
        return Int(tekst[bereik])
    }
}
