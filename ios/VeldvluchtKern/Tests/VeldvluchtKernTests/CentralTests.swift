@testable import VeldvluchtKern
import XCTest

/// Weather, sensor uploads and the water advice: the central system, version 0.
final class CentralTests: XCTestCase {
    private let amsterdam = TimeZone(identifier: "Europe/Amsterdam")!

    private func date(_ text: String) -> Date {
        JSONReading.parseDate(text)!
    }

    // MARK: Weather

    private func openMeteo() throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("open-meteo-voorbeeld.json"))
    }

    func testReadsTheForecastOfOpenMeteo() throws {
        let location = LatLng(lat: 52.499, lng: 5.5425)
        let weather = try OpenMeteo.forecast(from: openMeteo(), fieldId: "veld-noord", location: location,
                                             now: date("2026-10-26T12:00:00+01:00"))
        XCTAssertEqual(weather.days.map(\.date), ["2026-10-26", "2026-10-27", "2026-10-28", "2026-10-29", "2026-10-30"])
        XCTAssertEqual(weather.days[1].precipitationMm, 2.0)
        XCTAssertEqual(weather.days[0].gustMaxMps, 17.4)
        XCTAssertEqual(weather.days[0].evaporationMm, 1.4)
        XCTAssertEqual(weather.attribution, "Weergegevens door Open-Meteo.com (CC BY 4.0)")

        // Little wind, dry and daylight: Wednesday morning, then Thursday and Friday all day.
        let windows = try XCTUnwrap(weather.flightWindows)
        XCTAssertEqual(windows.count, 3)
        XCTAssertEqual(windows[0].start, date("2026-10-28T08:00:00+01:00"))
        XCTAssertEqual(windows[0].end, date("2026-10-28T11:00:00+01:00"))
        XCTAssertEqual(windows[1].start, date("2026-10-29T08:00:00+01:00"))
        XCTAssertEqual(windows[1].end, date("2026-10-29T18:00:00+01:00"))
        XCTAssertTrue(windows[0].reason.contains("windstoten tot 6 m/s"))

        // Written in the format veld/weer and read back by the field map.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let read = try WeatherForecast.read(encoder.encode(weather))
        XCTAssertEqual(read.days, weather.days)
        XCTAssertEqual(read.flightWindows?.count, 3)
    }

    func testAWindowThatHasStartedCountsFromTheCurrentHour() throws {
        let weather = try OpenMeteo.forecast(from: openMeteo(), fieldId: "veld-noord", location: LatLng(lat: 52.5, lng: 5.54),
                                             now: date("2026-10-29T12:30:00+01:00"))
        XCTAssertEqual(weather.flightWindows?.first?.start, date("2026-10-29T12:00:00+01:00"))
        XCTAssertEqual(weather.flightWindows?.first?.end, date("2026-10-29T18:00:00+01:00"))
    }

    // MARK: Sensor upload

    private func field() -> FieldRecord {
        let projection = LocalProjection(origin: LatLng(lat: 52.5, lng: 5.54))
        let boundary = [XY(x: 0, y: 0), XY(x: 100, y: 0), XY(x: 100, y: 60), XY(x: 0, y: 60)].map(projection.toLatLng)
        let created = date("2026-10-20T10:00:00+02:00")
        var field = FieldRecord(id: "proefveld", name: "Proefveld", boundary: boundary, home: boundary[0],
                                settings: .planner, createdAt: created, updatedAt: created)
        field.sensors = [FieldSensor(id: "proefveld-s1", location: projection.toLatLng(XY(x: 50, y: 30)))]
        return field
    }

    private let upload = """
    {"format":"veld/sensorupload","version":0,"sensorId":"proefveld-s1","depthCm":20,
     "measurements":[{"ageS":7200,"raw":760,"batteryVolt":3.91},{"ageS":3600,"raw":740,"batteryVolt":null}]}
    """

    func testTurnsAnUploadIntoMeasurements() throws {
        var field = field()
        field.sensors[0].calibration = .init(dryRaw: 860, wetRaw: 340)
        let received = date("2026-10-26T12:00:00+01:00")
        let list = try SensorUpload.read(Data(upload.utf8)).measurements(field: field, sensor: field.sensors[0], receivedAt: received)
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[0].time, date("2026-10-26T10:00:00+01:00"))
        XCTAssertEqual(list[1].time, date("2026-10-26T11:00:00+01:00"))
        XCTAssertEqual(list[0].location, field.sensors[0].location)
        XCTAssertEqual(list[0].fieldId, "proefveld")
        XCTAssertEqual(list[0].depthCm, 20)
        XCTAssertEqual(list[0].moisturePercent ?? -1, 100.0 / 520 * 100, accuracy: 0.01)
        XCTAssertEqual(list[0].batteryVolt, 3.91)
        XCTAssertNil(list[1].batteryVolt)
    }

    func testRefusesAWrongUpload() {
        XCTAssertThrowsError(try SensorUpload.read(Data(#"{"format":"veld/sensormeting","version":0}"#.utf8)))
        let negative = upload.replacingOccurrences(of: "7200", with: "-5")
        XCTAssertThrowsError(try SensorUpload.read(Data(negative.utf8)))
    }

    func testAnUploadSentTwiceGivesNoDoubles() throws {
        let field = field()
        let sensor = field.sensors[0]
        let first = try SensorUpload.read(Data(upload.utf8)).measurements(field: field, sensor: sensor, receivedAt: date("2026-10-26T12:00:00+01:00"))
        // The box missed the answer and sends the same two again 30 s later (ages 30 s higher).
        var again = try SensorUpload.read(Data(upload.utf8))
        again.measurements = again.measurements.map { var m = $0; m.ageS += 30; return m }
        let second = again.measurements(field: field, sensor: sensor, receivedAt: date("2026-10-26T12:00:31+01:00"))
        let merged = SensorHistory.merge(first, second)
        XCTAssertEqual(merged.all.count, 2)
        XCTAssertEqual(merged.added, 0)
    }

    func testNumberedMeasurementsAreSkippedWhenSentAgain() throws {
        let numbered = """
        {"format":"veld/sensorupload","version":0,"sensorId":"proefveld-s1","boot":4711,
         "measurements":[{"nr":1,"ageS":20,"raw":2000},{"nr":2,"ageS":10,"raw":2000}]}
        """
        let first = try SensorUpload.read(Data(numbered.utf8)).unseen(after: nil)
        XCTAssertTrue(first.numbered)
        XCTAssertEqual(first.measurements.count, 2, "the same value 10 s apart is still two measurements")
        XCTAssertEqual(first.mark, UploadMark(boot: 4711, lastNr: 2))

        // The box missed the answer and sends 1 and 2 again, with a new 3.
        var again = try SensorUpload.read(Data(numbered.utf8))
        again.measurements.append(.init(nr: 3, ageS: 0, raw: 2010, batteryVolt: nil))
        let second = again.unseen(after: first.mark)
        XCTAssertEqual(second.measurements.map(\.nr), [3])
        XCTAssertEqual(second.mark, UploadMark(boot: 4711, lastNr: 3))

        // After a power loss the box starts again at 1, with another boot id.
        again.boot = 99
        XCTAssertEqual(again.unseen(after: second.mark).measurements.count, 3)

        // Measurements with equal values 10 s apart are kept when they are numbered.
        let field = field()
        let list = try SensorUpload.read(Data(numbered.utf8)).measurements(field: field, sensor: field.sensors[0], receivedAt: Date())
        XCTAssertEqual(SensorHistory.merge([], list, checkDoubles: false).added, 2)
        XCTAssertEqual(SensorHistory.merge([], list).added, 1, "without numbers they would look like one")
    }

    // MARK: Water advice

    private func measurement(raw: Double, at time: String, field: FieldRecord) -> SensorMeasurement {
        SensorMeasurement(format: SensorMeasurement.format, version: 0, sensorId: "proefveld-s1", fieldId: field.id,
                          location: field.sensors[0].location, depthCm: 15, time: date(time), raw: raw,
                          moisturePercent: nil, calibration: nil, batteryVolt: nil)
    }

    private func weather(rainToday: Double, rainTomorrow: Double, evaporation: Double = 1) -> WeatherForecast {
        WeatherForecast(format: WeatherForecast.format, version: 0, fieldId: "proefveld", location: nil, source: "test",
                        attribution: "test", createdAt: date("2026-10-26T06:00:00+01:00"),
                        days: [
                            .init(date: "2026-10-25", precipitationMm: 30, tempMinC: 5, tempMaxC: 10, windMaxMps: 3, gustMaxMps: 5, evaporationMm: 1),
                            .init(date: "2026-10-26", precipitationMm: rainToday, tempMinC: 5, tempMaxC: 10, windMaxMps: 3, gustMaxMps: 5, evaporationMm: evaporation),
                            .init(date: "2026-10-27", precipitationMm: rainTomorrow, tempMinC: 5, tempMaxC: 10, windMaxMps: 3, gustMaxMps: 5, evaporationMm: evaporation),
                        ],
                        flightWindows: [])
    }

    private func advice(raw: Double, at time: String = "2026-10-26T10:00:00+01:00", weather: WeatherForecast?,
                        calibrated: Bool = true) -> [FieldResults.Feature] {
        var field = field()
        if calibrated { field.sensors[0].calibration = .init(dryRaw: 860, wetRaw: 340) }
        let results = WaterAdvisor.results(field: field, measurements: [measurement(raw: raw, at: time, field: field)],
                                           weather: weather, now: date("2026-10-26T12:00:00+01:00"))
        XCTAssertEqual(results.boundary?.properties.name, "Proefveld")
        return results.waterZones
    }

    func testStripsAlongTheFlightLines() {
        // 60 m across the east-west lines, strips of 24 m: 24 + 24 + 12.
        let zones = advice(raw: 600, weather: weather(rainToday: 0, rainTomorrow: 0))
        XCTAssertEqual(zones.map(\.properties.name), ["Strook 1", "Strook 2", "Strook 3"])
        XCTAssertTrue(zones.allSatisfy { !($0.properties.reason ?? "").isEmpty })
    }

    func testDryAndNoRainMeansWaterNow() throws {
        // Raw 760 is 19 % between dry (860) and wet (340).
        let zones = advice(raw: 760, weather: weather(rainToday: 0.5, rainTomorrow: 0.5))
        let middle = zones[1].properties
        XCTAssertEqual(middle.advice, .water)
        XCTAssertEqual(middle.amountMm ?? 0, 14.5, accuracy: 0.01)
        XCTAssertEqual(middle.confidence ?? 0, 0.7, accuracy: 1e-9, "sensor inside the strip, measured 2 hours ago")
        XCTAssertTrue(middle.reason!.contains("19 % vocht"))
        XCTAssertTrue(middle.reason!.contains("nu water geven"))
        // The strips next to it use the same sensor, with less confidence.
        XCTAssertEqual(zones[0].properties.advice, .water)
        XCTAssertEqual(zones[0].properties.confidence ?? 0, 0.5, accuracy: 1e-9)
        XCTAssertTrue(zones[0].properties.reason!.contains("naast deze strook"))
    }

    func testDryButMuchRainComingMeansWait() {
        let zones = advice(raw: 760, weather: weather(rainToday: 4, rainTomorrow: 8))
        XCTAssertEqual(zones[1].properties.advice, .binnenkort)
        XCTAssertTrue(zones[1].properties.reason!.contains("wacht op de regen"))
    }

    func testInBetween() {
        // Raw 620 is 46 %.
        XCTAssertEqual(advice(raw: 620, weather: weather(rainToday: 1, rainTomorrow: 0))[1].properties.advice, .binnenkort)
        XCTAssertEqual(advice(raw: 620, weather: weather(rainToday: 4, rainTomorrow: 4))[1].properties.advice, .genoeg)
    }

    func testWetEnough() {
        let zone = advice(raw: 500, weather: weather(rainToday: 0, rainTomorrow: 0))[1].properties
        XCTAssertEqual(zone.advice, .genoeg)
        XCTAssertEqual(zone.amountMm, 0)
    }

    func testNoAdviceWithoutCalibrationOrWithAnOldMeasurement() {
        let uncalibrated = advice(raw: 760, weather: weather(rainToday: 0, rainTomorrow: 0), calibrated: false)[1].properties
        XCTAssertNil(uncalibrated.advice)
        XCTAssertTrue(uncalibrated.reason!.contains("nog niet geijkt"))
        let old = advice(raw: 760, at: "2026-10-23T10:00:00+02:00", weather: weather(rainToday: 0, rainTomorrow: 0))[1].properties
        XCTAssertNil(old.advice)
        XCTAssertTrue(old.reason!.contains("laatste 2 dagen"))
    }

    func testWithoutWeatherRainDoesNotCount() {
        let zone = advice(raw: 760, weather: nil)[1].properties
        XCTAssertEqual(zone.advice, .water)
        XCTAssertEqual(zone.confidence ?? 0, 0.6, accuracy: 1e-9)
        XCTAssertTrue(zone.reason!.contains("Geen weersverwachting"))
    }

    func testNoSensorNoAdvice() {
        var field = field()
        field.sensors = []
        let results = WaterAdvisor.results(field: field, measurements: [], weather: nil, now: Date())
        XCTAssertTrue(results.waterZones.allSatisfy { $0.properties.advice == nil })
        XCTAssertTrue(results.waterZones[0].properties.reason!.contains("Geen sensor"))
    }

    func testTheResultsAreAValidFile() throws {
        var field = field()
        field.sensors[0].calibration = .init(dryRaw: 860, wetRaw: 340)
        let results = WaterAdvisor.results(field: field, measurements: [measurement(raw: 700, at: "2026-10-26T10:00:00+01:00", field: field)],
                                           weather: weather(rainToday: 0, rainTomorrow: 0), now: date("2026-10-26T12:00:00+01:00"))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let read = try FieldResults.read(encoder.encode(results))
        XCTAssertEqual(read, results)
    }
}
