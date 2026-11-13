import CoreGraphics
import Foundation

/// Indelen met vaste regels, op het toestel en zonder netwerk: de basis op toestellen zonder
/// Apple Intelligence (B9, B10). Werkt op de bladspiegel uit Vision (lettergrootte, kolommen) en
/// de tekst (getal + eenheid, nummering, reclamewoorden).
struct RegelIndeler: Indeler {
    func deelIn(_ regels: [HerkendeRegel], categorieen: [String], labels: [String]) async -> Indeling {
        Self.deelIn(regels, categorieen: categorieen, labels: labels)
    }

    static func deelIn(_ regels: [HerkendeRegel], categorieen: [String], labels: [String]) -> Indeling {
        guard !regels.isEmpty else { return Indeling(rollen: []) }
        let opmaak = Opmaak(regels)
        var rollen = Array(repeating: Rol.weg, count: regels.count)
        var blokRol = Array(repeating: Rol?.none, count: opmaak.blokken.count)

        // 1. Reclame en andere artikelen: het hele blok weg.
        for (index, blok) in opmaak.blokken.enumerated()
        where blok.regels.contains(where: { isReclame(regels[$0].tekst) }) {
            blokRol[index] = .weg
        }

        // 2. Titel: de grootste letter (hoogste regel) buiten de weggelaten blokken.
        let kandidaten = regels.indices.filter {
            blokRol[opmaak.blokVanRegel[$0]] == nil && regels[$0].tekst.count >= 3
        }
        guard let grootste = kandidaten.max(by: { regels[$0].kader.height < regels[$1].kader.height }) else {
            return Indeling(rollen: rollen)
        }
        let titelBlok = opmaak.blokVanRegel[grootste]
        let titelHoogte = regels[grootste].kader.height
        for regel in opmaak.blokken[titelBlok].regels {
            rollen[regel] = regels[regel].kader.height >= titelHoogte * 0.8 ? .titel : .intro
        }
        blokRol[titelBlok] = .titel

        // 3. Ingrediëntenlijsten en genummerde stappen.
        for (index, blok) in opmaak.blokken.enumerated() where blokRol[index] == nil {
            let teksten = blok.regels.map { regels[$0].tekst }
            let inhoud = teksten.filter { !IngredientParser.isKopje($0) }
            if inhoud.isEmpty {
                blokRol[index] = .weg  // alleen een kopje ("Bereiding")
            } else if inhoud.contains(where: IngredientParser.isGenummerd) {
                blokRol[index] = .stap
            } else {
                let ingredienten = inhoud.filter(IngredientParser.lijktIngredient).count
                let gemiddeldeLengte = inhoud.map(\.count).reduce(0, +) / inhoud.count
                if ingredienten * 2 >= inhoud.count, gemiddeldeLengte <= 45 {
                    blokRol[index] = .ingredient
                }
            }
        }

        // 4. Intro: tussen titel en recept, of met porties/tijd. Doorlopende bereiding: lopende tekst
        //    in dezelfde kolom als het recept, vlak onder of tussen de stappen.
        let titelPagina = opmaak.blokken[titelBlok].pagina
        let receptBovenkant =
            opmaak.blokken.indices
            .filter { [.ingredient, .stap].contains(blokRol[$0]) && opmaak.blokken[$0].pagina == titelPagina }
            .map { opmaak.blokken[$0].kader.minY }.min() ?? 1
        var gewijzigd = true
        while gewijzigd {
            gewijzigd = false
            for (index, blok) in opmaak.blokken.enumerated() where blokRol[index] == nil {
                let tekst = blok.regels.map { regels[$0].tekst }.joined(separator: " ")
                if blok.pagina == titelPagina, blok.kader.maxY <= receptBovenkant + 0.005,
                    blok.kader.minY >= opmaak.blokken[titelBlok].kader.minY
                {
                    blokRol[index] = .intro
                    gewijzigd = true
                } else if isLopendeTekst(tekst), sluitAanOpRecept(blok, opmaak: opmaak, rollen: blokRol) {
                    blokRol[index] = .stap
                    gewijzigd = true
                } else if looptDoorOnder(blok, opmaak: opmaak, rollen: blokRol) {
                    blokRol[index] = .stap
                    gewijzigd = true
                }
            }
        }
        for (index, blok) in opmaak.blokken.enumerated() where index != titelBlok {
            for regel in blok.regels { rollen[regel] = blokRol[index] ?? .weg }
        }

        // 5. Voorstellen voor categorie en labels, alleen uit de bestaande namen.
        let titel = rollen.indices.filter { rollen[$0] == .titel }.map { regels[$0].tekst }.joined(separator: " ")
        let intro = rollen.indices.filter { rollen[$0] == .intro }.map { regels[$0].tekst }.joined(separator: " ")
        let ingredienten = rollen.indices.filter { rollen[$0] == .ingredient }.map { regels[$0].tekst }
        return Indeling(
            rollen: rollen,
            categorieen: Voorstellen.categorieen(titel: titel, intro: intro, uit: categorieen),
            labels: Voorstellen.labels(
                ingredienten: ingredienten, minuten: ReceptOpbouw.minuten(in: intro), uit: labels),
            bron: .regels)
    }

    // MARK: - Regels

    /// Een korte rest direct onder een stap ("met peper en zout."): de laatste regel van die stap.
    private static func looptDoorOnder(_ blok: Opmaak.Blok, opmaak: Opmaak, rollen: [Rol?]) -> Bool {
        opmaak.blokken.indices.contains { index in
            let stap = opmaak.blokken[index]
            guard rollen[index] == .stap, stap.pagina == blok.pagina, !stap.regels.isEmpty else { return false }
            let regelhoogte = stap.kader.height / CGFloat(stap.regels.count)
            let tussenruimte = blok.kader.minY - stap.kader.maxY
            return abs(blok.kader.minX - stap.kader.minX) < 0.02 && tussenruimte >= -0.005
                && tussenruimte < regelhoogte * 0.8
        }
    }

    /// Woorden die op een advertentie of ander artikel wijzen.
    static func isReclame(_ tekst: String) -> Bool {
        let t = IngredientParser.vouw(tekst)
        if t.contains("€") { return true }
        return reclamePatronen.contains { t.range(of: $0, options: .regularExpression) != nil }
    }

    private static let reclamePatronen = [
        #"\bhalen\b"#, #"\bbetalen\b"#, #"geldig t/?m"#, #"geldig tot"#, #"lees verder"#, #"\baanbieding"#,
        #"\bkorting\b"#, #"\bactieprijs"#, #"lezersbrief"#, #"\badvertentie"#, #"\bwin\b.*\bprijs"#,
    ]

    /// Zinnen, geen lijst: gemiddeld lange regels en een punt erin.
    private static func isLopendeTekst(_ tekst: String) -> Bool {
        tekst.count >= 40 && tekst.contains(".")
    }

    /// Ligt het blok in een kolom met ingrediënten of stappen, vlak onder of boven zo'n blok, of
    /// naast de ingrediëntenlijst?
    private static func sluitAanOpRecept(_ blok: Opmaak.Blok, opmaak: Opmaak, rollen: [Rol?]) -> Bool {
        opmaak.blokken.indices.contains { index in
            let ander = opmaak.blokken[index]
            guard rollen[index] == .stap || rollen[index] == .ingredient, ander.pagina == blok.pagina else {
                return false
            }
            let overlapX = min(ander.kader.maxX, blok.kader.maxX) - max(ander.kader.minX, blok.kader.minX)
            let afstand = max(blok.kader.minY - ander.kader.maxY, ander.kader.minY - blok.kader.maxY)
            if overlapX > min(blok.kader.width, ander.kader.width) * 0.5 && afstand < 0.06 { return true }
            // Lopende tekst naast de ingrediëntenlijst: de bereiding in de kolom ernaast.
            let overlapY = min(ander.kader.maxY, blok.kader.maxY) - max(ander.kader.minY, blok.kader.minY)
            let naast = max(blok.kader.minX - ander.kader.maxX, ander.kader.minX - blok.kader.maxX)
            return rollen[index] == .ingredient && overlapY > 0 && naast >= 0 && naast < 0.15
        }
    }
}

/// Voorstellen voor categorie en labels op trefwoorden; alleen namen die al bestaan.
enum Voorstellen {
    /// Trefwoord (zonder accenten, kleine letters) → standaardcategorie.
    private static let categorieTrefwoorden: [(String, String)] = [
        ("soep", "Soepen"), ("bouillon", "Soepen"), ("salade", "Salades"), ("taart", "Gebak & taarten"),
        ("cake", "Gebak & taarten"), ("koek", "Gebak & taarten"), ("muffin", "Gebak & taarten"),
        ("brownie", "Gebak & taarten"), ("brood", "Brood"), ("focaccia", "Brood"), ("saus", "Sauzen & dressings"),
        ("dressing", "Sauzen & dressings"), ("pesto", "Sauzen & dressings"), ("vinaigrette", "Sauzen & dressings"),
        ("mousse", "Nagerechten"), ("pudding", "Nagerechten"), ("tiramisu", "Nagerechten"),
        ("crumble", "Nagerechten"), ("ijs", "Nagerechten"), ("toetje", "Nagerechten"), ("dessert", "Nagerechten"),
        ("panna cotta", "Nagerechten"), ("ontbijt", "Ontbijt & brunch"), ("brunch", "Ontbijt & brunch"),
        ("pannenkoek", "Ontbijt & brunch"), ("granola", "Ontbijt & brunch"), ("omelet", "Ontbijt & brunch"),
        ("limonade", "Dranken"), ("cocktail", "Dranken"), ("smoothie", "Dranken"), ("borrel", "Borrelhapjes"),
        ("hapje", "Borrelhapjes"), ("dip", "Borrelhapjes"), ("tapas", "Borrelhapjes"),
        ("stamppot", "Hoofdgerechten"), ("stoof", "Hoofdgerechten"), ("ovenschotel", "Hoofdgerechten"),
        ("curry", "Hoofdgerechten"), ("risotto", "Hoofdgerechten"), ("lasagne", "Hoofdgerechten"),
        ("pasta", "Hoofdgerechten"), ("tajine", "Hoofdgerechten"), ("tosti", "Lunch"), ("wrap", "Lunch"),
        ("sandwich", "Lunch"), ("broodje", "Lunch"), ("lunch", "Lunch"),
    ]

    private static let vlees = [
        "vlees", "kip", "gehakt", "spek", "ham", "rund", "varken", "worst", "lam", "bacon", "chorizo", "kalkoen",
        "eend", "biefstuk", "ossenstaart", "pancetta", "salami", "kalfs", "konijn", "hert",
    ]
    private static let vis = [
        "vis", "zalm", "garnal", "tonijn", "kabeljauw", "ansjovis", "makreel", "mosselen", "haring", "forel",
        "schelvis", "inktvis", "scampi", "kreeft", "krab", "sardine",
    ]

    /// Korte woorden die ook binnen andere woorden voorkomen, tellen alleen aan het begin van een
    /// woord: "ham" niet in "champignons", "ijs" niet in "rijst". De rest ook midden in een
    /// samenstelling ("pompoensoep", "ontbijtspek").
    private static let alleenWoordbegin: Set<String> = [
        "ijs", "dip", "ham", "kip", "lam", "vis", "eend", "hert", "rund", "wrap",
    ]

    static func bevat(_ tekst: String, _ woord: String) -> Bool {
        alleenWoordbegin.contains(woord)
            ? tekst.range(of: "\\b" + woord, options: .regularExpression) != nil : tekst.contains(woord)
    }

    static func categorieen(titel: String, intro: String, uit bestaande: [String]) -> [String] {
        let tekst = IngredientParser.vouw(titel + " " + intro)
        // "broodje" is lunch, niet brood: langste trefwoord eerst.
        var namen: [String] = []
        var gebruikt = tekst
        for (woord, categorie) in categorieTrefwoorden.sorted(by: { $0.0.count > $1.0.count })
        where bevat(gebruikt, woord) {
            namen.append(categorie)
            gebruikt = gebruikt.replacingOccurrences(of: woord, with: " ")
        }
        return Array(Indeling.bestaande(namen, uit: bestaande).prefix(2))
    }

    static func labels(ingredienten: [String], minuten: Int, uit bestaande: [String]) -> [String] {
        let namen = ingredienten.map { IngredientParser.vouw(IngredientParser.parse($0).naam) }
        func bevat(_ woorden: [String]) -> Bool {
            namen.contains { naam in woorden.contains { Self.bevat(naam, $0) } }
        }
        var voorstel: [String] = []
        let heeftVlees = bevat(vlees)
        let heeftVis = bevat(vis)
        if heeftVlees { voorstel.append("Vlees") }
        if heeftVis { voorstel.append("Vis") }
        if !heeftVlees, !heeftVis, ingredienten.count >= 3 { voorstel.append("Vegetarisch") }
        if minuten > 0, minuten <= 30 {
            // Het standaardlabel heet "Snel (< 30 min)"; een hernoemd label "Snel" telt ook.
            voorstel.append(
                bestaande.first { IngredientParser.vouw($0).hasPrefix("snel") } ?? "Snel")
        }
        return Indeling.bestaande(voorstel, uit: bestaande)
    }
}
