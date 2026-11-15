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
| 7 | AlarmKit, Live Activities | Info.plist + widget-extensie `KnipselWidgets` (zie hieronder) |

## Deel-extensie (#18)

De app bevat een Share Extension `KnipselDelen` (*Knipsel* in het deelmenu), met een **eigen
app-ID** `com.peterbijkerk.knipsel.delen`. App en extensie delen de **App Group**
`group.com.peterbijkerk.knipsel` (in `Knipsel/Knipsel.entitlements` en
`KnipselDelen/KnipselDelen.entitlements`): daarin staat *Nog te controleren*. Beide app-ID's moeten in
het developerportaal de capability *App Groups* met die groep hebben; signing is automatisch.
Versie en buildnummer van de extensie lopen mee met de app (`MARKETING_VERSION` /
`CURRENT_PROJECT_VERSION` op projectniveau in `project.yml`).

Faalt een Xcode Cloud-build op signing (*"No profiles for 'com.peterbijkerk.knipsel.delen'"*,
*"Provisioning profile doesn't include the com.apple.security.application-groups entitlement"*):
open het project eenmalig in Xcode, kies bij beide targets (Knipsel en KnipselDelen) onder *Signing &
Capabilities* het team en controleer dat *App Groups* met `group.com.peterbijkerk.knipsel` aangevinkt
is; controleer in het portaal dat de groep aan **beide** app-ID's hangt en start de build opnieuw.

Een nieuwe capability vraagt soms een eenmalige handmatige stap in Xcode; die staat dan in het issue.

## Widget-extensie voor Live Activities (#8)

De app bevat sinds fase 7 een widget-extensie `KnipselWidgets` (`PlugIns/KnipselWidgets.appex`) met de
Live Activities van de kookmodus en de kooktimers, met een **eigen app-ID**
`com.peterbijkerk.knipsel.widgets`. Die extensie heeft **geen entitlements en geen capabilities**: geen
App Group, geen iCloud, geen push. AlarmKit en Live Activities vragen geen capability, alleen
Info.plist-sleutels in de app (`NSAlarmKitUsageDescription`, `NSSupportsLiveActivities`).

Eenmalig in het portaal (developer.apple.com/account › Certificates, IDs & Profiles › Identifiers › ＋ ›
App IDs › App): Explicit `com.peterbijkerk.knipsel.widgets`, beschrijving "Knipsel Widgets", **geen**
capabilities aanvinken › Continue › Register. Signing is automatisch; versie en buildnummer lopen mee
met de app.

Faalt een Xcode Cloud-build op signing (*"No profiles for 'com.peterbijkerk.knipsel.widgets'"*): controleer
dat de app-ID bestaat, open het project eenmalig in Xcode, kies bij het target KnipselWidgets onder
*Signing & Capabilities* het team (automatisch beheer) en start de build opnieuw.
