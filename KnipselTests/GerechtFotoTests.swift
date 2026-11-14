import CoreData
import Foundation
import ImageIO
import Testing
import UIKit

@testable import Knipsel

/// Een verzonnen effen beeld van `breedte` × `hoogte` pixels (geen echte foto).
func testbeeld(breedte: CGFloat, hoogte: CGFloat, kleur: UIColor = .systemOrange) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: breedte, height: hoogte), format: format).image { context in
        kleur.setFill()
        context.fill(CGRect(x: 0, y: 0, width: breedte, height: hoogte))
    }
}

/// Pixelmaat van JPEG-data, zoals ImageIO hem leest.
func pixelmaat(_ data: Data) throws -> CGSize {
    let bron = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let eigenschappen = try #require(CGImageSourceCopyPropertiesAtIndex(bron, 0, nil) as? [CFString: Any])
    let breedte = try #require(eigenschappen[kCGImagePropertyPixelWidth] as? Int)
    let hoogte = try #require(eigenschappen[kCGImagePropertyPixelHeight] as? Int)
    return CGSize(width: breedte, height: hoogte)
}

struct GerechtFotoTests {
    @Test func liggendGrootWordtVierDerdeVanMaximaal1600() throws {
        let data = try #require(GerechtFoto.maakData(van: testbeeld(breedte: 4000, hoogte: 2000)))
        #expect(try pixelmaat(data) == CGSize(width: 1600, height: 1200))
    }

    @Test func staandWordtOokLiggendVierDerde() throws {
        let data = try #require(GerechtFoto.maakData(van: testbeeld(breedte: 3024, hoogte: 4032)))
        #expect(try pixelmaat(data) == CGSize(width: 1600, height: 1200))
    }

    @Test func kleinBeeldWordtNietOpgeschaald() throws {
        let data = try #require(GerechtFoto.maakData(van: testbeeld(breedte: 800, hoogte: 800)))
        #expect(try pixelmaat(data) == CGSize(width: 800, height: 600))
    }

    @Test func uitsnedeZitInHetMidden() {
        let staand = GerechtFoto.uitsnede(voor: CGSize(width: 3000, height: 4000))
        #expect(staand.bron == CGRect(x: 0, y: 875, width: 3000, height: 2250))
        let liggend = GerechtFoto.uitsnede(voor: CGSize(width: 4000, height: 2000))
        #expect(abs(liggend.bron.minX - (4000 - 2000 * 4 / 3.0) / 2) < 0.001)
        #expect(liggend.bron.minY == 0)
        #expect(liggend.bron.height == 2000)
    }

    @Test(arguments: [
        CGSize(width: 4032, height: 3024), CGSize(width: 1080, height: 1920), CGSize(width: 801, height: 601),
        CGSize(width: 5000, height: 1000), CGSize(width: 1, height: 1),
    ])
    func verhoudingIsAltijdVierDerdeEnNooitGroter(maat: CGSize) {
        let (bron, doel) = GerechtFoto.uitsnede(voor: maat)
        #expect(doel.width <= GerechtFoto.maxZijde)
        #expect(doel.width <= bron.width + 0.001)
        #expect(doel.height <= max(1, bron.height) + 0.001)
        #expect(bron.maxX <= maat.width + 0.001 && bron.maxY <= maat.height + 0.001)
        if doel.width >= 100 { #expect(abs(doel.width / doel.height - 4.0 / 3.0) < 0.01) }
    }

    @Test func middenVanHetBeeldBlijftBewaard() throws {
        // Staand: boven rood, midden groen, onder blauw. Na het bijsnijden is het midden groen.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let beeld = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 900), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
            UIColor.green.setFill()
            context.fill(CGRect(x: 0, y: 300, width: 300, height: 300))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 600, width: 300, height: 300))
        }
        let data = try #require(GerechtFoto.maakData(van: beeld))
        let resultaat = try #require(UIImage(data: data)?.cgImage)
        #expect(resultaat.width == 300 && resultaat.height == 225)
        let pixel = try #require(kleur(in: resultaat, x: 150, y: 112))
        #expect(pixel.groen > 200 && pixel.rood < 60 && pixel.blauw < 60)
    }

    @Test func gekozenFotoAlsDataWordtOokBijgesneden() throws {
        let bron = try #require(testbeeld(breedte: 2400, hoogte: 3200).jpegData(compressionQuality: 0.9))
        let data = try #require(GerechtFoto.maakData(van: bron))
        #expect(try pixelmaat(data) == CGSize(width: 1600, height: 1200))
        #expect(GerechtFoto.maakData(van: Data("geen foto".utf8)) == nil)
    }

    @Test func miniatuurIsVerkleind() throws {
        let data = try #require(GerechtFoto.maakData(van: testbeeld(breedte: 1600, hoogte: 1200)))
        let miniatuur = try #require(GerechtFoto.miniatuur(van: data, maxPixels: 200))
        #expect(max(miniatuur.width, miniatuur.height) == 200)
    }

    @MainActor @Test func cachesleutelVerandertMetDeFoto() {
        let opslag = Opslag.voorbeeld
        let id = opslag.eersteRecept.objectID
        let eerder = GerechtFotoCache.sleutel(id: id, gewijzigd: Date(timeIntervalSince1970: 1), maxPixels: 200)
        let later = GerechtFotoCache.sleutel(id: id, gewijzigd: Date(timeIntervalSince1970: 2), maxPixels: 200)
        #expect(eerder != later)
        #expect(eerder != GerechtFotoCache.sleutel(id: id, gewijzigd: Date(timeIntervalSince1970: 1), maxPixels: 720))
        let cache = GerechtFotoCache(limiet: 2)
        cache.bewaar(testbeeld(breedte: 2, hoogte: 2), voor: eerder)
        #expect(cache.beeld(voor: eerder) != nil)
        #expect(cache.beeld(voor: later) == nil)
    }

    private func kleur(in beeld: CGImage, x: Int, y: Int) -> (rood: Int, groen: Int, blauw: Int)? {
        var pixel = [UInt8](repeating: 0, count: 4)
        guard
            let context = CGContext(
                data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(beeld, in: CGRect(x: -x, y: -(beeld.height - 1 - y), width: beeld.width, height: beeld.height))
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }
}

@MainActor
struct GerechtFotoModelTests {
    @Test func fotoBewarenEnLezen() throws {
        let opslag = legeOpslag()
        let recept = try maakRecept("Ovenschotel", in: opslag.context)
        #expect(!recept.heeftFoto)
        let foto = try #require(GerechtFoto.maakData(van: testbeeld(breedte: 1200, hoogte: 900)))
        try recept.zetFoto(foto, op: Date(timeIntervalSince1970: 1000))

        // Vers ophalen in een tweede context: komt het echt uit de store?
        let ander = opslag.container.newBackgroundContext()
        let id = recept.objectID
        let (gelezen, datum) = try ander.performAndWait {
            let terug = try #require(try ander.existingObject(with: id) as? Recept)
            return (terug.fotoData, terug.fotoGewijzigdOp)
        }
        #expect(gelezen == foto)
        #expect(datum == Date(timeIntervalSince1970: 1000))
        #expect(recept.heeftFoto)
    }

    @Test func fotoVerwijderen() throws {
        let context = legeOpslag().context
        let recept = try maakRecept("Taart", in: context)
        try recept.zetFoto(Data([1, 2, 3]))
        try recept.zetFoto(nil)
        #expect(recept.fotoData == nil)
        #expect(recept.fotoGewijzigdOp == nil)
        #expect(!recept.heeftFoto)
        #expect(!context.hasChanges)
    }

    @Test func receptZonderFotoBlijftWerken() throws {
        let context = legeOpslag().context
        let recept = try maakRecept("Soep", ingredienten: ["1 ui"], in: context)
        try recept.legGekooktVast()
        #expect(recept.fotoData == nil)
        #expect(!recept.heeftFoto)
        #expect(recept.aantalKeerGekookt == 1)
        #expect(recept.gesorteerdeIngredienten.count == 1)
    }

    @Test func fotoVeldIsOptioneelEnExternOpgeslagen() throws {
        let entiteit = try #require(Opslag.model.entitiesByName["Recept"])
        let foto = try #require(entiteit.attributesByName["fotoData"])
        #expect(foto.isOptional)
        #expect(foto.attributeType == .binaryDataAttributeType)
        #expect(foto.allowsExternalBinaryDataStorage)
        #expect(try #require(entiteit.attributesByName["fotoGewijzigdOp"]).isOptional)
    }

    /// Een store van modelversie 1 (vóór de foto) opent met het huidige model (lichte migratie), en
    /// de recepten erin hebben geen foto.
    @Test func storeVanModelversie1MigreertLicht() throws {
        let momd = try #require(Bundle(for: Recept.self).url(forResource: "Knipsel", withExtension: "momd"))
        let v1 = try #require(NSManagedObjectModel(contentsOf: momd.appendingPathComponent("Knipsel.mom")))
        #expect(v1.entitiesByName["Recept"]?.attributesByName["fotoData"] == nil)

        let map = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: map, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: map) }
        let url = map.appendingPathComponent("Knipsel.sqlite")

        let oud = NSPersistentContainer(name: "Knipsel", managedObjectModel: v1)
        oud.persistentStoreDescriptions = [NSPersistentStoreDescription(url: url)]
        var fout: (any Error)?
        oud.loadPersistentStores { _, error in fout = error }
        #expect(fout == nil)
        let oudRecept = NSEntityDescription.insertNewObject(forEntityName: "Recept", into: oud.viewContext)
        oudRecept.setValue("Oude stoofpot", forKey: "titel")
        try oud.viewContext.save()
        for store in oud.persistentStoreCoordinator.persistentStores {
            try oud.persistentStoreCoordinator.remove(store)
        }

        let nieuw = NSPersistentContainer(name: "Knipsel", managedObjectModel: Opslag.model)
        let beschrijving = NSPersistentStoreDescription(url: url)
        beschrijving.shouldMigrateStoreAutomatically = true
        beschrijving.shouldInferMappingModelAutomatically = true
        nieuw.persistentStoreDescriptions = [beschrijving]
        nieuw.loadPersistentStores { _, error in fout = error }
        #expect(fout == nil)
        let recepten = try nieuw.viewContext.fetch(Recept.verzoek())
        #expect(recepten.map(\.titel) == ["Oude stoofpot"])
        #expect(recepten.first?.heeftFoto == false)
        try recepten.first?.zetFoto(Data([9]))
        for store in nieuw.persistentStoreCoordinator.persistentStores {
            try nieuw.persistentStoreCoordinator.remove(store)
        }
    }
}
