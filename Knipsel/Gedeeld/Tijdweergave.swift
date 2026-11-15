import Foundation

// Gedeeld met de widget-extensie (KnipselWidgets): alleen Foundation.

/// Tijden in beeld en hardop.
enum Tijdweergave {
    /// "45 sec", "1 min 30 sec", "20 min", "1 u", "1 u 15 min"; een bereik "10–15 min".
    static func label(seconden: Int, vanaf: Int? = nil) -> String {
        guard let vanaf else { return kort(seconden) }
        // Zelfde eenheid: "10–15 min", "2–3 u".
        if vanaf % 60 == 0, seconden % 60 == 0, seconden < 3600 { return "\(vanaf / 60)–\(seconden / 60) min" }
        if vanaf % 3600 == 0, seconden % 3600 == 0 { return "\(vanaf / 3600)–\(seconden / 3600) u" }
        return "\(kort(vanaf))–\(kort(seconden))"
    }

    static func kort(_ seconden: Int) -> String {
        let uren = seconden / 3600
        let minuten = (seconden % 3600) / 60
        let rest = seconden % 60
        if uren == 0 && minuten == 0 { return "\(rest) sec" }
        if uren == 0 { return rest == 0 ? "\(minuten) min" : "\(minuten) min \(rest) sec" }
        var delen = ["\(uren) u"]
        if minuten > 0 { delen.append("\(minuten) min") }
        return delen.joined(separator: " ")
    }

    /// "20 minuten", "1 minuut", "anderhalf uur", "1 uur en 15 minuten", "45 seconden".
    static func gesproken(_ seconden: Int) -> String {
        if seconden == 5400 { return "anderhalf uur" }
        if seconden == 1800 { return "een half uur" }
        let uren = seconden / 3600
        let minuten = (seconden % 3600) / 60
        let rest = seconden % 60
        var delen: [String] = []
        if uren > 0 { delen.append("\(uren) uur") }
        if minuten > 0 { delen.append(minuten == 1 ? "1 minuut" : "\(minuten) minuten") }
        if rest > 0 || delen.isEmpty { delen.append(rest == 1 ? "1 seconde" : "\(rest) seconden") }
        return delen.joined(separator: " en ")
    }

    /// Resterende tijd op een chip: "18:42", boven het uur "1:05:09".
    static func klok(_ interval: TimeInterval) -> String {
        let totaal = max(0, Int(interval.rounded(.up)))
        let uren = totaal / 3600
        let minuten = (totaal % 3600) / 60
        let seconden = totaal % 60
        if uren > 0 { return String(format: "%d:%02d:%02d", uren, minuten, seconden) }
        return String(format: "%02d:%02d", minuten, seconden)
    }

    /// Hardop: "12 minuten", onder de twee minuten met seconden ("1 minuut en 20 seconden").
    static func resterendGesproken(_ interval: TimeInterval) -> String {
        let totaal = max(0, Int(interval.rounded(.up)))
        if totaal >= 120 {
            let minuten = Int((Double(totaal) / 60).rounded())
            return gesproken(minuten * 60)
        }
        return gesproken(totaal)
    }
}
