import CloudKit
import CoreData
import OSLog

/// Thuis delen met `NSPersistentCloudKitContainer` (zoals Apple's voorbeeld *Sharing Core Data
/// objects between iCloud users*): één zone-brede `CKShare` "Knipsel · Thuis".
///
/// - Eigenaar: de Thuis-recepten staan in de privéstore; `share(_:to:)` verhuist ze (met alles waar
///   ze aan vastzitten: de Thuis-categorieën en -labels) naar de zone van de share.
/// - Deelnemer: na `acceptShareInvitations(from:into:)` staat Thuis in de gedeelde store; nieuwe
///   Thuis-recepten komen daar (`Kookboeken`) en `share(_:to:)` zet ze in dezelfde zone.
/// - Stoppen: `purgeObjectsAndRecordsInZone(with:in:)` haalt de zone weg uit CloudKit én de objecten
///   uit de store. Daarom kopieert `ThuisDelen` eerst wat bewaard moet blijven.
@MainActor
final class CloudKitDeelDienst: DeelDienst {
    static let titel = "Knipsel · Thuis"

    private let opslag: Opslag
    private let ckContainer: CKContainer
    private let logger = Logger(subsystem: "com.peterbijkerk.knipsel", category: "Thuis")

    init(opslag: Opslag, containerIdentifier: String) {
        self.opslag = opslag
        ckContainer = CKContainer(identifier: containerIdentifier)
    }

    var isBeschikbaar: Bool { opslag.synchroniseert }

    private var container: NSPersistentCloudKitContainer { opslag.container }

    /// De share van Thuis en je rol: een share in de gedeelde store is van een ander (deelnemer),
    /// een in de privéstore is van jou (eigenaar).
    private func thuisShare() throws -> (share: CKShare, rol: ThuisStatus.Rol)? {
        if let gedeeld = opslag.gedeeldeStore, let share = try container.fetchShares(in: gedeeld).first {
            return (share, .deelnemer)
        }
        if let prive = opslag.priveStore {
            let shares = try container.fetchShares(in: prive)
            if let share = shares.first(where: { ($0[CKShare.SystemFieldKey.title] as? String) == Self.titel })
                ?? shares.first
            {
                return (share, .eigenaar)
            }
        }
        return nil
    }

    func status() async throws -> ThuisStatus {
        guard isBeschikbaar, let (share, rol) = try thuisShare() else { return .nietGedeeld }
        let ik = share.currentUserParticipant
        let deelnemers = share.participants.map { deelnemer in
            let isIkZelf = deelnemer == ik
            return ThuisDeelnemer(
                id: deelnemer.userIdentity.userRecordID?.recordName ?? UUID().uuidString,
                naam: Self.naam(van: deelnemer, isIkZelf: isIkZelf),
                contact: deelnemer.userIdentity.lookupInfo?.emailAddress
                    ?? deelnemer.userIdentity.lookupInfo?.phoneNumber,
                status: Self.status(van: deelnemer.acceptanceStatus),
                isEigenaar: deelnemer.role == .owner,
                isIkZelf: isIkZelf,
                magBewerken: deelnemer.permission == .readWrite)
        }
        return ThuisStatus(rol: rol, deelnemers: deelnemers.sorted { $0.isEigenaar && !$1.isEigenaar })
    }

    func nietGedeeld(_ objecten: [NSManagedObjectID]) -> [NSManagedObjectID] {
        guard isBeschikbaar, !objecten.isEmpty else { return [] }
        let gedeeld = (try? container.fetchShares(matching: objecten)) ?? [:]
        return objecten.filter { gedeeld[$0] == nil }
    }

    func deel(_ objecten: [NSManagedObjectID]) async throws {
        guard isBeschikbaar else { return }
        let context = opslag.context
        let objecten = objecten.compactMap { try? context.existingObject(with: $0) }.filter { !$0.isDeleted }
        guard !objecten.isEmpty else { return }
        let bestaand = try thuisShare()?.share
        let share = try await deel(objecten, aan: bestaand)
        if bestaand == nil {
            // Nieuwe share: titel voor de uitnodiging, alleen wie uitgenodigd is (geen openbare link).
            share[CKShare.SystemFieldKey.title] = Self.titel as CKRecordValue
            share.publicPermission = .none
            if let prive = opslag.priveStore {
                try await bewaarShare(share, in: prive)
            }
            logger.info("Share Thuis aangemaakt")
        }
    }

    func uitnodiging() async throws -> (share: CKShare, container: CKContainer)? {
        guard isBeschikbaar else { return nil }
        if let (share, _) = try thuisShare() { return (share, ckContainer) }
        // Nog geen share: maak hem met de Thuis-recepten die er al zijn (een share kan niet leeg).
        let recepten = try Kookboeken.recepten(in: .thuis, context: opslag.context)
        guard !recepten.isEmpty else { return nil }
        try await deel(recepten.map(\.objectID))
        return try thuisShare().map { ($0.share, ckContainer) }
    }

    func stopMetDelen() async throws {
        guard let (share, rol) = try thuisShare(), rol == .eigenaar, let prive = opslag.priveStore else { return }
        try await wis(zone: share.recordID.zoneID, in: prive)
        logger.info("Delen van Thuis gestopt")
    }

    func verlaat() async throws {
        guard let (share, rol) = try thuisShare(), rol == .deelnemer, let gedeeld = opslag.gedeeldeStore else { return }
        try await wis(zone: share.recordID.zoneID, in: gedeeld)
        logger.info("Thuis verlaten")
    }

    func accepteer(_ metadata: CKShare.Metadata) async throws {
        guard let gedeeld = opslag.gedeeldeStore else { throw Kookboeken.Fout.geenStore }
        let doos = Doos(waarde: (container, metadata, gedeeld))
        try await withCheckedThrowingContinuation { (vervolg: CheckedContinuation<Void, any Error>) in
            let (container, metadata, gedeeld) = doos.waarde
            container.acceptShareInvitations(from: [metadata], into: gedeeld) { _, fout in
                if let fout { vervolg.resume(throwing: fout) } else { vervolg.resume() }
            }
        }
        logger.info("Uitnodiging voor Thuis geaccepteerd")
    }

    // MARK: - CloudKit-aanroepen (completion → async)

    private func deel(_ objecten: [NSManagedObject], aan share: CKShare?) async throws -> CKShare {
        let doos = Doos(waarde: (container, objecten, share))
        let resultaat = try await withCheckedThrowingContinuation {
            (vervolg: CheckedContinuation<Doos<CKShare>, any Error>) in
            let (container, objecten, share) = doos.waarde
            container.share(objecten, to: share) { _, share, _, fout in
                if let share {
                    vervolg.resume(returning: Doos(waarde: share))
                } else {
                    vervolg.resume(throwing: fout ?? CKError(.internalError))
                }
            }
        }
        return resultaat.waarde
    }

    private func bewaarShare(_ share: CKShare, in store: NSPersistentStore) async throws {
        let doos = Doos(waarde: (container, share, store))
        try await withCheckedThrowingContinuation { (vervolg: CheckedContinuation<Void, any Error>) in
            let (container, share, store) = doos.waarde
            container.persistUpdatedShare(share, in: store) { _, fout in
                if let fout { vervolg.resume(throwing: fout) } else { vervolg.resume() }
            }
        }
    }

    private func wis(zone: CKRecordZone.ID, in store: NSPersistentStore) async throws {
        let doos = Doos(waarde: (container, zone, store))
        try await withCheckedThrowingContinuation { (vervolg: CheckedContinuation<Void, any Error>) in
            let (container, zone, store) = doos.waarde
            container.purgeObjectsAndRecordsInZone(with: zone, in: store) { _, fout in
                if let fout { vervolg.resume(throwing: fout) } else { vervolg.resume() }
            }
        }
    }

    // MARK: - Omzetten

    private static func naam(van deelnemer: CKShare.Participant, isIkZelf: Bool) -> String {
        naam(
            componenten: deelnemer.userIdentity.nameComponents,
            email: deelnemer.userIdentity.lookupInfo?.emailAddress,
            telefoon: deelnemer.userIdentity.lookupInfo?.phoneNumber, isIkZelf: isIkZelf)
    }

    /// De naam van iemand in de share: zijn naam, anders e-mail of telefoon. Ontbreekt dat allemaal
    /// (CloudKit geeft je eigen naam vaak niet mee), dan "Jij" voor jezelf en anders "Onbekend".
    static func naam(componenten: PersonNameComponents?, email: String?, telefoon: String?, isIkZelf: Bool)
        -> String
    {
        if let componenten {
            let naam = PersonNameComponentsFormatter.localizedString(from: componenten, style: .default)
            if !naam.trimmingCharacters(in: .whitespaces).isEmpty { return naam }
        }
        if let email, !email.isEmpty { return email }
        if let telefoon, !telefoon.isEmpty { return telefoon }
        return isIkZelf ? ThuisDeelnemer.jij : "Onbekend"
    }

    private static func status(van status: CKShare.ParticipantAcceptanceStatus) -> ThuisDeelnemer.Status {
        switch status {
        case .pending: .uitgenodigd
        case .accepted: .doetMee
        case .removed: .afgewezen
        default: .onbekend
        }
    }
}

/// CloudKit- en Core Data-objecten zijn niet `Sendable`; deze callbacks lopen op een willekeurige
/// queue maar raken de objecten alleen aan om ze door te geven.
private struct Doos<Waarde>: @unchecked Sendable {
    let waarde: Waarde
}
