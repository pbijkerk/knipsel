import CloudKit
import SwiftUI
import UIKit

/// Instellingen › Thuis delen: uitnodigen, wie meedoet, en stoppen (eigenaar) of vertrekken
/// (deelnemer) — met bevestiging, en zonder dat er recepten kwijtraken.
struct ThuisDelenScherm: View {
    var delen: ThuisDelen = .gedeeld

    @State private var bevestigStop = false
    @State private var bevestigVerlaat = false
    @State private var kopieerBijVertrek = true
    @State private var foutmelding: String?
    @State private var uitnodigen = false

    var body: some View {
        List {
            Section {
                Text(
                    "Thuis is een kookboek dat je deelt met een huisgenoot met een eigen Apple ID. Jullie zien en bewerken allebei de recepten in Thuis, met foto en hoe vaak je ze kookte. Mijn recepten blijven privé."
                )
                .font(.callout)
                LabeledContent("Recepten in Thuis", value: "\(delen.aantalThuis)")
            }

            if !delen.dienst.isBeschikbaar {
                Section {
                    SwiftUI.Label("iCloud staat uit", systemImage: "icloud.slash")
                } footer: {
                    Text(
                        "Thuis delen gaat via iCloud. Log in met je Apple ID en zet iCloud aan voor Knipsel; tot die tijd staat Thuis alleen op dit toestel."
                    )
                }
            }

            switch delen.status.rol {
            case .nietGedeeld: nietGedeeld
            case .eigenaar: eigenaar
            case .deelnemer: deelnemer
            }

            if let fout = delen.fout {
                Section {
                    SwiftUI.Label(fout, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
        .navigationTitle("Thuis delen")
        .navigationBarTitleDisplayMode(.inline)
        .task { await delen.vernieuw() }
        .refreshable { await delen.vernieuw() }
        .confirmationDialog("Stoppen met delen?", isPresented: $bevestigStop, titleVisibility: .visible) {
            Button("Stop met delen", role: .destructive) { voerUit { try await delen.stopMetDelen() } }
        } message: {
            Text(
                "De recepten in Thuis gaan terug naar Mijn recepten. Je huisgenoot ziet ze daarna niet meer, behalve wat die zelf heeft gekopieerd."
            )
        }
        .confirmationDialog("Thuis verlaten?", isPresented: $bevestigVerlaat, titleVisibility: .visible) {
            Button(kopieerBijVertrek ? "Kopieer en verlaat Thuis" : "Verlaat Thuis", role: .destructive) {
                let kopieer = kopieerBijVertrek
                voerUit { try await delen.verlaat(kopieer: kopieer) }
            }
        } message: {
            Text(
                kopieerBijVertrek
                    ? "De recepten uit Thuis komen als kopie in Mijn recepten. Daarna verdwijnt Thuis van dit toestel."
                    : "De recepten uit Thuis verdwijnen van dit toestel. Bij de anderen blijven ze staan."
            )
        }
        .alert(
            "Er ging iets mis",
            isPresented: Binding(get: { foutmelding != nil }, set: { if !$0 { foutmelding = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(foutmelding ?? "")
        }
    }

    // MARK: Per rol

    @ViewBuilder private var nietGedeeld: some View {
        Section {
            uitnodigKnop(titel: "Nodig iemand uit")
                .disabled(!delen.dienst.isBeschikbaar || delen.aantalThuis == 0)
        } footer: {
            Text(
                delen.aantalThuis == 0
                    ? "Zet eerst een recept in Thuis: open een recept › ⋯ › Verplaats naar Thuis, of kies bij het bewaren van een knipsel \u{201C}Bewaar in: Thuis\u{201D}."
                    : "Je huisgenoot krijgt een link via Berichten of Mail, opent die op een iPhone of iPad met Knipsel, en ziet dan Thuis. Huisgenoten mogen recepten in Thuis bewerken en toevoegen."
            )
        }
    }

    @ViewBuilder private var eigenaar: some View {
        Section("Wie doet mee") {
            ForEach(delen.status.deelnemers) { DeelnemerRij(deelnemer: $0) }
        }
        Section {
            uitnodigKnop(titel: delen.status.huisgenoten.isEmpty ? "Nodig iemand uit" : "Nodig uit of beheer")
        } footer: {
            Text("Huisgenoten mogen recepten in Thuis bekijken, bewerken en toevoegen.")
        }
        Section {
            Button("Stop met delen", systemImage: "person.2.slash", role: .destructive) { bevestigStop = true }
                .disabled(delen.bezig)
        } footer: {
            Text("Je houdt alle recepten: ze gaan terug naar Mijn recepten.")
        }
    }

    @ViewBuilder private var deelnemer: some View {
        if let eigenaar = delen.status.eigenaar {
            Section("Gedeeld door") {
                DeelnemerRij(deelnemer: eigenaar)
            }
        }
        if !delen.status.huisgenoten.isEmpty {
            Section("Wie doet mee") {
                ForEach(delen.status.huisgenoten) { DeelnemerRij(deelnemer: $0) }
            }
        }
        Section {
            Toggle("Kopieer de Thuis-recepten naar Mijn recepten", isOn: $kopieerBijVertrek)
            Button("Verlaat Thuis", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                bevestigVerlaat = true
            }
            .disabled(delen.bezig)
        } footer: {
            Text("Na vertrekken verdwijnt Thuis van dit toestel. Met de kopie houd je de recepten in Mijn recepten.")
        }
    }

    private func uitnodigKnop(titel: String) -> some View {
        Button {
            Task { await nodigUit() }
        } label: {
            HStack {
                SwiftUI.Label(titel, systemImage: "person.crop.circle.badge.plus")
                if uitnodigen {
                    Spacer()
                    ProgressView()
                }
            }
        }
        .disabled(uitnodigen)
    }

    // MARK: Acties

    private func nodigUit() async {
        uitnodigen = true
        defer { uitnodigen = false }
        do {
            guard let (share, container) = try await delen.dienst.uitnodiging() else {
                foutmelding = "Zet eerst een recept in Thuis; dan kun je iemand uitnodigen."
                return
            }
            await delen.vernieuw()
            DeelBlad.toon(share: share, container: container) {
                Task { await delen.vernieuw() }
            }
        } catch {
            foutmelding = error.localizedDescription
        }
    }

    private func voerUit(_ actie: @escaping @MainActor () async throws -> Void) {
        Task {
            do { try await actie() } catch { foutmelding = error.localizedDescription }
        }
    }
}

/// Eén persoon in de share.
struct DeelnemerRij: View {
    let deelnemer: ThuisDeelnemer

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: deelnemer.isEigenaar ? "house.circle.fill" : "person.crop.circle.fill")
                .font(.title2)
                .foregroundStyle(deelnemer.status == .doetMee ? Color.accentColor : .secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(deelnemer.isIkZelf ? "\(deelnemer.naam) (jij)" : deelnemer.naam)
                if let contact = deelnemer.contact, contact != deelnemer.naam {
                    Text(contact)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(deelnemer.isEigenaar ? "Eigenaar" : deelnemer.status.tekst)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// `UICloudSharingController` voor de share van Thuis: uitnodigen (Berichten, Mail, link) en
/// deelnemers beheren. Getoond vanuit UIKit bovenop het bovenste scherm: als SwiftUI-sheet
/// (`UIViewControllerRepresentable`) presenteert de controller zich niet goed.
@MainActor
enum DeelBlad {
    private static var delegate: DeelBladDelegate?

    static func toon(share: CKShare, container: CKContainer, naSluiten: @escaping () -> Void) {
        let controller = UICloudSharingController(share: share, container: container)
        // Huisgenoten vullen aan: alleen uitgenodigden, met lezen én schrijven.
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        let delegate = DeelBladDelegate(naSluiten: naSluiten)
        self.delegate = delegate
        controller.delegate = delegate
        controller.modalPresentationStyle = .formSheet
        guard let bovenste = bovensteScherm() else { return }
        controller.popoverPresentationController?.sourceView = bovenste.view
        bovenste.present(controller, animated: true)
    }

    private static func bovensteScherm() -> UIViewController? {
        let venster = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        var scherm = venster?.rootViewController
        while let volgende = scherm?.presentedViewController { scherm = volgende }
        return scherm
    }
}

private final class DeelBladDelegate: NSObject, UICloudSharingControllerDelegate {
    let naSluiten: () -> Void

    init(naSluiten: @escaping () -> Void) {
        self.naSluiten = naSluiten
    }

    func itemTitle(for csc: UICloudSharingController) -> String? { CloudKitDeelDienst.titel }

    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: any Error) {
        naSluiten()
    }

    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) { naSluiten() }

    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) { naSluiten() }
}
