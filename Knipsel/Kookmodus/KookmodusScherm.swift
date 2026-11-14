import SwiftUI
import UIKit

/// Maten van de kookmodus, los van de weergave zodat ze testbaar zijn (K5).
enum Kookmaten {
    /// Staptekst bij standaard Dynamic Type: op 70–80 cm leesbaar (≥ 30 pt iPhone, ≥ 28 pt iPad).
    static let stapBasisSmal: CGFloat = 30
    static let stapBasisBreed: CGFloat = 32
    /// Bovengrens bij de grootste tekstmaten: anders past een lang woord ("kerriepoeder") niet meer
    /// op één regel van een iPhone.
    static let stapMaximum: CGFloat = 56
    /// Vanaf deze breedte staan afvinklijst en stap naast elkaar (iPad; niet in een smalle Split View).
    static let breedVanaf: CGFloat = 700

    /// Lettergrootte van de huidige stap, meeschalend met Dynamic Type zoals bodytekst.
    static func stapGrootte(breed: Bool, tekstgrootte: DynamicTypeSize) -> CGFloat {
        let basis = breed ? stapBasisBreed : stapBasisSmal
        let kenmerken = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(tekstgrootte))
        let geschaald = UIFontMetrics(forTextStyle: .body).scaledValue(for: basis, compatibleWith: kenmerken)
        return min(stapMaximum, max(basis, geschaald))
    }
}

/// Kleuren van de schetsen (tab 4): papier en inkt, tomaat als accent. Donker is de standaard.
enum Kookkleuren {
    static let achtergrond = Color(licht: 0xFBF7F0, donker: 0x1F1B18)
    static let tekst = Color(licht: 0x2B2622, donker: 0xF6EFE4)
    static let kaart = Color(licht: 0xF0E8DC, donker: 0x2C2622)
    static let balkLeeg = Color(licht: 0xE2D8C9, donker: 0x4A423B)
    /// Ingrediënten van deze stap; contrast ≥ 4,5:1 op de achtergrond.
    static let markering = Color(licht: 0xB24B2A, donker: 0xF2A27F)
    static let accent = Color(licht: 0xD9613C, donker: 0xD9613C)
    static let gedimd = Color(licht: 0x6F665C, donker: 0xA89D90)
}

extension Color {
    fileprivate init(licht: UInt32, donker: UInt32) {
        func kleur(_ hex: UInt32) -> UIColor {
            UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? kleur(donker) : kleur(licht) })
    }
}

/// De kookmodus (K5–K7): één stap groot, ingrediënten van de stap oranje, het hele scherm is een
/// tikzone (rechts ⅔ = volgende, links ⅓ = vorige), vegen en toetsenbord werken ook, en het scherm
/// blijft aan. Op iPad links de afvinklijst, rechts de stap met de vorige en volgende gedimd. Met de
/// luidspreker aan wordt elke stap voorgelezen (K9), en daarna wacht Knipsel.
struct KookmodusScherm: View {
    let sessie: KookSessie
    /// "Gekookt" op het laatste scherm: kooklog bijwerken.
    var gekookt: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var systeemSchema
    @Environment(\.dynamicTypeSize) private var systeemgrootte
    @AppStorage(AppConfiguratie.sleutelExtraGrootte) private var extraGrootte = 0
    @AppStorage(AppConfiguratie.sleutelKookmodusDonker) private var altijdDonker = true
    @AppStorage(AppConfiguratie.sleutelSpraakAan) private var spraakAan = true

    @State private var schermAan = SchermAan()
    @State private var wissel: WisselSpreker
    @State private var voorlezer: VoorleesService
    @State private var spraak: Spraakbediening
    @State private var luisteraar = LuisterService()
    @State private var motorSpreker: MotorSpreker?

    init(sessie: KookSessie, gekookt: @escaping () -> Void = {}) {
        self.sessie = sessie
        self.gekookt = gekookt
        let wissel = WisselSpreker()
        let voorlezer = VoorleesService(spreker: wissel)
        _wissel = State(initialValue: wissel)
        _voorlezer = State(initialValue: voorlezer)
        _spraak = State(initialValue: Spraakbediening(sessie: sessie, voorlezer: voorlezer))
    }

    /// Luisteren alleen met de kookmodus open, op de voorgrond, en spraakbediening aan.
    private var moetLuisteren: Bool { spraakAan && scenePhase == .active }

    var body: some View {
        KookmodusInhoud(
            sessie: sessie, voorlezer: voorlezer, spraak: spraak, luisteraar: luisteraar, gekookt: gekookt,
            sluit: { dismiss() }, toestemmingGevraagd: { Task { await vraagToestemming() } }
        )
        .dynamicTypeSize(Leesinstellingen.vergroot(systeemgrootte, met: extraGrootte))
        .environment(\.colorScheme, altijdDonker ? .dark : systeemSchema)
        .preferredColorScheme(altijdDonker ? .dark : nil)
        .onAppear {
            schermAan.kookmodusGeopend()
            spraak.sluit = { dismiss() }
            spraak.tik = { [luisteraar] in luisteraar.motor.speelTik() }
            if voorlezer.isAan { voorlezer.leesHuidigeStap(van: sessie) }
        }
        .onDisappear {
            schermAan.kookmodusGesloten()
            stopLuisteren()
            voorlezer.stop()
        }
        .onChange(of: scenePhase) { _, fase in
            schermAan.faseGewijzigd(fase)
            // Naar de achtergrond: stil. Doorlezen met vergrendeld scherm kan later (fase 6/7).
            if fase == .background { voorlezer.stop() }
        }
        .task(id: moetLuisteren) {
            if moetLuisteren {
                await startLuisteren()
            } else {
                stopLuisteren()
            }
        }
    }

    // MARK: - Luisteren

    private func startLuisteren() async {
        spraak.instellingen = Spraakinstellingen.herkenner()
        luisteraar.resultaat = { [spraak] tekst, segment, definitief, nu in
            spraak.verwerk(tekst, segment: segment, definitief: definitief, nu: nu)
        }
        luisteraar.tik = { [spraak] nu in spraak.controleer(nu: nu) }
        var lasNet = false
        luisteraar.voorMicrofoon = { [voorlezer, wissel, luisteraar] in
            // Vanaf nu gaat de stem door de audiomotor, anders hoort de microfoon hem.
            lasNet = voorlezer.status == .spreekt
            voorlezer.stop()
            let spreker = motorSpreker ?? MotorSpreker(motor: luisteraar.motor)
            motorSpreker = spreker
            wissel.gebruik(spreker)
        }
        await luisteraar.start(contextwoorden: spraak.contextwoorden)
        if luisteraar.status != .luistert, wissel.gebruiktMotor {
            wissel.gebruik(nil)
        }
        // Was Knipsel aan het voorlezen toen de microfoon opende: opnieuw, nu via de motor.
        if lasNet { voorlezer.leesHuidigeStap(van: sessie) }
    }

    private func stopLuisteren() {
        if wissel.gebruiktMotor {
            voorlezer.stop()
            wissel.gebruik(nil)
        }
        luisteraar.stop()
    }

    /// Na de uitleg: toestemming vragen en, als die er is, beginnen.
    private func vraagToestemming() async {
        UserDefaults.standard.set(true, forKey: AppConfiguratie.sleutelSpraakUitlegGezien)
        if await luisteraar.vraagToestemming(), moetLuisteren {
            await startLuisteren()
        }
    }
}

/// De inhoud, los van scherm-aan en thema zodat hij ook te renderen is.
struct KookmodusInhoud: View {
    let sessie: KookSessie
    let voorlezer: VoorleesService
    /// Spraakbediening (fase 5); `nil` in renders zonder spraak.
    var spraak: Spraakbediening?
    var luisteraar: LuisterService?
    var gekookt: () -> Void = {}
    var sluit: () -> Void = {}
    /// "Doorgaan" na de uitleg over de microfoon.
    var toestemmingGevraagd: () -> Void = {}

    @Environment(\.dynamicTypeSize) private var tekstgrootte
    @Environment(\.openURL) private var openURL
    @AppStorage(AppConfiguratie.sleutelLettertype) private var lettertype: Lettertype = .serif
    @AppStorage(AppConfiguratie.sleutelVoorlezenAan) private var voorlezenStandaardAan = true
    @AppStorage(AppConfiguratie.sleutelSpraakAan) private var spraakAan = true
    @State private var spraakmelding: Spraakbediening.Melding?

    @State private var breedte: CGFloat = 0
    @State private var bevestiging: Bevestiging?
    @State private var flits: Zone?
    @State private var isVastgelegd = false
    @State private var bevestigingTaak: Task<Void, Never>?

    /// Voor renders zonder venster: forceer de opmaak.
    var breedOverschrijving: Bool?

    private enum Zone { case vorige, volgende }

    private struct Bevestiging: Equatable {
        let tekst: String
        let nummer: Int
    }

    private var breed: Bool { breedOverschrijving ?? (breedte >= Kookmaten.breedVanaf) }

    var body: some View {
        ZStack(alignment: .top) {
            Kookkleuren.achtergrond.ignoresSafeArea()
            if breed {
                HStack(spacing: 0) {
                    afvinklijst
                        .frame(width: lijstbreedte)
                    Rectangle().fill(Kookkleuren.balkLeeg).frame(width: 1).ignoresSafeArea()
                    VStack(spacing: 0) {
                        kopbalk
                        tikvlak { stapKolomBreed }
                        spraakbalk
                    }
                }
            } else {
                VStack(spacing: 0) {
                    kopbalk
                    tikvlak { stapKolomSmal }
                    spraakbalk
                }
            }
            if luisterstatus == .uitlegNodig, spraakAan {
                Spraakuitleg(
                    doorgaan: toestemmingGevraagd,
                    nietNu: {
                        spraakAan = false
                        luisteraar?.stop()
                    })
            }
            if let bevestiging {
                Text(bevestiging.tekst)
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Kookkleuren.tekst, in: Capsule())
                    .foregroundStyle(Kookkleuren.achtergrond)
                    .padding(.top, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(Kookkleuren.tekst)
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            breedte = $0
        }
        .background { toetsenbord }
        .onChange(of: sessie.gebeurtenisNummer) {
            bevestig()
            // Nieuwe stap: de vorige uitspraak stopt en de nieuwe stap wordt voorgelezen; daarna wacht hij.
            voorlezer.reageer(op: sessie.gebeurtenis, in: sessie)
        }
    }

    // MARK: - Kop

    private var kopbalk: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                Button(action: sluit) {
                    Image(systemName: "xmark")
                        .font(.title3.weight(.semibold))
                        .frame(width: 48, height: 48)
                        .background(Kookkleuren.kaart, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Sluit kookmodus")
                VStack(alignment: .leading, spacing: 2) {
                    // Porties naast de stap, zodat de titel de volle breedte naast de knoppen houdt.
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(sessie.isAfgerond ? "Klaar" : "Stap \(sessie.stapNummer) van \(sessie.aantalStappen)")
                            .font(.headline)
                        if !breed, sessie.receptPorties > 0 {
                            Text("· \(sessie.porties) pers.")
                                .font(.subheadline)
                                .foregroundStyle(Kookkleuren.gedimd)
                        }
                    }
                    .lineLimit(1)
                    Text(sessie.titel)
                        .font(.subheadline)
                        .foregroundStyle(Kookkleuren.gedimd)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                microfoon
                luidspreker
            }
            voortgang
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
        // De kop is oriëntatie, geen leestekst: begrensd zodat hij bij de grootste maten niet de
        // helft van het scherm neemt. De stap zelf schaalt wel volledig mee.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// Een balkje per stap: gedaan in tomaat, huidig in inkt, nog te gaan gedimd.
    private var voortgang: some View {
        HStack(spacing: 4) {
            ForEach(sessie.stappen) { stap in
                Capsule()
                    .fill(kleur(voortgangVan: stap.id))
                    .frame(height: 5)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Voortgang")
        .accessibilityValue(
            sessie.isAfgerond ? "alle stappen gedaan" : "stap \(sessie.stapNummer) van \(sessie.aantalStappen)")
    }

    private func kleur(voortgangVan index: Int) -> Color {
        if sessie.isAfgerond || index < sessie.huidigeIndex { return Kookkleuren.accent }
        return index == sessie.huidigeIndex ? Kookkleuren.tekst : Kookkleuren.balkLeeg
    }

    // MARK: - Stap

    private var stapGrootte: CGFloat { Kookmaten.stapGrootte(breed: breed, tekstgrootte: tekstgrootte) }

    private var stapLettertype: Font { .system(size: stapGrootte, design: lettertype.ontwerp) }

    /// iPhone: de stap groot, daaronder wat je in deze stap nodig hebt.
    @ViewBuilder private var stapKolomSmal: some View {
        if sessie.isAfgerond {
            eetSmakelijk
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    huidigeStapTekst
                    nodigInDezeStap
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .overlay(alignment: .bottom) { spraakfeedback }
            voorleesbalk
            zonewijzer
        }
    }

    /// iPad: vorige en volgende stap gedimd boven en onder de huidige.
    @ViewBuilder private var stapKolomBreed: some View {
        if sessie.isAfgerond {
            eetSmakelijk
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if let vorige = sessie.vorigeStap {
                        gedimdeStap(vorige)
                    }
                    huidigeStapTekst
                    if let volgende = sessie.volgendeStap {
                        gedimdeStap(volgende)
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            .overlay(alignment: .bottom) { spraakfeedback }
            voorleesbalk
            zonewijzer
        }
    }

    @ViewBuilder private var huidigeStapTekst: some View {
        if let stap = sessie.huidigeStap {
            VStack(alignment: .leading, spacing: 12) {
                if let groep = stap.groep, !groep.isEmpty {
                    Text(groep)
                        .font(.headline)
                        .foregroundStyle(Kookkleuren.gedimd)
                }
                Text(gemarkeerd(stap))
                    .font(stapLettertype)
                    .lineSpacing(stapGrootte * 0.22)
                    .fixedSize(horizontal: false, vertical: true)
                if let timer = Weergave.tijd(minuten: stap.timerSeconden / 60) {
                    SwiftUI.Label(timer, systemImage: "timer")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Kookkleuren.markering)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Stap \(sessie.stapNummer) van \(sessie.aantalStappen). \(stap.tekst)")
            .accessibilityHint("Veeg omhoog voor de volgende stap, omlaag voor de vorige.")
            .accessibilityAddTraits(.isHeader)
            .accessibilityAdjustableAction { richting in
                switch richting {
                case .increment: sessie.volgende()
                case .decrement: sessie.vorige()
                @unknown default: break
                }
            }
            .accessibilityAction(named: "Volgende stap") { sessie.volgende() }
            .accessibilityAction(named: "Vorige stap") { sessie.vorige() }
        }
    }

    private func gedimdeStap(_ stap: KookStap) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(stap.id + 1)")
                .font(.title3.bold())
            Text(stap.tekst)
                .font(.system(.title3, design: lettertype.ontwerp))
                .lineLimit(3)
        }
        .foregroundStyle(Kookkleuren.gedimd)
        .opacity(0.7)
        .accessibilityHidden(true)
    }

    /// De staptekst met de woorden die naar een ingrediënt verwijzen in oranje.
    private func gemarkeerd(_ stap: KookStap) -> AttributedString {
        var tekst = AttributedString(stap.tekst)
        for treffer in sessie.treffers(inStap: stap.id) {
            guard let bereik = Range(treffer.bereik, in: tekst) else { continue }
            tekst[bereik].foregroundColor = Kookkleuren.markering
            tekst[bereik].inlinePresentationIntent = .stronglyEmphasized
        }
        return tekst
    }

    @ViewBuilder private var nodigInDezeStap: some View {
        let nodig = sessie.ingredientenInHuidigeStap
        if !nodig.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Nodig in deze stap")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Kookkleuren.gedimd)
                ForEach(nodig) { ingredient in
                    ingredientTekst(ingredient)
                        .font(.system(.title3, design: lettertype.ontwerp))
                        .foregroundStyle(Kookkleuren.markering)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Kookkleuren.kaart, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .combine)
        }
    }

    /// Hoeveelheid vet, geschaald naar het gekozen aantal porties.
    private func ingredientTekst(_ ingredient: KookIngredient) -> Text {
        guard let maat = sessie.maat(van: ingredient), let naam = sessie.naam(van: ingredient) else {
            return Text(ingredient.ruweTekst)
        }
        let toelichting = ingredient.toelichting.map { Portieschaling.schaalToelichting($0, factor: sessie.factor) }
        let rest = [naam, toelichting].compactMap { $0 }.joined(separator: ", ")
        return Text("\(Text(maat).bold()) \(rest)")
    }

    /// Stille wegwijzer onderaan: links terug, rechts verder.
    private var zonewijzer: some View {
        HStack(spacing: 0) {
            Text("‹ vorige")
                .frame(maxWidth: .infinity)
                .frame(width: breedteStapvlak / 3)
            Text(sessie.isAfgerond ? "" : "volgende ›")
                .frame(maxWidth: .infinity)
        }
        .font(.footnote)
        .foregroundStyle(Kookkleuren.gedimd.opacity(0.8))
        .padding(.vertical, 10)
        .accessibilityHidden(true)
    }

    private var breedteStapvlak: CGFloat {
        let totaal = breedte > 0 ? breedte : 393
        return breed ? totaal - lijstbreedte - 1 : totaal
    }

    /// Afvinklijst op iPad: ±30 % van de breedte, wat breder bij de grootste tekstmaten.
    private var lijstbreedte: CGFloat {
        let totaal = breedte > 0 ? breedte : 1180
        return tekstgrootte.isAccessibilitySize ? min(460, totaal * 0.38) : min(380, max(300, totaal * 0.3))
    }

    // MARK: - Voorlezen

    /// Luidspreker aan/uit; golft mee zolang er voorgelezen wordt. De keuze wordt onthouden.
    private var luidspreker: some View {
        Button {
            voorlezer.zetAan(!voorlezer.isAan, sessie: sessie)
            voorlezenStandaardAan = voorlezer.isAan
        } label: {
            Image(systemName: voorlezer.isAan ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .symbolEffect(.variableColor.iterative, isActive: voorlezer.status == .spreekt)
                .font(.title3.weight(.semibold))
                .foregroundStyle(voorlezer.isAan ? Kookkleuren.accent : Kookkleuren.gedimd)
                .frame(width: 48, height: 48)
                .background(Kookkleuren.kaart, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Voorlezen")
        .accessibilityValue(voorlezer.isAan ? "aan" : "uit")
        .accessibilityHint(voorlezer.isAan ? "Tik om voorlezen uit te zetten" : "Tik om elke stap voor te laten lezen")
    }

    /// Onder de stap: tijdens het voorlezen een grote stopknop, daarna herhaal en ingrediënten.
    /// Alleen met de luidspreker aan; knoppen gaan voor de tikzones.
    @ViewBuilder private var voorleesbalk: some View {
        if voorlezer.isAan {
            HStack(spacing: 10) {
                if voorlezer.spreekt {
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative, isActive: voorlezer.status == .spreekt)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Kookkleuren.accent)
                        .accessibilityHidden(true)
                    Text("Leest voor…")
                        .font(.headline)
                        .foregroundStyle(Kookkleuren.gedimd)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    balkKnop("Stop", systemImage: "stop.fill", nadruk: true) { voorlezer.stop() }
                        .accessibilityHint("Stopt het voorlezen direct")
                } else {
                    balkKnop("Herhaal", systemImage: "arrow.counterclockwise") { sessie.herhaal() }
                        .accessibilityHint("Leest deze stap nog een keer voor")
                    balkKnop("Ingrediënten", systemImage: "list.bullet") { voorlezer.leesIngredienten(van: sessie) }
                        .accessibilityLabel("Lees ingrediënten")
                    Spacer(minLength: 0)
                }
            }
            .frame(minHeight: 52)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
    }

    private func balkKnop(
        _ titel: String, systemImage: String, nadruk: Bool = false, actie: @escaping () -> Void
    ) -> some View {
        Button(action: actie) {
            SwiftUI.Label(titel, systemImage: systemImage)
                .font(.headline)
                .lineLimit(1)
                .padding(.horizontal, 18)
                .frame(minHeight: 48)
                .background(nadruk ? Kookkleuren.accent : Kookkleuren.kaart, in: Capsule())
                .foregroundStyle(nadruk ? Color.white : Kookkleuren.tekst)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Spraak

    private var luisterstatus: LuisterService.Status { luisteraar?.status ?? .uit }

    /// Microfoon aan/uit: luisteren naar spraakcommando's. De keuze wordt onthouden.
    private var microfoon: some View {
        Button {
            spraakAan.toggle()
        } label: {
            Image(systemName: spraakAan ? "mic.fill" : "mic.slash.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(spraakAan ? Kookkleuren.accent : Kookkleuren.gedimd)
                .frame(width: 48, height: 48)
                .background(Kookkleuren.kaart, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Spraakbediening")
        .accessibilityValue(spraakAan ? "aan" : "uit")
        .accessibilityHint(
            spraakAan ? "Tik om niet meer te luisteren" : "Tik om Knipsel naar je stem te laten luisteren")
    }

    /// Onderin: luistert Knipsel, laadt hij het spraakmodel, of mag hij niet?
    @ViewBuilder private var spraakbalk: some View {
        if spraakAan, let inhoud = spraakbalkInhoud {
            HStack(spacing: 10) {
                inhoud
            }
            .font(.subheadline)
            .foregroundStyle(Kookkleuren.gedimd)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Kookkleuren.kaart.opacity(0.6))
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        }
    }

    private var spraakbalkInhoud: AnyView? {
        switch luisterstatus {
        case .luistert:
            return AnyView(
                Group {
                    Circle().fill(Color.green).frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    Text("Luistert · zeg \"volgende\", \"herhaal\", \"hoeveel …?\"")
                        .font(.footnote)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .accessibilityLabel("Knipsel luistert. Zeg volgende, herhaal of hoeveel.")
                    Spacer(minLength: 0)
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative, isActive: true)
                        .foregroundStyle(Color.green)
                        .accessibilityHidden(true)
                })
        case .start, .vraagtToestemming:
            return AnyView(
                Group {
                    ProgressView().controlSize(.small)
                    Text("Microfoon gaat aan…")
                })
        case .modelLaden(let voortgang):
            let procent = voortgang.map { " \(Int(($0 * 100).rounded())) %" } ?? ""
            return AnyView(
                Group {
                    ProgressView().controlSize(.small)
                    Text("Spraakmodel wordt gedownload…\(procent) Tikken werkt al.")
                        .lineLimit(2)
                })
        case .geweigerd:
            return AnyView(
                Group {
                    Image(systemName: "mic.slash.fill")
                        .foregroundStyle(Kookkleuren.markering)
                        .accessibilityHidden(true)
                    Text("Knipsel mag de microfoon niet gebruiken. Tikken werkt gewoon.")
                        .lineLimit(3)
                    Spacer(minLength: 0)
                    Button("Instellingen") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Kookkleuren.accent)
                    .accessibilityHint(
                        "Opent de instellingen van Knipsel, om microfoon en spraakherkenning toe te staan")
                })
        case .nietBeschikbaar(let reden):
            return AnyView(
                Group {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Kookkleuren.markering)
                        .accessibilityHidden(true)
                    Text("\(reden) Tikken werkt gewoon.")
                        .lineLimit(3)
                })
        case .uit, .uitlegNodig:
            return nil
        }
    }

    /// "✓ volgende" (1,5 s) en het antwoord op "hoeveel …?", boven de spraakbalk.
    private var spraakfeedback: some View {
        VStack(spacing: 12) {
            if let antwoord = spraak?.antwoord {
                Antwoordkaart(antwoord: antwoord, lettertype: lettertype) { spraak?.sluitAntwoord() }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .task(id: antwoord.nummer) {
                        try? await Task.sleep(for: .seconds(8))
                        guard !Task.isCancelled else { return }
                        withAnimation { spraak?.sluitAntwoord() }
                    }
            }
            if let spraakmelding {
                Text(spraakmelding.tekst)
                    .font(.headline)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Kookkleuren.tekst, in: Capsule())
                    .foregroundStyle(Kookkleuren.achtergrond)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, alignment: .bottom)
        .task(id: spraak?.melding?.nummer) {
            guard let melding = spraak?.melding else { return }
            withAnimation(.easeOut(duration: 0.15)) { spraakmelding = melding }
            AccessibilityNotification.Announcement(melding.tekst).post()
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.3)) { spraakmelding = nil }
        }
    }

    // MARK: - Klaar

    private var eetSmakelijk: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            Image(systemName: "fork.knife")
                .font(.system(size: 44))
                .foregroundStyle(Kookkleuren.accent)
                .accessibilityHidden(true)
            Text("Eet smakelijk")
                .font(.system(size: stapGrootte * 1.2, weight: .semibold, design: lettertype.ontwerp))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            if isVastgelegd {
                SwiftUI.Label("Vastgelegd in je kooklog", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(Kookkleuren.gedimd)
            } else {
                Button {
                    gekookt()
                    isVastgelegd = true
                } label: {
                    SwiftUI.Label("Gekookt", systemImage: "checkmark")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(Kookkleuren.accent, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Zet vandaag in het kooklog van dit recept")
            }
            Button("Sluiten", action: sluit)
                .font(.headline)
                .padding(12)
                .buttonStyle(.plain)
                .foregroundStyle(Kookkleuren.gedimd)
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) { spraakfeedback }
        .accessibilityAction(named: "Vorige stap") { sessie.vorige() }
    }

    // MARK: - Afvinklijst (iPad)

    private var afvinklijst: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ingrediënten")
                        .font(.headline)
                        .foregroundStyle(Kookkleuren.gedimd)
                        .accessibilityAddTraits(.isHeader)
                    if sessie.receptPorties > 0 {
                        PortiesKnoppen(
                            porties: sessie.porties, wijzig: { sessie.wijzigPorties(naar: $0) },
                            kleur: Kookkleuren.tekst)
                    }
                }
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                let nodig = Set(sessie.ingredientenInHuidigeStap.map(\.id))
                ForEach(sessie.ingredienten) { ingredient in
                    if let groep = ingredient.groep, !groep.isEmpty,
                        ingredient.id == 0 || sessie.ingredienten[ingredient.id - 1].groep != groep
                    {
                        Text(groep)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Kookkleuren.gedimd)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                    }
                    afvinkRegel(ingredient, nodig: nodig.contains(ingredient.id))
                }
            }
            .padding(.vertical, 20)
        }
        .background(Kookkleuren.kaart.opacity(0.5))
    }

    private func afvinkRegel(_ ingredient: KookIngredient, nodig: Bool) -> some View {
        let isAf = sessie.isAfgevinkt(ingredient)
        let kleur: Color = isAf ? Kookkleuren.gedimd : (nodig ? Kookkleuren.markering : Kookkleuren.tekst)
        return Button {
            sessie.wisselAfgevinkt(ingredient)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: isAf ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isAf ? Kookkleuren.gedimd : (nodig ? Kookkleuren.markering : Kookkleuren.gedimd))
                ingredientTekst(ingredient)
                    .font(.system(.title3, design: lettertype.ontwerp))
                    .strikethrough(isAf)
                    .foregroundStyle(kleur)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(nodig && !isAf ? Kookkleuren.markering.opacity(0.12) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(
            [isAf ? "afgevinkt" : nil, nodig ? "nodig in deze stap" : nil].compactMap { $0 }.joined(separator: ", ")
        )
        .accessibilityHint("Tik om af te vinken")
    }

    // MARK: - Bediening

    /// Het hele vlak is een tikzone: links ⅓ = vorige, rechts ⅔ = volgende. Vegen werkt ook. Knoppen
    /// erin (sluiten, gekookt) gaan voor.
    private func tikvlak<Inhoud: View>(@ViewBuilder _ inhoud: () -> Inhoud) -> some View {
        let inhoud = inhoud()
        return GeometryReader { vlak in
            VStack(spacing: 0) { inhoud }
                .frame(width: vlak.size.width, height: vlak.size.height)
                .overlay(alignment: flits == .vorige ? .leading : .trailing) {
                    if let flits {
                        Kookkleuren.tekst.opacity(0.08)
                            .frame(width: flits == .vorige ? vlak.size.width / 3 : vlak.size.width * 2 / 3)
                            .allowsHitTesting(false)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { plek in
                    tik(plek.x < vlak.size.width / 3 ? .vorige : .volgende)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 40).onEnded { veeg in
                        let dx = veeg.translation.width
                        guard abs(dx) > 60, abs(dx) > abs(veeg.translation.height) * 1.5 else { return }
                        tik(dx < 0 ? .volgende : .vorige)
                    })
        }
    }

    private func tik(_ zone: Zone) {
        withAnimation(.easeOut(duration: 0.1)) { flits = zone }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            withAnimation(.easeOut(duration: 0.25)) { flits = nil }
        }
        switch zone {
        case .vorige: sessie.vorige()
        case .volgende: sessie.volgende()
        }
    }

    /// Korte bevestiging in beeld (en voor VoiceOver) na elke stapwissel.
    private func bevestig() {
        let tekst: String
        switch sessie.gebeurtenis {
        case .volgende, .naarStap: tekst = "Stap \(sessie.stapNummer)"
        case .vorige: tekst = sessie.isAfgerond ? "Klaar" : "Terug naar stap \(sessie.stapNummer)"
        case .afgerond: tekst = "Klaar"
        case .grens: tekst = sessie.isAfgerond ? "Klaar" : (sessie.isEersteStap ? "Eerste stap" : "Laatste stap")
        case .herhaal, nil: return
        }
        withAnimation(.easeOut(duration: 0.15)) {
            bevestiging = Bevestiging(tekst: tekst, nummer: sessie.gebeurtenisNummer)
        }
        AccessibilityNotification.Announcement(tekst).post()
        bevestigingTaak?.cancel()
        bevestigingTaak = Task {
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.3)) { bevestiging = nil }
        }
    }

    /// Hardwaretoetsenbord (iPad): spatie en → verder, ← terug, esc sluit.
    private var toetsenbord: some View {
        ZStack {
            Button("Volgende stap") { sessie.volgende() }
                .keyboardShortcut(.space, modifiers: [])
            Button("Volgende stap") { sessie.volgende() }
                .keyboardShortcut(.rightArrow, modifiers: [])
            Button("Vorige stap") { sessie.vorige() }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("Sluit kookmodus", action: sluit)
                .keyboardShortcut(.escape, modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

/// − aantal + voor porties, met grote raakvlakken en als één instelbaar element voor VoiceOver.
struct PortiesKnoppen: View {
    let porties: Int
    let wijzig: (Int) -> Void
    var kleur: Color = .accentColor

    var body: some View {
        HStack(spacing: 4) {
            Button {
                wijzig(porties - 1)
            } label: {
                Image(systemName: "minus").frame(width: 36, height: 36)
            }
            .disabled(porties <= 1)
            Text("\(porties) pers.")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .fixedSize()
                .frame(minWidth: 56)
            Button {
                wijzig(porties + 1)
            } label: {
                Image(systemName: "plus").frame(width: 36, height: 36)
            }
            .disabled(porties >= 99)
        }
        .buttonStyle(.plain)
        .foregroundStyle(kleur)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Porties")
        .accessibilityValue(Weergave.porties(porties) ?? "")
        .accessibilityAdjustableAction { richting in
            switch richting {
            case .increment: wijzig(min(99, porties + 1))
            case .decrement: wijzig(max(1, porties - 1))
            @unknown default: break
            }
        }
    }
}

#if DEBUG
    #Preview("iPhone") {
        KookmodusScherm(sessie: KookSessie(recept: Opslag.voorbeeld.eersteRecept, porties: 6))
    }
#endif
