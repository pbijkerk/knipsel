import Foundation

/// Vaste instellingen en sleutels op één plek.
enum AppConfiguratie {
    /// CloudKit-container voor iCloud-sync tussen eigen toestellen.
    ///
    /// Staat bewust op `nil`: de container en het iCloud-entitlement bestaan nog niet, en een
    /// verwijzing ernaar breekt de Xcode Cloud-build. Zolang dit `nil` is, bewaart Knipsel alles
    /// alleen op het toestel. Aanzetten (zie de PR van fase 1):
    /// 1. In Xcode: Signing & Capabilities › + iCloud › CloudKit, container
    ///    `iCloud.com.peterbijkerk.knipsel`, plus Background Modes › Remote notifications.
    /// 2. Het entitlement-bestand vastleggen in `project.yml` (`CODE_SIGN_ENTITLEMENTS`).
    /// 3. Deze waarde op `"iCloud.com.peterbijkerk.knipsel"` zetten.
    static let cloudKitContainer: String? = nil

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
