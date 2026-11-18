import CloudKit
import CoreData
import Observation
import OSLog

/// Thuis delen voor de app: recepten verplaatsen tussen de kookboeken, nieuwe Thuis-recepten in
/// de share zetten, en stoppen of vertrekken zonder dat er recepten kwijtraken (fase 8, #9).
///
/// De Core Data-kant gebeurt hier en in `Kookboeken` (testbaar met twee stores zonder CloudKit); de
/// CloudKit-kant zit achter `DeelDienst`.
@MainActor
@Observable
final class ThuisDelen {
    static let gedeeld = ThuisDelen(
        opslag: .gedeeld,
        dienst: Opslag.gedeeld.synchroniseert && !Opslag.draaitOnderTests
            ? CloudKitDeelDienst(
                opslag: .gedeeld, containerIdentifier: AppConfiguratie.cloudKitContainer ?? "")
            : GeenDeelDienst())

    let opslag: Opslag
    let dienst: any DeelDienst
    private(set) var status = ThuisStatus.nietGedeeld
    /// Laatste fout van het delen, voor Instellingen › Thuis delen: per soort die niet lukte een regel.
    var fout: String? {
        let regels = ThuisSoort.allCases.compactMap { foutPerSoort[$0] } + [algemeneFout].compactMap { $0 }
        return regels.isEmpty ? nil : regels.joined(separator: "\n")
    }
    private(set) var foutPerSoort: [ThuisSoort: String] = [:]
    /// Een fout buiten het delen per soort (accepteren van een uitnodiging).
    private var algemeneFout: String?
    private(set) var bezig = false

    @ObservationIgnored private let logger = Logger(subsystem: "com.peterbijkerk.knipsel", category: "Thuis")
    @ObservationIgnored private var gestart = false
    @ObservationIgnored private var deelTaak: Task<Void, Never>?
    /// Soorten die deze app-start al eens faalden: niet vanzelf opnieuw proberen.
    @ObservationIgnored private(set) var mislukt: Set<ThuisSoort> = []

    init(opslag: Opslag, dienst: any DeelDienst) {
        self.opslag = opslag
        self.dienst = dienst
    }

    var context: NSManagedObjectContext { opslag.context }

    /// Hoeveel recepten er in Thuis staan.
    var aantalThuis: Int {
        let verzoek = Recept.verzoek()
        verzoek.predicate = NSPredicate(format: "kookboek == %@", Kookboek.thuis.rawValue)
        return (try? context.count(for: verzoek)) ?? 0
    }

    /// Eén keer bij het starten: na elke bewaarbeurt nieuwe Thuis-recepten in de share zetten
    /// (ook als ze niet via `verplaats` kwamen, bijv. bewaard in het controlescherm), en wat de
    /// vorige keer niet lukte (geen netwerk) opnieuw proberen.
    func start() {
        guard !gestart else { return }
        gestart = true
        NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave, object: context, queue: .main
        ) { [weak self] melding in
            let thuis = ((melding.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject>) ?? [])
                .contains {
                    ($0 as? Recept)?.isThuis == true || ($0 as? BoodschappenItem)?.kookboekWaarde == .thuis
                        || ($0 as? Maaltijd)?.kookboekWaarde == .thuis
                }
            guard thuis else { return }
            MainActor.assumeIsolated { self?.planDelen() }
        }
        planDelen(na: .seconds(3))
    }

    private func planDelen(na wachttijd: Duration = .milliseconds(300)) {
        deelTaak?.cancel()
        deelTaak = Task { [weak self] in
            try? await Task.sleep(for: wachttijd)
            guard !Task.isCancelled, let self else { return }
            await self.deelOpenstaande()
        }
    }

    /// Zet Thuis-recepten, de items van de Thuis-boodschappenlijst (#39) en de Thuis-week (#41) die
    /// nog niet in de share staan erin (maakt de share zo nodig aan).
    ///
    /// Per soort een eigen aanroep: als bijvoorbeeld de boodschappen niet lukken (een recordtype dat
    /// nog niet in het iCloud-schema staat), gaan de recepten en het weekmenu gewoon door, en de
    /// melding zegt welke soort het was. Een soort die faalde, probeert Knipsel deze app-start niet
    /// vanzelf opnieuw (anders bij elke bewaarbeurt dezelfde fout); *Probeer opnieuw* kan wel.
    func deelOpenstaande() async {
        guard dienst.isBeschikbaar else { return }
        var ietsGedeeld = false
        for soort in ThuisSoort.allCases where !mislukt.contains(soort) {
            let open = dienst.nietGedeeld(objecten(van: soort))
            guard !open.isEmpty else {
                foutPerSoort[soort] = nil
                continue
            }
            do {
                try await dienst.deel(open)
                foutPerSoort[soort] = nil
                ietsGedeeld = true
            } catch {
                mislukt.insert(soort)
                foutPerSoort[soort] = DeelFout.melding(error, soort: soort)
                logger.error(
                    "Delen van \(soort.rawValue, privacy: .public) mislukt: \(DeelFout.logregel(error), privacy: .public)"
                )
            }
        }
        if ietsGedeeld { await vernieuw() }
    }

    /// De knop bij de foutmelding: alle soorten weer proberen, ook wat eerder deze app-start faalde.
    func probeerOpnieuw() async {
        mislukt.removeAll()
        await deelOpenstaande()
    }

    /// De Thuis-objecten van één soort.
    private func objecten(van soort: ThuisSoort) -> [NSManagedObjectID] {
        switch soort {
        case .recepten: ((try? Kookboeken.recepten(in: .thuis, context: context)) ?? []).map(\.objectID)
        case .boodschappen: Boodschappenlijsten.items(in: .thuis, context: context).map(\.objectID)
        case .maaltijden: Weekmenu.alle(in: .thuis, context: context).map(\.objectID)
        }
    }

    func vernieuw() async {
        do {
            status = try await dienst.status()
        } catch {
            logger.error("Status Thuis ophalen mislukt: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Verplaatsen

    /// "Verplaats naar Thuis" / "Verplaats naar Mijn recepten". Bewaart meteen; het delen zelf
    /// (CloudKit) volgt op de achtergrond. Geeft het recept in zijn nieuwe kookboek terug.
    @discardableResult
    func verplaats(_ recept: Recept, naar kookboek: Kookboek) throws -> Recept {
        let nieuw = try Kookboeken.verplaats(recept, naar: kookboek)
        if kookboek == .thuis { planDelen() }
        return nieuw
    }

    // MARK: - Stoppen en vertrekken

    /// Eigenaar: eerst alle Thuis-recepten terug naar Mijn recepten (anders verdwijnen ze met de
    /// zone ook bij jou), daarna de share weg. De huisgenoot houdt alleen wat die zelf kopieerde.
    func stopMetDelen() async throws {
        bezig = true
        defer { bezig = false }
        try Kookboeken.verplaatsAlles(van: .thuis, naar: .mijn, in: context)
        try Boodschappenlijsten.verplaatsAlles(van: .thuis, naar: .mijn, verwijderBron: true, context: context)
        try Weekmenu.verplaatsAlles(van: .thuis, naar: .mijn, verwijderBron: true, context: context)
        try await dienst.stopMetDelen()
        await vernieuw()
    }

    /// Deelnemer: eventueel eerst een kopie van de Thuis-recepten in Mijn recepten, dan uit de
    /// share. De Thuis-recepten verdwijnen daarna van dit toestel (niet bij de anderen).
    func verlaat(kopieer: Bool) async throws {
        bezig = true
        defer { bezig = false }
        if kopieer {
            try Kookboeken.kopieerAlles(van: .thuis, naar: .mijn, in: context)
            try Boodschappenlijsten.verplaatsAlles(van: .thuis, naar: .mijn, verwijderBron: false, context: context)
            try Weekmenu.verplaatsAlles(van: .thuis, naar: .mijn, verwijderBron: false, context: context)
        }
        try await dienst.verlaat()
        await vernieuw()
    }

    /// Een uitnodiging die iemand in Berichten of Mail opende.
    func accepteer(_ metadata: CKShare.Metadata) async {
        do {
            try await dienst.accepteer(metadata)
            algemeneFout = nil
        } catch {
            algemeneFout = "De uitnodiging voor Thuis kon niet worden geaccepteerd: \(DeelFout.uitleg(error))"
            logger.error("Accepteren mislukt: \(DeelFout.logregel(error), privacy: .public)")
        }
        await vernieuw()
    }

    func wisFout() {
        foutPerSoort.removeAll()
        algemeneFout = nil
    }
}
