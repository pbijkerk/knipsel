import CoreGraphics
import Foundation

@testable import Knipsel

/// Echte herkenning (Vision, nl-NL, accurate, met taalcorrectie) van een foto van Peter: een
/// krantenrubriek, "Peren in rode wijn" (4032 × 3024). Kaders, betrouwbaarheid, recept en OCR-fouten
/// zijn echt; de column is vervangen door verzonnen tekst van dezelfde vorm (auteursrecht, K14). Een column vooraf, de bereiding zonder
/// kopje midden in de tweede kolom en de ingrediënten in een kader onderaan (#17). Kaders zoals in
/// `HerkendeRegel`: genormaliseerd, oorsprong linksboven (Vision geeft linksonder: y = 1 − y − hoogte).
/// Let op de echte OCR: de initiaal ontbreekt ("ok wel" i.p.v. "Ook wel"), en na "los de suiker op" mist de punt.
enum PerenInRodeWijn {
    static func r(_ tekst: String, _ x: CGFloat, _ y: CGFloat, _ b: CGFloat, _ h: CGFloat, _ zeker: Float = 1)
        -> HerkendeRegel
    {
        HerkendeRegel(tekst: tekst, kader: CGRect(x: x, y: y, width: b, height: h), betrouwbaarheid: zeker)
    }

    static let regels: [HerkendeRegel] = [
        r("Peren in rode wijn", 0.2054, 0.0145, 0.1938, 0.016),
        r("Nagerecht voor 4 personen", 0.2052, 0.0316, 0.2718, 0.0212),
        r("ok wel eens zo'n winteravond", 0.2402, 0.0846, 0.2271, 0.0164),
        r("gehad, met koude handen en", 0.2326, 0.1017, 0.2171, 0.0146),
        r("een lege maag? Ik wel, vaak.", 0.2442, 0.1192, 0.2112, 0.0131),
        r("Op de markt in Deventer stond", 0.2093, 0.1352, 0.2384, 0.0146),
        r("vroeger een kraam waar je voor", 0.211, 0.1484, 0.264, 0.0164),
        r("weinig geld een kom erwtensoep", 0.2111, 0.1657, 0.26, 0.0143),
        r("kreeg, dik genoeg om een lepel in", 0.2112, 0.183, 0.2616, 0.0117),
        r("te laten staan. Daar dacht ik", 0.2132, 0.1991, 0.2345, 0.0117),
        r("aan toen ik deze week peren", 0.2112, 0.215, 0.1783, 0.0103),
        r("zag liggen bij de groenteboer.", 0.2304, 0.2281, 0.2465, 0.0156),
        r("Mijn grootmoeder stoofde ze in", 0.2112, 0.2455, 0.2306, 0.0117, 0.5),
        r("een gietijzeren pan op het", 0.2112, 0.2616, 0.2267, 0.0117),
        r("achterste pitje van het fornuis.", 0.2111, 0.2758, 0.2619, 0.0154),
        r("Ze deed er een kaneelstokje bij", 0.2132, 0.2936, 0.2539, 0.0132),
        r("en liet de pan uren staan. Dat", 0.2112, 0.308, 0.2597, 0.0146),
        r("rook je tot in de gang, en de", 0.2132, 0.3241, 0.2384, 0.0132),
        r("buren kwamen soms aanbellen", 0.2112, 0.3415, 0.2306, 0.0146),
        r("om te vragen wat er op het vuur", 0.215, 0.3562, 0.2483, 0.0147),
        r("stond. Betalen hoefde niemand", 0.2151, 0.3735, 0.2597, 0.0117),
        r("iets, er was altijd genoeg.", 0.2169, 0.3883, 0.2328, 0.0148),
        r("Zelf maakte ik ze lang op haar", 0.2326, 0.4055, 0.2112, 0.0117),
        r("manier, tot ik bij een vriend", 0.2171, 0.4215, 0.2578, 0.0103),
        r("in Gent een andere versie at.", 0.2209, 0.436, 0.2481, 0.0117),
        r("Hij gebruikte rode wijn in plaats", 0.2209, 0.4506, 0.2481, 0.0117),
        r("van water en suiker, en de pe-", 0.219, 0.465, 0.2597, 0.0117),
        r("ren werden donker en glanzend.", 0.2188, 0.4783, 0.2427, 0.0149),
        r("Een eenvoudig nagerecht, maar", 0.2168, 0.494, 0.262, 0.0148),
        r("het zag eruit alsof je er de hele", 0.2169, 0.5101, 0.2599, 0.0138),
        r("middag mee bezig was geweest.", 0.2171, 0.5275, 0.2539, 0.0117),
        r("Hij vertelde dat hij het recept", 0.2169, 0.5416, 0.2484, 0.0145),
        r("van zijn moeder had, die het op", 0.2149, 0.5569, 0.2408, 0.0159),
        r("haar beurt uit een oud kookboek", 0.2188, 0.5729, 0.233, 0.0146),
        r("had overgeschreven. Zo gaan re-", 0.2188, 0.5884, 0.2234, 0.0163),
        r("cepten van hand tot hand, met", 0.219, 0.6047, 0.2539, 0.0117),
        r("steeds een kleine aanpassing", 0.2208, 0.6195, 0.2561, 0.0138),
        r("onderweg. Ook ik heb er iets aan", 0.2207, 0.6365, 0.1264, 0.0137),
        r("veranderd, al zal mijn vriend", 0.2362, 0.6492, 0.2312, 0.017),
        r("dat vast niet goedkeuren. Vroe-", 0.2208, 0.6668, 0.2289, 0.014),
        r("ger liet ik de saus urenlang in-", 0.5019, 0.0843, 0.2229, 0.0132),
        r("koken. Onderdeel daarvan was het", 0.5019, 0.1002, 0.2461, 0.0132),
        r("inkoken van het kookvocht tot er", 0.5019, 0.1163, 0.2636, 0.0145),
        r("stroop overbleef. Dat kost tijd", 0.5039, 0.1337, 0.2481, 0.0117),
        r("en het huis ruikt er de hele dag", 0.5039, 0.1497, 0.2539, 0.0131),
        r("naar. Tegenwoordig bind ik de", 0.5058, 0.1657, 0.2345, 0.0131),
        r("saus met een beetje zetmeel. Het", 0.5019, 0.1817, 0.2558, 0.0131),
        r("gaat sneller en het resultaat is", 0.5039, 0.1977, 0.2422, 0.0102),
        r("glanzend en zacht van smaak. Het", 0.5056, 0.2116, 0.231, 0.0144),
        r("smaakt niet minder lekker.", 0.5039, 0.2282, 0.1473, 0.0131),
        r("Schil de peren, maar laat zo", 0.5037, 0.2583, 0.2329, 0.0175),
        r("mogelijk het steeltje eraan zitten.", 0.5056, 0.2744, 0.26, 0.0161),
        r("Neem een hoog pannetje waar", 0.5076, 0.2902, 0.2425, 0.0147),
        r("de peren krap aan in passen.", 0.5076, 0.3059, 0.2251, 0.015),
        r("Verwarm er de wijn met de", 0.5037, 0.3214, 0.2175, 0.0161),
        r("specerijen in en los de suiker op", 0.5037, 0.3379, 0.2523, 0.0157),
        r("Doe de peren in de pan en kook", 0.5075, 0.3528, 0.2505, 0.016),
        r("ze heel zachtjes een 20 minuten.", 0.5056, 0.3697, 0.2543, 0.0166),
        r("Draai ze af en toe om. Haal de", 0.5076, 0.3858, 0.233, 0.0144),
        r("peren uit de pan en laat ze af-", 0.5075, 0.4009, 0.2331, 0.0157),
        r("koelen. Roer het zetmeel los met", 0.5074, 0.4143, 0.2546, 0.0186),
        r("een minidrupje water en voeg bij", 0.5076, 0.433, 0.2541, 0.0128),
        r("het kookvocht. Laat al roerend", 0.5077, 0.4476, 0.2367, 0.0122),
        r("binden en kook zachtjes 1 minuut", 0.5078, 0.4622, 0.2597, 0.0117),
        r("door. Laat afkoelen, zet een paar", 0.5097, 0.4782, 0.2539, 0.0146),
        r("uur in de koelkast.", 0.5076, 0.493, 0.1437, 0.013),
        r("Overgiet de peren vlak voor", 0.527, 0.5083, 0.2193, 0.0144),
        r("het serveren met de saus. Wie", 0.5096, 0.5245, 0.2347, 0.0133),
        r("wil, doet er vanille-ijs of slagroom", 0.5097, 0.5407, 0.2578, 0.0117),
        r("bij, maar eigenlijk is dat zonde.", 0.5078, 0.5567, 0.2422, 0.0131),
        r("Wijn erbij? Welnee.", 0.5075, 0.5713, 0.1536, 0.0161),
        r("volkskeuken@volkskrant.nl", 0.5039, 0.6657, 0.2112, 0.0116, 0.5),
        r("INGREDIËNTEN", 0.4147, 0.8416, 0.1647, 0.016),
        r("• 4 handperen (ze hoeven niet helemaal rijp te zijn)", 0.2984, 0.8765, 0.3992, 0.0132),
        r("• 1 fles rode wijn", 0.4322, 0.8909, 0.1337, 0.0117),
        r("• 1 kruidnagel", 0.4299, 0.9056, 0.1285, 0.0163),
        r("• ½ steranijs", 0.4419, 0.9229, 0.1085, 0.0132, 0.5),
        r("• snufje kaneel", 0.438, 0.939, 0.124, 0.0117),
        r("• 150 gram suiker", 0.4264, 0.9534, 0.1453, 0.0147),
        r("• 1 dikke theel. aardappelzetmeel", 0.3719, 0.9674, 0.2581, 0.0139),
    ]
}
