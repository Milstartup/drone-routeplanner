// Talking to the central system in Supabase (centraal/README.md): logging in, and reading and
// writing fields, sensor measurements, weather, results and flights through its REST API.
// Plain Swift with a transport passed in: the app uses URLSession, the tests a fake server.
import Foundation

/// Which Supabase project, from Config/Lokaal.xcconfig. The key is the project's publishable
/// (or older "anon") key: it may be in the app, but it stays out of git like the DJI key.
struct CloudConfig: Equatable {
    var projectRef: String
    var key: String

    var isUsable: Bool {
        projectRef.range(of: #"^[a-z0-9]{10,40}$"#, options: .regularExpression) != nil && key.count >= 20
    }

    var baseURL: URL { URL(string: "https://\(projectRef).supabase.co")! }
}

/// A login: kept in the Keychain by the app.
struct CloudSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userId: String
    var email: String
}

struct CloudError: LocalizedError, Equatable {
    let message: String
    /// The login is no longer valid: log in again.
    var loggedOut = false
    /// No answer at all: no internet, or the cloud cannot be reached.
    var offline = false
    var errorDescription: String? { message }
}

/// A field in the cloud: your own, or one someone shared with you.
struct CloudField: Decodable, Equatable {
    /// The cloud's own id of the field.
    var id: String
    var veldId: String
    var naam: String
    var veld: FieldRecord
    var eigenaar: String

    enum CodingKeys: String, CodingKey {
        case id, naam, veld, eigenaar
        case veldId = "veld_id"
    }
}

struct CloudMeasurement: Decodable, Equatable {
    var tijd: Date
    var ruw: Double
    var batterijVolt: Double?
    var dieptecm: Double?
    var sensorId: String

    enum CodingKeys: String, CodingKey {
        case tijd, ruw, sensoren
        case batterijVolt = "batterij_volt"
        case dieptecm = "diepte_cm"
    }

    private struct Sensor: Decodable {
        var sensor_id: String
    }

    init(tijd: Date, ruw: Double, batterijVolt: Double?, dieptecm: Double?, sensorId: String) {
        self.tijd = tijd
        self.ruw = ruw
        self.batterijVolt = batterijVolt
        self.dieptecm = dieptecm
        self.sensorId = sensorId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tijd = try c.decode(Date.self, forKey: .tijd)
        ruw = try c.decode(Double.self, forKey: .ruw)
        batterijVolt = try c.decodeIfPresent(Double.self, forKey: .batterijVolt)
        dieptecm = try c.decodeIfPresent(Double.self, forKey: .dieptecm)
        sensorId = try c.decode(Sensor.self, forKey: .sensoren).sensor_id
    }

    /// As a measurement of the sensor placed in `field` (format veld/sensormeting).
    func measurement(field: FieldRecord) -> SensorMeasurement {
        let sensor = field.sensors.first { $0.id == sensorId }
        return SensorMeasurement(format: SensorMeasurement.format, version: SensorMeasurement.version,
                                 sensorId: sensorId, fieldId: field.id,
                                 location: sensor?.location ?? Geo.centroid(field.boundary),
                                 depthCm: dieptecm ?? sensor?.depthCm ?? 15, time: tijd, raw: ruw,
                                 moisturePercent: sensor?.calibration?.percent(raw: ruw),
                                 calibration: sensor?.calibration, batteryVolt: batterijVolt)
    }
}

/// One HTTP exchange: the request, and the answer's body and status code.
typealias CloudTransport = (URLRequest) async throws -> (Data, Int)

final class CloudAPI {
    let config: CloudConfig
    private let transport: CloudTransport
    private let now: () -> Date
    private(set) var session: CloudSession?
    /// Called after logging in, a refreshed login, and logging out: the app keeps it.
    var onSessionChange: ((CloudSession?) -> Void)?

    init(config: CloudConfig, session: CloudSession?, now: @escaping () -> Date = Date.init, transport: @escaping CloudTransport) {
        self.config = config
        self.session = session
        self.now = now
        self.transport = transport
    }

    // MARK: Requests

    private func request(_ path: String, method: String = "GET", body: Data? = nil, token: String?,
                         headers: [String: String] = [:]) -> URLRequest {
        var request = URLRequest(url: URL(string: path, relativeTo: config.baseURL)!)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 30
        request.setValue(config.key, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else if config.key.hasPrefix("eyJ") {
            // The older "anon" keys are JWTs and go in Authorization too; publishable keys do not.
            request.setValue("Bearer \(config.key)", forHTTPHeaderField: "Authorization")
        }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data
        let status: Int
        do {
            (data, status) = try await transport(request)
        } catch {
            throw CloudError(message: "Geen verbinding met de cloud. Heb je internet?", offline: true)
        }
        guard (200..<300).contains(status) else { throw Self.error(status: status, data: data) }
        return data
    }

    /// The cloud's message in Dutch where we know it.
    static func error(status: Int, data: Data) -> CloudError {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let text = (object?["msg"] ?? object?["message"] ?? object?["error_description"] ?? object?["error"]) as? String ?? ""
        let code = (object?["error_code"] ?? object?["code"]) as? String ?? ""
        switch code {
        case "invalid_credentials": return CloudError(message: "E-mailadres of wachtwoord klopt niet.")
        case "email_not_confirmed": return CloudError(message: "Bevestig eerst je e-mailadres: klik op de link in de e-mail van Supabase.")
        case "user_already_exists": return CloudError(message: "Er is al een account met dit e-mailadres. Log in.")
        case "weak_password": return CloudError(message: "Kies een langer wachtwoord (minstens 6 tekens).")
        case "over_email_send_rate_limit": return CloudError(message: "Te veel e-mails verstuurd. Probeer het over een uur opnieuw.")
        default: break
        }
        if status == 401 || code == "PGRST301" || code == "bad_jwt" {
            return CloudError(message: "Je bent uitgelogd. Log opnieuw in.", loggedOut: true)
        }
        return CloudError(message: text.isEmpty ? "De cloud gaf een fout (\(status))." : "De cloud gaf een fout: \(text)")
    }

    private static let decoder: JSONDecoder = JSONReading.decoder

    private static func json(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    // MARK: Logging in

    private struct TokenAnswer: Decodable {
        struct User: Decodable {
            var id: String
            var email: String?
        }

        var access_token: String?
        var refresh_token: String?
        var expires_in: Double?
        var user: User?
    }

    private func keep(_ answer: TokenAnswer, email fallback: String) throws -> CloudSession {
        guard let access = answer.access_token, let refresh = answer.refresh_token, let user = answer.user else {
            throw CloudError(message: "De cloud gaf geen geldige login terug.")
        }
        let session = CloudSession(accessToken: access, refreshToken: refresh,
                                   expiresAt: now().addingTimeInterval(answer.expires_in ?? 3600),
                                   userId: user.id, email: user.email ?? fallback)
        self.session = session
        onSessionChange?(session)
        return session
    }

    func signIn(email: String, password: String) async throws -> CloudSession {
        let body = Self.json(["email": email, "password": password])
        let data = try await send(request("auth/v1/token?grant_type=password", method: "POST", body: body, token: nil))
        return try keep(Self.decoder.decode(TokenAnswer.self, from: data), email: email)
    }

    /// Makes an account. Returns false when Supabase first sends an e-mail to confirm it.
    func signUp(email: String, password: String) async throws -> Bool {
        let body = Self.json(["email": email, "password": password])
        let data = try await send(request("auth/v1/signup", method: "POST", body: body, token: nil))
        let answer = try Self.decoder.decode(TokenAnswer.self, from: data)
        guard answer.access_token != nil else { return false }
        _ = try keep(answer, email: email)
        return true
    }

    func signOut() async {
        if let token = session?.accessToken {
            _ = try? await send(request("auth/v1/logout", method: "POST", token: token))
        }
        session = nil
        onSessionChange?(nil)
    }

    /// A token that is valid for at least another minute, refreshed when needed.
    private func token() async throws -> String {
        guard let session else { throw CloudError(message: "Log eerst in.", loggedOut: true) }
        if session.expiresAt.timeIntervalSince(now()) > 60 { return session.accessToken }
        let body = Self.json(["refresh_token": session.refreshToken])
        do {
            let data = try await send(request("auth/v1/token?grant_type=refresh_token", method: "POST", body: body, token: nil))
            return try keep(Self.decoder.decode(TokenAnswer.self, from: data), email: session.email).accessToken
        } catch let error as CloudError where !error.offline {
            // The refresh token is no longer valid.
            self.session = nil
            onSessionChange?(nil)
            throw CloudError(message: "Je bent uitgelogd. Log opnieuw in.", loggedOut: true)
        }
    }

    private func authorized(_ path: String, method: String = "GET", body: Data? = nil,
                            headers: [String: String] = [:]) async throws -> Data {
        try await send(request(path, method: method, body: body, token: try await token(), headers: headers))
    }

    private func rpc(_ name: String, _ arguments: [String: Any]) async throws -> Data {
        try await authorized("rest/v1/rpc/\(name)", method: "POST", body: Self.json(arguments))
    }

    // MARK: Fields

    /// Saves a field and returns the key of each of its sensors, for the sensor boxes.
    func saveField(_ field: FieldRecord) async throws -> [String: String] {
        let record = try JSONSerialization.jsonObject(with: field.encoded())
        let data = try await rpc("bewaar_veld", ["p_veld_id": field.id, "p_naam": field.name, "p_veld": record])
        struct Key: Decodable {
            var sensor_id: String
            var sleutel: String
        }
        let keys = try Self.decoder.decode([Key].self, from: data)
        return Dictionary(keys.map { ($0.sensor_id, $0.sleutel) }, uniquingKeysWith: { first, _ in first })
    }

    func deleteField(_ fieldId: String) async throws {
        guard let user = session?.userId else { throw CloudError(message: "Log eerst in.", loggedOut: true) }
        let id = fieldId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? fieldId
        _ = try await authorized("rest/v1/velden?eigenaar=eq.\(user)&veld_id=eq.\(id)", method: "DELETE")
    }

    /// Your own fields and the ones shared with you.
    func fields() async throws -> [CloudField] {
        let data = try await authorized("rest/v1/velden?select=id,veld_id,naam,veld,eigenaar&order=naam")
        return try Self.decoder.decode([CloudField].self, from: data)
    }

    func measurements(field cloudId: String, since: Date) async throws -> [CloudMeasurement] {
        let from = ISO8601DateFormatter().string(from: since)
        let data = try await authorized("rest/v1/sensormetingen?veld=eq.\(cloudId)&tijd=gte.\(from)&select=tijd,ruw,batterij_volt,diepte_cm,sensoren(sensor_id)&order=tijd.asc&limit=5000")
        return try Self.decoder.decode([CloudMeasurement].self, from: data)
    }

    func weather(field cloudId: String) async throws -> WeatherForecast? {
        let data = try await authorized("rest/v1/weer?veld=eq.\(cloudId)&select=verwachting")
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let forecast = rows.first?["verwachting"] else { return nil }
        return try WeatherForecast.read(JSONSerialization.data(withJSONObject: forecast))
    }

    func results(field cloudId: String) async throws -> FieldResults? {
        let data = try await authorized("rest/v1/resultaten?veld=eq.\(cloudId)&select=resultaten")
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let results = rows.first?["resultaten"] else { return nil }
        return try FieldResults.read(JSONSerialization.data(withJSONObject: results))
    }

    func saveFlight(field cloudId: String, log: PhotoLog) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let fotolog = try JSONSerialization.jsonObject(with: encoder.encode(log))
        let body = Self.json(["veld": cloudId, "vlucht_id": log.flightId, "fotolog": fotolog])
        _ = try await authorized("rest/v1/vluchten?on_conflict=veld,vlucht_id", method: "POST", body: body,
                                 headers: ["Prefer": "resolution=merge-duplicates,return=minimal"])
    }

    /// A plant that needs attention, from the photo analysis on the Mac.
    struct AttentionMark: Equatable {
        var position: LatLng
        var reason: String
        var photo: String?
        var confidence: Double
    }

    /// Replaces the markers of one flight with these.
    func saveAttention(field cloudId: String, flightId: String, marks: [AttentionMark]) async throws {
        let flight = flightId.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? flightId
        _ = try await authorized("rest/v1/aandacht?veld=eq.\(cloudId)&vlucht_id=eq.\(flight)", method: "DELETE")
        guard !marks.isEmpty else { return }
        let rows: [[String: Any]] = marks.map {
            ["veld": cloudId, "vlucht_id": flightId, "lat": $0.position.lat, "lng": $0.position.lng,
             "reden": $0.reason, "foto": $0.photo ?? NSNull(), "zekerheid": $0.confidence]
        }
        _ = try await authorized("rest/v1/aandacht", method: "POST", body: Self.json(rows), headers: ["Prefer": "return=minimal"])
    }

    /// Asks the central system to work out the weather and advice of this field now.
    func recalculate(field cloudId: String) async throws {
        _ = try await send(request("functions/v1/centraal", method: "POST", body: Self.json(["veld": cloudId]), token: nil))
    }

    // MARK: Sharing

    /// "toegevoegd", "onbekend" (no account with that address) or "jezelf".
    func invite(fieldId: String, email: String) async throws -> String {
        let data = try await rpc("nodig_uit", ["p_veld_id": fieldId, "p_email": email])
        return (try? Self.decoder.decode(String.self, from: data)) ?? String(decoding: data, as: UTF8.self)
    }

    func members(fieldId: String) async throws -> [String] {
        struct Member: Decodable {
            var email: String
        }
        return try await Self.decoder.decode([Member].self, from: rpc("leden", ["p_veld_id": fieldId])).map(\.email)
    }

    func removeMember(fieldId: String, email: String) async throws {
        _ = try await rpc("verwijder_lid", ["p_veld_id": fieldId, "p_email": email])
    }

    // MARK: Sensor boxes

    /// Sends what a box sent to the app on to the cloud, with the key of its sensor.
    /// Works without a login, like the box itself.
    func forward(upload: Data, key: String) async throws {
        guard let object = try? JSONSerialization.jsonObject(with: upload) else { return }
        let body = Self.json(["p_sleutel": key, "p_upload": object])
        _ = try await send(request("rest/v1/rpc/sensor_upload", method: "POST", body: body, token: nil))
    }
}
