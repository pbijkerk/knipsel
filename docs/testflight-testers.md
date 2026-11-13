# TestFlight — testinformatie en externe testers

Over te nemen in App Store Connect → Knipsel → TestFlight → **Testinformatie**.

## Beta-appbeschrijving

> Knipsel bewaart recepten uit kranten en tijdschriften. Fotografeer de pagina en Knipsel houdt alleen
> de recepttekst over: titel, ingrediënten en bereiding. Recepten deel je in naar categorieën en labels,
> en in de keuken lees je ze groot en rustig, laat je ze stap voor stap voorlezen en bedien je de app
> met je stem, zodat je het scherm met vieze handen niet hoeft aan te raken.
>
> Dit is een vroege testversie die per fase groeit. Bij elke build staat onder "Wat te testen" wat er
> nieuw is en waar we feedback op zoeken.

## Velden

| Veld | Invullen |
|---|---|
| Feedback-e-mail | je eigen e-mailadres |
| Marketing-URL | `https://github.com/pbijkerk/knipsel` |
| Privacybeleid-URL | `https://github.com/pbijkerk/knipsel/blob/main/docs/privacy.md` |
| Contactgegevens beoordeling | je naam, telefoon en e-mail (alleen voor Apple) |
| Aanmelden vereist | Nee |
| Opmerkingen voor de beoordelaar | *"Geen account nodig. Recepten worden lokaal en in de eigen iCloud van de gebruiker bewaard. Voeg een recept toe met de +-knop om de app te proberen."* |

## "Wat te testen" — gaat vanzelf

Xcode Cloud neemt per build de tekst over uit [`TestFlight/WhatToTest.nl-NL.txt`](../TestFlight/WhatToTest.nl-NL.txt).
Dat bestand wordt bij elke fase bijgewerkt. Lukt dat niet (bijv. andere taal in App Store Connect),
dan staat de tekst daar om te kopiëren.

## Externe testers toevoegen

1. TestFlight → **Externe tests → +** → groep `Familie`.
2. Testers toevoegen op e-mailadres, of **Openbare link** aanzetten en doorsturen.
3. **Xcode Cloud aanpassen**, anders mogen builds niet naar externe testers:
   - Xcode → ⌘9 → Cloud → rechtsklik op de workflow → **Edit Workflow**.
   - **Archive → Deployment Preparation:** `TestFlight and App Store` (was: *Internal Testing Only*).
   - **Post-Actions → + → TestFlight External Testing** → groep `Familie`.
   - Save. Alleen builds ná deze wijziging zijn geschikt voor externe testers.
4. De eerste externe build gaat langs Apple (*Beta App Review*, meestal < 1 dag). Latere builds van
   dezelfde versie gaan meestal direct door.

## Interne testers (alternatief)

Mensen in je App Store Connect-team (Gebruikers en toegang, rol bijv. *Marketing*), daarna in groep
`Intern`. Geen beoordeling door Apple, maar ze krijgen een account in jouw App Store Connect.
