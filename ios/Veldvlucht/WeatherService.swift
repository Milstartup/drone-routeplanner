// Fetches the weather for a field drawn in the app from Open-Meteo, keeps it with the field,
// and can give a notification before the next good moment to fly (docs/ARCHITECTUUR.md,
// chapter 7: a local notification instead of a push from a server, which needs a paid account).
import Foundation
import UserNotifications

@MainActor
final class WeatherService: ObservableObject {
    @Published private(set) var loading = false
    @Published private(set) var problem: String?
    /// Changes after every successful fetch, so the field map reloads.
    @Published private(set) var updates = 0

    /// A fresh forecast is fetched when the one kept is older than this.
    static let maxAgeS = 3600.0

    /// Fetches the forecast unless the one kept is still fresh.
    func refresh(_ field: FieldRecord, force: Bool = false) async {
        let url = SampleData.weatherURL(fieldId: field.id)
        if !force, let kept = try? WeatherForecast.read(Data(contentsOf: url)),
           Date().timeIntervalSince(kept.createdAt) < Self.maxAgeS {
            await FlightNotifier.schedule(kept, fieldName: field.name)
            return
        }
        loading = true
        defer { loading = false }
        let location = Geo.centroid(field.boundary)
        do {
            let (data, response) = try await URLSession.shared.data(from: OpenMeteo.url(for: location))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw FileReadError(message: "De weerdienst gaf geen antwoord.")
            }
            let forecast = try OpenMeteo.forecast(from: data, fieldId: field.id, location: location, now: Date())
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(forecast).write(to: url, options: .atomic)
            problem = nil
            updates += 1
            await FlightNotifier.schedule(forecast, fieldName: field.name)
        } catch let error as URLError {
            problem = error.code == .notConnectedToInternet ? "Geen internet: het weer kan niet opgehaald worden." : "Het weer kan nu niet opgehaald worden."
        } catch {
            problem = error.localizedDescription
        }
    }
}

/// One notification, an hour before the next good moment to fly.
enum FlightNotifier {
    private static let key = "melding.vliegweer"
    private static let id = "vliegweer"

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    /// Asks permission the first time; returns whether notifications are allowed.
    static func enable() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let allowed = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        enabled = allowed
        return allowed
    }

    static func disable() {
        enabled = false
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    static func schedule(_ weather: WeatherForecast, fieldName: String) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard enabled, let window = weather.flightWindows?.first(where: { $0.start > Date().addingTimeInterval(3600) }) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Goed vliegweer bij \(fieldName)"
        content.body = "\(FieldSummary.windowLabel(window)). \(window.reason)"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: window.start.timeIntervalSinceNow - 3600, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
