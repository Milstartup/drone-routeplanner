// Data for the field map. For a field drawn in the app: its received sensor measurements,
// the weather fetched for it, and the water advice of the central system (WaterAdvisor),
// unless you loaded a results file of your own. For the sample field: your own files when
// you loaded them, otherwise the sample files from docs/voorbeelden, which the app carries
// as the folder "voorbeelden".
import Foundation

enum SampleData {
    static func data(_ fileName: String) -> Data? {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: nil, subdirectory: "voorbeelden") else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    /// Own files, in the Files app under "Op mijn iPhone › Veldvlucht › Veldkaart".
    static var ownFolder: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appendingPathComponent("Veldkaart", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private enum Kind: CaseIterable {
        case results
        case sensors
        case weather

        var ownName: String {
            switch self {
            case .results: return "resultaten.geojson"
            case .sensors: return "sensormetingen.json"
            case .weather: return "weer.json"
            }
        }

        var sampleName: String {
            switch self {
            case .results: return "voorbeeld-resultaten.geojson"
            case .sensors: return "voorbeeld-sensormetingen.json"
            case .weather: return "voorbeeld-weer.json"
            }
        }

        var label: String {
            switch self {
            case .results: return "resultaten"
            case .sensors: return "sensormetingen"
            case .weather: return "weer"
            }
        }
    }

    /// Everything the field map needs, or a message when a file is missing or wrong.
    static func field() -> Result<FieldData, FileReadError> {
        var own: [String] = []
        func read<T>(_ kind: Kind, _ reader: (Data) throws -> T) throws -> T {
            let ownURL = ownFolder.appendingPathComponent(kind.ownName)
            let isOwn = FileManager.default.fileExists(atPath: ownURL.path)
            let name = isOwn ? kind.ownName : kind.sampleName
            let contents: Data? = isOwn ? (try? Data(contentsOf: ownURL)) : SampleData.data(kind.sampleName)
            guard let contents = contents else {
                throw FileReadError(message: "Bestand \(name) ontbreekt.")
            }
            do {
                let value = try reader(contents)
                if isOwn { own.append(kind.label) }
                return value
            } catch {
                throw FileReadError(message: "\(name): \(error.localizedDescription)")
            }
        }
        do {
            let results = try read(.results, FieldResults.read)
            let sensors = FieldSummary.sensors(try read(.sensors, SensorMeasurement.readList))
            let weather = try read(.weather, WeatherForecast.read)
            return .success(FieldData(fieldId: nil, name: results.boundary?.properties.name ?? "Voorbeeldveld",
                                      results: results, sensors: sensors, waitingSensors: [], weather: weather,
                                      ownData: own, adviceSource: .file, shared: false))
        } catch let error as FileReadError {
            return .failure(error)
        } catch {
            return .failure(FileReadError(message: error.localizedDescription))
        }
    }

    /// Where the results of the central system in the cloud are kept for a field.
    static func cloudResultsURL(key: String) -> URL {
        FieldStore.dataFolder(key).appendingPathComponent("resultaten-cloud.geojson")
    }

    /// One field drawn in the app, or shared with you (`key` "gedeeld:<id>").
    static func field(_ record: FieldRecord, key: String? = nil, now: Date = Date()) -> Result<FieldData, FileReadError> {
        let key = key ?? record.id
        let folder = FieldStore.dataFolder(key)
        var own: [String] = []
        // Where each sensor is now, and its calibration now: both may have changed after measuring.
        let placed = Dictionary(record.sensors.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let measurements = SensorStore.read(fieldId: key).map { m -> SensorMeasurement in
            guard let sensor = placed[m.sensorId] else { return m }
            var m = m
            m.location = sensor.location
            m.calibration = sensor.calibration
            m.moisturePercent = sensor.calibration?.percent(raw: m.raw)
            return m
        }
        let weather = try? WeatherForecast.read(Data(contentsOf: folder.appendingPathComponent(Kind.weather.ownName)))
        var results: FieldResults
        let source: FieldData.AdviceSource
        let ownResults = folder.appendingPathComponent(Kind.results.ownName)
        let cloud = try? FieldResults.read(Data(contentsOf: cloudResultsURL(key: key)))
        let newest = measurements.map(\.time).max() ?? .distantPast
        if FileManager.default.fileExists(atPath: ownResults.path) {
            do {
                results = try FieldResults.read(Data(contentsOf: ownResults))
                own.append(Kind.results.label)
                source = .file
            } catch {
                return .failure(FileReadError(message: "\(Kind.results.ownName): \(error.localizedDescription)"))
            }
        } else if let cloud, cloud.properties.createdAt >= newest {
            // The central system in the cloud had every measurement the app has.
            results = cloud
            source = .cloud
        } else {
            results = WaterAdvisor.results(field: record, measurements: measurements, weather: weather, now: now)
            // Newer measurements than the cloud's: the app works it out, with the cloud's markers.
            results.features += cloud?.attention ?? []
            source = .app
        }
        let measured = Set(measurements.map(\.sensorId))
        return .success(FieldData(fieldId: key, name: record.name, results: results,
                                  sensors: FieldSummary.sensors(measurements.filter { placed[$0.sensorId] != nil }),
                                  waitingSensors: record.sensors.filter { !measured.contains($0.id) },
                                  weather: weather, ownData: own, adviceSource: source,
                                  shared: key.hasPrefix(FieldStore.sharedPrefix)))
    }

    /// Checks a file in one of the field formats and keeps a copy for the field map: in the
    /// folder of a field drawn in the app, or for the sample field. Returns what kind it was.
    @discardableResult
    static func importFile(_ url: URL, fieldId: String? = nil) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            throw FileReadError(message: "Dit is geen geldig JSON-bestand.")
        }
        let root = object as? [String: Any]
        let kind: Kind
        if root?["type"] as? String == "FeatureCollection" {
            _ = try FieldResults.read(data)
            kind = .results
        } else if object is [Any] || root?["format"] as? String == SensorMeasurement.format {
            _ = try SensorMeasurement.readList(data)
            kind = .sensors
        } else if root?["format"] as? String == WeatherForecast.format {
            _ = try WeatherForecast.read(data)
            kind = .weather
        } else {
            throw FileReadError(message: "Dit is geen bestand voor de veldkaart (veld/resultaten, veld/sensormeting of veld/weer).")
        }
        if let fieldId {
            if kind == .sensors {
                // Measurements are added to the ones the sensor boxes sent.
                SensorStore.add(try SensorMeasurement.readList(data), fieldId: fieldId)
            } else {
                try data.write(to: FieldStore.dataFolder(fieldId).appendingPathComponent(kind.ownName), options: .atomic)
            }
        } else {
            try data.write(to: ownFolder.appendingPathComponent(kind.ownName), options: .atomic)
        }
        return kind.label
    }

    /// Back to the advice of the central system for a field drawn in the app.
    static func removeOwnResults(fieldId: String) {
        try? FileManager.default.removeItem(at: FieldStore.dataFolder(fieldId).appendingPathComponent(Kind.results.ownName))
    }

    /// Where the weather of a field drawn in the app is kept.
    static func weatherURL(fieldId: String) -> URL {
        FieldStore.dataFolder(fieldId).appendingPathComponent(Kind.weather.ownName)
    }

    /// Back to the sample files.
    static func removeOwnData() {
        for kind in Kind.allCases {
            try? FileManager.default.removeItem(at: ownFolder.appendingPathComponent(kind.ownName))
        }
    }
}

struct FieldData {
    /// The field drawn in the app; nil = the sample field.
    var fieldId: String?
    var name: String
    var results: FieldResults
    var sensors: [SensorSummary]
    /// Placed sensors that have not sent a measurement yet.
    var waitingSensors: [FieldSensor]
    /// nil while it is being fetched, or without internet.
    var weather: WeatherForecast?
    /// Which parts come from your own files.
    var ownData: [String]
    enum AdviceSource {
        /// The central system in the cloud.
        case cloud
        /// The same rules in the app (WaterAdvisor), when the cloud is not used or behind.
        case app
        /// A results file (the sample, or one you loaded).
        case file
    }

    var adviceSource: AdviceSource
    /// Someone shared this field with you: you can look but not change it.
    var shared: Bool
}

/// The sensor measurements of a field drawn in the app: what the sensor boxes sent, in the
/// format veld/sensormeting (Documents/Velden/<field>/sensormetingen.json).
enum SensorStore {
    static func url(fieldId: String) -> URL {
        FieldStore.dataFolder(fieldId).appendingPathComponent("sensormetingen.json")
    }

    static func read(fieldId: String) -> [SensorMeasurement] {
        guard let data = try? Data(contentsOf: url(fieldId: fieldId)) else { return [] }
        return (try? SensorMeasurement.readList(data)) ?? []
    }

    static func write(_ list: [SensorMeasurement], fieldId: String) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(list) {
            try? data.write(to: url(fieldId: fieldId), options: .atomic)
        }
    }

    /// Adds measurements without doubles; returns how many were new.
    @discardableResult
    static func add(_ new: [SensorMeasurement], fieldId: String, checkDoubles: Bool = true) -> Int {
        let merged = SensorHistory.merge(read(fieldId: fieldId), new, checkDoubles: checkDoubles)
        write(merged.all, fieldId: fieldId)
        return merged.added
    }

    private static func marksURL(fieldId: String) -> URL {
        FieldStore.dataFolder(fieldId).appendingPathComponent("ontvangst.json")
    }

    /// Per sensor: the last numbered measurement received (SensorUpload.unseen).
    static func marks(fieldId: String) -> [String: UploadMark] {
        guard let data = try? Data(contentsOf: marksURL(fieldId: fieldId)) else { return [:] }
        return (try? JSONDecoder().decode([String: UploadMark].self, from: data)) ?? [:]
    }

    static func saveMark(_ mark: UploadMark, sensorId: String, fieldId: String) {
        var marks = marks(fieldId: fieldId)
        marks[sensorId] = mark
        if let data = try? JSONEncoder().encode(marks) {
            try? data.write(to: marksURL(fieldId: fieldId), options: .atomic)
        }
    }
}
