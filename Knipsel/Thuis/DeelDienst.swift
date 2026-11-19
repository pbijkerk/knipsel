import CloudKit
import CoreData

/// Iemand in de share "Thuis" (`CKShare.Participant`, zonder CloudKit-typen zodat de weergave en de
/// tests er los van kunnen).
struct ThuisDeelnemer: Identifiable, Equatable, Sendable {
    enum Status: Sendable {
        case uitgenodigd
        case doetMee
        case afgewezen
        case onbekend

        var tekst: String {
            switch self {
            case .uitgenodigd: "Uitgenodigd"
            case .doetMee: "Doet mee"
            case .afgewezen: "Afgewezen"
            case .onbekend: "Onbekend"
            }
        }
    }

    let id: String
    var naam: String
    var contact: String?
    var status: Status
    var isEigenaar: Bool
    var isIkZelf: Bool
    var magBewerken: Bool

    /// De naam voor jezelf als CloudKit geen naam meegeeft.
    static let jij = "Jij"

    /// Zoals in de lijst “Wie doet mee”: “Peter Voorbeeld (jij)”, of alleen “Jij” als je naam ontbreekt.
    var weergaveNaam: String {
        guard isIkZelf else { return naam }
        return naam == Self.jij ? naam : "\(naam) (jij)"
    }
}

/// Hoe Thuis op dit toestel gedeeld is.
struct ThuisStatus: Equatable, Sendable {
    enum Rol: Sendable {
        /// Nog niemand uitgenodigd (Thuis-recepten blijven op je eigen toestellen).
        case nietGedeeld
        /// Jij deelt Thuis.
        case eigenaar
        /// Iemand anders deelt Thuis met jou.
        case deelnemer
    }

    var rol: Rol
    /// Iedereen in de share, de eigenaar eerst.
    var deelnemers: [ThuisDeelnemer]

    static let nietGedeeld = ThuisStatus(rol: .nietGedeeld, deelnemers: [])

    var eigenaar: ThuisDeelnemer? { deelnemers.first(where: \.isEigenaar) }
    /// De anderen dan de eigenaar.
    var huisgenoten: [ThuisDeelnemer] { deelnemers.filter { !$0.isEigenaar } }
}

/// De CloudKit-kant van Thuis delen achter een protocol: echt (`CloudKitDeelDienst`) in de app,
/// een nep in tests en zonder iCloud (`GeenDeelDienst`). De Core Data-kant (kopiëren, verplaatsen)
/// zit in `Kookboeken` en `ThuisDelen` en is wel te testen.
@MainActor
protocol DeelDienst: AnyObject {
    /// Kan dit toestel delen (iCloud-account, sync aan)?
    var isBeschikbaar: Bool { get }
    func status() async throws -> ThuisStatus
    /// Zet net bewaarde Thuis-objecten in de share (en hun hele objectgraaf); maakt de share
    /// "Knipsel · Thuis" aan als er nog geen is.
    func deel(_ objecten: [NSManagedObjectID]) async throws
    /// Welke van deze objecten nog niet in de share staan.
    func nietGedeeld(_ objecten: [NSManagedObjectID]) -> [NSManagedObjectID]
    /// Welke van deze objecten al minstens één keer naar iCloud zijn geëxporteerd (er is een
    /// `CKRecord` voor). Alleen die kunnen veilig de share in; zie `ThuisExport`.
    func geexporteerd(_ objecten: [NSManagedObjectID]) -> Set<NSManagedObjectID>
    /// De share en container voor `UICloudSharingController` (uitnodigen, deelnemers beheren);
    /// `nil` als er nog niets te delen is.
    func uitnodiging() async throws -> (share: CKShare, container: CKContainer)?
    /// Eigenaar: de share en zone weg, bij iedereen.
    func stopMetDelen() async throws
    /// Deelnemer: uit de share stappen; de Thuis-recepten verdwijnen van dit toestel.
    func verlaat() async throws
    func accepteer(_ metadata: CKShare.Metadata) async throws
}

extension DeelDienst {
    /// Is dit object al naar iCloud geëxporteerd?
    func isGeexporteerd(_ id: NSManagedObjectID) -> Bool { geexporteerd([id]).contains(id) }
}

/// Geen iCloud (of onder tests zonder nep): Thuis bestaat alleen op dit toestel.
@MainActor
final class GeenDeelDienst: DeelDienst {
    var isBeschikbaar: Bool { false }
    func status() async throws -> ThuisStatus { .nietGedeeld }
    func deel(_ objecten: [NSManagedObjectID]) async throws {}
    func nietGedeeld(_ objecten: [NSManagedObjectID]) -> [NSManagedObjectID] { [] }
    func geexporteerd(_ objecten: [NSManagedObjectID]) -> Set<NSManagedObjectID> { Set(objecten) }
    func uitnodiging() async throws -> (share: CKShare, container: CKContainer)? { nil }
    func stopMetDelen() async throws {}
    func verlaat() async throws {}
    func accepteer(_ metadata: CKShare.Metadata) async throws {}
}
