import ActivityKit
import Foundation
import OSLog

/// De inhoud van de Live Activity van de kookmodus, puur opgebouwd uit de kookbeurt en de timers.
enum KookActivityInhoud {
    /// Zoveel tekens van de stap passen op het vergrendelscherm (twee regels).
    static let maximaleTekst = 110

    @MainActor
    static func staat(van sessie: KookSessie, timers: [KookTimer], nu: Date) -> KookActivityAttributes.ContentState {
        staat(
            stapNummer: sessie.stapNummer, aantalStappen: sessie.aantalStappen,
            stapTekst: sessie.huidigeStap?.tekst ?? "", isAfgerond: sessie.isAfgerond, timers: timers, nu: nu)
    }

    static func staat(
        stapNummer: Int, aantalStappen: Int, stapTekst: String, isAfgerond: Bool, timers: [KookTimer], nu: Date
    ) -> KookActivityAttributes.ContentState {
        KookActivityAttributes.ContentState(
            stapNummer: stapNummer, aantalStappen: aantalStappen, stapTekst: ingekort(stapTekst),
            isAfgerond: isAfgerond, timer: eerstvolgende(timers, nu: nu), aantalTimers: timers.count)
    }

    /// De timer die er het meest toe doet: een afgaand alarm, anders de eerste die afloopt, anders
    /// een gepauzeerde.
    static func eerstvolgende(_ timers: [KookTimer], nu: Date) -> KookActivityAttributes.Timerstand? {
        guard let timer = TimerService.gesorteerd(timers).first else { return nil }
        if timer.gaatAf { return .init(naam: timer.kort, gaatAf: true) }
        if let eindigtOp = timer.eindigtOp {
            return .init(naam: timer.kort, einde: eindigtOp, begin: min(nu, eindigtOp))
        }
        return .init(naam: timer.kort, resterend: timer.resterendBijPauze ?? 0)
    }

    /// Op een woordgrens ingekort, met "…".
    static func ingekort(_ tekst: String, tot lengte: Int = maximaleTekst) -> String {
        let schoon = tekst.trimmingCharacters(in: .whitespacesAndNewlines)
        guard schoon.count > lengte else { return schoon }
        var kort = ""
        for woord in schoon.split(separator: " ") {
            if kort.count + woord.count + 1 > lengte - 1 { break }
            kort += kort.isEmpty ? String(woord) : " " + woord
        }
        return kort + "…"
    }
}

/// Start, werkt bij en stopt een Live Activity; in de app ActivityKit, in tests een nep.
@MainActor
protocol KookActivityMotor: AnyObject {
    func start(_ attributen: KookActivityAttributes, staat: KookActivityAttributes.ContentState)
    func werkBij(_ staat: KookActivityAttributes.ContentState)
    func stop()
}

/// De Live Activity zolang de kookmodus open is: op het vergrendelscherm (alle toestellen) en in het
/// Dynamic Island (iPhone 15 Plus). Werkt alleen bij als de inhoud verandert; stopt bij sluiten en
/// bij "Gekookt".
@MainActor
final class KookActivityBeheer {
    static let gedeeld = KookActivityBeheer(motor: ActivityKitMotor())

    private let motor: any KookActivityMotor
    private(set) var laatste: KookActivityAttributes.ContentState?
    private(set) weak var sessie: KookSessie?

    init(motor: any KookActivityMotor) {
        self.motor = motor
    }

    var isActief: Bool { laatste != nil }

    func start(_ sessie: KookSessie, timers: [KookTimer], nu: Date = .now) {
        stop()
        self.sessie = sessie
        let staat = KookActivityInhoud.staat(van: sessie, timers: timers, nu: nu)
        motor.start(KookActivityAttributes(titel: sessie.titel, symbool: sessie.symbool), staat: staat)
        laatste = staat
    }

    /// Na een stapwissel of timerwijziging; alleen voor de sessie die hem startte.
    func werkBij(_ sessie: KookSessie, timers: [KookTimer], nu: Date = .now) {
        guard isActief, self.sessie === sessie else { return }
        let staat = KookActivityInhoud.staat(van: sessie, timers: timers, nu: nu)
        guard !Self.gelijk(staat, laatste) else { return }
        motor.werkBij(staat)
        laatste = staat
    }

    func stop(_ sessie: KookSessie) {
        guard self.sessie === sessie else { return }
        stop()
    }

    private func stop() {
        guard isActief else { return }
        motor.stop()
        laatste = nil
        sessie = nil
    }

    /// Gelijk zonder te kijken naar het beginmoment van het aftellen (dat schuift elke keer op).
    private static func gelijk(_ a: KookActivityAttributes.ContentState, _ b: KookActivityAttributes.ContentState?)
        -> Bool
    {
        guard var b else { return false }
        var a = a
        a.timer?.begin = nil
        b.timer?.begin = nil
        return a == b
    }
}

/// ActivityKit: één `Activity<KookActivityAttributes>` tegelijk, zonder pushmeldingen. Bijwerken en
/// stoppen zoeken de activity op zijn id op, zodat er geen (niet-Sendable) `Activity` tussen threads
/// gaat.
@MainActor
final class ActivityKitMotor: KookActivityMotor {
    private var activityID: String?
    private let log = Logger(subsystem: "com.peterbijkerk.knipsel", category: "liveactivity")

    func start(_ attributen: KookActivityAttributes, staat: KookActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // Een achtergebleven activity van een eerdere kookbeurt (app gestopt) eerst opruimen.
        Task { await Self.beeindigAlle() }
        do {
            let activity = try Activity.request(attributes: attributen, content: .init(state: staat, staleDate: nil))
            activityID = activity.id
        } catch {
            log.error("Live Activity starten mislukt: \(error.localizedDescription, privacy: .public)")
        }
    }

    func werkBij(_ staat: KookActivityAttributes.ContentState) {
        guard let activityID else { return }
        Task { await Self.werkBij(id: activityID, staat) }
    }

    func stop() {
        guard let activityID else { return }
        self.activityID = nil
        Task { await Self.beeindig(id: activityID) }
    }

    private nonisolated static func werkBij(id: String, _ staat: KookActivityAttributes.ContentState) async {
        guard let activity = Activity<KookActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.update(.init(state: staat, staleDate: nil))
    }

    private nonisolated static func beeindig(id: String) async {
        guard let activity = Activity<KookActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    private nonisolated static func beeindigAlle() async {
        for activity in Activity<KookActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
