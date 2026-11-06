@testable import VeldvluchtKern
import XCTest

final class RouteFlightTests: XCTestCase {
    private var plan: FlightPlan!
    private var drone: FakeDrone!
    private var flight: RouteFlight!

    override func setUpWithError() throws {
        let file = try RoutePlanFile.read(TestFiles.data("voorbeeld.routeplan.json"))
        plan = FlightPlan(file)
        setUpFlight()
    }

    private func setUpFlight() {
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

    func testBuildsUpSpeedGently() {
        start()
        run(seconds: 120) { [unowned self] in flight.phase == .toStart }
        // The direction test itself makes short, sudden moves; after it everything is gentle.
        drone.largestSpeedRise = 0
        runUntilFinished()
        XCTAssertEqual(flight.phase, .finished)
        assertAllPhotosOnTheirPlace()
        // 1 m/s² at 10 commands per second, plus the bit the drone still drifted when the
        // steering started (it builds up from the drone's own speed).
        XCTAssertLessThanOrEqual(drone.largestSpeedRise, 0.12)
    }

    func testDirectionTestCopesWithGPSWander() {
        // 6 November 2026: on the first real flight the first direction test failed (48°).
        for phase in stride(from: 0.0, to: 6.2, by: 0.4) {
            setUpFlight()
            drone.gpsWanderM = 1.0
            drone.gpsWanderPhase = phase
            start()
            run(seconds: 120) { [unowned self] in flight.axisMapping != nil || flight.log.contains { $0.text.hasPrefix("Richtingtest mislukt") } }
            XCTAssertEqual(flight.axisMapping, .documented, "fase \(phase): \(flight.log.map(\.text))")
            XCTAssertTrue(flight.log.contains { $0.text.hasPrefix("Gemeten: pitch ") }, "\(flight.log.map(\.text))")
        }
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

final class RouteFlightSafetyTests: XCTestCase {
    private var plan: FlightPlan!
    private var drone: FakeDrone!
    private var flight: RouteFlight!

    override func setUpWithError() throws {
        plan = FlightPlan(try RoutePlanFile.read(TestFiles.data("voorbeeld.routeplan.json")))
        make()
    }

    private func make(settings: RouteFlight.Settings = .init(), startAtPhoto: Int = 0) {
        drone = FakeDrone(projection: plan.projection)
        let fake = drone!
        flight = RouteFlight(plan: plan, drone: fake, flightId: "t", fieldId: "veld-noord",
                             settings: settings, startAtPhoto: startAtPhoto, clock: { fake.now })
        drone.flight = flight
        flight.update(drone.telemetry())
    }

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

    private func finished() -> Bool {
        if case .finished = flight.phase { return true }
        if case .failed = flight.phase { return true }
        return false
    }

    func testFollowsTheDronesOwnReturnAndStopsSteering() {
        flight.start()
        run(seconds: 2000) { [unowned self] in flight.photoLog.photos.count >= 40 }
        drone.startOwnReturn()
        run(seconds: 1)
        XCTAssertEqual(flight.phase, .returningHome)
        let sent = drone.sendCount
        run(seconds: 600, until: finished)
        XCTAssertEqual(flight.phase, .finished)
        XCTAssertEqual(drone.sendCount, sent, "geen stuurcommando's tijdens de eigen terugkeer van de drone")
        XCTAssertEqual(flight.continueAtPhoto.map { $0 >= 40 }, true)
    }

    func testFailsafeReturnAfterConnectionLossIsShown() {
        flight.start()
        run(seconds: 2000) { [unowned self] in flight.photoLog.photos.count >= 10 }
        drone.connected = false
        run(seconds: 1)
        drone.startOwnReturn() // DJI failsafe after 3 s without connection
        run(seconds: 3)
        drone.connected = true
        run(seconds: 1)
        XCTAssertEqual(flight.phase, .returningHome)
        run(seconds: 600, until: finished)
        XCTAssertEqual(flight.phase, .finished)
    }

    func testSeriousLowBatteryAndStrongWindGoHome() {
        flight.start()
        run(seconds: 2000) { [unowned self] in flight.phase == .flying }
        drone.seriousLowBattery = true
        run(seconds: 1)
        XCTAssertEqual(flight.phase, .returningHome)

        make()
        flight.start()
        run(seconds: 2000) { [unowned self] in flight.phase == .flying }
        drone.windWarning = 2
        run(seconds: 1)
        XCTAssertEqual(flight.phase, .returningHome)
    }

    func testContinuesFromAPhotoOfAnEarlierFlight() {
        make(startAtPhoto: 90)
        flight.start()
        run(seconds: 2500, until: finished)
        XCTAssertEqual(flight.phase, .finished)
        XCTAssertEqual(flight.photoLog.photos.compactMap(\.plannedPhotoIndex), Array(90..<180))
        XCTAssertEqual(flight.missedPhotos, [])
        XCTAssertNil(flight.continueAtPhoto)
        for (shot, photo) in zip(drone.shots, plan.photos[90...]) {
            XCTAssertLessThan(hypot(shot.position.x - photo.position.x, shot.position.y - photo.position.y), 2.0)
        }
    }

    func testRealFlightNeedsStricterChecks() {
        var settings = RouteFlight.Settings()
        settings.requireSimulator = false
        settings.maxRouteLengthM = 800
        make(settings: settings)
        drone.simulatorActive = false
        drone.gpsLevel = 3
        drone.homePointSet = false
        drone.windWarning = 1
        drone.batteryPercent = 45
        drone.satellites = 9
        flight.update(drone.telemetry())
        let problems = flight.preflightProblems().joined(separator: "\n")
        for expected in ["korte route", "harde wind", "thuispunt", "GPS-signaal te zwak", "Accu te leeg", "satellieten"] {
            XCTAssertTrue(problems.contains(expected), "verwacht: \(expected)\n\(problems)")
        }
        XCTAssertFalse(problems.contains("simulator"))
        flight.start()
        run(seconds: 5)
        XCTAssertEqual(flight.phase, .ready)
        XCTAssertFalse(drone.motorsOn)
    }

    func testRealFlightRefusesWhileTheSimulatorRuns() {
        var settings = RouteFlight.Settings()
        settings.requireSimulator = false
        make(settings: settings)
        XCTAssertTrue(flight.preflightProblems().contains { $0.contains("simulator staat nog aan") })
    }

    func testLandingByThePilotAfterATakeOverEndsTheFlight() {
        flight.start()
        run(seconds: 2000) { [unowned self] in flight.photoLog.photos.count >= 25 }
        flight.takeOver()
        drone.landByPilot()
        run(seconds: 1)
        XCTAssertEqual(flight.phase, .finished)
        XCTAssertFalse(flight.phase.isAirborne)
        XCTAssertNotNil(flight.continueAtPhoto)
    }

    func testRecordsThatAStickTookOver() {
        flight.start()
        run(seconds: 2000) { [unowned self] in flight.phase == .flying }
        XCTAssertFalse(flight.stickTakeOverHappened)
        flight.sticksMoved()
        XCTAssertTrue(flight.stickTakeOverHappened)
    }

    // MARK: Simulator test of 2 November 2026: "Overnemen" while the drone went home

    private func goHomeUntilLanding() {
        flight.start()
        run(seconds: 2000) { [unowned self] in flight.phase == .flying }
        flight.goHome()
        run(seconds: 600) { [unowned self] in drone.landing }
        XCTAssertTrue(drone.landing)
    }

    func testTakeOverWhileGoingHomeStopsGoingHome() {
        flight.start()
        run(seconds: 2000) { [unowned self] in flight.photoLog.photos.count >= 20 }
        flight.goHome()
        run(seconds: 2)
        XCTAssertTrue(drone.goingHome)
        XCTAssertFalse(drone.landing)
        flight.takeOver()
        run(seconds: 5)
        guard case .takenOver = flight.phase else { return XCTFail("\(flight.phase)") }
        XCTAssertFalse(drone.goingHome)
        XCTAssertTrue(flight.log.contains { $0.text == "Naar huis is afgebroken; jij vliegt." })
    }

    func testTakeOverWhileLandingStopsTheLanding() {
        goHomeUntilLanding()
        flight.takeOver()
        run(seconds: 1)
        guard case .takenOver = flight.phase else { return XCTFail("\(flight.phase)") }
        XCTAssertFalse(drone.goingHome)
        XCTAssertTrue(drone.flying, "hangt stil in de lucht")
        XCTAssertTrue(flight.log.contains { $0.text == "Landen is afgebroken; jij vliegt." })
        run(seconds: 5)
        guard case .takenOver = flight.phase else { return XCTFail("springt terug: \(flight.phase)") }
    }

    func testRefusedTakeOverKeepsTheReturnAndSaysSo() {
        drone.refusesCancel = true
        goHomeUntilLanding()
        for _ in 0..<6 {
            flight.takeOver()
            run(seconds: 0.5)
            XCTAssertEqual(flight.phase, .returningHome)
        }
        run(seconds: 3)
        XCTAssertEqual(flight.phase, .returningHome)
        XCTAssertFalse(flight.log.contains { $0.text.contains("jij vliegt") }, "zegt niet dat de piloot vliegt")
        XCTAssertFalse(flight.log.contains { $0.text.contains("keert zelf terug") }, "springt niet heen en weer")
        XCTAssertLessThanOrEqual(flight.log.filter { $0.text.contains("afbreken lukt niet") }.count, 2,
                                 "één poging tegelijk")
        XCTAssertTrue(flight.log.contains { $0.text.contains("pauzeknop op de afstandsbediening") })
        run(seconds: 600, until: finished)
        XCTAssertEqual(flight.phase, .finished)
    }

    func testWaitingToLandIsExplained() {
        drone.waitsForLandingConfirmation = true
        goHomeUntilLanding()
        run(seconds: 60) { [unowned self] in drone.telemetry().landingConfirmationNeeded }
        run(seconds: 1)
        XCTAssertTrue(flight.log.contains { $0.text == "De drone landt." })
        XCTAssertEqual(flight.log.filter { $0.text.contains("Tik dan op Landen") }.count, 1)
        XCTAssertTrue(flight.canConfirmLanding)
        drone.landByPilot()
        run(seconds: 1)
        XCTAssertEqual(flight.phase, .finished)
        XCTAssertFalse(flight.canConfirmLanding)
    }

    func testLandenButtonLetsTheWaitingDroneLand() {
        drone.waitsForLandingConfirmation = true
        goHomeUntilLanding()
        XCTAssertFalse(flight.canConfirmLanding, "nog niet zo laag")
        flight.confirmLanding()
        XCTAssertFalse(flight.log.contains { $0.text.contains("Landen bevestigd") }, "alleen als de drone wacht")
        run(seconds: 60) { [unowned self] in flight.canConfirmLanding }
        flight.confirmLanding()
        XCTAssertFalse(flight.canConfirmLanding, "de knop verdwijnt na één tik")
        flight.confirmLanding()
        XCTAssertEqual(flight.log.filter { $0.text == "Landen bevestigd door de piloot." }.count, 1)
        run(seconds: 10, until: finished)
        XCTAssertEqual(flight.phase, .finished)
        XCTAssertFalse(flight.log.contains { $0.text.contains("bevestigen lukt niet") })
    }

    func testPauseButtonDuringTheReturnHandsOver() {
        flight.start()
        run(seconds: 2000) { [unowned self] in flight.photoLog.photos.count >= 20 }
        flight.goHome()
        run(seconds: 5)
        drone.stopOwnReturn()
        run(seconds: 2)
        XCTAssertEqual(flight.phase, .returningHome, "nog niet in de eerste 3 s")
        run(seconds: 2)
        guard case .takenOver = flight.phase else { return XCTFail("\(flight.phase)") }
        XCTAssertTrue(flight.log.contains { $0.text.contains("keert niet meer terug") })
        flight.takeOver()
        run(seconds: 1)
        XCTAssertFalse(flight.log.contains { $0.text.contains("afbreken lukt niet") })
    }

    func testThePilotsOwnLandingIsNotCalledAReturn() {
        goHomeUntilLanding()
        flight.takeOver()
        run(seconds: 3)
        guard case .takenOver = flight.phase else { return XCTFail("\(flight.phase)") }
        let before = flight.log.count
        drone.startOwnReturn() // left stick down above the take-off point: the drone lands
        run(seconds: 3)
        XCTAssertEqual(flight.phase, .returningHome)
        let after = flight.log.dropFirst(before).map(\.text)
        XCTAssertTrue(after.contains("De drone landt."), "\(after)")
        XCTAssertFalse(after.contains { $0.contains("keert zelf terug") }, "\(after)")
        run(seconds: 600, until: finished)
        XCTAssertEqual(flight.phase, .finished)
    }

    func testFailedTakeOffSaysWhatTheDroneReported() {
        drone.ignoresTakeOff = true
        flight.start()
        run(seconds: 25)
        guard case .failed = flight.phase else { return XCTFail("\(flight.phase)") }
        XCTAssertTrue(flight.log.contains { $0.text.contains("nam het commando aan. Motoren uit") }, "\(flight.log.map(\.text))")
    }

    func testLogsConnectionAndFlightModeChangesInTheAir() {
        flight.start()
        run(seconds: 2000) { [unowned self] in flight.phase == .flying }
        drone.flightModeName = "Joystick"
        run(seconds: 1)
        drone.flightModeName = "GoHome"
        flight.goHome()
        run(seconds: 2)
        drone.connected = false
        run(seconds: 1)
        drone.connected = true
        run(seconds: 1)
        let texts = flight.log.map(\.text)
        XCTAssertEqual(texts.filter { $0 == "Vluchtstand van de drone: Joystick." }.count, 1)
        XCTAssertEqual(texts.filter { $0 == "Vluchtstand van de drone: GoHome." }.count, 1, "niet opnieuw na de verbinding")
        XCTAssertTrue(texts.contains("Verbinding met de drone weg."), "\(texts)")
        XCTAssertTrue(texts.contains("Verbinding met de drone terug."), "\(texts)")
    }

    func testLogsTheSimulatorStoppingDuringTheReturn() {
        flight.start()
        run(seconds: 2000) { [unowned self] in flight.phase == .flying }
        flight.goHome()
        run(seconds: 2)
        drone.connected = false
        run(seconds: 1)
        drone.simulatorActive = false
        drone.connected = true
        run(seconds: 1)
        XCTAssertEqual(flight.log.filter { $0.text == "De simulator staat uit." }.count, 1, "\(flight.log.map(\.text))")
    }

    func testRefusesToStartWithAnAlmostEmptyBattery() {
        drone.batteryPercent = 31
        flight.update(drone.telemetry())
        XCTAssertEqual(flight.preflightProblems(), ["Accu te leeg: 31 % (minimaal 40 %)."])
    }

    func testPullingTheCableIsExplainedAndSoIsTheStoppedSimulator() {
        flight.start()
        run(seconds: 2000) { [unowned self] in flight.phase == .flying }
        drone.cableConnected = false
        run(seconds: 1)
        guard case .takenOver = flight.phase else { return XCTFail("\(flight.phase)") }
        let texts = flight.log.map(\.text)
        XCTAssertTrue(texts.contains { $0.hasPrefix("Kabel tussen iPhone en afstandsbediening los") && $0.contains("hangt de drone stil") }, "\(texts)")
        XCTAssertFalse(texts.contains { $0.contains("keert de drone na 3 s") }, "dat geldt voor de radioverbinding")
        // 6 November 2026: the simulator had stopped and the drone stood on the ground again.
        drone.simulatorActive = false
        drone.landByPilot()
        drone.cableConnected = true
        run(seconds: 1)
        XCTAssertEqual(flight.phase, .finished)
        let end = flight.log.map(\.text)
        XCTAssertTrue(end.contains("De simulator is gestopt, dus de drone staat weer op de grond. \(flight.photoLog.photos.count) foto's bevestigd."), "\(end)")
        XCTAssertFalse(end.contains { $0.hasPrefix("Geland door de piloot") })
    }

    func testPointsTheCameraStraightDownBeforeTakeOff() {
        XCTAssertEqual(drone.cameraPitchDeg, 0)
        flight.start()
        run(seconds: 30) { [unowned self] in drone.flying }
        XCTAssertEqual(drone.cameraPitchDeg, -90)
        let texts = flight.log.map(\.text)
        let down = texts.firstIndex(of: "Camera recht naar beneden.")
        let takeOff = texts.firstIndex(of: "Opstijgen…")
        XCTAssertNotNil(down, "\(texts)")
        XCTAssertLessThan(down ?? .max, takeOff ?? .min)
    }

    func testDoesNotTakeOffWhenTheCameraCannotPointDown() {
        drone.refusesCameraDown = true
        flight.start()
        run(seconds: 5)
        guard case .failed = flight.phase else { return XCTFail("\(flight.phase)") }
        XCTAssertFalse(drone.motorsOn)
        XCTAssertTrue(flight.log.contains { $0.text.contains("Camera recht naar beneden draaien lukt niet: gimbal geeft geen antwoord") },
                      "\(flight.log.map(\.text))")
    }

    func testSkipsPhotosWhileTheCameraIsTiltedAndTurnsItBack() {
        flight.start()
        run(seconds: 2000) { [unowned self] in flight.photoLog.photos.count >= 5 }
        // The pilot turns the gimbal wheel on the remote controller (6 November 2026).
        drone.cameraPitchDeg = -45
        let photos = flight.photoLog.photos.count
        run(seconds: 60) { [unowned self] in flight.photoLog.photos.count >= photos + 2 }
        XCTAssertEqual(drone.cameraPitchDeg, -90)
        let texts = flight.log.map(\.text)
        XCTAssertEqual(texts.filter { $0 == "De camera kijkt even niet recht naar beneden (-45°). De app wacht met de foto en draait hem terug." }.count, 1, "\(texts)")
        run(seconds: 2500, until: finished)
        XCTAssertEqual(flight.phase, .finished)
        XCTAssertEqual(drone.tiltedShots, 0, "geen scheve foto's")
        XCTAssertLessThanOrEqual(flight.missedPhotos.count, 1)
        for index in flight.missedPhotos {
            XCTAssertTrue(flight.log.contains { $0.text == "Foto \(index + 1) gemist: de camera keek niet recht naar beneden (-45°)." }, "\(flight.log.map(\.text))")
        }
        XCTAssertEqual(flight.photoLog.photos.count, plan.photos.count - flight.missedPhotos.count)
    }
}

/// One test per finding of the independent review (26 October 2026).
final class ReviewFindingsTests: XCTestCase {
    private var plan: FlightPlan!
    private var drone: FakeDrone!
    private var flight: RouteFlight!

    override func setUpWithError() throws {
        plan = FlightPlan(try RoutePlanFile.read(TestFiles.data("voorbeeld.routeplan.json")))
        drone = FakeDrone(projection: plan.projection)
        let fake = drone!
        flight = RouteFlight(plan: plan, drone: fake, flightId: "t", fieldId: "veld-noord", clock: { fake.now })
        drone.flight = flight
        flight.update(drone.telemetry())
    }

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

    private func finished() -> Bool {
        if case .finished = flight.phase { return true }
        if case .failed = flight.phase { return true }
        return false
    }

    private var isTakenOver: Bool {
        if case .takenOver = flight.phase { return true }
        return false
    }

    /// 1. Before the direction test the app must not steer with an unchecked mapping.
    func testNoPositionHoldWithUncheckedAxes() {
        drone.mapping = AxisMapping(pitch: XY(x: 0, y: 1), roll: XY(x: 1, y: 0))
        flight.start()
        run(seconds: 60) { [unowned self] in flight.phase == .climbing }
        drone.nudge(XY(x: 0.6, y: 0))
        var farthest = 0.0
        run(seconds: 120) { [unowned self] in
            farthest = max(farthest, hypot(drone.position.x, drone.position.y))
            return flight.phase == .toStart
        }
        XCTAssertEqual(flight.phase, .toStart)
        // The test itself moves the drone one leg east and one north; 3 m more is drift.
        let settings = RouteFlight.Settings()
        let testMoves = hypot(1, 1) * settings.axisTestSpeedMps * settings.axisMoveS
        XCTAssertLessThan(farthest, testMoves + 3, "de drone dreef \(farthest) m weg vóór de richtingtest klaar was")
    }

    /// 1b. After a failed direction test the pause must not run away either.
    func testFailedDirectionTestDoesNotRunAway() {
        drone.mapping = AxisMapping(pitch: XY(x: 1, y: 0), roll: XY(x: 1, y: 0))
        flight.start()
        run(seconds: 120) { [unowned self] in if case .paused = flight.phase { return true }; return false }
        let start = drone.position
        drone.nudge(XY(x: 0.5, y: 0.5))
        run(seconds: 60)
        XCTAssertLessThan(hypot(drone.position.x - start.x, drone.position.y - start.y), 2)
    }

    /// 2. A take-over while Virtual Stick is being switched on must win.
    func testLateEnableDoesNotOverrideATakeOver() {
        drone.enableDelay = 1.0
        flight.start()
        // The moment the app asks for Virtual Stick; the answer takes 1 s.
        run(seconds: 30) { [unowned self] in flight.log.contains { $0.text.contains("Virtual Stick aan") } }
        flight.takeOver()
        run(seconds: 5)
        XCTAssertTrue(isTakenOver, "\(flight.phase)")
        XCTAssertFalse(drone.virtualStick)
        XCTAssertEqual(drone.sendCount, 0)
    }

    /// 2b. Moving a stick while a resume is being set up keeps control with the pilot.
    func testStickDuringResumeKeepsControlWithThePilot() {
        flight.start()
        run(seconds: 2000) { [unowned self] in flight.phase == .flying }
        flight.takeOver()
        drone.enableDelay = 1.0
        flight.resume()
        flight.updateSticks(deflected: true)
        run(seconds: 5)
        XCTAssertTrue(isTakenOver, "\(flight.phase)")
        XCTAssertFalse(drone.virtualStick)
        XCTAssertTrue(flight.stickTakeOverHappened)
        // And no resume while the stick is still out of the centre.
        flight.resume()
        run(seconds: 3)
        XCTAssertTrue(isTakenOver)
    }

    /// 2c. A stick held during take-off.
    func testStickDuringTakeOffHandsOver() {
        flight.start()
        run(seconds: 30) { [unowned self] in flight.phase == .takingOff }
        flight.updateSticks(deflected: true)
        run(seconds: 10)
        XCTAssertTrue(isTakenOver, "\(flight.phase)")
        XCTAssertEqual(drone.sendCount, 0)
    }

    /// 3. Go-home must not be sent after the pilot took over.
    func testGoHomeIsNotSentAfterATakeOver() {
        drone.disableDelay = 1.0
        flight.start()
        run(seconds: 2000) { [unowned self] in flight.phase == .flying }
        flight.goHome()
        flight.takeOver()
        run(seconds: 10)
        XCTAssertTrue(isTakenOver, "\(flight.phase)")
        XCTAssertFalse(drone.goingHome)
    }

    /// 4. A failed switch-off of Virtual Stick is retried.
    func testRetriesSwitchingVirtualStickOff() {
        flight.start()
        run(seconds: 2000) { [unowned self] in flight.phase == .flying }
        drone.failDisableCount = 2
        flight.takeOver()
        XCTAssertTrue(drone.virtualStick)
        run(seconds: 3)
        XCTAssertFalse(drone.virtualStick)
        XCTAssertTrue(flight.log.contains { $0.text.contains("Virtual Stick staat nu uit") })
    }

    /// 5. One unreported file does not shift the photo log.
    func testUnreportedFileDoesNotShiftThePhotoLog() {
        drone.unreportedFiles = [5]
        flight.start()
        run(seconds: 2500, until: finished)
        XCTAssertEqual(flight.phase, .finished)
        XCTAssertEqual(flight.missedPhotos, [4])
        for photo in flight.photoLog.photos {
            // The fake numbers files 1, 2, 3... for planned photos 0, 1, 2...
            XCTAssertEqual(RouteFlight.fileNumber(photo.file), photo.plannedPhotoIndex! + 1, photo.file)
        }
        XCTAssertEqual(flight.photoLog.photos.count, 179)
    }

    /// 5b. A camera error although the photo was taken.
    func testCameraErrorButPhotoTaken() {
        drone.falseErrors = [3]
        flight.start()
        run(seconds: 2500, until: finished)
        XCTAssertEqual(flight.missedPhotos, [])
        XCTAssertEqual(flight.photoLog.photos.count, 180)
        for photo in flight.photoLog.photos {
            XCTAssertEqual(RouteFlight.fileNumber(photo.file), photo.plannedPhotoIndex! + 1, photo.file)
        }
    }

    /// 6. Losing GPS mid-route resumes where the drone was, not at the start.
    func testGPSLossResumesWhereTheRouteStopped() {
        flight.start()
        run(seconds: 2000) { [unowned self] in flight.legIndex >= 4 && flight.phase == .flying }
        run(seconds: 10) // well into the line
        let leg = flight.legIndex
        drone.gpsLost = true
        run(seconds: 2)
        guard case .paused = flight.phase else { return XCTFail("\(flight.phase)") }
        drone.gpsLost = false
        flight.resume()
        run(seconds: 120) { [unowned self] in flight.phase == .flying }
        XCTAssertEqual(flight.legIndex, leg)
        run(seconds: 2500, until: finished)
        XCTAssertEqual(flight.photoLog.photos.count, 180)
        XCTAssertEqual(flight.missedPhotos, [])
    }

    func testRefusesToStartWithAStickOutOfTheCentre() {
        flight.updateSticks(deflected: true)
        XCTAssertTrue(flight.preflightProblems().contains("Laat de sticks los."))
    }

    func testFileNumbers() {
        XCTAssertEqual(RouteFlight.fileNumber("DJI_0096.jpg"), 96)
        XCTAssertEqual(RouteFlight.fileNumber("DJI_0001.JPG"), 1)
        XCTAssertNil(RouteFlight.fileNumber("foto.jpg"))
    }
}
