@testable import VeldvluchtKern
import XCTest

/// The cloud client against a fake Supabase: the requests it makes and how it reads the answers.
final class CloudTests: XCTestCase {
    private let config = CloudConfig(projectRef: "abcdefghijklmnopqrst", key: "sb_publishable_proefsleutel123")
    private var requests: [URLRequest] = []
    private var answers: [(path: String, status: Int, body: String)] = []
    private var clock = Date(timeIntervalSince1970: 1_793_000_000)

    private func api(session: CloudSession? = nil) -> CloudAPI {
        CloudAPI(config: config, session: session, now: { [unowned self] in clock }) { [unowned self] request in
            requests.append(request)
            let path = request.url!.absoluteString.replacingOccurrences(of: "https://abcdefghijklmnopqrst.supabase.co/", with: "")
            guard let index = answers.firstIndex(where: { path.hasPrefix($0.path) }) else { return (Data("{}".utf8), 404) }
            let answer = answers.remove(at: index)
            return (Data(answer.body.utf8), answer.status)
        }
    }

    private func body(_ request: URLRequest) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
    }

    private let loggedIn = CloudSession(accessToken: "toegang", refreshToken: "ververs", expiresAt: Date(timeIntervalSince1970: 1_793_003_600),
                                        userId: "00000000-0000-0000-0000-00000000000a", email: "milan@voorbeeld.nl")

    func testTheConfigNeedsAProjectAndAKey() {
        XCTAssertTrue(config.isUsable)
        XCTAssertEqual(config.baseURL.absoluteString, "https://abcdefghijklmnopqrst.supabase.co")
        XCTAssertFalse(CloudConfig(projectRef: "", key: "").isUsable)
        XCTAssertFalse(CloudConfig(projectRef: "https://iets.supabase.co", key: "sb_publishable_proefsleutel123").isUsable)
    }

    func testLogsInAndKeepsTheLogin() async throws {
        answers = [("auth/v1/token?grant_type=password", 200,
                    #"{"access_token":"toegang","refresh_token":"ververs","expires_in":3600,"user":{"id":"u1","email":"milan@voorbeeld.nl"}}"#)]
        let api = api()
        var kept: CloudSession?
        api.onSessionChange = { kept = $0 }
        let session = try await api.signIn(email: "milan@voorbeeld.nl", password: "geheim123")
        XCTAssertEqual(session.userId, "u1")
        XCTAssertEqual(kept, session)
        XCTAssertEqual(session.expiresAt, clock.addingTimeInterval(3600))
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), config.key)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(body(request)["password"] as? String, "geheim123")
    }

    func testExplainsAWrongPasswordInDutch() async {
        answers = [("auth/v1/token", 400, #"{"code":400,"error_code":"invalid_credentials","msg":"Invalid login credentials"}"#)]
        do {
            _ = try await api().signIn(email: "a@b.nl", password: "fout")
            XCTFail("hoort te mislukken")
        } catch {
            XCTAssertEqual(error.localizedDescription, "E-mailadres of wachtwoord klopt niet.")
        }
    }

    func testAnAccountThatMustBeConfirmedFirst() async throws {
        answers = [("auth/v1/signup", 200, #"{"id":"u1","email":"a@b.nl","confirmation_sent_at":"2026-10-27T10:00:00Z"}"#)]
        let loggedIn = try await api().signUp(email: "a@b.nl", password: "geheim123")
        XCTAssertFalse(loggedIn)
    }

    func testRefreshesAnExpiredLoginFirst() async throws {
        clock = loggedIn.expiresAt.addingTimeInterval(-10)
        answers = [
            ("auth/v1/token?grant_type=refresh_token", 200,
             #"{"access_token":"nieuw","refresh_token":"ververs2","expires_in":3600,"user":{"id":"u1","email":"milan@voorbeeld.nl"}}"#),
            ("rest/v1/velden", 200, "[]"),
        ]
        let api = api(session: loggedIn)
        _ = try await api.fields()
        XCTAssertEqual(body(requests[0])["refresh_token"] as? String, "ververs")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer nieuw")
        XCTAssertEqual(api.session?.refreshToken, "ververs2")
    }

    func testAnInvalidRefreshLogsOut() async {
        clock = loggedIn.expiresAt
        answers = [("auth/v1/token?grant_type=refresh_token", 400, #"{"error_code":"refresh_token_not_found","msg":"Invalid Refresh Token"}"#)]
        let api = api(session: loggedIn)
        do {
            _ = try await api.fields()
            XCTFail("hoort te mislukken")
        } catch let error as CloudError {
            XCTAssertTrue(error.loggedOut)
            XCTAssertNil(api.session)
        } catch {
            XCTFail("\(error)")
        }
    }

    func testSavesAFieldAndGetsTheKeysOfItsSensors() async throws {
        let date = Date(timeIntervalSince1970: 1_793_000_000)
        var field = FieldRecord(id: "broccoli-west", name: "Broccoli west",
                                boundary: [LatLng(lat: 52.5, lng: 5.54), LatLng(lat: 52.5, lng: 5.541), LatLng(lat: 52.501, lng: 5.541)],
                                home: nil, settings: .planner, createdAt: date, updatedAt: date)
        field.sensors = [FieldSensor(id: "broccoli-west-s1", location: LatLng(lat: 52.5005, lng: 5.5405))]
        answers = [("rest/v1/rpc/bewaar_veld", 200, #"[{"sensor_id":"broccoli-west-s1","sleutel":"0123456789abcdef0123456789abcdef"}]"#)]
        let keys = try await api(session: loggedIn).saveField(field)
        XCTAssertEqual(keys, ["broccoli-west-s1": "0123456789abcdef0123456789abcdef"])
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer toegang")
        XCTAssertEqual(body(request)["p_veld_id"] as? String, "broccoli-west")
        let sent = try XCTUnwrap(body(request)["p_veld"] as? [String: Any])
        XCTAssertEqual(sent["format"] as? String, "veldvlucht/veld")
        XCTAssertEqual((sent["sensors"] as? [[String: Any]])?.first?["id"] as? String, "broccoli-west-s1")
    }

    func testSavesMarkersWithWhatTheAISaw() async throws {
        answers = [("rest/v1/aandacht", 204, ""), ("rest/v1/aandacht", 201, "")]
        let seen = Date(timeIntervalSince1970: 1_794_000_000)
        try await api(session: loggedIn).saveAttention(field: "veld-1", flightId: "vlucht 1", marks: [
            .init(position: LatLng(lat: 52.5, lng: 5.54), reason: "Plek 1: AI: te droog (82 % zeker).", photo: "DJI_0001.JPG",
                  confidence: 0.82, kind: "te-droog", seenAt: seen),
            .init(position: LatLng(lat: 52.5, lng: 5.54), reason: "Plek 2: Plant kleiner.", photo: nil, confidence: 0.4),
        ])
        XCTAssertEqual(requests.map(\.httpMethod), ["DELETE", "POST"])
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(requests[1].httpBody)) as? [[String: Any]])
        XCTAssertEqual(rows[0]["soort"] as? String, "te-droog")
        XCTAssertEqual(rows[0]["gezien"] as? String, ISO8601DateFormatter().string(from: seen))
        XCTAssertTrue(rows[1]["soort"] is NSNull)
        XCTAssertTrue(rows[1]["gezien"] is NSNull)
    }

    func testReadsFieldsAndMeasurementsAsTheDatabaseGivesThem() async throws {
        let date = Date(timeIntervalSince1970: 1_793_000_000)
        let field = FieldRecord(id: "broccoli-west", name: "Broccoli west", boundary: [], home: nil, settings: .planner,
                                createdAt: date, updatedAt: date)
        let veld = String(decoding: try field.encoded(), as: UTF8.self)
        answers = [
            ("rest/v1/velden", 200, #"[{"id":"11111111-2222-3333-4444-555555555555","veld_id":"broccoli-west","naam":"Broccoli west","eigenaar":"u2","veld":\#(veld)}]"#),
            ("rest/v1/sensormetingen", 200,
             #"[{"tijd":"2026-10-27T21:20:43.123456+00:00","ruw":2875,"batterij_volt":3.91,"diepte_cm":15,"sensoren":{"sensor_id":"broccoli-west-s1"}}]"#),
        ]
        let api = api(session: loggedIn)
        let fields = try await api.fields()
        XCTAssertEqual(fields.first?.veld, field)
        XCTAssertEqual(fields.first?.eigenaar, "u2")
        let measurements = try await api.measurements(field: fields[0].id, since: date)
        XCTAssertEqual(measurements.first?.sensorId, "broccoli-west-s1")
        XCTAssertEqual(measurements.first?.tijd.timeIntervalSince1970 ?? 0, 1_793_136_043.123, accuracy: 0.001)
        XCTAssertTrue(requests[1].url!.absoluteString.contains("veld=eq.11111111-2222-3333-4444-555555555555"))
    }

    func testAnswersOfTheDatabaseAfterALogoutMeanLogInAgain() async {
        answers = [("rest/v1/velden", 401, #"{"code":"PGRST301","message":"JWT expired"}"#)]
        do {
            _ = try await api(session: loggedIn).fields()
            XCTFail("hoort te mislukken")
        } catch let error as CloudError {
            XCTAssertTrue(error.loggedOut)
        } catch {
            XCTFail("\(error)")
        }
    }

    func testForwardsAnUploadWithTheKeyWithoutALogin() async throws {
        answers = [("rest/v1/rpc/sensor_upload", 200, #"{"ontvangen":1,"nieuw":1}"#)]
        let upload = Data(#"{"format":"veld/sensorupload","version":0,"sensorId":"x-s1","measurements":[{"ageS":5,"raw":2000}]}"#.utf8)
        try await api(session: loggedIn).forward(upload: upload, key: "sleutel123")
        let request = try XCTUnwrap(requests.first)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(body(request)["p_sleutel"] as? String, "sleutel123")
        XCTAssertEqual((body(request)["p_upload"] as? [String: Any])?["sensorId"] as? String, "x-s1")
    }

    func testNoInternetIsSaidPlainly() async {
        let api = CloudAPI(config: config, session: loggedIn) { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await api.fields()
            XCTFail("hoort te mislukken")
        } catch let error as CloudError {
            XCTAssertTrue(error.offline)
            XCTAssertNotNil(api.session, "no internet does not log you out")
        } catch {
            XCTFail("\(error)")
        }
    }
}
