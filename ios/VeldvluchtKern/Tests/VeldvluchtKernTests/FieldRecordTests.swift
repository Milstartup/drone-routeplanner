@testable import VeldvluchtKern
import XCTest

final class FieldRecordTests: XCTestCase {
    private func lShape() throws -> [LatLng] {
        try RoutePlanFile.read(TestFiles.data("voorbeeld-veld.routeplan.json")).boundary
    }

    private func record(_ boundary: [LatLng]) -> FieldRecord {
        let date = Date(timeIntervalSince1970: 1_793_000_000)
        return FieldRecord(id: "proefveld", name: "Proefveld", boundary: boundary, home: boundary[0],
                           settings: .planner, createdAt: date, updatedAt: date)
    }

    func testIdsFromNames() {
        XCTAssertEqual(FieldRecord.slug("Broccoli noord (voorbeeld)"), "broccoli-noord-voorbeeld")
        XCTAssertEqual(FieldRecord.slug("Één veld"), "een-veld")
        XCTAssertEqual(FieldRecord.slug("  "), "veld")
        XCTAssertEqual(FieldRecord.makeId(for: "Noord", taken: ["noord", "noord-2"]), "noord-3")
    }

    func testStripsCoverTheWholeField() throws {
        for boundary in [try lShape(), try RoutePlanFile.read(TestFiles.data("voorbeeld-veld-u.routeplan.json")).boundary] {
            let field = record(boundary)
            let strips = FieldStrips.strips(boundary: boundary, angleDeg: field.lineAngleDeg, widthM: 24)
            XCTAssertGreaterThan(strips.count, 3)
            let total = strips.map(Geo.polygonAreaM2).reduce(0, +)
            XCTAssertEqual(total, field.areaM2, accuracy: field.areaM2 * 0.001)
        }
    }

    func testSensorPlacesLieInsideTheField() throws {
        let boundary = try RoutePlanFile.read(TestFiles.data("voorbeeld-veld-u.routeplan.json")).boundary
        let angle = FieldPlanner.lineAngle(boundary: boundary, setting: nil)
        let places = FieldStrips.sensorPlaces(boundary: boundary, angleDeg: angle, count: 6)
        XCTAssertEqual(places.count, 6)
        let projection = LocalProjection(origin: Geo.centroid(boundary))
        let poly = boundary.map(projection.toXY)
        for place in places {
            XCTAssertTrue(Geo.pointInPolygon(projection.toXY(place), poly))
        }
    }

    func testCalibrationWorksBothWaysRound() {
        let school = SensorMeasurement.Calibration(dryRaw: 860, wetRaw: 340)
        XCTAssertEqual(school.percent(raw: 600) ?? -1, 50, accuracy: 1e-9)
        XCTAssertEqual(school.percent(raw: 900) ?? -1, 0, accuracy: 1e-9)
        let other = SensorMeasurement.Calibration(dryRaw: 300, wetRaw: 700)
        XCTAssertEqual(other.percent(raw: 600) ?? -1, 75, accuracy: 1e-9)
        XCTAssertNil(SensorMeasurement.Calibration(dryRaw: 500, wetRaw: 500).percent(raw: 500))
    }

    func testSavedAndReadBack() throws {
        var field = record(try lShape())
        field.sensors = [FieldSensor(id: "proefveld-s1", location: field.boundary[1],
                                     calibration: .init(dryRaw: 3100, wetRaw: 1200))]
        let read = try FieldRecord.read(field.encoded())
        XCTAssertEqual(read, field)
    }

    func testTheRouteKeepsItsIdentityUntilTheFieldChanges() throws {
        let field = record(try lShape())
        XCTAssertEqual(field.plan().file.createdAt, field.plan().file.createdAt)
        XCTAssertEqual(field.plan().file.createdAt, "2026-10-26T07:33:20.000Z")
        XCTAssertFalse(field.plan().hasErrors)
    }

    func testFootprintOfTheCamera() throws {
        let footprint = try XCTUnwrap(CameraFootprint.at(altitudeM: 30))
        XCTAssertEqual(footprint.widthM, 42.4, accuracy: 0.1)
        XCTAssertEqual(footprint.lengthM, 31.8, accuracy: 0.1)
        XCTAssertEqual(footprint.gsdCm, 1.06, accuracy: 0.01)
    }
}
