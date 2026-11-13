import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Tekst herkennen op een paginafoto, op het toestel (Vision, `nl-NL`, met taalcorrectie).
enum ScanService {
    static func herken(_ beeld: CGImage, pagina: Int = 0) async throws -> [HerkendeRegel] {
        var verzoek = RecognizeTextRequest()
        verzoek.recognitionLevel = .accurate
        verzoek.recognitionLanguages = [Locale.Language(identifier: "nl-NL")]
        verzoek.usesLanguageCorrection = true
        let waarnemingen = try await verzoek.perform(on: beeld)
        return waarnemingen.compactMap { waarneming in
            guard let kandidaat = waarneming.topCandidates(1).first else { return nil }
            let kader = waarneming.boundingBox.cgRect
            // Vision: oorsprong linksonder. Knipsel: linksboven, zoals SwiftUI.
            return HerkendeRegel(
                tekst: kandidaat.string,
                kader: CGRect(x: kader.minX, y: 1 - kader.maxY, width: kader.width, height: kader.height),
                betrouwbaarheid: kandidaat.confidence,
                pagina: pagina)
        }
    }

    /// Meerdere pagina's (een recept dat doorloopt), achter elkaar genummerd.
    static func herken(_ beelden: [CGImage]) async throws -> [HerkendeRegel] {
        var alle: [HerkendeRegel] = []
        for (pagina, beeld) in beelden.enumerated() {
            alle += try await herken(beeld, pagina: pagina)
        }
        return alle
    }
}

/// Opnamedatum uit de EXIF-gegevens van een foto: standaard de datum van het blad.
enum Fotodatum {
    static func uit(_ data: Data) -> Date? {
        guard let bron = CGImageSourceCreateWithData(data as CFData, nil),
            let eigenschappen = CGImageSourceCopyPropertiesAtIndex(bron, 0, nil) as? [CFString: Any]
        else { return nil }
        let exif = eigenschappen[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = eigenschappen[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let tekst =
            exif?[kCGImagePropertyExifDateTimeOriginal] as? String
            ?? exif?[kCGImagePropertyExifDateTimeDigitized] as? String
            ?? tiff?[kCGImagePropertyTIFFDateTime] as? String
        guard let tekst else { return nil }
        let opmaak = DateFormatter()
        opmaak.locale = Locale(identifier: "en_US_POSIX")
        opmaak.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return opmaak.date(from: tekst)
    }
}
