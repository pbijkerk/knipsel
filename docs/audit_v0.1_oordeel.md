# Oordeel over de audit v0.1

| Versie | Datum | Auteur | Wijziging | Status |
|---|---|---|---|---|
| 0.1 | 19-11-2026 | Claude (Hermes), akkoord Peter | Oordeel per aanbeveling uit `audit_v0.1_concept.md` | Vastgesteld |

Getoetst aan de code op `main` (`fa54d2d`), dezelfde stand die de audit bekeek. Het eindoordeel en
de lijst met wat goed zit kloppen. Bij een deel van de bevindingen klopt de onderbouwing niet; die
staan hieronder met de reden.

## Per aanbeveling

| # | Bevinding | Oordeel | Toelichting | Wat we doen |
|---|---|---|---|---|
| 1 | `laadfout` wordt niet getoond | Eens, eerste prioriteit | Klopt: de fout wordt bewaard en gelogd, maar nergens gelezen. Opent de opslag niet, dan lijkt de app leeg en de recepten weg. | Herstelscherm met uitleg; geen automatische herstelactie. Nu. |
| 2 | `aps-environment: development` | Oneens | Met automatische ondertekening zet Xcode de waarde bij het archiveren voor TestFlight en App Store zelf op `production`. De TestFlight-build heeft al een Thuis-share gemaakt en gesynchroniseerd. | Niets wijzigen. Eventueel controleren op een TestFlight-build. |
| 3 | `KookmodusScherm.swift` te groot | Eens, lagere ernst | Vijf onderdelen in één bestand; opsplitsen is mechanisch en veilig. Geen risico voor de gebruiker, dus geen "midden". | Bij de volgende wijziging aan de kookmodus. |
| 4 | Map `xcodecloud/` niet getrackt | Advies eens, redenering niet | De map bestaat alleen in de Xcode-kopie (aangemaakt bij het instellen van Xcode Cloud). CI werkt op een verse checkout en ziet de map niet. | Opnemen in `.gitignore`. Nu. |
| 5 | Deel-extensie faalt stil bij `try?` | Eens | De extensie heeft geen logging; een mislukte kopie van een afbeelding of PDF geeft alleen "niets gedeeld". | Logging en een duidelijkere melding. Nu. |
| 6 | Ruwe foutmeldingen op twee plekken | Eens, groter dan gemeld | Rond tien plekken gebruiken `localizedDescription`; vier daarvan tonen alleen de Engelse systeemtekst. | Alle meldingen centraal vertalen, zoals `DeelFout`. Nu. |
| 7 | Geen lintstap, extensies indirect gebouwd | Grotendeels oneens | CI controleert de opmaak al met swift-format. De extensies zitten in de app en worden altijd meegebouwd. | Niets. Een strengere lint kan later. |
| 8 | `ThuisDelen.gedeeld` lastig te testen | Mag, geen haast | Klopt als ontwerpopmerking, maar het werkt en de tests gebruiken een nep-dienst. | Pas als dat stuk toch verandert. |

## Buiten de audit

De audit is statisch. De problemen van 18 november (ontbrekend CloudKit-schema in Production,
recepten die nog niet geüpload waren bij het delen) vielen daarbuiten en kwamen alleen op het
toestel boven. Na elke wijziging aan opslag of delen hoort een korte test in TestFlight; zie
`docs/testflight-testers.md`.
