import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

/// De widget-extensie van Knipsel (fase 7): alleen Live Activities, geen widgets op het beginscherm.
/// - De kookmodus: stap, timer en knoppen op het vergrendelscherm en in het Dynamic Island.
/// - Elke kooktimer (AlarmKit): het aftellen met pauze en stop. Zonder deze configuratie toont
///   AlarmKit het aftellen niet op het vergrendelscherm.
@main
struct KnipselWidgets: WidgetBundle {
    var body: some Widget {
        KookActivityWidget()
        KookTimerWidget()
    }
}

struct KookActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: KookActivityAttributes.self) { context in
            KookActivityVergrendelscherm(
                titel: context.attributes.titel, symbool: context.attributes.symbool, staat: context.state
            )
            .activityBackgroundTint(Activitykleuren.papier)
            .activitySystemActionForegroundColor(Activitykleuren.inkt)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    KookEiland.UitgebreidLinks(symbool: context.attributes.symbool, staat: context.state)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    KookEiland.UitgebreidRechts(staat: context.state)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    KookEiland.UitgebreidOnder(titel: context.attributes.titel, staat: context.state)
                }
            } compactLeading: {
                KookEiland.CompactLinks(symbool: context.attributes.symbool, staat: context.state)
            } compactTrailing: {
                KookEiland.CompactRechts(staat: context.state)
            } minimal: {
                KookEiland.Minimaal(staat: context.state)
            }
            .keylineTint(Activitykleuren.tomaat)
        }
    }
}

struct KookTimerWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<KookTimerMetadata>.self) { context in
            TimerActivityWeergave(
                alarmID: context.state.alarmID, metadata: context.attributes.metadata, modus: context.state.mode
            )
            .activityBackgroundTint(Activitykleuren.papier)
            .activitySystemActionForegroundColor(Activitykleuren.inkt)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    TimerEiland.CompactLinks(metadata: context.attributes.metadata)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimerAftellen(modus: context.state.mode)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Activitykleuren.tomaat)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.attributes.metadata?.naam ?? "Kooktimer")
                            .font(.system(.subheadline, design: .serif))
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        TimerKnoppen(alarmID: context.state.alarmID, modus: context.state.mode)
                    }
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(Activitykleuren.tomaat)
            } compactTrailing: {
                TimerEiland.CompactRechts(modus: context.state.mode)
            } minimal: {
                Image(systemName: "timer")
                    .foregroundStyle(Activitykleuren.tomaat)
            }
            .keylineTint(Activitykleuren.tomaat)
        }
    }
}
