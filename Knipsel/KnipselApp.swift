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
        // Fase 7: kooktimers (AlarmKit) bijhouden, en de knoppen van de Live Activity laten werken.
        TimerService.gedeeld.begin()
        TimerService.gedeeld.naAfloop = { timer in
            // Zonder AlarmKit (geen toestemming) zegt Knipsel het zelf; anders gaat het alarm af.
            guard timer.isLokaal else { return }
            ActieveKookSessie.gedeeld.voorlezer?.spreek(Timerzinnen.afgelopen(timer))
        }
        KookActivityBediening.uitvoeren = { actie in
            let opdracht: KookOpdracht =
                switch actie {
                case .vorige: .vorige
                case .herhaal: .herhaal
                case .volgende: .volgende
                }
            _ = KookOpdrachtUitvoerder.voerUit(opdracht)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, opslag.context)
                .environment(InleesInbox.gedeeld)
        }
    }
}
