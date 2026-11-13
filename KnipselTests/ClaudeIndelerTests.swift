import Foundation
import Testing

@testable import Knipsel

/// Vangt verzoeken af en geeft een vast antwoord. Alleen voor de sessie van deze tests.
final class NepAnthropic: URLProtocol {
    struct Antwoord: Sendable {
        var status: Int
        var body: Data
    }

    nonisolated(unsafe) static var antwoord = Antwoord(status: 200, body: Data())
    nonisolated(unsafe) static var verzoeken: [(URLRequest, Data)] = []

    static var sessie: URLSession {
        let configuratie = URLSessionConfiguration.ephemeral
        configuratie.protocolClasses = [NepAnthropic.self]
        return URLSession(configuration: configuratie)
    }

    static func zet(status: Int = 200, tekst: String) {
        let body: [String: Any] = ["content": [["type": "text", "text": tekst]], "role": "assistant"]
        antwoord = Antwoord(status: status, body: try! JSONSerialization.data(withJSONObject: body))
        verzoeken = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // URLSession zet de body om in een stream.
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let gelezen = stream.read(&buffer, maxLength: buffer.count)
                if gelezen <= 0 { break }
                body.append(buffer, count: gelezen)
            }
            stream.close()
        }
        Self.verzoeken.append((request, body))
        let antwoord = HTTPURLResponse(
            url: request.url!, statusCode: Self.antwoord.status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: antwoord, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.antwoord.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct ClaudeIndelerTests {
    let claudeAntwoord = """
        ```json
        {"titel":[0],"intro":[1],"ingredienten":[3,4,5,6,7,8,9,10],"bereiding":[11,12,13,14,15,16,17,18,24,25,26],\
        "categorieen":["Soepen","Bestaat niet"],"labels":["vegetarisch"]}
        ```
        """

    func indeler(sleutel: String? = "test-sleutel-niet-echt") -> ClaudeIndeler {
        ClaudeIndeler(sleutel: { sleutel }, sessie: NepAnthropic.sessie, terugval: RegelIndeler())
    }

    @Test func verzoekBevatAlleenTekst() async throws {
        NepAnthropic.zet(tekst: claudeAntwoord)
        _ = await indeler().deelIn(Testpagina.regels, categorieen: Testpagina.categorieen, labels: Testpagina.labels)

        let (verzoek, body) = try #require(NepAnthropic.verzoeken.first)
        #expect(NepAnthropic.verzoeken.count == 1)
        #expect(verzoek.url == URL(string: "https://api.anthropic.com/v1/messages"))
        #expect(verzoek.httpMethod == "POST")
        #expect(verzoek.value(forHTTPHeaderField: "x-api-key") == "test-sleutel-niet-echt")
        #expect(verzoek.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")

        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == "claude-haiku-4-5")
        let berichten = try #require(json["messages"] as? [[String: Any]])
        #expect(berichten.count == 1)
        // Inhoud is platte tekst (een string), geen lijst met blokken, dus ook geen beeld.
        let inhoud = try #require(berichten[0]["content"] as? String)
        #expect(inhoud.contains("[0] Pompoensoep met gember"))
        #expect(inhoud.contains("[11] 1. Schil de pompoen, verwijder de pitten en"))
        #expect(inhoud.contains("Soepen"))
        // Geen beeld en geen kaders in het hele verzoek.
        let tekst = String(decoding: body, as: UTF8.self)
        for verboden in ["image", "base64", "media_type", "png", "jpeg", "kader", "0.034"] {
            #expect(!tekst.contains(verboden), "\(verboden) hoort niet in het verzoek")
        }
        #expect(Set(json.keys) == ["model", "max_tokens", "system", "messages"])
    }

    @Test func antwoordWordtIndeling() async {
        NepAnthropic.zet(tekst: claudeAntwoord)
        let indeling = await indeler().deelIn(
            Testpagina.regels, categorieen: Testpagina.categorieen, labels: Testpagina.labels)
        #expect(indeling.bron == .claude)
        #expect(indeling.blokken(.titel) == [0])
        #expect(indeling.blokken(.intro) == [1])
        #expect(indeling.blokken(.ingredient) == Array(3...10))
        #expect(indeling.blokken(.weg) == [2] + Array(19...23) + Array(27...30))
        #expect(indeling.categorieen == ["Soepen"])
        #expect(indeling.labels == ["Vegetarisch"])
        // Zelfde recept als met de regels.
        let concept = ReceptOpbouw.bouw(Testpagina.regels, indeling: indeling)
        let viaRegels = ReceptOpbouw.bouw(
            Testpagina.regels,
            indeling: RegelIndeler.deelIn(
                Testpagina.regels, categorieen: Testpagina.categorieen, labels: Testpagina.labels))
        #expect(concept.stappen.map(\.tekst) == Testpagina.stappen)
        #expect(concept.ingredienten.map(\.tekst) == viaRegels.ingredienten.map(\.tekst))
        #expect(concept.titel == viaRegels.titel)
    }

    @Test func httpFoutValtTerugOpRegels() async {
        NepAnthropic.zet(status: 401, tekst: "{}")
        let indeling = await indeler().deelIn(
            Testpagina.regels, categorieen: Testpagina.categorieen, labels: Testpagina.labels)
        #expect(NepAnthropic.verzoeken.count == 1)
        #expect(indeling.bron == .regels)
        #expect(indeling.blokken(.titel) == [0])
    }

    @Test func zonderSleutelGeenVerzoek() async {
        NepAnthropic.zet(tekst: claudeAntwoord)
        for sleutel in [nil, ""] as [String?] {
            let indeling = await indeler(sleutel: sleutel).deelIn(
                Testpagina.regels, categorieen: Testpagina.categorieen, labels: Testpagina.labels)
            #expect(indeling.bron == .regels)
        }
        #expect(NepAnthropic.verzoeken.isEmpty)
    }

    @Test func onbruikbaarAntwoordValtTerug() async {
        for tekst in ["Sorry, dat kan ik niet.", #"{"titel":[],"ingredienten":[]}"#, #"{"titel":[99]}"#] {
            NepAnthropic.zet(tekst: tekst)
            let indeling = await indeler().deelIn(
                Testpagina.regels, categorieen: Testpagina.categorieen, labels: Testpagina.labels)
            #expect(indeling.bron == .regels, "\(tekst)")
        }
    }

    @Test func keuzeZonderSleutelIsGeenClaude() {
        #expect(!(IndelerKeuze.standaard(sleutel: nil) is ClaudeIndeler))
        #expect(!(IndelerKeuze.standaard(sleutel: "") is ClaudeIndeler))
        #expect(IndelerKeuze.standaard(sleutel: "test-sleutel-niet-echt") is ClaudeIndeler)
    }
}
