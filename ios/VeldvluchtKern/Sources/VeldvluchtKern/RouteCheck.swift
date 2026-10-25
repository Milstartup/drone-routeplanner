// Checks a route file again in the app (rule 2 of docs/ROUTEBESTAND.md): the planner's
// rules from src/core/validate.ts, plus checks on the `derived` block the app will fly.
// Errors block flying; warnings are shown but do not block anything.
import Foundation

struct RouteIssue: Identifiable, Equatable {
    enum Level {
        case error
        case warning
    }

    let level: Level
    let code: String
    let message: String

    var id: String { "\(code): \(message)" }
}

enum RouteLimits {
    static let minAltitudeM = 5.0
    static let lowAltitudeWarningM = 15.0
    /// Legal limit in the EU open category.
    static let maxAltitudeM = 120.0
    /// Apps control the Mavic Mini only in P mode, where 8 m/s is the maximum.
    static let maxSpeedMps = 8.0
    static let speedWarningMps = 6.0
    static let minLineSpacingM = 2.0
    /// Stricter than the planner (0.5 s, warning below 2 s): the camera's shortest interval
    /// is 2 s, and the app will not ask for photos faster than that.
    static let minPhotoIntervalS = 2.0
    static let duplicatePointM = 0.5
    /// A planned photo must lie this close to the leg it belongs to.
    static let photoOffLegM = 1.0
    /// Waypoints may differ this much from the route points after rounding to 7 decimals.
    static let pointMatchM = 0.05
    static let manyPhotosWarning = 3000
}

/// Figures the app works out itself from the waypoints, so it does not trust `derived.estimate`.
struct RouteSummary: Equatable {
    var waypointCount: Int
    var photoCount: Int
    /// Along the waypoints, without the flights to and from the take-off point.
    var routeLengthM: Double
    /// Including the flights to and from the take-off point.
    var totalDistanceM: Double
    var flightTimeS: Double
    var maxDistanceFromHomeM: Double?
    var fieldAreaM2: Double?
}

enum RouteCheck {
    static func summary(_ file: RoutePlanFile) -> RouteSummary {
        let waypoints = file.derived.waypoints.map(\.latLng)
        let routeLength = Geo.pathLengthM(waypoints)
        var homeLegs = 0.0
        var maxFromHome: Double?
        if let home = file.home, let first = waypoints.first, let last = waypoints.last {
            homeLegs = Geo.distanceM(home, first) + Geo.distanceM(last, home)
            maxFromHome = waypoints.map { Geo.distanceM(home, $0) }.max()
        }
        return RouteSummary(
            waypointCount: waypoints.count,
            photoCount: file.derived.photoPoints.count,
            routeLengthM: routeLength,
            totalDistanceM: routeLength + homeLegs,
            flightTimeS: flightTimeS(file),
            maxDistanceFromHomeM: maxFromHome,
            fieldAreaM2: file.boundary.count >= 3 ? Geo.polygonAreaM2(file.boundary) : nil
        )
    }

    /// The planner's time model (src/core/timeline.ts): vertical climb, constant speed,
    /// a pause at every waypoint, return to the take-off point and vertical descent.
    static func flightTimeS(_ file: RoutePlanFile) -> Double {
        let waypoints = file.derived.waypoints.map(\.latLng)
        let v = file.settings.speedMps
        let altitude = file.settings.altitudeM
        let a = file.assumptions
        guard let first = waypoints.first, let last = waypoints.last, v > 0, altitude > 0 else { return 0 }
        let pause = max(0, a.waypointPauseS)
        var t = 0.0
        if let home = file.home {
            t += altitude / a.ascentSpeedMps + Geo.distanceM(home, first) / v + pause
        }
        let legCount = waypoints.count - 1
        for i in 0..<max(0, legCount) {
            t += Geo.distanceM(waypoints[i], waypoints[i + 1]) / v
            if i < legCount - 1 || file.home != nil { t += pause }
        }
        if let home = file.home {
            t += Geo.distanceM(last, home) / v + altitude / a.descentSpeedMps
        }
        return t
    }

    static func check(_ file: RoutePlanFile) -> [RouteIssue] {
        var issues: [RouteIssue] = []
        func add(_ level: RouteIssue.Level, _ code: String, _ message: String) {
            issues.append(RouteIssue(level: level, code: code, message: message))
        }

        checkSettings(file, add)
        checkAssumptions(file.assumptions, add)
        let structureOK = checkStructure(file, add)
        if structureOK {
            checkPhotos(file, add)
        }
        checkPlace(file, add)

        let summary = summary(file)
        let a = file.assumptions
        if a.usableFlightTimeS > 0, summary.flightTimeS > a.usableFlightTimeS {
            add(.warning, "battery", "Geschatte vliegtijd (\(minutes(summary.flightTimeS))) is langer dan de bruikbare accutijd (\(minutes(a.usableFlightTimeS))). Verdeel het veld over meerdere vluchten.")
        }
        let stated = file.derived.estimate.totalDistanceM
        if structureOK, abs(stated - summary.totalDistanceM) > max(1, 0.02 * summary.totalDistanceM) {
            add(.warning, "estimate-mismatch", "De afstand in het bestand (\(meters(stated))) klopt niet met de route (\(meters(summary.totalDistanceM))). Is het bestand met de hand aangepast?")
        }
        return issues
    }

    private typealias Add = (RouteIssue.Level, String, String) -> Void

    private static func checkSettings(_ file: RoutePlanFile, _ add: Add) {
        let s = file.settings
        if !s.altitudeM.isFinite || s.altitudeM < RouteLimits.minAltitudeM {
            add(.error, "altitude-low", "Vlieghoogte moet minstens \(number(RouteLimits.minAltitudeM)) m zijn.")
        } else if s.altitudeM > RouteLimits.maxAltitudeM {
            add(.error, "altitude-high", "Vlieghoogte is hoger dan \(number(RouteLimits.maxAltitudeM)) m, de grens in de open categorie van de EU-dronewetgeving.")
        } else if s.altitudeM < RouteLimits.lowAltitudeWarningM {
            add(.warning, "altitude-lowish", "Lage vlieghoogte (onder \(number(RouteLimits.lowAltitudeWarningM)) m): let op bomen, hekken, masten en lijnen rond het veld.")
        }

        if !s.speedMps.isFinite || s.speedMps <= 0 {
            add(.error, "speed-invalid", "Snelheid moet groter dan 0 zijn.")
        } else if s.speedMps > RouteLimits.maxSpeedMps {
            add(.error, "speed-high", "Snelheid is hoger dan \(number(RouteLimits.maxSpeedMps)) m/s, het maximum van de Mavic Mini in de P-stand.")
        } else if s.speedMps > RouteLimits.speedWarningMps {
            add(.warning, "speed-fast", "Snelheid boven \(number(RouteLimits.speedWarningMps)) m/s: weinig marge bij tegenwind en meer kans op onscherpe foto's.")
        }

        if !s.photoIntervalS.isFinite || s.photoIntervalS < RouteLimits.minPhotoIntervalS {
            add(.error, "interval-short", "Foto-interval moet minstens \(number(RouteLimits.minPhotoIntervalS)) s zijn: sneller kan de camera van de Mavic Mini niet. Pas het interval aan in de planner.")
        }

        if file.mode == .field {
            if !s.lineSpacingM.isFinite || s.lineSpacingM < RouteLimits.minLineSpacingM {
                add(.error, "spacing-small", "Baanafstand moet minstens \(number(RouteLimits.minLineSpacingM)) m zijn.")
            }
            if !s.edgeMarginM.isFinite || s.edgeMarginM < 0 {
                add(.error, "margin-invalid", "Randmarge moet 0 of meer zijn.")
            }
        }
    }

    private static func checkAssumptions(_ a: RoutePlanFile.Assumptions, _ add: Add) {
        let positive: [(Double, String)] = [
            (a.ascentSpeedMps, "stijgsnelheid"),
            (a.descentSpeedMps, "daalsnelheid"),
            (a.usableFlightTimeS, "bruikbare vliegtijd"),
            (a.maxDistanceFromHomeM, "maximale afstand tot startpunt"),
        ]
        for (value, label) in positive where !value.isFinite || value <= 0 {
            add(.error, "assumption-invalid", "Aanname \"\(label)\" moet een getal groter dan 0 zijn.")
        }
        if !a.waypointPauseS.isFinite || a.waypointPauseS < 0 {
            add(.error, "assumption-invalid", "Aanname \"pauze per routepunt\" moet 0 of meer zijn.")
        }
    }

    /// Waypoints, legs and their link to the inputs. Returns false when the route itself is unusable.
    private static func checkStructure(_ file: RoutePlanFile, _ add: Add) -> Bool {
        let d = file.derived
        guard d.waypoints.count >= 2 else {
            add(.error, "route-too-few", "Het bestand bevat minder dan 2 routepunten om te vliegen.")
            return false
        }
        if d.waypoints.enumerated().contains(where: { $0.offset != $0.element.index }) {
            add(.error, "waypoint-order", "De routepunten (derived.waypoints) zijn niet doorlopend genummerd.")
            return false
        }
        let legsOK = d.legs.count == d.waypoints.count - 1
            && d.legs.enumerated().allSatisfy { $0.element.from == $0.offset && $0.element.to == $0.offset + 1 }
        if !legsOK {
            add(.error, "legs-mismatch", "De stukken (derived.legs) passen niet bij de routepunten.")
            return false
        }
        if let wrong = d.waypoints.first(where: { abs($0.altitudeM - file.settings.altitudeM) > 0.01 }) {
            add(.error, "waypoint-altitude", "Routepunt \(wrong.index + 1) heeft een andere hoogte (\(number(wrong.altitudeM)) m) dan de vlieghoogte (\(number(file.settings.altitudeM)) m).")
        }

        if file.mode == .route {
            let inputs = file.routePoints
            let same = inputs.count == d.waypoints.count
                && zip(inputs, d.waypoints).allSatisfy { Geo.distanceM($0.latLng, $1.latLng) <= RouteLimits.pointMatchM }
                && zip(inputs, d.legs).allSatisfy { $0.capture == $1.capture }
            if !same {
                add(.error, "derived-mismatch", "De routepunten in \"derived\" komen niet overeen met \"routePoints\". Sla de route opnieuw op in de planner.")
            }
        }

        for i in 1..<d.waypoints.count where Geo.distanceM(d.waypoints[i - 1].latLng, d.waypoints[i].latLng) < RouteLimits.duplicatePointM {
            add(.warning, "route-duplicate", "Routepunt \(i) en \(i + 1) liggen op dezelfde plek.")
        }
        return true
    }

    private static func checkPhotos(_ file: RoutePlanFile, _ add: Add) {
        let d = file.derived
        let photos = d.photoPoints
        guard !photos.isEmpty else {
            add(.warning, "route-no-photos", "Op deze route staan geen foto's gepland.")
            return
        }
        if photos.enumerated().contains(where: { $0.offset != $0.element.index }) {
            add(.error, "photo-order", "De fotoposities (derived.photoPoints) zijn niet doorlopend genummerd.")
            return
        }

        let projection = LocalProjection(origin: d.waypoints[0].latLng)
        let points = d.waypoints.map { projection.toXY($0.latLng) }
        var legStartM = [0.0]
        for i in 1..<points.count {
            legStartM.append(legStartM[i - 1] + hypot(points[i].x - points[i - 1].x, points[i].y - points[i - 1].y))
        }

        var previousAlongM: Double?
        var tooClose = 0
        for photo in photos {
            guard d.legs.indices.contains(photo.legIndex) else {
                add(.error, "photo-leg", "Foto \(photo.index + 1) verwijst naar een stuk dat niet bestaat.")
                return
            }
            guard d.legs[photo.legIndex].capture else {
                add(.error, "photo-leg", "Foto \(photo.index + 1) ligt op een stuk zonder foto's.")
                return
            }
            let p = projection.toXY(photo.latLng)
            let a = points[photo.legIndex]
            let b = points[photo.legIndex + 1]
            if Geo.distancePointToSegment(p, a, b) > RouteLimits.photoOffLegM {
                add(.error, "photo-off-leg", "Foto \(photo.index + 1) ligt niet op de route.")
                return
            }
            let along = legStartM[photo.legIndex] + hypot(p.x - a.x, p.y - a.y)
            if let previous = previousAlongM {
                if along < previous - RouteLimits.photoOffLegM {
                    add(.error, "photo-order", "De foto's staan niet in vliegvolgorde (foto \(photo.index + 1)).")
                    return
                }
                // At the start of a new flight line the gap can be shorter than 2 s of flying.
                if file.settings.speedMps > 0, (along - previous) / file.settings.speedMps < RouteLimits.minPhotoIntervalS - 0.05 {
                    tooClose += 1
                }
            }
            previousAlongM = along
        }
        if tooClose > 0 {
            add(.warning, "photos-close", "\(tooClose) keer liggen twee foto's minder dan \(number(RouteLimits.minPhotoIntervalS)) s vliegen uit elkaar. De app wacht daar later tot de camera klaar is.")
        }
        if d.estimate.photoCount != photos.count {
            add(.warning, "photo-count", "Het bestand noemt \(d.estimate.photoCount) foto's, maar er staan er \(photos.count) gepland.")
        }
        if photos.count > RouteLimits.manyPhotosWarning {
            add(.warning, "photos-many", "\(photos.count) foto's: controleer of de geheugenkaart groot genoeg is.")
        }
    }

    private static func checkPlace(_ file: RoutePlanFile, _ add: Add) {
        let waypoints = file.derived.waypoints.map(\.latLng)
        if let home = file.home {
            if let farthest = waypoints.map({ Geo.distanceM(home, $0) }).max(), farthest > file.assumptions.maxDistanceFromHomeM {
                add(.warning, "home-far", "Het verste routepunt ligt \(meters(farthest)) van het startpunt. Je moet de drone met eigen ogen kunnen zien (aanname: tot \(meters(file.assumptions.maxDistanceFromHomeM))).")
            }
        } else {
            add(.warning, "home-missing", "Er staat geen startpunt in het bestand. Controleer afstand en vliegtijd straks met de echte plek van de drone.")
        }

        guard file.boundary.count >= 3, !waypoints.isEmpty else { return }
        let projection = LocalProjection(origin: Geo.centroid(file.boundary))
        let polygon = file.boundary.map(projection.toXY)
        let outside = waypoints.enumerated().compactMap { offset, point -> Int? in
            let p = projection.toXY(point)
            let inside = Geo.pointInPolygon(p, polygon) || Geo.distanceToPolygonEdges(p, polygon) < 0.5
            return inside ? nil : offset + 1
        }
        if !outside.isEmpty {
            let list = outside.prefix(10).map(String.init).joined(separator: ", ")
            add(.warning, "route-outside-field", "Routepunt \(list)\(outside.count > 10 ? " en meer" : "") ligt buiten de veldgrens.")
        }
    }

    static func number(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")
    }

    static func meters(_ value: Double) -> String {
        value >= 1000 ? String(format: "%.2f km", value / 1000).replacingOccurrences(of: ".", with: ",") : "\(Int(value.rounded())) m"
    }

    static func minutes(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d min", total / 60, total % 60)
    }
}
