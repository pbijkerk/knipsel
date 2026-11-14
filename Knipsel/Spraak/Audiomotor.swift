@preconcurrency import AVFoundation
import Foundation

/// Eén `AVAudioEngine` voor luisteren én voorlezen in de kookmodus (K8).
///
/// Waarom één motor: de echo-onderdrukking (voice processing) haalt alleen geluid weg dat door
/// dezelfde engine wordt afgespeeld. Leest Knipsel voor via `AVSpeechSynthesizer.speak`, dan hoort de
/// microfoon die stem gewoon. Daarom gaat de stem tijdens het luisteren als buffers door
/// `spraakSpeler` in deze engine (zie `MotorSpreker`), en het tikgeluid door `tikSpeler`.
@MainActor
final class Audiomotor {
    /// Formaat waarin stem en tik naar de mixer gaan; de mixer zet het om naar de uitgang.
    nonisolated static let speelformaat = AVAudioFormat(standardFormatWithSampleRate: 22_050, channels: 1)!

    private let engine = AVAudioEngine()
    private let spraakSpeler = AVAudioPlayerNode()
    private let tikSpeler = AVAudioPlayerNode()
    /// Voor de synthesizer-callback (andere thread): plant buffers in op de spraakspeler.
    let spraakSluis: Buffersluis

    private(set) var draait = false
    /// Draait er ergens een motor? Dan blijft `SysteemSpreker` van de audiosessie af.
    static private(set) var inGebruik = false
    /// Staat de echo-onderdrukking aan? (Niet op elk toestel/simulator beschikbaar.)
    private(set) var echoOnderdrukking = false

    private lazy var tikBuffer: AVAudioPCMBuffer? = Self.maakTik()

    init() {
        spraakSluis = Buffersluis(speler: spraakSpeler, doel: Self.speelformaat)
        engine.attach(spraakSpeler)
        engine.attach(tikSpeler)
        engine.connect(spraakSpeler, to: engine.mainMixerNode, format: Self.speelformaat)
        engine.connect(tikSpeler, to: engine.mainMixerNode, format: Self.speelformaat)
    }

    /// Audiosessie aan, echo-onderdrukking aan, microfoon open. `invoer` krijgt de microfoonbuffers op de
    /// audiothread.
    func start(invoer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) throws {
        guard !draait else { return }
        try Self.activeerAudiosessie()
        let microfoon = engine.inputNode
        do {
            try microfoon.setVoiceProcessingEnabled(true)
            // Muziek van andere apps zo min mogelijk extra zachter (de sessie duckt al met .duckOthers).
            microfoon.voiceProcessingOtherAudioDuckingConfiguration =
                AVAudioVoiceProcessingOtherAudioDuckingConfiguration(
                    enableAdvancedDucking: true, duckingLevel: .min)
            echoOnderdrukking = true
        } catch {
            echoOnderdrukking = false
        }
        let formaat = microfoon.outputFormat(forBus: 0)
        guard formaat.sampleRate > 0, formaat.channelCount > 0 else {
            throw Audiofout.geenMicrofoon
        }
        Self.installeerTap(op: microfoon, formaat: formaat, invoer: invoer)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            microfoon.removeTap(onBus: 0)
            throw error
        }
        spraakSpeler.play()
        tikSpeler.play()
        draait = true
        Self.inGebruik = true
    }

    func stop() {
        guard draait else { return }
        draait = false
        Self.inGebruik = false
        spraakSluis.wis()
        spraakSpeler.stop()
        tikSpeler.stop()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? engine.inputNode.setVoiceProcessingEnabled(false)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Afspelen

    func stopSpraak() {
        spraakSluis.wis()
        spraakSpeler.stop()
        if draait { spraakSpeler.play() }
    }

    func pauzeerSpraak() { spraakSpeler.pause() }
    func hervatSpraak() { if draait { spraakSpeler.play() } }

    /// Zacht tikje (± 60 ms) bij een begrepen commando; volgt het mediavolume.
    func speelTik() {
        guard draait, let tikBuffer else { return }
        tikSpeler.scheduleBuffer(tikBuffer, at: nil, options: .interrupts)
    }

    // MARK: - Hulp

    /// De tap-closure mag niet op de main actor gemaakt worden: hij draait op de audiothread, en een
    /// main-actor-closure laat Swift 6 daar crashen.
    private nonisolated static func installeerTap(
        op microfoon: AVAudioInputNode, formaat: AVAudioFormat, invoer: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) {
        microfoon.installTap(onBus: 0, bufferSize: 1024, format: formaat) { buffer, _ in invoer(buffer) }
    }

    /// `.playAndRecord` met mode `.default`: voice processing zet de motor zelf aan op de microfoon,
    /// `.voiceChat` is daarvoor niet nodig en zou het voorlezen als telefoongesprek behandelen (zachter,
    /// smalbandig via Bluetooth). `.defaultToSpeaker` (anders klinkt het uit het oorspeakertje),
    /// `.duckOthers` (muziek en podcasts zachter, niet pauzeren — dus bewust zonder
    /// `.interruptSpokenAudioAndMixWithOthers`), Bluetooth voor koptelefoon of speaker.
    static func activeerAudiosessie() throws {
        let sessie = AVAudioSession.sharedInstance()
        try sessie.setCategory(
            .playAndRecord, mode: .default,
            options: [.defaultToSpeaker, .duckOthers, .allowBluetoothHFP, .allowBluetoothA2DP])
        try sessie.setActive(true)
    }

    /// 1,2 kHz, 60 ms, zacht in- en uitgefaded.
    private static func maakTik() -> AVAudioPCMBuffer? {
        let formaat = speelformaat
        let frames = AVAudioFrameCount(formaat.sampleRate * 0.06)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: formaat, frameCapacity: frames),
            let kanaal = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            let t = Double(i) / formaat.sampleRate
            let omhulling = sin(Double.pi * Double(i) / Double(frames))
            kanaal[i] = Float(0.18 * omhulling * sin(2 * Double.pi * 1_200 * t))
        }
        return buffer
    }
}

enum Audiofout: Error {
    case geenMicrofoon
}

/// Plant buffers in op een speler vanaf een willekeurige thread (de synthesizer-callback), zet ze om
/// naar het speelformaat en telt wat er nog afgespeeld moet worden. Een nieuwe `generatie` (na stop)
/// laat late buffers van de vorige uitspraak vallen.
final class Buffersluis: @unchecked Sendable {
    private let slot = NSLock()
    private let speler: AVAudioPlayerNode
    private let doel: AVAudioFormat
    private var omzetter: Omzetter?
    private var generatie = 0
    private var openstaand = 0

    init(speler: AVAudioPlayerNode, doel: AVAudioFormat) {
        self.speler = speler
        self.doel = doel
    }

    /// Nieuwe uitspraak: oude buffers tellen niet meer. Geeft de nieuwe generatie.
    func nieuweGeneratie() -> Int {
        slot.withLock {
            generatie += 1
            openstaand = 0
            return generatie
        }
    }

    func wis() {
        _ = nieuweGeneratie()
    }

    /// Plant `buffer` in; `afgespeeld(nogOpenstaand)` komt als hij gespeeld (of weggegooid) is.
    func plan(_ buffer: AVAudioPCMBuffer, generatie: Int, afgespeeld: @escaping @Sendable (Int) -> Void) {
        let omgezet: AVAudioPCMBuffer? = slot.withLock {
            guard generatie == self.generatie else { return nil }
            if omzetter?.bron != buffer.format { omzetter = Omzetter(van: buffer.format, naar: doel) }
            guard let resultaat = omzetter?.zet(buffer) else { return nil }
            openstaand += 1
            return resultaat
        }
        guard let omgezet else { return }
        speler.scheduleBuffer(omgezet, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            guard let self else { return }
            let rest: Int? = self.slot.withLock {
                guard generatie == self.generatie else { return nil }
                self.openstaand = max(0, self.openstaand - 1)
                return self.openstaand
            }
            if let rest { afgespeeld(rest) }
        }
    }

    var nogOpenstaand: Int { slot.withLock { openstaand } }
}

/// Zet audiobuffers om naar een ander formaat (samplefrequentie, Int16 → Float32). Eén omzetter per
/// stroom, zodat de resampler zijn toestand tussen buffers houdt. Niet thread-safe: gebruik hem vanaf
/// één thread tegelijk.
final class Omzetter: @unchecked Sendable {
    let bron: AVAudioFormat
    let doel: AVAudioFormat
    private let converter: AVAudioConverter?

    init(van bron: AVAudioFormat, naar doel: AVAudioFormat) {
        self.bron = bron
        self.doel = doel
        converter = bron == doel ? nil : AVAudioConverter(from: bron, to: doel)
    }

    func zet(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let converter else { return buffer }
        let verhouding = doel.sampleRate / bron.sampleRate
        let capaciteit = AVAudioFrameCount((Double(buffer.frameLength) * verhouding).rounded(.up)) + 64
        guard let uit = AVAudioPCMBuffer(pcmFormat: doel, frameCapacity: capaciteit) else { return nil }
        let gegeven = Vlag()
        var fout: NSError?
        let status = converter.convert(to: uit, error: &fout) { _, invoerStatus in
            if gegeven.staat {
                invoerStatus.pointee = .noDataNow
                return nil
            }
            gegeven.staat = true
            invoerStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, fout == nil, uit.frameLength > 0 else { return nil }
        return uit
    }

    private final class Vlag: @unchecked Sendable {
        var staat = false
    }
}
