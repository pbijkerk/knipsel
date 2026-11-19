import SwiftUI

@main
struct KnipselApp: App {
    /// Alleen voor het accepteren van een uitnodiging voor Thuis (`KnipselSceneDelegate`).
    @UIApplicationDelegateAdaptor(KnipselAppDelegate.self) private var appDelegate
    private let opslag = Opslag.gedeeld

    init() {
        // Ging de opslag niet open, dan toont de app het herstelscherm en start dit pas na een
        // geslaagde "Probeer opnieuw" (audit v0.1, #1).
        if opslag.isGeopend { Self.startMetOpslag(opslag) }
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
            Startscherm(opslag: opslag)
        }
    }

    /// Wat de app doet zodra de privéstore open is: bij het starten, of na "Probeer opnieuw".
    static func startMetOpslag(_ opslag: Opslag) {
        opslag.richIn()
        #if DEBUG
            // Alleen Debug (Development-omgeving): het CloudKit-schema één keer per modelversie
            // klaarzetten, zodat Deploy Schema Changes daarna alle recordtypes en velden ziet.
            CloudKitSchema.gedeeld.startVanzelf()
        #endif
        // "Verder met…" van vóór fase 8 wees naar het objectID; nu naar de uuid van het recept.
        KookVoortgang().migreer(in: opslag.context)
        // Recepten vindbaar in Spotlight en voor Siri ("Kook … met Knipsel").
        ReceptIndex.gedeeld.start(opslag: opslag)
        // Nieuwe Thuis-recepten in de share van Thuis zetten (fase 8).
        ThuisDelen.gedeeld.start()
    }
}

/// De bibliotheek, of het herstelscherm als de opslag niet openging.
struct Startscherm: View {
    let opslag: Opslag
    @State private var geopend: Bool

    init(opslag: Opslag) {
        self.opslag = opslag
        _geopend = State(initialValue: opslag.isGeopend)
    }

    var body: some View {
        if geopend {
            ContentView()
                .environment(\.managedObjectContext, opslag.context)
                .environment(InleesInbox.gedeeld)
        } else {
            HerstelScherm(opslag: opslag) {
                KnipselApp.startMetOpslag(opslag)
                geopend = true
            }
        }
    }
}
