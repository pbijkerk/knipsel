# Audit Knipsel-xcode

| Versie | Datum | Auteur | Wijziging | Status |
|---|---|---|---|---|
| 0.1 | 19-11-2026 | Mistral Vibe | Eerste opzet: rapport van de code-audit | Concept |

**Scope van de audit:** 159 Swift-bestanden (±35.000 regels), 4 targets (app, deel-extensie
KnipselDelen, widget-extensie KnipselWidgets, tests), XcodeGen-project (project.yml), CI
(.github/workflows/ci.yml) en documentatie. Doorgenomen: opslag en CloudKit-delen, de App Group
met de deel-extensie, spraak en de Claude-indeler, CI en bouwinstellingen, tests en privacy. Aan-
aansluitend een gerichte statische analyse over de hele codebase (force unwraps, foutafhandeling,
concurrency, observers).

**Eindoordeel: dit is een ongewoon schoon project voor deze omvang.** Geen kritieke bevindingen;
acht verbeterpunten, waarvan één substantieel.

## Wat goed zit

- **Gelaagde opbouw** (Weergave → Diensten → Opslag) met dependencies achter protocols
  (`Indeler`, `DeelDienst`, `PaginaOphaler`) — netwerk en CloudKit zijn in tests perfect
  isoleerbaar (`Knipsel/Diensten/Inlezen/ReceptInlezer.swift`, protocol op regel 13).
- **Statische analyse is vrijwel leeg:** nul `as!`, nul gewone force-unwraps; alle `try!` zijn
  statische regex-literalen (onkritisch), één terechte `fatalError` voor een ontbrekend datamodel
  (`Knipsel/Opslag/Opslag.swift:32`).
- **Beveiliging klopt met de beloftes:** de Anthropic-sleutel zit in de Keychain met
  `ThisDeviceOnly` (`Knipsel/Diensten/KeychainService.swift`); spraakherkenning is écht on-device
  (`SpeechAnalyzer` met als terugval `SFSpeechRecognizer` met
  `requiresOnDeviceRecognition`, `Knipsel/Spraak/LuisterService.swift`);
  `docs/privacy.md` beschrijft bijzonder nauwkeurig wat de code werkelijk doet, inclusief de
  Claude-uitzondering en de App Group.
- **Robuuste iCloud-delen:** retry per soort, voorwaarts delen pas na een geslaagde export,
  vangnet na CloudKit-fout 1570 met maximum pogingen en de knop *Probeer opnieuw*
  (`Knipsel/Thuis/ThuisDelen.swift`).
- **Tests:** 36 bestanden, ±9.000 regels, deterministisch (geen sleeps of expectation-wachtingen),
  in-memory stores. **CI** controleert swift-format én dat het getrackte `.xcodeproj` actueel is
  na `xcodegen generate`.
- **Toestemmings-teksten** in `Knipsel/Info.plist` zijn concreet en eerlijk (camera, microfoon,
  spraak, AlarmKit, Herinneringen).

## Bevindingen

| # | Ernst | Vindplaats | Wat | Advies |
|---|---|---|---|---|
| 1 | Midden | `Knipsel/Opslag/Opslag.swift:42,109` | `laadfout` wordt gezet als `loadPersistentStores` faalt, maar wordt nergens gelezen. Slaat het openen van een store niet, dan ziet de gebruiker een lege app zonder dat er iets aan de hand lijkt — het ernstigste probleem in de app is onzichtbaar. | Toon `laadfout` in het startscherm of Instellingen; hersteltraject overwegen. Met automatische migratie is dit zeldzaam, maar juist dan mag het niet stil blijven. |
| 2 | Midden | `Knipsel/Knipsel.entitlements` | `aps-environment: development` met de hand gezet; voor productie-push van CloudKit (TestFlight/App Store) is dat niet voldoende. | Bouwinstelling per omgeving, óf `automatic` en door Xcode laten beheren; verifiëren in de volgende TestFlight-deploy. |
| 3 | Midden | `Knipsel/Kookmodus/KookmodusScherm.swift:115` | 1297 regels in één bestand: `Kookmaten`, `Microfoonstatus` en het scherm zelf (2 bodies). | Opsplitsen: `Kookmaten.swift`, `Microfoonstatus.swift`, subcomponenten van het scherm. Verlaagt onderhoudsdruk rond de kookmodus. |
| 4 | Laag | werkmap, ongetrackt | `Knipsel.xcodeproj/xcshareddata/xcodecloud/manifest.json` is niet getrackt en niet genegeerd. De CI vergelijkt `git diff` op de hele projectmap; een half-gehuisveste map zoals deze maakt de staat van het project onduidelijk. | Committen (als Xcode Cloud lokaal wordt gebruikt) of negeren in `.gitignore`. |
| 5 | Laag | `Knipsel/Delen/DeelLezer.swift:184-221` | Meerdere `try?`-ketens: lukt het opslaan van een gedeelde afbeelding of PDF onhoorbaar, dan toont de extensie "niets" zonder oorzaak. | Logging bij falen en een duidelijkere melding dan alleen "niets gedeeld". |
| 6 | Laag | `Knipsel/Thuis/ThuisDelenScherm.swift:188`, `Knipsel/Bibliotheek/ReceptLijst.swift:163` | Twee plekken tonen `error.localizedDescription` rechtstreeks; overal elders vertaalt de app fouten via eigen zinnen (`DeelFout.melding`). | Voor consistentie ook hier centraal vertalen. |
| 7 | Laag | `.github/workflows/ci.yml` | Geen lintstap; de extensies worden alleen indirect via het scheme gebouwd. | Subtargets voor de extensies expliciet in de build-check opnemen; overweeg `swift format -s --lint`. |
| 8 | Laag | `Knipsel/Thuis/ThuisDelen.swift:24` | `ThuisDelen.gedeeld` wordt aangemaakt in de default-expressie van de singleton, met voorwaarden op andere singletons: lastig te testen en ondoorzichtig. | Fabrieksfunctie (`static func maak()`) in plaats van de default-expressie. |

**Los van de tabel:** de NotificationCenter-observaties gebruiken consequent
`weak self`, de Task-lifecycle (`deelTaak`, `exportTaak`, `taak`, `ontdubbelTaak`) wordt overal
voor een nieuwe start geannuleerd, en de `MainActor.assumeIsolated`-toepassingen zijn consistent —
geen concurrency-bezwaren.

## Aanbeveling in volgorde

1. **#1** — zichtbare melding van `laadfout` (belangrijkste gebruikersrisico).
2. **#2** — vóór de volgende TestFlight-deploy de `aps-environment` regelen.
3. **#3, #4 en #6** — ±15-30 minuten werk, directe codekwaliteitswinst.
4. **#5, #7 en #8** — later, in een rustige iteratie.
