@testable import VeldvluchtKern
import XCTest

final class FieldFormatsTests: XCTestCase {
    func testReadsSensorMeasurements() throws {
        let measurements = try SensorMeasurement.readList(TestFiles.data("voorbeeld-sensormetingen.json"))
        XCTAssertEqual(measurements.count, 12)

        let sensors = FieldSummary.sensors(measurements)
        XCTAssertEqual(sensors.map(\.shortName), ["s1", "s2", "s3"])
        XCTAssertEqual(sensors[2].latest.raw, 761)
        XCTAssertEqual(sensors[2].history.map(\.raw), [702, 721, 744, 761])
        XCTAssertEqual(sensors[0].valueText, "ruw 478")
        XCTAssertEqual(sensors[1].valueText, "49 % vocht")
        XCTAssertEqual(sensors[1].latest.calibration, .init(dryRaw: 860, wetRaw: 340))
    }

    func testReadsASingleSensorMeasurement() throws {
        let one = """
        {"format":"veld/sensormeting","version":0,"sensorId":"veld-noord-s1","fieldId":"veld-noord",
         "location":{"lat":52.4991,"lng":5.5431},"depthCm":15,"time":"2026-10-25T06:00:00+01:00",
         "raw":612,"moisturePercent":null,"calibration":null,"batteryVolt":3.9}
        """
        let measurements = try SensorMeasurement.readList(Data(one.utf8))
        XCTAssertEqual(measurements.count, 1)
        XCTAssertEqual(measurements[0].time, JSONReading.parseDate("2026-10-25T05:00:00Z"))
    }

    func testRefusesAMeasurementWithAnotherFormat() {
        let wrong = #"[{"format":"veld/fotolog","version":0}]"#
        XCTAssertThrowsError(try SensorMeasurement.readList(Data(wrong.utf8))) {
            XCTAssertTrue($0.localizedDescription.contains("veld/sensormeting"))
        }
    }

    func testReadsThePhotoLog() throws {
        let log = try PhotoLog.read(TestFiles.data("voorbeeld-fotolog.json"))
        XCTAssertEqual(log.flightId, "2026-10-25-veld-noord-1")
        XCTAssertEqual(log.photos.map(\.file).first, "DJI_0001.JPG")
        XCTAssertEqual(log.photos.map(\.plannedPhotoIndex), [0, 1, 2, 3, 4])
    }

    func testPhotoLogMatchesTheSampleRoute() throws {
        let log = try PhotoLog.read(TestFiles.data("voorbeeld-fotolog.json"))
        let route = try RoutePlanFile.read(TestFiles.data("voorbeeld.routeplan.json"))
        XCTAssertEqual(log.routePlanName, route.name)
        for photo in log.photos {
            let planned = route.derived.photoPoints[photo.plannedPhotoIndex!]
            XCTAssertLessThan(Geo.distanceM(planned.latLng, LatLng(lat: photo.lat, lng: photo.lng)), 1.5)
        }
    }

    func testReadsTheResults() throws {
        let results = try FieldResults.read(TestFiles.data("voorbeeld-resultaten.geojson"))
        XCTAssertEqual(results.properties.fieldId, "veld-noord")
        XCTAssertEqual(results.boundary?.geometry.outerRing.count, 4)
        XCTAssertEqual(results.waterZones.compactMap(\.properties.advice), [.genoeg, .genoeg, .binnenkort, .binnenkort, .water])
        XCTAssertEqual(results.attention.count, 3)
        XCTAssertTrue(results.features.allSatisfy { $0.properties.kind == .veldgrens || $0.properties.reason != nil })

        // GeoJSON is [lng, lat]: the first marker lies in the field, not in the sea off Somalia.
        guard case .point(let p) = results.attention[0].geometry else { return XCTFail("geen punt") }
        XCTAssertEqual(p.lat, 52.4991996, accuracy: 1e-7)
        XCTAssertEqual(p.lng, 5.5413693, accuracy: 1e-7)
    }

    func testResultsZonesFillTheField() throws {
        let results = try FieldResults.read(TestFiles.data("voorbeeld-resultaten.geojson"))
        let field = Geo.polygonAreaM2(results.boundary!.geometry.outerRing)
        let zones = results.waterZones.map { Geo.polygonAreaM2($0.geometry.outerRing) }.reduce(0, +)
        XCTAssertEqual(zones, field, accuracy: field * 0.001)
    }

    func testRefusesResultsWithInvalidCoordinates() throws {
        let invalid = try TestFiles.modified("voorbeeld-resultaten.geojson") { root in
            var features = root["features"] as! [[String: Any]]
            features[6]["geometry"] = ["type": "Point", "coordinates": [5.5413693, 95.0]]
            root["features"] = features
        }
        XCTAssertThrowsError(try FieldResults.read(invalid)) {
            XCTAssertTrue($0.localizedDescription.contains("lengtegraad eerst"))
        }
    }

    func testReadsTheWeather() throws {
        let weather = try WeatherForecast.read(TestFiles.data("voorbeeld-weer.json"))
        XCTAssertEqual(weather.days.count, 5)
        XCTAssertEqual(weather.flightWindows?.count, 2)
        XCTAssertEqual(FieldSummary.dayLabel(weather.days[0].date), "ma 26 okt")
        XCTAssertEqual(FieldSummary.windowLabel(weather.flightWindows![0]), "di 27 okt 11:00–15:00")
        // A flight window should not be on a day with strong gusts (the Mini handles up to 8 m/s).
        for window in weather.flightWindows! {
            let day = String(ISO8601DateFormatter().string(from: window.start).prefix(10))
            let forecast = weather.days.first { $0.date == day }
            XCTAssertNotNil(forecast)
            XCTAssertLessThan(forecast!.gustMaxMps, 8)
        }
    }

    func testAgeText() {
        let now = JSONReading.parseDate("2026-10-25T12:00:00+01:00")!
        XCTAssertEqual(FieldSummary.ageText(of: now.addingTimeInterval(-30), now: now), "zojuist")
        XCTAssertEqual(FieldSummary.ageText(of: now.addingTimeInterval(-45 * 60), now: now), "45 min geleden")
        XCTAssertEqual(FieldSummary.ageText(of: now.addingTimeInterval(-6 * 3600), now: now), "6 uur geleden")
        XCTAssertEqual(FieldSummary.ageText(of: now.addingTimeInterval(-3 * 86400), now: now), "3 dagen geleden")
    }
}
