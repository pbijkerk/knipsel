import ActivityKit
import AlarmKit
import Foundation
import OSLog
import SwiftUI

/// De echte alarmklok: AlarmKit (iOS 26). Een countdown-alarm per timer, met de naam van recept en
/// stap als titel, pauze/verder tijdens het aftellen en "Nog 1 min" als hij afgaat. Het alarm gaat
/// ook af als het scherm op slot zit of het toestel op stil staat. De Live Activity met het aftellen
/// komt uit de widget-extensie (`KookTimerWidget`).
@MainActor
final class AlarmKitWekker: Wekker {
    /// "Nog 1 min" na het alarm.
    nonisolated static let nogEenMinuut: TimeInterval = 60

    private let log = Logger(subsystem: "com.peterbijkerk.knipsel", category: "alarmkit")

    private var beheer: AlarmManager { AlarmManager.shared }

    func vraagToestemming() async -> Bool {
        switch beheer.authorizationState {
        case .authorized: return true
        case .denied: return false
        case .notDetermined:
            do {
                return try await Self.vraag()
            } catch {
                log.error("Toestemming voor alarmen mislukt: \(error.localizedDescription, privacy: .public)")
                return false
            }
        @unknown default:
            return false
        }
    }

    func plan(_ timer: KookTimer) async throws {
        try await Self.plan(timer)
    }

    // AlarmManager en de configuratie zijn niet Sendable: de async aanroepen gebeuren buiten de main
    // actor, met alleen Sendable invoer (de `KookTimer`).
    private nonisolated static func vraag() async throws -> Bool {
        try await AlarmManager.shared.requestAuthorization() == .authorized
    }

    private nonisolated static func plan(_ timer: KookTimer) async throws {
        do {
            _ = try await AlarmManager.shared.schedule(id: timer.id, configuration: configuratie(voor: timer))
        } catch AlarmManager.AlarmError.maximumLimitReached {
            throw TimerFout.teVeel
        }
    }

    func pauzeer(_ id: UUID) throws { try beheer.pause(id: id) }
    func hervat(_ id: UUID) throws { try beheer.resume(id: id) }
    func annuleer(_ id: UUID) throws { try beheer.cancel(id: id) }
    func stop(_ id: UUID) throws { try beheer.stop(id: id) }

    func huidige() -> [WekkerStand] {
        ((try? beheer.alarms) ?? []).map(Self.stand)
    }

    func wijzigingen() -> AsyncStream<[WekkerStand]> {
        let updates = beheer.alarmUpdates
        return AsyncStream { vervolg in
            let taak = Task { @MainActor in
                for await alarms in updates {
                    vervolg.yield(alarms.map(Self.stand))
                }
                vervolg.finish()
            }
            vervolg.onTermination = { _ in taak.cancel() }
        }
    }

    nonisolated static func stand(_ alarm: Alarm) -> WekkerStand {
        let toestand: WekkerStand.Toestand =
            switch alarm.state {
            case .scheduled: .gepland
            case .countdown: .loopt
            case .paused: .gepauzeerd
            case .alerting: .gaatAf
            @unknown default: .loopt
            }
        return WekkerStand(id: alarm.id, toestand: toestand)
    }

    // MARK: - Configuratie

    nonisolated static func configuratie(voor timer: KookTimer) -> AlarmManager.AlarmConfiguration<KookTimerMetadata> {
        let nogKnop = AlarmButton(text: "Nog 1 min", textColor: .white, systemImageName: "goforward.60")
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(
                title: "\(timer.titel)", secondaryButton: nogKnop, secondaryButtonBehavior: .countdown)
        } else {
            alert = AlarmPresentation.Alert(
                title: "\(timer.titel)",
                stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill"),
                secondaryButton: nogKnop, secondaryButtonBehavior: .countdown)
        }
        let presentatie = AlarmPresentation(
            alert: alert,
            countdown: AlarmPresentation.Countdown(
                title: "\(timer.naam)",
                pauseButton: AlarmButton(text: "Pauze", textColor: .white, systemImageName: "pause.fill")),
            paused: AlarmPresentation.Paused(
                title: "Gepauzeerd",
                resumeButton: AlarmButton(text: "Verder", textColor: .white, systemImageName: "play.fill")))
        let attributen = AlarmAttributes(
            presentation: presentatie,
            metadata: KookTimerMetadata(recept: timer.recept, naam: timer.naam, kort: timer.kort),
            tintColor: Activitykleuren.tomaat)
        return AlarmManager.AlarmConfiguration(
            countdownDuration: Alarm.CountdownDuration(
                preAlert: TimeInterval(timer.totaal), postAlert: Self.nogEenMinuut),
            attributes: attributen,
            stopIntent: StopTimerIntent(alarmID: timer.id),
            secondaryIntent: NogEenMinuutIntent(alarmID: timer.id))
    }
}
