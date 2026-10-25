// What the field map shows, worked out from the data formats. The app does not calculate
// any advice itself (docs/ARCHITECTUUR.md): this only sorts and labels what it is given.
import Foundation

struct SensorSummary: Identifiable, Equatable {
    let sensorId: String
    let location: LatLng
    let latest: SensorMeasurement
    /// All measurements of this sensor, oldest first.
    let history: [SensorMeasurement]

    var id: String { sensorId }

    /// "s1" for "veld-noord-s1": the part after the field id.
    var shortName: String {
        let prefix = latest.fieldId + "-"
        return sensorId.hasPrefix(prefix) ? String(sensorId.dropFirst(prefix.count)) : sensorId
    }

    var valueText: String {
        if let percent = latest.moisturePercent {
            return String(format: "%.0f %% vocht", percent)
        }
        return "ruw \(Int(latest.raw.rounded()))"
    }
}

enum FieldSummary {
    /// One entry per sensor with its latest measurement, sorted by sensor id.
    static func sensors(_ measurements: [SensorMeasurement]) -> [SensorSummary] {
        Dictionary(grouping: measurements, by: \.sensorId)
            .compactMap { sensorId, list -> SensorSummary? in
                let sorted = list.sorted { $0.time < $1.time }
                guard let latest = sorted.last else { return nil }
                return SensorSummary(sensorId: sensorId, location: latest.location, latest: latest, history: sorted)
            }
            .sorted { $0.sensorId < $1.sensorId }
    }

    /// "zojuist", "45 min geleden", "3 uur geleden", "2 dagen geleden".
    static func ageText(of date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 0 { return "in de toekomst" }
        let minutes = Int(seconds / 60)
        if minutes < 2 { return "zojuist" }
        if minutes < 60 { return "\(minutes) min geleden" }
        let hours = minutes / 60
        if hours < 48 { return hours == 1 ? "1 uur geleden" : "\(hours) uur geleden" }
        return "\(hours / 24) dagen geleden"
    }

    /// "ma 26 okt" for "2026-10-26".
    static func dayLabel(_ isoDate: String) -> String {
        let input = DateFormatter()
        input.locale = Locale(identifier: "en_US_POSIX")
        input.timeZone = TimeZone(identifier: "Europe/Amsterdam")
        input.dateFormat = "yyyy-MM-dd"
        guard let date = input.date(from: isoDate) else { return isoDate }
        let output = DateFormatter()
        output.locale = Locale(identifier: "nl_NL")
        output.timeZone = input.timeZone
        output.dateFormat = "EEE d MMM"
        return output.string(from: date).replacingOccurrences(of: ".", with: "")
    }

    /// "di 27 okt 11:00–15:00" in Dutch time.
    static func windowLabel(_ window: WeatherForecast.FlightWindow) -> String {
        let day = DateFormatter()
        day.locale = Locale(identifier: "nl_NL")
        day.timeZone = TimeZone(identifier: "Europe/Amsterdam")
        day.dateFormat = "EEE d MMM HH:mm"
        let time = DateFormatter()
        time.locale = day.locale
        time.timeZone = day.timeZone
        time.dateFormat = "HH:mm"
        return "\(day.string(from: window.start))–\(time.string(from: window.end))".replacingOccurrences(of: ".", with: "")
    }
}
