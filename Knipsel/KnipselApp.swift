import SwiftUI

@main
struct KnipselApp: App {
    private let opslag = Opslag.gedeeld

    init() {
        opslag.richIn()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, opslag.context)
        }
    }
}
