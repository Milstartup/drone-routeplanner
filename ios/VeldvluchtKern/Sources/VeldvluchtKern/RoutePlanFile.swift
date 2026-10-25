// The planner's route file (.routeplan.json, docs/ROUTEBESTAND.md) as the app reads it.
// The app flies the `derived` block (waypoints, legs, photo points), so it must be present;
// RouteCheck then checks it against the inputs and the rules.
import Foundation

struct RoutePlanFile: Codable, Equatable {
    static let format = "drone-routeplanner/plan"
    static let version = 1

    enum Mode: String, Codable {
        case route
        case field
    }

    struct Settings: Codable, Equatable {
        var altitudeM: Double
        var speedMps: Double
        var lineSpacingM: Double
        var photoIntervalS: Double
        var lineAngleDeg: Double?
        var edgeMarginM: Double
    }

    struct Assumptions: Codable, Equatable {
        var ascentSpeedMps: Double
        var descentSpeedMps: Double
        var waypointPauseS: Double
        var usableFlightTimeS: Double
        var maxDistanceFromHomeM: Double

        /// The planner's defaults (src/core/defaults.ts), used when a file has no assumptions.
        static let planner = Assumptions(
            ascentSpeedMps: 2,
            descentSpeedMps: 1.5,
            waypointPauseS: 3,
            usableFlightTimeS: 20 * 60,
            maxDistanceFromHomeM: 500
        )
    }

    struct RoutePoint: Codable, Equatable {
        var lat: Double
        var lng: Double
        /// Take photos on the leg from this point to the next one (the planner's default is true).
        var capture: Bool

        var latLng: LatLng { LatLng(lat: lat, lng: lng) }

        init(lat: Double, lng: Double, capture: Bool) {
            self.lat = lat
            self.lng = lng
            self.capture = capture
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            lat = try container.decode(Double.self, forKey: .lat)
            lng = try container.decode(Double.self, forKey: .lng)
            capture = try container.decodeIfPresent(Bool.self, forKey: .capture) ?? true
        }
    }

    struct Waypoint: Codable, Equatable {
        var index: Int
        var lat: Double
        var lng: Double
        var altitudeM: Double

        var latLng: LatLng { LatLng(lat: lat, lng: lng) }
    }

    struct Leg: Codable, Equatable {
        var from: Int
        var to: Int
        var capture: Bool
    }

    struct PhotoPoint: Codable, Equatable {
        var index: Int
        var lat: Double
        var lng: Double
        var legIndex: Int

        var latLng: LatLng { LatLng(lat: lat, lng: lng) }
    }

    struct Estimate: Codable, Equatable {
        var totalDistanceM: Double
        var flightTimeS: Double
        var photoCount: Int
        var photoSpacingM: Double
        var fieldAreaM2: Double?
    }

    struct Derived: Codable, Equatable {
        var waypoints: [Waypoint]
        var legs: [Leg]
        var photoPoints: [PhotoPoint]
        var estimate: Estimate
    }

    var format: String
    var version: Int
    var notice: String?
    var createdAt: String?
    var name: String
    var mode: Mode
    var settings: Settings
    var assumptions: Assumptions
    var home: LatLng?
    var boundary: [LatLng]
    var routePoints: [RoutePoint]
    var derived: Derived

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(String.self, forKey: .format)
        version = try container.decode(Int.self, forKey: .version)
        notice = try container.decodeIfPresent(String.self, forKey: .notice)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        let rawName = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        name = rawName.trimmingCharacters(in: .whitespaces).isEmpty ? "Geladen route" : rawName
        mode = try container.decode(Mode.self, forKey: .mode)
        settings = try container.decode(Settings.self, forKey: .settings)
        assumptions = try container.decodeIfPresent(Assumptions.self, forKey: .assumptions) ?? .planner
        home = try container.decodeIfPresent(LatLng.self, forKey: .home)
        boundary = try container.decodeIfPresent([LatLng].self, forKey: .boundary) ?? []
        routePoints = try container.decodeIfPresent([RoutePoint].self, forKey: .routePoints) ?? []
        derived = try container.decode(Derived.self, forKey: .derived)
    }

    /// Reads a route file. Refuses other formats and versions and invalid coordinates
    /// (rule 1 of docs/ROUTEBESTAND.md). Everything else is up to RouteCheck.
    static func read(_ data: Data) throws -> RoutePlanFile {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            throw FileReadError(message: "Dit is geen geldig JSON-bestand.")
        }
        guard let root = object as? [String: Any] else {
            throw FileReadError(message: "Dit is geen routebestand: het bestand bevat geen JSON-object.")
        }
        try JSONReading.checkHeader(root, format: format, version: version, what: "routebestand van de planner")
        if let mode = root["mode"] as? String, Mode(rawValue: mode) == nil {
            throw FileReadError(message: "Veld \"mode\" moet \"route\" of \"field\" zijn.")
        }
        guard root["derived"] != nil else {
            throw FileReadError(message: "Het blok \"derived\" ontbreekt. Sla de route opnieuw op in de planner.")
        }

        let file = try JSONReading.decode(RoutePlanFile.self, from: data)
        if let home = file.home, !home.isValid {
            throw FileReadError(message: "Het startpunt (\"home\") heeft geen geldige GPS-coördinaten.")
        }
        try checkPoints(file.boundary, "boundary")
        try checkPoints(file.routePoints.map(\.latLng), "routePoints")
        try checkPoints(file.derived.waypoints.map(\.latLng), "derived.waypoints")
        try checkPoints(file.derived.photoPoints.map(\.latLng), "derived.photoPoints")
        return file
    }

    private static func checkPoints(_ points: [LatLng], _ path: String) throws {
        if let i = points.firstIndex(where: { !$0.isValid }) {
            throw FileReadError(message: "Punt \(i + 1) in \"\(path)\" heeft geen geldige GPS-coördinaten (lat −90..90, lng −180..180).")
        }
    }
}
