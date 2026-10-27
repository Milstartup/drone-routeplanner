// The app's link with the central system in the cloud (centraal/README.md): your login, and
// keeping fields, sensor measurements, weather, advice and flights the same on the iPhone and
// in the cloud. Without a cloud project in Config/Lokaal.xcconfig the app works on its own.
import Foundation
import Security

@MainActor
final class CloudStore: ObservableObject {
    enum State: Equatable {
        /// No project in Config/Lokaal.xcconfig.
        case notConfigured
        case loggedOut
        case loggedIn(email: String)
    }

    /// What this iPhone knows of a field of its own in the cloud: the cloud's id and the keys
    /// of the sensor boxes (Documents/Velden/<field>/cloud.json).
    struct FieldLink: Codable, Equatable {
        var cloudId: String?
        var keys: [String: String] = [:]
        /// The field as it was last saved in the cloud.
        var savedVersion: Date?
    }

    @Published private(set) var state = State.notConfigured
    @Published private(set) var syncing = false
    @Published private(set) var lastSync: Date?
    @Published private(set) var problem: String?
    /// Changes after every sync, so the screens reload.
    @Published private(set) var updates = 0

    let config: CloudConfig?
    private let api: CloudAPI?
    private let fields: FieldStore
    private static let uploadedFlightsKey = "cloud.geuploadeVluchten"

    init(fields: FieldStore) {
        self.fields = fields
        let info = Bundle.main.infoDictionary ?? [:]
        let config = CloudConfig(projectRef: (info["VeldvluchtCloudProject"] as? String ?? "").trimmingCharacters(in: .whitespaces),
                                 key: (info["VeldvluchtCloudKey"] as? String ?? "").trimmingCharacters(in: .whitespaces))
        guard config.isUsable else {
            self.config = nil
            api = nil
            return
        }
        self.config = config
        let session = Keychain.read()
        let api = CloudAPI(config: config, session: session) { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        self.api = api
        state = session.map { .loggedIn(email: $0.email) } ?? .loggedOut
        api.onSessionChange = { [weak self] session in
            Keychain.save(session)
            Task { @MainActor in self?.state = session.map { .loggedIn(email: $0.email) } ?? .loggedOut }
        }
    }

    var isLoggedIn: Bool {
        if case .loggedIn = state { return true }
        return false
    }

    // MARK: Logging in

    func signIn(email: String, password: String) async throws {
        guard let api else { return }
        _ = try await api.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
        await sync()
    }

    /// Returns false when Supabase first sends an e-mail to confirm the account.
    func signUp(email: String, password: String) async throws -> Bool {
        guard let api else { return false }
        let loggedIn = try await api.signUp(email: email.trimmingCharacters(in: .whitespaces), password: password)
        if loggedIn { await sync() }
        return loggedIn
    }

    func signOut() async {
        await api?.signOut()
        fields.replaceShared([])
        problem = nil
        updates += 1
    }

    // MARK: Links per field

    private static func linkURL(_ fieldId: String) -> URL {
        FieldStore.dataFolder(fieldId).appendingPathComponent("cloud.json")
    }

    func link(_ fieldId: String) -> FieldLink {
        guard let data = try? Data(contentsOf: Self.linkURL(fieldId)) else { return FieldLink() }
        return (try? JSONDecoder().decode(FieldLink.self, from: data)) ?? FieldLink()
    }

    private func save(_ link: FieldLink, for fieldId: String) {
        if let data = try? JSONEncoder().encode(link) {
            try? data.write(to: Self.linkURL(fieldId), options: .atomic)
        }
    }

    // MARK: Keeping things the same

    /// Saves one field in the cloud now (after drawing it or placing sensors) and gets the
    /// keys of its sensors.
    func save(_ field: FieldRecord) async {
        guard let api, isLoggedIn else { return }
        do {
            var link = link(field.id)
            link.keys = try await api.saveField(field)
            link.savedVersion = field.updatedAt
            if link.cloudId == nil {
                link.cloudId = try await api.fields().first { $0.veldId == field.id && $0.eigenaar == api.session?.userId }?.id
            }
            save(link, for: field.id)
            problem = nil
            updates += 1
        } catch {
            note(error)
        }
    }

    func delete(_ fieldId: String) async {
        guard let api, isLoggedIn else { return }
        do {
            try await api.deleteField(fieldId)
        } catch {
            note(error)
        }
    }

    /// Everything both ways: own fields up, shared fields, measurements, weather, advice down,
    /// and flights up. Runs when the app opens and when you ask for it.
    func sync() async {
        guard let api, isLoggedIn, !syncing else { return }
        syncing = true
        defer { syncing = false }
        do {
            // Own fields that changed since they were last saved in the cloud.
            for field in fields.fields where link(field.id).savedVersion != field.updatedAt || link(field.id).cloudId == nil {
                var link = link(field.id)
                link.keys = try await api.saveField(field)
                link.savedVersion = field.updatedAt
                save(link, for: field.id)
            }

            let me = api.session?.userId
            let inCloud = try await api.fields()
            var shared: [SharedField] = []
            var pairs: [(key: String, cloudId: String, record: FieldRecord)] = []
            for cloudField in inCloud {
                if cloudField.eigenaar == me {
                    guard let local = fields.field(cloudField.veldId) else { continue }
                    var link = link(local.id)
                    if link.cloudId != cloudField.id {
                        link.cloudId = cloudField.id
                        save(link, for: local.id)
                    }
                    pairs.append((local.id, cloudField.id, local))
                } else {
                    let field = SharedField(cloudId: cloudField.id, record: cloudField.veld)
                    shared.append(field)
                    pairs.append((field.id, cloudField.id, field.record))
                }
            }
            fields.replaceShared(shared)

            for pair in pairs {
                try await pull(pair.cloudId, into: pair.key, record: pair.record)
            }
            try await uploadFlights(pairs.filter { !$0.key.hasPrefix(FieldStore.sharedPrefix) })
            lastSync = Date()
            problem = nil
        } catch {
            note(error)
        }
        updates += 1
    }

    /// Measurements of the last two weeks, the weather and the advice of one field.
    private func pull(_ cloudId: String, into key: String, record: FieldRecord) async throws {
        guard let api else { return }
        let since = Date().addingTimeInterval(-14 * 86400)
        let measurements = try await api.measurements(field: cloudId, since: since).map { $0.measurement(field: record) }
        SensorStore.add(measurements, fieldId: key)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        if let weather = try await api.weather(field: cloudId) {
            let url = SampleData.weatherURL(fieldId: key)
            let kept = try? WeatherForecast.read(Data(contentsOf: url))
            if kept.map({ $0.createdAt < weather.createdAt }) ?? true {
                try encoder.encode(weather).write(to: url, options: .atomic)
            }
        }
        if let results = try await api.results(field: cloudId) {
            try encoder.encode(results).write(to: SampleData.cloudResultsURL(key: key), options: .atomic)
        }
    }

    /// The photo logs of flights over your own fields that are not in the cloud yet.
    private func uploadFlights(_ own: [(key: String, cloudId: String, record: FieldRecord)]) async throws {
        guard let api else { return }
        var uploaded = Set(UserDefaults.standard.stringArray(forKey: Self.uploadedFlightsKey) ?? [])
        let byField = Dictionary(own.map { ($0.key, $0.cloudId) }, uniquingKeysWith: { first, _ in first })
        let urls = (try? FileManager.default.contentsOfDirectory(at: FlightRecorder.folder, includingPropertiesForKeys: nil)) ?? []
        for url in urls where url.lastPathComponent.hasSuffix(".fotolog.json") {
            guard let log = try? PhotoLog.read(Data(contentsOf: url)), !uploaded.contains(log.flightId),
                  let cloudId = byField[log.fieldId], !log.photos.isEmpty else { continue }
            try await api.saveFlight(field: cloudId, log: log)
            uploaded.insert(log.flightId)
            UserDefaults.standard.set(Array(uploaded), forKey: Self.uploadedFlightsKey)
        }
    }

    /// Asks the central system to work out the advice of one field now, then fetches it.
    func recalculate(_ fieldId: String) async {
        guard let api, isLoggedIn, let cloudId = link(fieldId).cloudId else { return }
        do {
            try await api.recalculate(field: cloudId)
            if let field = fields.field(fieldId) {
                try await pull(cloudId, into: fieldId, record: field)
            }
            updates += 1
        } catch {
            note(error)
        }
    }

    // MARK: Sharing

    func invite(_ email: String, to fieldId: String) async throws -> String {
        guard let api else { throw CloudError(message: "De cloud is nog niet ingesteld.") }
        await save(fields.field(fieldId) ?? FieldRecord(id: fieldId, name: fieldId, boundary: [], home: nil, settings: .planner,
                                                        createdAt: Date(), updatedAt: Date()))
        switch try await api.invite(fieldId: fieldId, email: email.trimmingCharacters(in: .whitespaces)) {
        case "toegevoegd": return "Gedeeld met \(email). Die ziet het veld na het synchroniseren."
        case "jezelf": return "Dat is je eigen e-mailadres."
        default: return "Er is nog geen account met \(email). Vraag diegene eerst een account te maken in Veldvlucht (Account → Account maken)."
        }
    }

    func members(of fieldId: String) async throws -> [String] {
        guard let api else { return [] }
        return try await api.members(fieldId: fieldId)
    }

    func remove(_ email: String, from fieldId: String) async throws {
        try await api?.removeMember(fieldId: fieldId, email: email)
    }

    // MARK: Sensor boxes

    /// A box sent its measurements to the app: send them on to the cloud as well.
    func forward(upload: Data, sensorId: String, fieldId: String) async {
        guard let api, let key = link(fieldId).keys[sensorId] else { return }
        do {
            try await api.forward(upload: upload, key: key)
        } catch {
            note(error)
        }
    }

    private func note(_ error: Error) {
        problem = error.localizedDescription
    }
}

/// The login, in the iPhone's Keychain (not in a file).
enum Keychain {
    private static let service = "nl.milanmehrzad.veldvlucht.cloud"

    static func read() -> CloudSession? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CloudSession.self, from: data)
    }

    static func save(_ session: CloudSession?) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        SecItemDelete(query as CFDictionary)
        guard let session else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(session) else { return }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}
