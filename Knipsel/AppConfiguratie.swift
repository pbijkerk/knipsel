import Foundation

/// Vaste instellingen en sleutels op één plek.
enum AppConfiguratie {
    /// CloudKit-container voor iCloud-sync tussen eigen toestellen (entitlement in
    /// `Knipsel/Knipsel.entitlements`). Sync gaat alleen aan als er een iCloud-account op het
    /// toestel is en de app niet onder tests draait; anders bewaart Knipsel alles lokaal.
    static let cloudKitContainer: String? = "iCloud.com.peterbijkerk.knipsel"

    /// UserDefaults: zijn de standaardcategorieën en -labels op dit toestel al eens aangemaakt?
    static let sleutelStandaardIngericht = "standaardIngericht"

    /// Leesinstellingen (Aa).
    static let sleutelLettertype = "leesLettertype"
    static let sleutelExtraGrootte = "leesExtraGrootte"
    /// Kookmodus altijd donker (standaard aan): minder verblinding in een schemerige keuken.
    static let sleutelKookmodusDonker = "kookmodusDonker"

    /// Keychain: de eigen Anthropic-sleutel voor indelen met Claude (optioneel, B10).
    static let sleutelClaude = "claudeApiSleutel"

    /// Regels met een lagere betrouwbaarheid van de tekstherkenning worden oranje in de controle.
    static let twijfelDrempel: Float = 0.5

    /// Langste zijde van een paginafoto vóór het herkennen: scherp genoeg voor krantenletters, zuinig
    /// met geheugen (de foto blijft alleen in het geheugen tot het recept bewaard is, B7).
    static let maxFotoZijde: CGFloat = 3000

    /// Privacybeleid, gelinkt vanuit de instellingen voor Claude.
    static let privacyURL = URL(string: "https://github.com/pbijkerk/knipsel/blob/main/docs/privacy.md")!

    /// Auteur van wijzigingen vanuit de app in de persistent history.
    static let transactieAuteur = "app"

    /// Wachttijd na een wijziging van buiten (iCloud) voordat er ontdubbeld wordt; een import komt
    /// vaak in meerdere stukken binnen.
    static let ontdubbelVertraging: Duration = .seconds(2)
}
