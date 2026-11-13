import SwiftUI

/// De bibliotheek: op iPhone een lijst met chips, op iPad (brede breedte) drie kolommen.
struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var breedte

    var body: some View {
        if breedte == .compact {
            BibliotheekCompact()
        } else {
            BibliotheekSplit()
        }
    }

    static var versie: String {
        let info = Bundle.main.infoDictionary
        let versie = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(versie) (\(build))"
    }
}

#if DEBUG
    #Preview {
        ContentView()
            .environment(\.managedObjectContext, Opslag.voorbeeld.context)
    }
#endif
