# Changelog

Alle noemenswaardige wijzigingen aan dit project worden in dit bestand bijgehouden.

Het formaat is gebaseerd op [Keep a Changelog](https://keepachangelog.com/nl/1.1.0/)
en dit project volgt [Semantic Versioning](https://semver.org/lang/nl/).

## [Unreleased]

### Toegevoegd
- Privacybeleid (`docs/privacy.md`), testinformatie en uitleg voor externe testers (`docs/testflight-testers.md`), en "Wat te testen" per build via `TestFlight/WhatToTest.nl-NL.txt`
- Ontwerp v0.1 met eisen K1–K14 en bronnen (`docs/ontwerp.md`), schermschetsen voor iPhone en iPad
  (`docs/ux/schetsen.html`) en een proef met on-device herkennen en indelen van een krantenrecept
  (`docs/spikes/`)
- Ontwerp v0.2: besluiten over meerdere categorieën, alleen tekst bewaren, delen per recept, indelen met regels + optioneel Claude (toestellen zonder Apple Intelligence) en impliciete commando's standaard aan
- Basis-app voor TestFlight: iPhone en iPad, iOS 26, lijst met standaardcategorieën, CI op GitHub Actions
- Fase 1: recepten bewaren met iCloud-sync (Core Data + CloudKit), bibliotheek met zoeken op titel en ingrediënt, categorie- en labelfilters, categorie- en labelbeheer, recept invoeren en leesbare receptweergave (#2)
- Fase 2: recept knippen — pagina scannen of foto kiezen, tekst herkennen op het toestel, indelen met regels (optioneel Claude met eigen sleutel), knipselscherm met gekleurde blokken en controlescherm met twijfel in oranje; ingrediënten krijgen hoeveelheid, eenheid en naam (#3)
- Fase 3: kookmodus — één stap groot (≥ 30 pt), donker, scherm blijft aan, tikzones (rechts ⅔ verder, links ⅓ terug), vegen en toetsenbord, ingrediënten van de stap oranje, afvinklijst naast de stap op iPad, "Gekookt" in het kooklog; porties schalen met nette breuken, ook in de receptweergave (#4)
- Fase 4: voorlezen per stap in de kookmodus — daarna wacht Knipsel; stop, herhaal en ingrediënten voorlezen, uitspraakregels ("twee eetlepels", "anderhalve liter"), Nederlandse stem en tempo (0,8–1,2×) instelbaar, ingrediënten van de stap meelezen, muziek gaat zachter (#5)
- Fase 5: spraakbediening in de kookmodus zonder wekwoord — "volgende", "terug", "herhaal", "stop" (ook tijdens het voorlezen), "lees voor", "langzamer/sneller", "wat heb ik nodig?", "hoeveel bouillon?" (geschaald, in beeld en hardop), "stap drie", "stoppen met koken", en "oké"/"klaar" = volgende (uit te zetten); alleen korte uitingen tellen, optioneel wekwoord "Knipsel"; herkenning op het toestel (SpeechAnalyzer, terugval SFSpeechRecognizer) met echo-onderdrukking; microfoonstatus, bevestiging met tikje, uitleg vóór de toestemming en Instellingen › Spraakbediening (#6)
- Stappen herkennen in lopende bereidingstekst: Knipsel deelt een bereiding zonder nummers zelf in stappen van één of een paar handelingen (zinsgrenzen met afkortingen als "ca." en "180 °C.", kookwerkwoorden, signaalwoorden als "intussen" en "tot slot", kopjes als "Voor de saus:"); de tekst blijft woord voor woord gelijk. In het controlescherm "Splits hier" en "Voeg samen met vorige" (⋯, lang drukken of vegen); bij Recept bewerken "Stappen opnieuw indelen" met een voorbeeld vooraf en Bewaar of Annuleer (#17)

- UX-ronde "mooier en makkelijker": eisen U1–U8 (`docs/ontwerp.md` §2.1) en schetsen per scherm met keuzes (`docs/ux/schetsen-v2.html`); uitgewerkt in #21–#24

### Gewijzigd
- Bibliotheek op de iPhone: recepten staan als kaarten in een raster (2 kolommen, meer op een breder scherm), elk in de kleur en met het symbool van de eerste categorie en met de titel in serif, de tijd en hoe vaak je het kookte. Eén rij met categorieën; de labels zitten achter de knop *Filter*. *Knip* is een tomaatrode knop rechtsonder, onder de duim; ＋ en instellingen blijven bovenin. Lang drukken op een kaart of regel geeft *Verwijder*. In Instellingen › Weergave kies je *Kaarten* of *Lijst*; ook de lijst (en op iPad de middenkolom) toont nu het symbool van de categorie in plaats van steeds het schaartje (#23)
- Recept: porties en een brede knop "Kook dit" staan in een vaste balk onderin, ook als je naar de bereiding scrolt; de ingrediënten schalen meteen mee en de laatste notitie valt niet achter de balk. Bovenin staan de tijden en het aantal personen als blokjes, en categorieën en labels op een eigen regel. Op iPad is de balk smaller en gecentreerd (#22)
- Kookmodus: onderin een kleine terug-knop en een brede knop "Volgende stap" (72 pt hoog, ook met een knokkel te raken); bij de laatste stap "Klaar", daarna "Gekookt" en "Sluiten". De microfoonstatus staat als korte zin in beeld ("Luistert · zeg ‘volgende’", "Microfoon uit"). Op iPad staat de stap op 40 pt (een lange stap krimpt tot minimaal 32 pt) en lichten de ingrediënten van deze stap op in de afvinklijst, met de hoeveelheid in tomaat. Tikken, vegen, toetsenbord en spraak werken zoals voorheen (#21)
- Indelen met de regels: een column of verhaal vóór het recept wordt intro, en de bereiding begint bij de eerste alinea met een gebiedende zin, ook zonder kopje midden in een kolom; e-mailadressen vallen weg, een regel als "Nagerecht voor 4 personen" is geen titel, één reclamewoord in een lange column maakt er geen advertentie van, en bolletjes (•) vallen van de ingrediënten af (#17)
- Indelen met Claude (en Apple Intelligence): het antwoord geeft per stap de regelnummers en de eerste woorden; Knipsel knipt de letterlijke tekst daarop en valt terug op de regels als dat niet klopt. De opdracht noemt de column vooraf en de bereiding zonder kopje (#17)

### Opgelost
- Spraakbediening: "volgende", "vorige" en "herhaal" werden twee keer uitgevoerd (eerst bij het voorlopige resultaat, ± 2 s later nog eens bij het eindresultaat van dezelfde uiting)
- Porties schalen geeft "1 ui" en "2 eieren" in plaats van "1 uien" en "2 ei" (enkelvoud/meervoud voor veelvoorkomende ingrediënten)
