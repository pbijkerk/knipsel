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

        // 1. Reclame en andere artikelen: het hele blok weg. Eén reclamewoord in een lange column
        //    ("als je dat betalen kon") maakt er nog geen advertentie van.
        for (index, blok) in opmaak.blokken.enumerated() {
            let reclame = blok.regels.filter { isReclame(regels[$0].tekst) }.count
            if reclame > 0, blok.regels.count <= 8 || reclame * 4 >= blok.regels.count {
                blokRol[index] = .weg
            }
        }

        // 2. Titel: de grootste letter (hoogste regel) buiten de weggelaten blokken; een regel met
        //    porties ("Nagerecht voor 4 personen") is geen titel. Steekt geen regel duidelijk boven de
        //    rest uit (Vision-kaders van een krantenkop zijn soms niet hoger), dan de bovenste korte
        //    regel die geen zin is.
        let kandidaten = regels.indices.filter {
            blokRol[opmaak.blokVanRegel[$0]] == nil && regels[$0].tekst.count >= 3 && !isPortiesregel(regels[$0].tekst)
        }
        guard var grootste = kandidaten.max(by: { regels[$0].kader.height < regels[$1].kader.height }) else {
            return Indeling(rollen: rollen)
        }
        let hoogtes = kandidaten.map { regels[$0].kader.height }.sorted()
        let mediaan = hoogtes[hoogtes.count / 2]
        if regels[grootste].kader.height < mediaan * 1.5,
            let bovenste =
                kandidaten
                .filter({ isKopregel(regels[$0].tekst) })
                .min(by: { regels[$0].kader.minY < regels[$1].kader.minY })
        {
            grootste = bovenste
        }
        let titelBlok = opmaak.blokVanRegel[grootste]
        let titelHoogte = regels[grootste].kader.height
        for regel in opmaak.blokken[titelBlok].regels {
            let isTitel = regels[regel].kader.height >= titelHoogte * 0.8 && !isPortiesregel(regels[regel].tekst)
            rollen[regel] = isTitel ? .titel : .intro
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

        // 4b. Een column of verhaal vooraf waarin de bereiding zonder kopje begint ("Schil de peren,
        //     …" midden in de laatste kolom): vanaf die alinea bereiding, ervóór intro (#17).
        for (index, blok) in opmaak.blokken.enumerated()
        where index != titelBlok && blok.pagina == titelPagina && (blokRol[index] == nil || blokRol[index] == .intro) {
            guard let begin = bereidingBegin(blok.regels, in: regels) else { continue }
            for (positie, regel) in blok.regels.enumerated() {
                rollen[regel] = positie < begin ? .intro : .stap
            }
        }
        // Een afzender (e-mailadres, website) hoort nooit bij het recept.
        for regel in regels.indices where isAfzender(regels[regel].tekst) { rollen[regel] = .weg }

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

    /// Waar in lopende tekst de bereiding begint: de eerste alinea die met een gebiedende zin begint
    /// ("Schil de peren, …"), gevolgd door overwegend handelingen. Een alinea herken je aan inspringen
    /// of aan een korte regel ervoor; Vision geeft geen vet. Zinnen met ik, je of we en zinnen in de
    /// verleden tijd ("Onderdeel ervan was het inkoken …") tellen niet. Geeft de positie in `nummers`.
    static func bereidingBegin(_ nummers: [Int], in regels: [HerkendeRegel]) -> Int? {
        guard nummers.count >= 2 else { return nil }
        let stukken = nummers.map { StapSplitser.Stuk(tekst: regels[$0].tekst) }
        let bron = StapSplitser.Bron(stukken)
        let zinnen = StapSplitser.zinnen(bron).map {
            (begin: $0.bereik.lowerBound, tekst: String(bron.tekens[$0.bereik]))
        }
        let kaders = nummers.map { regels[$0].kader }
        let links = kaders.map(\.minX).min() ?? 0
        let rechts = kaders.map(\.maxX).max() ?? 1
        let breedte = rechts - links
        for positie in nummers.indices {
            let bereik = bron.bereik[positie]
            guard !bereik.isEmpty, let eerste = zinnen.firstIndex(where: { $0.begin == bereik.lowerBound }) else {
                continue
            }
            let alinea =
                positie == 0 || kaders[positie].minX > links + 0.008
                || kaders[positie - 1].width < breedte * 0.85
            guard alinea, StapSplitser.isGebiedend(zinnen[eerste].tekst) else { continue }
            let rest = zinnen[eerste...].map(\.tekst).filter { !isAfzender($0) }
            let handelingen = rest.filter(StapSplitser.isHandeling).count
            let vooraan = rest.prefix(3).filter(StapSplitser.isHandeling).count
            if handelingen >= 3, vooraan >= 2, handelingen * 2 >= rest.count { return positie }
        }
        return nil
    }

    /// "Nagerecht voor 4 personen", "6 porties".
    static func isPortiesregel(_ tekst: String) -> Bool {
        tekst.range(of: #"\d+\s*(personen|persoon|porties|portie)\b"#, options: [.regularExpression, .caseInsensitive])
            != nil
    }

    /// Kan een titel zijn: kort en geen zin.
    private static func isKopregel(_ tekst: String) -> Bool {
        let t = tekst.trimmingCharacters(in: .whitespaces)
        guard let laatste = t.last, t.count >= 3 else { return false }
        return t.split(separator: " ").count <= 8 && !".,;:-".contains(laatste) && !isAfzender(t)
            && t.first?.isUppercase == true
    }

    /// "volkskeuken@krant.nl", "www.voorbeeld.nl": een afzender, geen recepttekst.
    static func isAfzender(_ tekst: String) -> Bool {
        let t = tekst.trimmingCharacters(in: .whitespaces)
        return t.range(of: #"^\S+@\S+\.\w{2,}$"#, options: .regularExpression) != nil
            || t.range(of: #"^(https?://|www\.)\S+$"#, options: [.regularExpression, .caseInsensitive]) != nil
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
        ("nagerecht", "Nagerechten"),
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
