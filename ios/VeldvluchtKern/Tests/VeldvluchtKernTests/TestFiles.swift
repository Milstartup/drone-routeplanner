// The sample files in docs/voorbeelden, shared with the app and the documentation.
import Foundation

enum TestFiles {
    static let examples: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // VeldvluchtKernTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // VeldvluchtKern
        .deletingLastPathComponent() // ios
        .deletingLastPathComponent() // repository
        .appendingPathComponent("docs/voorbeelden")

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: examples.appendingPathComponent(name))
    }

    /// Edits a JSON object and returns it as data, for files with one thing wrong.
    static func modified(_ name: String, _ change: (inout [String: Any]) -> Void) throws -> Data {
        var root = try JSONSerialization.jsonObject(with: data(name)) as! [String: Any]
        change(&root)
        return try JSONSerialization.data(withJSONObject: root)
    }

    /// The example from docs/ROUTEBESTAND.md, unchanged.
    static let routeFileExample = """
    {
      "format": "drone-routeplanner/plan",
      "version": 1,
      "notice": "Planningsbestand van de drone-routeplanner (prototype).",
      "createdAt": "2026-10-25T12:00:00.000Z",
      "coordinateSystem": "WGS84 (EPSG:4326), decimale graden",
      "altitudeReference": "meter boven het startpunt",
      "name": "Proefstrook",
      "mode": "route",
      "settings": {
        "altitudeM": 30,
        "speedMps": 4,
        "lineSpacingM": 20,
        "photoIntervalS": 3,
        "lineAngleDeg": null,
        "edgeMarginM": 5
      },
      "assumptions": {
        "ascentSpeedMps": 2,
        "descentSpeedMps": 1.5,
        "waypointPauseS": 3,
        "usableFlightTimeS": 1200,
        "maxDistanceFromHomeM": 500
      },
      "home": null,
      "boundary": [],
      "routePoints": [
        { "lat": 52.5, "lng": 5.5, "capture": true },
        { "lat": 52.5, "lng": 5.5007, "capture": false },
        { "lat": 52.5004, "lng": 5.5007, "capture": true }
      ],
      "derived": {
        "waypoints": [
          { "index": 0, "lat": 52.5, "lng": 5.5, "altitudeM": 30 },
          { "index": 1, "lat": 52.5, "lng": 5.5007, "altitudeM": 30 },
          { "index": 2, "lat": 52.5004, "lng": 5.5007, "altitudeM": 30 }
        ],
        "legs": [
          { "from": 0, "to": 1, "capture": true },
          { "from": 1, "to": 2, "capture": false }
        ],
        "photoPoints": [
          { "index": 0, "lat": 52.5, "lng": 5.5, "legIndex": 0 },
          { "index": 1, "lat": 52.5, "lng": 5.5001773, "legIndex": 0 },
          { "index": 2, "lat": 52.5, "lng": 5.5003546, "legIndex": 0 },
          { "index": 3, "lat": 52.5, "lng": 5.5005318, "legIndex": 0 }
        ],
        "estimate": {
          "totalDistanceM": 91.86,
          "flightTimeS": 25.97,
          "photoCount": 4,
          "photoSpacingM": 12,
          "fieldAreaM2": null
        }
      }
    }
    """
}
