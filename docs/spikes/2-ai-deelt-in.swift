import Foundation
import Vision
import AppKit
import FoundationModels

@Generable struct Indeling {
  @Guide(description: "Nummer van het blok met de titel") var titelBlok: Int
  @Guide(description: "Nummers van blokken met ingredientregels (geen kopjes)") var ingredientBlokken: [Int]
  @Guide(description: "Nummers van blokken met bereidingstekst") var bereidingBlokken: [Int]
  @Guide(description: "Nummers van blokken met intro, porties of tijd") var introBlokken: [Int]
  @Guide(.anyOf(["Voorgerecht","Soep","Hoofdgerecht","Bijgerecht","Salade","Nagerecht","Gebak","Brood","Saus","Drank","Ontbijt & lunch","Borrelhapje"])) var categorie: String
}
let img = NSImage(contentsOfFile: "testpagina.png")!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let req = VNRecognizeTextRequest(); req.recognitionLevel = .accurate; req.recognitionLanguages = ["nl-NL"]; req.usesLanguageCorrection = true
let t0 = Date()
try VNImageRequestHandler(cgImage: img).perform([req])
let lines = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
print("OCR \(lines.count) regels in \(String(format: "%.1f", Date().timeIntervalSince(t0)))s")
let blocks = lines.enumerated().map { "[\($0.offset)] \($0.element)" }.joined(separator: "\n")
let sem = DispatchSemaphore(value: 0)
Task {
  let s = LanguageModelSession(instructions: "Je zet OCR-tekst van een krant- of tijdschriftpagina om in een gestructureerd recept. Deel elk blok in. Blokken die niet bij het recept horen (advertenties, andere artikelen) laat je weg.")
  let t1 = Date()
  do {
    let r = try await s.respond(to: "Tekstblokken:\n\(blocks)", generating: Indeling.self).content
    print("\nFM in \(String(format: "%.1f", Date().timeIntervalSince(t1)))s")
    print("titel", r.titelBlok, "ingr", r.ingredientBlokken, "bereiding", r.bereidingBlokken, "intro", r.introBlokken, "cat", r.categorie)
    // deterministisch samenvoegen: nieuwe stap bij regel die met "N." begint
    var stappen:[String]=[]
    for i in r.bereidingBlokken.sorted() { let l=lines[i]; if l.range(of: #"^\d+\."#, options:.regularExpression) != nil || stappen.isEmpty { stappen.append(l) } else { stappen[stappen.count-1] += " " + l } }
    stappen.forEach { print(" >", $0) }
    } catch { print("FM fout:", error) }
  sem.signal()
}
sem.wait()
