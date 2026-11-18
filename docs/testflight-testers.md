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

## Je huisgenoot Knipsel geven (Thuis delen, #9)

Thuis delen werkt alleen als je huisgenoot zelf Knipsel heeft, met een **eigen Apple ID** en iCloud aan.
Zonder App Store gaat dat via TestFlight, op één van twee manieren:

| | Interne tester | Externe tester |
|---|---|---|
| Wat je huisgenoot moet zijn | Gebruiker in jouw App Store Connect-team (Gebruikers en toegang › ＋, rol bijv. *Marketing* of *Ontwikkelaar*); de uitnodiging per e-mail accepteren | Niets: alleen een e-mailadres, of de openbare link |
| Apple-beoordeling | Nee, elke build meteen | Eerste build van een versie langs *Beta App Review* (meestal < 1 dag) |
| Xcode Cloud | Zoals nu (*Internal Testing Only*) | Workflow aanpassen, zie *Externe testers toevoegen* hierboven |
| Nadeel | Huisgenoot krijgt een account in jouw App Store Connect | Wachten op de beoordeling; openbare link kan door anderen gebruikt worden |

Advies: **extern**, groep `Familie`, uitnodigen op e-mailadres (geen openbare link). Daarna:

1. Huisgenoot installeert TestFlight, opent de uitnodiging en installeert Knipsel; iCloud staat aan
   voor Knipsel (Instellingen › [naam] › iCloud › Apps die iCloud gebruiken).
2. Jij: zet een recept in Thuis (recept › ⋯ › *Verplaats naar Thuis*), dan Instellingen › *Thuis delen*
   › *Nodig iemand uit* en stuur de link via Berichten of Mail.
3. Huisgenoot tikt op de link; Knipsel opent en Thuis verschijnt (dat kan even duren).

Let op: TestFlight-builds praten met de **Production**-omgeving van CloudKit. Rol eerst het schema uit
(CloudKit Console › Knipsel-container › *Deploy Schema Changes*), anders werkt sync en delen niet.

### CloudKit-schema klaarzetten (na elke nieuwe modelversie)

*Deploy Schema Changes* zet alleen over wat al in **Development** staat. Zegt de Console "geen
wijzigingen" terwijl er een modelversie bij kwam, dan heeft Development de nieuwe recordtypes nog niet.
Zo komen ze erin:

1. Draai de app vanuit Xcode (**Debug**, ⌘R) op een iPhone of iPad met iCloud aan.
2. Wacht op **"CloudKit-schema klaar"**: Instellingen › Over Knipsel › *CloudKit-schema (Development)*
   (alleen zichtbaar in Debug), of in het log (categorie `CloudKitSchema`). Lukte het niet, tik dan op
   *Zet CloudKit-schema klaar*.
3. Verplaats in diezelfde Debug-run een recept naar Thuis en zet een boodschap en een maaltijd in Thuis,
   zodat ook de velden voor delen in Development komen.
4. CloudKit Console › Knipsel-container › *Deploy Schema Changes* — nu staan er wijzigingen
   (o.a. `CD_BoodschappenItem`, `CD_Maaltijd`).
5. Test daarna de TestFlight-build (Production). Staat er in Instellingen › Thuis delen nog een melding,
   tik *Probeer opnieuw*.
