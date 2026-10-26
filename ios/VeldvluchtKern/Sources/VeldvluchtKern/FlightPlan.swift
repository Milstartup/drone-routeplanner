// The route as the flight logic uses it: flat coordinates in metres around the take-off
// point, legs with their length and position along the route, and the planned photos.
// Built from a route file that passed RouteCheck without errors.
import Foundation

struct FlightPlan {
    struct Leg {
        let from: XY
        let to: XY
        let capture: Bool
        /// Distance along the route where this leg starts.
        let startAlongM: Double
        let lengthM: Double

        /// Compass bearing of the leg (0 = north, 90 = east).
        var bearingDeg: Double { Self.bearing(from: from, to: to) }

        static func bearing(from a: XY, to b: XY) -> Double {
            let degrees = atan2(b.x - a.x, b.y - a.y) / Geo.deg
            return (degrees + 360).truncatingRemainder(dividingBy: 360)
        }
    }

    struct Photo {
        let index: Int
        let latLng: LatLng
        let position: XY
        let legIndex: Int
        /// Distance along the whole route.
        let alongM: Double
    }

    let name: String
    /// Take-off and landing point: `home` from the file, or else the first waypoint.
    let home: LatLng
    let hasHomeInFile: Bool
    let altitudeM: Double
    let speedMps: Double
    let projection: LocalProjection
    let waypoints: [XY]
    let legs: [Leg]
    let photos: [Photo]

    var lengthM: Double { legs.last.map { $0.startAlongM + $0.lengthM } ?? 0 }

    init(_ file: RoutePlanFile) {
        name = file.name
        let points = file.derived.waypoints.map(\.latLng)
        home = file.home ?? points.first ?? LatLng(lat: 0, lng: 0)
        hasHomeInFile = file.home != nil
        altitudeM = file.settings.altitudeM
        speedMps = file.settings.speedMps
        projection = LocalProjection(origin: home)
        waypoints = points.map(projection.toXY)

        var legs: [Leg] = []
        var along = 0.0
        for leg in file.derived.legs where waypoints.indices.contains(leg.from) && waypoints.indices.contains(leg.to) {
            let a = waypoints[leg.from]
            let b = waypoints[leg.to]
            let length = hypot(b.x - a.x, b.y - a.y)
            legs.append(Leg(from: a, to: b, capture: leg.capture, startAlongM: along, lengthM: length))
            along += length
        }
        self.legs = legs

        let projection = self.projection
        photos = file.derived.photoPoints.compactMap { photo -> Photo? in
            guard legs.indices.contains(photo.legIndex) else { return nil }
            let leg = legs[photo.legIndex]
            let p = projection.toXY(photo.latLng)
            let onLeg = leg.lengthM > 0
                ? ((p.x - leg.from.x) * (leg.to.x - leg.from.x) + (p.y - leg.from.y) * (leg.to.y - leg.from.y)) / leg.lengthM
                : 0
            return Photo(index: photo.index, latLng: photo.latLng, position: p, legIndex: photo.legIndex,
                         alongM: leg.startAlongM + min(max(onLeg, 0), leg.lengthM))
        }
    }

    /// Where `p` lies relative to leg `index`: the distance along the leg from its start
    /// (negative before the start, beyond the length after the end) and the distance
    /// sideways (positive = right of the direction of flight).
    func track(_ p: XY, onLeg index: Int) -> (alongLegM: Double, crossM: Double) {
        let leg = legs[index]
        guard leg.lengthM > 0 else { return (0, 0) }
        let ux = (leg.to.x - leg.from.x) / leg.lengthM
        let uy = (leg.to.y - leg.from.y) / leg.lengthM
        let dx = p.x - leg.from.x
        let dy = p.y - leg.from.y
        // Right of (ux, uy) is (uy, -ux) when x = east and y = north.
        return (dx * ux + dy * uy, dx * uy - dy * ux)
    }

    /// The point on the route at a distance along it, with the leg it lies on.
    func point(alongM: Double) -> (point: XY, legIndex: Int) {
        guard let last = legs.indices.last else { return (waypoints.first ?? XY(x: 0, y: 0), 0) }
        let clamped = min(max(alongM, 0), lengthM)
        let index = legs.lastIndex { $0.startAlongM <= clamped } ?? 0
        let leg = legs[min(index, last)]
        let f = leg.lengthM > 0 ? (clamped - leg.startAlongM) / leg.lengthM : 0
        return (XY(x: leg.from.x + (leg.to.x - leg.from.x) * f, y: leg.from.y + (leg.to.y - leg.from.y) * f), min(index, last))
    }
}
