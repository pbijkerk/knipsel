import Foundation

/// Wat je meestal in huis hebt (L2): staat op de boodschappenlijst standaard uitgevinkt. De woorden
/// zijn aan te passen in Instellingen › Boodschappen; Knipsel telt wat je uitvinkt en stelt na drie
/// keer voor het toe te voegen. Alleen op dit toestel (UserDefaults, JSON).
struct MeestalInHuis: Codable, Equatable, Sendable {
    /// Kleine letters, zoals de gebruiker ze ziet.
    var woorden: [String]
    /// Hoe vaak een ingrediënt (`BoodschappenRegel.sleutel`) is uitgevinkt en toch niet gekocht.
    var tellers: [String: Int] = [:]
    /// Voorstellen waar de gebruiker "Nee" op zei; daar vraagt Knipsel niet meer naar.
    var afgewezen: [String] = []

    /// Zout, peper, olie, water, azijn en bakpoeder. Boter en bloem niet: die raken vaker op.
    static let standaardWoorden = [
        "zout", "peper", "olie", "olijfolie", "zonnebloemolie", "water", "azijn", "bakpoeder",
    ]
    static let standaard = MeestalInHuis(woorden: standaardWoorden)

    /// Na zoveel keer uitvinken stelt Knipsel voor het woord toe te voegen.
    static let leerDrempel = 3

    /// Namen met een standaardwoord erin die je wél koopt: rode peper is geen peper uit de molen.
    private static let uitzonderingen = [
        "rode peper", "groene peper", "spaanse peper", "chilipeper", "chilipepers", "kokoswater", "rozenwater",
        "sinaasappelbloesemwater",
    ]

    /// Hoort deze naam ("olijfolie", "peper en zout", "zwarte peper") bij wat je meestal in huis hebt?
    /// Een heel woord telt, en een samenstelling die erop eindigt (zeezout, zonnebloemolie).
    func bevat(_ naam: String) -> Bool {
        let gevouwen = " " + Self.woordenIn(naam).joined(separator: " ") + " "
        let lijst = woorden.map { Self.woordenIn($0).joined(separator: " ") }.filter { !$0.isEmpty }
        // Een eigen woordgroep ("rode peper") gaat voor de uitzonderingen.
        if lijst.contains(where: { $0.contains(" ") && gevouwen.contains(" \($0) ") }) { return true }
        if Self.uitzonderingen.contains(where: { gevouwen.contains(" \(IngredientParser.vouw($0)) ") }) {
            return false
        }
        let naamwoorden = Self.woordenIn(naam).map { Portieschaling.getal($0, voor: 1) }
        return lijst.contains { woord in
            naamwoorden.contains { $0 == woord || (woord.count >= 4 && $0.count > woord.count && $0.hasSuffix(woord)) }
        }
    }

    // MARK: - Aanpassen

    mutating func voegToe(_ woord: String) {
        let schoon = woord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !schoon.isEmpty, !woorden.contains(where: { IngredientParser.vouw($0) == IngredientParser.vouw(schoon) })
        else { return }
        woorden.append(schoon)
        tellers[BoodschappenLijst.sleutel(schoon)] = nil
    }

    mutating func verwijder(_ woord: String) {
        woorden.removeAll { $0 == woord }
    }

    mutating func herstelStandaard() {
        woorden = Self.standaardWoorden
    }

    // MARK: - Leren

    /// Na versturen of delen: deze ingrediënten stonden uitgevinkt (en waren niet al "meestal in huis").
    mutating func registreerUitgevinkt(_ regels: [BoodschappenRegel]) {
        for regel in regels where !regel.meestalInHuis {
            tellers[regel.sleutel, default: 0] += 1
        }
    }

    /// Het eerste ingrediënt dat je al minstens drie keer uitvinkte en waar Knipsel nog niet naar vroeg.
    func suggestie(in regels: [BoodschappenRegel]) -> BoodschappenRegel? {
        regels.first { regel in
            !regel.meestalInHuis && (tellers[regel.sleutel] ?? 0) >= Self.leerDrempel
                && !afgewezen.contains(regel.sleutel) && !bevat(regel.woord)
        }
    }

    /// "Altijd uit": het woord erbij.
    mutating func neemOver(_ regel: BoodschappenRegel) {
        voegToe(regel.woord)
    }

    /// "Nee": niet meer naar vragen.
    mutating func wijsAf(_ regel: BoodschappenRegel) {
        if !afgewezen.contains(regel.sleutel) { afgewezen.append(regel.sleutel) }
        tellers[regel.sleutel] = nil
    }

    // MARK: - Bewaren

    static func laad(uit defaults: UserDefaults = .standard) -> MeestalInHuis {
        guard let data = defaults.data(forKey: AppConfiguratie.sleutelMeestalInHuis),
            let opgeslagen = try? JSONDecoder().decode(MeestalInHuis.self, from: data)
        else { return .standaard }
        return opgeslagen
    }

    func bewaar(in defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: AppConfiguratie.sleutelMeestalInHuis)
    }

    private static func woordenIn(_ tekst: String) -> [String] {
        IngredientParser.vouw(tekst.lowercased())
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
    }
}
