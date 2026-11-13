import CoreGraphics
import Foundation

/// De bladspiegel van herkende regels: welke regels samen een blok vormen (een alinea, een lijst,
/// een advertentie) en in welke volgorde je ze leest (pagina, kolom, van boven naar beneden).
/// Vision levert regels in een eigen volgorde; een stap die doorloopt na een advertentie moet toch
/// achter de vorige stap komen.
struct Opmaak: Sendable {
    struct Blok: Equatable, Sendable {
        /// Regelnummers, van boven naar beneden.
        var regels: [Int]
        var kader: CGRect
        var pagina: Int
        var kolom: Int
    }

    /// In leesvolgorde.
    let blokken: [Blok]
    /// Per regelnummer de index van zijn blok in `blokken`.
    let blokVanRegel: [Int]

    /// Regelnummers in leesvolgorde.
    var leesvolgorde: [Int] { blokken.flatMap(\.regels) }

    init(_ regels: [HerkendeRegel]) {
        // 1. Regels samenvoegen tot blokken (union-find).
        var ouder = Array(regels.indices)
        func wortel(_ i: Int) -> Int {
            var i = i
            while ouder[i] != i {
                ouder[i] = ouder[ouder[i]]
                i = ouder[i]
            }
            return i
        }
        for i in regels.indices {
            for j in regels.indices where j > i && Self.horenBijElkaar(regels[i], regels[j]) {
                ouder[wortel(i)] = wortel(j)
            }
        }
        var groepen: [Int: [Int]] = [:]
        for i in regels.indices { groepen[wortel(i), default: []].append(i) }

        var losseBlokken: [Blok] = groepen.values.map { leden in
            let gesorteerd = leden.sorted {
                (regels[$0].kader.minY, regels[$0].kader.minX) < (regels[$1].kader.minY, regels[$1].kader.minX)
            }
            let kader = gesorteerd.dropFirst().reduce(regels[gesorteerd[0]].kader) { $0.union(regels[$1].kader) }
            return Blok(regels: gesorteerd, kader: kader, pagina: regels[gesorteerd[0]].pagina, kolom: 0)
        }

        // 2. Kolommen per pagina: blokken waarvan de linkerkant ongeveer gelijk ligt.
        for pagina in Set(losseBlokken.map(\.pagina)) {
            let indices = losseBlokken.indices.filter { losseBlokken[$0].pagina == pagina }
                .sorted { losseBlokken[$0].kader.minX < losseBlokken[$1].kader.minX }
            var kolom = 0
            var anker: CGFloat?
            for index in indices {
                let x = losseBlokken[index].kader.minX
                if let a = anker {
                    if x - a > Self.kolomTolerantie {
                        kolom += 1
                        anker = x
                    }
                } else {
                    anker = x
                }
                losseBlokken[index].kolom = kolom
            }
        }

        // 3. Leesvolgorde: pagina, kolom, boven naar beneden.
        losseBlokken.sort { ($0.pagina, $0.kolom, $0.kader.minY) < ($1.pagina, $1.kolom, $1.kader.minY) }
        var blokVanRegel = Array(repeating: 0, count: regels.count)
        for (index, blok) in losseBlokken.enumerated() {
            for regel in blok.regels { blokVanRegel[regel] = index }
        }
        blokken = losseBlokken
        self.blokVanRegel = blokVanRegel
    }

    /// Linkerkanten die minder dan dit (deel van de paginabreedte) verschillen, zijn één kolom.
    static let kolomTolerantie: CGFloat = 0.06

    /// Twee regels horen bij hetzelfde blok als ze (a) onder elkaar staan in dezelfde kolom, met een
    /// kleine tussenruimte en ongeveer dezelfde lettergrootte, of (b) op dezelfde hoogte vlak naast
    /// elkaar staan (een zin die Vision in tweeën knipte).
    static func horenBijElkaar(_ a: HerkendeRegel, _ b: HerkendeRegel) -> Bool {
        guard a.pagina == b.pagina else { return false }
        let ka = a.kader
        let kb = b.kader
        let hoogte = min(ka.height, kb.height)
        guard hoogte > 0 else { return false }

        // Vision-kaders van dezelfde letter verschillen tot ±50 % in hoogte (wel of geen stokken en
        // staarten); een kop is meestal twee keer zo groot.
        let overlapX = min(ka.maxX, kb.maxX) - max(ka.minX, kb.minX)
        let tussenruimteY = max(kb.minY - ka.maxY, ka.minY - kb.maxY)
        if overlapX > 0, tussenruimteY < hoogte * 1.0, max(ka.height, kb.height) / hoogte < 1.75 {
            return true
        }
        let overlapY = min(ka.maxY, kb.maxY) - max(ka.minY, kb.minY)
        let tussenruimteX = max(kb.minX - ka.maxX, ka.minX - kb.maxX)
        return overlapY > hoogte * 0.5 && tussenruimteX < 0.025
    }
}
