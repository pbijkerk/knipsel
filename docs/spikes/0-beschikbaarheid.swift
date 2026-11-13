import Foundation
import Vision
import AVFoundation
import Speech
import FoundationModels

let req = VNRecognizeTextRequest()
req.recognitionLevel = .accurate
print("Vision accurate:", (try? req.supportedRecognitionLanguages()) ?? [])
let nlVoices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("nl") }
print("NL voices:", nlVoices.map { "\($0.name) \($0.language) q=\($0.quality.rawValue)" })
print("SFSpeech nl-NL:", SFSpeechRecognizer(locale: Locale(identifier: "nl-NL"))?.supportsOnDeviceRecognition as Any)
let sem = DispatchSemaphore(value: 0)
Task {
  let locs = await SpeechTranscriber.supportedLocales
  print("SpeechTranscriber nl:", locs.filter { $0.identifier.hasPrefix("nl") }.map(\.identifier))
  let m = SystemLanguageModel.default
  print("FM availability:", m.availability)
  print("FM nl supported:", m.supportedLanguages.contains { $0.languageCode?.identifier == "nl" })
  sem.signal()
}
sem.wait()
