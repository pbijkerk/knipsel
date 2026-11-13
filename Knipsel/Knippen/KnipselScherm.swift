import SwiftUI

/// Kleuren per rol, zoals in de schets (tab 1): titel en intro tomaat, ingrediënten groen,
/// bereiding blauw, weg grijs gearceerd.
extension Rol {
    var kleur: Color {
        switch self {
        case .titel, .intro: Color(red: 0.851, green: 0.380, blue: 0.235)
        case .ingredient: Color(red: 0.20, green: 0.60, blue: 0.33)
        case .stap: Color(red: 0.20, green: 0.45, blue: 0.82)
        case .weg: Color(white: 0.45)
        }
    }

    /// Kort etiket op het vak.
    var etiket: String {
        switch self {
        case .titel: "TITEL"
        case .intro: "INTRO"
        case .ingredient: "INGR"
        case .stap: "BEREIDING"
        case .weg: "WEG"
        }
    }
}

/// Het knipselscherm: de foto('s) met gekleurde kaders per blok. Tik op een kader om de rol te
/// wisselen (titel → intro → ingrediënt → bereiding → weg).
struct KnipselScherm: View {
    @Bindable var sessie: KnipSessie
    /// Smalle variant (naast de controle op iPad): geen tikken, geen uitleg.
    var alleenKijken = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !alleenKijken {
                    Legenda()
                }
                ForEach(sessie.paginas.indices, id: \.self) { pagina in
                    PaginaMetVakken(
                        beeld: sessie.paginas[pagina],
                        vakken: sessie.vakken.filter { $0.pagina == pagina },
                        tekst: { sessie.regels[$0].tekst },
                        tikbaar: !alleenKijken
                    ) { vak in
                        withAnimation(.snappy) { sessie.wisselRol(vak) }
                    }
                    .accessibilityLabel(sessie.paginas.count > 1 ? "Pagina \(pagina + 1)" : "Pagina")
                }
                if !alleenKijken {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tik op een blok om de rol te wisselen.")
                        Text(sessie.indeling.bron.omschrijving)
                            .foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                }
            }
            .padding()
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
    }
}

struct Legenda: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { items }
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow {
                    item(.titel, "Titel en intro")
                    item(.ingredient, "Ingrediënten")
                }
                GridRow {
                    item(.stap, "Bereiding")
                    item(.weg, "Weg")
                }
            }
        }
        .font(.footnote)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var items: some View {
        item(.titel, "Titel en intro")
        item(.ingredient, "Ingrediënten")
        item(.stap, "Bereiding")
        item(.weg, "Weg")
    }

    private func item(_ rol: Rol, _ titel: String) -> some View {
        HStack(spacing: 6) {
            VakVorm(rol: rol)
                .frame(width: 18, height: 14)
            Text(titel)
        }
    }
}

/// Eén pagina met de vakken eroverheen.
struct PaginaMetVakken: View {
    let beeld: UIImage
    let vakken: [KnipSessie.Vak]
    let tekst: (Int) -> String
    var tikbaar = true
    var tik: (KnipSessie.Vak) -> Void = { _ in }

    var body: some View {
        Image(uiImage: beeld)
            .resizable()
            .scaledToFit()
            .overlay {
                GeometryReader { geo in
                    let etiketten = eersteVakPerRol
                    ForEach(vakken) { vak in
                        let kader = schaal(vak.kader, naar: geo.size)
                        VakVorm(rol: vak.rol)
                            .frame(width: kader.width, height: kader.height)
                            .overlay(alignment: .topLeading) {
                                if etiketten.contains(vak.id) {
                                    Text(vak.rol.etiket)
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(vak.rol.kleur, in: RoundedRectangle(cornerRadius: 3))
                                        .offset(x: -1, y: -12)
                                        .fixedSize()
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { if tikbaar { tik(vak) } }
                            .position(x: kader.midX, y: kader.midY)
                            .accessibilityElement()
                            .accessibilityLabel("\(vak.rol.naam): \(vak.regels.map(tekst).joined(separator: " "))")
                            .accessibilityHint(tikbaar ? "Tik om de rol te wisselen" : "")
                            .accessibilityAddTraits(tikbaar ? .isButton : [])
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
    }

    /// Etiket alleen op het eerste vak van elke rol (anders staat er vier keer "BEREIDING").
    private var eersteVakPerRol: Set<Int> {
        var gezien = Set<Rol>()
        var ids = Set<Int>()
        for vak in vakken.sorted(by: { $0.kader.minY < $1.kader.minY }) where gezien.insert(vak.rol).inserted {
            ids.insert(vak.id)
        }
        return ids
    }

    private func schaal(_ kader: CGRect, naar maat: CGSize) -> CGRect {
        CGRect(
            x: kader.minX * maat.width, y: kader.minY * maat.height, width: kader.width * maat.width,
            height: kader.height * maat.height
        ).insetBy(dx: -4, dy: -3)
    }
}

/// Gekleurd kader; "weg" grijs gearceerd.
struct VakVorm: View {
    let rol: Rol

    var body: some View {
        let vorm = RoundedRectangle(cornerRadius: 4, style: .continuous)
        ZStack {
            if rol == .weg {
                Arcering()
                    .stroke(rol.kleur.opacity(0.55), lineWidth: 1.5)
                    .clipShape(vorm)
                vorm.fill(Color(white: 0.5).opacity(0.25))
            } else {
                vorm.fill(rol.kleur.opacity(0.16))
            }
            vorm.strokeBorder(rol.kleur, lineWidth: rol == .weg ? 1 : 2)
        }
    }
}

/// Schuine lijnen.
struct Arcering: Shape {
    var afstand: CGFloat = 7

    func path(in rect: CGRect) -> Path {
        var pad = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            pad.move(to: CGPoint(x: x, y: rect.maxY))
            pad.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += afstand
        }
        return pad
    }
}
