// Makes the route for a field in the app, the same way as the planner: parallel flight lines
// inside the boundary (src/core/coverage.ts), a photo every speed × interval metres
// (photos.ts), the time model (timeline.ts, estimate.ts) and the route file with its
// `derived` block (planFile.ts). Tap a few corners, and this gives the route to fly.
//
// The planner's reference files docs/voorbeelden/voorbeeld-veld*.routeplan.json are made by
// the planner itself; FieldPlannerTests checks that this port gives the same route.
import Foundation

/// What you draw in the app: the corners of the field, the take-off point and the settings.
struct FieldPlanInput: Equatable {
    var name: String
    var boundary: [LatLng]
    var home: LatLng?
    var settings: RoutePlanFile.Settings = .planner
    var assumptions: RoutePlanFile.Assumptions = .planner
}

enum FieldPlanner {
    /// Pieces of a flight line shorter than this are dropped.
    static let minLineLengthM = 1.0
    static let maxScanLines = 2000
    /// Safety cap, as in the planner.
    static let maxPhotos = 20_000
    /// A photo due within this distance after the end of a leg is still taken at the end.
    static let endToleranceM = 0.1
    static let minBoundaryAreaM2 = 100.0
    static let largeFieldWarningM2 = 50 * 10_000.0
    static let maxFieldExtentM = 5000.0

    static let notice = "Planningsbestand van de drone-routeplanner (prototype). Dit is GEEN DJI-missiebestand en kan niet rechtstreeks door een DJI-drone of DJI-app worden uitgevoerd. Een toekomstige drone-app moet de route zelf inlezen, opnieuw controleren en omzetten naar eigen commando's."

    struct Leg: Equatable {
        var from: LatLng
        var to: LatLng
        /// Photos are planned on this leg.
        var capture: Bool
    }

    struct Coverage: Equatable {
        var waypoints: [LatLng]
        /// legs[i] goes from waypoints[i] to waypoints[i + 1].
        var legs: [Leg]
        /// Number of straight photo lines (a concave field can have several per scan line).
        var lineCount: Int
        var angleDeg: Double
        /// Transits between lines that leave the field (concave fields).
        var transitsOutside: Int
    }

    struct Photo: Equatable {
        var index: Int
        var legIndex: Int
        /// 0...1 along the leg.
        var legFraction: Double
        var position: LatLng
    }

    struct Estimate: Equatable {
        var totalDistanceM: Double
        var flightTimeS: Double
        var photoCount: Int
        var photoSpacingM: Double
        var fieldAreaM2: Double?
    }

    /// Everything the field drawing screen shows while you draw.
    struct Result {
        var coverage: Coverage
        var photos: [Photo]
        var estimate: Estimate
        var issues: [RouteIssue]
        var file: RoutePlanFile

        var hasErrors: Bool { issues.contains { $0.level == .error } }
    }

    // MARK: - One call

    /// The route, the photos, the estimate, the checks and the route file for a field.
    static func plan(_ input: FieldPlanInput, createdAt: Date = Date()) -> Result {
        var coverage = Coverage(waypoints: [], legs: [], lineCount: 0, angleDeg: input.settings.lineAngleDeg ?? 0, transitsOutside: 0)
        if input.boundary.count >= 3, !crossesItself(input.boundary) {
            coverage = self.coverage(boundary: input.boundary, lineSpacingM: input.settings.lineSpacingM,
                                     lineAngleDeg: input.settings.lineAngleDeg, edgeMarginM: input.settings.edgeMarginM,
                                     start: input.home)
        }
        let photos = self.photos(legs: coverage.legs, spacingM: input.settings.speedMps * input.settings.photoIntervalS)
        let estimate = self.estimate(input, coverage: coverage, photos: photos)
        let file = makeFile(input, coverage: coverage, photos: photos, estimate: estimate, createdAt: createdAt)
        var issues = boundaryIssues(input.boundary)
        if !issues.contains(where: { $0.level == .error }) {
            if coverage.lineCount == 0 {
                issues.append(RouteIssue(level: .error, code: "no-lines", message: "Er passen geen vliegbanen in het veld met deze baanafstand en randmarge. Verklein de randmarge of de baanafstand."))
            } else {
                issues += RouteCheck.check(file).filter { $0.code != "estimate-mismatch" }
            }
            if coverage.transitsOutside > 0 {
                issues.append(RouteIssue(level: .warning, code: "transit-outside", message: "\(coverage.transitsOutside) overgang(en) tussen vliegbanen lopen buiten de veldgrens. Controleer die plekken op obstakels of kies een andere baanrichting."))
            }
        }
        return Result(coverage: coverage, photos: photos, estimate: estimate, issues: issues, file: file)
    }

    // MARK: - Field boundary

    static func crossesItself(_ boundary: [LatLng]) -> Bool {
        guard boundary.count >= 4 else { return false }
        let projection = LocalProjection(origin: Geo.centroid(boundary))
        return Geo.findSelfIntersection(boundary.map(projection.toXY)) != nil
    }

    /// The planner's checks on the field boundary (src/core/validate.ts, validateBoundary).
    static func boundaryIssues(_ b: [LatLng]) -> [RouteIssue] {
        var issues: [RouteIssue] = []
        func add(_ level: RouteIssue.Level, _ code: String, _ message: String) {
            issues.append(RouteIssue(level: level, code: code, message: message))
        }
        guard b.count >= 3 else {
            add(.error, "boundary-too-few", "Tik minstens 3 hoeken van je veld aan.")
            return issues
        }
        for i in b.indices {
            let j = (i + 1) % b.count
            if Geo.distanceM(b[i], b[j]) < RouteLimits.duplicatePointM {
                add(.error, "boundary-duplicate", "Hoek \(i + 1) en \(j + 1) liggen op dezelfde plek. Verwijder er één.")
            }
        }
        let projection = LocalProjection(origin: Geo.centroid(b))
        let poly = b.map(projection.toXY)
        if let (i, j) = Geo.findSelfIntersection(poly) {
            add(.error, "boundary-self-intersect", "De veldgrens kruist zichzelf (lijn \(i + 1)–\((i + 1) % b.count + 1) en lijn \(j + 1)–\((j + 1) % b.count + 1)). Versleep of verwijder een hoek.")
            return issues
        }
        let xs = poly.map(\.x)
        let ys = poly.map(\.y)
        let extent = max((xs.max() ?? 0) - (xs.min() ?? 0), (ys.max() ?? 0) - (ys.min() ?? 0))
        if extent > maxFieldExtentM {
            add(.error, "boundary-extent", "Het veld is \(RouteCheck.meters(extent)) breed. De app is bedoeld voor velden tot \(RouteCheck.meters(maxFieldExtentM)).")
        }
        let area = Geo.polygonAreaXY(poly)
        if area < minBoundaryAreaM2 {
            add(.error, "boundary-small", "Het veld is kleiner dan \(Int(minBoundaryAreaM2)) m².")
        } else if area > largeFieldWarningM2 {
            add(.warning, "boundary-large", "Groot veld (\(hectares(area))): reken op meerdere vluchten en accu's.")
        }
        return issues
    }

    static func hectares(_ m2: Double) -> String {
        String(format: "%.2f ha", m2 / 10_000).replacingOccurrences(of: ".", with: ",")
    }

    // MARK: - Flight lines (coverage.ts)

    private typealias Interval = (lo: Double, hi: Double)

    private struct Piece {
        var y: Double
        var x0: Double
        var x1: Double
    }

    /// Lines have no direction, so bearings are folded into 0..<180.
    static func normalizeLineAngle(_ deg: Double) -> Double {
        let d = deg.truncatingRemainder(dividingBy: 180)
        return d < 0 ? d + 180 : d
    }

    /// Bearing of the longest boundary edge.
    static func autoLineAngleDeg(_ poly: [XY]) -> Double {
        var best = 0.0
        var bestLength = -1.0
        for i in poly.indices {
            let a = poly[i]
            let b = poly[(i + 1) % poly.count]
            let length = hypot(b.x - a.x, b.y - a.y)
            if length > bestLength {
                bestLength = length
                best = atan2(b.x - a.x, b.y - a.y) / Geo.deg
            }
        }
        return normalizeLineAngle(best)
    }

    /// The bearing the lines get for this boundary and setting.
    static func lineAngle(boundary: [LatLng], setting: Double?) -> Double {
        if let setting, setting.isFinite { return normalizeLineAngle(setting) }
        guard boundary.count >= 3 else { return 0 }
        let projection = LocalProjection(origin: Geo.centroid(boundary))
        return autoLineAngleDeg(boundary.map(projection.toXY))
    }

    /// x-range where k * x + m lies in lo...hi.
    private static func linearRange(_ k: Double, _ m: Double, _ lo: Double, _ hi: Double) -> Interval? {
        if abs(k) < 1e-12 { return m >= lo && m <= hi ? (-.infinity, .infinity) : nil }
        let a = (lo - m) / k
        let b = (hi - m) / k
        return a < b ? (a, b) : (b, a)
    }

    /// Part of the horizontal line at height y that is closer than d to segment a-b.
    private static func nearEdgeInterval(_ a: XY, _ b: XY, _ y: Double, _ d: Double) -> Interval? {
        var lo = Double.infinity
        var hi = -Double.infinity
        for p in [a, b] {
            let dy = y - p.y
            if abs(dy) < d {
                let h = (d * d - dy * dy).squareRoot()
                lo = min(lo, p.x - h)
                hi = max(hi, p.x + h)
            }
        }
        let ex = b.x - a.x
        let ey = b.y - a.y
        let length = hypot(ex, ey)
        if length > 1e-9 {
            let ux = ex / length
            let uy = ey / length
            // Along the edge: 0...length. Across the edge: -d...d.
            if let along = linearRange(ux, -a.x * ux + (y - a.y) * uy, 0, length),
               let across = linearRange(-uy, a.x * uy + (y - a.y) * ux, -d, d) {
                let r0 = max(along.lo, across.lo)
                let r1 = min(along.hi, across.hi)
                if r0 < r1 {
                    lo = min(lo, r0)
                    hi = max(hi, r1)
                }
            }
        }
        return lo < hi ? (lo, hi) : nil
    }

    private static func mergeIntervals(_ list: [Interval]) -> [Interval] {
        var out: [Interval] = []
        for interval in list.sorted(by: { $0.lo < $1.lo }) {
            if let last = out.last, interval.lo <= last.hi {
                out[out.count - 1].hi = max(last.hi, interval.hi)
            } else {
                out.append(interval)
            }
        }
        return out
    }

    private static func subtractIntervals(_ from: [Interval], _ blocked: [Interval]) -> [Interval] {
        var out: [Interval] = []
        for (a, b) in from {
            var current = a
            for (c, d) in blocked {
                if d <= current { continue }
                if c >= b { break }
                if c > current { out.append((current, c)) }
                current = max(current, d)
                if current >= b { break }
            }
            if current < b { out.append((current, b)) }
        }
        return out
    }

    /// Inside parts of the horizontal line at height y, at least `margin` away from every edge.
    private static func lineIntervals(_ poly: [XY], _ y: Double, _ margin: Double) -> [Interval] {
        var xs: [Double] = []
        for i in poly.indices {
            let a = poly[i]
            let b = poly[(i + 1) % poly.count]
            if (a.y <= y && b.y > y) || (b.y <= y && a.y > y) {
                xs.append(a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y))
            }
        }
        xs.sort()
        var inside: [Interval] = []
        var i = 0
        while i + 1 < xs.count {
            inside.append((xs[i], xs[i + 1]))
            i += 2
        }
        guard margin > 0 else { return inside }
        let blocked = poly.indices.compactMap { nearEdgeInterval(poly[$0], poly[($0 + 1) % poly.count], y, margin) }
        return subtractIntervals(inside, mergeIntervals(blocked))
    }

    static func coverage(boundary: [LatLng], lineSpacingM spacing: Double, lineAngleDeg: Double?,
                         edgeMarginM: Double, start: LatLng?) -> Coverage {
        let margin = edgeMarginM.isFinite ? max(0, edgeMarginM) : 0
        func empty(_ angle: Double) -> Coverage {
            Coverage(waypoints: [], legs: [], lineCount: 0, angleDeg: angle, transitsOutside: 0)
        }
        guard boundary.count >= 3 else { return empty(lineAngleDeg ?? 0) }

        let projection = LocalProjection(origin: Geo.centroid(boundary))
        let poly = boundary.map(projection.toXY)
        let angleDeg: Double
        if let setting = lineAngleDeg, setting.isFinite {
            angleDeg = normalizeLineAngle(setting)
        } else {
            angleDeg = autoLineAngleDeg(poly)
        }
        guard spacing > 0 else { return empty(angleDeg) }

        // Rotate so that the line direction (bearing) becomes the +x axis.
        let s = sin(angleDeg * Geo.deg)
        let c = cos(angleDeg * Geo.deg)
        func rotate(_ p: XY) -> XY { XY(x: p.x * s + p.y * c, y: -p.x * c + p.y * s) }
        func unrotate(_ p: XY) -> XY { XY(x: p.x * s - p.y * c, y: p.x * c + p.y * s) }
        let rp = poly.map(rotate)

        let ys = rp.map(\.y)
        let inset = max(margin, 0.01)
        let lo = (ys.min() ?? 0) + inset
        let hi = (ys.max() ?? 0) - inset
        var pieces: [Piece] = []
        if hi >= lo {
            let n = min(maxScanLines, Int(((hi - lo) / spacing + 1e-9).rounded(.down)) + 1)
            // Centre the lines in the band so both outer lines sit equally far from the edge.
            let first = lo + (hi - lo - Double(n - 1) * spacing) / 2
            for k in 0..<n {
                let y = first + Double(k) * spacing
                for (x0, x1) in lineIntervals(rp, y, margin) where x1 - x0 >= minLineLengthM {
                    pieces.append(Piece(y: y, x0: x0, x1: x1))
                }
            }
        }
        guard !pieces.isEmpty else { return empty(angleDeg) }

        let ordered = orderPieces(pieces, start: start.map { rotate(projection.toXY($0)) })
        func toLatLng(_ p: XY) -> LatLng { projection.toLatLng(unrotate(p)) }
        var waypoints: [LatLng] = []
        var legs: [Leg] = []
        var transitsOutside = 0
        for (i, segment) in ordered.enumerated() {
            let from = toLatLng(segment.start)
            let to = toLatLng(segment.end)
            if i > 0 {
                if !Geo.segmentInsidePolygon(ordered[i - 1].end, segment.start, rp) { transitsOutside += 1 }
                legs.append(Leg(from: waypoints[waypoints.count - 1], to: from, capture: false))
            }
            waypoints.append(from)
            legs.append(Leg(from: from, to: to, capture: true))
            waypoints.append(to)
        }
        return Coverage(waypoints: waypoints, legs: legs, lineCount: ordered.count, angleDeg: angleDeg,
                        transitsOutside: transitsOutside)
    }

    /// Starts on an outer line (the end nearest to `start`), then always flies to the nearest
    /// free line end. For a convex field this gives the classic back-and-forth pattern.
    private static func orderPieces(_ pieces: [Piece], start: XY?) -> [(start: XY, end: XY)] {
        func ends(_ p: Piece) -> (XY, XY) { (XY(x: p.x0, y: p.y), XY(x: p.x1, y: p.y)) }
        let minY = pieces.map(\.y).min() ?? 0
        let maxY = pieces.map(\.y).max() ?? 0
        let outer = pieces.indices.filter { abs(pieces[$0].y - minY) < 1e-6 || abs(pieces[$0].y - maxY) < 1e-6 }

        var firstIndex = outer[0]
        var firstReversed = false
        if let start {
            var best = Double.infinity
            for i in outer {
                let (a, b) = ends(pieces[i])
                let da = hypot(a.x - start.x, a.y - start.y)
                let db = hypot(b.x - start.x, b.y - start.y)
                if da < best {
                    best = da
                    firstIndex = i
                    firstReversed = false
                }
                if db < best {
                    best = db
                    firstIndex = i
                    firstReversed = true
                }
            }
        }

        var used = [Bool](repeating: false, count: pieces.count)
        var result: [(start: XY, end: XY)] = []
        func take(_ i: Int, _ reversed: Bool) {
            used[i] = true
            let (a, b) = ends(pieces[i])
            result.append(reversed ? (b, a) : (a, b))
        }
        take(firstIndex, firstReversed)
        while result.count < pieces.count {
            let position = result[result.count - 1].end
            var bestIndex = -1
            var bestReversed = false
            var best = Double.infinity
            for i in pieces.indices where !used[i] {
                let (a, b) = ends(pieces[i])
                let da = hypot(a.x - position.x, a.y - position.y)
                let db = hypot(b.x - position.x, b.y - position.y)
                if da < best {
                    best = da
                    bestIndex = i
                    bestReversed = false
                }
                if db < best {
                    best = db
                    bestIndex = i
                    bestReversed = true
                }
            }
            take(bestIndex, bestReversed)
        }
        return result
    }

    // MARK: - Photos (photos.ts)

    /// A photo every `spacingM` metres on legs with photos. A run of photo legs counts as one
    /// stretch, so a corner gives no double photo; every new stretch starts with a photo.
    static func photos(legs: [Leg], spacingM: Double) -> [Photo] {
        var photos: [Photo] = []
        guard spacingM > 0 else { return photos }
        var inRun = false
        var runDistance = 0.0
        var nextAt = 0.0
        for (legIndex, leg) in legs.enumerated() {
            guard leg.capture else {
                inRun = false
                continue
            }
            if !inRun {
                inRun = true
                runDistance = 0
                nextAt = 0
            }
            let length = Geo.distanceM(leg.from, leg.to)
            while nextAt <= runDistance + length + endToleranceM, photos.count < maxPhotos {
                let f = length > 0 ? min(1, max(0, (nextAt - runDistance) / length)) : 0
                photos.append(Photo(index: photos.count, legIndex: legIndex, legFraction: f,
                                    position: Geo.interpolate(leg.from, leg.to, f)))
                nextAt += spacingM
            }
            runDistance += length
        }
        return photos
    }

    // MARK: - Estimate (timeline.ts, estimate.ts)

    static func estimate(_ input: FieldPlanInput, coverage: Coverage, photos: [Photo]) -> Estimate {
        let s = input.settings
        let a = input.assumptions
        let waypoints = coverage.waypoints
        var distance = 0.0
        var time = 0.0
        if let first = waypoints.first, let last = waypoints.last, s.speedMps > 0, s.altitudeM > 0 {
            let v = s.speedMps
            let pause = max(0, a.waypointPauseS)
            func fly(_ from: LatLng, _ to: LatLng) {
                let d = Geo.distanceM(from, to)
                distance += d
                time += d / v
            }
            if let home = input.home {
                time += s.altitudeM / a.ascentSpeedMps
                fly(home, first)
                time += pause
            }
            for (i, leg) in coverage.legs.enumerated() {
                fly(leg.from, leg.to)
                if pause > 0, i < coverage.legs.count - 1 || input.home != nil { time += pause }
            }
            if let home = input.home {
                fly(last, home)
                time += s.altitudeM / a.descentSpeedMps
            }
        }
        return Estimate(totalDistanceM: distance, flightTimeS: time, photoCount: photos.count,
                        photoSpacingM: s.speedMps * s.photoIntervalS,
                        fieldAreaM2: input.boundary.count >= 3 ? Geo.polygonAreaM2(input.boundary) : nil)
    }

    // MARK: - Route file (planFile.ts)

    /// JavaScript's Math.round, so the numbers match the planner's file exactly.
    private static func round(_ value: Double, _ decimals: Double) -> Double {
        (value * decimals + 0.5).rounded(.down) / decimals
    }

    private static func rounded(_ p: LatLng) -> LatLng {
        LatLng(lat: round(p.lat, 1e7), lng: round(p.lng, 1e7))
    }

    static func makeFile(_ input: FieldPlanInput, coverage: Coverage, photos: [Photo], estimate: Estimate,
                         createdAt: Date) -> RoutePlanFile {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let derived = RoutePlanFile.Derived(
            waypoints: coverage.waypoints.enumerated().map {
                let p = rounded($0.element)
                return RoutePlanFile.Waypoint(index: $0.offset, lat: p.lat, lng: p.lng, altitudeM: input.settings.altitudeM)
            },
            legs: coverage.legs.enumerated().map { RoutePlanFile.Leg(from: $0.offset, to: $0.offset + 1, capture: $0.element.capture) },
            photoPoints: photos.map {
                let p = rounded($0.position)
                return RoutePlanFile.PhotoPoint(index: $0.index, lat: p.lat, lng: p.lng, legIndex: $0.legIndex)
            },
            estimate: RoutePlanFile.Estimate(
                totalDistanceM: round(estimate.totalDistanceM, 100),
                flightTimeS: round(estimate.flightTimeS, 100),
                photoCount: estimate.photoCount,
                photoSpacingM: round(estimate.photoSpacingM, 100),
                fieldAreaM2: estimate.fieldAreaM2.map { round($0, 100) }
            )
        )
        return RoutePlanFile(name: input.name, mode: .field, settings: input.settings, assumptions: input.assumptions,
                             home: input.home.map(rounded), boundary: input.boundary.map(rounded), routePoints: [],
                             derived: derived, createdAt: formatter.string(from: createdAt), notice: notice)
    }
}
