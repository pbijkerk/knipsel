# TestFlight via Xcode Cloud — stappen voor Knipsel

Zelfde route als FableFlux. Wat in de repo moest, is al gedaan:

- [x] Bundle-ID `com.peterbijkerk.knipsel`, team `68K8BCC3DL`, automatische signing (`project.yml`)
- [x] `ITSAppUsesNonExemptEncryption = NO` in `Knipsel/Info.plist` (anders "Missing Compliance")
- [x] iPad-oriëntaties compleet (anders faalt de upload met ITMS-90474)
- [x] App-icoon 1024 px zonder alfakanaal
- [x] Gedeeld scheme `Knipsel` in `Knipsel.xcodeproj/xcshareddata/xcschemes/`

## Wat Peter doet (eenmalig, ±15 minuten)

1. **App Store Connect → Apps → + → Nieuwe app**
   - Platform: iOS · Naam: `Knipsel` (bezet? dan `Knipsel Recepten`; later wijzigbaar)
   - Taal: Nederlands · Bundle-ID: `com.peterbijkerk.knipsel` · SKU: `knipsel` · Volledige toegang
   - Staat de bundle-ID niet in de lijst: Certificates, IDs & Profiles → Identifiers → + → App IDs →
     `com.peterbijkerk.knipsel` (Explicit).
2. **TestFlight → Interne tests → +** → groep `Intern`, automatische distributie aan, jezelf als tester.
   Doe dit vóór stap 3; de workflow wil een groep kiezen.
3. **Xcode → Integrate → Xcode Cloud → Create Workflow** (in `~/Projects/Knipsel/Knipsel.xcodeproj`)
   - GitHub-app: alleen repo `knipsel` toevoegen.
   - Niet direct starten: *Edit Workflow*.
   - Start Conditions → Branch Changes: `main`.
   - Actions: `Build – iOS` verwijderen, + Archive: iOS, scheme `Knipsel`,
     *TestFlight (Internal Testing Only)*.
   - Post-Actions: + TestFlight Internal Testing → groep `Intern`.
   - Save → Start Build op `main`.
4. **TestFlight-app** op iPhone en iPad: uitnodiging accepteren.

Daarna start elke merge naar `main` vanzelf een nieuwe TestFlight-build.

## Later (fase 5–8) komen er rechten en capabilities bij

| Fase | Wat | Waar |
|---|---|---|
| 1 / 8 | iCloud (CloudKit), container `iCloud.com.peterbijkerk.knipsel` | Xcode → Signing & Capabilities; container wordt dan aangemaakt |
| 5 | Microfoon, spraakherkenning | Info.plist-teksten |
| 7 | AlarmKit, Live Activities | Info.plist + widget-extensie |

Een nieuwe capability vraagt soms een eenmalige handmatige stap in Xcode; die staat dan in het issue.
