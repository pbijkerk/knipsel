#if canImport(FoundationModels)
    import Foundation
    import FoundationModels
    import OSLog

    /// Indelen met het taalmodel op het toestel (Apple Intelligence). Peters toestellen hebben dat niet
    /// (B9); deze indeler wordt alleen gebruikt als het model er is, en valt anders terug.
    struct ModelIndeler: Indeler {
        var terugval: any Indeler = RegelIndeler()

        static var isBeschikbaar: Bool {
            SystemLanguageModel.default.availability == .available
        }

        @Generable
        struct Uitkomst {
            @Guide(description: "Nummers van regels met de titel")
            var titel: [Int]
            @Guide(description: "Nummers van regels met intro, porties of tijd")
            var intro: [Int]
            @Guide(description: "Nummers van regels met ingrediënten (geen kopjes)")
            var ingredienten: [Int]
            @Guide(description: "Nummers van regels met bereidingstekst")
            var bereiding: [Int]
            @Guide(description: "Categorieën, alleen uit de gegeven lijst")
            var categorieen: [String]
            @Guide(description: "Labels, alleen uit de gegeven lijst")
            var labels: [String]
        }

        func deelIn(_ regels: [HerkendeRegel], categorieen: [String], labels: [String]) async -> Indeling {
            guard Self.isBeschikbaar else {
                return await terugval.deelIn(regels, categorieen: categorieen, labels: labels)
            }
            do {
                let sessie = LanguageModelSession(instructions: ClaudeIndeler.opdracht)
                let tekst = regels.enumerated().map { "[\($0.offset)] \($0.element.tekst)" }.joined(separator: "\n")
                let uitkomst = try await sessie.respond(
                    to: """
                        Categorieën: \(categorieen.joined(separator: ", "))
                        Labels: \(labels.joined(separator: ", "))

                        Tekstregels:
                        \(tekst)
                        """,
                    generating: Uitkomst.self
                ).content
                let indeling = Indeling(
                    aantal: regels.count, titel: uitkomst.titel, intro: uitkomst.intro,
                    ingredienten: uitkomst.ingredienten, bereiding: uitkomst.bereiding,
                    categorieen: Indeling.bestaande(uitkomst.categorieen, uit: categorieen),
                    labels: Indeling.bestaande(uitkomst.labels, uit: labels), bron: .model)
                guard !indeling.blokken(.titel).isEmpty else {
                    return await terugval.deelIn(regels, categorieen: categorieen, labels: labels)
                }
                return indeling
            } catch {
                Logger(subsystem: "com.peterbijkerk.knipsel", category: "Model")
                    .info("Model niet gebruikt: \(String(describing: error), privacy: .public)")
                return await terugval.deelIn(regels, categorieen: categorieen, labels: labels)
            }
        }
    }
#endif
