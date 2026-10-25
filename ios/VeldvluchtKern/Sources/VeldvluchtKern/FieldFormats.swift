// The field data formats, version 0, from docs/ARCHITECTUUR.md chapter 6:
// sensor measurements, the photo log, the results for the field map and the weather.
// Examples of each are in docs/voorbeelden/.
import Foundation

// MARK: - Sensor measurement (veld/sensormeting)

struct SensorMeasurement: Codable, Equatable, Identifiable {
    static let format = "veld/sensormeting"
    static let version = 0

    struct Calibration: Codable, Equatable {
        /// Raw value in dry soil from the field.
        var dryRaw: Double
        /// Raw value in saturated soil from the field.
        var wetRaw: Double
    }

    var format: String
    var version: Int
    var sensorId: String
    var fieldId: String
    var location: LatLng
    var depthCm: Double
    var time: Date
    var raw: Double
    /// Empty until the sensor is calibrated.
    var moisturePercent: Double?
    var calibration: Calibration?
    var batteryVolt: Double?

    var id: String { "\(sensorId)@\(time.timeIntervalSince1970)" }

    /// Reads one measurement or a list of measurements.
    static func readList(_ data: Data) throws -> [SensorMeasurement] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            throw FileReadError(message: "Dit is geen geldig JSON-bestand.")
        }
        let roots: [[String: Any]]
        if let list = object as? [[String: Any]] {
            roots = list
        } else if let single = object as? [String: Any] {
            roots = [single]
        } else {
            throw FileReadError(message: "Dit is geen bestand met sensormetingen.")
        }
        for root in roots {
            try JSONReading.checkHeader(root, format: format, version: version, what: "sensormeting")
        }
        if object is [Any] {
            return try JSONReading.decode([SensorMeasurement].self, from: data)
        }
        return [try JSONReading.decode(SensorMeasurement.self, from: data)]
    }
}

// MARK: - Photo log per flight (veld/fotolog)

struct PhotoLog: Codable, Equatable {
    static let format = "veld/fotolog"
    static let version = 0

    struct Photo: Codable, Equatable {
        var index: Int
        /// Index in `derived.photoPoints` of the route file.
        var plannedPhotoIndex: Int?
        /// File name on the drone's microSD card.
        var file: String
        var time: Date
        var lat: Double
        var lng: Double
        var altitudeM: Double
        var headingDeg: Double
    }

    var format: String
    var version: Int
    var flightId: String
    var fieldId: String
    var routePlanName: String
    var photos: [Photo]

    static func read(_ data: Data) throws -> PhotoLog {
        try JSONReading.checkHeader(data, format: format, version: version, what: "fotolog")
        return try JSONReading.decode(PhotoLog.self, from: data)
    }
}

// MARK: - Results for the field map (veld/resultaten, GeoJSON)

enum WaterAdvice: String, Codable, CaseIterable {
    case genoeg
    case binnenkort
    case water

    var label: String {
        switch self {
        case .genoeg: return "Genoeg water"
        case .binnenkort: return "Binnenkort water geven"
        case .water: return "Nu water geven"
        }
    }
}

/// GeoJSON geometry. GeoJSON puts the longitude first: [lng, lat].
enum Geometry: Codable, Equatable {
    case point(LatLng)
    case lineString([LatLng])
    /// Outer ring first, then holes. Rings repeat their first point at the end.
    case polygon([[LatLng]])

    private enum CodingKeys: String, CodingKey {
        case type
        case coordinates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "Point":
            self = .point(try Self.point(container.decode([Double].self, forKey: .coordinates), container))
        case "LineString":
            self = .lineString(try container.decode([[Double]].self, forKey: .coordinates).map { try Self.point($0, container) })
        case "Polygon":
            let rings = try container.decode([[[Double]]].self, forKey: .coordinates)
            self = .polygon(try rings.map { try $0.map { try Self.point($0, container) } })
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "geometrie \"\(type)\" wordt niet ondersteund (alleen Point, LineString en Polygon).")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .point(let p):
            try container.encode("Point", forKey: .type)
            try container.encode([p.lng, p.lat], forKey: .coordinates)
        case .lineString(let points):
            try container.encode("LineString", forKey: .type)
            try container.encode(points.map { [$0.lng, $0.lat] }, forKey: .coordinates)
        case .polygon(let rings):
            try container.encode("Polygon", forKey: .type)
            try container.encode(rings.map { $0.map { [$0.lng, $0.lat] } }, forKey: .coordinates)
        }
    }

    private static func point(_ values: [Double], _ container: KeyedDecodingContainer<CodingKeys>) throws -> LatLng {
        guard values.count >= 2 else {
            throw DecodingError.dataCorruptedError(forKey: .coordinates, in: container, debugDescription: "een punt heeft [lengtegraad, breedtegraad] nodig.")
        }
        let p = LatLng(lat: values[1], lng: values[0])
        guard p.isValid else {
            throw DecodingError.dataCorruptedError(forKey: .coordinates, in: container, debugDescription: "ongeldige coördinaat [\(values[0]), \(values[1])]. Let op: GeoJSON zet de lengtegraad eerst.")
        }
        return p
    }

    /// Outer ring without the repeated closing point.
    var outerRing: [LatLng] {
        guard case .polygon(let rings) = self, var ring = rings.first else { return [] }
        if ring.count > 1, ring.first == ring.last { ring.removeLast() }
        return ring
    }

    var allPoints: [LatLng] {
        switch self {
        case .point(let p): return [p]
        case .lineString(let points): return points
        case .polygon(let rings): return rings.flatMap { $0 }
        }
    }
}

struct FieldResults: Codable, Equatable {
    static let format = "veld/resultaten"
    static let version = 0

    struct Header: Codable, Equatable {
        var format: String
        var version: Int
        var fieldId: String
        var createdAt: Date
    }

    enum Kind: String, Codable {
        /// The field boundary.
        case veldgrens
        /// A strip or zone with water advice.
        case waterzone
        /// A plant or spot that needs attention.
        case aandacht
    }

    struct Properties: Codable, Equatable {
        var kind: Kind
        var name: String?
        var advice: WaterAdvice?
        var amountMm: Double?
        /// What the advice or marking is based on; the app always shows it.
        var reason: String?
        /// 0...1
        var confidence: Double?
        var photoFile: String?
        var flightId: String?
    }

    struct Feature: Codable, Equatable {
        var type: String
        var geometry: Geometry
        var properties: Properties
    }

    var type: String
    var properties: Header
    var features: [Feature]

    var boundary: Feature? { features.first { $0.properties.kind == .veldgrens } }
    var waterZones: [Feature] { features.filter { $0.properties.kind == .waterzone } }
    var attention: [Feature] { features.filter { $0.properties.kind == .aandacht } }

    static func read(_ data: Data) throws -> FieldResults {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            throw FileReadError(message: "Dit is geen geldig JSON-bestand.")
        }
        guard let root = object as? [String: Any], root["type"] as? String == "FeatureCollection" else {
            throw FileReadError(message: "Dit is geen GeoJSON-bestand met resultaten (verwacht \"type\": \"FeatureCollection\").")
        }
        guard let header = root["properties"] as? [String: Any] else {
            throw FileReadError(message: "Dit is geen resultatenbestand: \"properties\" met \"format\" en \"version\" ontbreekt.")
        }
        try JSONReading.checkHeader(header, format: format, version: version, what: "resultatenbestand")
        return try JSONReading.decode(FieldResults.self, from: data)
    }
}

// MARK: - Weather forecast (veld/weer)

struct WeatherForecast: Codable, Equatable {
    static let format = "veld/weer"
    static let version = 0

    struct Day: Codable, Equatable, Identifiable {
        /// Local date, "2026-10-26".
        var date: String
        var precipitationMm: Double
        var tempMinC: Double
        var tempMaxC: Double
        var windMaxMps: Double
        var gustMaxMps: Double
        var evaporationMm: Double?

        var id: String { date }
    }

    /// A good moment to fly: little wind, dry and daylight.
    struct FlightWindow: Codable, Equatable, Identifiable {
        var start: Date
        var end: Date
        var reason: String

        var id: Date { start }
    }

    var format: String
    var version: Int
    var fieldId: String
    var location: LatLng?
    var source: String
    /// Required credit for the weather service, shown with the forecast.
    var attribution: String
    var createdAt: Date
    var days: [Day]
    var flightWindows: [FlightWindow]?

    static func read(_ data: Data) throws -> WeatherForecast {
        try JSONReading.checkHeader(data, format: format, version: version, what: "weerbestand")
        return try JSONReading.decode(WeatherForecast.self, from: data)
    }
}
