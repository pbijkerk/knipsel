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

    /// Auteur van wijzigingen vanuit de app in de persistent history.
    static let transactieAuteur = "app"

    /// Wachttijd na een wijziging van buiten (iCloud) voordat er ontdubbeld wordt; een import komt
    /// vaak in meerdere stukken binnen.
    static let ontdubbelVertraging: Duration = .seconds(2)
}
