import AppIntents
import Foundation

// Siri en Opdrachten voor timers (fase 7, K11): "Zet een timer in Knipsel" en "Hoe lang nog in
// Knipsel". Zinnen in `KnipselOpdrachten` en `AppShortcuts.xcstrings`.

/// "Zet een timer in Knipsel": zonder minuten de tijd van de huidige stap in de kookmodus.
struct ZetTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Zet een timer"
    static let description = IntentDescription(
        "Zet een kooktimer met alarm. Zonder minuten de tijd uit de stap waar je in de kookmodus bent.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Minuten", inclusiveRange: (1, 1440))
    var minuten: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("Zet een timer van \(\.$minuten) minuten")
    }

    init() {}

    init(minuten: Int?) {
        self.minuten = minuten
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch await TimerOpdrachtUitvoerder.zet(minuten: minuten) {
        case .gezet(let zin), .mislukt(let zin):
            return .result(dialog: "\(zin)")
        case .geenTijd:
            throw $minuten.needsValueError("Hoeveel minuten?")
        }
    }
}

/// "Hoe lang nog in Knipsel": de resterende tijd van elke lopende timer.
struct HoeLangNogIntent: AppIntent {
    static let title: LocalizedStringResource = "Hoe lang nog"
    static let description = IntentDescription("Zegt hoe lang de kooktimers van Knipsel nog lopen.")
    static let supportedModes: IntentModes = .background

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: "\(TimerOpdrachtUitvoerder.hoeLangNog())")
    }
}

/// Wat de timer-opdrachten doen, los van Siri zodat het te testen is met een nep-alarmklok.
@MainActor
enum TimerOpdrachtUitvoerder {
    enum Uitkomst: Equatable {
        case gezet(String)
        /// Geen minuten genoemd en de stap noemt geen tijd (of er is geen kookmodus): Siri vraagt erom.
        case geenTijd
        case mislukt(String)
    }

    static let mislukt = "Het lukte niet om de timer te zetten. Mag Knipsel alarmen gebruiken (Instellingen)?"

    static func zet(
        minuten: Int?, houder: ActieveKookSessie = .gedeeld, timers: TimerService = .gedeeld
    ) async -> Uitkomst {
        let sessie = houder.sessie
        let stap = sessie.flatMap { $0.isAfgerond ? nil : $0.huidigeStap }
        let seconden: Int
        let tijd: Tijdvermelding?
        if let minuten, minuten > 0 {
            seconden = minuten * 60
            tijd = stap?.tijden.first { $0.seconden == seconden }
        } else if let stap, stap.hoofdtijdSeconden > 0 {
            seconden = stap.hoofdtijdSeconden
            tijd = stap.hoofdtijd
        } else {
            return .geenTijd
        }
        // Een losse tijd ("timer 5 minuten") hoort niet bij de stap, tenzij de stap hem noemt.
        let bijStap = tijd == nil ? nil : stap
        guard
            let timer = await KookTimers.start(
                seconden: seconden, stap: bijStap, tijd: tijd, in: sessie, timers: timers)
        else { return .mislukt(mislukt) }
        houder.voorlezer?.sluitTimervraag()
        return .gezet(Timerzinnen.gezet(timer))
    }

    static func hoeLangNog(timers: TimerService = .gedeeld, nu: Date = .now) -> String {
        Timerzinnen.hoeLangNog(timers.timers, nu: nu)
    }
}
