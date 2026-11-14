import SwiftUI

/// Uitleg vóór de toestemmingsvraag (eerste keer in de kookmodus): wat Knipsel met de microfoon doet.
struct Spraakuitleg: View {
    var doorgaan: () -> Void
    var nietNu: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Kookkleuren.accent)
                    .accessibilityHidden(true)
                Text("Kook zonder het scherm aan te raken")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(
                    "Zeg \"volgende\", \"herhaal\", \"stop\" of \"hoeveel boter?\". Knipsel luistert alleen zolang de kookmodus open is, en alles blijft op dit toestel: er gaat geen geluid naar internet."
                )
                .fixedSize(horizontal: false, vertical: true)
                Text("Zo meteen vraagt iOS om toestemming voor de microfoon en voor spraakherkenning.")
                    .font(.subheadline)
                    .foregroundStyle(Kookkleuren.gedimd)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 10) {
                    Button(action: doorgaan) {
                        Text("Doorgaan")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(Kookkleuren.accent, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    Button(action: nietNu) {
                        Text("Niet nu")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(Kookkleuren.gedimd)
                    }
                    .accessibilityHint("Zet spraakbediening uit; met de microfoonknop bovenin zet je hem weer aan")
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(24)
            .foregroundStyle(Kookkleuren.tekst)
            .background(Kookkleuren.achtergrond, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Kookkleuren.balkLeeg, lineWidth: 1))
            .frame(maxWidth: 460)
            .padding(24)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

/// Het antwoord op "hoeveel …?": groot de geschaalde hoeveelheid, of dat het niet in het recept staat.
struct Antwoordkaart: View {
    let antwoord: Spraakbediening.Antwoord
    var lettertype: Lettertype = .serif
    var sluit: () -> Void = {}

    var body: some View {
        Button(action: sluit) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: antwoord.gevonden ? "scalemass.fill" : "questionmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(antwoord.gevonden ? Kookkleuren.markering : Kookkleuren.gedimd)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(antwoord.titel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Kookkleuren.gedimd)
                    Text(antwoord.tekst)
                        .font(.system(.title2, design: lettertype.ontwerp).weight(.semibold))
                        .foregroundStyle(antwoord.gevonden ? Kookkleuren.markering : Kookkleuren.tekst)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Kookkleuren.gedimd)
                    .accessibilityHidden(true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Kookkleuren.kaart, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Kookkleuren.balkLeeg, lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(antwoord.titel): \(antwoord.tekst)")
        .accessibilityHint("Tik om te sluiten")
    }
}
