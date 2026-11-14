import CoreData
import SwiftUI

/// Hoe de iPhone-bibliotheek recepten toont (Instellingen › Weergave). Standaard kaarten.
enum BibliotheekWeergave: String, CaseIterable, Identifiable, Sendable {
    case kaarten
    case lijst

    var id: String { rawValue }

    var titel: String {
        switch self {
        case .kaarten: return "Kaarten"
        case .lijst: return "Lijst"
        }
    }
}

/// Eén receptkaart (U1): kleur en symbool van de eerste categorie, titel in serif (max. 3 regels),
/// daaronder de tijd en hoe vaak je het kookte.
struct ReceptKaart: View {
    @ObservedObject var recept: Recept
    @ScaledMetric(relativeTo: .headline) private var minHoogte: CGFloat = 168
    @ScaledMetric(relativeTo: .title2) private var symboolMaat: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: recept.kaartSymbool)
                .font(.system(size: symboolMaat, weight: .regular))
                .foregroundStyle(Kaartkleuren.titel.kleur.opacity(0.85))
                .accessibilityHidden(true)
            Spacer(minLength: 4)
            Text(recept.titelOfStandaard)
                .font(.system(.headline, design: .serif).weight(.bold))
                .foregroundStyle(Kaartkleuren.titel.kleur)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            if let onderregel {
                Text(onderregel)
                    .font(.footnote)
                    .foregroundStyle(Kaartkleuren.ondertekst.kleur)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: minHoogte, alignment: .topLeading)
        .background(recept.kaartkleur.kleur, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(recept.titelOfStandaard)
        .accessibilityValue(toegankelijkeOmschrijving)
    }

    private var onderregel: String? {
        let delen = [
            Weergave.tijd(minuten: recept.weergaveMinuten),
            recept.aantalKeerGekookt > 0 ? "\(recept.aantalKeerGekookt)× gekookt" : nil,
        ].compactMap { $0 }
        return delen.isEmpty ? nil : delen.joined(separator: " · ")
    }

    private var toegankelijkeOmschrijving: String {
        [recept.kaartCategorie?.naamOfStandaard, onderregel].compactMap { $0 }.joined(separator: ", ")
    }
}

/// Het categoriesymbool op de kaartkleur, voor de lijstweergave (iPhone en iPad).
struct CategorieIcoon: View {
    @ObservedObject var recept: Recept
    @ScaledMetric(relativeTo: .body) private var maat: CGFloat = 44

    var body: some View {
        RoundedRectangle(cornerRadius: maat * 0.24, style: .continuous)
            .fill(recept.kaartkleur.kleur)
            .frame(width: maat, height: maat)
            .overlay {
                Image(systemName: recept.kaartSymbool)
                    .font(.system(size: maat * 0.44, weight: .medium))
                    .foregroundStyle(Kaartkleuren.titel.kleur.opacity(0.85))
            }
            .accessibilityHidden(true)
    }
}

/// Zwevende knop onderin (U2): het recept knippen, onder de duim. Tomaat met witte, vette tekst
/// zoals "Kook dit" (grote tekst: ≥ 3:1).
struct KnipKnop: View {
    let actie: () -> Void
    @ScaledMetric(relativeTo: .headline) private var hoogte: CGFloat = 54

    var body: some View {
        Button(action: actie) {
            SwiftUI.Label("Knip", systemImage: "scissors")
                .font(.headline.weight(.bold))
                .lineLimit(1)
                .padding(.horizontal, 22)
                .frame(minHeight: max(52, hoogte))
                .background(Kookkleuren.accent, in: Capsule())
                .foregroundStyle(.white)
                .contentShape(Capsule())
                .shadow(color: Kookkleuren.accent.opacity(0.35), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Knip recept")
        .accessibilityHint("Scan een pagina of kies een foto van een recept")
    }
}

/// Labels aan/uit (achter de chip "Filter"), combineerbaar met de categorie; zoals de tweede
/// chiprij van voorheen.
struct LabelFilter: View {
    @Binding var labels: Set<NSManagedObjectID>
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(
            key: "naam", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
    ])
    private var alleLabels: FetchedResults<ReceptLabel>

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(alleLabels, id: \.objectID) { label in
                        let gekozen = labels.contains(label.objectID)
                        Button {
                            if gekozen {
                                labels.remove(label.objectID)
                            } else {
                                labels.insert(label.objectID)
                            }
                        } label: {
                            HStack {
                                Image(systemName: gekozen ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(gekozen ? Color.accentColor : .secondary)
                                    .font(.title3)
                                Text(label.naamOfStandaard)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(label.aantalRecepten, format: .number)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(gekozen ? .isSelected : [])
                    }
                } footer: {
                    Text("Kies je meer labels, dan zie je recepten met al die labels.")
                }
            }
            .navigationTitle("Labels")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Wis") { labels.removeAll() }
                        .disabled(labels.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klaar") { dismiss() }
                }
            }
        }
    }
}
