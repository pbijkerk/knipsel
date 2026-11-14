import AVFoundation
import Foundation

/// Iets dat tekst hardop uitspreekt. De app gebruikt `SysteemSpreker` (AVSpeechSynthesizer); tests
/// een nep-spreker die alleen bijhoudt wat er gezegd en gestopt is.
@MainActor
protocol Spreker: AnyObject {
    /// Spreekt `tekst` uit met de stem (`identifier`, `nil` = de beste Nederlandse) en het tempo
    /// (0,8–1,2 × normaal). Wat er nog gesproken werd, stopt eerst.
    func spreek(_ tekst: String, stem: String?, tempo: Double)
    /// Stopt direct, ook midden in een woord.
    func stop()
    func pauzeer()
    func hervat()
    /// Wordt aangeroepen als de laatste uitspraak helemaal is uitgesproken (niet na `stop()`).
    var klaar: (() -> Void)? { get set }
}

// MARK: - Stemmen

/// Een geïnstalleerde stem, los van AVFoundation zodat de keuze testbaar is.
struct Stem: Identifiable, Equatable, Sendable {
    enum Kwaliteit: Int, Comparable, Sendable {
        case standaard = 1
        case verbeterd = 2
        case premium = 3

        static func < (a: Kwaliteit, b: Kwaliteit) -> Bool { a.rawValue < b.rawValue }

        var naam: String {
            switch self {
            case .standaard: "standaard"
            case .verbeterd: "verbeterd"
            case .premium: "premium"
            }
        }
    }

    /// `AVSpeechSynthesisVoice.identifier`.
    let id: String
    let naam: String
    /// "nl-NL" of "nl-BE".
    let taal: String
    let kwaliteit: Kwaliteit

    /// "Xander (verbeterd)", met "België" voor een Vlaamse stem.
    var omschrijving: String {
        let land = taal == "nl-BE" ? ", België" : ""
        return "\(naam) (\(kwaliteit.naam)\(land))"
    }
}

/// Welke stem leest voor? De eigen keuze als die nog geïnstalleerd is; anders de beste Nederlandse:
/// eerst nl-NL, dan nl-BE, en binnen een taal premium > verbeterd > standaard.
enum Stemkeuze {
    static let talen = ["nl-NL", "nl-BE"]

    /// Alleen Nederlandse stemmen, beste eerst.
    static func gesorteerd(_ stemmen: [Stem]) -> [Stem] {
        stemmen.filter { talen.contains($0.taal) }.sorted { a, b in
            let taalA = talen.firstIndex(of: a.taal) ?? talen.count
            let taalB = talen.firstIndex(of: b.taal) ?? talen.count
            if taalA != taalB { return taalA < taalB }
            if a.kwaliteit != b.kwaliteit { return a.kwaliteit > b.kwaliteit }
            return a.naam.localizedStandardCompare(b.naam) == .orderedAscending
        }
    }

    static func kies(uit stemmen: [Stem], voorkeur: String?) -> Stem? {
        let nederlands = gesorteerd(stemmen)
        if let voorkeur, let gekozen = nederlands.first(where: { $0.id == voorkeur }) { return gekozen }
        return nederlands.first
    }

    /// De Nederlandse stemmen op dit toestel; zonder persoonlijke en grappige stemmen.
    static func geinstalleerd() -> [Stem] {
        gesorteerd(
            AVSpeechSynthesisVoice.speechVoices().compactMap { stem in
                guard talen.contains(stem.language), !stem.voiceTraits.contains(.isNoveltyVoice),
                    !stem.voiceTraits.contains(.isPersonalVoice)
                else { return nil }
                let kwaliteit: Stem.Kwaliteit =
                    switch stem.quality {
                    case .premium: .premium
                    case .enhanced: .verbeterd
                    default: .standaard
                    }
                return Stem(id: stem.identifier, naam: stem.name, taal: stem.language, kwaliteit: kwaliteit)
            })
    }

    /// Is er al een betere dan de standaardstem? Zo niet, dan wijst Knipsel op het downloaden.
    static func heeftVerbeterdeStem(_ stemmen: [Stem]) -> Bool {
        stemmen.contains { $0.kwaliteit > .standaard }
    }
}

// MARK: - Tempo

/// Spreektempo als factor van normaal (0,8×–1,2×), omgezet naar de `rate` van AVSpeechUtterance.
enum Voorleestempo {
    static let minimum = 0.8
    static let maximum = 1.2
    static let standaard = 1.0

    static func begrensd(_ factor: Double) -> Double {
        min(maximum, max(minimum, factor))
    }

    /// 1,0× = `AVSpeechUtteranceDefaultSpeechRate`; de schaal van `rate` is lineair genoeg rond
    /// het midden om de factor er direct mee te vermenigvuldigen.
    static func snelheid(
        _ factor: Double, normaal: Float = AVSpeechUtteranceDefaultSpeechRate,
        minimaal: Float = AVSpeechUtteranceMinimumSpeechRate, maximaal: Float = AVSpeechUtteranceMaximumSpeechRate
    ) -> Float {
        min(maximaal, max(minimaal, normaal * Float(begrensd(factor))))
    }

    /// "1,1×".
    static func label(_ factor: Double) -> String {
        let tekst = begrensd(factor).formatted(
            .number.precision(.fractionLength(1)).locale(Locale(identifier: "nl_NL")))
        return "\(tekst)×"
    }
}

// MARK: - Echte spraak

/// Spreekt met `AVSpeechSynthesizer`. De audiosessie gaat alleen aan tijdens het spreken:
/// `.playback` + `.spokenAudio` met `.duckOthers` (muziek gaat zachter, niet uit) en
/// bewust zonder `.interruptSpokenAudioAndMixWithOthers` (die laat podcasts pauzeren i.p.v. zachter spelen); daarna uit met `.notifyOthersOnDeactivation`, zodat
/// muziek weer op volume komt.
@MainActor
final class SysteemSpreker: NSObject, Spreker {
    var klaar: (() -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    /// De uitspraak die nu loopt; een melding over een eerdere (gestopte) wordt genegeerd.
    private var huidige: ObjectIdentifier?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func spreek(_ tekst: String, stem: String?, tempo: Double) {
        huidige = nil
        if synthesizer.isSpeaking || synthesizer.isPaused { synthesizer.stopSpeaking(at: .immediate) }
        let uiting = Self.uiting(tekst, stem: stem, tempo: tempo)
        activeerAudiosessie()
        huidige = ObjectIdentifier(uiting)
        synthesizer.speak(uiting)
    }

    /// Een uitspraak met de gekozen (of beste Nederlandse) stem en het tempo; ook voor `MotorSpreker`.
    static func uiting(_ tekst: String, stem: String?, tempo: Double) -> AVSpeechUtterance {
        let uiting = AVSpeechUtterance(string: tekst)
        let gekozen = Stemkeuze.kies(uit: Stemkeuze.geinstalleerd(), voorkeur: stem)
        uiting.voice =
            gekozen.flatMap { AVSpeechSynthesisVoice(identifier: $0.id) } ?? AVSpeechSynthesisVoice(language: "nl-NL")
        uiting.rate = Voorleestempo.snelheid(tempo)
        uiting.postUtteranceDelay = 0.1
        return uiting
    }

    func stop() {
        huidige = nil
        synthesizer.stopSpeaking(at: .immediate)
        // Niet nu deactiveren: de synthesizer is dan nog bezig met stoppen. Dat gebeurt in
        // `didCancel`, als er intussen niet al een nieuwe uitspraak is begonnen.
        if !synthesizer.isSpeaking { deactiveerAudiosessie() }
    }

    func pauzeer() {
        synthesizer.pauseSpeaking(at: .immediate)
    }

    func hervat() {
        synthesizer.continueSpeaking()
    }

    fileprivate func afgelopen(_ uiting: ObjectIdentifier, uitgesproken: Bool) {
        if huidige == uiting {
            huidige = nil
            if uitgesproken { klaar?() }
        }
        if huidige == nil { deactiveerAudiosessie() }
    }

    private func activeerAudiosessie() {
        // Luistert Knipsel (fase 5), dan beheert de audiomotor de sessie.
        guard !Audiomotor.inGebruik else { return }
        let sessie = AVAudioSession.sharedInstance()
        do {
            try sessie.setCategory(
                .playback, mode: .spokenAudio, options: [.duckOthers])
            try sessie.setActive(true)
        } catch {
            // Zonder sessie spreekt de synthesizer nog steeds; alleen het zachter zetten van muziek mist.
        }
    }

    private func deactiveerAudiosessie() {
        guard !Audiomotor.inGebruik else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

extension SysteemSpreker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let uiting = ObjectIdentifier(utterance)
        Task { @MainActor in self.afgelopen(uiting, uitgesproken: true) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let uiting = ObjectIdentifier(utterance)
        Task { @MainActor in self.afgelopen(uiting, uitgesproken: false) }
    }
}

/// Luistert naar onderbrekingen van de audiosessie (telefoontje, Siri, wekker). Bij het begin ervan
/// roept hij `actie` aan; na afloop gebeurt er niets (de kok tikt zelf op herhaal). Een
/// selector-observer verdwijnt vanzelf met dit object.
final class Onderbrekingswacht: NSObject, Sendable {
    private let actie: @MainActor @Sendable () -> Void

    init(actie: @escaping @MainActor @Sendable () -> Void) {
        self.actie = actie
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(onderbroken(_:)), name: AVAudioSession.interruptionNotification, object: nil)
    }

    @objc private func onderbroken(_ melding: Notification) {
        guard let waarde = melding.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
            AVAudioSession.InterruptionType(rawValue: waarde) == .began
        else { return }
        let actie = actie
        Task { @MainActor in actie() }
    }
}
