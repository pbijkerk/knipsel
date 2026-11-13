import CoreData
import Observation
import OSLog
import UIKit

/// Eén keer knippen: foto's → herkende regels → indeling → concept. De foto's staan alleen in het
/// geheugen van deze sessie en worden nooit bewaard (B7); na bewaren of annuleren zijn ze weg.
@MainActor
@Observable
final class KnipSessie {
    enum Toestand: Equatable {
        case kiezen
        case bezig(String)
        case klaar
        case fout(String)
    }

    /// Een rechthoek in het knipselscherm: aaneengesloten regels van één blok met dezelfde rol.
    struct Vak: Identifiable, Equatable {
        var id: Int { regels[0] }
        let regels: [Int]
        let kader: CGRect
        let pagina: Int
        let rol: Rol
    }

    private(set) var paginas: [UIImage] = []
    private(set) var regels: [HerkendeRegel] = []
    private(set) var opmaak = Opmaak([])
    var indeling = Indeling(rollen: [])
    var toestand = Toestand.kiezen
    /// Datum van het blad: uit de EXIF van de foto, anders vandaag.
    var bronDatum = Date.now

    private let logger = Logger(subsystem: "com.peterbijkerk.knipsel", category: "Knippen")

    init() {}

    /// Voor tests en schermafbeeldingen: een sessie met al herkende regels.
    init(paginas: [UIImage], regels: [HerkendeRegel], indeling: Indeling, bronDatum: Date = .now) {
        self.paginas = paginas
        self.regels = regels
        self.opmaak = Opmaak(regels)
        self.indeling = indeling
        self.bronDatum = bronDatum
        toestand = .klaar
    }

    /// Herkennen en indelen. `datum`: opnamedatum uit de foto, als die bekend is.
    func verwerk(
        _ beelden: [UIImage], datum: Date?, categorieen: [String], labels: [String],
        indeler: any Indeler = IndelerKeuze.standaard()
    ) async {
        guard !beelden.isEmpty else { return }
        let rechtop = beelden.map { $0.rechtop(maxZijde: AppConfiguratie.maxFotoZijde) }
        paginas = rechtop
        bronDatum = datum ?? .now
        toestand = .bezig(beelden.count == 1 ? "Tekst herkennen…" : "Tekst herkennen op \(beelden.count) pagina's…")
        do {
            let cgBeelden = rechtop.compactMap(\.cgImage)
            let herkend = try await ScanService.herken(cgBeelden)
            guard !herkend.isEmpty else {
                toestand = .fout("Er is geen tekst gevonden. Probeer een scherpere foto, recht van boven.")
                return
            }
            toestand = .bezig("Indelen…")
            let indeling = await indeler.deelIn(herkend, categorieen: categorieen, labels: labels)
            regels = herkend
            opmaak = Opmaak(herkend)
            self.indeling = indeling
            toestand = .klaar
        } catch {
            logger.error("Herkennen mislukt: \(error.localizedDescription, privacy: .public)")
            toestand = .fout("Herkennen is niet gelukt. Probeer het nog eens.")
        }
    }

    /// Opnieuw beginnen: alles vergeten.
    func herstel() {
        paginas = []
        regels = []
        opmaak = Opmaak([])
        indeling = Indeling(rollen: [])
        toestand = .kiezen
    }

    // MARK: - Knipselscherm

    var vakken: [Vak] {
        var vakken: [Vak] = []
        for blok in opmaak.blokken {
            var huidig: [Int] = []
            func sluit() {
                guard let eerste = huidig.first else { return }
                let kader = huidig.dropFirst().reduce(regels[eerste].kader) { $0.union(regels[$1].kader) }
                vakken.append(Vak(regels: huidig, kader: kader, pagina: blok.pagina, rol: rol(eerste)))
                huidig = []
            }
            for regel in blok.regels {
                if let vorige = huidig.last, rol(vorige) != rol(regel) { sluit() }
                huidig.append(regel)
            }
            sluit()
        }
        return vakken
    }

    func rol(_ regel: Int) -> Rol {
        indeling.rollen.indices.contains(regel) ? indeling.rollen[regel] : .weg
    }

    /// Tik op een vak: de volgende rol voor alle regels erin.
    func wisselRol(_ vak: Vak) {
        let nieuw = vak.rol.volgende
        for regel in vak.regels where indeling.rollen.indices.contains(regel) {
            indeling.rollen[regel] = nieuw
        }
    }

    // MARK: - Controle

    var concept: ReceptConcept {
        ReceptOpbouw.bouw(regels, indeling: indeling)
    }

    /// Uitsnede uit de foto rond deze regels, om een twijfelregel te vergelijken.
    func uitsnede(_ nummers: [Int]) -> UIImage? {
        guard let eerste = nummers.first, regels.indices.contains(eerste) else { return nil }
        let pagina = regels[eerste].pagina
        guard paginas.indices.contains(pagina), let beeld = paginas[pagina].cgImage else { return nil }
        let kader = nummers.filter { regels.indices.contains($0) && regels[$0].pagina == pagina }
            .map { regels[$0].kader }.reduce(regels[eerste].kader) { $0.union($1) }
        let breedte = CGFloat(beeld.width)
        let hoogte = CGFloat(beeld.height)
        let rand = kader.height * hoogte * 0.4
        let pixels = CGRect(
            x: kader.minX * breedte, y: kader.minY * hoogte, width: kader.width * breedte,
            height: kader.height * hoogte
        ).insetBy(dx: -rand, dy: -rand).intersection(CGRect(x: 0, y: 0, width: breedte, height: hoogte))
        guard let stuk = beeld.cropping(to: pixels.integral) else { return nil }
        return UIImage(cgImage: stuk)
    }
}

extension UIImage {
    /// Rechtop gedraaid (EXIF-oriëntatie toegepast) en verkleind tot `maxZijde` pixels.
    func rechtop(maxZijde: CGFloat) -> UIImage {
        let pixels = CGSize(width: size.width * scale, height: size.height * scale)
        let factor = min(1, maxZijde / max(pixels.width, pixels.height))
        guard factor < 1 || imageOrientation != .up || scale != 1 else { return self }
        let doel = CGSize(width: (pixels.width * factor).rounded(), height: (pixels.height * factor).rounded())
        let opmaak = UIGraphicsImageRendererFormat()
        opmaak.scale = 1
        return UIGraphicsImageRenderer(size: doel, format: opmaak).image { _ in
            draw(in: CGRect(origin: .zero, size: doel))
        }
    }
}
