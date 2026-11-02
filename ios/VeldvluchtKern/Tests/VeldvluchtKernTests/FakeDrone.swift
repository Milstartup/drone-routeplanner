// A fake drone for the flight tests (docs/DJI-MOBILE-SDK-V4.md, 6.1: "test bijna alles met
// een nep-drone"). Simple physics: the velocity follows the stick command with a delay, the
// height moves towards the commanded height, and the camera needs time per photo.
// The app's debug build also uses it, for the screen tour (Veldvlucht/ScreenTour.swift).
#if SWIFT_PACKAGE
@testable import VeldvluchtKern
#endif
import Foundation

#if DEBUG || SWIFT_PACKAGE
final class FakeDrone: DroneControl {
    /// How this drone moves for raw pitch and roll. A real drone may differ from DJI's text.
    var mapping = AxisMapping.documented
    var simulatorActive = true
    var connected = true
    var batteryPercent = 90
    var batteryNeededToGoHome = 12
    var satellites = 12
    var gpsLevel: Int? = 5
    var homePointSet = true
    var windWarning = 0
    var seriousLowBattery = false
    /// Constant wind pushing the drone (m/s, x = east, y = north).
    var wind = XY(x: 0, y: 0)
    /// Seconds before switching Virtual Stick on or off is confirmed.
    var enableDelay = 0.0
    var disableDelay = 0.0
    /// How many times switching Virtual Stick off fails first.
    var failDisableCount = 0
    /// Shot numbers (1, 2, ...) whose new file the camera does not report.
    var unreportedFiles: Set<Int> = []
    /// Shot numbers where the camera reports an error although the photo is taken.
    var falseErrors: Set<Int> = []
    var gpsLost = false
    /// At the end of going home, wait 0.3 m above the ground until the pilot lands.
    var waitsForLandingConfirmation = false
    /// The drone refuses to stop going home or landing.
    var refusesCancel = false
    /// The drone accepts the take-off command but stays on the ground.
    var ignoresTakeOff = false

    private(set) var now = Date(timeIntervalSince1970: 1_793_000_000)
    private(set) var position: XY
    private(set) var velocity = XY(x: 0, y: 0)
    private(set) var altitude = 0.0
    private(set) var heading = 0.0
    private(set) var flying = false
    private(set) var motorsOn = false
    private(set) var virtualStick = false
    private(set) var goingHome = false
    private(set) var sendCount = 0
    /// Where the drone was each time the camera took a photo.
    private(set) var shots: [(time: Date, position: XY)] = []

    weak var flight: RouteFlight?
    let projection: LocalProjection
    private var lastSticks: StickValues?
    private var lastSendTime: Date?
    private var events: [(time: Date, action: () -> Void)] = []
    private var fileNumber = 0

    init(projection: LocalProjection, start: XY = XY(x: 0, y: 0)) {
        self.projection = projection
        position = start
    }

    func telemetry() -> DroneTelemetry {
        DroneTelemetry(
            time: now,
            connected: connected,
            simulatorActive: simulatorActive,
            position: gpsLost ? nil : projection.toLatLng(position),
            satelliteCount: satellites,
            altitudeM: altitude,
            headingDeg: heading,
            // DJI reports the velocity over the ground (GPS), so including the wind.
            velocityNorth: velocity.y + (flying ? wind.y : 0),
            velocityEast: velocity.x + (flying ? wind.x : 0),
            isFlying: flying,
            motorsOn: motorsOn,
            batteryPercent: batteryPercent,
            batteryNeededToGoHome: batteryNeededToGoHome,
            gpsLevel: gpsLevel,
            homePointSet: homePointSet,
            windWarning: windWarning,
            seriousLowBattery: seriousLowBattery,
            droneReturningHome: goingHome,
            droneLanding: landing,
            landingConfirmationNeeded: landing && waitsForLandingConfirmation && altitude <= 0.3 + 1e-6
        )
    }

    /// The last part of going home: above the take-off point, coming down.
    var landing: Bool { flying && goingHome && hypot(position.x, position.y) <= 0.5 }

    func step(_ dt: Double) {
        now = now.addingTimeInterval(dt)
        let due = events.filter { $0.time <= now }
        events.removeAll { $0.time <= now }
        due.forEach { $0.action() }

        var target = XY(x: 0, y: 0)
        var targetAltitude = altitude
        if flying, goingHome {
            let distance = hypot(position.x, position.y)
            // DJI's own return flies over the ground with GPS, so it cancels the wind.
            if distance > 0.5 {
                target = XY(x: -position.x / distance * min(5, distance) - wind.x,
                            y: -position.y / distance * min(5, distance) - wind.y)
            } else {
                target = XY(x: -wind.x, y: -wind.y)
                targetAltitude = waitsForLandingConfirmation ? 0.3 : 0
            }
        } else if flying, virtualStick, let sticks = lastSticks, let sent = lastSendTime, now.timeIntervalSince(sent) < 0.5 {
            // DJI: without fresh commands the drone hovers.
            target = XY(x: mapping.pitch.x * sticks.pitch + mapping.roll.x * sticks.roll,
                        y: mapping.pitch.y * sticks.pitch + mapping.roll.y * sticks.roll)
            targetAltitude = sticks.altitudeM
            heading = (heading + sticks.yawRate * dt + 360).truncatingRemainder(dividingBy: 360)
        }
        if flying {
            let k = min(1, dt / 0.4)
            velocity = XY(x: velocity.x + (target.x - velocity.x) * k, y: velocity.y + (target.y - velocity.y) * k)
            position = XY(x: position.x + (velocity.x + wind.x) * dt, y: position.y + (velocity.y + wind.y) * dt)
            altitude += max(-2 * dt, min(2 * dt, targetAltitude - altitude))
            if goingHome, altitude <= 0.05, hypot(position.x, position.y) <= 0.5 {
                altitude = 0
                velocity = XY(x: 0, y: 0)
                flying = false
                motorsOn = false
                goingHome = false
            }
        }
    }

    /// The pilot flies the drone down and switches the motors off.
    func landByPilot() {
        virtualStick = false
        altitude = 0
        velocity = XY(x: 0, y: 0)
        flying = false
        motorsOn = false
    }

    /// The drone decides to go home by itself, as on low battery or the RC button.
    func startOwnReturn() {
        virtualStick = false
        goingHome = true
    }

    /// The pilot stops the return with the pause button on the remote controller: it hovers.
    func stopOwnReturn() {
        goingHome = false
    }

    private func after(_ seconds: Double, _ action: @escaping () -> Void) {
        events.append((now.addingTimeInterval(seconds), action))
    }

    // MARK: DroneControl

    func prepareForRoute(goHomeHeightM: Double, completion: @escaping (Error?) -> Void) {
        completion(nil)
    }

    func takeOff(completion: @escaping (Error?) -> Void) {
        guard !ignoresTakeOff else { return completion(nil) }
        motorsOn = true
        after(1.0) { [self] in
            flying = true
            altitude = 1.2
            completion(nil)
        }
    }

    func setVirtualStick(enabled: Bool, completion: @escaping (Error?) -> Void) {
        if !enabled, failDisableCount > 0 {
            failDisableCount -= 1
            completion(FlightError(message: "geen antwoord"))
            return
        }
        let delay = enabled ? enableDelay : disableDelay
        guard delay > 0 else {
            virtualStick = enabled
            completion(nil)
            return
        }
        after(delay) { [self] in
            virtualStick = enabled
            completion(nil)
        }
    }

    /// A gust pushes the drone.
    func nudge(_ push: XY) {
        velocity = XY(x: velocity.x + push.x, y: velocity.y + push.y)
    }

    func send(_ sticks: StickValues) {
        sendCount += 1
        lastSticks = sticks
        lastSendTime = now
    }

    func shootPhoto(completion: @escaping (Error?) -> Void) {
        if let last = shots.last, now.timeIntervalSince(last.time) < 1.5 {
            completion(FlightError(message: "camera bezig"))
            return
        }
        shots.append((now, position))
        let shotNumber = shots.count
        completion(falseErrors.contains(shotNumber) ? FlightError(message: "time-out") : nil)
        after(0.6) { [self] in
            fileNumber += 1
            if !unreportedFiles.contains(shotNumber) {
                flight?.photoSaved(fileName: String(format: "DJI_%04d.JPG", fileNumber))
            }
        }
    }

    func goHome(completion: @escaping (Error?) -> Void) {
        virtualStick = false
        goingHome = true
        completion(nil)
    }

    /// While landing this times out, like DJI's cancelGoHome in the simulator on 2 November 2026.
    func cancelGoHome(completion: @escaping (Error?) -> Void) {
        guard !refusesCancel, !landing else {
            after(2) { completion(FlightError(message: "time-out")) }
            return
        }
        goingHome = false
        completion(nil)
    }

    func confirmLanding(completion: @escaping (Error?) -> Void) {
        guard landing, waitsForLandingConfirmation else { return completion(FlightError(message: "niet aan het landen")) }
        waitsForLandingConfirmation = false
        completion(nil)
    }

    func cancelLanding(completion: @escaping (Error?) -> Void) {
        guard !refusesCancel, landing else {
            after(2) { completion(FlightError(message: "time-out")) }
            return
        }
        goingHome = false
        completion(nil)
    }
}
#endif
