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
- **Timers (fase 7, #8).** `TijdHerkenner` haalt de tijden uit de staptekst ("20 minuten", "20 min.",
  "1½ uur", "anderhalf uur", "1 uur en 15 minuten", "een kwartier", "drie kwartier", "een minuut of
  vijf", "45 seconden"); een bereik ("10-15 min", "10 à 15 minuten") geeft de bovengrens als timer en
  het bereik in beeld. Temperaturen, "2 el", jaartallen en kloktijden ("om 18.00 uur") tellen niet.
  Bij bewaren (knippen, inlezen, bewerken) krijgt `Stap.timerSeconden` de langste tijd; oude recepten
  zonder die waarde krijgen hem in de kookmodus uit de tekst. In de kookmodus staat bij elke tijd een
  tomaatrode knop "⏱ Timer 20 min"; lopende timers staan als chips boven de knoppen onderin (tik =
  pauzeren, verder, stoppen). `TimerService` zet ze als AlarmKit-countdown (alarm ook op slot en op
  stil, "Nog 1 min" bij het alarm, meerdere tegelijk, elk met recept + stap als naam, bv. "Pompoensoep
  · Stap 3: laat 20 minuten zachtjes koken"). Zonder toestemming voor alarmen lopen ze alleen in de app
  en zegt Knipsel het als ze klaar zijn. Na het voorlezen van een stap met een tijd vraagt Knipsel
  "Zal ik een timer van 20 minuten zetten?" (niet als er voor die stap al een loopt).
- **Live Activities (fase 7).** De widget-extensie `KnipselWidgets` levert twee: de kookmodus
  (`KookActivityAttributes`: "Stap 3 van 7 · titel", de stap kort, de eerstvolgende timer die zelf
  aftelt, knoppen vorige/herhaal/volgende als `LiveActivityIntent` die in de app draaien) zolang de
  kookmodus open is — weg bij sluiten en bij *Gekookt* — en per timer de AlarmKit-weergave
  (`AlarmAttributes<KookTimerMetadata>`: aftellen, pauze/verder, stop). Lopende timers blijven lopen
  als de kookmodus dicht gaat.
- Ingrediënten die in de huidige stap voorkomen worden in de lijst uitgelicht; afvinken kan met "gedaan".

## 4. Bediening zonder handen — lagen

| Laag | Wanneer | Techniek | Status |
|---|---|---|---|
| 1. Stem in de app (primair) | Tijdens koken, app open | `SpeechAnalyzer` + `DictationTranscriber` (`nl_NL` on-device, gecontroleerd); terugval `SFSpeechRecognizer` on-device. `AVAudioEngine` met *voice processing* (echo-onderdrukking), zodat Knipsel zijn eigen stem niet hoort en "stop" midden in het voorlezen werkt. | Kern, fase 5 |
| 2. Siri / App Shortcuts | Starten, of app op achtergrond / vergrendeld | App Intents: `KookReceptIntent` (met `ReceptEntiteit`, zoekbaar op titel en ingrediënt), `VolgendeStapIntent`, `VorigeStapIntent`, `HerhaalStapIntent`, `LeesIngredientenIntent`; Nederlandse zinnen in `KnipselOpdrachten` ("Kook pompoensoep met Knipsel", "Volgende stap in Knipsel", …). Recepten staan in Spotlight (`IndexedEntity`). Fase 7: `ZetTimerIntent` ("Zet een timer in Knipsel"; zonder minuten de tijd van de huidige stap, anders vraagt Siri "Hoeveel minuten?") en `HoeLangNogIntent` ("Hoe lang nog in Knipsel"). | Gebouwd in fase 6 (#7) en 7 (#8); Nederlandse zinnen op toestel nog te testen |
| 3. Actieknop | Eén knop met knokkel = volgende stap | Snelkoppeling "Volgende stap" aan de Actieknop | Alleen iPhone 15 Pro en nieuwer; niet op Peters toestellen, geparkeerd |
| 4. AirPods / Apple Watch | Steeltje 1× = voorlezen/stoppen, 2× = volgende, 3× = vorige | `MPRemoteCommandCenter` + Nu speelt, achter de instelling *Bediening met AirPods en Apple Watch (proef)* (standaard uit) | Proef S3 gebouwd, op toestel te testen (`docs/spikes/S3-airpods.md`) |

**Hoe het samenhangt (fase 6).** Eén `KookRouter` opent de kookmodus: "Kook dit", *Verder met…* en
Siri zetten daar een verzoek neer, en de bibliotheek toont de kookmodus als volledig scherm. De open
kookmodus meldt zich bij `ActieveKookSessie`; Siri en AirPods vinden de sessie daar (ook met de app
op de achtergrond, in hetzelfde proces) en gebruiken hetzelfde pad als spraak (`Spraakbediening` →
`KookSessie`-gebeurtenis → voorlezer). De voorlezer reageert in de sessie zelf, niet via een
schermupdate, zodat voorlezen ook op de achtergrond volgt. Achtergrondmodus `audio` houdt het
voorlezen en luisteren gaande als de app naar de achtergrond gaat of het scherm op slot gaat, alleen
zolang de kookmodus open is.
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
| "timer ‹n› minuten", "zet de timer", "hoe lang nog?", "stop de timer" | timer zetten (‹n› of de tijd van de stap) / resterende tijd voorlezen / eerstvolgende timer stoppen (fase 7) |
| "ja", "oké", "klaar", "doe maar" / "nee" — alleen direct na de timervraag² | timer van de stap zetten / geen timer |
| "stoppen met koken" | kookmodus sluiten |

¹ Impliciete signalen ("oké", "klaar", "gedaan") staan standaard aan (B11), met melding en "terug" om te herstellen; uit te zetten in Instellingen.

² **Toestand "timervraag" (fase 7).** Na "Zal ik een timer van 20 minuten zetten?" telt "ja", "oké",
"klaar" of "doe maar" (ook met de impliciete signalen uit) als *ja* zolang de vraag klinkt en tot 8
seconden daarna (`Timervraag.venster`); een uiting die in dat venster begint maar waarvan het
eindresultaat later binnenkomt (± 2 s), telt ook. "Nee", "nee hoor", "hoeft niet", "geen timer" sluiten
de vraag. Daarbuiten betekent "oké"/"klaar" weer *volgende*, en is "nee" geen commando. Een nieuwe stap,
"stop" of tikken op Ja/Nee in de banner sluit de vraag ook. "Stop de timer" stopt eerst het voorlezen
(voorlopig "stop") en daarna de timer als de zin doorloopt.

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
- **Thuis delen (fase 8, #9)** volgt Apple's voorbeeld *Sharing Core Data objects between iCloud users*:
  - Eén `NSPersistentCloudKitContainer` met twee stores: `Knipsel.sqlite` (bestaand, `databaseScope =
    .private`) en `Knipsel-gedeeld.sqlite` (nieuw, `.shared`). Beide met persistent history en remote
    change notifications. Een bestaande database opent ongewijzigd: alles staat in "Mijn recepten".
  - Eén zone-brede `CKShare` "Knipsel · Thuis" (`CKShare.SystemFieldKey.title`, geen openbare link,
    deelnemers lezen en schrijven). Als **eigenaar** staan de Thuis-recepten in je *privéstore*, in de
    record zone van de share (`container.share(_:to:)` verhuist ze daarheen); als **deelnemer** staan ze
    in de *gedeelde store* (`acceptShareInvitations(from:into:)`). Een recept, categorie of label weet zijn
    kookboek via het veld `kookboek` ("mijn"/"thuis").
  - Core Data kent geen relaties tussen stores, en `share(_:to:)` neemt de hele objectgraaf mee (een
    recept → zijn categorie → álle recepten in die categorie). Daarom heeft Thuis **eigen categorieën en
    labels** met dezelfde namen. Naar Thuis verplaatsen = een volledige kopie (ingrediënten, stappen, foto,
    kooklog, beoordeling, dezelfde `uuid`) aan de gelijknamige Thuis-categorieën (zo nodig aangemaakt),
    het origineel weg, in één bewaarbeurt (`Kookboeken`). Terug idem. Vóór elke bewaarbeurt zet
    `Kookboeken.herstel` nieuwe objecten in de juiste store en een keuze uit het andere kookboek om naar
    de gelijknamige. De standaardset zaait alleen in Mijn recepten; ontdubbelen gaat per store en kookboek.
  - De bibliotheek leest beide stores; categorieën en labels met dezelfde naam zijn één chip/regel
    (filter op naam). Zijbalk en Filter: Alles / Mijn recepten / Thuis (alleen als er Thuis-recepten zijn).
  - "Verder met…", Siri en Spotlight verwijzen naar de `uuid` (`Recept.verwijzing`), niet naar het
    objectID; oude standen worden bij het starten omgezet.
  - **Stoppen.** `purgeObjectsAndRecordsInZone(with:in:)` haalt de zone uit CloudKit **en** de objecten
    uit de store (Apple: "apps that need to keep the object graph can make a deep copy … and save it").
    Daarom verplaatst de eigenaar bij *Stop met delen* eerst alles uit Thuis naar Mijn recepten, en kan
    een deelnemer bij *Verlaat Thuis* eerst een kopie maken (standaard aan). Bij de huisgenoot
    verdwijnen de Thuis-recepten; open scherm, *Verder met…*, Siri en Spotlight vangen dat op.
  - Accepteren: `CKSharingSupported` in Info.plist; een `UIWindowSceneDelegate` (via
    `UIApplicationDelegateAdaptor`) ontvangt `windowScene(_:userDidAcceptCloudKitShareWith:)`.
  - CloudKit-kant achter het protocol `DeelDienst` (nep in tests); modelversie 3 voegt `kookboek` toe
    aan `Categorie` en `Label` (optioneel met standaard "mijn"). **CloudKit-schema opnieuw naar
    Production uitrollen** (CloudKit Console › Deploy Schema Changes); het schema geldt voor de privé- en
    gedeelde database samen.
  - CloudKit-eisen: alle attributen optioneel of met standaardwaarde, geen unieke constraints,
    relaties met inverse.
  - **CloudKit-schema naar Development en Production.** *Deploy Schema Changes* zet alleen over wat al in
    de Development-omgeving staat, en daar komt een recordtype of veld pas als een Debug-build er een
    record mee uploadt. Na modelversie 4 en 5 gebeurde dat niet, dus zag de Console "geen wijzigingen" en
    misten `CD_BoodschappenItem` en `CD_Maaltijd` in Production. Daarom roept een **Debug**-build bij het
    starten één keer per modelversie `initializeCloudKitSchema(options: [])` aan (`CloudKitSchema`,
    UserDefaults `cloudkitSchemaGeinitialiseerd-<versie>`; ook als knop in Instellingen › Over Knipsel,
    alleen in Debug). Dat maakt voorbeeldrecords met élk veld dat Core Data kan schrijven, uploadt en wist
    ze, voor alle stores met CloudKit (privé en gedeeld; het schema is per container). Het draait ná
    `loadPersistentStores`, op de achtergrond (het blokkeert), nooit onder tests/previews en nooit in
    Release: het werkt alleen tegen Development. Stappen na elke modelversie:
    1. Draai de app vanuit Xcode (Debug, ⌘R) op een toestel met iCloud.
    2. Wacht op "CloudKit-schema klaar" (Instellingen › Over Knipsel, of het log `CloudKitSchema`).
    3. Verplaats in dezelfde Debug-run een recept naar Thuis (zet een boodschap en een maaltijd in
       Thuis), zodat ook de velden die alleen bij delen ontstaan (zoals `CD_moveReceipt`) in Development
       komen.
    4. CloudKit Console › container › Schema › *Deploy Schema Changes* — nu met wijzigingen.
    5. Daarna pas een TestFlight-build testen (die praat met Production).
  - **Thuis bijwerken.** `ThuisDelen` deelt recepten, boodschappen en het weekmenu in **aparte**
    aanroepen: faalt één soort, dan gaan de andere door, en de melding zegt welke soort het was. Een
    soort die faalde, probeert Knipsel die app-start niet vanzelf opnieuw (wel via *Probeer opnieuw*).
    `DeelFout` zet Core Data-validatiefouten (die als "%{PROPERTY}@ is een vereiste waarde." binnenkomen)
    om in "bij een boodschap ontbreekt 'veld'" en CloudKit-fouten in gewone taal ("iCloud-schema ontbreekt
    — Deploy Schema Changes nodig"); het log (`Thuis`) toont domein, code, `userInfo`-sleutels en
    entiteit.veld, zonder inhoud.
- **Model (eerste versie):**
  - `Recept`: titel, intro, porties, bereidingstijd, totale tijd, notities, bronNaam, bronDatum, bronPagina,
    beoordeling, laatstGekooktOp, aangemaaktOp, kookboek (Mijn recepten / Thuis); veel-op-veel met `Categorie`.
    Modelversie 3 (#9): `kookboek` ook op `Categorie` en `Label`.
    Modelversie 2 (#23, 3b): `fotoData` (eigen gerechtfoto, JPEG 4:3 ≤ 1600 px, *Allows External Storage*,
    in CloudKit een asset) en `fotoGewijzigdOp` (`nil` = geen foto). Nooit de krantenfoto (B7).
  - `Ingredient`: volgorde, groep, ruweTekst, hoeveelheid, hoeveelheidTot, eenheid, naam, toelichting
  - `Stap`: volgorde, groep, tekst, timerSeconden
  - `Categorie`: naam, symbool, volgorde, verborgen, isStandaard
  - `Label`: naam
  - `Kooklog`: datum, notitie
  - Modelversie 4 (#39): `BoodschappenItem` (uuid, naam, sleutel, hoeveelheid, eenheid, tekst, afdeling,
    afgevinkt, afgevinktOp, aangemaaktOp, volgorde, herkomst, kookboek). Alle velden optioneel of met
    standaard, geen relaties (dus `share(_:to:)` sleept niets mee) en geen unieke constraints. Eén lijst per
    kookboek: Mijn recepten in de privéstore, Thuis in de zone van de Thuis-share (bij de eigenaar in de
    privéstore, bij de huisgenoot in de gedeelde store); `Kookboeken.herstel` zet een nieuw item in de juiste
    store, `ThuisDelen` zet Thuis-items in de share en verplaatst ze bij stoppen/vertrekken naar Mijn lijst.
    **CloudKit-schema opnieuw uitrollen** (Deploy Schema Changes).
  - Modelversie 5 (#41): `Maaltijd` (uuid, datum = begin van de dag in de lokale tijd, receptUUID als tekst,
    titel als terugval, porties, notitie, restjesVanUUID, kookboek, aangemaaktOp). Alle velden optioneel of
    met standaard, geen relaties en geen unieke constraints — zoals `BoodschappenItem`: een verwijderd recept
    laat de maaltijd staan (titel doorgehaald, "kies opnieuw"), en delen sleept niets mee. Eén avondeten per
    dag per kookboek bewaakt de code (bij dubbelen via iCloud telt de nieuwste). Zelfde zone-regels als de
    lijst: `Kookboeken.herstel` stap 6, `ThuisDelen` deelt de Thuis-week en zet hem bij stoppen/vertrekken in
    Mijn week (dagen die daar al bezet zijn houden wat er stond). **Deploy Schema Changes** opnieuw nodig.
- **Eigen boodschappenlijst (#39):** `Boodschappenlijsten` (lezen, optellen, afvinken, wissen, verplaatsen),
  `LijstOptellen` (puur: zelfde `sleutel` + optelbare maat, hergebruikt `BoodschappenLijst` met hele stuks
  in de winkel; afgevinkte items tellen niet mee; herkomst = recepttitels), `Afdelingen` (woordenlijst van
  ruim 550 ingrediënten → 13 afdelingen in de volgorde van een Nederlandse supermarkt, onbekend → Overig) en
  `AfdelingGeheugen` (eigen keuze per sleutel gaat voor woordenlijst, dan Claude; op dit toestel). Alleen met
  een eigen Claude-sleutel stuurt `OnbekendeAfdelingen` de **naam** van onbekende ingrediënten naar Claude,
  elke naam hooguit één keer (cache). Het boodschappenvel van #38 kiest via `VelBestemming` standaard de
  Knipsel-lijst van het kookboek van het recept (instelling: Knipsel-lijst of Herinneringen).
- **Weekmenu (#41):** `Weekplanning` (puur): week voor een datum met instelbare begindag (`Weekbegin`,
  standaard maandag; gregoriaans, `nl_NL`, rekenen in hele dagen zodat zomertijd en jaargrens kloppen),
  verplaatsen (bezette dag = ruilen), kook dubbel (volgende dag "Restjes van …"; bezet = eerst vragen:
  vervangen of een andere dag), wissen (met de restjes), "vandaag" en de boodschappen-paren vanaf een dag
  t/m het eind van de week: per recept de porties plus die van zijn restjes; notities en restjes-dagen
  zelf leveren niets op. `Weekmenu` zet `Maaltijd` om naar waarden, laat `Weekplanning` rekenen en schrijft
  terug. `WeekScherm` (📅 naast 🛒 op iPhone, zijbalkrij op iPad) toont de week met *Mijn week | Thuis*
  (`BoodschappenSchakelaar`), `ReceptKiezer`, `DagActies`, slepen tussen dagen en onderin het vel van #40
  (`VelRecept.start` = geplande porties). `PlanInVel` vanuit ⋯ › *Plan in…* in het recept; `VandaagRij`
  bovenaan de bibliotheek; `VandaagIntent` voor Siri. Gepland telt niet als gekookt.
- **Diensten:** `ScanService` (VisionKit/Vision), `Indeler`-protocol met `RegelIndeler`, `ClaudeIndeler` en `ModelIndeler`, `KeychainService`,
  `IngredientParser` (puur, goed testbaar), `VoorleesService` (AVSpeechSynthesizer + uitspraakregels),
  `LuisterService` (AVAudioEngine + SpeechAnalyzer), `CommandoHerkenner` (puur, testbaar),
  `KookSessie` (toestandsmachine stap/voorlezen/luisteren/timers), `TimerService` (AlarmKit),
  `KookActivity` (ActivityKit), App Intents.
- **Inlezen (#18, deel 1 in de app):** `SchemaReceptLezer` (schema.org `Recipe` uit JSON-LD of microdata),
  `PaginaLezer` + `TekstRegels` (leesbare tekst → herkende regels → bestaande `Indeler`), `Betaalmuur`
  (heuristiek), `ReceptInlezer`, `WebOphaler` (`URLSession` rechtstreeks vanaf het toestel) en
  `InleesInbox` ("Nog te controleren": JSON + bestanden in een map die later de App Group van de
  deel-extensie wordt). Een recept van een website bewaart de link in `bronPagina` (geen modelwijziging)
  en, als dat aan staat, één foto van de site in `fotoData`; papierknipsels blijven tekst-only (B7).
- **Rechten (Info.plist):** camera, microfoon, spraakherkenning, foto's (alleen kiezen), AlarmKit
  (`NSAlarmKitUsageDescription`), Live Activities (`NSSupportsLiveActivities`). Netwerk alleen voor
  Claude (optioneel) en iCloud.
- **Targets:** de app, `KnipselDelen` (deelmenu, App Group) en `KnipselWidgets` (fase 7, alleen Live
  Activities, zonder entitlements). Wat de widget nodig heeft (`KookActivityAttributes`,
  `KookTimerMetadata`, de knoppen als `LiveActivityIntent` en de weergaven) staat in `Knipsel/Gedeeld`
  en compileert in beide.

## 8. Risico's en proeven

| # | Risico | Proef | Status |
|---|---|---|---|
| S1 | OCR op echte krantenfoto's: kolommen, glanzend papier, krom blad, `l`/`1` | 10 echte pagina's (blijven lokaal) | Synthetisch gedaan: `1 l groentebouillon` → `1 groentebouillon`, `ë` verdween. Echte foto's nog doen |
| S2 | Indeling op wisselende layouts: regels vs. Claude | Zelfde 10 pagina's | Synthetisch met on-device model: 100 % juist. Regels en Claude nog te meten |
| S3 | AirPods/Watch-bediening vraagt "Nu speelt"; telt spraaksynthese daarvoor mee? | In de app achter een proefinstelling (fase 6), testplan in `docs/spikes/S3-airpods.md` | Gebouwd, op toestel te testen |
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
| 6 | Siri, App Shortcuts, Spotlight, AirPods/Watch (proef); Actieknop geparkeerd | Bouwt op de `KookSessie` van 3–5. Gebouwd (#7); `ZetTimer` in fase 7 |
| 7 | Timers (AlarmKit) en Live Activity | Gebouwd (#8): tijdherkenning, timers, timervraag, Live Activities (widget-extensie `KnipselWidgets`), Siri-timers. Alarm op slot/stil en Dynamic Island nog op toestel te testen |
| 8 | Delen met huisgenoot | Raakt het datamodel; na stabiel gebruik. Gebouwd (#9): kookboek Thuis, modelversie 3 |
| — | Boodschappen 1, 2 en 3 | Gebouwd: vel naar Herinneringen (#38); eigen lijst per afdeling met optellen, Thuis-lijst, modelversie 4 (#39); lijst voor meerdere recepten tegelijk (#40). Weekmenu apart |
| — | Weekmenu (A + B) | Gebouwd (#41): weekoverzicht met kook dubbel/restjes, boodschappen voor de rest van de week, Mijn week / Thuis, Vandaag en Siri; *Plan in* vanuit het recept; modelversie 5. Weekvoorstel (C) later |

## 10. Eigen suggesties (nog niet ingepland)

1. **"Vraag de chef"** — vrije vraag tijdens het koken ("kan ik ook crème fraîche gebruiken?"), beantwoord
   door Claude (of later het on-device model), alleen met het recept als context en met een zichtbaar "suggestie"-label.
2. **Boodschappenlijst** — stap 1 gebouwd (#38): 🛒 in de receptbalk opent een vel met de ingrediënten
   geschaald en aangevinkt, "Meestal in huis" uitgevinkt (aan te passen, Knipsel leert wat je vaak uitvinkt),
   naar de lijst "Boodschappen" in Herinneringen of delen als tekst. Herinneringen deelt een lijst van het type
   Boodschappen zelf in per afdeling; EventKit kan dat lijsttype niet zetten, dus dat doet de gebruiker in
   Herinneringen (Toon lijstinfo › Lijsttype). Stap 2 gebouwd (#39, schets 2A): een eigen lijst in Knipsel
   over meerdere recepten, opgeteld en per afdeling in winkelvolgorde, met een gedeelde Thuis-lijst; Herinneringen
   blijft als bestemming (keuze in Instellingen). Stap 3 gebouwd (#40, schets 3A): *Selecteer* in de
   bibliotheek (iPhone en iPad, kaarten en lijst, ook via het contextmenu van een kaart); tik = aan/uit met een
   tomaatkleurig vinkje, onderaan *🛒 Boodschappen voor n recepten* en *Annuleer*. Dat opent hetzelfde vel
   (`BoodschappenVel`, geen kopie) met bovenaan per recept de porties (start op de standaardporties), alles
   opgeteld via `BoodschappenLijst.regels(recepten:)` — eerst per recept geschaald, dan opgeteld op naam en
   optelbare maat, hele stuks pas op het totaal naar boven (½ + ½ citroen = 1) — en onder elke regel uit welke
   recepten hij komt. Bij gemengde kookboeken gaat het op de lijst van het kookboek met de meeste gekozen
   recepten (gelijkspel: Mijn lijst), met bovenaan *Zet op: Mijn lijst | Thuis* als Thuis bestaat. Op de eigen
   lijst krijgt elk item alleen de recepten waar het uit komt als herkomst; in Herinneringen staan alle titels
   in de notitie. Na een geslaagde lijst gaat de selectiemodus uit zodra het vel dicht is. Geen modelwijziging.
   Het weekmenu is gebouwd in #41 (schetsen `docs/ux/schetsen-weekmenu.html`, eisen M1–M7): A
   (weekoverzicht) met B (*Plan in* vanuit het recept). Nog niet: C, een weekvoorstel op basis van wat je
   lang niet kookte en het seizoen — als knop in het weekoverzicht zodra er genoeg kookgeschiedenis is.
3. **"Wat kan ik maken met …"** — gebouwd in #44 (schetsen `docs/ux/schetsen-wat-kan-ik-maken.html`, eisen
   W1–W6): A, de in huis-zoeker, met C, de Siri-zin voor één ingrediënt. Bovenaan de bibliotheek (iPhone en
   iPad) staat de rij *Wat kan ik maken?*; daar typ of dicteer je wat je hebt als chips (komma of enter,
   suggesties uit de ingrediënten van je recepten, ✕ per chip; ze blijven bewaard tot je *Wis* tikt). Wat je
   meestal in huis hebt (#38) telt mee. De recepten van het gekozen kookboek staan in groepen *Alles in huis*,
   *Nog 1 nodig*, *Nog 2 nodig* en *Nog 3 of meer nodig* (achter *Toon meer*), binnen een groep eerst wie
   de meeste van jouw ingrediënten gebruikt en dan de kortste tijd; recepten zonder een van jouw
   ingrediënten staan er niet. Per recept "mist: bladerdeeg" of "alles in huis", een kleine meter en de
   varianten ("rode ui ≈ ui"); 🛒 (ook vegen of lang drukken) zet wat ontbreekt op de lijst uit Instellingen ›
   Boodschappen. Het vergelijken (`IngredientMatcher`) is een woordenlijst zonder netwerk: enkelvoud/meervoud,
   bijvoeglijke woorden weg ("verse", "geraspte", "oude" bij kaas), samenstellingen op hun kopwoord
   ("preiringen" → prei), een paar synoniemen (slagroom = room). De regel voor varianten: wat je hebt dekt
   het recept als het hetzelfde of specifieker is (rode ui in huis → recept met ui); iets algemeners of
   verwants (ui in huis → recept met rode ui; sjalot ≈ ui; kaas ≈ parmezaan) telt als *bijna*: wel in huis,
   maar zichtbaar (W5). "Naar smaak", "optioneel", "voor erbij" en kopjes tellen niet als ontbrekend. Siri:
   "Wat kan ik maken met prei in Knipsel" noemt het aantal en het snelste recept en opent het scherm met die
   chip; met één chip kies je *Snelst* of *Lang niet gekookt*. Claude als aanvulling op de woordenlijst is
   een mogelijk vervolg; B (voorraadkast) blijft geparkeerd.
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
