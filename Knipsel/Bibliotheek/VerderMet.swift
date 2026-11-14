import CoreData
import OSLog
import SwiftUI

/// Een afgebroken kookbeurt die je kunt hervatten: het recept en waar je bleef.
struct VerderKeuze: Identifiable {
    let recept: Recept
    let stand: KookVoortgang.Stand

    var id: URL { stand.recept }

    /// De meest recente afgebroken kookbeurt van een recept dat nog bestaat (`nil` als er geen is).
    @MainActor
    static func huidige(in context: NSManagedObjectContext, nu: Date = .now) -> VerderKeuze? {
        let voortgang = KookVoortgang()
        guard let stand = voortgang.meestRecente(nu: nu, bestaat: { recept(bij: $0, in: context) != nil }),
            let recept = recept(bij: stand.recept, in: context)
        else { return nil }
        return VerderKeuze(recept: recept, stand: stand)
    }

    @MainActor
    static func recept(bij uri: URL, in context: NSManagedObjectContext) -> Recept? {
        guard let id = context.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: uri),
            let recept = try? context.existingObject(with: id) as? Recept, !recept.isDeleted
        else { return nil }
        return recept
    }
}

/// Bovenaan de bibliotheek (U8): "Verder met…" als je een kookmodus halverwege sloot, met het
/// symbool of de foto van het recept, "Stap 4 van 7 · gisteren", de knop *Verder* en een ✕ om
/// hem te vergeten.
struct VerderMetKaart: View {
    let keuze: VerderKeuze
    let verder: () -> Void
    let vergeet: () -> Void

    @ScaledMetric(relativeTo: .headline) private var knophoogte: CGFloat = 44
    @Environment(\.dynamicTypeSize) private var tekstgrootte

    private var vorm: RoundedRectangle { RoundedRectangle(cornerRadius: 18, style: .continuous) }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                CategorieIcoon(recept: keuze.recept)
                tekst
                Spacer(minLength: 8)
                verderKnop
                vergeetKnop
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 14) {
                    // Bij de grootste tekstmaten krijgt de titel de ruimte van het symbool.
                    if !tekstgrootte.isAccessibilitySize {
                        CategorieIcoon(recept: keuze.recept)
                    }
                    tekst
                    Spacer(minLength: 0)
                    vergeetKnop
                }
                verderKnop
            }
        }
        .padding(.vertical, 12)
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .background(Kaartkleuren.neutraal.kleur, in: vorm)
        .accessibilityElement(children: .contain)
    }

    private var tekst: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Verder met")
                .font(.caption.weight(.bold))
                .textCase(.uppercase)
                .kerning(0.4)
                .foregroundStyle(Kaartkleuren.ondertekst.kleur)
            Text(keuze.recept.titelOfStandaard)
                .font(.system(.headline, design: .serif).weight(.bold))
                .foregroundStyle(Kaartkleuren.titel.kleur)
                .lineLimit(tekstgrootte.isAccessibilitySize ? 4 : 2)
                .fixedSize(horizontal: false, vertical: true)
            Text(KookVoortgang.omschrijving(keuze.stand))
                .font(.subheadline)
                .foregroundStyle(Kaartkleuren.ondertekst.kleur)
        }
        .accessibilityElement(children: .combine)
    }

    private var verderKnop: some View {
        Button(action: verder) {
            SwiftUI.Label("Verder", systemImage: "play.fill")
                .font(.headline.weight(.bold))
                .lineLimit(1)
                .padding(.horizontal, 18)
                .frame(minHeight: max(44, knophoogte))
                .background(Kookkleuren.accent, in: Capsule())
                .foregroundStyle(.white)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Verder met \(keuze.recept.titelOfStandaard)")
        .accessibilityHint("Opent de kookmodus bij stap \(keuze.stand.stapNummer)")
    }

    private var vergeetKnop: some View {
        Button(action: vergeet) {
            Image(systemName: "xmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Kaartkleuren.ondertekst.kleur)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Vergeet")
        .accessibilityHint("Haalt Verder met weg")
    }
}

/// "Verder met…" voor de bibliotheek: houdt de afgebroken kookbeurt bij (`keuze`) en opent de
/// kookmodus op die stap, met die porties, zodra `gestart` gezet wordt. Na "Gekookt" verdwijnt de
/// kaart; de fotovraag werkt zoals vanuit het recept.
struct VerderMet: ViewModifier {
    @Environment(\.managedObjectContext) private var context
    /// Volgt de opslag van `KookVoortgang`, zodat de kaart meteen verschijnt of verdwijnt.
    @AppStorage(AppConfiguratie.sleutelKookVoortgang) private var opslag = Data()
    @Binding var keuze: VerderKeuze?
    @Binding var gestart: VerderKeuze?

    @State private var fotoRecept: Recept?
    @State private var fotoNaKoken = false
    @State private var toonFotoBibliotheek = false
    @State private var toonCamera = false

    func body(content: Content) -> some View {
        content
            .task(id: opslag) {
                KookVoortgang().ruimOp()
                keuze = VerderKeuze.huidige(in: context)
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange)) { _ in
                // Recept verwijderd, of titel of foto gewijzigd.
                keuze = VerderKeuze.huidige(in: context)
            }
            .onChange(of: gestart?.id) {
                if let gestart { fotoRecept = gestart.recept }
            }
            .fullScreenCover(item: $gestart, onDismiss: naKookmodus) { keuze in
                VerderKookmodus(
                    keuze: keuze, gekookt: { legGekooktVast(keuze.recept) }, fotoMaken: { fotoNaKoken = true })
            }
            .background {
                if let fotoRecept {
                    Color.clear
                        .gerechtFotoKiezer(recept: fotoRecept, bibliotheek: $toonFotoBibliotheek, camera: $toonCamera)
                }
            }
    }

    private func legGekooktVast(_ recept: Recept) {
        KookVoortgang().wis(recept: recept.objectID.uriRepresentation())
        do {
            try recept.legGekooktVast()
        } catch {
            context.rollback()
            Logger(subsystem: "com.peterbijkerk.knipsel", category: "Recept")
                .error("Gekookt vastleggen mislukt: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func naKookmodus() {
        guard fotoNaKoken else { return }
        fotoNaKoken = false
        if CameraKiezer.isBeschikbaar {
            toonCamera = true
        } else {
            toonFotoBibliotheek = true
        }
    }
}

/// De kookmodus voor een hervatte kookbeurt; de sessie wordt één keer gemaakt.
private struct VerderKookmodus: View {
    let keuze: VerderKeuze
    let gekookt: () -> Void
    let fotoMaken: () -> Void
    @State private var sessie: KookSessie

    init(keuze: VerderKeuze, gekookt: @escaping () -> Void, fotoMaken: @escaping () -> Void) {
        self.keuze = keuze
        self.gekookt = gekookt
        self.fotoMaken = fotoMaken
        _sessie = State(initialValue: KookSessie(recept: keuze.recept, stand: keuze.stand))
    }

    var body: some View {
        KookmodusScherm(
            sessie: sessie, gekookt: gekookt, vraagFoto: !keuze.recept.heeftFoto, fotoMaken: fotoMaken,
            gesloten: { [sessie] in KookVoortgang().naSluiten(sessie, recept: keuze.stand.recept) })
    }
}

extension View {
    /// Zie `VerderMet`.
    func verderMet(_ keuze: Binding<VerderKeuze?>, gestart: Binding<VerderKeuze?>) -> some View {
        modifier(VerderMet(keuze: keuze, gestart: gestart))
    }
}
