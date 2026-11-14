# Knipsel — ontwerp v0.2 (concept)

Recepten-app voor iPhone en iPad. Je fotografeert een recept uit een krant of tijdschrift; Knipsel bewaart
alleen de recepttekst, deelt hem in en helpt je in de keuken: groot leesbaar, voorlezen in jouw tempo en
bediening met je stem, zodat je het scherm met vieze handen niet hoeft aan te raken.

- Schermschetsen: [`docs/ux/schetsen.html`](ux/schetsen.html) (open in een browser)
- Haalbaarheidsproef herkennen + indelen: [`docs/spikes/ocr-en-indeling.md`](spikes/ocr-en-indeling.md)
- Uitvoering in fasen: GitHub-issues met label `fase-*` (overzicht in §9)

## 1. Vastgestelde keuzes

| # | Keuze | Besluit (13-11-2026) |
|---|---|---|
| B1 | Naam | Knipsel (repo `pbijkerk/knipsel`, bundle-ID `com.peterbijkerk.knipsel`) |
| B2 | Zichtbaarheid repo | Publiek, zoals FableFlux |
| B3 | Minimale versie | iOS/iPadOS 26 |
| B4 | Synchronisatie | iCloud tussen eigen toestellen **en** delen met een huisgenoot |
| B5 | Testen | TestFlight via Xcode Cloud, interne groep (zoals FableFlux) |
| B6 | Categorieën (V1) | Een recept kan in **meerdere** categorieën staan |
| B7 | Paginafoto (V2) | **Alleen de tekst** bewaren; de foto verdwijnt na het knippen |
| B8 | Delen (V3) | **Per recept kiezen**: "Mijn recepten" (privé) of "Thuis" (gedeeld) |
| B9 | Toestellen (V4) | iPhone 14 Plus, iPhone 15 Plus, iPad (10e generatie). **Geen van drieën heeft Apple Intelligence**, dus geen on-device taalmodel |
| B10 | Indelen | Regels op het toestel als basis, **optioneel Claude** (eigen API-sleutel in de Keychain; alleen de herkende tekst gaat naar Anthropic, nooit de foto), zoals FableFlux |
| B11 | Impliciete commando's (V5) | **Standaard aan**: "oké", "klaar", "gedaan" = volgende stap, met zichtbare melding en "terug" om te herstellen |

## 2. Eisen (K1–K14) met onderbouwing

Elke eis heeft een wetenschappelijke of praktijkbasis. De nummers keren terug in de schetsen en issues.

| Eis | Wat | Basis |
|---|---|---|
| **K1** Alleen de recepttekst | Na de foto kiest Knipsel zelf welke tekstblokken bij het recept horen; advertenties, lezersbrieven en kolommen van andere artikelen vallen weg. De gebruiker corrigeert met een tik per blok. | Praktijk: Mela laat gescande blokken toewijzen aan titel/ingrediënten/bereiding (Mela Help; MacStories). Proef: een taalmodel wees advertentie en lezersbrief correct af (spike). Op Peters toestellen: regels + optioneel Claude (B10). |
| **K2** Letterlijke tekst, eerst controleren | De tekst blijft letterlijk de herkende tekst; AI deelt alleen in, herschrijft niet. Onzekere woorden worden oranje onderstreept. | Proef: de AI die zelf herschreef, liet hoeveelheden weg en maakte "olifolie" (spike). Mensen gaan automatisering te snel vertrouwen (*automation bias*, Parasuraman & Manzey, 2010): dus zichtbaar maken wat onzeker is. |
| **K3** Vaste structuur | Titel, intro, porties, tijd, ingrediënten (hoeveelheid · eenheid · naam, met groepen als "Voor de saus"), genummerde stappen, notities, bron (blad, datum, pagina). | Nodig voor schalen, voorlezen per stap en "hoeveel …?". |
| **K4** Categorieën en labels | Indeling naar gang (13 standaardcategorieën, zie §5; een recept kan in meerdere, B6) plus vrije labels (vegetarisch, snel, …). Alles hernoemen, verbergen, verplaatsen, toevoegen en verwijderen. AI stelt categorie en labels voor. | Facetclassificatie: meerdere onafhankelijke kenmerken vinden beter dan één diepe boom (Hearst, 2006). |
| **K5** Goed leesbaar | Dynamic Type; leesweergave in serif (New York) met ±60 tekens per regel; kookmodus ≥ 30 pt op iPhone (≥ 28 pt op iPad) zodat het op 70–80 cm vlot leesbaar blijft; contrast ≥ 4,5:1; donkere modus. | Leessnelheid daalt onder de *critical print size* (≈ 0,2° x-hoogte, Legge & Bigelow, 2011): op 70–80 cm is dat 2,4–2,8 mm x-hoogte, ±30–34 pt op een iPhone (x-hoogte ≈ halve korps). Regellengte 55–70 tekens (Dyson, 2004). WCAG 2.2 (1.4.3). |
| **K6** iPad naast elkaar | Op iPad staan ingrediënten en bereiding naast elkaar; in de kookmodus de huidige stap groot, de rest gedimd. | *Spatial contiguity*: samenhangende informatie dicht bij elkaar (Mayer, 2009). Praktijk: Mela, Paprika. |
| **K7** Aanraakloos koken | Na "Kook dit" hoeft niemand het scherm nog aan te raken; aanraken mag wel (hele scherm = grote tikzone, ook met knokkel of elleboog). Scherm blijft aan. | Gemiddeld 5,8 aanrakingen van de tablet per half uur koken; 34 % waste na rauwe kip de handen niet voor ze de tablet aanraakten; *Salmonella* overleeft > 24 uur op het scherm (safefood, 2024). FDA-survey: maar ⅓ wast handen na aanraken van het toestel (Lando e.a., 2018). |
| **K8** Spraakbesturing zonder wekwoord | In de kookmodus luistert Knipsel naar korte commando's ("volgende", "herhaal", "hoeveel boter?"), óók naar impliciete signalen als "oké" en "klaar". | In een kookstudie kwam bijna een kwart van de beurten via impliciete signalen ("oké", "ja") in plaats van commando's (Vtyurina & Fourney, CHI 2018). |
| **K9** Voorlezen in jouw tempo | Voorlezen per stap; daarna wacht Knipsel tot jij verder wilt. Nooit automatisch doorlezen. "Stop" werkt ook midden in een zin. | *Segmenting principle*: mensen leren en volgen beter met instructie in zelfgekozen stukken dan als doorlopend geheel (Mayer & Pilegard, 2014). |
| **K10** Siri en snelkoppelingen | "Hé Siri, kook pompoensoep met Knipsel", en stappen besturen vanaf het vergrendelscherm, de Actieknop, AirPods. | Praktijk: Siri eist de appnaam in elke zin; daarom is Siri voor starten en "buiten de app", K8 voor tijdens het koken. |
| **K11** Timers uit de tekst | "laat 20 minuten zachtjes koken" wordt een timerknop; Knipsel vraagt na het voorlezen "Zal ik een timer van 20 minuten zetten?". Alarm ook bij vergrendeld scherm of stille modus. | Proef: tijden werden correct uit de stappen gehaald (spike). AlarmKit (iOS 26). |
| **K12** Privé en offline | Herkennen, spraak en voorlezen gebeuren op het toestel. Geen account, geen eigen server; alleen iCloud. Uitzondering die je zelf aanzet: indelen met Claude stuurt alleen de herkende tekst naar Anthropic. | Vision en Speech draaien on-device (proef op deze Mac); B10. |
| **K13** Delen met huisgenoot | Een gedeeld kookboek "Thuis" dat beide gebruikers zien en aanvullen. | Besluit B4. |
| **K14** Bron en auteursrecht | Bron blijft bij elk recept staan. De paginafoto wordt niet bewaard (B7). | Kopiëren voor eigen gebruik valt onder de thuiskopie (art. 16b Auteurswet); publiek delen niet. Echte krantenfoto's komen dus ook niet in deze publieke repo. |

### 2.1 Eisen U1–U8: mooier en makkelijker (UX-ronde 14-11-2026)

Aanvulling op K1–K14 na gebruik van fase 1–5. Schetsen en onderbouwing: `docs/ux/schetsen-v2.html`.
Gekozen door Peter: Kookmodus A + iPad B (#21), Recept A (#22), Bibliotheek A → B (#23), iPad A (#24).

| Eis | Wat | Basis |
|---|---|---|
| **U1** Elk recept een eigen gezicht | Kleur, symbool of eigen foto in de lijst | Pirolli & Card (1999); Paivio (1971) |
| **U2** Hoofdactie onder de duim | *Knip* en *Kook dit* groot en onderin | Fitts (1954); Hoober (2013) |
| **U3** Bediening die je ziet | Tikvlakken en spraakstatus zichtbaar | Norman (2013); Nielsen (1994) |
| **U4** Eerst klaarzetten, dan koken | Wat nu nodig is en wat komt | Sweller (1988); Vtyurina & Fourney (2018) |
| **U5** Rust | Eén chiprij, labels achter *Filter* | Hick (1952); Tractinsky e.a. (2000) |
| **U6** Geen lege vlakken op iPad | Overzicht of inhoud, nooit "Kies een recept" | Shneiderman (1996) |
| **U7** Leesbaar op aanrechtafstand | iPad-kookmodus ±40 pt (1–1,5 m) | Legge & Bigelow (2011) |
| **U8** Kookgeschiedenis telt | "n× gekookt", sterren, "Verder met…" | Zeigarnik (1927); Mark e.a. (2008) |

## 3. De belangrijkste stromen

### 3.1 Knippen (foto → recept)

1. **Vastleggen** — `VNDocumentCameraViewController`: rechtzet de pagina, meerdere pagina's per recept
   (recept op twee pagina's). Of kies een bestaande foto (PhotosPicker).
2. **Herkennen** — Vision `RecognizeTextRequest`, taal `nl-NL` (ondersteund, gecontroleerd), met
   taalcorrectie en per regel een betrouwbaarheid en kader.
3. **Indelen** — welk blok is titel / intro / ingrediënt / stap / niet-recept, plus voorstel voor
   categorieën en labels. Drie uitvoerders achter één `Indeler`-protocol, met dezelfde uitvoer
   (alleen bloknummers per rol; de tekst blijft letterlijk):
   - **Regels (altijd, basis):** grootste letter = titel; regel die begint met getal + eenheid of een
     bekend ingrediënt = ingrediënt; genummerde of lange alinea's = bereiding; blokken buiten de kolommen
     van titel/ingrediënten/bereiding of met reclamewoorden ("halen", "betalen", "geldig t/m", "€") = weg.
     Vision levert per regel het kader, dus kolommen en lettergrootte zijn bekend.
   - **Claude (optioneel, B10):** zelfde opdracht als in de proef (`claude-haiku-4-5`, sleutel in de
     Keychain, alleen tekst + bloknummers). Gebruikt als er een sleutel en internet is; anders de regels.
   - **On-device model:** vanzelf gebruikt op een toekomstig toestel met Apple Intelligence; niet op
     Peters huidige toestellen (B9).
   *Code voegt daarna samen*: stapregels aan elkaar tot een nieuw nummer begint, ingrediëntregels via een
   Nederlandse hoeveelheidsparser (`½ tl`, `2 el`, `1 l`, `ca. 1 kg`, `snufje`, `teen`, `blik`).
4. **Knipselscherm** — de foto met gekleurde kaders per blok: titel (tomaat), ingrediënten (groen),
   bereiding (blauw), weggelaten (grijs gearceerd). Tik = rol wisselen, sleep = blokken samen selecteren.
5. **Controle** — het gestructureerde recept naast (iPad) of onder (iPhone) de uitsnede; onzekere woorden
   oranje; categorie- en labelvoorstellen als knopjes; bron vooraf ingevuld (datum uit de foto).
6. **Bewaren** — alleen de tekst; de foto wordt na het knippen weggegooid (B7).

### 3.2 Koken (aanraakloos)

```
[Recept] --"Kook dit" / Siri--> [Kookmodus: stap 1]
   ├─ leest stap voor (als voorlezen aan)
   ├─ wacht ── "volgende"/"oké"/"klaar"/tik ──> stap 2
   │        ── "herhaal"  ──> leest opnieuw
   │        ── "stop"     ──> stil (ook midden in een zin)
   │        ── "hoeveel bouillon?" ──> "1 liter groentebouillon"
   │        ── "timer" / "ja" (na voorstel) ──> AlarmKit-timer + Live Activity
   └─ laatste stap ── "klaar" ──> "Eet smakelijk" · "Gekookt op" vastleggen
```

- Scherm blijft aan (`isIdleTimerDisabled`) zolang de kookmodus open is.
- Live Activity op het vergrendelscherm (alle toestellen) en in het Dynamic Island (alleen iPhone 15 Plus): "Stap 3 van 4 · ⏱ 18:42".
- Ingrediënten die in de huidige stap voorkomen worden in de lijst uitgelicht; afvinken kan met "gedaan".

## 4. Bediening zonder handen — lagen

| Laag | Wanneer | Techniek | Status |
|---|---|---|---|
| 1. Stem in de app (primair) | Tijdens koken, app open | `SpeechAnalyzer` + `DictationTranscriber` (`nl_NL` on-device, gecontroleerd); terugval `SFSpeechRecognizer` on-device. `AVAudioEngine` met *voice processing* (echo-onderdrukking), zodat Knipsel zijn eigen stem niet hoort en "stop" midden in het voorlezen werkt. | Kern, fase 5 |
| 2. Siri / App Shortcuts | Starten, of app op achtergrond / vergrendeld | App Intents: `KookReceptIntent` (met `AppEntity` Recept), `VolgendeStap`, `VorigeStap`, `HerhaalStap`, `LeesIngredienten`, `ZetTimer`. Verschijnen vanzelf in Siri, Spotlight en Opdrachten. | Fase 6 |
| 3. Actieknop | Eén knop met knokkel = volgende stap | Snelkoppeling "Volgende stap" aan de Actieknop | Alleen iPhone 15 Pro en nieuwer; niet op Peters toestellen, geparkeerd |
| 4. AirPods / Apple Watch | Steeltje indrukken = volgende, dubbel = vorige | `MPRemoteCommandCenter` + Nu speelt; de Watch toont dan vanzelf de bediening | Fase 6, eerst proef (S3) |
| 5. Grote tikzones | Altijd | Rechter ⅔ van het scherm = volgende, linker ⅓ = vorige; werkt met knokkel/elleboog; toetsenbord (spatie/pijlen) op iPad | Fase 3 |
| 6. Zwaaien (experiment) | Hand voor de camera = volgende | Vision hand-pose via voorcamera | Geparkeerd; batterij en privacy afwegen |

### Spraakcommando's (eerste set)

| Zeg | Doet |
|---|---|
| "volgende", "verder", "oké", "klaar", "gedaan"¹ | volgende stap (en voorlezen) |
| "vorige", "terug" | vorige stap |
| "herhaal", "nog een keer", "wat zei je?" | huidige stap opnieuw |
| "stop", "stil", "pauze" | stopt met voorlezen (direct) |
| "lees voor", "ga door" | voorlezen hervatten |
| "langzamer", "sneller" | spreektempo |
| "ingrediënten", "wat heb ik nodig?" | ingrediënten voor deze stap (of alles) |
| "hoeveel ‹ingrediënt›?" | "200 milliliter kokosmelk" (rekening houdend met geschaalde porties) |
| "stap 3" | spring naar stap 3 |
| "timer ‹n› minuten", "zet de timer", "hoe lang nog?" | timer zetten / resterende tijd |
| "stoppen met koken" | kookmodus sluiten |

¹ Impliciete signalen ("oké", "klaar", "gedaan") staan standaard aan (B11), met melding en "terug" om te herstellen; uit te zetten in Instellingen.

Regels tegen vals alarm (afzuigkap, radio, gesprek):
- Alleen korte uitingen (≤ 4 woorden) die een commando zijn tellen; een lange zin met "volgende" erin niet.
- Optioneel wekwoord "Knipsel, …" voor drukke keukens.
- Elk begrepen commando kort zichtbaar ("✓ volgende") met een zacht tikgeluid; een tik op "ongedaan" of
  "vorige" herstelt (zichtbaarheid van systeemstatus, Nielsen).

### Voorlezen

- `AVSpeechSynthesizer` met Nederlandse stem; Knipsel wijst op het downloaden van een *verbeterde* stem
  (Instellingen › Toegankelijkheid › Gesproken materiaal). Op deze Mac beschikbaar: Xander (nl-NL),
  Ellen (nl-BE).
- Uitspraakregels vóór het voorlezen: `2 el` → "twee eetlepels", `½ tl` → "een halve theelepel",
  `ca.` → "circa", `180 °C` → "180 graden", `1 l` → "1 liter", `3-4` → "drie à vier".
- Tempo instelbaar (0,8×–1,2×), plus "langzamer/sneller" tijdens het koken.
- Instelling "lees bij elke stap ook de ingrediënten van die stap".
- Audio-sessie zo dat muziek of een podcast zachter gaat (*ducking*) in plaats van stopt.

## 5. Categorieën en labels

**Standaardcategorieën (gang):** Ontbijt & brunch · Lunch · Soepen · Voorgerechten · Salades ·
Hoofdgerechten · Bijgerechten · Nagerechten · Gebak & taarten · Brood · Sauzen & dressings · Borrelhapjes ·
Dranken. Plus de vaste bak "Zonder categorie".

**Standaardlabels:** Vegetarisch · Vegan · Vis · Vlees · Snel (< 30 min) · Feestelijk · Voorbereiden.

Beheer (Instellingen › Categorieën): hernoemen, SF-symbool kiezen, volgorde slepen, verbergen,
toevoegen, verwijderen (recepten gaan dan naar "Zonder categorie", met bevestiging en aantal).
Een recept heeft één of meer categorieën (B6) en nul of meer labels.

## 6. Schermen (zie schetsen)

| # | Scherm | iPhone | iPad |
|---|---|---|---|
| 1 | Bibliotheek | Lijst met categoriechips en zoeken (ook op ingrediënt: "prei") | Zijbalk categorieën · lijst · recept (3 kolommen) |
| 2 | Knippen | Camera → knipselscherm met gekleurde blokken | Idem, controle naast de foto |
| 3 | Recept | Titel, porties-stepper, ingrediënten (afvinken), stappen | Ingrediënten links, bereiding rechts |
| 4 | Kookmodus | Eén stap groot, voortgang, microfoonstatus | Ingrediënten + huidige stap groot, rest gedimd |
| 5 | Vergrendelscherm | Live Activity met stap en timer | Idem |
| 6 | Categorieën beheren | Lijst met slepen, symbool, aantal | Idem |

## 7. Architectuur

- **SwiftUI**, iOS/iPadOS 26, Swift 6. Alleen Apple-frameworks, geen externe packages (lijn FableFlux).
- **Opslag: Core Data + `NSPersistentCloudKitContainer`**, niet SwiftData. Reden: SwiftData synchroniseert
  alleen met de privé-database; delen met een andere Apple ID (CloudKit *shared database*) kan alleen via
  Core Data (Apple DTS op de developer-forums, 2024–2026). Twee stores: privé ("Mijn recepten") en gedeeld
  ("Thuis", gedeelde *record zone* via `UICloudSharingController`).
  - CloudKit-eisen: alle attributen optioneel of met standaardwaarde, geen unieke constraints,
    relaties met inverse.
- **Model (eerste versie):**
  - `Recept`: titel, intro, porties, bereidingstijd, totale tijd, notities, bronNaam, bronDatum, bronPagina,
    beoordeling, laatstGekooktOp, aangemaaktOp, kookboek (Mijn recepten / Thuis); veel-op-veel met `Categorie`.
    Modelversie 2 (#23, 3b): `fotoData` (eigen gerechtfoto, JPEG 4:3 ≤ 1600 px, *Allows External Storage*,
    in CloudKit een asset) en `fotoGewijzigdOp` (`nil` = geen foto). Nooit de krantenfoto (B7).
  - `Ingredient`: volgorde, groep, ruweTekst, hoeveelheid, hoeveelheidTot, eenheid, naam, toelichting
  - `Stap`: volgorde, groep, tekst, timerSeconden
  - `Categorie`: naam, symbool, volgorde, verborgen, isStandaard
  - `Label`: naam
  - `Kooklog`: datum, notitie
- **Diensten:** `ScanService` (VisionKit/Vision), `Indeler`-protocol met `RegelIndeler`, `ClaudeIndeler` en `ModelIndeler`, `KeychainService`,
  `IngredientParser` (puur, goed testbaar), `VoorleesService` (AVSpeechSynthesizer + uitspraakregels),
  `LuisterService` (AVAudioEngine + SpeechAnalyzer), `CommandoHerkenner` (puur, testbaar),
  `KookSessie` (toestandsmachine stap/voorlezen/luisteren/timers), `TimerService` (AlarmKit),
  `KookActivity` (ActivityKit), App Intents.
- **Rechten (Info.plist):** camera, microfoon, spraakherkenning, foto's (alleen kiezen), AlarmKit. Netwerk alleen voor Claude (optioneel) en iCloud.

## 8. Risico's en proeven

| # | Risico | Proef | Status |
|---|---|---|---|
| S1 | OCR op echte krantenfoto's: kolommen, glanzend papier, krom blad, `l`/`1` | 10 echte pagina's (blijven lokaal) | Synthetisch gedaan: `1 l groentebouillon` → `1 groentebouillon`, `ë` verdween. Echte foto's nog doen |
| S2 | Indeling op wisselende layouts: regels vs. Claude | Zelfde 10 pagina's | Synthetisch met on-device model: 100 % juist. Regels en Claude nog te meten |
| S3 | AirPods/Watch-bediening vraagt "Nu speelt"; telt spraaksynthese daarvoor mee? | Klein testproject | Open |
| S4 | Altijd luisteren: batterij, warmte, valse commando's bij afzuigkap | 30 min koken met meting | Open |
| S5 | Geen Apple Intelligence op Peters toestellen (B9) | Regelindeler als basis, Claude optioneel | Ontworpen |
| S6 | Spraakherkenning en voorlezen op iPhone 14 Plus (A15) en iPad 10 (A14): beschikbaar en snel genoeg? | Testscherm in een vroege TestFlight-build | Open |

## 9. Fasering (issues)

| Fase | Inhoud | Waarom in deze volgorde |
|---|---|---|
| 0 | Repo, CI, Xcode Cloud → TestFlight | Testen kan vanaf dag één |
| 1 | Datamodel (Core Data + iCloud privé), bibliotheek, categorieën beheren, recept handmatig invoeren, receptweergave | Alles bouwt hierop |
| 2 | Knippen: scannen, herkennen, indelen, knipselscherm, controle, ingrediëntparser | De kernbelofte |
| 3 | Kookmodus visueel: stap voor stap, groot, scherm aan, tikzones, afvinken, porties schalen | Bruikbaar in de keuken zonder spraak |
| 4 | Voorlezen per stap, uitspraakregels, tempo | Vóór spraak: commando's sturen het voorlezen |
| 5 | Spraakbesturing in de app | Grootste UX-winst, hoogste risico (S4) |
| 6 | Siri, App Shortcuts, Actieknop, AirPods/Watch | Bouwt op de `KookSessie` van 3–5 |
| 7 | Timers (AlarmKit) en Live Activity | Los te bouwen na fase 3 |
| 8 | Delen met huisgenoot | Raakt het datamodel; na stabiel gebruik |

## 10. Eigen suggesties (nog niet ingepland)

1. **"Vraag de chef"** — vrije vraag tijdens het koken ("kan ik ook crème fraîche gebruiken?"), beantwoord
   door Claude (of later het on-device model), alleen met het recept als context en met een zichtbaar "suggestie"-label.
2. **Boodschappenlijst** — ingrediënten (geschaald) naar Herinneringen, op winkelvolgorde gegroepeerd.
3. **"Wat kan ik maken met …"** — zoeken op wat je in huis hebt ("prei, ei, kaas").
4. **Menu koken** — twee of drie recepten tegelijk in de kookmodus, met wisselen per stem ("naar de saus").
5. **Gekookt-logboek** — datum, sterren en notitie ("minder zout"); tonen bij het recept.
6. **Eigen foto van het resultaat** — handig in de lijst (plaatjes zeggen meer dan woorden), los van de
   krantenfoto.
7. **Import via delen** — een link naar een receptsite (schema.org-recept) of een PDF; zelfde controlescherm.
8. **Spotlight en Handoff** — recept zoeken vanuit iOS; op de iPhone beginnen, op de iPad verder koken.
9. **Seizoen** — "nu in het seizoen"-filter op basis van ingrediënten.
10. **Export** — alle recepten als JSON en als nette PDF (afdrukken, back-up).
11. **Mac** — de iPad-app draait ook op een Mac met Apple-chip; scannen dan via de iPhone-camera.

## 11. Open vragen

V1–V5 beantwoord op 13-11-2026, zie B6–B11 in §1.

## Bronnen

- Dyson, M. C. (2004). How physical text layout affects reading from screen. *Behaviour & Information Technology*, 23(6), 377–393.
- Hearst, M. A. (2006). Design recommendations for hierarchical faceted search interfaces. *SIGIR Workshop on Faceted Search*.
- Lando, A. M., Bazaco, M. C., & Chen, Y. (2018). Consumers' use of personal electronic devices in the kitchen. *Journal of Food Protection*, 81(3), 437–443. https://pubmed.ncbi.nlm.nih.gov/29474153/
- Legge, G. E., & Bigelow, C. A. (2011). Does print size matter for reading? A review of findings from vision science and typography. *Journal of Vision*, 11(5):8.
- Mayer, R. E. (2009). *Multimedia Learning* (2nd ed.). Cambridge University Press.
- Mayer, R. E., & Pilegard, C. (2014). Principles for managing essential processing: segmenting, pretraining, and modality principles. In *The Cambridge Handbook of Multimedia Learning*.
- Parasuraman, R., & Manzey, D. H. (2010). Complacency and bias in human use of automation. *Human Factors*, 52(3), 381–410.
- safefood (2024). *Consumers' use of smart devices while preparing food in the domestic kitchen on the island of Ireland.* https://www.safefood.net/professional/research/smart-devices-kitchen
- Vtyurina, A., & Fourney, A. (2018). Exploring the role of conversational cues in guided task support with virtual assistants. *CHI 2018*. https://doi.org/10.1145/3173574.3173782
- Praktijk: Mela Help (https://mela.recipes/help/); MacStories, review Mela (2021); Apple Developer Forums over SwiftData en CloudKit-delen (threads 756721, 794600, 817369).
- Apple-documentatie: Vision, VisionKit, Foundation Models, Speech (SpeechAnalyzer), AVFoundation, App Intents, AlarmKit, ActivityKit, Core Data + CloudKit.
