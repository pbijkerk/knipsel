import AVFoundation
import MediaPlayer
import UIKit

// Proef S3 (docs/spikes/S3-airpods.md): AirPods-steeltje en Apple Watch bedienen de kookmodus via
// "Nu speelt". Alleen met Instellingen › Siri en Opdrachten › *Bediening met AirPods en Apple Watch
// (proef)* aan, en alleen zolang de kookmodus open is.

/// Een knop van AirPods, Watch, vergrendelscherm of Bedieningspaneel.
enum AfstandsKnop: CaseIterable, Sendable {
    case volgende
    case vorige
    case speelPauze
    case speel
    case pauze
}

/// Wat een `AfstandsKnop` in de kookmodus doet. Puur, zodat het zonder `MPRemoteCommandCenter` te
/// testen is.
enum AfstandsBediening {
    enum Actie: Equatable, Sendable {
        case opdracht(KookOpdracht)
        case stopVoorlezen
    }

    /// Volgende/vorige nummer = volgende/vorige stap; afspelen = de stap (opnieuw) voorlezen;
    /// pauze = stoppen met voorlezen; afspelen/pauze wisselt daartussen.
    static func actie(voor knop: AfstandsKnop, spreekt: Bool) -> Actie {
        switch knop {
        case .volgende: .opdracht(.volgende)
        case .vorige: .opdracht(.vorige)
        case .speel: .opdracht(.herhaal)
        case .pauze: .stopVoorlezen
        case .speelPauze: spreekt ? .stopVoorlezen : .opdracht(.herhaal)
        }
    }

    /// Voert de knop uit op de lopende kookbeurt; zonder kookbeurt gebeurt er niets (`false`).
    @MainActor
    @discardableResult
    static func verwerk(_ knop: AfstandsKnop, in houder: ActieveKookSessie = .gedeeld) -> Bool {
        guard let voorlezer = houder.voorlezer else { return false }
        switch actie(voor: knop, spreekt: voorlezer.status == .spreekt) {
        case .opdracht(let opdracht):
            _ = KookOpdrachtUitvoerder.voerUit(opdracht, in: houder)
        case .stopVoorlezen:
            voorlezer.stop()
        }
        return true
    }
}

/// De gegevens voor "Nu speelt": recepttitel, "Stap 3 van 7", en of Knipsel nu voorleest. Puur.
struct NuSpeeltGegevens: Equatable, Sendable {
    let titel: String
    let ondertitel: String
    let spreekt: Bool

    @MainActor
    init(sessie: KookSessie, spreekt: Bool) {
        titel = sessie.titel
        ondertitel = sessie.isAfgerond ? "Klaar" : "Stap \(sessie.stapNummer) van \(sessie.aantalStappen)"
        self.spreekt = spreekt
    }

    /// Voor `MPNowPlayingInfoCenter.nowPlayingInfo` (zonder afbeelding).
    var woordenboek: [String: Any] {
        [
            MPMediaItemPropertyTitle: titel,
            MPMediaItemPropertyArtist: ondertitel,
            MPMediaItemPropertyAlbumTitle: "Knipsel",
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackRate: spreekt ? 1.0 : 0.0,
        ]
    }
}

/// Registreert de knoppen bij `MPRemoteCommandCenter` en houdt "Nu speelt" bij, zolang de proef aan
/// staat en de kookmodus open is. `stop()` haalt alles weer weg.
@MainActor
final class NuSpeeltBediening {
    static let gedeeld = NuSpeeltBediening()

    nonisolated static func proefAan(_ standaarden: UserDefaults = .standard) -> Bool {
        standaarden.bool(forKey: AppConfiguratie.sleutelAirPodsProef)
    }

    /// Audiosessie van het voorlezen zonder microfoon. Normaal `.duckOthers` (muziek zachter). Dat is
    /// mixbaar, en een mixbare app wordt volgens Apple nooit de "Nu speelt"-app; tijdens de proef
    /// daarom zonder: muziek pauzeert dan bij het voorlezen.
    nonisolated static func spraakOpties(proefAan: Bool) -> AVAudioSession.CategoryOptions {
        proefAan ? [] : [.duckOthers]
    }

    private(set) var actief = false
    private var doelen: [(MPRemoteCommand, Any)] = []
    private var afbeelding: MPMediaItemArtwork?

    func start(houder: ActieveKookSessie = .gedeeld) {
        guard !actief, Self.proefAan(), let sessie = houder.sessie else { return }
        let centrum = MPRemoteCommandCenter.shared()
        let knoppen: [(MPRemoteCommand, AfstandsKnop)] = [
            (centrum.nextTrackCommand, .volgende), (centrum.previousTrackCommand, .vorige),
            (centrum.togglePlayPauseCommand, .speelPauze), (centrum.playCommand, .speel),
            (centrum.pauseCommand, .pauze),
        ]
        for (commando, knop) in knoppen {
            commando.isEnabled = true
            doelen.append((commando, commando.addTarget(handler: Self.afhandeling(knop))))
        }
        // Geen spoelen: dat heeft in een recept geen betekenis.
        centrum.skipForwardCommand.isEnabled = false
        centrum.skipBackwardCommand.isEnabled = false
        centrum.changePlaybackPositionCommand.isEnabled = false
        afbeelding = Self.afbeelding(fotoData: sessie.fotoData, symbool: sessie.symbool).map(Self.artwork)
        actief = true
        werkBij(houder: houder)
    }

    func werkBij(houder: ActieveKookSessie = .gedeeld) {
        guard actief, let sessie = houder.sessie, let voorlezer = houder.voorlezer else { return }
        var info = NuSpeeltGegevens(sessie: sessie, spreekt: voorlezer.status == .spreekt).woordenboek
        if let afbeelding { info[MPMediaItemPropertyArtwork] = afbeelding }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func stop() {
        guard actief else { return }
        for (commando, doel) in doelen {
            commando.removeTarget(doel)
            commando.isEnabled = false
        }
        doelen = []
        afbeelding = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        actief = false
    }

    /// Buiten de main actor gemaakt: MediaPlayer roept hem aan op een eigen thread (Swift 6 zou een
    /// main-actor-closure daar laten crashen). Het werk zelf gaat naar de main actor.
    private nonisolated static func afhandeling(
        _ knop: AfstandsKnop
    ) -> (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        { _ in
            Task { @MainActor in AfstandsBediening.verwerk(knop) }
            return .success
        }
    }

    private nonisolated static func artwork(_ beeld: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: beeld.size) { _ in beeld }
    }

    /// De eigen foto, of het categoriesymbool wit op tomaat.
    static func afbeelding(fotoData: Data?, symbool: String) -> UIImage? {
        if let fotoData, let foto = UIImage(data: fotoData) { return foto }
        let zijde: CGFloat = 600
        let configuratie = UIImage.SymbolConfiguration(pointSize: zijde * 0.45, weight: .semibold)
        guard
            let teken =
                (UIImage(systemName: symbool, withConfiguration: configuratie)
                ?? UIImage(systemName: "fork.knife", withConfiguration: configuratie))?
                .withTintColor(.white, renderingMode: .alwaysOriginal)
        else { return nil }
        let formaat = UIGraphicsImageRendererFormat()
        formaat.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: zijde, height: zijde), format: formaat).image { _ in
            UIColor(red: 0xD9 / 255, green: 0x61 / 255, blue: 0x3C / 255, alpha: 1).setFill()
            UIRectFill(CGRect(x: 0, y: 0, width: zijde, height: zijde))
            let maat = teken.size
            teken.draw(at: CGPoint(x: (zijde - maat.width) / 2, y: (zijde - maat.height) / 2))
        }
    }
}
