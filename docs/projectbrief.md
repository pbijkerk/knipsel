# Projectbrief — Knipsel

## Doel
Een eigen recepten-app voor iPhone en iPad waarmee Peter recepten uit kranten en tijdschriften
vastlegt (alleen de recepttekst), overzichtelijk indeelt en in de keuken handsfree gebruikt.

## Gebruikers
- Peter (eigenaar), en een huisgenoot via een gedeeld kookboek.

## Scope v1
- Recept knippen uit een foto of scan: alleen de recepttekst, met controle vóór bewaren.
- Categorieën (standaardset, aanpasbaar en uitbreidbaar) en labels.
- Goed leesbare receptweergave en een kookmodus voor op afstand.
- Voorlezen per stap, in het tempo van de kok.
- Spraakbesturing in de app, plus Siri/Opdrachten.
- Timers uit de recepttekst, ook op het vergrendelscherm.
- iCloud-synchronisatie en delen met een huisgenoot.

## Buiten scope v1
- Recepten van websites importeren, boodschappenlijst, Apple Watch-app, Mac-versie
  (staan als suggestie in `docs/ontwerp.md` §10).

## Randvoorwaarden
- iOS/iPadOS 26+, alleen Apple-frameworks, verwerking on-device, geen eigen server of account.
- Distributie alleen via TestFlight (interne groep), zoals FableFlux.
- Publieke repo: geen echte krantenfoto's of persoonlijke gegevens in Git.

## Succes
- Een krantenrecept staat binnen een minuut correct in de app.
- Een gerecht van begin tot eind koken zonder het scherm aan te raken.
