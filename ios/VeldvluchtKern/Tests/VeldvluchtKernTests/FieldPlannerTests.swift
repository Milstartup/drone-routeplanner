@testable import VeldvluchtKern
import XCTest

final class FieldPlannerTests: XCTestCase {
    /// A 100 m (east-west) by 60 m field near Dronten.
    private func rectangle() -> [LatLng] {
        let projection = LocalProjection(origin: LatLng(lat: 52.5, lng: 5.54))
        return [XY(x: 0, y: 0), XY(x: 100, y: 0), XY(x: 100, y: 60), XY(x: 0, y: 60)].map(projection.toLatLng)
    }

    /// The planner itself made these files (src/fixtures/fieldFixtures.test.ts). The app must
    /// give exactly the same route, photos and estimate for the same corners and settings.
    func testSameRouteAsThePlanner() throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for name in ["voorbeeld-veld.routeplan.json", "voorbeeld-veld-schuin.routeplan.json", "voorbeeld-veld-u.routeplan.json"] {
            let reference = try RoutePlanFile.read(TestFiles.data(name))
            let input = FieldPlanInput(name: reference.name, boundary: reference.boundary, home: reference.home,
                                       settings: reference.settings, assumptions: reference.assumptions)
            let createdAt = try XCTUnwrap(reference.createdAt.flatMap(formatter.date(from:)))
            let result = FieldPlanner.plan(input, createdAt: createdAt)

            XCTAssertEqual(result.file.derived.waypoints, reference.derived.waypoints, name)
            XCTAssertEqual(result.file.derived.legs, reference.derived.legs, name)
            XCTAssertEqual(result.file.derived.photoPoints, reference.derived.photoPoints, name)
            XCTAssertEqual(result.file.derived.estimate, reference.derived.estimate, name)
            XCTAssertEqual(result.file, reference, name)
            XCTAssertFalse(result.hasErrors, "\(name): \(result.issues)")
        }
    }

    func testTheUShapeHasTransitsOutsideTheField() throws {
        let reference = try RoutePlanFile.read(TestFiles.data("voorbeeld-veld-u.routeplan.json"))
        let result = FieldPlanner.plan(FieldPlanInput(name: reference.name, boundary: reference.boundary,
                                                      home: reference.home, settings: reference.settings))
        XCTAssertGreaterThan(result.coverage.transitsOutside, 0)
        XCTAssertTrue(result.issues.contains { $0.code == "transit-outside" })
    }

    func testRectangleGivesThreeLinesAlongTheLongSide() {
        let boundary = rectangle()
        let input = FieldPlanInput(name: "Proefveld", boundary: boundary, home: boundary[0])
        let result = FieldPlanner.plan(input)

        XCTAssertEqual(result.coverage.lineCount, 3)
        XCTAssertEqual(result.coverage.angleDeg, 90, accuracy: 0.01, "along the longest edge, east-west")
        XCTAssertEqual(result.coverage.waypoints.count, 6)
        XCTAssertEqual(result.coverage.legs.map(\.capture), [true, false, true, false, true])
        XCTAssertEqual(result.coverage.transitsOutside, 0)
        // 60 m minus 2 × 5 m margin leaves 50 m: lines at 10, 30 and 50 m from the south edge.
        let projection = LocalProjection(origin: LatLng(lat: 52.5, lng: 5.54))
        let ys = stride(from: 0, to: 6, by: 2).map { projection.toXY(result.coverage.waypoints[$0]).y }
        XCTAssertEqual(ys.sorted()[0], 10, accuracy: 0.01)
        XCTAssertEqual(ys.sorted()[1], 30, accuracy: 0.01)
        XCTAssertEqual(ys.sorted()[2], 50, accuracy: 0.01)
        // Each line runs 90 m (5 m margin at both ends); a photo every 4 m/s × 3 s = 12 m.
        XCTAssertEqual(Geo.distanceM(result.coverage.waypoints[0], result.coverage.waypoints[1]), 90, accuracy: 0.05)
        XCTAssertEqual(result.photos.count, 3 * 8)
        XCTAssertFalse(result.hasErrors, "\(result.issues)")
    }

    func testStartsAtTheLineEndNearestToTheTakeOffPoint() {
        let boundary = rectangle()
        for corner in boundary {
            let result = FieldPlanner.plan(FieldPlanInput(name: "Proefveld", boundary: boundary, home: corner))
            let first = result.coverage.waypoints[0]
            let nearest = result.coverage.waypoints.map { Geo.distanceM(corner, $0) }.min()!
            XCTAssertEqual(Geo.distanceM(corner, first), nearest, accuracy: 0.01)
        }
    }

    func testPhotosLieOnTheirLegsAndTheFileIsValid() throws {
        let boundary = rectangle()
        let result = FieldPlanner.plan(FieldPlanInput(name: "Proefveld", boundary: boundary, home: boundary[2]))
        let file = result.file
        XCTAssertEqual(file.mode, .field)
        XCTAssertEqual(file.derived.photoPoints.count, result.photos.count)
        XCTAssertEqual(file.derived.estimate.photoCount, result.photos.count)
        XCTAssertTrue(RouteCheck.check(file).filter { $0.level == .error }.isEmpty)
        // The app's own summary of the file agrees with the estimate written in it.
        let summary = RouteCheck.summary(file)
        XCTAssertEqual(summary.totalDistanceM, file.derived.estimate.totalDistanceM, accuracy: 0.5)
        XCTAssertEqual(summary.flightTimeS, file.derived.estimate.flightTimeS, accuracy: 0.5)

        // Written and read back, it is the same route; the planner needs "lineAngleDeg": null.
        let data = try file.encoded()
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"lineAngleDeg\" : null"))
        let read = try RoutePlanFile.read(data)
        XCTAssertEqual(read, file)
    }

    func testRefusesABoundaryThatCrossesItself() {
        let r = rectangle()
        let bowTie = [r[0], r[2], r[1], r[3]]
        let result = FieldPlanner.plan(FieldPlanInput(name: "Strik", boundary: bowTie, home: r[0]))
        XCTAssertTrue(result.issues.contains { $0.code == "boundary-self-intersect" })
        XCTAssertTrue(result.coverage.waypoints.isEmpty)
        XCTAssertTrue(result.hasErrors)
    }

    func testAsksForThreeCorners() {
        let r = rectangle()
        let result = FieldPlanner.plan(FieldPlanInput(name: "Twee", boundary: Array(r.prefix(2)), home: r[0]))
        XCTAssertEqual(result.issues.map(\.code), ["boundary-too-few"])
    }

    func testTooSmallForLines() {
        let projection = LocalProjection(origin: LatLng(lat: 52.5, lng: 5.54))
        let tiny = [XY(x: 0, y: 0), XY(x: 12, y: 0), XY(x: 12, y: 9), XY(x: 0, y: 9)].map(projection.toLatLng)
        let result = FieldPlanner.plan(FieldPlanInput(name: "Klein", boundary: tiny, home: tiny[0]))
        XCTAssertTrue(result.issues.contains { $0.code == "no-lines" })
    }

    func testAPhotoIntervalUnderTwoSecondsIsAnErrorInTheApp() {
        let boundary = rectangle()
        var input = FieldPlanInput(name: "Snel", boundary: boundary, home: boundary[0])
        input.settings.photoIntervalS = 1.5
        XCTAssertTrue(FieldPlanner.plan(input).issues.contains { $0.code == "interval-short" })
    }

    func testFixedAngleIsFoldedIntoHalfACircle() {
        XCTAssertEqual(FieldPlanner.normalizeLineAngle(200), 20, accuracy: 1e-9)
        XCTAssertEqual(FieldPlanner.normalizeLineAngle(-30), 150, accuracy: 1e-9)
        let boundary = rectangle()
        var input = FieldPlanInput(name: "Noord-zuid", boundary: boundary, home: boundary[0])
        input.settings.lineAngleDeg = 180
        let result = FieldPlanner.plan(input)
        XCTAssertEqual(result.coverage.angleDeg, 0, accuracy: 1e-9)
        // North-south lines across 100 m: (100 - 10) / 20 + 1 = 5 lines.
        XCTAssertEqual(result.coverage.lineCount, 5)
    }
}
