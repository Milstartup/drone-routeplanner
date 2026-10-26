// Data for the field map: your own files (from the central system or made by hand) when
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
            return .success(FieldData(results: results, sensors: sensors, weather: weather, ownData: own))
        } catch let error as FileReadError {
            return .failure(error)
        } catch {
            return .failure(FileReadError(message: error.localizedDescription))
        }
    }

    /// Checks a file in one of the field formats and keeps a copy for the field map.
    /// Returns what kind of data it was.
    @discardableResult
    static func importFile(_ url: URL) throws -> String {
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
        try data.write(to: ownFolder.appendingPathComponent(kind.ownName), options: .atomic)
        return kind.label
    }

    /// Back to the sample files.
    static func removeOwnData() {
        for kind in Kind.allCases {
            try? FileManager.default.removeItem(at: ownFolder.appendingPathComponent(kind.ownName))
        }
    }
}

struct FieldData {
    var results: FieldResults
    var sensors: [SensorSummary]
    var weather: WeatherForecast
    /// Which parts come from your own files; empty = all sample data.
    var ownData: [String]
}
