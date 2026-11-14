@preconcurrency import AVFoundation
import Foundation

/// Leest voor via de `Audiomotor` in plaats van rechtstreeks via de synthesizer, zodat de
/// echo-onderdrukking van het luisteren de eigen stem herkent en wegfiltert (zie `Audiomotor`).
/// `AVSpeechSynthesizer.write` levert de stem als buffers; die gaan naar de spraakspeler van de motor.
@MainActor
final class MotorSpreker: NSObject, Spreker {
    var klaar: (() -> Void)?

    private let motor: Audiomotor
    private let synthesizer = AVSpeechSynthesizer()
    /// Generatie van de huidige uitspraak (zie `Buffersluis`); 0 = niets.
    private var generatie = 0
    /// De synthesizer is klaar met schrijven (delegate of: een tijd geen nieuwe buffers).
    private var geschreven = false
    private var huidige: ObjectIdentifier?
    private var stiltecontrole: Task<Void, Never>?

    init(motor: Audiomotor) {
        self.motor = motor
        super.init()
        synthesizer.delegate = self
    }

    func spreek(_ tekst: String, stem: String?, tempo: Double) {
        stopZonderMelding()
        let uiting = SysteemSpreker.uiting(tekst, stem: stem, tempo: tempo)
        generatie = motor.spraakSluis.nieuweGeneratie()
        geschreven = false
        huidige = ObjectIdentifier(uiting)
        motor.hervatSpraak()
        synthesizer.write(
            uiting,
            toBufferCallback: Self.schrijver(
                sluis: motor.spraakSluis, generatie: generatie,
                gebeurtenis: { [weak self] generatie, soort in
                    Task { @MainActor in self?.gebeurtenis(soort, generatie: generatie) }
                }))
    }

    func stop() {
        stopZonderMelding()
    }

    func pauzeer() {
        motor.pauzeerSpraak()
    }

    func hervat() {
        motor.hervatSpraak()
    }

    private func stopZonderMelding() {
        huidige = nil
        generatie = 0
        stiltecontrole?.cancel()
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        motor.stopSpraak()
    }

    // MARK: - Einde bepalen

    enum Soort: Sendable {
        /// Een buffer met geluid is ingepland.
        case buffer
        /// Een lege buffer: tussen zinnen of aan het eind.
        case leeg
        /// Een buffer is afgespeeld; `rest` buffers staan nog open.
        case afgespeeld(rest: Int)
    }

    private func gebeurtenis(_ soort: Soort, generatie: Int) {
        guard generatie == self.generatie, generatie != 0 else { return }
        switch soort {
        case .buffer:
            stiltecontrole?.cancel()
        case .leeg:
            // Lege buffers komen ook tússen zinnen. Pas als er een tijd niets nieuws komt, is het schrijven klaar.
            stiltecontrole?.cancel()
            stiltecontrole = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.schrijvenKlaar(generatie: generatie)
            }
        case .afgespeeld(let rest):
            if rest == 0, geschreven { afgelopen() }
        }
    }

    fileprivate func schrijvenKlaar(generatie: Int) {
        guard generatie == self.generatie else { return }
        geschreven = true
        if motor.spraakSluis.nogOpenstaand == 0 { afgelopen() }
    }

    fileprivate func schrijvenKlaar(uiting: ObjectIdentifier) {
        guard uiting == huidige else { return }
        schrijvenKlaar(generatie: generatie)
    }

    private func afgelopen() {
        guard generatie != 0 else { return }
        generatie = 0
        huidige = nil
        stiltecontrole?.cancel()
        klaar?()
    }

    /// Callback voor `write`, buiten de main actor gemaakt: hij draait op een thread van de synthesizer.
    private nonisolated static func schrijver(
        sluis: Buffersluis, generatie: Int, gebeurtenis: @escaping @Sendable (Int, Soort) -> Void
    ) -> (AVAudioBuffer) -> Void {
        { buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
                gebeurtenis(generatie, .leeg)
                return
            }
            sluis.plan(pcm, generatie: generatie) { rest in gebeurtenis(generatie, .afgespeeld(rest: rest)) }
            gebeurtenis(generatie, .buffer)
        }
    }
}

extension MotorSpreker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let uiting = ObjectIdentifier(utterance)
        Task { @MainActor in self.schrijvenKlaar(uiting: uiting) }
    }
}

/// Wisselt tussen de gewone spreker en de motor-spreker: zolang Knipsel luistert, gaat de stem door de
/// audiomotor (echo-onderdrukking); anders blijft de bestaande route met `SysteemSpreker`.
@MainActor
final class WisselSpreker: Spreker {
    var klaar: (() -> Void)? {
        didSet { koppel() }
    }

    private let gewoon: any Spreker
    private var motor: (any Spreker)?

    init(gewoon: any Spreker = SysteemSpreker()) {
        self.gewoon = gewoon
    }

    private var actief: any Spreker { motor ?? gewoon }

    /// `nil` = terug naar de gewone route. Wat er nog gesproken werd, stopt.
    func gebruik(_ nieuw: (any Spreker)?) {
        actief.stop()
        motor = nieuw
        koppel()
    }

    var gebruiktMotor: Bool { motor != nil }

    private func koppel() {
        gewoon.klaar = { [weak self] in if self?.motor == nil { self?.klaar?() } }
        motor?.klaar = { [weak self] in if self?.motor != nil { self?.klaar?() } }
    }

    func spreek(_ tekst: String, stem: String?, tempo: Double) { actief.spreek(tekst, stem: stem, tempo: tempo) }
    func stop() { actief.stop() }
    func pauzeer() { actief.pauzeer() }
    func hervat() { actief.hervat() }
}
