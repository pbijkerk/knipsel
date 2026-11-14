@preconcurrency import AVFoundation
import Foundation
import Observation
import OSLog
@preconcurrency import Speech

/// Luistert in de kookmodus naar korte commando's (K8), alleen zolang de kookmodus open en op de
/// voorgrond is en luisteren aan staat. Alles op het toestel.
///
/// Primair `SpeechAnalyzer` + `DictationTranscriber` (`nl_NL`; `SpeechTranscriber` kent geen Nederlands),
/// met het taalmodel via `AssetInventory`. Terugval: `SFSpeechRecognizer` (`nl-NL`) met
/// `requiresOnDeviceRecognition`, opnieuw gestart na elke uiting. De microfoon loopt via de
/// `Audiomotor`, met echo-onderdrukking.
@MainActor
@Observable
final class LuisterService {
    enum Status: Equatable, Sendable {
        case uit
        /// Nog geen toestemming gevraagd: eerst de uitleg tonen.
        case uitlegNodig
        case vraagtToestemming
        /// Microfoon of spraakherkenning geweigerd (Instellingen).
        case geweigerd
        /// Het Nederlandse spraakmodel wordt gedownload; voortgang 0…1 als bekend.
        case modelLaden(Double?)
        case start
        case luistert
        /// Kan op dit toestel niet (geen Nederlandse herkenning, geen microfoon).
        case nietBeschikbaar(String)
    }

    enum Route: String, Sendable {
        case analyzer = "SpeechAnalyzer"
        case terugval = "SFSpeechRecognizer"
    }

    private(set) var status: Status = .uit
    private(set) var route: Route?

    /// (tekst, segment, definitief, tijd): elk (deel)resultaat van de herkenner.
    @ObservationIgnored var resultaat: (String, Int, Bool, TimeInterval) -> Void = { _, _, _, _ in }
    /// Elke 0,2 s tijdens het luisteren, voor stabiele voorlopige resultaten.
    @ObservationIgnored var tik: (TimeInterval) -> Void = { _ in }
    /// Vlak voordat de microfoon opengaat: het voorlezen moet dan over op de audiomotor.
    @ObservationIgnored var voorMicrofoon: () -> Void = {}

    @ObservationIgnored let motor = Audiomotor()
    @ObservationIgnored private var taken: [Task<Void, Never>] = []
    @ObservationIgnored private var analyzer: SpeechAnalyzer?
    @ObservationIgnored private var invoer: AsyncStream<AnalyzerInput>.Continuation?
    @ObservationIgnored private var terugval: Terugvalherkenner?
    @ObservationIgnored private var poging = 0

    static let taal = Locale(identifier: "nl_NL")
    private static let log = Logger(subsystem: "com.peterbijkerk.knipsel", category: "luisteren")

    // MARK: - Toestemming

    enum Toestemming: Equatable, Sendable {
        case onbekend
        case gegeven
        case geweigerd
    }

    /// Microfoon én spraakherkenning.
    static var toestemming: Toestemming {
        let microfoon = AVAudioApplication.shared.recordPermission
        let spraak = SFSpeechRecognizer.authorizationStatus()
        if microfoon == .denied || spraak == .denied || spraak == .restricted { return .geweigerd }
        if microfoon == .undetermined || spraak == .notDetermined { return .onbekend }
        return .gegeven
    }

    /// Vraagt de toestemmingen (na de uitleg in de kookmodus).
    func vraagToestemming() async -> Bool {
        status = .vraagtToestemming
        let microfoon = await AVAudioApplication.requestRecordPermission()
        let spraak = await Self.vraagSpraaktoestemming()
        let gegeven = microfoon && spraak
        status = gegeven ? .uit : .geweigerd
        return gegeven
    }

    private nonisolated static func vraagSpraaktoestemming() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in continuation.resume(returning: status == .authorized) }
        }
    }

    // MARK: - Starten en stoppen

    /// Begint te luisteren. `contextwoorden`: commando's en ingrediëntnamen, die de herkenner extra kans geeft.
    func start(contextwoorden: [String]) async {
        switch Self.toestemming {
        case .onbekend:
            status = .uitlegNodig
            return
        case .geweigerd:
            status = .geweigerd
            return
        case .gegeven:
            break
        }
        guard status != .luistert, status != .start else { return }
        stop()
        poging += 1
        let dezePoging = poging
        status = .start
        do {
            if let transcriber = try await bereidAnalyzerVoor(), dezePoging == poging {
                try await startAnalyzer(transcriber, contextwoorden: contextwoorden)
                route = .analyzer
            } else if dezePoging == poging {
                try startTerugval(contextwoorden: contextwoorden)
                route = .terugval
            }
        } catch {
            Self.log.error("Luisteren via SpeechAnalyzer lukt niet: \(error.localizedDescription, privacy: .public)")
            stopAudio()
            guard dezePoging == poging else { return }
            do {
                try startTerugval(contextwoorden: contextwoorden)
                route = .terugval
            } catch {
                Self.log.error("Terugval lukt ook niet: \(error.localizedDescription, privacy: .public)")
                stopAudio()
                status = .nietBeschikbaar("Spraakherkenning werkt nu niet op dit toestel.")
                return
            }
        }
        guard dezePoging == poging else { return }
        status = .luistert
        startTikker()
    }

    #if DEBUG
        /// Alleen voor renders en previews.
        func toonStatus(_ nieuw: Status) {
            status = nieuw
        }
    #endif

    func stop() {
        poging += 1
        stopAudio()
        if status != .geweigerd, status != .uitlegNodig { status = .uit }
    }

    private func stopAudio() {
        for taak in taken { taak.cancel() }
        taken = []
        invoer?.finish()
        invoer = nil
        if let analyzer {
            Task { await analyzer.cancelAndFinishNow() }
        }
        analyzer = nil
        terugval?.stop()
        terugval = nil
        motor.stop()
        route = nil
    }

    private func startTikker() {
        taken.append(
            Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(200))
                    self?.tik(ProcessInfo.processInfo.systemUptime)
                }
            })
    }

    // MARK: - SpeechAnalyzer + DictationTranscriber

    /// De transcriber als Nederlands kan; zo nodig eerst het taalmodel downloaden. `nil` = terugval.
    private func bereidAnalyzerVoor() async throws -> DictationTranscriber? {
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: Self.taal) else { return nil }
        let transcriber = DictationTranscriber(
            locale: locale, contentHints: [.shortForm, .farField], transcriptionOptions: [],
            reportingOptions: [.volatileResults, .frequentFinalization], attributeOptions: [])
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .unsupported:
            return nil
        case .installed:
            return transcriber
        case .supported, .downloading:
            try await installeerModel(voor: transcriber)
            return transcriber
        @unknown default:
            return nil
        }
    }

    private func installeerModel(voor transcriber: DictationTranscriber) async throws {
        guard let verzoek = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else { return }
        status = .modelLaden(nil)
        let voortgang = verzoek.progress
        let volger = Task { [weak self] in
            while !Task.isCancelled {
                self?.status = .modelLaden(voortgang.totalUnitCount > 0 ? voortgang.fractionCompleted : nil)
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
        defer { volger.cancel() }
        try await verzoek.downloadAndInstall()
        status = .start
    }

    private func startAnalyzer(_ transcriber: DictationTranscriber, contextwoorden: [String]) async throws {
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        let context = AnalysisContext()
        context.contextualStrings[.general] = contextwoorden
        try? await analyzer.setContext(context)
        guard let formaat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw Audiofout.geenMicrofoon
        }
        try await analyzer.prepareToAnalyze(in: formaat)
        let (stroom, invoer) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingNewest(128))
        self.invoer = invoer
        try await analyzer.start(inputSequence: stroom)

        let resultaten = Task { [weak self] in
            do {
                var teller = Uitingteller()
                for try await resultaat in transcriber.results {
                    let tekst = String(resultaat.text.characters)
                    let segment = teller.segment(definitief: resultaat.isFinal)
                    self?.resultaat(tekst, segment, resultaat.isFinal, ProcessInfo.processInfo.systemUptime)
                }
            } catch {
                Self.log.error("Herkenning gestopt: \(error.localizedDescription, privacy: .public)")
            }
        }
        taken.append(resultaten)
        voorMicrofoon()
        try motor.start(invoer: Self.naarAnalyzer(invoer, formaat: formaat))
    }

    /// Zet microfoonbuffers om naar het formaat van de analyzer; buiten de main actor (audiothread).
    private nonisolated static func naarAnalyzer(
        _ invoer: AsyncStream<AnalyzerInput>.Continuation, formaat: AVAudioFormat
    ) -> @Sendable (AVAudioPCMBuffer) -> Void {
        let houder = OmzetterHouder(doel: formaat)
        return { buffer in
            guard let omgezet = houder.zet(buffer) else { return }
            invoer.yield(AnalyzerInput(buffer: omgezet))
        }
    }

    // MARK: - Terugval: SFSpeechRecognizer

    private func startTerugval(contextwoorden: [String]) throws {
        guard let herkenner = SFSpeechRecognizer(locale: Locale(identifier: "nl-NL")), herkenner.isAvailable,
            herkenner.supportsOnDeviceRecognition
        else {
            throw Herkenfout.geenNederlands
        }
        let terugval = Terugvalherkenner(herkenner: herkenner, contextwoorden: contextwoorden) {
            [weak self] tekst, segment, definitief in
            self?.resultaat(tekst, segment, definitief, ProcessInfo.processInfo.systemUptime)
        }
        self.terugval = terugval
        terugval.begin()
        voorMicrofoon()
        try motor.start(invoer: terugval.invoer)
    }

    enum Herkenfout: Error {
        case geenNederlands
    }
}

/// Eén omzetter voor de microfoonstroom; wordt alleen vanaf de audiothread gebruikt.
private final class OmzetterHouder: @unchecked Sendable {
    private let doel: AVAudioFormat
    private var omzetter: Omzetter?

    init(doel: AVAudioFormat) {
        self.doel = doel
    }

    func zet(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if omzetter?.bron != buffer.format { omzetter = Omzetter(van: buffer.format, naar: doel) }
        return omzetter?.zet(buffer)
    }
}

/// `SFSpeechRecognizer` met een nieuwe taak per uiting: na een eindresultaat (of fout, of na 50 s,
/// ruim binnen de grens van ± 1 minuut per taak) begint er een nieuwe. Elk taaknummer is een segment.
@MainActor
final class Terugvalherkenner {
    private let herkenner: SFSpeechRecognizer
    private let contextwoorden: [String]
    private let melding: (String, Int, Bool) -> Void
    private let houder = VerzoekHouder()
    private var taak: SFSpeechRecognitionTask?
    private var segment = 0
    private var actief = false
    private var herstart: Task<Void, Never>?

    init(herkenner: SFSpeechRecognizer, contextwoorden: [String], melding: @escaping (String, Int, Bool) -> Void) {
        self.herkenner = herkenner
        self.contextwoorden = contextwoorden
        self.melding = melding
    }

    /// Voor de microfoon-tap (audiothread).
    var invoer: @Sendable (AVAudioPCMBuffer) -> Void {
        let houder = houder
        return { buffer in houder.voegToe(buffer) }
    }

    func begin() {
        actief = true
        nieuweTaak()
    }

    func stop() {
        actief = false
        herstart?.cancel()
        houder.zet(nil)
        taak?.cancel()
        taak = nil
    }

    private func nieuweTaak() {
        guard actief else { return }
        taak?.cancel()
        segment += 1
        let verzoek = SFSpeechAudioBufferRecognitionRequest()
        verzoek.requiresOnDeviceRecognition = true
        verzoek.shouldReportPartialResults = true
        verzoek.addsPunctuation = false
        verzoek.taskHint = .confirmation
        verzoek.contextualStrings = contextwoorden
        houder.zet(verzoek)
        let ditSegment = segment
        taak = herkenner.recognitionTask(
            with: verzoek,
            resultHandler: Self.verwerker { [weak self] tekst, definitief, fout in
                self?.ontvang(tekst, definitief: definitief, fout: fout, segment: ditSegment)
            })
        herstart?.cancel()
        herstart = Task { [weak self] in
            try? await Task.sleep(for: .seconds(50))
            guard !Task.isCancelled else { return }
            self?.nieuweTaak()
        }
    }

    private func ontvang(_ tekst: String?, definitief: Bool, fout: Bool, segment: Int) {
        guard actief, segment == self.segment else { return }
        if let tekst, !tekst.isEmpty { melding(tekst, segment, definitief) }
        if definitief || fout { nieuweTaak() }
    }

    /// Resultaat-callback buiten de main actor; haalt alleen tekst en eindstatus eruit.
    private nonisolated static func verwerker(
        _ door: @escaping @MainActor @Sendable (String?, Bool, Bool) -> Void
    ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { resultaat, fout in
            let tekst = resultaat?.bestTranscription.formattedString
            let definitief = resultaat?.isFinal ?? false
            let isFout = fout != nil
            Task { @MainActor in door(tekst, definitief, isFout) }
        }
    }
}

/// Het lopende verzoek, voor de audiothread.
private final class VerzoekHouder: @unchecked Sendable {
    private let slot = NSLock()
    private var verzoek: SFSpeechAudioBufferRecognitionRequest?

    func zet(_ nieuw: SFSpeechAudioBufferRecognitionRequest?) {
        let oud: SFSpeechAudioBufferRecognitionRequest? = slot.withLock {
            let oud = verzoek
            verzoek = nieuw
            return oud
        }
        oud?.endAudio()
    }

    func voegToe(_ buffer: AVAudioPCMBuffer) {
        slot.withLock { verzoek }?.append(buffer)
    }
}
