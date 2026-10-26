// Which way the drone moves for the raw Virtual Stick values pitch and roll (velocity mode,
// ground coordinate system). DJI's header says pitch = east and roll = north, but DJI's
// guide and sample code seem to disagree (docs/DJI-MOBILE-SDK-V4.md, 6.2). So every flight
// first measures it: a short move with pitch only, then with roll only.
import Foundation

struct AxisMapping: Equatable {
    /// Direction (x = east, y = north, length 1) the drone moves for pitch +1 m/s.
    var pitch: XY
    /// Direction the drone moves for roll +1 m/s.
    var roll: XY

    /// What DJIFlightControllerBaseTypes.h says for the ground coordinate system.
    static let documented = AxisMapping(pitch: XY(x: 1, y: 0), roll: XY(x: 0, y: 1))

    /// Raw stick values for a velocity to the east and north (m/s).
    func sticks(east: Double, north: Double) -> (pitch: Double, roll: Double) {
        (east * pitch.x + north * pitch.y, east * roll.x + north * roll.y)
    }

    /// "pitch = oost, roll = noord"
    var description: String {
        "pitch = \(Self.name(pitch)), roll = \(Self.name(roll))"
    }

    /// Works out the mapping from how far the drone moved (in metres) after a pitch-only
    /// and a roll-only command. Each move must clearly go along one compass axis, and the
    /// two must be at right angles; anything else stops the flight before the route.
    static func measure(pitchMove: XY, rollMove: XY, minimumM: Double = 0.5) throws -> AxisMapping {
        let pitch = try axis(of: pitchMove, minimumM: minimumM, what: "pitch")
        let roll = try axis(of: rollMove, minimumM: minimumM, what: "roll")
        guard pitch.x * roll.x + pitch.y * roll.y == 0 else {
            throw FlightError(message: "Richtingtest mislukt: pitch en roll bewogen de drone allebei naar het \(name(pitch)).")
        }
        return AxisMapping(pitch: pitch, roll: roll)
    }

    private static func axis(of move: XY, minimumM: Double, what: String) throws -> XY {
        let length = hypot(move.x, move.y)
        guard length >= minimumM else {
            throw FlightError(message: "Richtingtest mislukt: met alleen \(what) bewoog de drone maar \(String(format: "%.1f", length)) m.")
        }
        // Within 30 degrees of one compass axis.
        let major = max(abs(move.x), abs(move.y))
        let minor = min(abs(move.x), abs(move.y))
        guard minor <= major * tan(30 * Geo.deg) else {
            throw FlightError(message: "Richtingtest mislukt: met alleen \(what) bewoog de drone schuin (\(Int(FlightPlan.Leg.bearing(from: XY(x: 0, y: 0), to: move).rounded()))°).")
        }
        return abs(move.x) >= abs(move.y) ? XY(x: move.x > 0 ? 1 : -1, y: 0) : XY(x: 0, y: move.y > 0 ? 1 : -1)
    }

    private static func name(_ axis: XY) -> String {
        switch (axis.x, axis.y) {
        case (1, 0): return "oost"
        case (-1, 0): return "west"
        case (0, 1): return "noord"
        default: return "zuid"
        }
    }
}
