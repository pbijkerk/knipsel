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
    /// Thuis-objecten die nog niet (met alles waar ze aan vastzitten) in iCloud staan, per soort: die
    /// wachten op de export en gaan daarna vanzelf de share in. Geen fout.
    private(set) var wachtend: [ThuisSoort: Set<NSManagedObjectID>] = [:]

    /// De rustige regel in Instellingen › Thuis delen, of `nil` als er niets wacht.
    var wachtMelding: String? { ThuisExport.wachtMelding(wachtend.mapValues(\.count)) }

    @ObservationIgnored private let logger = Logger(subsystem: "com.peterbijkerk.knipsel", category: "Thuis")
    @ObservationIgnored private var gestart = false
    @ObservationIgnored private var deelTaak: Task<Void, Never>?
    @ObservationIgnored private var exportTaak: Task<Void, Never>?
    /// Soorten die deze app-start al eens faalden met een echte fout: niet vanzelf opnieuw proberen.
    @ObservationIgnored private(set) var mislukt: Set<ThuisSoort> = []
    /// Per object hoe vaak delen deze app-start faalde op `recordMetadata` (max `ThuisExport.maxPogingen`).
    @ObservationIgnored private(set) var pogingen: [NSManagedObjectID: Int] = [:]
    /// Objecten die faalden op `recordMetadata` en zijn aangeraakt: pas na de volgende geslaagde export
    /// opnieuw proberen (`records(for:)` zegt dan al wel "geëxporteerd").
    @ObservationIgnored private(set) var wachtOpExport: Set<NSManagedObjectID> = []
    /// Onderdelen die na een geslaagde export nog steeds niet in iCloud stonden en deze app-start één
    /// keer zijn aangeraakt.
    @ObservationIgnored private(set) var aangestoten: Set<NSManagedObjectID> = []
    /// Per wachtend object welke onderdelen van zijn graaf nog niet geëxporteerd zijn.
    @ObservationIgnored private var ontbrekend: [NSManagedObjectID: Set<NSManagedObjectID>] = [:]
    @ObservationIgnored private var aanHetDelen = false
    @ObservationIgnored private var nogEenRonde = false

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
        // Na elke geslaagde export naar iCloud: wat wachtte, kan nu misschien de share in.
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: opslag.container, queue: .main
        ) { [weak self] melding in
            guard
                let gebeurtenis = melding.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                ThuisExport.isGeslaagdeExport(
                    gebeurtenis.type, eind: gebeurtenis.endDate, gelukt: gebeurtenis.succeeded)
            else { return }
            MainActor.assumeIsolated { self?.planNaExport() }
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

    /// Een export komt vaak in een reeks gebeurtenissen; wacht 2 s na de laatste.
    private func planNaExport() {
        guard !wachtend.values.allSatisfy(\.isEmpty) || !wachtOpExport.isEmpty else { return }
        exportTaak?.cancel()
        exportTaak = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            await self.naExport()
        }
    }

    /// Na een geslaagde export: opnieuw delen wat wachtte (ook wat na een fout op `recordMetadata` is
    /// aangeraakt). Wat daarna nog steeds niet in iCloud staat, raakt Knipsel één keer aan zodat Core
    /// Data het opnieuw exporteert (bijv. een export die eerder mislukte doordat het schema ontbrak).
    /// Een soort met een echte fout blijft geblokkeerd tot *Probeer opnieuw*.
    func naExport() async {
        let wachtteAl = Set(wachtend.values.flatMap { $0 })
        wachtOpExport.removeAll()
        await deelOpenstaande()
        let nogSteeds = wachtteAl.intersection(wachtend.values.flatMap { $0 })
        let aanTeRaken = Set(nogSteeds.flatMap { ontbrekend[$0] ?? [] }).subtracting(aangestoten)
        guard !aanTeRaken.isEmpty else { return }
        aangestoten.formUnion(aanTeRaken)
        for id in aanTeRaken {
            guard let object = try? context.existingObject(with: id) else { continue }
            do {
                try ThuisExport.raakAan(object)
            } catch {
                logger.error("Aanraken voor export mislukt: \(DeelFout.logregel(error), privacy: .public)")
            }
        }
        logger.info("\(aanTeRaken.count) onderdelen opnieuw naar iCloud gestuurd")
    }

    /// Zet Thuis-recepten, de items van de Thuis-boodschappenlijst (#39) en de Thuis-week (#41) die
    /// nog niet in de share staan erin (maakt de share zo nodig aan).
    ///
    /// Per soort een eigen aanroep: als bijvoorbeeld de boodschappen niet lukken (een recordtype dat
    /// nog niet in het iCloud-schema staat), gaan de recepten en het weekmenu gewoon door, en de
    /// melding zegt welke soort het was. Een soort die faalde, probeert Knipsel deze app-start niet
    /// vanzelf opnieuw (anders bij elke bewaarbeurt dezelfde fout); *Probeer opnieuw* kan wel.
    ///
    /// Alleen wat (met de hele graaf die `share(_:to:)` meeneemt) al naar iCloud is geëxporteerd, gaat
    /// de share in; de rest wacht rustig op de volgende export (`naExport`). Komt toch fout 1570 op
    /// `recordMetadata`, dan deelt Knipsel de objecten één voor één, raakt de probleemgevallen aan
    /// zodat ze opnieuw exporteren, en probeert die na de volgende export nog eens (max 3 keer).
    func deelOpenstaande() async {
        guard dienst.isBeschikbaar else { return }
        // Niet twee keer tegelijk (bewaarbeurt, export en het scherm kunnen elkaar kruisen): wie later
        // komt, laat de lopende ronde daarna nog één keer draaien.
        guard !aanHetDelen else {
            nogEenRonde = true
            return
        }
        aanHetDelen = true
        defer { aanHetDelen = false }
        repeat {
            nogEenRonde = false
            await deelRonde()
        } while nogEenRonde
    }

    private func deelRonde() async {
        var ietsGedeeld = false
        for soort in ThuisSoort.allCases where !mislukt.contains(soort) {
            let open = dienst.nietGedeeld(objecten(van: soort))
                .filter { (pogingen[$0] ?? 0) < ThuisExport.maxPogingen }
            let (klaar, wacht) = splitsOpExport(open)
            wachtend[soort] = wacht
            guard !klaar.isEmpty else {
                if !heeftOpgegeven(soort) { foutPerSoort[soort] = nil }
                continue
            }
            do {
                try await dienst.deel(klaar)
                if !heeftOpgegeven(soort) { foutPerSoort[soort] = nil }
                ietsGedeeld = true
            } catch  where DeelFout.isOntbrekendeRecordMetadata(error) {
                logger.info(
                    "Delen van \(soort.rawValue, privacy: .public) wacht op iCloud: \(DeelFout.logregel(error), privacy: .public); één voor één"
                )
                if klaar.count == 1 {
                    verwerkOntbrekendeMetadata(klaar[0], fout: error, soort: soort)
                } else if await deelEenVoorEen(klaar, soort: soort) {
                    ietsGedeeld = true
                }
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

    /// Welke objecten met hun hele graaf geëxporteerd zijn (klaar om te delen), en welke wachten.
    private func splitsOpExport(_ open: [NSManagedObjectID]) -> (
        klaar: [NSManagedObjectID], wacht: Set<NSManagedObjectID>
    ) {
        guard !open.isEmpty else { return ([], []) }
        var grafen: [NSManagedObjectID: Set<NSManagedObjectID>] = [:]
        for id in open {
            guard let object = try? context.existingObject(with: id) else { continue }
            grafen[id] = ThuisExport.graaf(van: object)
        }
        let geexporteerd = dienst.geexporteerd(Array(Set(grafen.values.flatMap { $0 })))
        var klaar: [NSManagedObjectID] = []
        var wacht: Set<NSManagedObjectID> = []
        for id in open {
            guard let graaf = grafen[id] else { continue }
            let mist = graaf.subtracting(geexporteerd)
            if mist.isEmpty && !wachtOpExport.contains(id) {
                klaar.append(id)
                ontbrekend[id] = nil
            } else {
                wacht.insert(id)
                if !mist.isEmpty { ontbrekend[id] = mist }
            }
        }
        return (klaar, wacht)
    }

    /// Vangnet na fout 1570 op `recordMetadata`: elk object apart, zodat één probleemgeval de rest niet
    /// tegenhoudt. Een probleemgeval wordt aangeraakt (opnieuw exporteren) en wacht op de volgende
    /// export; na `ThuisExport.maxPogingen` keer geeft Knipsel het deze app-start op en toont de melding.
    /// Een andere fout blokkeert de soort zoals altijd. Geeft `true` als er iets gedeeld is.
    private func deelEenVoorEen(_ objecten: [NSManagedObjectID], soort: ThuisSoort) async -> Bool {
        var ietsGedeeld = false
        for id in objecten {
            do {
                try await dienst.deel([id])
                ietsGedeeld = true
            } catch  where DeelFout.isOntbrekendeRecordMetadata(error) {
                verwerkOntbrekendeMetadata(id, fout: error, soort: soort)
            } catch {
                mislukt.insert(soort)
                foutPerSoort[soort] = DeelFout.melding(error, soort: soort)
                logger.error(
                    "Delen van \(soort.rawValue, privacy: .public) mislukt: \(DeelFout.logregel(error), privacy: .public)"
                )
                break
            }
        }
        return ietsGedeeld
    }

    /// Eén object faalde op `recordMetadata`: tel de poging, raak het aan en wacht op de export — of
    /// geef het na `ThuisExport.maxPogingen` keer op (dan wel een melding).
    private func verwerkOntbrekendeMetadata(_ id: NSManagedObjectID, fout: any Error, soort: ThuisSoort) {
        let poging = (pogingen[id] ?? 0) + 1
        pogingen[id] = poging
        if poging >= ThuisExport.maxPogingen {
            wachtend[soort]?.remove(id)
            foutPerSoort[soort] = DeelFout.melding(fout, soort: soort)
            logger.error("Delen van één \(soort.rawValue, privacy: .public) opgegeven na \(poging) pogingen")
        } else {
            wachtend[soort, default: []].insert(id)
            wachtOpExport.insert(id)
            raakAanMetGraaf(id)
        }
    }

    /// Het object en zijn directe onderdelen (ingrediënten, stappen, kooklog, categorieën, labels)
    /// opnieuw laten exporteren.
    private func raakAanMetGraaf(_ id: NSManagedObjectID) {
        guard let object = try? context.existingObject(with: id) else { return }
        var teDoen = [object]
        for naam in object.entity.relationshipsByName.keys {
            switch object.value(forKey: naam) {
            case let enkel as NSManagedObject: teDoen.append(enkel)
            case let set as NSSet: teDoen += set.allObjects.compactMap { $0 as? NSManagedObject }
            default: break
            }
        }
        for deel in teDoen {
            do {
                try ThuisExport.raakAan(deel)
            } catch {
                logger.error("Aanraken voor export mislukt: \(DeelFout.logregel(error), privacy: .public)")
            }
        }
    }

    /// Is er voor deze soort een object waarvoor Knipsel het na max pogingen opgaf (dan blijft de
    /// melding staan)?
    private func heeftOpgegeven(_ soort: ThuisSoort) -> Bool {
        let mogelijk = Set(objecten(van: soort))
        return pogingen.contains { $0.value >= ThuisExport.maxPogingen && mogelijk.contains($0.key) }
    }

    /// De knop bij de foutmelding: alle soorten weer proberen, ook wat eerder deze app-start faalde.
    func probeerOpnieuw() async {
        mislukt.removeAll()
        pogingen.removeAll()
        wachtOpExport.removeAll()
        aangestoten.removeAll()
        foutPerSoort.removeAll()
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
        wachtend.removeAll()
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
        wachtend.removeAll()
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
