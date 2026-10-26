@testable import VeldvluchtKern
import XCTest

final class RouteFlightTests: XCTestCase {
    private var plan: FlightPlan!
    private var drone: FakeDrone!
    private var flight: RouteFlight!

    override func setUpWithError() throws {
        let file = try RoutePlanFile.read(TestFiles.data("voorbeeld.routeplan.json"))
        plan = FlightPlan(file)
        drone = FakeDrone(projection: plan.projection)
        let fake = drone!
        flight = RouteFlight(plan: plan, drone: fake, flightId: "test-1", fieldId: "veld-noord", clock: { fake.now })
        drone.flight = flight
    }

    /// Runs the fake drone and the 10 Hz control loop.
    private func run(seconds: Double, until done: (() -> Bool)? = nil) {
        var t = 0.0
        while t < seconds {
            drone.step(0.1)
            flight.update(drone.telemetry())
            flight.tick()
            t += 0.1
            if done?() == true { return }
        }
    }

    private func start() {
        flight.update(drone.telemetry())
        XCTAssertEqual(flight.preflightProblems(), [])
        flight.start()
    }

    private func runUntilFinished() {
        run(seconds: 2500) { [unowned self] in
            if case .finished = flight.phase { return true }
            if case .failed = flight.phase { return true }
            return false
        }
    }

    private func assertAllPhotosOnTheirPlace(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(flight.photoLog.photos.count, plan.photos.count, "bevestigde foto's", file: file, line: line)
        XCTAssertEqual(flight.missedPhotos, [], "gemiste foto's", file: file, line: line)
        XCTAssertEqual(flight.photoLog.photos.compactMap(\.plannedPhotoIndex), Array(0..<plan.photos.count), file: file, line: line)
        XCTAssertEqual(drone.shots.count, plan.photos.count, file: file, line: line)
        for (shot, photo) in zip(drone.shots, plan.photos) {
            let error = hypot(shot.position.x - photo.position.x, shot.position.y - photo.position.y)
            XCTAssertLessThan(error, 2.0, "foto \(photo.index + 1) ligt \(error) m naast de plek", file: file, line: line)
        }
        for (a, b) in zip(drone.shots, drone.shots.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b.time.timeIntervalSince(a.time), 2.0 - 1e-6, file: file, line: line)
        }
    }

    func testFliesTheSampleRouteAndTakesEveryPhotoOnItsPlace() {
        start()
        runUntilFinished()
        XCTAssertEqual(flight.phase, .finished)
        XCTAssertEqual(flight.axisMapping, .documented)
        assertAllPhotosOnTheirPlace()
        XCTAssertFalse(drone.flying)
        XCTAssertLessThan(hypot(drone.position.x, drone.position.y), 1, "geland op het startpunt")
        // The planner estimates 12:04 min; braking, the direction test and the climb add a bit.
        let flown = flight.log.last!.time.timeIntervalSince(flight.log.first!.time)
        XCTAssertLessThan(flown, 724 * 1.5)
    }

    func testFindsSwappedAxesAndStillFliesTheRoute() {
        drone.mapping = AxisMapping(pitch: XY(x: 0, y: 1), roll: XY(x: 1, y: 0))
        start()
        runUntilFinished()
        XCTAssertEqual(flight.axisMapping, drone.mapping)
        XCTAssertEqual(flight.phase, .finished)
        assertAllPhotosOnTheirPlace()
    }

    func testFindsReversedAxes() {
        drone.mapping = AxisMapping(pitch: XY(x: -1, y: 0), roll: XY(x: 0, y: -1))
        start()
        runUntilFinished()
        XCTAssertEqual(flight.axisMapping, drone.mapping)
        assertAllPhotosOnTheirPlace()
    }

    func testStaysOnTheLinesInCrosswind() {
        drone.wind = XY(x: 1.5, y: 0)
        start()
        runUntilFinished()
        XCTAssertEqual(flight.phase, .finished)
        assertAllPhotosOnTheirPlace()
    }

    func testDoesNotFlyTheRouteWhenTheDirectionTestFails() {
        drone.mapping = AxisMapping(pitch: XY(x: 1, y: 0), roll: XY(x: 1, y: 0))
        start()
        run(seconds: 120)
        guard case .paused(let reason) = flight.phase else { return XCTFail("\(flight.phase)") }
        XCTAssertTrue(reason.contains("Richtingtest mislukt"))
        XCTAssertNil(flight.axisMapping)
        XCTAssertEqual(drone.shots.count, 0)
        // Hovering, not wandering off.
        let before = drone.position
        run(seconds: 10)
        XCTAssertLessThan(hypot(drone.position.x - before.x, drone.position.y - before.y), 0.5)
    }

    func testRefusesToStartOutsideTheSimulator() {
        drone.simulatorActive = false
        flight.update(drone.telemetry())
        XCTAssertTrue(flight.preflightProblems().contains { $0.contains("simulator") })
        flight.start()
        run(seconds: 10)
        XCTAssertEqual(flight.phase, .ready)
        XCTAssertFalse(drone.motorsOn)
    }

    func testRefusesToStartFarFromTheTakeOffPoint() {
        drone = FakeDrone(projection: plan.projection, start: XY(x: 200, y: 0))
        let fake = drone!
        flight = RouteFlight(plan: plan, drone: fake, flightId: "test-2", fieldId: "veld-noord", clock: { fake.now })
        flight.update(drone.telemetry())
        XCTAssertTrue(flight.preflightProblems().contains { $0.contains("200 m van het startpunt") })
    }

    func testPauseHoldsPositionAndResumeContinuesWithoutDoubles() {
        start()
        run(seconds: 2000) { [unowned self] in flight.photoLog.photos.count >= 50 }
        XCTAssertEqual(flight.phase, .flying)
        flight.pause()
        run(seconds: 4) // braking
        let held = drone.position
        let shotsBefore = drone.shots.count
        run(seconds: 15)
        XCTAssertLessThan(hypot(drone.position.x - held.x, drone.position.y - held.y), 0.3)
        XCTAssertEqual(drone.shots.count, shotsBefore)

        flight.resume()
        runUntilFinished()
        XCTAssertEqual(flight.phase, .finished)
        assertAllPhotosOnTheirPlace()
    }

    func testMovingAStickHandsControlBackAndNeverResumesByItself() {
        start()
        run(seconds: 2000) { [unowned self] in flight.photoLog.photos.count >= 20 }
        flight.sticksMoved()
        guard case .takenOver = flight.phase else { return XCTFail("\(flight.phase)") }
        XCTAssertFalse(drone.virtualStick)
        let sent = drone.sendCount
        run(seconds: 30)
        XCTAssertEqual(drone.sendCount, sent, "geen stuurcommando's meer na overnemen")
        guard case .takenOver = flight.phase else { return XCTFail("\(flight.phase)") }

        // Resuming takes a tap, flies back to where it stopped and finishes the route.
        flight.resume()
        runUntilFinished()
        XCTAssertEqual(flight.phase, .finished)
        assertAllPhotosOnTheirPlace()
    }

    func testConnectionLossHandsOverAndDoesNotResumeAfterReconnecting() {
        start()
        run(seconds: 2000) { [unowned self] in flight.photoLog.photos.count >= 10 }
        drone.connected = false
        run(seconds: 3)
        guard case .takenOver = flight.phase else { return XCTFail("\(flight.phase)") }
        drone.connected = true
        run(seconds: 20)
        guard case .takenOver = flight.phase else { return XCTFail("na herstel: \(flight.phase)") }
    }

    func testLowBatteryGoesHome() {
        start()
        run(seconds: 2000) { [unowned self] in flight.photoLog.photos.count >= 30 }
        drone.batteryPercent = 20
        run(seconds: 1)
        XCTAssertEqual(flight.phase, .returningHome)
        runUntilFinished()
        XCTAssertEqual(flight.phase, .finished)
        XCTAssertFalse(drone.flying)
        XCTAssertLessThan(flight.photoLog.photos.count, plan.photos.count)
    }

    func testStoppingTheSimulatorHandsControlBack() {
        start()
        run(seconds: 2000) { [unowned self] in flight.phase == .flying }
        drone.simulatorActive = false
        run(seconds: 1)
        guard case .takenOver(let reason) = flight.phase else { return XCTFail("\(flight.phase)") }
        XCTAssertTrue(reason.contains("simulator"))
    }

    func testPhotoLogIsInTheFieldFormat() throws {
        start()
        runUntilFinished()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(flight.photoLog)
        let read = try PhotoLog.read(data)
        XCTAssertEqual(read.photos.count, plan.photos.count)
        XCTAssertEqual(read.routePlanName, plan.name)
        XCTAssertEqual(read.photos.first?.altitudeM ?? 0, plan.altitudeM, accuracy: 1)
    }
}

final class AxisMappingTests: XCTestCase {
    func testSticksForTheDocumentedMapping() {
        let sticks = AxisMapping.documented.sticks(east: 3, north: 4)
        XCTAssertEqual(sticks.pitch, 3)
        XCTAssertEqual(sticks.roll, 4)
        XCTAssertEqual(AxisMapping.documented.description, "pitch = oost, roll = noord")
    }

    func testMeasuresSwappedAndReversedAxes() throws {
        let mapping = try AxisMapping.measure(pitchMove: XY(x: 0.2, y: -2.1), rollMove: XY(x: 1.9, y: 0.3))
        XCTAssertEqual(mapping, AxisMapping(pitch: XY(x: 0, y: -1), roll: XY(x: 1, y: 0)))
        let sticks = mapping.sticks(east: 1, north: 2)
        XCTAssertEqual(sticks.pitch, -2)
        XCTAssertEqual(sticks.roll, 1)
    }

    func testRefusesUnclearMoves() {
        XCTAssertThrowsError(try AxisMapping.measure(pitchMove: XY(x: 0.1, y: 0), rollMove: XY(x: 0, y: 2)))
        XCTAssertThrowsError(try AxisMapping.measure(pitchMove: XY(x: 1.5, y: 1.5), rollMove: XY(x: 0, y: 2)))
        XCTAssertThrowsError(try AxisMapping.measure(pitchMove: XY(x: 2, y: 0), rollMove: XY(x: -2, y: 0)))
    }
}

final class FlightPlanTests: XCTestCase {
    func testPhotosLieOnTheRouteInOrder() throws {
        let plan = FlightPlan(try RoutePlanFile.read(TestFiles.data("voorbeeld.routeplan.json")))
        XCTAssertEqual(plan.legs.count, 19)
        XCTAssertEqual(plan.photos.count, 180)
        XCTAssertEqual(plan.home, LatLng(lat: 52.4979, lng: 5.5409))
        for (a, b) in zip(plan.photos, plan.photos.dropFirst()) {
            XCTAssertLessThan(a.alongM, b.alongM)
        }
        for photo in plan.photos {
            let p = plan.point(alongM: photo.alongM).point
            XCTAssertLessThan(hypot(p.x - photo.position.x, p.y - photo.position.y), 0.05)
        }
        XCTAssertEqual(plan.legs[0].bearingDeg, 0, accuracy: 0.01)
        XCTAssertEqual(plan.legs[2].bearingDeg, 180, accuracy: 0.01)
    }

    func testTrackSaysWhichSideOfTheLine() throws {
        let plan = FlightPlan(try RoutePlanFile.read(TestFiles.data("voorbeeld.routeplan.json")))
        let leg = plan.legs[0] // northwards
        let east = plan.track(XY(x: leg.from.x + 3, y: leg.from.y + 10), onLeg: 0)
        XCTAssertEqual(east.alongLegM, 10, accuracy: 1e-6)
        XCTAssertEqual(east.crossM, 3, accuracy: 1e-6) // east of a northward line is on the right
    }
}
