import AppIntents

/// De zinnen voor Siri (Nederlands; vertaald in `AppShortcuts.xcstrings`). Elke zin bevat de appnaam,
/// anders herkent Siri hem niet. Verschijnen vanzelf in Opdrachten en Spotlight.
struct KnipselOpdrachten: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: KookReceptIntent(),
            phrases: [
                "Kook \(\.$recept) met \(.applicationName)",
                "Kook met \(.applicationName)",
                "Koken met \(.applicationName)",
            ],
            shortTitle: "Kook een recept", systemImageName: "frying.pan")
        AppShortcut(
            intent: VolgendeStapIntent(),
            phrases: [
                "Volgende stap in \(.applicationName)",
                "Volgende stap \(.applicationName)",
                "Verder in \(.applicationName)",
            ],
            shortTitle: "Volgende stap", systemImageName: "forward.fill")
        AppShortcut(
            intent: VorigeStapIntent(),
            phrases: [
                "Vorige stap in \(.applicationName)",
                "Vorige stap \(.applicationName)",
                "Terug in \(.applicationName)",
            ],
            shortTitle: "Vorige stap", systemImageName: "backward.fill")
        AppShortcut(
            intent: HerhaalStapIntent(),
            phrases: [
                "Herhaal de stap in \(.applicationName)",
                "Herhaal in \(.applicationName)",
                "Herhaal stap \(.applicationName)",
            ],
            shortTitle: "Herhaal de stap", systemImageName: "arrow.counterclockwise")
        AppShortcut(
            intent: LeesIngredientenIntent(),
            phrases: [
                "Wat heb ik nodig in \(.applicationName)",
                "Wat heb ik nodig \(.applicationName)",
                "Ingrediënten in \(.applicationName)",
            ],
            shortTitle: "Wat heb ik nodig?", systemImageName: "list.bullet")
        AppShortcut(
            intent: ZetTimerIntent(),
            phrases: [
                "Zet een timer in \(.applicationName)",
                "Zet de timer in \(.applicationName)",
                "Timer in \(.applicationName)",
            ],
            shortTitle: "Zet een timer", systemImageName: "timer")
        AppShortcut(
            intent: HoeLangNogIntent(),
            phrases: [
                "Hoe lang nog in \(.applicationName)",
                "Hoe lang nog \(.applicationName)",
                "Hoelang nog in \(.applicationName)",
            ],
            shortTitle: "Hoe lang nog?", systemImageName: "hourglass")
        AppShortcut(
            intent: BoodschappenlijstIntent(),
            phrases: [
                "Wat staat er op mijn boodschappenlijst in \(.applicationName)",
                "Boodschappenlijst in \(.applicationName)",
                "Wat moet ik kopen in \(.applicationName)",
            ],
            shortTitle: "Boodschappenlijst", systemImageName: "cart")
        AppShortcut(
            intent: VandaagIntent(),
            phrases: [
                "Wat eten we vandaag in \(.applicationName)",
                "Wat eten we vandaag \(.applicationName)",
                "Wat staat er vandaag op het menu in \(.applicationName)",
            ],
            shortTitle: "Wat eten we vandaag?", systemImageName: "calendar")
    }

    static let shortcutTileColor: ShortcutTileColor = .orange
}
