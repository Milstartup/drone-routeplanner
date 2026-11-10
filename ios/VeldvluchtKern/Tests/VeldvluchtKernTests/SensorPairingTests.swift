@testable import VeldvluchtKern
import XCTest

final class SensorPairingTests: XCTestCase {
    private let settings = SensorPairing.Settings(
        hotspotName: "iPhone van Milan", hotspotPassword: "geheim 1&2=3", sensorId: "broccoli-west-s1",
        sensorKey: "0123456789abcdef0123456789abcdef", cloudProject: "abcdefghijklmnopqrst",
        cloudKey: "sb_publishable_proefsleutel123", depthCm: 15)

    func testGoodSettingsHaveNoProblems() {
        XCTAssertEqual(SensorPairing.problems(settings), [])
        var appOnly = settings
        appOnly.cloudProject = nil
        appOnly.sensorKey = nil
        appOnly.cloudKey = nil
        XCTAssertEqual(SensorPairing.problems(appOnly), [], "zonder cloud stuurt het kastje alleen naar de app")
    }

    func testTheSameChecksAsTheBox() {
        var s = settings
        s.hotspotName = ""
        s.hotspotPassword = "kort"
        s.sensorId = "Broccoli West"
        s.depthCm = 300
        s.intervalMinutes = 0
        XCTAssertEqual(SensorPairing.problems(s).count, 5, "\(SensorPairing.problems(s))")
        s = settings
        s.hotspotName = String(repeating: "é", count: 17)
        XCTAssertEqual(SensorPairing.problems(s).count, 1, "34 bytes: te lang voor de wifi van het kastje")
        s = settings
        s.sensorKey = nil
        XCTAssertEqual(SensorPairing.problems(s), ["De sleutel van de sensor ontbreekt. Log in en druk eerst op Bewaren bij Sensoren."])
        s = settings
        s.cloudProject = "Mijn-Project"
        XCTAssertEqual(SensorPairing.problems(s), ["Het cloudproject klopt niet: alleen kleine letters en cijfers."])
    }

    func testSendsAFormTheBoxCanRead() throws {
        let request = SensorPairing.request(settings)
        XCTAssertEqual(request.url?.absoluteString, "http://192.168.4.1/instellingen")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertFalse(request.allowsCellularAccess)
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertEqual(body, "hotspot=iPhone%20van%20Milan&wachtwoord=geheim%201%262%3D3&sensor=broccoli-west-s1"
                       + "&sleutel=0123456789abcdef0123456789abcdef&project=abcdefghijklmnopqrst"
                       + "&cloudsleutel=sb_publishable_proefsleutel123&diepte=15&interval=60")
        XCTAssertEqual(SensorPairing.formEncoded("Milan’s iPhone"), "Milan%E2%80%99s%20iPhone")
    }

    func testReadsTheAnswerOfTheBox() {
        XCTAssertEqual(SensorPairing.outcome(data: Data(#"{"ok":true,"sensorId":"broccoli-west-s1","ruw":2875}"#.utf8), status: 200),
                       .paired(sensorId: "broccoli-west-s1", raw: 2875))
        XCTAssertEqual(SensorPairing.outcome(data: Data(#"{"ok":false,"fout":"Vul het wachtwoord van de hotspot in."}"#.utf8), status: 400),
                       .refused("Vul het wachtwoord van de hotspot in."))
        guard case .refused = SensorPairing.outcome(data: Data("<html>".utf8), status: 302) else { return XCTFail() }
    }
}
