import CoreData
import ImageIO
import UIKit

/// De eigen foto van het gekookte gerecht (#23, 3b): midden uitsnijden naar 4:3 (liggend),
/// verkleinen tot max. 1600 px breed (nooit vergroten) en bewaren als JPEG 0,8. Nooit de
/// krantenfoto: die verdwijnt na het knippen (B7).
enum GerechtFoto {
    /// Breedte : hoogte van de bewaarde foto.
    static let verhouding: CGFloat = 4.0 / 3.0
    static let maxZijde: CGFloat = 1600
    static let kwaliteit: CGFloat = 0.8
    /// Grote foto's eerst via ImageIO verkleinen tot deze lange zijde (geen 48 MP in het geheugen).
    /// Ruim genoeg voor 1600 px breed, ook bij staande 9:16.
    static let voorverkleining = 3200

    /// De middenuitsnede in 4:3 van een beeld van `maat` pixels, en de maat waarin die bewaard wordt.
    static func uitsnede(voor maat: CGSize) -> (bron: CGRect, doel: CGSize) {
        guard maat.width >= 1, maat.height >= 1 else { return (.zero, .zero) }
        let bron =
            maat.width / maat.height > verhouding
            ? CGSize(width: maat.height * verhouding, height: maat.height)
            : CGSize(width: maat.width, height: maat.width / verhouding)
        let rechthoek = CGRect(
            x: (maat.width - bron.width) / 2, y: (maat.height - bron.height) / 2, width: bron.width,
            height: bron.height)
        let schaal = min(1, maxZijde / bron.width)
        let breedte = max(1, (bron.width * schaal).rounded(.down))
        let hoogte = max(1, (breedte / verhouding).rounded(.down))
        return (rechthoek, CGSize(width: breedte, height: hoogte))
    }

    /// Bijgesneden en verkleind als JPEG, of `nil` als het beeld leeg is.
    static func maakData(van beeld: UIImage) -> Data? {
        let pixels = CGSize(width: beeld.size.width * beeld.scale, height: beeld.size.height * beeld.scale)
        let (bron, doel) = uitsnede(voor: pixels)
        guard bron.width >= 1 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let schaal = doel.width / bron.width
        // `draw(in:)` houdt rekening met de oriëntatie van camerafoto's.
        return UIGraphicsImageRenderer(size: doel, format: format).jpegData(withCompressionQuality: kwaliteit) { _ in
            beeld.draw(
                in: CGRect(
                    x: -bron.minX * schaal, y: -bron.minY * schaal, width: pixels.width * schaal,
                    height: pixels.height * schaal))
        }
    }

    /// Voor een gekozen foto (JPEG, HEIC, …): eerst verkleinen via ImageIO, dan als hierboven.
    static func maakData(van data: Data) -> Data? {
        guard let beeld = miniatuur(van: data, maxPixels: voorverkleining) else { return nil }
        return maakData(van: UIImage(cgImage: beeld))
    }

    /// Een verkleinde, rechtop gezette versie (lange zijde ≤ `maxPixels`), zonder de hele foto te
    /// decoderen. Draait buiten de main thread.
    static func miniatuur(van data: Data, maxPixels: Int) -> CGImage? {
        guard let bron = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opties: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        return CGImageSourceCreateThumbnailAtIndex(bron, 0, opties as CFDictionary)
    }
}

/// Gedecodeerde gerechtfoto's per recept, foto-versie en maat, zodat scrollen niet steeds opnieuw
/// decodeert. `NSCache` is thread-safe en ruimt zelf op bij geheugendruk.
final class GerechtFotoCache: @unchecked Sendable {
    static let gedeeld = GerechtFotoCache()

    private let cache = NSCache<NSString, UIImage>()

    init(limiet: Int = 300) {
        cache.countLimit = limiet
    }

    static func sleutel(id: NSManagedObjectID, gewijzigd: Date?, maxPixels: Int) -> String {
        "\(id.uriRepresentation().absoluteString)|\(gewijzigd?.timeIntervalSinceReferenceDate ?? 0)|\(maxPixels)"
    }

    func beeld(voor sleutel: String) -> UIImage? {
        cache.object(forKey: sleutel as NSString)
    }

    func bewaar(_ beeld: UIImage, voor sleutel: String) {
        cache.setObject(beeld, forKey: sleutel as NSString)
    }
}
