import SwiftUI

// De timers in de kookmodus (fase 7, K11): een knop per tijd in de stap, lopende timers als chips
// boven de knoppen onderin, en de timervraag als banner na het voorlezen.

/// "⏱ Timer 20 min" bij een tijd in de stap; bij een bereik staat het bereik erachter ("10–15 min").
/// Loopt er al een timer voor deze tijd, dan "Timer loopt".
struct TimerKnop: View {
    let tijd: Tijdvermelding
    var loopt = false
    let actie: () -> Void

    var body: some View {
        Button(action: actie) {
            HStack(spacing: 8) {
                Image(systemName: loopt ? "checkmark.circle.fill" : "timer")
                    .font(.title3.weight(.bold))
                Text(loopt ? "\(Tijdweergave.kort(tijd.seconden)) loopt" : "Timer \(Tijdweergave.kort(tijd.seconden))")
                    .font(.title3.weight(.semibold))
                if tijd.isBereik {
                    Text("· \(tijd.label)")
                        .font(.subheadline.weight(.semibold))
                        .opacity(0.85)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 18)
            .frame(minHeight: 52)
            .background(loopt ? Kookkleuren.kaart : Kookkleuren.accent, in: Capsule())
            .foregroundStyle(loopt ? Kookkleuren.markering : Color.white)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(loopt ? "Timer van \(tijd.label) loopt" : "Zet een timer van \(tijd.label)")
        .accessibilityHint(tijd.isBereik ? "De timer staat op de langste tijd" : "")
    }
}

/// Lopende timers als chips: "⏱ Stap 3 · 18:42". Tik = pauzeren, verder of stoppen.
struct TimerChips: View {
    let timers: [KookTimer]
    var pauzeer: (UUID) -> Void = { _ in }
    var hervat: (UUID) -> Void = { _ in }
    var stop: (UUID) -> Void = { _ in }
    /// Voor renders: een vaste tijd in plaats van de klok.
    var nu: Date?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(timers) { timer in
                    Menu {
                        if timer.gaatAf {
                            Button("Stop alarm", systemImage: "bell.slash") { stop(timer.id) }
                        } else if timer.isGepauzeerd {
                            Button("Verder", systemImage: "play.fill") { hervat(timer.id) }
                            Button("Stop timer", systemImage: "xmark", role: .destructive) { stop(timer.id) }
                        } else {
                            Button("Pauzeer", systemImage: "pause.fill") { pauzeer(timer.id) }
                            Button("Stop timer", systemImage: "xmark", role: .destructive) { stop(timer.id) }
                        }
                    } label: {
                        TimerChip(timer: timer, nu: nu)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }
}

struct TimerChip: View {
    let timer: KookTimer
    var nu: Date?

    var body: some View {
        if let nu {
            inhoud(op: nu)
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                inhoud(op: context.date)
            }
        }
    }

    private func inhoud(op datum: Date) -> some View {
        let symbool =
            timer.gaatAf ? "bell.and.waves.left.and.right.fill" : (timer.isGepauzeerd ? "pause.fill" : "timer")
        let tijd = timer.gaatAf ? "Klaar" : Tijdweergave.klok(timer.resterend(op: datum))
        return HStack(spacing: 8) {
            Image(systemName: symbool)
                .font(.headline)
                .foregroundStyle(timer.gaatAf ? Color.white : Kookkleuren.markering)
            Text(timer.kort)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(timer.gaatAf ? Color.white : Kookkleuren.gedimd)
            Text(tijd)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(timer.gaatAf ? Color.white : Kookkleuren.tekst)
                .opacity(timer.isGepauzeerd ? 0.6 : 1)
        }
        .lineLimit(1)
        .padding(.horizontal, 16)
        .frame(minHeight: 48)
        .background(timer.gaatAf ? Kookkleuren.accent : Kookkleuren.kaart, in: Capsule())
        .overlay(Capsule().strokeBorder(Kookkleuren.accent.opacity(timer.gaatAf ? 0 : 0.5), lineWidth: 1.5))
        .contentShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Timer \(timer.naam)")
        .accessibilityValue(
            timer.gaatAf
                ? "klaar"
                : (timer.isGepauzeerd ? "gepauzeerd, " : "")
                    + "nog \(Tijdweergave.resterendGesproken(timer.resterend(op: datum)))"
        )
        .accessibilityHint("Tik om te pauzeren of te stoppen")
    }
}

/// Na het voorlezen: "Zal ik een timer van 20 minuten zetten?" met Ja en Nee. Zeggen kan ook.
struct TimervraagBanner: View {
    let vraag: Timervraag
    var luistert = false
    let ja: () -> Void
    let nee: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "timer")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Kookkleuren.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Timer van \(Tijdweergave.gesproken(vraag.seconden)) zetten?")
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if luistert {
                        Text("Zeg ‘ja’ of ‘nee’")
                            .font(.subheadline)
                            .foregroundStyle(Kookkleuren.gedimd)
                    }
                }
            }
            HStack(spacing: 10) {
                Button(action: ja) {
                    SwiftUI.Label("Ja, zet timer", systemImage: "checkmark")
                        .font(.headline)
                        .padding(.horizontal, 18)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Kookkleuren.accent, in: Capsule())
                        .foregroundStyle(Color.white)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                Button(action: nee) {
                    Text("Nee")
                        .font(.headline)
                        .padding(.horizontal, 22)
                        .frame(minHeight: 48)
                        .background(Kookkleuren.balkLeeg, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: 520, alignment: .leading)
        .background(Kookkleuren.kaart, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Kookkleuren.accent, lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .accessibilityElement(children: .contain)
    }
}
