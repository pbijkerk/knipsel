import ActivityKit
import AlarmKit
import Foundation
import SwiftUI

// Gedeeld tussen de app en de widget-extensie (KnipselWidgets, fase 7). Alleen typen die de Live
// Activity nodig heeft; geen Core Data, geen kookmodus. De extensie heeft geen entitlements.

/// Wat een kooktimer (AlarmKit) meeneemt naar zijn Live Activity en het alarm.
struct KookTimerMetadata: AlarmMetadata {
    /// "Pompoensoep met gember".
    var recept: String
    /// "Stap 3: laat 20 minuten zachtjes koken".
    var naam: String
    /// "Stap 3", voor kleine plekken (Dynamic Island).
    var kort: String
}

/// De Live Activity van een open kookmodus: "Stap 3 van 7 · Pompoensoep", de stap kort, en de
/// eerstvolgende timer. Zonder pushmeldingen: de app werkt hem bij bij elke stapwissel en timer.
struct KookActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var stapNummer: Int
        var aantalStappen: Int
        /// De staptekst, ingekort tot ±110 tekens.
        var stapTekst: String
        var isAfgerond: Bool
        /// De eerstvolgende timer; `nil` als er geen loopt.
        var timer: Timerstand?
        /// Hoeveel timers er in totaal lopen (ook gepauzeerd of afgaand).
        var aantalTimers: Int

        init(
            stapNummer: Int, aantalStappen: Int, stapTekst: String, isAfgerond: Bool = false,
            timer: Timerstand? = nil, aantalTimers: Int = 0
        ) {
            self.stapNummer = stapNummer
            self.aantalStappen = aantalStappen
            self.stapTekst = stapTekst
            self.isAfgerond = isAfgerond
            self.timer = timer
            self.aantalTimers = aantalTimers
        }

        /// "Stap 3 van 7", of "Klaar".
        var kop: String { isAfgerond ? "Klaar" : "Stap \(stapNummer) van \(aantalStappen)" }
    }

    struct Timerstand: Codable, Hashable, Sendable {
        /// "Stap 3".
        var naam: String
        /// Wanneer hij afgaat, zolang hij loopt.
        var einde: Date?
        /// Wanneer hij (opnieuw) begon te lopen; voor `Text(timerInterval:)`.
        var begin: Date?
        /// Resterende seconden als hij gepauzeerd is.
        var resterend: TimeInterval?
        var gaatAf: Bool

        init(naam: String, einde: Date? = nil, begin: Date? = nil, resterend: TimeInterval? = nil, gaatAf: Bool = false)
        {
            self.naam = naam
            self.einde = einde
            self.begin = begin
            self.resterend = resterend
            self.gaatAf = gaatAf
        }
    }

    var titel: String
    /// SF Symbol van de eerste categorie.
    var symbool: String
}

/// Kleuren van de Live Activities: tomaat op donker papier, zoals de kookmodus.
enum Activitykleuren {
    static let tomaat = Color(red: 0xD9 / 255, green: 0x61 / 255, blue: 0x3C / 255)
    static let papier = Color(red: 0x1F / 255, green: 0x1B / 255, blue: 0x18 / 255)
    static let inkt = Color(red: 0xF6 / 255, green: 0xEF / 255, blue: 0xE4 / 255)
    static let gedimd = Color(red: 0xA8 / 255, green: 0x9D / 255, blue: 0x90 / 255)
}
