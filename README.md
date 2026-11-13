# Knipsel

Recepten-app voor iPhone en iPad: fotografeer een recept uit krant of tijdschrift, bewaar alleen de
recepttekst, deel hem in, en kook handsfree met voorlezen en spraakbesturing in je eigen tempo.

**Status:** ontwerpfase (v0.1). De app bevat nog alleen de basis voor TestFlight.

- Ontwerp en eisen: [`docs/ontwerp.md`](docs/ontwerp.md)
- Schermschetsen: [`docs/ux/schetsen.html`](docs/ux/schetsen.html)
- Projectbrief: [`docs/projectbrief.md`](docs/projectbrief.md)
- Proef herkennen en indelen: [`docs/spikes/ocr-en-indeling.md`](docs/spikes/ocr-en-indeling.md)
- TestFlight instellen: [`docs/testflight-xcode-cloud.md`](docs/testflight-xcode-cloud.md)

**Vereisten:** iOS/iPadOS 26+, Xcode 26+, XcodeGen. Alleen Apple-frameworks, alles on-device.

```bash
brew install xcodegen
xcodegen generate
open Knipsel.xcodeproj
```
