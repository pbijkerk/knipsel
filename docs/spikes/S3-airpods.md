# Proef S3 — AirPods en Apple Watch als bediening van de kookmodus

*Fase 6 (#7). Status: gebouwd achter een instelling, **nog niet op een toestel getest**. Dit document
claimt niet dat het werkt; het legt vast wat er is, waarop het rust en hoe we het testen.*

## Vraag

Kan de kookmodus met het steeltje van AirPods (en met Nu speelt op de Apple Watch en het
vergrendelscherm) naar de volgende of vorige stap, zonder het scherm aan te raken? Die knoppen gaan
naar de app die iOS als "Nu speelt"-app ziet. Telt een app die alleen spraaksynthese laat horen
daarvoor mee?

## Wat er gebouwd is

- Instelling **Instellingen › Siri en Opdrachten › Bediening met AirPods en Apple Watch (proef)**,
  standaard **uit** (`AppConfiguratie.sleutelAirPodsProef`). Geldt vanaf de volgende keer dat de
  kookmodus opent.
- `NuSpeeltBediening` (`Knipsel/Kookmodus/NuSpeelt.swift`), alleen actief als de instelling aan staat
  **en** de kookmodus open is; bij sluiten haalt `stop()` alle doelen weg, zet de knoppen uit en wist
  Nu speelt.
  - `MPNowPlayingInfoCenter`: titel = recept, artiest = "Stap 3 van 7" (of "Klaar"), album =
    "Knipsel", afbeelding = de eigen gerechtfoto of anders het categoriesymbool wit op tomaat,
    afspeelsnelheid 1 tijdens het voorlezen en 0 daarbuiten. Bijgewerkt bij elke stapwissel en elke
    verandering van de voorlezer.
  - `MPRemoteCommandCenter`: `nextTrack` → volgende stap, `previousTrack` → vorige stap, `play` → stap
    (opnieuw) voorlezen, `pause` → stoppen met voorlezen, `togglePlayPause` → wisselt daartussen.
    Spoelen staat uit.
  - De knoppen lopen via `AfstandsBediening` → `KookOpdrachtUitvoerder` → `Spraakbediening.voerUit`:
    hetzelfde pad als spraak en Siri, dus het voorlezen volgt.
- Met de proef aan zet het voorlezen zonder microfoon de audiosessie op `.playback` / `.spokenAudio`
  **zonder** `.duckOthers` (`NuSpeeltBediening.spraakOpties`). Reden: `.duckOthers` maakt de sessie
  mixbaar, en volgens Apple wordt een mixbare app nooit de Nu speelt-app. Gevolg tijdens de proef:
  muziek of een podcast pauzeert bij het voorlezen in plaats van zachter te gaan.
- De app heeft achtergrondmodus `audio`, zodat de kookmodus doorloopt met het scherm op slot.

AirPods (standaard indeling): 1× drukken = afspelen/pauze, 2× = volgende nummer, 3× = vorige nummer.
In Knipsel: 1× = stap voorlezen of stoppen, 2× = volgende stap, 3× = vorige stap.

## Aannames en risico's

1. **Nu speelt vraagt een actieve audiosessie die speelt.** iOS kiest als Nu speelt-app de app die
   het laatst niet-mixbare audio afspeelde. Knipsel speelt alleen tijdens het voorlezen; daarna wordt
   de sessie gedeactiveerd. Mogelijk verdwijnt Knipsel dan na een paar seconden uit Nu speelt en gaan
   de knoppen terug naar bijvoorbeeld Spotify. Dat is precies wat de proef moet uitwijzen.
2. **Telt spraaksynthese mee?** Zonder microfoon spreekt `AVSpeechSynthesizer` via de eigen
   audiosessie van de app (`SysteemSpreker`). Met de microfoon aan gaat de stem via de
   `AVAudioEngine` van de spraakbediening (`MotorSpreker`), met `.playAndRecord` **mét**
   `.duckOthers` (dat is niet gewijzigd: de echo-onderdrukking en het zachter zetten van muziek
   blijven). Die sessie is dus mixbaar; verwacht dat Nu speelt dan niet werkt. Test daarom eerst met
   de microfoon uit.
3. **Achtergrond.** Zonder geluid kan iOS een app op de achtergrond na korte tijd pauzeren; de
   MediaPlayer-knoppen wekken een app meestal wel (zoals bij podcastapps), maar dat is niet getest.
4. **Siri en dezelfde sessie.** Siri-opdrachten draaien in hetzelfde proces en vinden de sessie via
   `ActieveKookSessie`; dat staat los van deze proef.

## Testplan voor Peter (iPhone 14 Plus of 15 Plus, AirPods, Apple Watch)

Voorbereiding: Instellingen › Siri en Opdrachten › *Bediening met AirPods en Apple Watch (proef)* aan.
Open een recept met minstens 4 stappen, zet in de kookmodus de **microfoon uit** en de luidspreker
aan. AirPods in.

| # | Doe | Verwacht | Uitkomst |
|---|---|---|---|
| 1 | Kookmodus open, stap 1 wordt voorgelezen. Kijk op het vergrendelscherm en in het Bedieningspaneel | Nu speelt: recepttitel, "Stap 1 van n", foto of symbool | |
| 2 | Steeltje 2× | Stap 2 in beeld en voorgelezen | |
| 3 | Steeltje 3× | Terug naar stap 1 | |
| 4 | Steeltje 1× tijdens het voorlezen | Voorlezen stopt | |
| 5 | Steeltje 1× als het stil is | Stap opnieuw voorgelezen | |
| 6 | Wacht 30 s na het voorlezen, dan 2× | Werkt het nog, of gaat het naar een andere app? | |
| 7 | Scherm op slot, 2× | Volgende stap wordt voorgelezen | |
| 8 | Apple Watch: Nu speelt openen | Recept zichtbaar; ⏭/⏮/⏯ werken als hierboven | |
| 9 | Zelfde als 2–5 met de **microfoon aan** | Verwacht: werkt waarschijnlijk niet (zie aanname 2) | |
| 10 | Muziek aan (Spotify of Muziek), dan een stap voorlezen | Muziek pauzeert tijdens het voorlezen (proef); daarna weer verder? | |
| 11 | Kookmodus sluiten, steeltje 1× | Knipsel weg uit Nu speelt; de knop werkt weer voor je muziek | |
| 12 | Instelling uit, kookmodus open | Geen Knipsel in Nu speelt; muziek gaat weer zachter i.p.v. pauzeren | |

## Beslissing na de test

- Werken 1–8: proef wordt een gewone functie (instelling blijft, eventueel standaard aan).
- Werkt het alleen tijdens het voorlezen (6 faalt): mogelijke vervolgstap is een stil geluid laten
  spelen zolang de kookmodus open is, zodat Knipsel de Nu speelt-app blijft. Dat kost batterij en
  houdt andere audio onderbroken; eerst met Peter afwegen.
- Werkt niets: proef stoppen, instelling weghalen, en in ontwerp §4 laag 4 op "geparkeerd" zetten.
