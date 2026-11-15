import Foundation
import Observation
import OSLog

/// Eén kooktimer: "Stap 3: laat 20 minuten zachtjes koken" van de pompoensoep.
struct KookTimer: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    /// "Stap 3: laat 20 minuten zachtjes koken".
    var naam: String
    /// "Stap 3" (op een chip en in het Dynamic Island).
    var kort: String
    var recept: String
    /// Bij welke stap (0 = stap 1) hij gezet is; `nil` voor een losse timer (Siri, "timer 5 minuten").
    var stapIndex: Int?
    /// De ingestelde tijd in seconden.
    var totaal: Int
    /// Zolang hij loopt: wanneer hij afgaat.
    var eindigtOp: Date?
    /// Gepauzeerd: hoeveel er nog over was.
    var resterendBijPauze: TimeInterval?
    var gaatAf = false
    /// Zonder toestemming voor alarmen loopt de timer alleen in de app (geen AlarmKit).
    var isLokaal = false
    var gestartOp: Date

    var isGepauzeerd: Bool { eindigtOp == nil && !gaatAf }

    /// "Pompoensoep · Stap 3: laat 20 minuten zachtjes koken": de titel van het alarm.
    var titel: String { recept.isEmpty ? naam : "\(recept) · \(naam)" }

    func resterend(op nu: Date) -> TimeInterval {
        if gaatAf { return 0 }
        if let eindigtOp { return max(0, eindigtOp.timeIntervalSince(nu)) }
        return resterendBijPauze ?? 0
    }
}

/// Wat AlarmKit van een timer weet.
struct WekkerStand: Equatable, Sendable {
    enum Toestand: Equatable, Sendable {
        case gepland
        case loopt
        case gepauzeerd
        case gaatAf
    }

    let id: UUID
    let toestand: Toestand
}

/// De alarmklok achter de timers: in de app AlarmKit (`AlarmKitWekker`), in tests een nep.
@MainActor
protocol Wekker: AnyObject {
    /// Vraagt (zo nodig) toestemming; `true` als alarmen mogen.
    func vraagToestemming() async -> Bool
    func plan(_ timer: KookTimer) async throws
    func pauzeer(_ id: UUID) throws
    func hervat(_ id: UUID) throws
    /// Haalt een (lopende of gepauzeerde) timer weg.
    func annuleer(_ id: UUID) throws
    /// Stopt een afgaand alarm.
    func stop(_ id: UUID) throws
    /// De timers die de alarmklok nu kent.
    func huidige() -> [WekkerStand]
    /// Elke wijziging, ook van buiten de app (knoppen op het vergrendelscherm, het alarm zelf).
    func wijzigingen() -> AsyncStream<[WekkerStand]>
}

enum TimerFout: Error, Equatable {
    case teVeel
}

/// Kooktimers met AlarmKit (K11): meerdere tegelijk, elk met de naam van de stap, ook als het scherm
/// op slot zit of het toestel op stil staat. Houdt een eigen lijst bij (naam, eindtijd), want AlarmKit
/// geeft alleen id en toestand terug; die lijst blijft bewaard zodat de timers na het herstarten van
/// de app weer in beeld komen. Pauzeren, hervatten en stoppen kan ook vanaf het vergrendelscherm;
/// `wijzigingen()` houdt de lijst dan gelijk.
///
/// Zonder toestemming voor alarmen loopt een timer alleen in de app (`isLokaal`): `tik(nu:)` laat hem
/// aflopen en `naAfloop` laat Knipsel het zeggen.
@MainActor
@Observable
final class TimerService {
    static let gedeeld = TimerService(wekker: AlarmKitWekker(), standaarden: .standard)

    /// Op volgorde van aflopen: eerst wat afgaat, dan wat het eerst klaar is, dan gepauzeerd.
    private(set) var timers: [KookTimer] = []
    /// Alarmen mogen niet: de timers lopen alleen in de app.
    private(set) var alleenInApp = false

    /// Een lokale timer is afgelopen (zonder AlarmKit), of een AlarmKit-timer gaat af.
    @ObservationIgnored var naAfloop: ((KookTimer) -> Void)?

    @ObservationIgnored private let wekker: any Wekker
    @ObservationIgnored private let standaarden: UserDefaults?
    @ObservationIgnored private let klok: () -> Date
    @ObservationIgnored private var luisterTaak: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.peterbijkerk.knipsel", category: "timers")

    static let sleutel = "kookTimers"
    /// Zo lang na het zetten telt een update zonder deze timer nog niet als "weg" (AlarmKit kan
    /// even achterlopen).
    static let aanloop: TimeInterval = 2

    init(wekker: any Wekker, standaarden: UserDefaults? = nil, klok: @escaping () -> Date = Date.init) {
        self.wekker = wekker
        self.standaarden = standaarden
        self.klok = klok
        if let data = standaarden?.data(forKey: Self.sleutel),
            let bewaard = try? JSONDecoder().decode([KookTimer].self, from: data)
        {
            timers = bewaard.filter { !$0.isLokaal }
        }
    }

    // MARK: - Luisteren

    /// Begint met luisteren naar AlarmKit (eenmalig) en ruimt timers op die AlarmKit niet meer kent.
    func begin() {
        guard luisterTaak == nil else { return }
        verwerk(wekker.huidige())
        let stroom = wekker.wijzigingen()
        luisterTaak = Task { [weak self] in
            for await standen in stroom {
                self?.verwerk(standen)
            }
        }
    }

    /// De stand van AlarmKit overnemen: weg = gestopt of afgelopen, gepauzeerd of verder via het
    /// vergrendelscherm, afgaand.
    func verwerk(_ standen: [WekkerStand]) {
        let nu = klok()
        let perID = Dictionary(standen.map { ($0.id, $0.toestand) }, uniquingKeysWith: { a, _ in a })
        var nieuw: [KookTimer] = []
        var afgegaan: [KookTimer] = []
        for var timer in timers {
            guard !timer.isLokaal else {
                nieuw.append(timer)
                continue
            }
            guard let toestand = perID[timer.id] else {
                // Weg bij AlarmKit: gestopt, geannuleerd of afgelopen. Net gezet: nog even wachten.
                if nu.timeIntervalSince(timer.gestartOp) < Self.aanloop { nieuw.append(timer) }
                continue
            }
            switch toestand {
            case .gepland, .loopt:
                if timer.gaatAf {
                    // "Nog 1 min": AlarmKit telt de 60 s na het alarm af.
                    timer.gaatAf = false
                    timer.eindigtOp = nu.addingTimeInterval(AlarmKitWekker.nogEenMinuut)
                } else if timer.eindigtOp == nil {
                    timer.eindigtOp = nu.addingTimeInterval(timer.resterendBijPauze ?? 0)
                    timer.resterendBijPauze = nil
                }
            case .gepauzeerd:
                if let eindigtOp = timer.eindigtOp {
                    timer.resterendBijPauze = max(0, eindigtOp.timeIntervalSince(nu))
                    timer.eindigtOp = nil
                }
            case .gaatAf:
                if !timer.gaatAf { afgegaan.append(timer) }
                timer.gaatAf = true
                timer.eindigtOp = nil
                timer.resterendBijPauze = nil
            }
            nieuw.append(timer)
        }
        zet(nieuw)
        for timer in afgegaan { naAfloop?(timer) }
    }

    // MARK: - Bediening

    /// Zet een timer. Vraagt de eerste keer toestemming voor alarmen; zonder toestemming loopt hij
    /// alleen in de app. `nil` als AlarmKit hem weigert (te veel alarmen).
    @discardableResult
    func start(seconden: Int, naam: String, kort: String, recept: String, stapIndex: Int? = nil) async -> KookTimer? {
        guard seconden > 0 else { return nil }
        begin()
        let nu = klok()
        var timer = KookTimer(
            id: UUID(), naam: naam, kort: kort, recept: recept, stapIndex: stapIndex, totaal: seconden,
            eindigtOp: nu.addingTimeInterval(TimeInterval(seconden)), gestartOp: nu)
        if await wekker.vraagToestemming() {
            alleenInApp = false
            do {
                try await wekker.plan(timer)
            } catch {
                log.error("Timer zetten mislukt: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        } else {
            alleenInApp = true
            timer.isLokaal = true
        }
        zet(timers + [timer])
        return timer
    }

    func pauzeer(_ id: UUID) {
        guard var timer = timer(id), let eindigtOp = timer.eindigtOp else { return }
        if !timer.isLokaal { probeer { try wekker.pauzeer(id) } }
        timer.resterendBijPauze = max(0, eindigtOp.timeIntervalSince(klok()))
        timer.eindigtOp = nil
        vervang(timer)
    }

    func hervat(_ id: UUID) {
        guard var timer = timer(id), timer.isGepauzeerd else { return }
        if !timer.isLokaal { probeer { try wekker.hervat(id) } }
        timer.eindigtOp = klok().addingTimeInterval(timer.resterendBijPauze ?? 0)
        timer.resterendBijPauze = nil
        vervang(timer)
    }

    /// Weg ermee: een lopende of gepauzeerde timer annuleren, een afgaand alarm stoppen.
    func stop(_ id: UUID) {
        guard let timer = timer(id) else { return }
        if !timer.isLokaal {
            probeer { try timer.gaatAf ? wekker.stop(id) : wekker.annuleer(id) }
        }
        zet(timers.filter { $0.id != id })
    }

    /// Alle timers weg (bijvoorbeeld "stop alle timers").
    func stopAlles() {
        for timer in timers { stop(timer.id) }
    }

    /// Voor de app zonder AlarmKit: elke seconde. Laat lokale timers aflopen.
    func tik(nu: Date? = nil) {
        let nu = nu ?? klok()
        var afgelopen: [KookTimer] = []
        let nieuw = timers.map { timer in
            guard timer.isLokaal, !timer.gaatAf, let eindigtOp = timer.eindigtOp, eindigtOp <= nu else { return timer }
            var klaar = timer
            klaar.gaatAf = true
            klaar.eindigtOp = nil
            afgelopen.append(klaar)
            return klaar
        }
        guard !afgelopen.isEmpty else { return }
        zet(nieuw)
        for timer in afgelopen { naAfloop?(timer) }
    }

    // MARK: - Opvragen

    func timer(_ id: UUID) -> KookTimer? { timers.first { $0.id == id } }

    /// De klok van de timers (in tests een nepklok).
    func nu() -> Date { klok() }

    /// De eerste die afgaat of afloopt (wat "stop de timer" en "hoe lang nog?" bedoelen).
    var eerstvolgende: KookTimer? { timers.first }

    /// Loopt er al een timer voor deze stap van dit recept?
    func heeftTimer(recept: String, stapIndex: Int) -> Bool {
        timers.contains { $0.recept == recept && $0.stapIndex == stapIndex }
    }

    // MARK: - Intern

    private func vervang(_ timer: KookTimer) {
        zet(timers.map { $0.id == timer.id ? timer : $0 })
    }

    private func zet(_ nieuw: [KookTimer]) {
        let gesorteerd = Self.gesorteerd(nieuw)
        guard gesorteerd != timers else { return }
        timers = gesorteerd
        if let standaarden {
            standaarden.set(try? JSONEncoder().encode(gesorteerd.filter { !$0.isLokaal }), forKey: Self.sleutel)
        }
    }

    private func probeer(_ actie: () throws -> Void) {
        do { try actie() } catch {
            log.error("Timer bijwerken mislukt: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Afgaand eerst, dan lopend op eindtijd, dan gepauzeerd op resterende tijd.
    nonisolated static func gesorteerd(_ timers: [KookTimer]) -> [KookTimer] {
        func sleutel(_ timer: KookTimer) -> (Int, Double) {
            if timer.gaatAf { return (0, timer.gestartOp.timeIntervalSinceReferenceDate) }
            if let eindigtOp = timer.eindigtOp { return (1, eindigtOp.timeIntervalSinceReferenceDate) }
            return (2, timer.resterendBijPauze ?? 0)
        }
        return timers.sorted { sleutel($0) < sleutel($1) }
    }
}

// MARK: - Naam en zinnen

/// De naam van een timer uit de staptekst: het zinsdeel met de tijd erin. "Schenk de bouillon erbij en
/// laat 20 minuten zachtjes koken." → "Stap 3: laat 20 minuten zachtjes koken".
enum Timernaam {
    static let maximaleLengte = 44

    static func naam(stapNummer: Int?, tekst: String, tijd: Tijdvermelding?) -> String {
        let kop = stapNummer.map { "Stap \($0)" } ?? "Timer"
        guard let tijd else { return kop }
        let deel = zinsdeel(rond: tijd.bereik, in: tekst)
        return deel.isEmpty ? kop : "\(kop): \(deel)"
    }

    static func kort(stapNummer: Int?) -> String {
        stapNummer.map { "Stap \($0)" } ?? "Timer"
    }

    /// Het zinsdeel (tussen . ; : , en " en ") waarin de tijd staat, ingekort op woordgrens.
    static func zinsdeel(rond bereik: Range<String.Index>, in tekst: String) -> String {
        let ervoor = tekst[..<bereik.lowerBound]
        let erna = tekst[bereik.upperBound...]
        let scheiding = #"[.;:!?,]\s|\s(?:en|daarna|dan)\s|[.;!?]$"#
        var begin = tekst.startIndex
        if let laatste = ervoor.ranges(of: try! Regex(scheiding)).last { begin = laatste.upperBound }
        var einde = tekst.endIndex
        if let eerste = erna.firstRange(of: try! Regex(scheiding)) { einde = eerste.lowerBound }
        var deel = String(tekst[begin..<einde]).trimmingCharacters(
            in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if deel.count > maximaleLengte {
            var kort = ""
            for woord in deel.split(separator: " ") {
                if kort.count + woord.count + 1 > maximaleLengte - 1 { break }
                kort += kort.isEmpty ? String(woord) : " " + woord
            }
            deel = kort + "…"
        }
        guard let eerste = deel.first else { return deel }
        return eerste.lowercased() + deel.dropFirst()
    }
}

/// Wat Knipsel zegt over timers.
enum Timerzinnen {
    static func vraag(seconden: Int) -> String {
        "Zal ik een timer van \(Tijdweergave.gesproken(seconden)) zetten?"
    }

    static func gezet(_ timer: KookTimer) -> String {
        "Timer van \(Tijdweergave.gesproken(timer.totaal)) loopt."
    }

    static let geenTimer = "Er loopt geen timer."
    static let geenTijdInStap = "Deze stap noemt geen tijd. Zeg bijvoorbeeld: timer tien minuten."

    static func afgelopen(_ timer: KookTimer) -> String {
        "De timer van \(timer.kort.lowercased()) is klaar."
    }

    /// "Stap 3: nog 12 minuten." voor elke timer, de eerstvolgende eerst.
    static func hoeLangNog(_ timers: [KookTimer], nu: Date) -> String {
        guard !timers.isEmpty else { return geenTimer }
        return timers.map { timer in
            if timer.gaatAf { return "\(timer.kort): klaar." }
            let rest = Tijdweergave.resterendGesproken(timer.resterend(op: nu))
            return timer.isGepauzeerd ? "\(timer.kort): gepauzeerd, nog \(rest)." : "\(timer.kort): nog \(rest)."
        }.joined(separator: " ")
    }
}

/// Een timer zetten vanuit de kookmodus (knop, spraak, Siri): met de naam van recept en stap.
@MainActor
enum KookTimers {
    @discardableResult
    static func start(
        seconden: Int, stap: KookStap?, tijd: Tijdvermelding?, in sessie: KookSessie?, timers: TimerService
    ) async -> KookTimer? {
        let nummer = stap.map { $0.id + 1 }
        let naam =
            stap == nil
            ? "Timer \(Tijdweergave.kort(seconden))"
            : Timernaam.naam(stapNummer: nummer, tekst: stap?.tekst ?? "", tijd: tijd)
        return await timers.start(
            seconden: seconden, naam: naam, kort: Timernaam.kort(stapNummer: nummer), recept: sessie?.titel ?? "",
            stapIndex: stap?.id)
    }
}
