# Privacybeleid Knipsel

*Laatst bijgewerkt: 16 november 2026 (boodschappen naar Herinneringen)*

Knipsel is een recepten-app voor iPhone en iPad, gemaakt door Peter Bijkerk voor eigen gebruik en een
kleine kring testers. Dit beleid beschrijft welke gegevens de app gebruikt en waar ze blijven.

## Kort gezegd

- De maker van Knipsel ontvangt **geen** gegevens van jou. Er is geen eigen server, geen account,
  geen advertenties, geen analyse- of trackingsoftware.
- Je recepten staan op je toestel en in **jouw eigen iCloud**.
- Eén uitzondering die je zelf aanzet: als je een eigen Claude-sleutel invult, gaat de herkende
  recepttekst naar Anthropic om in te delen (zie hieronder).
- Lees je een recept in vanaf een link, dan haalt je toestel die pagina **rechtstreeks** bij de
  website op, zoals Safari dat doet. Er zit geen server van Knipsel tussen.

## Welke gegevens en waar

| Gegeven | Waar het blijft |
|---|---|
| Recepten, categorieën, labels, notities | Op je toestel, gesynchroniseerd via je eigen iCloud-account (Apple CloudKit, privédatabase). De maker kan er niet bij. |
| Gedeeld kookboek "Thuis" | Alleen de recepten die jij in Thuis zet (of bewaart met *Bewaar in: Thuis*), in iCloud (Apple CloudKit, gedeelde zone), zichtbaar voor de mensen die jij uitnodigt — niemand anders, ook de maker niet. Zij zien en bewerken van die recepten alles: titel, ingrediënten, stappen, notities, bron, beoordeling, de foto van je gerecht en het kooklog (hoe vaak en wanneer het gekookt is), plus de categorieën en labels die eraan hangen. Recepten in "Mijn recepten" blijven privé. Wie uitnodigt ziet de naam en het e-mailadres of telefoonnummer van de deelnemers (en andersom), zoals iCloud dat bij delen toont. Stop je met delen, dan gaan de Thuis-recepten terug naar jouw Mijn recepten en verdwijnen ze bij de anderen; vertrekt een huisgenoot, dan kan die eerst een kopie maken. Spotlight-index en *Verder met…* blijven per toestel. |
| Foto's van een krant- of tijdschriftpagina | Alleen gebruikt om de tekst te herkennen, op het toestel. De foto wordt daarna **niet bewaard**. |
| Eigen foto van je gerecht (optioneel) | Alleen als je er zelf een maakt of kiest. Verkleind bewaard bij het recept, op je toestel en in je eigen iCloud (privédatabase; bij een recept in het gedeelde kookboek "Thuis" ook zichtbaar voor wie je hebt uitgenodigd). Gaat **nooit** naar Claude of de maker. Verwijder hem via ⋯ › Verwijder foto. |
| Spraak (spraakbesturing in de kookmodus) | Herkend op het toestel. Er worden geen opnames bewaard of verstuurd. |
| Voorlezen | Gebeurt op het toestel met de stemmen van iOS. |
| Siri, Opdrachten en Spotlight | Knipsel zet de **titel en categorie** van je recepten in de zoekindex van iOS, op dit toestel, zodat je ze in Spotlight vindt en Siri ze herkent ("Kook pompoensoep met Knipsel"). Ingrediënten, stappen, notities en foto's gaan niet in de index. Wat je tegen Siri zegt, verwerkt Apple volgens zijn eigen privacybeleid; Knipsel krijgt alleen het gekozen recept of de opdracht ("volgende stap"). |
| Nu speelt (proef, standaard uit) | Met *Bediening met AirPods en Apple Watch* aan toont iOS tijdens het koken de recepttitel, "Stap 3 van 7" en de foto of het symbool van het recept onder Nu speelt (vergrendelscherm, Bedieningspaneel, Apple Watch). Dat blijft op je toestellen. |
| Kooktimers (alarmen) | Een timer is een alarm van iOS (AlarmKit) op je toestel, met de naam van het recept en de stap ("Pompoensoep · Stap 3: laat 20 minuten zachtjes koken"). Knipsel onthoudt de lopende timers (naam en eindtijd) op het toestel, zodat ze na het herstarten weer in beeld staan; ze synchroniseren niet en gaan nergens heen. |
| Live Activities (vergrendelscherm, Dynamic Island) | Zolang de kookmodus open is, toont iOS de recepttitel, "Stap 3 van 7", het begin van de stap en de eerstvolgende timer op je vergrendelscherm en (op toestellen die het hebben) in het Dynamic Island; elke timer heeft er ook een. Dat wordt op het toestel bijgewerkt, zonder pushmeldingen of server. Iedereen die je vergrendelscherm ziet, ziet die stap; zet Live Activities uit in Instellingen › Knipsel. |
| Boodschappen (Herinneringen, optioneel) | Alleen als je in het vel *Boodschappen* op *Zet op de lijst* tikt: Knipsel zet de ingrediënten die jij aanvinkt als herinneringen in je lijst "Boodschappen" (en maakt die lijst aan als hij er niet is), met de naam van het recept als notitie. Om niets dubbel te zetten kijkt Knipsel welke open herinneringen al in die lijst staan; kies je *Erbij tellen*, dan past Knipsel de hoeveelheid van dat item aan. Andere lijsten en herinneringen leest of wijzigt Knipsel niet. De herinneringen staan in de app Herinneringen van Apple, op je toestel en in je iCloud als je Herinneringen daar synchroniseert; deel je die lijst met een huisgenoot, dan ziet die ze ook. Knipsel zelf bewaart alleen welke woorden je "meestal in huis" hebt en hoe vaak je iets uitvinkt, op dit toestel. *Delen als tekst* gaat via het deelmenu van iOS naar de app die jij kiest. Niets hiervan gaat naar Claude of de maker. |
| Claude-sleutel (optioneel) | In de Keychain van je toestel. |
| Ingelezen recepten die nog niet gecontroleerd zijn ("Nog te controleren") | Alleen op je toestel, in een map die alleen Knipsel en zijn deelmenu-onderdeel kunnen lezen (App Group). Na bewaren of annuleren verdwijnen ze, met de bijbehorende bestanden (schermafdruk, PDF, foto). |
| Delen via het deelmenu ("Knipsel" in het deelmenu van Safari, een krantenapp, Foto's of Bestanden) | Knipsel leest alleen wat je zelf deelt: de link, de tekst, de afbeelding(en) of de PDF. Het deelmenu haalt niets op en stuurt niets weg; het zet het item alleen lokaal in *Nog te controleren*. Pas als je Knipsel opent, wordt het ingelezen (een link wordt dan rechtstreeks bij de website opgehaald), en het wordt pas een recept als je het hebt gecontroleerd. |
| Webpagina's van een link | Je toestel haalt de pagina rechtstreeks bij de website op (met de gewone gegevens die elke browser meestuurt, zoals je IP-adres). Knipsel bewaart alleen het recept dat je na controle bewaart, met de naam van de site, de link en de datum. |
| Foto van een receptsite (optioneel, standaard aan) | Eén foto van het gerecht van de site, verkleind bewaard bij het recept (op je toestel en in je eigen iCloud). Uit te zetten in Instellingen › Inlezen. |
| Inloggen bij een site met een betaalmuur | Als je een pagina in Knipsel opent en daar zelf inlogt, bewaart de site haar cookies in de webopslag van Knipsel op dit toestel, zoals in een browser. Knipsel bewaart of ziet **geen wachtwoorden** en stuurt die cookies nergens anders heen. Wis ze door Knipsel te verwijderen. |
| Geplakte tekst, schermafdrukken en PDF's | Alleen op het toestel gelezen (tekstherkenning op het toestel). Bij plakken vraagt iOS eerst of Knipsel het klembord mag lezen. |

## Optioneel: indelen met Claude

Als je in Instellingen een eigen API-sleutel van Anthropic invult, stuurt Knipsel bij het knippen van
een recept **alleen de herkende tekst** naar Anthropic, om te bepalen wat titel, ingrediënten en
bereiding is. Dat geldt ook voor de tekst van een webpagina zonder receptgegevens, geplakte tekst of
een PDF; een recept dat een site al als receptgegevens (schema.org) meestuurt, gaat nooit naar
Claude. De foto gaat nooit mee. Daarop is het privacybeleid van Anthropic van toepassing:
<https://www.anthropic.com/legal/privacy>. Zonder sleutel gebeurt alles op het toestel.

## Rechten die de app vraagt

- **Camera / Foto's** — om een receptpagina vast te leggen, en als je dat wilt een foto van je eigen
  gerecht. Een foto kiezen uit Foto's gebeurt via de systeemkiezer: Knipsel ziet alleen de foto die
  je kiest en vraagt daarvoor geen toegang tot je hele fotobibliotheek.
- **Microfoon en spraakherkenning** — voor bediening met je stem tijdens het koken. Staat de
  kookmodus open en luistert Knipsel, dan blijft dat zo als je het scherm op slot zet of naar een
  andere app gaat (je ziet dan het oranje microfoonlampje); sluit je de kookmodus, dan stopt het.
- **Herinneringen** — om je boodschappen in de lijst "Boodschappen" te zetten. iOS kent alleen volledige
  toegang tot Herinneringen; Knipsel gebruikt die alleen voor die ene lijst en alleen als je zelf op *Zet
  op de lijst* tikt. Weiger je dit, dan kun je de lijst nog steeds als tekst delen.
- **Alarmen** — voor kooktimers: ze gaan ook af als je scherm op slot zit of je telefoon op stil
  staat. Weiger je dit, dan lopen timers alleen zolang Knipsel open is en zegt Knipsel het als ze klaar
  zijn.

Je kunt elk recht weigeren of later intrekken in Instellingen van iOS; de rest van de app blijft werken.

## Gegevens verwijderen

Verwijder recepten in de app, of verwijder de app. Gegevens in iCloud verwijder je via
Instellingen › [je naam] › iCloud › Opslag beheren › Knipsel.

## Kinderen

Knipsel is niet gericht op kinderen en verzamelt geen gegevens van wie dan ook.

## Contact

Vragen of opmerkingen: maak een issue aan op <https://github.com/pbijkerk/knipsel/issues>, of gebruik
de feedbackknop in de TestFlight-app.
