import CoreData
import SwiftUI

/// Selectiemodus in de bibliotheek (#40, schets 3A): recepten aan- en uitvinken voor één
/// boodschappenlijst. De volgorde is die waarin je ze aantikt. Puur, zodat het te testen is.
struct Selectie<ID: Hashable>: Equatable {
    private(set) var actief = false
    private(set) var gekozen: [ID] = []

    var aantal: Int { gekozen.count }

    func bevat(_ id: ID) -> Bool { gekozen.contains(id) }

    mutating func wissel(_ id: ID) {
        guard actief else { return }
        if let plek = gekozen.firstIndex(of: id) {
            gekozen.remove(at: plek)
        } else {
            gekozen.append(id)
        }
    }

    /// Aan, eventueel met een eerste recept (contextmenu "Selecteer").
    mutating func start(met id: ID? = nil) {
        actief = true
        if let id, !gekozen.contains(id) { gekozen.append(id) }
    }

    mutating func stop() {
        actief = false
        gekozen = []
    }

    /// "🛒 Boodschappen voor 3 recepten".
    static func knop(aantal: Int) -> String {
        aantal == 1 ? "Boodschappen voor 1 recept" : "Boodschappen voor \(aantal) recepten"
    }
}

typealias ReceptSelectie = Selectie<NSManagedObjectID>

/// Vinkje op een kaart of regel in selectiemodus: tomaat met wit vinkje als gekozen, anders een open
/// rondje.
struct SelectieVinkje: View {
    let aan: Bool
    /// Op een kaart: met een lichte achtergrond, zodat het ook op een foto zichtbaar is.
    var opKaart = true
    @ScaledMetric(relativeTo: .title3) private var maat: CGFloat = 28

    var body: some View {
        ZStack {
            if aan {
                Circle().fill(Kookkleuren.accent)
                Image(systemName: "checkmark")
                    .font(.system(size: maat * 0.5, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle().fill(opKaart ? AnyShapeStyle(.background.opacity(0.7)) : AnyShapeStyle(.clear))
                Circle().strokeBorder(Color.secondary, lineWidth: 1.5)
            }
        }
        .frame(width: maat, height: maat)
        .shadow(color: .black.opacity(opKaart ? 0.2 : 0), radius: 2, y: 1)
        .accessibilityHidden(true)
    }
}

/// Werkbalk onderin in selectiemodus: "🛒 Boodschappen voor n recepten" (uit bij 0) en "Annuleer".
/// Opent het vel voor meerdere recepten; na een geslaagde lijst gaat de selectiemodus uit zodra het
/// vel dicht is.
struct SelectieBalk: View {
    @Binding var selectie: ReceptSelectie
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [], predicate: NSPredicate(format: "kookboek == %@", Kookboek.thuis.rawValue))
    private var thuisRecepten: FetchedResults<Recept>
    @State private var vel: VelKeuze?
    @State private var geslaagd = false

    struct VelKeuze: Identifiable {
        let id = UUID()
        let recepten: [VelRecept]
        let thuisBestaat: Bool
    }

    var body: some View {
        HStack(spacing: 12) {
            Button("Annuleer") { selectie.stop() }
                .font(.body.weight(.semibold))
                .frame(minHeight: 50)
                .padding(.horizontal, 6)
            Button(action: open) {
                SwiftUI.Label(ReceptSelectie.knop(aantal: selectie.aantal), systemImage: "cart.fill")
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(
                        selectie.aantal == 0
                            ? AnyShapeStyle(Color.secondary.opacity(0.35)) : AnyShapeStyle(Kookkleuren.accent),
                        in: Capsule()
                    )
                    .foregroundStyle(.white)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(selectie.aantal == 0)
            .accessibilityLabel(ReceptSelectie.knop(aantal: selectie.aantal))
            .accessibilityHint("Maak één boodschappenlijst voor de gekozen recepten")
        }
        .frame(maxWidth: 560)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .sheet(item: $vel, onDismiss: { if geslaagd { selectie.stop() } }) { keuze in
            BoodschappenVel(
                recepten: keuze.recepten, bestemming: HerinneringenDienst.gedeeld, thuisBestaat: keuze.thuisBestaat,
                naSucces: { geslaagd = true })
        }
    }

    private func open() {
        let recepten = selectie.gekozen.compactMap { id -> Recept? in
            guard let recept = try? context.existingObject(with: id) as? Recept, !recept.isDeleted else { return nil }
            return recept
        }
        guard !recepten.isEmpty else { return }
        geslaagd = false
        let thuisBestaat =
            recepten.contains(where: \.isThuis)
            || BoodschappenSchakelaar.toon(
                rol: ThuisDelen.gedeeld.status.rol, thuisItems: 0, thuisRecepten: thuisRecepten.count)
        vel = VelKeuze(recepten: recepten.map(VelRecept.init), thuisBestaat: thuisBestaat)
    }
}
