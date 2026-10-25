@testable import VeldvluchtKern
import XCTest

final class RouteFileTests: XCTestCase {
    private func sample() throws -> RoutePlanFile {
        try RoutePlanFile.read(TestFiles.data("voorbeeld.routeplan.json"))
    }

    private func codes(_ issues: [RouteIssue], _ level: RouteIssue.Level) -> [String] {
        issues.filter { $0.level == level }.map(\.code)
    }

    private func routeFile(_ change: (inout [String: Any]) -> Void) throws -> RoutePlanFile {
        try RoutePlanFile.read(TestFiles.modified("voorbeeld.routeplan.json", change))
    }

    func testReadsTheExampleFromTheDocumentation() throws {
        let file = try RoutePlanFile.read(Data(TestFiles.routeFileExample.utf8))
        XCTAssertEqual(file.name, "Proefstrook")
        XCTAssertEqual(file.mode, .route)
        XCTAssertNil(file.home)
        XCTAssertEqual(file.derived.photoPoints.count, 4)

        let issues = RouteCheck.check(file)
        XCTAssertEqual(codes(issues, .error), [])
        XCTAssertEqual(codes(issues, .warning), ["home-missing"])
    }

    func testTheExampleEstimateMatchesTheAppsOwnFigures() throws {
        let file = try RoutePlanFile.read(Data(TestFiles.routeFileExample.utf8))
        let summary = RouteCheck.summary(file)
        XCTAssertEqual(summary.totalDistanceM, file.derived.estimate.totalDistanceM, accuracy: 0.05)
        XCTAssertEqual(summary.flightTimeS, file.derived.estimate.flightTimeS, accuracy: 0.05)
    }

    func testSampleRouteIsValid() throws {
        let file = try sample()
        let issues = RouteCheck.check(file)
        XCTAssertEqual(codes(issues, .error), [])
        XCTAssertEqual(codes(issues, .warning), [])

        let summary = RouteCheck.summary(file)
        XCTAssertEqual(summary.waypointCount, 20)
        XCTAssertEqual(summary.photoCount, 180)
        XCTAssertEqual(summary.totalDistanceM, file.derived.estimate.totalDistanceM, accuracy: 0.05)
        XCTAssertEqual(summary.flightTimeS, file.derived.estimate.flightTimeS, accuracy: 0.05)
        XCTAssertEqual(summary.fieldAreaM2 ?? 0, file.derived.estimate.fieldAreaM2 ?? -1, accuracy: 0.05)
    }

    func testRefusesOtherFormatsAndVersions() throws {
        XCTAssertThrowsError(try RoutePlanFile.read(Data("geen json".utf8))) {
            XCTAssertEqual($0.localizedDescription, "Dit is geen geldig JSON-bestand.")
        }
        XCTAssertThrowsError(try routeFile { $0["format"] = "dji/mission" }) {
            XCTAssertTrue($0.localizedDescription.contains("drone-routeplanner/plan"))
        }
        XCTAssertThrowsError(try routeFile { $0["version"] = 2 }) {
            XCTAssertTrue($0.localizedDescription.contains("Onbekende versie 2"))
        }
        XCTAssertThrowsError(try routeFile { $0["mode"] = "orbit" }) {
            XCTAssertEqual($0.localizedDescription, "Veld \"mode\" moet \"route\" of \"field\" zijn.")
        }
        XCTAssertThrowsError(try routeFile { $0["derived"] = nil }) {
            XCTAssertTrue($0.localizedDescription.contains("derived"))
        }
    }

    func testRefusesInvalidCoordinates() throws {
        XCTAssertThrowsError(try routeFile { root in
            var derived = root["derived"] as! [String: Any]
            var waypoints = derived["waypoints"] as! [[String: Any]]
            waypoints[3]["lat"] = 95.0
            derived["waypoints"] = waypoints
            root["derived"] = derived
        }) {
            XCTAssertEqual($0.localizedDescription, "Punt 4 in \"derived.waypoints\" heeft geen geldige GPS-coördinaten (lat −90..90, lng −180..180).")
        }
    }

    func testExplainsMissingFields() throws {
        XCTAssertThrowsError(try routeFile { root in
            var settings = root["settings"] as! [String: Any]
            settings["speedMps"] = nil
            root["settings"] = settings
        }) {
            XCTAssertEqual($0.localizedDescription, "Veld \"settings.speedMps\" ontbreekt.")
        }
    }

    func testPhotoIntervalBelowTwoSecondsIsAnError() throws {
        var file = try sample()
        file.settings.photoIntervalS = 1.5
        XCTAssertTrue(codes(RouteCheck.check(file), .error).contains("interval-short"))
    }

    func testAltitudeAndSpeedLimits() throws {
        var file = try sample()
        file.settings.altitudeM = 130
        file.settings.speedMps = 9
        let errors = codes(RouteCheck.check(file), .error)
        XCTAssertTrue(errors.contains("altitude-high"))
        XCTAssertTrue(errors.contains("speed-high"))
        // The waypoints still say 30 m, so they no longer match the settings.
        XCTAssertTrue(errors.contains("waypoint-altitude"))
    }

    func testDerivedMustMatchTheRoutePoints() throws {
        var file = try sample()
        file.derived.waypoints[5].lng += 0.0001
        XCTAssertTrue(codes(RouteCheck.check(file), .error).contains("derived-mismatch"))
    }

    func testLegsMustConnectTheWaypoints() throws {
        var file = try sample()
        file.derived.legs[2].to = 7
        XCTAssertEqual(codes(RouteCheck.check(file), .error), ["legs-mismatch"])
    }

    func testPhotoMustLieOnItsLeg() throws {
        var file = try sample()
        file.derived.photoPoints[10].lng += 0.0001 // about 7 m east
        XCTAssertTrue(codes(RouteCheck.check(file), .error).contains("photo-off-leg"))
    }

    func testPhotoOnALegWithoutPhotosIsAnError() throws {
        var file = try sample()
        file.derived.photoPoints[10].legIndex = 1
        XCTAssertTrue(codes(RouteCheck.check(file), .error).contains("photo-leg"))
    }

    func testWarnsWhenTheRouteIsFarFromHome() throws {
        var file = try sample()
        file.assumptions.maxDistanceFromHomeM = 100
        XCTAssertTrue(codes(RouteCheck.check(file), .warning).contains("home-far"))
    }

    func testWarnsWhenTheFlightIsLongerThanTheBattery() throws {
        var file = try sample()
        file.assumptions.usableFlightTimeS = 600
        XCTAssertTrue(codes(RouteCheck.check(file), .warning).contains("battery"))
    }

    func testWarnsAboutWaypointsOutsideTheField() throws {
        var file = try sample()
        file.boundary = Array(file.boundary.prefix(3))
        XCTAssertTrue(codes(RouteCheck.check(file), .warning).contains("route-outside-field"))
    }

    func testWarnsWhenTheEstimateWasEdited() throws {
        var file = try sample()
        file.derived.estimate.totalDistanceM = 1000
        XCTAssertTrue(codes(RouteCheck.check(file), .warning).contains("estimate-mismatch"))
    }
}
