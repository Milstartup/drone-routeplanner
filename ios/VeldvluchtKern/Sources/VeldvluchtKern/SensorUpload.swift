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

// MARK: - Pairing a sensor box (sensor/README.md, "Koppelen met de app")

/// The app gives a sensor box its settings over the box's own WiFi network: after switching on
/// the box opens "Veldsensor-XXXX" for two minutes and listens at 192.168.4.1. A form, not
/// JSON, because the box has no JSON reader; it checks everything again itself.
enum SensorPairing {
    static let address = URL(string: "http://192.168.4.1/instellingen")!
    static let networkPrefix = "Veldsensor-"
    static let networkPassword = "veldsensor"

    struct Settings: Equatable {
        var hotspotName: String
        var hotspotPassword: String
        var sensorId: String
        /// The sensor's key and the cloud project: without them the box only sends to the app.
        var sensorKey: String?
        var cloudProject: String?
        var cloudKey: String?
        var depthCm: Int
        var intervalMinutes = 60
    }

    enum Outcome: Equatable {
        case paired(sensorId: String, raw: Int)
        case refused(String)
    }

    /// Why the box would refuse these settings, in Dutch: the same checks as the box makes.
    static func problems(_ s: Settings) -> [String] {
        var problems: [String] = []
        if !(1...32).contains(s.hotspotName.utf8.count) {
            problems.append("Vul de naam van je hotspot in: precies de naam van je iPhone (Instellingen → Algemeen → Info → Naam).")
        }
        if !(8...63).contains(s.hotspotPassword.utf8.count) {
            problems.append("Vul het wachtwoord van je hotspot in (Instellingen → Persoonlijke hotspot): 8 tot 63 tekens.")
        }
        if !(1...40).contains(s.sensorId.count) || !s.sensorId.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") }) {
            problems.append("De naam van de sensor mag alleen kleine letters, cijfers en streepjes hebben.")
        }
        if let project = s.cloudProject, !project.isEmpty {
            if project.count > 40 || !project.allSatisfy({ $0.isASCII && ($0.isLowercase || $0.isNumber) }) {
                problems.append("Het cloudproject klopt niet: alleen kleine letters en cijfers.")
            }
            if (s.sensorKey ?? "").isEmpty || (s.cloudKey ?? "").isEmpty {
                problems.append("De sleutel van de sensor ontbreekt. Log in en druk eerst op Bewaren bij Sensoren.")
            } else if (s.sensorKey ?? "").count > 64 || (s.cloudKey ?? "").count > 256 {
                problems.append("Een sleutel is te lang voor het kastje.")
            }
        }
        if !(0...200).contains(s.depthCm) {
            problems.append("De diepte moet 0 tot 200 cm zijn.")
        }
        if !(1...1440).contains(s.intervalMinutes) {
            problems.append("Meten kan elke 1 tot 1440 minuten.")
        }
        return problems
    }

    static func request(_ s: Settings) -> URLRequest {
        var request = URLRequest(url: address, timeoutInterval: 8)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // The box is only on WiFi: never look for it over the mobile network.
        request.allowsCellularAccess = false
        let fields = [("hotspot", s.hotspotName), ("wachtwoord", s.hotspotPassword), ("sensor", s.sensorId),
                      ("sleutel", s.sensorKey ?? ""), ("project", s.cloudProject ?? ""), ("cloudsleutel", s.cloudKey ?? ""),
                      ("diepte", String(s.depthCm)), ("interval", String(s.intervalMinutes))]
        request.httpBody = Data(fields.map { "\($0.0)=\(formEncoded($0.1))" }.joined(separator: "&").utf8)
        return request
    }

    /// Only letters, digits and -._~ stay as they are; the rest becomes %XX (UTF-8).
    static func formEncoded(_ text: String) -> String {
        let plain = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return text.addingPercentEncoding(withAllowedCharacters: plain) ?? ""
    }

    static func outcome(data: Data, status: Int) -> Outcome {
        let answer = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if status == 200, answer?["ok"] as? Bool == true, let id = answer?["sensorId"] as? String {
            return .paired(sensorId: id, raw: answer?["ruw"] as? Int ?? 0)
        }
        if let reason = answer?["fout"] as? String {
            return .refused(reason)
        }
        return .refused("Het kastje gaf een onverwacht antwoord (code \(status)). Is dit wel een Veldsensor-netwerk?")
    }

    static let noAnswer = "Het kastje antwoordt niet. Staat je iPhone op de wifi Veldsensor-…? Het kastje houdt dat netwerk 2 minuten open na het aanzetten: druk op EN op het bordje, kies het netwerk opnieuw en probeer het nog een keer."
}
