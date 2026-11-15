import AlarmKit
import AppIntents
import Foundation

// Knoppen in de Live Activities (fase 7). Een `LiveActivityIntent` draait altijd in het proces van de
// app, ook als hij in de widget-extensie getikt wordt; daarom staan ze in beide targets. Ze staan niet
// in Opdrachten (`isDiscoverable = false`): daar zijn de Siri-opdrachten van fase 6 voor.

/// Wat de knoppen in de Live Activity van de kookmodus kunnen.
enum KookActivityActie: String, Sendable {
    case vorige
    case herhaal
    case volgende
}

/// De app zet hier bij het starten de uitvoering neer (`KookOpdrachtUitvoerder`); in de extensie zelf
/// blijft hij leeg.
@MainActor
enum KookActivityBediening {
    static var uitvoeren: ((KookActivityActie) -> Void)?
}

struct VorigeStapKnopIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Vorige stap"
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        KookActivityBediening.uitvoeren?(.vorige)
        return .result()
    }
}

struct HerhaalStapKnopIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Herhaal de stap"
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        KookActivityBediening.uitvoeren?(.herhaal)
        return .result()
    }
}

struct VolgendeStapKnopIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Volgende stap"
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        KookActivityBediening.uitvoeren?(.volgende)
        return .result()
    }
}

// MARK: - Timers (AlarmKit)

/// Pauzeert een kooktimer vanaf het vergrendelscherm of het Dynamic Island.
struct PauzeerTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pauzeer timer"
    static let isDiscoverable = false

    @Parameter(title: "Timer")
    var alarmID: String

    init() {}

    init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { try AlarmManager.shared.pause(id: id) }
        return .result()
    }
}

struct HervatTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Hervat timer"
    static let isDiscoverable = false

    @Parameter(title: "Timer")
    var alarmID: String

    init() {}

    init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { try AlarmManager.shared.resume(id: id) }
        return .result()
    }
}

/// Stopt een afgaand alarm, of haalt een lopende timer weg.
struct StopTimerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop timer"
    static let isDiscoverable = false

    @Parameter(title: "Timer")
    var alarmID: String

    init() {}

    init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) {
            try? AlarmManager.shared.stop(id: id)
            try? AlarmManager.shared.cancel(id: id)
        }
        return .result()
    }
}

/// "Nog 1 min" bij een afgaand alarm: telt de `postAlert`-tijd (60 s) opnieuw af.
struct NogEenMinuutIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Nog 1 minuut"
    static let isDiscoverable = false

    @Parameter(title: "Timer")
    var alarmID: String

    init() {}

    init(alarmID: UUID) {
        self.alarmID = alarmID.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: alarmID) { try AlarmManager.shared.countdown(id: id) }
        return .result()
    }
}
