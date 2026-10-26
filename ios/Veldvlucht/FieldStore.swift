// The fields drawn in the app. Each field is one file in Documents/Velden, with a folder of
// its own for the data that belongs to it (sensor measurements, weather, results). In the
// Files app: Op mijn iPhone › Veldvlucht › Velden.
import Foundation

final class FieldStore: ObservableObject {
    /// Figures for the list, worked out once per save instead of on every redraw.
    struct Info {
        var photoCount: Int
        var flightTimeS: Double
        var distanceM: Double
        var hasErrors: Bool
    }

    @Published private(set) var fields: [FieldRecord] = []
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

    /// The data folder of one field: sensormetingen.json, weer.json, resultaten.geojson.
    static func dataFolder(_ fieldId: String) -> URL {
        let folder = Self.folder.appendingPathComponent(fieldId, isDirectory: true)
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
        self.problems = problems
        info = Dictionary(uniqueKeysWithValues: fields.map { ($0.id, Self.info(for: $0)) })
        if let id = selectedId, field(id) == nil { selectedId = nil }
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
