import SwiftUI
import UIKit

/// "Knipsel" in het deelmenu (#18). Zet wat je deelt in de inbox van de app (App Group) en
/// bevestigt dat; het inlezen zelf doet de app, bij het openen. Geen netwerk, geen Core Data.
@objc(DeelViewController)
final class DeelViewController: UIViewController {
    private var hosting: UIHostingController<DeelBevestiging>?

    override func viewDidLoad() {
        super.viewDidLoad()
        toon(.bezig)
        Task { await verwerk() }
    }

    private func verwerk() async {
        guard let map = DeelGroep.inboxMap else {
            toon(.mislukt("Knipsel kan zijn map voor gedeelde items niet openen. Open Knipsel en probeer het opnieuw."))
            return
        }
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        if let post = await DeelLezer(bus: DeelBus(map: map)).lees(providers) {
            toon(.toegevoegd(DeelBevestiging.omschrijving(post.bron)))
        } else {
            toon(.niets)
        }
    }

    private func toon(_ toestand: DeelBevestiging.Toestand) {
        let scherm = DeelBevestiging(toestand: toestand) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
        if let hosting {
            hosting.rootView = scherm
            return
        }
        let hosting = UIHostingController(rootView: scherm)
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hosting.didMove(toParent: self)
        self.hosting = hosting
    }
}
