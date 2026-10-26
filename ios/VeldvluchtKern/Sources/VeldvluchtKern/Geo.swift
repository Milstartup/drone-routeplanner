// Geometry for one field. Same formulas as the planner (src/core/geo.ts): haversine for
// distances on the earth, a local flat projection in metres for shapes.
import Foundation

/// WGS84 coordinate in decimal degrees (EPSG:4326).
struct LatLng: Codable, Equatable, Hashable {
    var lat: Double
    var lng: Double

    var isValid: Bool {
        lat.isFinite && lng.isFinite && (-90...90).contains(lat) && (-180...180).contains(lng)
    }
}

/// Local flat coordinate in metres (x = east, y = north).
struct XY: Equatable {
    var x: Double
    var y: Double
}

enum Geo {
    static let earthRadiusM = 6_371_008.8
    static let deg = Double.pi / 180

    static func distanceM(_ a: LatLng, _ b: LatLng) -> Double {
        let dLat = (b.lat - a.lat) * deg
        let dLng = (b.lng - a.lng) * deg
        let s = pow(sin(dLat / 2), 2) + cos(a.lat * deg) * cos(b.lat * deg) * pow(sin(dLng / 2), 2)
        return 2 * earthRadiusM * asin(min(1, s.squareRoot()))
    }

    static func pathLengthM(_ points: [LatLng]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + distanceM($1.0, $1.1) }
    }

    /// Compass bearing from a to b in degrees (0 = north, 90 = east).
    static func bearingDeg(_ a: LatLng, _ b: LatLng) -> Double {
        let phi1 = a.lat * deg
        let phi2 = b.lat * deg
        let dLng = (b.lng - a.lng) * deg
        let y = sin(dLng) * cos(phi2)
        let x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(dLng)
        return (atan2(y, x) / deg + 360).truncatingRemainder(dividingBy: 360)
    }

    static func centroid(_ points: [LatLng]) -> LatLng {
        guard !points.isEmpty else { return LatLng(lat: 0, lng: 0) }
        let n = Double(points.count)
        return LatLng(lat: points.map(\.lat).reduce(0, +) / n, lng: points.map(\.lng).reduce(0, +) / n)
    }

    static func polygonAreaM2(_ points: [LatLng]) -> Double {
        guard points.count >= 3 else { return 0 }
        let projection = LocalProjection(origin: centroid(points))
        return polygonAreaXY(points.map(projection.toXY))
    }

    static func pointInPolygon(_ p: XY, _ poly: [XY]) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in poly.indices {
            let a = poly[i]
            let b = poly[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    static func distancePointToSegment(_ p: XY, _ a: XY, _ b: XY) -> Double {
        let ex = b.x - a.x
        let ey = b.y - a.y
        let len2 = ex * ex + ey * ey
        let t = len2 == 0 ? 0 : max(0, min(1, ((p.x - a.x) * ex + (p.y - a.y) * ey) / len2))
        return hypot(p.x - (a.x + t * ex), p.y - (a.y + t * ey))
    }

    static func distanceToPolygonEdges(_ p: XY, _ poly: [XY]) -> Double {
        poly.indices.map { distancePointToSegment(p, poly[$0], poly[($0 + 1) % poly.count]) }.min() ?? .infinity
    }

    /// Straight interpolation in degrees; fine for the short legs inside one field.
    static func interpolate(_ a: LatLng, _ b: LatLng, _ f: Double) -> LatLng {
        LatLng(lat: a.lat + (b.lat - a.lat) * f, lng: a.lng + (b.lng - a.lng) * f)
    }

    static func polygonAreaXY(_ poly: [XY]) -> Double {
        var twice = 0.0
        for i in poly.indices {
            let a = poly[i]
            let b = poly[(i + 1) % poly.count]
            twice += a.x * b.y - b.x * a.y
        }
        return abs(twice) / 2
    }

    private static func cross(_ o: XY, _ a: XY, _ b: XY) -> Double {
        (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
    }

    private static func onSegment(_ a: XY, _ b: XY, _ p: XY) -> Bool {
        min(a.x, b.x) - 1e-9 <= p.x && p.x <= max(a.x, b.x) + 1e-9
            && min(a.y, b.y) - 1e-9 <= p.y && p.y <= max(a.y, b.y) + 1e-9
    }

    /// True when segments p1-p2 and p3-p4 cross or touch.
    static func segmentsIntersect(_ p1: XY, _ p2: XY, _ p3: XY, _ p4: XY) -> Bool {
        let d1 = cross(p3, p4, p1)
        let d2 = cross(p3, p4, p2)
        let d3 = cross(p1, p2, p3)
        let d4 = cross(p1, p2, p4)
        if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) {
            return true
        }
        let eps = 1e-9
        return (abs(d1) < eps && onSegment(p3, p4, p1))
            || (abs(d2) < eps && onSegment(p3, p4, p2))
            || (abs(d3) < eps && onSegment(p1, p2, p3))
            || (abs(d4) < eps && onSegment(p1, p2, p4))
    }

    /// True only when the segments cross in their interiors (touching does not count).
    private static func properlyCross(_ p1: XY, _ p2: XY, _ p3: XY, _ p4: XY) -> Bool {
        let eps = 1e-9
        return cross(p3, p4, p1) * cross(p3, p4, p2) < -eps && cross(p1, p2, p3) * cross(p1, p2, p4) < -eps
    }

    /// The indexes of the first two non-neighbouring edges that intersect (edge i runs from
    /// point i to point i + 1), or nil when the polygon is simple.
    static func findSelfIntersection(_ poly: [XY]) -> (Int, Int)? {
        let n = poly.count
        guard n >= 4 else { return nil }
        for i in 0..<n {
            for j in (i + 1)..<n {
                let neighbours = j == i + 1 || (i == 0 && j == n - 1)
                if neighbours { continue }
                if segmentsIntersect(poly[i], poly[(i + 1) % n], poly[j], poly[(j + 1) % n]) { return (i, j) }
            }
        }
        return nil
    }

    /// True when segment a-b stays inside the polygon (its ends may touch the boundary).
    static func segmentInsidePolygon(_ a: XY, _ b: XY, _ poly: [XY]) -> Bool {
        for i in poly.indices where properlyCross(a, b, poly[i], poly[(i + 1) % poly.count]) {
            return false
        }
        for f in [0.25, 0.5, 0.75] {
            let p = XY(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
            if !pointInPolygon(p, poly), distanceToPolygonEdges(p, poly) > 1e-6 { return false }
        }
        return true
    }
}

/// Equirectangular projection around an origin; error stays far below 0.1 % within a few km.
struct LocalProjection {
    let origin: LatLng
    private let kLat: Double
    private let kLng: Double

    init(origin: LatLng) {
        self.origin = origin
        kLat = Geo.earthRadiusM * Geo.deg
        kLng = kLat * cos(origin.lat * Geo.deg)
    }

    func toXY(_ p: LatLng) -> XY {
        XY(x: (p.lng - origin.lng) * kLng, y: (p.lat - origin.lat) * kLat)
    }

    func toLatLng(_ p: XY) -> LatLng {
        LatLng(lat: origin.lat + p.y / kLat, lng: origin.lng + p.x / kLng)
    }
}
