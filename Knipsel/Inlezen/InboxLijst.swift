import CoreData
import PDFKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Bovenaan de bibliotheek (onder "Verder met…"): "Nog te controleren (n)" als er ingelezen
/// recepten op controle wachten. Een tik opent de lijst.
struct NogTeControlerenKaart: View {
    let aantal: Int
    let bezig: Bool
    let open: () -> Void

    private var vorm: RoundedRectangle { RoundedRectangle(cornerRadius: 18, style: .continuous) }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                Image(systemName: "tray.full")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Kaartkleuren.titel.kleur.opacity(0.85))
                    .frame(width: 44, height: 44)
                    .background(Kaartkleuren.titel.kleur.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nog te controleren (\(aantal))")
                        .font(.system(.headline, design: .serif).weight(.bold))
                        .foregroundStyle(Kaartkleuren.titel.kleur)
                    Text(bezig ? "Bezig met inlezen…" : "Ingelezen recepten wachten op je controle")
                        .font(.subheadline)
                        .foregroundStyle(Kaartkleuren.ondertekst.kleur)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Kaartkleuren.ondertekst.kleur)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(Kaartkleuren.neutraal.kleur, in: vorm)
            .contentShape(vorm)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Nog te controleren, \(aantal)")
        .accessibilityHint("Opent de ingelezen recepten die nog gecontroleerd moeten worden")
    }
}

/// De lijst "Nog te controleren". Tik = inlezen/controleren; vegen = verwijderen.
struct InboxLijst: View {
    @Environment(InleesInbox.self) private var inbox
    @Environment(\.dismiss) private var dismiss
    @State private var geopend: InleesItemKeuze?

    var body: some View {
        NavigationStack {
            Group {
                if inbox.items.isEmpty {
                    ContentUnavailableView(
                        "Niets te controleren", systemImage: "tray",
                        description: Text("Recepten die je plakt, deelt of als link invoert, komen eerst hier."))
                } else {
                    List {
                        Section {
                            ForEach(inbox.items) { item in
                                Button {
                                    geopend = InleesItemKeuze(id: item.id)
                                } label: {
                                    InboxRij(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete { plekken in
                                for plek in plekken { inbox.verwijder(inbox.items[plek].id) }
                            }
                        } footer: {
                            Text("Niets wordt een recept zonder dat je het hebt gecontroleerd.")
                        }
                    }
                }
            }
            .navigationTitle("Nog te controleren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klaar") { dismiss() }
                }
            }
        }
        .sheet(item: $geopend) { keuze in
            InleesScherm(id: keuze.id)
        }
    }
}

/// Eén regel in de lijst: soort bron, titel, status en datum.
struct InboxRij: View {
    let item: InleesItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbool)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.titel)
                    .font(.system(.headline, design: .serif))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if item.status == .bezig || item.status == .wachten {
                        ProgressView().controlSize(.mini)
                    }
                    Text(status)
                        .foregroundStyle(statusKleur)
                }
                .font(.subheadline)
                Text(onderregel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var symbool: String {
        switch item.bron {
        case .link: "link"
        case .tekst: "text.alignleft"
        case .afbeeldingen: "photo"
        case .pdf: "doc.richtext"
        }
    }

    private var status: String {
        switch item.status {
        case .wachten: "Wacht op inlezen"
        case .bezig: "Bezig met inlezen…"
        case .klaar: "Klaar om te controleren"
        case .betaalmuur: "Achter een betaalmuur: kies hoe verder"
        case .herkennen: "Tekst herkennen en controleren"
        case .mislukt(let reden): reden
        }
    }

    private var statusKleur: Color {
        switch item.status {
        case .klaar, .herkennen: .accentColor
        case .betaalmuur, .mislukt: .orange
        default: .secondary
        }
    }

    private var onderregel: String {
        let bron: String? =
            switch item.bron {
            case .link(let url): item.bronNaam ?? ReceptInlezer.host(url)
            default: item.bronNaam
            }
        let datum = item.datum.formatted(.relative(presentation: .named).locale(Locale(identifier: "nl_NL")))
        return [bron, datum].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Een item om te openen (voor `.sheet(item:)`).
struct InleesItemKeuze: Identifiable, Hashable {
    let id: InleesItem.ID
}

/// Iets dat op de bibliotheek gesleept wordt (iPad): een link uit Safari of tekst.
enum GesleeptItem: Transferable {
    case link(URL)
    case tekst(String)

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(importing: { (url: URL) in GesleeptItem.link(url) })
        ProxyRepresentation(importing: { (tekst: String) in GesleeptItem.tekst(tekst) })
    }
}

/// Het ＋-menu van de bibliotheek en alles wat erbij hoort: nieuw recept, recept plakken, link
/// invoeren, PDF of schermafdruk kiezen, slepen (iPad), en het verwerken van wachtende items.
struct InleesInvoer: ViewModifier {
    let nieuw: () -> Void
    @Binding var toonInbox: Bool
    var slepen = false

    @Environment(InleesInbox.self) private var inbox
    @Environment(\.scenePhase) private var fase
    @State private var geopend: InleesItemKeuze?
    @State private var toonLink = false
    @State private var linkTekst = ""
    @State private var toonPDF = false
    @State private var toonFotos = false
    @State private var fotoKeuze: [PhotosPickerItem] = []
    @State private var knipBeelden: KnipBeelden?
    @State private var melding: String?

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(key: "volgorde", ascending: true)],
        // De voorstellen van de indeler komen uit Mijn recepten (Thuis heeft gelijknamige).
        predicate: NSPredicate(format: "verborgen == NO AND kookboek == %@", Kookboek.mijn.rawValue))
    private var categorieen: FetchedResults<Categorie>
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(
                key: "naam", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare(_:)))
        ], predicate: Bibliotheekbeheer.alleenMijn)
    private var labels: FetchedResults<ReceptLabel>

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        InvoerMenuInhoud(
                            nieuw: nieuw, plak: plakKlembord, link: { toonLink = true }, pdf: { toonPDF = true },
                            schermafdruk: { toonFotos = true })
                    } label: {
                        SwiftUI.Label("Nieuw recept", systemImage: "plus")
                    }
                }
            }
            .alert("Link invoeren", isPresented: $toonLink) {
                TextField("https://…", text: $linkTekst)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Lees in") {
                    voegLinkToe(linkTekst)
                    linkTekst = ""
                }
                Button("Annuleer", role: .cancel) { linkTekst = "" }
            } message: {
                Text("Het webadres van een receptpagina. Knipsel haalt de pagina rechtstreeks op dit toestel op.")
            }
            .alert(
                "Niet gelukt", isPresented: Binding(get: { melding != nil }, set: { if !$0 { melding = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(melding ?? "")
            }
            .fileImporter(isPresented: $toonPDF, allowedContentTypes: [.pdf]) { uitkomst in
                if case .success(let url) = uitkomst { voegPDFToe(url) }
            }
            .photosPicker(
                isPresented: $toonFotos, selection: $fotoKeuze, maxSelectionCount: 4, selectionBehavior: .ordered,
                matching: .images
            )
            .onChange(of: fotoKeuze) { _, keuze in
                guard !keuze.isEmpty else { return }
                Task {
                    knipBeelden = await KnipBeelden.laad(keuze)
                    fotoKeuze = []
                }
            }
            .sheet(item: $knipBeelden) { keuze in
                KnipStart(beelden: keuze.beelden)
            }
            .sheet(item: $geopend) { keuze in
                InleesScherm(id: keuze.id)
            }
            .sheet(isPresented: $toonInbox) {
                InboxLijst()
            }
            .modifier(
                Slepen(aan: slepen) { item in
                    switch item {
                    case .link(let url): open(inbox.voegToe(.link(url)))
                    case .tekst(let tekst): open(inbox.voegToe(.tekst(tekst)))
                    }
                }
            )
            .task(id: fase) {
                guard fase == .active else { return }
                inbox.laad()
                // Net via het deelmenu toegevoegd (de extensie schrijft in de App Group).
                inbox.neemGedeeldOver()
                inbox.ruimOp()
                await InleesVerwerker(inbox: inbox).verwerkWachtende(
                    categorieen: categorieen.map(\.naamOfStandaard), labels: labels.map(\.naamOfStandaard))
            }
    }

    private func open(_ item: InleesItem) {
        geopend = InleesItemKeuze(id: item.id)
    }

    /// Klembord: een link of tekst. iOS vraagt zelf toestemming om te plakken.
    private func plakKlembord() {
        let klembord = UIPasteboard.general
        if let url = klembord.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            open(inbox.voegToe(.link(url)))
        } else if let tekst = klembord.string, !tekst.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            open(inbox.voegToe(.tekst(tekst)))
        } else {
            melding = "Er staat geen link of tekst op het klembord. Kopieer eerst het recept of de link."
        }
    }

    private func voegLinkToe(_ tekst: String) {
        var schoon = tekst.trimmingCharacters(in: .whitespacesAndNewlines)
        if !schoon.isEmpty, !schoon.contains("://") { schoon = "https://" + schoon }
        guard let url = ReceptInlezer.link(in: schoon) else {
            melding = "Dat is geen geldig webadres."
            return
        }
        open(inbox.voegToe(.link(url)))
    }

    private func voegPDFToe(_ url: URL) {
        let toegang = url.startAccessingSecurityScopedResource()
        defer { if toegang { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), PDFDocument(data: data) != nil,
            let naam = try? inbox.bewaarBestand(data, extensie: "pdf")
        else {
            melding = "De PDF kon niet worden geopend."
            return
        }
        var item = inbox.voegToe(.pdf(naam))
        let bestandsnaam = url.deletingPathExtension().lastPathComponent
        inbox.werkBij(item.id) { $0.bronNaam = bestandsnaam }
        item.bronNaam = bestandsnaam
        open(item)
    }
}

/// De knoppen in het ＋-menu.
struct InvoerMenuInhoud: View {
    let nieuw: () -> Void
    let plak: () -> Void
    let link: () -> Void
    let pdf: () -> Void
    let schermafdruk: () -> Void

    var body: some View {
        Button("Nieuw recept", systemImage: "square.and.pencil", action: nieuw)
        Section("Inlezen") {
            Button("Recept plakken", systemImage: "doc.on.clipboard", action: plak)
            Button("Link invoeren", systemImage: "link", action: link)
            Button("Kies een PDF", systemImage: "doc.richtext", action: pdf)
            Button("Kies een schermafdruk", systemImage: "photo.on.rectangle", action: schermafdruk)
        }
    }
}

/// `.dropDestination` alleen als `aan` (iPad).
private struct Slepen: ViewModifier {
    let aan: Bool
    let ontvang: (GesleeptItem) -> Void

    func body(content: Content) -> some View {
        if aan {
            content.dropDestination(for: GesleeptItem.self) { items, _ in
                guard let eerste = items.first else { return false }
                ontvang(eerste)
                return true
            }
        } else {
            content
        }
    }
}

extension View {
    /// Zie `InleesInvoer`.
    func inleesInvoer(nieuw: @escaping () -> Void, toonInbox: Binding<Bool>, slepen: Bool = false) -> some View {
        modifier(InleesInvoer(nieuw: nieuw, toonInbox: toonInbox, slepen: slepen))
    }
}
