// A fake drone for the flight tests (docs/DJI-MOBILE-SDK-V4.md, 6.1: "test bijna alles met
// een nep-drone"). Simple physics: the velocity follows the stick command with a delay, the
// height moves towards the commanded height, and the camera needs time per photo.
@testable import VeldvluchtKern
import Foundation

final class FakeDrone: DroneControl {
    /// How this drone moves for raw pitch and roll. A real drone may differ from DJI's text.
    var mapping = AxisMapping.documented
    var simulatorActive = true
    var connected = true
    var batteryPercent = 90
    var batteryNeededToGoHome = 12
    var satellites = 12
    /// Constant wind pushing the drone (m/s, x = east, y = north).
    var wind = XY(x: 0, y: 0)

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
            position: projection.toLatLng(position),
            satelliteCount: satellites,
            altitudeM: altitude,
            headingDeg: heading,
            // DJI reports the velocity over the ground (GPS), so including the wind.
            velocityNorth: velocity.y + (flying ? wind.y : 0),
            velocityEast: velocity.x + (flying ? wind.x : 0),
            isFlying: flying,
            motorsOn: motorsOn,
            batteryPercent: batteryPercent,
            batteryNeededToGoHome: batteryNeededToGoHome
        )
    }

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
                targetAltitude = 0
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

    private func after(_ seconds: Double, _ action: @escaping () -> Void) {
        events.append((now.addingTimeInterval(seconds), action))
    }

    // MARK: DroneControl

    func prepareForRoute(goHomeHeightM: Double, completion: @escaping (Error?) -> Void) {
        completion(nil)
    }

    func takeOff(completion: @escaping (Error?) -> Void) {
        motorsOn = true
        after(1.0) { [self] in
            flying = true
            altitude = 1.2
            completion(nil)
        }
    }

    func setVirtualStick(enabled: Bool, completion: @escaping (Error?) -> Void) {
        virtualStick = enabled
        completion(nil)
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
        completion(nil)
        after(0.6) { [self] in
            fileNumber += 1
            flight?.photoSaved(fileName: String(format: "DJI_%04d.JPG", fileNumber))
        }
    }

    func goHome(completion: @escaping (Error?) -> Void) {
        virtualStick = false
        goingHome = true
        completion(nil)
    }

    func cancelGoHome(completion: @escaping (Error?) -> Void) {
        goingHome = false
        completion(nil)
    }
}
