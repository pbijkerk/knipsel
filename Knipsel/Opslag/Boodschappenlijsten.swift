import CoreData
import Foundation

/// De eigen boodschappenlijst in Knipsel (#39): één lijst per kookboek. Nieuwe items komen via
/// `Kookboeken.herstel` in de store van hun kookboek (Thuis: dezelfde zone als de Thuis-recepten);
/// `ThuisDelen` zet ze daarna in de share.
@MainActor
enum Boodschappenlijsten {
    // MARK: - Lezen

    /// Alle items van één lijst: open op afdeling en volgorde, afgevinkt als laatste.
    static func items(in kookboek: Kookboek, context: NSManagedObjectContext) -> [BoodschappenItem] {
        let verzoek = BoodschappenItem.verzoek()
        verzoek.predicate = NSPredicate(format: "kookboek == %@", kookboek.rawValue)
        verzoek.sortDescriptors = sortering
        return ((try? context.fetch(verzoek)) ?? []).filter { !$0.isDeleted }
    }

    static let sortering = [
        NSSortDescriptor(key: "volgorde", ascending: true), NSSortDescriptor(key: "aangemaaktOp", ascending: true),
    ]

    /// Aantal open items (badge op 🛒); zonder kookboek beide lijsten samen.
    static func aantalOpen(in context: NSManagedObjectContext, kookboek: Kookboek? = nil) -> Int {
        let verzoek = BoodschappenItem.verzoek()
        verzoek.predicate = predicaatOpen(kookboek: kookboek)
        return (try? context.count(for: verzoek)) ?? 0
    }

    static func predicaatOpen(kookboek: Kookboek?) -> NSPredicate {
        guard let kookboek else { return NSPredicate(format: "afgevinkt == NO") }
        return NSPredicate(format: "afgevinkt == NO AND kookboek == %@", kookboek.rawValue)
    }

    /// Open items per afdeling, in winkelvolgorde; lege afdelingen ontbreken.
    static func secties(_ items: [BoodschappenItem]) -> [(afdeling: Afdeling, items: [BoodschappenItem])] {
        let open = items.filter { !$0.afgevinkt && !$0.isDeleted }
        let perAfdeling = Dictionary(grouping: open, by: \.afdelingWaarde)
        return Afdeling.allCases.compactMap { afdeling in
            guard let items = perAfdeling[afdeling], !items.isEmpty else { return nil }
            return (afdeling, items.sorted(by: volgordeEerst))
        }
    }

    /// Afgevinkt, het laatst afgevinkte bovenaan.
    static func afgevinkt(_ items: [BoodschappenItem]) -> [BoodschappenItem] {
        items.filter { $0.afgevinkt && !$0.isDeleted }.sorted {
            ($0.afgevinktOp ?? .distantPast) > ($1.afgevinktOp ?? .distantPast)
        }
    }

    private static func volgordeEerst(_ a: BoodschappenItem, _ b: BoodschappenItem) -> Bool {
        if a.volgorde != b.volgorde { return a.volgorde < b.volgorde }
        return (a.aangemaaktOp ?? .distantPast) < (b.aangemaaktOp ?? .distantPast)
    }

    /// Delen als tekst: per afdeling, alleen open items.
    static func tekst(_ items: [BoodschappenItem], kookboek: Kookboek) -> String {
        let titel = kookboek == .thuis ? "Boodschappen · Thuis" : "Boodschappen"
        return BoodschappenLijst.tekst(
            titel: titel, perAfdeling: secties(items).map { ($0.afdeling, $0.items.map(\.tekstOfNaam)) })
    }

    // MARK: - Toevoegen

    /// Zet regels op de lijst van `kookboek`; gelijke open items worden opgeteld en krijgen de
    /// recepttitel erbij in hun herkomst. Afgevinkte items tellen niet mee: dan een nieuw item.
    /// Bewaart.
    @discardableResult
    static func zetOpLijst(
        _ regels: [LijstRegel], herkomst: String?, kookboek: Kookboek, context: NSManagedObjectContext,
        geheugen: AfdelingGeheugen = .laad()
    ) throws -> Boodschappenresultaat {
        var resultaat = Boodschappenresultaat()
        var open = items(in: kookboek, context: context).filter { !$0.afgevinkt }
        var volgende = (open.map(\.volgorde).max() ?? 0) + 1
        for regel in regels where !regel.tekst.isEmpty || !regel.naam.isEmpty {
            if let (item, samen) = open.lazy.compactMap({ item in
                BoodschappenLijst.samengevoegd(lijstRegel(item), regel).map { (item, $0) }
            }).first {
                zet(samen, op: item)
                item.herkomst = BoodschappenLijst.herkomst(item.herkomst, plus: herkomst)
                resultaat.bijgewerkt += 1
            } else {
                let item = BoodschappenItem(context: context)
                item.kookboek = kookboek.rawValue
                zet(regel, op: item)
                item.herkomst = BoodschappenLijst.herkomst(nil, plus: herkomst)
                item.afdeling =
                    geheugen.afdeling(naam: regel.naam, sleutel: regel.sleutel, eenheid: regel.eenheid).rawValue
                item.volgorde = volgende
                volgende += 1
                open.append(item)
                resultaat.toegevoegd += 1
            }
        }
        try context.bewaarIndienNodig()
        return resultaat
    }

    /// "＋ Item": vrije tekst, geparsed ("2 uien", "wc-papier").
    @discardableResult
    static func voegToe(
        tekst: String, kookboek: Kookboek, context: NSManagedObjectContext, geheugen: AfdelingGeheugen = .laad()
    ) throws -> Boodschappenresultaat {
        guard let regel = LijstRegel(vrijeTekst: tekst) else { return Boodschappenresultaat() }
        return try zetOpLijst([regel], herkomst: nil, kookboek: kookboek, context: context, geheugen: geheugen)
    }

    // MARK: - Wijzigen

    static func vink(_ item: BoodschappenItem, af: Bool, op datum: Date = .now) throws {
        item.afgevinkt = af
        item.afgevinktOp = af ? datum : nil
        try item.managedObjectContext?.bewaarIndienNodig()
    }

    static func verwijder(_ item: BoodschappenItem) throws {
        guard let context = item.managedObjectContext else { return }
        context.delete(item)
        try context.bewaarIndienNodig()
    }

    @discardableResult
    static func wisAfgevinkt(in kookboek: Kookboek, context: NSManagedObjectContext) throws -> Int {
        let weg = items(in: kookboek, context: context).filter(\.afgevinkt)
        weg.forEach(context.delete)
        try context.bewaarIndienNodig()
        return weg.count
    }

    /// Bewerken: naam, hoeveelheid, eenheid en afdeling. Een andere afdeling onthoudt Knipsel voor dit
    /// ingrediënt (ook voor de volgende keer) en geldt meteen voor gelijke open items op de lijst.
    static func wijzig(
        _ item: BoodschappenItem, naam: String, hoeveelheid: Double?, eenheid: String?, afdeling: Afdeling,
        geheugen: inout AfdelingGeheugen, defaults: UserDefaults = .standard
    ) throws {
        let naam = naam.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !naam.isEmpty, let context = item.managedObjectContext else { return }
        let eenheid = eenheid?.trimmingCharacters(in: .whitespaces).lowercased()
        let regel = LijstRegel(naam: naam, hoeveelheid: hoeveelheid, eenheid: eenheid?.isEmpty == true ? nil : eenheid)
        zet(regel, op: item)
        if afdeling != item.afdelingWaarde || geheugen.keuzes[regel.sleutel] != nil {
            geheugen.kies(afdeling, voor: regel.sleutel)
            geheugen.bewaar(in: defaults)
            for ander in items(in: item.kookboekWaarde, context: context)
            where !ander.afgevinkt && ander.sleutel == regel.sleutel {
                ander.afdeling = afdeling.rawValue
            }
        }
        item.afdeling = afdeling.rawValue
        try context.bewaarIndienNodig()
    }

    /// Afdelingen die Claude net gaf: geldt voor open items die nog in Overig staan.
    static func pasToe(_ afdelingen: [String: Afdeling], context: NSManagedObjectContext) throws {
        guard !afdelingen.isEmpty else { return }
        let verzoek = BoodschappenItem.verzoek()
        verzoek.predicate = NSPredicate(format: "afgevinkt == NO")
        for item in (try? context.fetch(verzoek)) ?? [] where item.afdelingWaarde == .overig {
            if let sleutel = item.sleutel, let afdeling = afdelingen[sleutel] { item.afdeling = afdeling.rawValue }
        }
        try context.bewaarIndienNodig()
    }

    /// Bij stoppen met delen of vertrekken: de open items naar de andere lijst (opgeteld waar het kan).
    /// `verwijderBron`: de originelen weg (stoppen) of laten staan (die verdwijnen met de share).
    static func verplaatsAlles(
        van bron: Kookboek, naar doel: Kookboek, verwijderBron: Bool, context: NSManagedObjectContext
    ) throws {
        let alle = items(in: bron, context: context)
        let open = alle.filter { !$0.afgevinkt }
        var geheugen = AfdelingGeheugen()
        for item in open {
            // De afdeling gaat mee, ook een eigen keuze.
            if let sleutel = item.sleutel { geheugen.keuzes[sleutel] = item.afdelingWaarde }
            try zetOpLijst(
                [lijstRegel(item)], herkomst: item.herkomst, kookboek: doel, context: context, geheugen: geheugen)
        }
        if verwijderBron { alle.forEach(context.delete) }
        try context.bewaarIndienNodig()
    }

    // MARK: - Omzetten

    static func lijstRegel(_ item: BoodschappenItem) -> LijstRegel {
        let naam = item.naam ?? item.tekstOfNaam
        return LijstRegel(
            naam: naam, sleutel: item.sleutel ?? BoodschappenLijst.sleutel(naam),
            hoeveelheid: item.hoeveelheid?.doubleValue,
            eenheid: item.eenheid, tekst: item.tekstOfNaam)
    }

    /// Voor "Ook naar Herinneringen".
    static func regel(_ item: BoodschappenItem) -> BoodschappenRegel {
        let lijst = lijstRegel(item)
        return BoodschappenRegel(
            id: item.uuid?.uuidString ?? lijst.sleutel, sleutel: lijst.sleutel, naam: lijst.naam,
            hoeveelheid: lijst.hoeveelheid, hoeveelheidTot: nil, eenheid: lijst.eenheid, tekst: lijst.tekst,
            meestalInHuis: false)
    }

    private static func zet(_ regel: LijstRegel, op item: BoodschappenItem) {
        item.naam = regel.naam
        item.sleutel = regel.sleutel
        item.hoeveelheid = regel.hoeveelheid.map { NSNumber(value: $0) }
        item.eenheid = regel.eenheid
        item.tekst = regel.tekst
    }
}

/// Onbekende namen op de lijst op de achtergrond laten indelen door Claude (alleen met een eigen
/// sleutel, B10). Alleen de naam gaat naar Anthropic; het antwoord komt in `AfdelingGeheugen`, dus
/// elke naam hooguit één keer. Zonder sleutel blijft het Overig.
@MainActor
final class OnbekendeAfdelingen {
    static let gedeeld = OnbekendeAfdelingen()

    private let claude: ClaudeAfdelingen
    private let defaults: UserDefaults
    private var bezig = false

    init(
        claude: ClaudeAfdelingen = ClaudeAfdelingen(sleutel: {
            KeychainService.load(forKey: AppConfiguratie.sleutelClaude)
        }),
        defaults: UserDefaults = .standard
    ) {
        self.claude = claude
        self.defaults = defaults
    }

    /// De open items in Overig waarvan niemand de afdeling weet.
    static func onbekend(in context: NSManagedObjectContext, geheugen: AfdelingGeheugen) -> [String: String] {
        let verzoek = BoodschappenItem.verzoek()
        verzoek.predicate = NSPredicate(format: "afgevinkt == NO")
        var namen: [String: String] = [:]
        for item in (try? context.fetch(verzoek)) ?? [] where item.afdelingWaarde == .overig {
            guard let sleutel = item.sleutel, !sleutel.isEmpty else { continue }
            let naam = item.naam ?? item.tekstOfNaam
            if geheugen.isOnbekend(naam: naam, sleutel: sleutel) { namen[naam] = sleutel }
        }
        return namen
    }

    func deelIn(context: NSManagedObjectContext) async {
        guard !bezig else { return }
        let geheugen = AfdelingGeheugen.laad(uit: defaults)
        let namen = Self.onbekend(in: context, geheugen: geheugen)
        guard !namen.isEmpty else { return }
        bezig = true
        defer { bezig = false }
        let antwoord = await claude.deelIn(namen.keys.sorted())
        guard !antwoord.isEmpty else { return }
        var bijgewerkt = AfdelingGeheugen.laad(uit: defaults)
        var perSleutel: [String: Afdeling] = [:]
        for (naam, afdeling) in antwoord {
            guard let sleutel = namen[naam] else { continue }
            bijgewerkt.claude[sleutel] = afdeling
            perSleutel[sleutel] = afdeling
        }
        bijgewerkt.bewaar(in: defaults)
        try? Boodschappenlijsten.pasToe(perSleutel, context: context)
    }
}
