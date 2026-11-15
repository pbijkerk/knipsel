import SwiftUI

@main
struct KnipselApp: App {
    /// Alleen voor het accepteren van een uitnodiging voor Thuis (`KnipselSceneDelegate`).
    @UIApplicationDelegateAdaptor(KnipselAppDelegate.self) private var appDelegate
    private let opslag = Opslag.gedeeld

    init() {
        opslag.richIn()
        // "Verder met…" van vóór fase 8 wees naar het objectID; nu naar de uuid van het recept.
        KookVoortgang().migreer(in: opslag.context)
        // Recepten vindbaar in Spotlight en voor Siri ("Kook … met Knipsel").
        ReceptIndex.gedeeld.start(opslag: opslag)
        // Nieuwe Thuis-recepten in de share van Thuis zetten (fase 8).
        ThuisDelen.gedeeld.start()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, opslag.context)
                .environment(InleesInbox.gedeeld)
        }
    }
}
