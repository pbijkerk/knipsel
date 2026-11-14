# Privacybeleid Knipsel

*Laatst bijgewerkt: 14 november 2026*

Knipsel is een recepten-app voor iPhone en iPad, gemaakt door Peter Bijkerk voor eigen gebruik en een
kleine kring testers. Dit beleid beschrijft welke gegevens de app gebruikt en waar ze blijven.

## Kort gezegd

- De maker van Knipsel ontvangt **geen** gegevens van jou. Er is geen eigen server, geen account,
  geen advertenties, geen analyse- of trackingsoftware.
- Je recepten staan op je toestel en in **jouw eigen iCloud**.
- Eén uitzondering die je zelf aanzet: als je een eigen Claude-sleutel invult, gaat de herkende
  recepttekst naar Anthropic om in te delen (zie hieronder).

## Welke gegevens en waar

| Gegeven | Waar het blijft |
|---|---|
| Recepten, categorieën, labels, notities | Op je toestel, gesynchroniseerd via je eigen iCloud-account (Apple CloudKit, privédatabase). De maker kan er niet bij. |
| Gedeeld kookboek "Thuis" | In iCloud, alleen zichtbaar voor de mensen die jij uitnodigt. Je kunt delen altijd stoppen. |
| Foto's van een krant- of tijdschriftpagina | Alleen gebruikt om de tekst te herkennen, op het toestel. De foto wordt daarna **niet bewaard**. |
| Eigen foto van je gerecht (optioneel) | Alleen als je er zelf een maakt of kiest. Verkleind bewaard bij het recept, op je toestel en in je eigen iCloud (privédatabase; bij een recept in het gedeelde kookboek "Thuis" ook zichtbaar voor wie je hebt uitgenodigd). Gaat **nooit** naar Claude of de maker. Verwijder hem via ⋯ › Verwijder foto. |
| Spraak (spraakbesturing in de kookmodus) | Herkend op het toestel. Er worden geen opnames bewaard of verstuurd. |
| Voorlezen | Gebeurt op het toestel met de stemmen van iOS. |
| Claude-sleutel (optioneel) | In de Keychain van je toestel. |

## Optioneel: indelen met Claude

Als je in Instellingen een eigen API-sleutel van Anthropic invult, stuurt Knipsel bij het knippen van
een recept **alleen de herkende tekst** naar Anthropic, om te bepalen wat titel, ingrediënten en
bereiding is. De foto gaat nooit mee. Daarop is het privacybeleid van Anthropic van toepassing:
<https://www.anthropic.com/legal/privacy>. Zonder sleutel gebeurt alles op het toestel.

## Rechten die de app vraagt

- **Camera / Foto's** — om een receptpagina vast te leggen, en als je dat wilt een foto van je eigen
  gerecht. Een foto kiezen uit Foto's gebeurt via de systeemkiezer: Knipsel ziet alleen de foto die
  je kiest en vraagt daarvoor geen toegang tot je hele fotobibliotheek.
- **Microfoon en spraakherkenning** — voor bediening met je stem tijdens het koken.
- **Meldingen / alarmen** — voor kooktimers.

Je kunt elk recht weigeren of later intrekken in Instellingen van iOS; de rest van de app blijft werken.

## Gegevens verwijderen

Verwijder recepten in de app, of verwijder de app. Gegevens in iCloud verwijder je via
Instellingen › [je naam] › iCloud › Opslag beheren › Knipsel.

## Kinderen

Knipsel is niet gericht op kinderen en verzamelt geen gegevens van wie dan ook.

## Contact

Vragen of opmerkingen: maak een issue aan op <https://github.com/pbijkerk/knipsel/issues>, of gebruik
de feedbackknop in de TestFlight-app.
