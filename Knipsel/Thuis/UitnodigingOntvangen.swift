import CloudKit
import SwiftUI
import UIKit

/// Alleen voor het accepteren van een uitnodiging voor Thuis (fase 8): iOS meldt dat aan de
/// scène-delegate (`windowScene(_:userDidAcceptCloudKitShareWith:)`), die SwiftUI zelf niet heeft.
/// De rest van de levenscyclus (vensters, scenePhase, Siri, de inbox) blijft bij SwiftUI: deze
/// delegate zet alleen een eigen klasse op de scèneconfiguratie, en SwiftUI stuurt de overige
/// berichten door.
final class KnipselAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuratie = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuratie.delegateClass = KnipselSceneDelegate.self
        return configuratie
    }
}

final class KnipselSceneDelegate: NSObject, UIWindowSceneDelegate {
    /// Koude start via de uitnodigingslink: de metadata zit in de verbindingsopties.
    func scene(
        _ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            accepteer(metadata)
        }
    }

    /// De app draaide al.
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        accepteer(metadata)
    }

    private func accepteer(_ metadata: CKShare.Metadata) {
        Task { @MainActor in
            await ThuisDelen.gedeeld.accepteer(metadata)
        }
    }
}
