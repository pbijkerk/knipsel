import SwiftUI
import UIKit

/// Wat het scherm wakker houdt. In de app de systeem-idle-timer; in tests een nep.
@MainActor
protocol Slaapstand: AnyObject {
    /// `true`: het scherm gaat niet vanzelf uit.
    var uitgesteld: Bool { get set }
}

/// De echte: `UIApplication.isIdleTimerDisabled`.
@MainActor
final class SysteemSlaapstand: Slaapstand {
    var uitgesteld: Bool {
        get { UIApplication.shared.isIdleTimerDisabled }
        set { UIApplication.shared.isIdleTimerDisabled = newValue }
    }
}

/// Houdt het scherm aan zolang de kookmodus open én in beeld is (K7). Naar de achtergrond geeft
/// de slaapstand vrij; terug in beeld houdt hij het scherm weer aan. Sluiten geeft altijd vrij.
@MainActor
final class SchermAan {
    private let slaapstand: any Slaapstand
    private(set) var isOpen = false
    private var fase: ScenePhase = .active

    init(slaapstand: any Slaapstand = SysteemSlaapstand()) {
        self.slaapstand = slaapstand
    }

    func kookmodusGeopend() {
        isOpen = true
        werkBij()
    }

    func kookmodusGesloten() {
        isOpen = false
        werkBij()
    }

    func faseGewijzigd(_ nieuweFase: ScenePhase) {
        fase = nieuweFase
        werkBij()
    }

    private func werkBij() {
        slaapstand.uitgesteld = isOpen && fase != .background
    }
}
