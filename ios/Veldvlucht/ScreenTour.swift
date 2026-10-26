// Debug builds only: a tour past every screen with example data, to check the design on the
// iPhone itself. Each screen is saved as a PNG in Documents/Schermtour, in light and dark
// mode. It never starts the DJI SDK: the flight screens use the fake drone of the tests.
//
// Start:  xcrun devicectl device process launch --device <id> nl.milanmehrzad.veldvlucht -schermtour
// Fetch:  xcrun devicectl device copy from --device <id> --domain-type appDataContainer
//         --domain-identifier nl.milanmehrzad.veldvlucht --source Documents/Schermtour --destination <map>
#if DEBUG
import SwiftUI
import UIKit

enum ScreenTour {
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains("-schermtour") }

    static var folder: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Schermtour", isDirectory: true)
    }

    /// Example flights for the Vluchten tab, removed again at the end of the tour.
    static let exampleFlightIds = ["schermtour-voorbeeld-simulator", "schermtour-voorbeeld"]
}

struct ScreenTourView: View {
    private enum Page {
        case start
        case tabs(Screen)
        case routeMap
        case flight
        case checklist(simulator: Bool)
        case field(preselected: String?)
        case savedFlight
    }

    @StateObject private var drone = DJIConnection()
    @StateObject private var route = RouteModel()
    @State private var page = Page.start
    @State private var screen = Screen.drone
    @State private var session: FlightSession?
    @State private var flight: RouteFlight?
    @State private var fake: FakeDrone?
    @State private var savedFlight: SavedFlight?
    /// Changes for every page, so SwiftUI builds each page fresh.
    @State private var pageNumber = 0

    var body: some View {
        content
            .id(pageNumber)
            .task { await run() }
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .start:
            Color.groupedBackground.ignoresSafeArea()
        case .tabs:
            MainTabs(drone: drone, route: route, screen: $screen)
        case .routeMap:
            if let file = route.file {
                NavigationStack { RouteMapView(file: file, contentID: "tour") }
            }
        case .flight:
            if let session, let flight {
                FlightScreen(session: session, flight: flight, drone: drone)
            }
        case .checklist(let simulator):
            StartChecklist(isSimulator: simulator, altitudeM: 30) {}
        case .field(let preselected):
            NavigationStack { FieldMapScreen(preselected: preselected) }
        case .savedFlight:
            if let savedFlight {
                NavigationStack { SavedFlightView(flight: savedFlight) }
            }
        }
    }

    // MARK: The tour

    @MainActor
    private func run() async {
        try? FileManager.default.removeItem(at: ScreenTour.folder)
        try? FileManager.default.createDirectory(at: ScreenTour.folder, withIntermediateDirectories: true)
        removeExampleFlights()
        await wait(1)

        drone.showTourStatus(connected: false, simulator: false)
        await shoot("01-drone-niet-verbonden", .tabs(.drone))
        drone.showTourStatus(connected: true, simulator: false)
        await shoot("02-drone-verbonden", .tabs(.drone), dark: true)

        await shoot("03-route-leeg", .tabs(.route))
        route.loadSample()
        await shoot("04-route-geladen", .tabs(.route), seconds: 4, dark: true)
        await shoot("05-route-kaart", .routeMap, seconds: 5)

        guard let file = route.file else { return }
        startFlight(file, simulatorOn: false)
        await shoot("06-vlucht-simulator-uit", .flight, seconds: 4)
        startFlight(file, simulatorOn: true)
        await shoot("07-vlucht-klaar", .flight, seconds: 4)
        await shoot("08-controlelijst-simulator", .checklist(simulator: true))
        await shoot("09-controlelijst-echt", .checklist(simulator: false), dark: true)

        flight?.start()
        fly { $0.photoLog.photos.count >= 46 }
        await shoot("10-vlucht-bezig", .flight, seconds: 4, dark: true)
        flight?.pause()
        fly(seconds: 3)
        await shoot("11-vlucht-pauze", .flight, seconds: 3)
        flight?.updateSticks(deflected: true)
        fly(seconds: 1)
        flight?.updateSticks(deflected: false)
        await shoot("12-vlucht-overgenomen", .flight, seconds: 3)
        flight?.resume()
        fly { if case .finished = $0.phase { return true } else { return false } }
        await shoot("13-vlucht-klaar", .flight, seconds: 3)

        await shoot("14-veldkaart", .field(preselected: nil), seconds: 6, dark: true)
        await shoot("15-veldkaart-strook", .field(preselected: "zone-4"), seconds: 5)
        if case .success(let field) = SampleData.field(), let sensor = field.sensors.first {
            await shoot("16-veldkaart-sensor", .field(preselected: "sensor-\(sensor.sensorId)"), seconds: 5, dark: true)
        }

        saveExampleFlights()
        await shoot("17-vluchten", .tabs(.flights), seconds: 2, dark: true)
        if savedFlight != nil {
            await shoot("18-vlucht-opgeslagen", .savedFlight, seconds: 5)
        }
        removeExampleFlights()
        await shoot("19-vluchten-leeg", .tabs(.flights), seconds: 2)

        try? "klaar".write(to: ScreenTour.folder.appendingPathComponent("klaar.txt"), atomically: true, encoding: .utf8)
    }

    @MainActor
    private func shoot(_ name: String, _ next: Page, seconds: Double = 2, dark: Bool = false) async {
        if case .tabs(let tab) = next { screen = tab }
        page = next
        pageNumber += 1
        setStyle(.light)
        await wait(seconds)
        capture(name)
        if dark {
            setStyle(.dark)
            await wait(seconds > 3 ? 3 : 2)
            capture(name + "-donker")
            setStyle(.light)
        }
    }

    // MARK: Example flights with the fake drone

    @MainActor
    private func startFlight(_ file: RoutePlanFile, simulatorOn: Bool) {
        drone.showTourStatus(connected: true, simulator: simulatorOn)
        let plan = FlightPlan(file)
        let fake = FakeDrone(projection: plan.projection)
        fake.simulatorActive = simulatorOn
        let flight = RouteFlight(plan: plan, drone: fake, flightId: ScreenTour.exampleFlightIds[0],
                                 fieldId: "schermtour", clock: { fake.now })
        fake.flight = flight
        flight.update(fake.telemetry())
        self.fake = fake
        self.flight = flight
        session = FlightSession(file: file, drone: drone)
    }

    /// Runs the fake drone and the control loop, faster than real time.
    @MainActor
    private func fly(seconds: Double = 3000, until done: ((RouteFlight) -> Bool)? = nil) {
        guard let fake, let flight else { return }
        var t = 0.0
        while t < seconds {
            fake.step(0.1)
            flight.update(fake.telemetry())
            flight.tick()
            t += 0.1
            if done?(flight) == true { return }
        }
    }

    @MainActor
    private func saveExampleFlights() {
        guard let flight else { return }
        let recorder = FlightRecorder()
        var log = flight.photoLog
        recorder.save(log)
        recorder.save(log: flight.log, flightId: log.flightId)
        log.flightId = ScreenTour.exampleFlightIds[1]
        log.photos = Array(log.photos.prefix(24))
        recorder.save(log)
        let url = FlightRecorder.folder.appendingPathComponent("\(flight.photoLog.flightId).fotolog.json")
        savedFlight = SavedFlight(photoLog: flight.photoLog, photoLogURL: url,
                                  logURL: FlightRecorder.folder.appendingPathComponent("\(flight.photoLog.flightId).logboek.txt"))
    }

    private func removeExampleFlights() {
        for id in ScreenTour.exampleFlightIds {
            for suffix in [".fotolog.json", ".logboek.txt"] {
                try? FileManager.default.removeItem(at: FlightRecorder.folder.appendingPathComponent(id + suffix))
            }
        }
    }

    // MARK: Screenshots

    private func wait(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private var window: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }

    private func setStyle(_ style: UIUserInterfaceStyle) {
        window?.overrideUserInterfaceStyle = style
    }

    private func capture(_ name: String) {
        guard let window else { return }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try? image.pngData()?.write(to: ScreenTour.folder.appendingPathComponent(name + ".png"))
    }
}
#endif
