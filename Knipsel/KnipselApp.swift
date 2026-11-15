import SwiftUI

@main
struct KnipselApp: App {
    private let opslag = Opslag.gedeeld

    init() {
        opslag.richIn()
        // Recepten vindbaar in Spotlight en voor Siri ("Kook … met Knipsel").
        ReceptIndex.gedeeld.start(opslag: opslag)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, opslag.context)
                .environment(InleesInbox.gedeeld)
        }
    }
}
