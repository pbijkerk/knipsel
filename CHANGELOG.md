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
