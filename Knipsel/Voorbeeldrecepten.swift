#if DEBUG
    import CoreData

    /// Verzonnen recepten voor previews en schermafbeeldingen. Geen echte krantenteksten.
    enum Voorbeeldrecepten {
        static func vul(_ context: NSManagedObjectContext) throws {
            try Inrichting.zaaiStandaard(in: context)
            let categorieen = Dictionary(
                uniqueKeysWithValues: try context.fetch(Categorie.verzoek()).map { ($0.naam ?? "", $0) })
            let labels = Dictionary(
                uniqueKeysWithValues: try context.fetch(ReceptLabel.verzoek()).map { ($0.naam ?? "", $0) })

            func recept(
                _ titel: String, intro: String? = nil, porties: Int = 4, minuten: Int = 0, totaal: Int = 0,
                bron: String? = nil, pagina: String? = nil, categorie: [String], label: [String] = [],
                ingredienten: [String], stappen: [String], notities: String? = nil
            ) {
                var invoer = ReceptInvoer()
                invoer.titel = titel
                invoer.intro = intro ?? ""
                invoer.porties = porties
                invoer.bereidingstijdMinuten = minuten
                invoer.totaleTijdMinuten = totaal
                invoer.bronNaam = bron ?? ""
                invoer.bronDatum = bron == nil ? nil : Date(timeIntervalSince1970: 1_794_528_000)
                invoer.bronPagina = pagina ?? ""
                invoer.categorieen = Set(categorie.compactMap { categorieen[$0]?.objectID })
                invoer.labels = Set(label.compactMap { labels[$0]?.objectID })
                invoer.ingredientenTekst = ingredienten.joined(separator: "\n")
                invoer.stappenTekst = stappen.joined(separator: "\n")
                invoer.notities = notities ?? ""
                _ = try? invoer.bewaar(in: context)
            }

            recept(
                "Pompoensoep met gember", intro: "Een warme, fluweelzachte soep voor koude dagen.", minuten: 45,
                bron: "Het Testblad", pagina: "52", categorie: ["Soepen"], label: ["Vegetarisch", "Voorbereiden"],
                ingredienten: [
                    "1 flespompoen (ca. 1 kg)", "2 uien, gesnipperd", "3 cm verse gember", "2 el olijfolie",
                    "1 l groentebouillon", "200 ml kokosmelk", "½ tl kerriepoeder", "peper en zout",
                ],
                stappen: [
                    "Schil de pompoen, verwijder de pitten en snijd het vruchtvlees in blokjes van 2 cm.",
                    "Verhit de olie in een soeppan en fruit de ui en gember 5 minuten op middelhoog vuur.",
                    "Voeg de pompoen en het kerriepoeder toe en bak 2 minuten mee. Schenk de bouillon erbij en laat 20 minuten zachtjes koken.",
                    "Pureer de soep met een staafmixer, roer de kokosmelk erdoor en breng op smaak met peper en zout.",
                ], notities: "Lekker met geroosterde pompoenpitten.")
            recept(
                "Prei-quiche met oude kaas", minuten: 25, totaal: 60, bron: "Proefkeuken", categorie: ["Lunch"],
                label: ["Vegetarisch"],
                ingredienten: ["1 rol bladerdeeg", "3 stengels prei", "4 eieren", "150 g oude kaas, geraspt"],
                stappen: [
                    "Verwarm de oven voor op 200 °C.", "Snijd de prei in ringen en stoof 8 minuten.",
                    "Klop de eieren los met de kaas, schep de prei erdoor en giet in de vorm. Bak 35 minuten.",
                ])
            recept(
                "Stoofpot met rode wijn en paddenstoelen", porties: 6, minuten: 30, totaal: 180,
                categorie: ["Hoofdgerechten"], label: ["Vlees", "Feestelijk"],
                ingredienten: [
                    "1 kg runderstoofvlees", "500 g kastanjechampignons", "½ fles rode wijn", "2 laurierblaadjes",
                ],
                stappen: ["Braad het vlees rondom bruin.", "Voeg wijn en kruiden toe en laat 2½ uur sudderen."])
            recept(
                "Lauwwarme linzensalade", porties: 2, minuten: 25, categorie: ["Salades", "Lunch"],
                label: ["Vegan", "Snel (< 30 min)"],
                ingredienten: ["200 g beluga-linzen", "1 rode ui", "handje peterselie"],
                stappen: ["Kook de linzen gaar."])
            recept(
                "Rabarbercrumble", minuten: 50, categorie: [], label: ["Vegetarisch"],
                ingredienten: ["500 g rabarber", "100 g koude boter", "150 g bloem"],
                stappen: ["Snijd de rabarber in stukjes.", "Kruimel boter, bloem en suiker en bak 30 minuten."])
        }
    }

    extension Opslag {
        static let voorbeeld: Opslag = {
            let opslag = Opslag(inGeheugen: true)
            try? Voorbeeldrecepten.vul(opslag.context)
            return opslag
        }()

        var eersteRecept: Recept {
            let verzoek = Recept.verzoek()
            verzoek.sortDescriptors = ReceptFilter.sortering
            verzoek.predicate = NSPredicate(format: "titel BEGINSWITH %@", "Pompoensoep")
            return (try? context.fetch(verzoek).first) ?? Recept(context: context)
        }
    }
#endif
