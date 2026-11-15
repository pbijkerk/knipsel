/// De teksten bij "Verplaats naar Thuis" / "Verplaats naar Mijn recepten" (menu ⋯ in een recept).
enum ReceptVerplaatsen {
    static func menu(naar doel: Kookboek) -> String {
        "Verplaats naar \(doel.naam)"
    }

    static func vraag(naar doel: Kookboek) -> String {
        "Naar \(doel.naam) verplaatsen?"
    }

    static func knop(naar doel: Kookboek) -> String {
        "Verplaats naar \(doel.naam)"
    }

    static func uitleg(naar doel: Kookboek, eersteKeer: Bool) -> String {
        switch doel {
        case .thuis:
            let kort =
                "Wie Thuis met je deelt, ziet dit recept dan ook (met foto en hoe vaak je het kookte) en mag het aanvullen."
            return eersteKeer
                ? kort
                    + " Thuis is een kookboek dat je deelt met een huisgenoot met een eigen Apple ID; nodig iemand uit via Instellingen › Thuis delen. Mijn recepten blijven privé."
                : kort
        case .mijn:
            return
                "Het recept komt in Mijn recepten en is dan alleen nog van jou: wie Thuis met je deelt, ziet het niet meer."
        }
    }
}
