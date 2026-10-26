// A field you drew in the app: its corners, the take-off point, the flight settings and the
// soil sensors placed in it. The app keeps one file per field; the route file for the drone
// is made from it with FieldPlanner, and FieldStrips cuts it into the strips the tractor
// waters (docs/ARCHITECTUUR.md, chapter 7: advice per strip along the tractor's direction).
import Foundation

struct FieldRecord: Codable, Equatable, Identifiable {
    static let format = "veldvlucht/veld"
    static let version = 0
    /// Until the tractor's real figures are known: the width the water cannons cover.
    static let defaultStripWidthM = 24.0

    var format = FieldRecord.format
    var version = FieldRecord.version
    /// The field id in every data format, such as "broccoli-noord".
    var id: String
    var name: String
    var boundary: [LatLng]
    var home: LatLng?
    var settings: RoutePlanFile.Settings
    var sensors: [FieldSensor] = []
    /// Width of one watering strip along the flight lines (the tractor's direction).
    var stripWidthM = FieldRecord.defaultStripWidthM
    var createdAt: Date
    var updatedAt: Date

    var planInput: FieldPlanInput {
        FieldPlanInput(name: name, boundary: boundary, home: home, settings: settings)
    }

    /// The route for the drone. `updatedAt` is its creation time, so a route keeps the same
    /// identity (and the progress of a half-flown route) until the field changes.
    func plan() -> FieldPlanner.Result {
        FieldPlanner.plan(planInput, createdAt: updatedAt)
    }

    /// The direction of the flight lines, which is also the tractor's direction.
    var lineAngleDeg: Double {
        FieldPlanner.lineAngle(boundary: boundary, setting: settings.lineAngleDeg)
    }

    var areaM2: Double { Geo.polygonAreaM2(boundary) }

    /// "Broccoli noord" → "broccoli-noord"; a number is added when the id is taken.
    static func makeId(for name: String, taken: Set<String>) -> String {
        let base = slug(name)
        var id = base
        var n = 2
        while taken.contains(id) {
            id = "\(base)-\(n)"
            n += 1
        }
        return id
    }

    /// "Broccoli noord (voorbeeld)" → "broccoli-noord-voorbeeld"
    static func slug(_ name: String) -> String {
        let plain = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "nl_NL")).lowercased()
        let parts = plain.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return parts.isEmpty ? "veld" : parts.joined(separator: "-")
    }

    static func read(_ data: Data) throws -> FieldRecord {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(FieldRecord.self, from: data)
        guard record.format == format, record.version == version else {
            throw FileReadError(message: "Dit is geen veld van Veldvlucht (verwacht \"\(format)\" versie \(version)).")
        }
        return record
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}

/// A soil sensor in the field: where it is, and its calibration once it is calibrated.
struct FieldSensor: Codable, Equatable, Identifiable {
    /// The full sensor id, such as "broccoli-noord-s1". The sensor box sends it along.
    var id: String
    var location: LatLng
    var depthCm = 15.0
    var calibration: SensorMeasurement.Calibration?

    /// "s1" for "broccoli-noord-s1".
    func shortName(fieldId: String) -> String {
        id.hasPrefix(fieldId + "-") ? String(id.dropFirst(fieldId.count + 1)) : id
    }
}

extension SensorMeasurement.Calibration {
    /// Moisture between dry (0 %) and saturated (100 %) soil of the field. The school sensor
    /// gives a higher raw value when the soil is drier, so this works both ways round.
    func percent(raw: Double) -> Double? {
        guard dryRaw.isFinite, wetRaw.isFinite, abs(dryRaw - wetRaw) >= 1 else { return nil }
        return min(100, max(0, (raw - dryRaw) / (wetRaw - dryRaw) * 100))
    }
}

// MARK: - Strips and sensor places

enum FieldStrips {
    /// The field cut into strips of `widthM` along `angleDeg`, from one edge to the other.
    /// Each strip is the part of the field between two parallel lines.
    static func strips(boundary: [LatLng], angleDeg: Double, widthM: Double) -> [[LatLng]] {
        guard boundary.count >= 3, widthM > 0 else { return [] }
        let frame = Frame(boundary: boundary, angleDeg: angleDeg)
        let ys = frame.rotated.map(\.y)
        guard let minY = ys.min(), let maxY = ys.max(), maxY > minY else { return [] }
        let count = min(500, Int(((maxY - minY) / widthM).rounded(.up)))
        var strips: [[LatLng]] = []
        for k in 0..<count {
            let y0 = minY + Double(k) * widthM
            let y1 = min(maxY, y0 + widthM)
            let piece = clip(frame.rotated, from: y0, to: y1)
            if piece.count >= 3, Geo.polygonAreaXY(piece) >= 1 {
                strips.append(piece.map(frame.toLatLng))
            }
        }
        return strips
    }

    /// `count` places for sensors, one in the middle of each of `count` equal bands across the
    /// tractor's direction, always inside the field.
    static func sensorPlaces(boundary: [LatLng], angleDeg: Double, count: Int) -> [LatLng] {
        guard boundary.count >= 3, count > 0 else { return [] }
        let frame = Frame(boundary: boundary, angleDeg: angleDeg)
        let ys = frame.rotated.map(\.y)
        guard let minY = ys.min(), let maxY = ys.max(), maxY > minY else { return [] }
        let band = (maxY - minY) / Double(count)
        return (0..<count).compactMap { k in
            let y = minY + (Double(k) + 0.5) * band
            guard let (x0, x1) = longestInside(frame.rotated, y: y) else { return nil }
            return frame.toLatLng(XY(x: (x0 + x1) / 2, y: y))
        }
    }

    /// The field turned so the tractor's direction lies along +x, like FieldPlanner does.
    private struct Frame {
        let projection: LocalProjection
        let s: Double
        let c: Double
        let rotated: [XY]

        init(boundary: [LatLng], angleDeg: Double) {
            projection = LocalProjection(origin: Geo.centroid(boundary))
            s = sin(angleDeg * Geo.deg)
            c = cos(angleDeg * Geo.deg)
            let (s, c) = (s, c)
            rotated = boundary.map(projection.toXY).map { XY(x: $0.x * s + $0.y * c, y: -$0.x * c + $0.y * s) }
        }

        func toLatLng(_ p: XY) -> LatLng {
            projection.toLatLng(XY(x: p.x * s - p.y * c, y: p.x * c + p.y * s))
        }
    }

    /// The polygon between two horizontal lines (Sutherland–Hodgman, one side at a time).
    private static func clip(_ poly: [XY], from y0: Double, to y1: Double) -> [XY] {
        func cut(_ points: [XY], keep: (XY) -> Bool, at y: Double) -> [XY] {
            guard !points.isEmpty else { return [] }
            var out: [XY] = []
            for i in points.indices {
                let a = points[i]
                let b = points[(i + 1) % points.count]
                if keep(a) { out.append(a) }
                if keep(a) != keep(b), b.y != a.y {
                    let t = (y - a.y) / (b.y - a.y)
                    out.append(XY(x: a.x + (b.x - a.x) * t, y: y))
                }
            }
            return out
        }
        return cut(cut(poly, keep: { $0.y >= y0 }, at: y0), keep: { $0.y <= y1 }, at: y1)
    }

    /// The longest inside part of the horizontal line at height y.
    private static func longestInside(_ poly: [XY], y: Double) -> (Double, Double)? {
        var xs: [Double] = []
        for i in poly.indices {
            let a = poly[i]
            let b = poly[(i + 1) % poly.count]
            if (a.y <= y && b.y > y) || (b.y <= y && a.y > y) {
                xs.append(a.x + (y - a.y) * (b.x - a.x) / (b.y - a.y))
            }
        }
        xs.sort()
        var best: (Double, Double)?
        var i = 0
        while i + 1 < xs.count {
            if best == nil || xs[i + 1] - xs[i] > best!.1 - best!.0 { best = (xs[i], xs[i + 1]) }
            i += 2
        }
        return best
    }
}

/// The camera's footprint on the ground (src/core/camera.ts): the Mavic Mini looks straight
/// down; the long side of the photo lies across the flight direction.
enum CameraFootprint {
    static let diagonalFovDeg = 83.0
    static let imageWidthPx = 4000.0
    static let imageHeightPx = 3000.0

    /// Width across and length along the flight direction in metres, and centimetres per pixel.
    static func at(altitudeM: Double) -> (widthM: Double, lengthM: Double, gsdCm: Double)? {
        guard altitudeM > 0 else { return nil }
        let diagonalM = 2 * altitudeM * tan(diagonalFovDeg * Geo.deg / 2)
        let diagonalPx = hypot(imageWidthPx, imageHeightPx)
        let width = diagonalM * imageWidthPx / diagonalPx
        let length = diagonalM * imageHeightPx / diagonalPx
        return (width, length, width / imageWidthPx * 100)
    }

    /// Overlap between neighbouring photos (0.6 = 60 %); negative means a gap.
    static func overlap(footprintM: Double, distanceM: Double) -> Double {
        1 - distanceM / footprintM
    }
}
