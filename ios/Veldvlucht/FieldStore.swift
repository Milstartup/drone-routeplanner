// The fields drawn in the app. Each field is one file in Documents/Velden, with a folder of
// its own for the data that belongs to it (sensor measurements, weather, results). In the
// Files app: Op mijn iPhone › Veldvlucht › Velden.
// Fields someone shared with you through the cloud are kept in Documents/Gedeeld, under the
// cloud's id ("gedeeld:<id>"); you can look at them but not change or fly them.
import Foundation

/// A field someone else shared with you.
struct SharedField: Identifiable, Equatable {
    var cloudId: String
    var record: FieldRecord

    /// The key in this store, for its data folder and the selection.
    var id: String { FieldStore.sharedPrefix + cloudId }
}

final class FieldStore: ObservableObject {
    /// Figures for the list, worked out once per save instead of on every redraw.
    struct Info {
        var photoCount: Int
        var flightTimeS: Double
        var distanceM: Double
        var hasErrors: Bool
    }

    @Published private(set) var fields: [FieldRecord] = []
    @Published private(set) var shared: [SharedField] = []
    @Published private(set) var info: [String: Info] = [:]
    @Published private(set) var problems: [String] = []
    /// The field the field map shows; nil = the sample field from docs/voorbeelden.
    @Published var selectedId: String? {
        didSet { UserDefaults.standard.set(selectedId, forKey: "veldkaart.veld") }
    }

    static var folder: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appendingPathComponent("Velden", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static let sharedPrefix = "gedeeld:"

    static var sharedFolder: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appendingPathComponent("Gedeeld", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// The data folder of one field: sensormetingen.json, weer.json, resultaten.geojson.
    /// `key` is the field id, or "gedeeld:<cloud id>" for a shared field.
    static func dataFolder(_ key: String) -> URL {
        let folder = key.hasPrefix(sharedPrefix)
            ? sharedFolder.appendingPathComponent(String(key.dropFirst(sharedPrefix.count)), isDirectory: true)
            : Self.folder.appendingPathComponent(key, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static func fileURL(_ id: String) -> URL {
        folder.appendingPathComponent("\(id).veld.json")
    }

    init() {
        selectedId = UserDefaults.standard.string(forKey: "veldkaart.veld")
        reload()
    }

    var selected: FieldRecord? { selectedId.flatMap { field($0) } }

    /// What the field map shows: an own or a shared field, with its key; nil = the sample field.
    var selection: (key: String, record: FieldRecord, shared: Bool)? {
        guard let id = selectedId else { return nil }
        if let own = field(id) { return (id, own, false) }
        if let other = shared.first(where: { $0.id == id }) { return (id, other.record, true) }
        return nil
    }

    func field(_ id: String) -> FieldRecord? { fields.first { $0.id == id } }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        var found: [FieldRecord] = []
        var problems: [String] = []
        for url in urls where url.lastPathComponent.hasSuffix(".veld.json") {
            do {
                found.append(try FieldRecord.read(Data(contentsOf: url)))
            } catch {
                problems.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        fields = found.sorted { $0.updatedAt > $1.updatedAt }
        let sharedURLs = (try? FileManager.default.contentsOfDirectory(at: Self.sharedFolder, includingPropertiesForKeys: nil)) ?? []
        shared = sharedURLs.filter { $0.lastPathComponent.hasSuffix(".veld.json") }.compactMap { url in
            guard let record = try? FieldRecord.read(Data(contentsOf: url)) else { return nil }
            return SharedField(cloudId: String(url.lastPathComponent.dropLast(".veld.json".count)), record: record)
        }.sorted { $0.record.name < $1.record.name }
        self.problems = problems
        info = Dictionary(uniqueKeysWithValues: fields.map { ($0.id, Self.info(for: $0)) })
        if selectedId != nil, selection == nil { selectedId = nil }
    }

    /// The fields shared with you, as the cloud has them now; others are removed.
    func replaceShared(_ list: [SharedField]) {
        let keep = Set(list.map(\.cloudId))
        for old in shared where !keep.contains(old.cloudId) {
            try? FileManager.default.removeItem(at: Self.sharedFolder.appendingPathComponent("\(old.cloudId).veld.json"))
            try? FileManager.default.removeItem(at: Self.sharedFolder.appendingPathComponent(old.cloudId, isDirectory: true))
        }
        for field in list {
            try? field.record.encoded().write(to: Self.sharedFolder.appendingPathComponent("\(field.cloudId).veld.json"), options: .atomic)
        }
        reload()
    }

    private static func info(for field: FieldRecord) -> Info {
        let plan = field.plan()
        return Info(photoCount: plan.photos.count, flightTimeS: plan.estimate.flightTimeS,
                    distanceM: plan.estimate.totalDistanceM, hasErrors: plan.hasErrors)
    }

    func save(_ field: FieldRecord) throws {
        try field.encoded().write(to: Self.fileURL(field.id), options: .atomic)
        reload()
    }

    /// Removes the field and everything that belongs to it.
    func delete(_ id: String) {
        try? FileManager.default.removeItem(at: Self.fileURL(id))
        try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent(id, isDirectory: true))
        reload()
    }

    func newId(for name: String) -> String {
        FieldRecord.makeId(for: name, taken: Set(fields.map(\.id)))
    }

    /// "Mijn veld", "Mijn veld 2", ...
    func newName() -> String {
        let names = Set(fields.map(\.name))
        if !names.contains("Mijn veld") { return "Mijn veld" }
        var n = 2
        while names.contains("Mijn veld \(n)") { n += 1 }
        return "Mijn veld \(n)"
    }

    /// The field a sensor box belongs to, from the sensor id it sends.
    func field(forSensor sensorId: String) -> FieldRecord? {
        fields.first { $0.sensors.contains { $0.id == sensorId } }
    }
}
