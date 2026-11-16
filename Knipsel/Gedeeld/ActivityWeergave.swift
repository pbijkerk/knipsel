import AlarmKit
import AppIntents
import SwiftUI

// De weergaven van de Live Activities, gedeeld met de app zodat ze ook los te renderen zijn. De
// widget-extensie (KnipselWidgets) zet ze in `ActivityConfiguration` en `DynamicIsland`.

// MARK: - Kookmodus

/// De lopende timer: telt zelf af (`Text(timerInterval:)`), zonder dat de app hoeft bij te werken.
struct KookTimerTekst: View {
    let timer: KookActivityAttributes.Timerstand

    var body: some View {
        if timer.gaatAf {
            Text("Klaar")
        } else if let einde = timer.einde {
            Text(timerInterval: min(timer.begin ?? einde, einde)...einde, countsDown: true)
                .monospacedDigit()
        } else {
            Text(Tijdweergave.klok(timer.resterend ?? 0))
                .monospacedDigit()
        }
    }
}

/// Vergrendelscherm (en meldingen op iPad): stap, titel, staptekst, eerstvolgende timer en knoppen.
struct KookActivityVergrendelscherm: View {
    let titel: String
    let symbool: String
    let staat: KookActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: symbool)
                    .font(.headline)
                    .foregroundStyle(Activitykleuren.tomaat)
                    .frame(width: 32, height: 32)
                    .background(Activitykleuren.tomaat.opacity(0.18), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(staat.kop)
                        .font(.headline)
                    Text(titel)
                        .font(.subheadline)
                        .foregroundStyle(Activitykleuren.gedimd)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let timer = staat.timer {
                    KookTimerKader(timer: timer, extra: staat.aantalTimers - 1)
                }
            }
            if !staat.isAfgerond {
                Text(staat.stapTekst)
                    .font(.system(.body, design: .serif))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            KookActivityKnoppen(isAfgerond: staat.isAfgerond)
        }
        .foregroundStyle(Activitykleuren.inkt)
        .padding(16)
    }
}

/// "⏱ 18:42" in een tomaatkleurig kader, met "+1" als er meer timers lopen.
struct KookTimerKader: View {
    let timer: KookActivityAttributes.Timerstand
    var extra = 0

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            // Text(timerInterval:) neemt de volle breedte: rechts uitlijnen in een vaste breedte.
            KookTimerTekst(timer: timer)
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.trailing)
                .frame(width: 84, alignment: .trailing)
            SwiftUI.Label(
                extra > 0 ? "\(timer.naam) · +\(extra)" : timer.naam,
                systemImage: timer.gaatAf ? "bell.fill" : (timer.einde == nil ? "pause.fill" : "timer")
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(Activitykleuren.gedimd)
            .lineLimit(1)
        }
        .foregroundStyle(Activitykleuren.tomaat)
    }
}

/// Vorige / herhaal / volgende; draaien in de app (`LiveActivityIntent`).
struct KookActivityKnoppen: View {
    var isAfgerond = false

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: VorigeStapKnopIntent()) {
                SwiftUI.Label("Vorige", systemImage: "chevron.left")
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .tint(Activitykleuren.gedimd)
            Button(intent: HerhaalStapKnopIntent()) {
                SwiftUI.Label("Herhaal", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .tint(Activitykleuren.gedimd)
            .disabled(isAfgerond)
            Button(intent: VolgendeStapKnopIntent()) {
                SwiftUI.Label("Volgende", systemImage: "chevron.right")
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .tint(Activitykleuren.tomaat)
            .disabled(isAfgerond)
        }
        .buttonStyle(.borderedProminent)
        .font(.subheadline.weight(.semibold))
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

/// De delen van het Dynamic Island (alleen iPhone 15 Plus bij Peter); los zodat ze te renderen zijn.
enum KookEiland {
    struct CompactLinks: View {
        let symbool: String
        let staat: KookActivityAttributes.ContentState

        var body: some View {
            HStack(spacing: 4) {
                Image(systemName: symbool)
                    .foregroundStyle(Activitykleuren.tomaat)
                Text(staat.isAfgerond ? "Klaar" : "\(staat.stapNummer)/\(staat.aantalStappen)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
        }
    }

    struct CompactRechts: View {
        let staat: KookActivityAttributes.ContentState

        var body: some View {
            if let timer = staat.timer {
                KookTimerTekst(timer: timer)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Activitykleuren.tomaat)
                    .frame(maxWidth: 56)
            } else {
                Image(systemName: "frying.pan")
                    .foregroundStyle(Activitykleuren.tomaat)
            }
        }
    }

    struct Minimaal: View {
        let staat: KookActivityAttributes.ContentState

        var body: some View {
            if staat.timer != nil {
                Image(systemName: "timer")
                    .foregroundStyle(Activitykleuren.tomaat)
            } else {
                Text("\(staat.stapNummer)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Activitykleuren.tomaat)
            }
        }
    }

    struct UitgebreidLinks: View {
        let symbool: String
        let staat: KookActivityAttributes.ContentState

        var body: some View {
            SwiftUI.Label(staat.kop, systemImage: symbool)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Activitykleuren.inkt)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    struct UitgebreidRechts: View {
        let staat: KookActivityAttributes.ContentState

        var body: some View {
            if let timer = staat.timer {
                KookTimerKader(timer: timer, extra: staat.aantalTimers - 1)
            }
        }
    }

    struct UitgebreidOnder: View {
        let titel: String
        let staat: KookActivityAttributes.ContentState

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(staat.isAfgerond ? titel : staat.stapTekst)
                    .font(.system(.subheadline, design: .serif))
                    .foregroundStyle(Activitykleuren.inkt)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                KookActivityKnoppen(isAfgerond: staat.isAfgerond)
            }
        }
    }
}

// MARK: - Timers (AlarmKit)

/// De Live Activity van één kooktimer (AlarmKit): naam, aftellen, pauze/hervat en stop.
struct TimerActivityWeergave: View {
    let alarmID: UUID
    let metadata: KookTimerMetadata?
    let modus: AlarmPresentationState.Mode

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                SwiftUI.Label(metadata?.recept ?? "Knipsel", systemImage: "timer")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Activitykleuren.tomaat)
                    .lineLimit(1)
                Text(metadata?.naam ?? "Kooktimer")
                    .font(.system(.body, design: .serif))
                    .foregroundStyle(Activitykleuren.inkt)
                    .lineLimit(2)
                TimerAftellen(modus: modus)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(Activitykleuren.inkt)
            }
            Spacer(minLength: 4)
            TimerKnoppen(alarmID: alarmID, modus: modus)
        }
        .padding(16)
    }
}

/// "18:42" dat zelf aftelt; gepauzeerd de stilstaande tijd, afgaand "Klaar!".
struct TimerAftellen: View {
    let modus: AlarmPresentationState.Mode

    var body: some View {
        switch modus {
        case .countdown(let aftellen):
            Text(timerInterval: min(aftellen.startDate, aftellen.fireDate)...aftellen.fireDate, countsDown: true)
                .monospacedDigit()
        case .paused(let pauze):
            Text(Tijdweergave.klok(pauze.totalCountdownDuration - pauze.previouslyElapsedDuration))
                .monospacedDigit()
        case .alert:
            Text("Klaar!")
        @unknown default:
            Text("")
        }
    }
}

/// Pauze of verder, en stop; ronde knoppen van 44 pt.
struct TimerKnoppen: View {
    let alarmID: UUID
    let modus: AlarmPresentationState.Mode

    var body: some View {
        HStack(spacing: 10) {
            switch modus {
            case .countdown:
                Button(intent: PauzeerTimerIntent(alarmID: alarmID)) { rond("pause.fill") }
                    .tint(Activitykleuren.gedimd)
                    .accessibilityLabel("Pauzeer")
            case .paused:
                Button(intent: HervatTimerIntent(alarmID: alarmID)) { rond("play.fill") }
                    .tint(Activitykleuren.tomaat)
                    .accessibilityLabel("Verder")
            case .alert:
                Button(intent: NogEenMinuutIntent(alarmID: alarmID)) { rond("goforward.60") }
                    .tint(Activitykleuren.gedimd)
                    .accessibilityLabel("Nog 1 minuut")
            @unknown default:
                EmptyView()
            }
            Button(intent: StopTimerIntent(alarmID: alarmID)) { rond("xmark") }
                .tint(Activitykleuren.tomaat)
                .accessibilityLabel("Stop")
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
    }

    private func rond(_ symbool: String) -> some View {
        Image(systemName: symbool)
            .font(.title3.weight(.bold))
            .frame(width: 32, height: 32)
    }
}

/// Het Dynamic Island van een kooktimer.
enum TimerEiland {
    struct CompactRechts: View {
        let modus: AlarmPresentationState.Mode

        var body: some View {
            TimerAftellen(modus: modus)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Activitykleuren.tomaat)
                .frame(maxWidth: 56)
        }
    }

    struct CompactLinks: View {
        let metadata: KookTimerMetadata?

        var body: some View {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .foregroundStyle(Activitykleuren.tomaat)
                Text(metadata?.kort ?? "Timer")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
        }
    }
}
