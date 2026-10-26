// What a sensor box sends to the app over the iPhone's hotspot (sensor/README.md): its id and
// the measurements it kept, each with how many seconds ago it was made. The box has no clock;
// the app turns `ageS` into a time and adds the place and calibration of the sensor.
// The box numbers its measurements since it was switched on (`boot`, `nr`), so the app can
// skip the ones it already has when a box sends them again.
import Foundation

struct SensorUpload: Codable, Equatable {
    static let format = "veld/sensorupload"
    static let version = 0

    struct Measurement: Codable, Equatable {
        /// Number since the box was switched on; optional.
        var nr: Int?
        /// Seconds between the measurement and the moment the box sent it.
        var ageS: Double
        var raw: Double
        var batteryVolt: Double?
    }

    var format: String
    var version: Int
    var sensorId: String
    var depthCm: Double?
    /// A random id of the box's current start; optional.
    var boot: Int?
    var measurements: [Measurement]

    /// The measurements the app has not received before, and the mark to keep for next time.
    /// Without numbers every measurement counts as new (`numbered` is false).
    func unseen(after mark: UploadMark?) -> (measurements: [Measurement], mark: UploadMark?, numbered: Bool) {
        guard let boot, measurements.allSatisfy({ $0.nr != nil }) else { return (measurements, mark, false) }
        let fresh = mark?.boot == boot ? measurements.filter { $0.nr! > mark!.lastNr } : measurements
        let last = measurements.compactMap(\.nr).max() ?? 0
        let lastNr = mark?.boot == boot ? max(mark!.lastNr, last) : last
        return (fresh, UploadMark(boot: boot, lastNr: lastNr), true)
    }

    static func read(_ data: Data) throws -> SensorUpload {
        try JSONReading.checkHeader(data, format: format, version: version, what: "upload van een sensorkastje")
        let upload = try JSONReading.decode(SensorUpload.self, from: data)
        guard !upload.sensorId.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw FileReadError(message: "Het kastje stuurde geen sensorId.")
        }
        if upload.measurements.contains(where: { !$0.ageS.isFinite || $0.ageS < 0 || !$0.raw.isFinite }) {
            throw FileReadError(message: "Een meting heeft geen geldige leeftijd (ageS) of ruwe waarde (raw).")
        }
        return upload
    }

    /// The measurements in the format veld/sensormeting, for the sensor placed in `field`.
    func measurements(field: FieldRecord, sensor: FieldSensor, receivedAt: Date) -> [SensorMeasurement] {
        measurements.map { m in
            SensorMeasurement(format: SensorMeasurement.format, version: SensorMeasurement.version,
                              sensorId: sensorId, fieldId: field.id, location: sensor.location,
                              depthCm: depthCm ?? sensor.depthCm,
                              time: receivedAt.addingTimeInterval(-m.ageS.rounded()),
                              raw: m.raw, moisturePercent: sensor.calibration?.percent(raw: m.raw),
                              calibration: sensor.calibration, batteryVolt: m.batteryVolt)
        }
    }
}

/// The last measurement the app received from a box since that box was switched on.
struct UploadMark: Codable, Equatable {
    var boot: Int
    var lastNr: Int
}

enum SensorHistory {
    /// Adds new measurements to the ones already kept. A box that sends the same measurements
    /// again (because it missed the app's answer) gives no doubles: same sensor and raw value
    /// within two minutes counts as the same measurement. Oldest first.
    /// `checkDoubles` false: the measurements are known to be new (numbered by the box).
    static func merge(_ old: [SensorMeasurement], _ new: [SensorMeasurement],
                      checkDoubles: Bool = true) -> (all: [SensorMeasurement], added: Int) {
        var all = old
        var added = 0
        for m in new {
            let duplicate = checkDoubles && all.contains {
                $0.sensorId == m.sensorId && $0.raw == m.raw && abs($0.time.timeIntervalSince(m.time)) < 120
            }
            if !duplicate {
                all.append(m)
                added += 1
            }
        }
        return (all.sorted { $0.time < $1.time }, added)
    }

    /// Applies a (new) calibration to every measurement of that sensor.
    static func calibrate(_ list: [SensorMeasurement], sensorId: String,
                          calibration: SensorMeasurement.Calibration?) -> [SensorMeasurement] {
        list.map { m in
            guard m.sensorId == sensorId else { return m }
            var m = m
            m.calibration = calibration
            m.moisturePercent = calibration?.percent(raw: m.raw)
            return m
        }
    }
}
