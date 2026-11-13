import Foundation

/// De categorieën waarmee een nieuwe installatie start (zie docs/ontwerp.md, K4).
/// Categorie = de gang of het soort gerecht; labels (vegetarisch, snel, …) zijn een aparte as.
/// De gebruiker kan ze hernoemen, verbergen, verplaatsen, verwijderen en aanvullen.
struct StandaardCategorie: Identifiable, Hashable, Sendable {
    let naam: String
    /// SF Symbol.
    let symbool: String
    var id: String { naam }
}

enum StandaardCategorieen {
    static let alle: [StandaardCategorie] = [
        .init(naam: "Ontbijt & brunch", symbool: "sun.horizon"),
        .init(naam: "Lunch", symbool: "takeoutbag.and.cup.and.straw"),
        .init(naam: "Soepen", symbool: "cup.and.saucer"),
        .init(naam: "Voorgerechten", symbool: "fork.knife"),
        .init(naam: "Salades", symbool: "leaf"),
        .init(naam: "Hoofdgerechten", symbool: "frying.pan"),
        .init(naam: "Bijgerechten", symbool: "carrot"),
        .init(naam: "Nagerechten", symbool: "birthday.cake"),
        .init(naam: "Gebak & taarten", symbool: "oven"),
        .init(naam: "Brood", symbool: "basket"),
        .init(naam: "Sauzen & dressings", symbool: "drop"),
        .init(naam: "Borrelhapjes", symbool: "wineglass"),
        .init(naam: "Dranken", symbool: "mug"),
    ]

    /// Labels: een recept kan er meerdere hebben, naast zijn categorie.
    static let labels: [String] = [
        "Vegetarisch", "Vegan", "Vis", "Vlees", "Snel (< 30 min)", "Feestelijk", "Voorbereiden",
    ]
}
