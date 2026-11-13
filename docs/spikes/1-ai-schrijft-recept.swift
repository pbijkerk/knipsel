import Foundation
import Vision
import AppKit
import FoundationModels

@Generable struct Ingredient { 
  @Guide(description: "Hoeveelheid als getal, leeg als niet genoemd") var hoeveelheid: Double?
  @Guide(description: "Eenheid zoals g, ml, el, tl, stuks, cm; leeg als geen") var eenheid: String?
  var naam: String }
@Generable struct Stap { var tekst: String
  @Guide(description: "Wachttijd in minuten die in deze stap genoemd wordt, anders leeg") var timerMinuten: Int? }
@Generable struct Recept {
  var titel: String
  var porties: Int?
  var ingredienten: [Ingredient]
  var stappen: [Stap]
  @Guide(.anyOf(["Voorgerecht","Soep","Hoofdgerecht","Bijgerecht","Salade","Nagerecht","Gebak","Brood","Saus","Drank","Ontbijt & lunch","Borrelhapje"])) var categorie: String
  @Guide(description: "Nummers van de tekstblokken die NIET bij het recept horen (advertenties, andere artikelen)") var genegeerdeBlokken: [Int]
}

let img = NSImage(contentsOfFile: "testpagina.png")!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let req = VNRecognizeTextRequest(); req.recognitionLevel = .accurate; req.recognitionLanguages = ["nl-NL"]; req.usesLanguageCorrection = true
let t0 = Date()
try VNImageRequestHandler(cgImage: img).perform([req])
let lines = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
print("OCR \(lines.count) regels in \(String(format: "%.1f", Date().timeIntervalSince(t0)))s")
let blocks = lines.enumerated().map { "[\($0.offset)] \($0.element)" }.joined(separator: "\n")
print(blocks)
let sem = DispatchSemaphore(value: 0)
Task {
  let s = LanguageModelSession(instructions: "Je zet OCR-tekst van een krant- of tijdschriftpagina om in een gestructureerd recept. Neem alleen recepttekst over, letterlijk, en verzin niets.")
  let t1 = Date()
  do {
    let r = try await s.respond(to: "Tekstblokken:\n\(blocks)", generating: Recept.self).content
    print("\nFM in \(String(format: "%.1f", Date().timeIntervalSince(t1)))s")
    print("Titel:", r.titel, "| porties:", r.porties as Any, "| categorie:", r.categorie)
    r.ingredienten.forEach { print(" -", $0.hoeveelheid as Any, $0.eenheid ?? "", $0.naam) }
    r.stappen.enumerated().forEach { print(" \($0.offset+1).", $0.element.tekst, "⏱", $0.element.timerMinuten as Any) }
    print("Genegeerd:", r.genegeerdeBlokken)
  } catch { print("FM fout:", error) }
  sem.signal()
}
sem.wait()
