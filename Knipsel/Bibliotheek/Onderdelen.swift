import SwiftUI

/// Een filterknop in de vorm van een pil. Gekozen: getinte achtergrond met inkt-kleurige tekst
/// (wit op tomaat haalt de 4,5:1 contrast niet).
struct Chip: View {
    let titel: String
    var symbool: String?
    var aantal: Int?
    let gekozen: Bool
    let actie: () -> Void

    var body: some View {
        Button(action: actie) {
            HStack(spacing: 6) {
                if let symbool {
                    Image(systemName: symbool)
                        .foregroundStyle(gekozen ? Color.accentColor : .secondary)
                }
                Text(titel)
                    .fontWeight(gekozen ? .semibold : .regular)
                if let aantal {
                    Text(aantal, format: .number)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(gekozen ? Color.accentColor.opacity(0.18) : Color(.secondarySystemFill), in: Capsule())
            .overlay {
                Capsule().strokeBorder(gekozen ? Color.accentColor : .clear, lineWidth: 1.5)
            }
            .foregroundStyle(.primary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(gekozen ? .isSelected : [])
    }
}

/// Een klein, niet-tikbaar label (categorie of label bij een recept).
struct Kenmerk: View {
    let titel: String
    var symbool: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbool { Image(systemName: symbool).foregroundStyle(Color.accentColor) }
            Text(titel)
        }
        .font(.footnote)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color(.secondarySystemFill), in: Capsule())
    }
}

/// Zet elementen naast elkaar en breekt af naar een nieuwe regel als het niet past (chips bij een
/// recept, ook bij de grootste tekstgroottes).
struct Stroomopmaak: Layout {
    var ruimte: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let breedte = proposal.width ?? .infinity
        let regels = indeling(subviews: subviews, breedte: breedte)
        let hoogte = regels.map(\.hoogte).reduce(0, +) + ruimte * CGFloat(max(0, regels.count - 1))
        let maxBreedte = regels.map(\.breedte).max() ?? 0
        return CGSize(width: proposal.width ?? maxBreedte, height: hoogte)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for regel in indeling(subviews: subviews, breedte: bounds.width) {
            var x = bounds.minX
            for index in regel.indices {
                let maat = subviews[index].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: min(maat.width, bounds.width), height: nil))
                x += maat.width + ruimte
            }
            y += regel.hoogte + ruimte
        }
    }

    private struct Regel {
        var indices: [Int] = []
        var breedte: CGFloat = 0
        var hoogte: CGFloat = 0
    }

    private func indeling(subviews: Subviews, breedte: CGFloat) -> [Regel] {
        var regels: [Regel] = []
        var huidig = Regel()
        for (index, subview) in subviews.enumerated() {
            let maat = subview.sizeThatFits(ProposedViewSize(width: breedte, height: nil))
            let nodig = huidig.indices.isEmpty ? maat.width : huidig.breedte + ruimte + maat.width
            if nodig > breedte, !huidig.indices.isEmpty {
                regels.append(huidig)
                huidig = Regel()
            }
            huidig.breedte = huidig.indices.isEmpty ? min(maat.width, breedte) : huidig.breedte + ruimte + maat.width
            huidig.hoogte = max(huidig.hoogte, maat.height)
            huidig.indices.append(index)
        }
        if !huidig.indices.isEmpty { regels.append(huidig) }
        return regels
    }
}
