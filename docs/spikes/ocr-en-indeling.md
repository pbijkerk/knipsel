# Proef: herkennen en indelen van een krantenrecept (13-11-2026)

Doel: nagaan of herkennen en indelen van een Nederlands krantenrecept volledig on-device kan, met alleen
Apple-frameworks. Gedraaid op de MacBook (macOS 27, Xcode 27.2); dezelfde frameworks bestaan op iOS 26.

**Let op:** de testpagina is verzonnen en gegenereerd ([`testpagina.html`](testpagina.html) →
[`testpagina.png`](testpagina.png)): een recept in twee kolommen, met ernaast een supermarktadvertentie en
eronder een lezersbrief. Echte foto's (glanzend papier, krom blad) zijn nog niet getest — zie S1 in het ontwerp.

## 0. Beschikbaarheid ([`0-beschikbaarheid.swift`](0-beschikbaarheid.swift))

| Onderdeel | Uitkomst |
|---|---|
| Vision tekstherkenning `nl-NL` (accurate) | Ondersteund |
| Foundation Models (on-device taalmodel) | Beschikbaar, Nederlands ondersteund |
| `SpeechTranscriber` (nieuw, lange spraak) | **Geen Nederlands** |
| `DictationTranscriber` (SpeechAnalyzer) | `nl_NL` en `nl_BE` ondersteund → gebruiken voor spraakbesturing |
| `SFSpeechRecognizer` `nl-NL` on-device | Ondersteund (terugval) |
| Nederlandse stemmen | Xander (nl-NL), Ellen (nl-BE), plus één extra |

## 1. AI schrijft het hele recept ([`1-ai-schrijft-recept.swift`](1-ai-schrijft-recept.swift))

Vision-tekst → Foundation Models met `@Generable struct Recept` (titel, porties, ingrediënten met
hoeveelheid/eenheid, stappen met timer, categorie, weggelaten blokken).

- Goed: titel, 4 porties, categorie *Soep*, advertentie en lezersbrief weggelaten, timers 5 en 20 min.
- **Fout:** alle hoeveelheden weg (`1 flespompoen (ca. 1 kg)` → `pompoen`), tekst herschreven
  (`2 uien, gesnipperd` → `ui`), een typfout erbij (`olifolie`).

## 2. AI deelt alleen in, code voegt samen ([`2-ai-deelt-in.swift`](2-ai-deelt-in.swift))

Foundation Models geeft alleen bloknummers per rol + categorie. Code plakt stapregels aan elkaar tot een
nieuw nummer begint.

- Indeling 100 % juist: titel = blok 0, ingrediënten = 3–10, bereiding = 11–21, intro = 1–2,
  advertentie en lezersbrief (22–31) weggelaten, categorie *Soep*.
- Stappen letterlijk en compleet, bv. *"3. Voeg de pompoen en kerriepoeder toe en bak 2 minuten mee.
  Schenk de bouillon erbij en laat 20 minuten zachtjes koken."*
- Tijd: OCR 0,5 s, indeling 6,3 s (eerste OCR-run 68 s door het laden van het model).

## Fouten van de tekstherkenning zelf

- `1 l groentebouillon` → `1 groentebouillon`: de losse `l` (liter) verdwijnt, klassiek `l`/`1`-probleem.
- `Ingrediënten` → `Ingredienten`: trema weg.
- `·` → `•`.

## Conclusies voor het ontwerp

1. **AI deelt in, AI schrijft niet** (K2). De tekst blijft letterlijk; hoeveelheden komen uit een eigen
   Nederlandse parser die getest kan worden.
2. **Controlescherm is nodig**: herkenning mist eenheden. Markeer regels met lage betrouwbaarheid, en
   regels die op een ingrediënt lijken maar geen eenheid hebben terwijl dat wel verwacht wordt
   (`1 groentebouillon`).
3. Spraak: `DictationTranscriber`, niet `SpeechTranscriber`.
4. Nog te doen: dezelfde proef op 10 echte foto's (lokaal, niet in deze publieke repo) en op een iPhone.

**Aanvulling 13-11:** Peters toestellen (iPhone 14 Plus, 15 Plus, iPad 10) hebben geen Apple Intelligence. Het indelen gebeurt daar met regels, optioneel met Claude (ontwerp B10). Dezelfde testpagina wordt de eerste test voor de regelindeler.

Opnieuw draaien: `swift docs/spikes/2-ai-deelt-in.swift` vanuit `docs/spikes/` (Mac met Apple Intelligence aan).
