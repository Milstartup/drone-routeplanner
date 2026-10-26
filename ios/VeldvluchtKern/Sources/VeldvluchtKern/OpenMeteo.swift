// The weather for a field from Open-Meteo, in the format veld/weer, with the moments that are
// good for flying (docs/ARCHITECTUUR.md, chapters 3 and 7). Open-Meteo is free for
// non-commercial use such as this school project, needs no key, and must be credited.
import Foundation

enum OpenMeteo {
    static let source = "Open-Meteo"
    static let attribution = "Weergegevens door Open-Meteo.com (CC BY 4.0)"

    /// Five days of hourly and daily figures, wind in m/s, times in Dutch time.
    static func url(for location: LatLng, days: Int = 5) -> URL {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", location.lat)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", location.lng)),
            URLQueryItem(name: "hourly", value: "precipitation,wind_speed_10m,wind_gusts_10m,is_day"),
            URLQueryItem(name: "daily", value: "precipitation_sum,temperature_2m_min,temperature_2m_max,wind_speed_10m_max,wind_gusts_10m_max,et0_fao_evapotranspiration"),
            URLQueryItem(name: "wind_speed_unit", value: "ms"),
            URLQueryItem(name: "timezone", value: "Europe/Amsterdam"),
            URLQueryItem(name: "forecast_days", value: "\(days)"),
        ]
        return components.url!
    }

    private struct Answer: Decodable {
        struct Hourly: Decodable {
            var time: [String]
            var precipitation: [Double?]
            var wind_speed_10m: [Double?]
            var wind_gusts_10m: [Double?]
            var is_day: [Int?]
        }

        struct Daily: Decodable {
            var time: [String]
            var precipitation_sum: [Double?]
            var temperature_2m_min: [Double?]
            var temperature_2m_max: [Double?]
            var wind_speed_10m_max: [Double?]
            var wind_gusts_10m_max: [Double?]
            var et0_fao_evapotranspiration: [Double?]
        }

        var timezone: String
        var hourly: Hourly
        var daily: Daily
    }

    /// Turns Open-Meteo's answer into the weather for the field map.
    static func forecast(from data: Data, fieldId: String, location: LatLng, now: Date) throws -> WeatherForecast {
        let answer: Answer
        do {
            answer = try JSONDecoder().decode(Answer.self, from: data)
        } catch {
            throw FileReadError(message: "Het antwoord van de weerdienst is niet te lezen.")
        }
        let parse = DateFormatter()
        parse.locale = Locale(identifier: "en_US_POSIX")
        parse.timeZone = TimeZone(identifier: answer.timezone) ?? TimeZone(identifier: "Europe/Amsterdam")
        parse.dateFormat = "yyyy-MM-dd'T'HH:mm"

        let d = answer.daily
        let days = d.time.indices.map { i in
            WeatherForecast.Day(date: d.time[i],
                                precipitationMm: daily(d.precipitation_sum, i),
                                tempMinC: daily(d.temperature_2m_min, i),
                                tempMaxC: daily(d.temperature_2m_max, i),
                                windMaxMps: daily(d.wind_speed_10m_max, i),
                                gustMaxMps: daily(d.wind_gusts_10m_max, i),
                                evaporationMm: d.et0_fao_evapotranspiration.indices.contains(i) ? d.et0_fao_evapotranspiration[i] : nil)
        }
        let h = answer.hourly
        let hours = h.time.indices.compactMap { i -> FlightWeather.Hour? in
            guard let time = parse.date(from: h.time[i]) else { return nil }
            return FlightWeather.Hour(start: time, precipitationMm: value(h.precipitation, i), windMps: value(h.wind_speed_10m, i),
                                      gustMps: value(h.wind_gusts_10m, i),
                                      isDay: (h.is_day.indices.contains(i) ? h.is_day[i] : nil) == 1)
        }
        return WeatherForecast(format: WeatherForecast.format, version: WeatherForecast.version, fieldId: fieldId,
                               location: location, source: source, attribution: attribution, createdAt: now,
                               days: days, flightWindows: FlightWeather.windows(hours, now: now))
    }

    /// A missing hourly number counts as the worst case for flying.
    private static func value(_ list: [Double?], _ i: Int) -> Double {
        (list.indices.contains(i) ? list[i] : nil) ?? .infinity
    }

    /// A missing daily number is shown as 0 (JSON has no infinity).
    private static func daily(_ list: [Double?], _ i: Int) -> Double {
        (list.indices.contains(i) ? list[i] : nil) ?? 0
    }
}

/// When to fly: little wind, dry and daylight (the Mavic Mini handles wind up to 8 m/s).
enum FlightWeather {
    /// "Ruim onder 8 m/s": average wind and gusts with room to spare.
    static let maxWindMps = 5.0
    static let maxGustMps = 7.0
    static let minHours = 2

    struct Hour {
        var start: Date
        var precipitationMm: Double
        var windMps: Double
        var gustMps: Double
        var isDay: Bool

        var isGood: Bool {
            isDay && precipitationMm < 0.05 && windMps < FlightWeather.maxWindMps && gustMps < FlightWeather.maxGustMps
        }
    }

    /// Runs of at least two good hours from now on, soonest first.
    static func windows(_ hours: [Hour], now: Date) -> [WeatherForecast.FlightWindow] {
        var windows: [WeatherForecast.FlightWindow] = []
        var run: [Hour] = []
        func close() {
            if run.count >= minHours, let first = run.first, let last = run.last {
                let wind = run.map(\.windMps).max() ?? 0
                let gust = run.map(\.gustMps).max() ?? 0
                windows.append(WeatherForecast.FlightWindow(
                    start: first.start,
                    end: last.start.addingTimeInterval(3600),
                    reason: "Wind tot \(Int(wind.rounded())) m/s met windstoten tot \(Int(gust.rounded())) m/s, droog en daglicht."
                ))
            }
            run = []
        }
        for hour in hours.sorted(by: { $0.start < $1.start }) {
            // An hour that is already over does not count; the current hour does.
            guard hour.start.addingTimeInterval(3600) > now else { continue }
            if hour.isGood, run.last.map({ hour.start.timeIntervalSince($0.start) <= 3600 }) ?? true {
                run.append(hour)
            } else {
                close()
                if hour.isGood { run.append(hour) }
            }
        }
        close()
        return windows
    }
}
