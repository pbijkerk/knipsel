import Foundation

/// Beslist per (deel)resultaat van de spraakherkenning of er een commando uitgevoerd wordt. Puur: de
/// tijd komt van buiten, zodat debounce en stabiliteit te testen zijn.
///
/// - Een eindresultaat voert het commando direct uit.
/// - Een voorlopig (volatile) resultaat alleen als het stabiel is: hetzelfde commando in hetzelfde
///   segment gedurende `stabielNa` (via `controleer(nu:)`). Uitzondering is "stop": dat gaat meteen,
///   want het moet binnen een seconde stil zijn en een onterechte stop kost weinig.
/// - Impliciete signalen ("oké", "ja") pas bij het eindresultaat: "ja" kan het begin zijn van "ja, dat is
///   lekker".
/// - Per segment (uiting) hooguit één commando, en hetzelfde commando niet twee keer binnen `debounce`.
/// - Wat Knipsel zelf voorleest (echo die door de echo-onderdrukking glipt) telt niet; zie `Echofilter`.
struct Uitingbeslisser: Sendable {
    var herkenner: CommandoHerkenner
    /// Seconden dat een voorlopig resultaat onveranderd moet blijven.
    var stabielNa: TimeInterval = 0.5
    /// Seconden waarin hetzelfde commando niet nog eens telt.
    var debounce: TimeInterval = 1.0

    private struct Kandidaat: Sendable {
        let segment: Int
        let commando: Commando
        let sinds: TimeInterval
    }

    private var kandidaat: Kandidaat?
    private var uitgevoerdeSegmenten: Set<Int> = []
    private var laatste: (commando: Commando, tijd: TimeInterval)?
    /// Net alleen "Knipsel" gehoord: de volgende uiting tot dit tijdstip telt als met wekwoord.
    private var gewektTot: TimeInterval?

    /// Seconden na een los "Knipsel" waarin de volgende uiting erbij hoort.
    static let wekwoordGeldig: TimeInterval = 4

    init(herkenner: CommandoHerkenner) {
        self.herkenner = herkenner
    }

    /// Een resultaat van de herkenner. `voorgelezen` is de tekst die Knipsel op dit moment (of net)
    /// voorleest. Geeft het commando terug dat nu uitgevoerd moet worden.
    mutating func verwerk(
        _ tekst: String, segment: Int, definitief: Bool, nu: TimeInterval, voorgelezen: String? = nil
    ) -> Commando? {
        guard !uitgevoerdeSegmenten.contains(segment) else { return nil }
        if let voorgelezen, Echofilter.isEcho(tekst, voorgelezen: voorgelezen) {
            if kandidaat?.segment == segment { kandidaat = nil }
            return nil
        }
        if CommandoHerkenner.isAlleenWekwoord(tekst) {
            if definitief { gewektTot = nu + Self.wekwoordGeldig }
            return nil
        }
        let gewekt = gewektTot.map { nu <= $0 } ?? false
        guard let commando = herkenner.herken(gewekt ? "\(CommandoHerkenner.wekwoord) \(tekst)" : tekst) else {
            if kandidaat?.segment == segment { kandidaat = nil }
            return nil
        }
        // Stop meteen, behalve als Knipsel zelf net "stop" zegt ("Stop de ui in de pan"): dan eerst
        // zien of de zin doorgaat.
        let directeStop =
            commando == .stop
            && !(voorgelezen.map { CommandoHerkenner.woorden($0).contains("stop") } ?? false)
        if definitief || directeStop {
            if definitief { gewektTot = nil }
            return voerUit(commando, segment: segment, nu: nu)
        }
        switch commando {
        case .impliciet, .hoeveel(ingredient: nil, _):
            // Pas bij het eindresultaat: "ja" kan "ja, dat is lekker" worden, en "hoeveel bo…" is nog
            // geen ingrediënt.
            kandidaat = nil
            return nil
        default:
            break
        }
        if let kandidaat, kandidaat.segment == segment, kandidaat.commando == commando { return nil }
        kandidaat = Kandidaat(segment: segment, commando: commando, sinds: nu)
        return nil
    }

    /// Periodiek aanroepen (± 5× per seconde): een voorlopig resultaat dat lang genoeg gelijk bleef.
    mutating func controleer(nu: TimeInterval) -> Commando? {
        guard let kandidaat, nu - kandidaat.sinds >= stabielNa else { return nil }
        return voerUit(kandidaat.commando, segment: kandidaat.segment, nu: nu)
    }

    private mutating func voerUit(_ commando: Commando, segment: Int, nu: TimeInterval) -> Commando? {
        kandidaat = nil
        uitgevoerdeSegmenten.insert(segment)
        if uitgevoerdeSegmenten.count > 200 { uitgevoerdeSegmenten = [segment] }
        if let laatste, laatste.commando == commando, nu - laatste.tijd < debounce { return nil }
        laatste = (commando, nu)
        return commando
    }
}

/// Nummert de uitingen van de herkenner: alle voorlopige resultaten tot en met het eindresultaat zijn
/// één segment. Niet het begin van het tijdbereik gebruiken: het eindresultaat knipt de stilte vooraf
/// weg en krijgt dan een ander begin dan zijn voorlopige resultaten, waardoor een commando twee keer
/// werd uitgevoerd (eerst voorlopig, ± 2 s later nog eens bij het eindresultaat).
struct Uitingteller: Sendable {
    private var volgende = 0

    mutating func segment(definitief: Bool) -> Int {
        defer { if definitief { volgende += 1 } }
        return volgende
    }
}

/// Is een transcript (vrijwel) een stuk van wat Knipsel zelf voorleest? Vangnet naast de
/// echo-onderdrukking van de microfoon: anders hoort Knipsel bij "Stap 2." zichzelf "stap twee" zeggen.
///
/// "Stop", "stil" en "pauze" tellen nooit als echo: stoppen moet altijd kunnen, ook als de stap zelf
/// "stop de ui in de pan" zegt.
enum Echofilter {
    static func isEcho(_ transcript: String, voorgelezen: String) -> Bool {
        var gehoord = CommandoHerkenner.woorden(transcript).map(normaal)
        _ = CommandoHerkenner.haalWekwoordWeg(&gehoord)
        guard !gehoord.isEmpty else { return false }
        if gehoord.count == 1, altijdDoorlaten.contains(gehoord[0]) { return false }
        let gelezen = CommandoHerkenner.woorden(voorgelezen).map(normaal)
        guard gelezen.count >= gehoord.count else { return false }
        // Bij langere stukken mag de herkenner een woord anders verstaan.
        let toegestaan = gehoord.count >= 4 ? 1 : 0
        for start in 0...(gelezen.count - gehoord.count) {
            var fouten = 0
            for (i, woord) in gehoord.enumerated() where woord != gelezen[start + i] {
                fouten += 1
                if fouten > toegestaan { break }
            }
            if fouten <= toegestaan { return true }
        }
        return false
    }

    private static let altijdDoorlaten: Set<String> = ["stop", "stil", "pauze", "stoppen"]

    /// "twee" en "2" zijn hetzelfde woord.
    private static func normaal(_ woord: String) -> String {
        CommandoHerkenner.getal(woord).map(String.init) ?? woord
    }
}
