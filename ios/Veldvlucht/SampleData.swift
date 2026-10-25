// The sample files from docs/voorbeelden, copied into the app as the folder "voorbeelden".
// The field map uses them until the central system exists.
import Foundation

enum SampleData {
    static func data(_ fileName: String) -> Data? {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: nil, subdirectory: "voorbeelden") else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    /// Everything the field map needs, or a message when a file is missing or wrong.
    static func field() -> Result<FieldData, FileReadError> {
        func read<T>(_ fileName: String, _ reader: (Data) throws -> T) throws -> T {
            guard let data = data(fileName) else {
                throw FileReadError(message: "Voorbeeldbestand \(fileName) ontbreekt in de app.")
            }
            do {
                return try reader(data)
            } catch {
                throw FileReadError(message: "\(fileName): \(error.localizedDescription)")
            }
        }
        do {
            return .success(FieldData(
                results: try read("voorbeeld-resultaten.geojson", FieldResults.read),
                sensors: FieldSummary.sensors(try read("voorbeeld-sensormetingen.json", SensorMeasurement.readList)),
                weather: try read("voorbeeld-weer.json", WeatherForecast.read)
            ))
        } catch let error as FileReadError {
            return .failure(error)
        } catch {
            return .failure(FileReadError(message: error.localizedDescription))
        }
    }
}

struct FieldData {
    var results: FieldResults
    var sensors: [SensorSummary]
    var weather: WeatherForecast
}
