// Debug builds only: a tour past every screen with example data, to check the design on the
// iPhone itself. Each screen is saved as a PNG in Documents/Schermtour, in light and dark
// mode. It never starts the DJI SDK: the flight screens use the fake drone of the tests.
// Example fields, measurements and flights are removed again afterwards (and at the next
// normal start, should the tour stop halfway).
//
// Start:  xcrun devicectl device process launch --device <id> nl.milanmehrzad.veldvlucht -- -schermtour
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

    /// Example flights for the Vluchten tab.
    static let exampleFlightIds = ["schermtour-voorbeeld-simulator", "schermtour-voorbeeld"]
    /// Example fields for the Route tab and the field map.
    static let exampleFieldIds = ["schermtour-broccoli-west", "schermtour-kool-oost"]

    /// Removes everything the tour made, except its screenshots.
    static func removeExamples(_ fields: FieldStore) {
        for id in exampleFlightIds {
            for suffix in [".fotolog.json", ".logboek.txt"] {
                try? FileManager.default.removeItem(at: FlightRecorder.folder.appendingPathComponent(id + suffix))
            }
        }
        for id in exampleFieldIds where fields.field(id) != nil {
            fields.delete(id)
        }
    }

    /// At a normal start: the screenshots and anything a stopped tour left behind.
    static func cleanUp(_ fields: FieldStore) {
        try? FileManager.default.removeItem(at: folder)
        removeExamples(fields)
    }
}

struct ScreenTourView: View {
    private enum Page {
        case start
        case tabs(Screen)
        case fieldEditor(FieldRecord?)
        case fieldSettings(FieldRecord)
        case routeDetail
        case routeMap
        case flight
        case checklist(simulator: Bool)
        case sensors(FieldRecord)
        case field(preselected: String?)
        case savedFlight
    }

    @StateObject private var drone = DJIConnection()
    @StateObject private var route = RouteModel()
    @StateObject private var fields = FieldStore()
    @StateObject private var weather = WeatherService()
    @StateObject private var receiver = SensorReceiver(fields: FieldStore())
    @StateObject private var cloud = CloudStore(fields: FieldStore())
    @State private var page = Page.start
    @State private var screen = Screen.drone
    @State private var session: FlightSession?
    @State private var flight: RouteFlight?
    @State private var fake: FakeDrone?
    @State private var savedFlight: SavedFlight?
    /// The real receiver, for a test from the Mac (sensor/nep-sensorkastje.py) during the tour.
    @State private var testReceiver: SensorReceiver?
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
            MainTabs(drone: drone, route: route, fields: fields, receiver: receiver, cloud: cloud, weather: weather, screen: $screen)
        case .fieldEditor(let field):
            FieldEditorView(field: field, fields: fields) { _ in }
        case .fieldSettings(let field):
            FieldSettingsSheet(input: .constant(field.planInput), boundary: field.boundary)
        case .routeDetail:
            NavigationStack {
                RouteDetailView(model: route, drone: drone, onEdit: { _ in }, onDelete: { _ in })
            }
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
        case .sensors(let field):
            SensorEditorView(field: field, fields: fields, receiver: testReceiver ?? receiver, cloud: cloud)
        case .field(let preselected):
            FieldMapScreen(fields: fields, receiver: receiver, cloud: cloud, weather: weather, preselected: preselected)
        case .savedFlight:
            if let savedFlight {
                NavigationStack { SavedFlightView(flight: savedFlight) }
            }
        }
    }

    // MARK: The tour

    @MainActor
    private func run() async {
        // The tour takes a few minutes: the screen must not lock meanwhile.
        UIApplication.shared.isIdleTimerDisabled = true
        try? FileManager.default.removeItem(at: ScreenTour.folder)
        try? FileManager.default.createDirectory(at: ScreenTour.folder, withIntermediateDirectories: true)
        ScreenTour.removeExamples(fields)
        let selectedBefore = fields.selectedId
        await wait(1)

        drone.showTourStatus(connected: false, simulator: false)
        await shoot("01-drone-niet-verbonden", .tabs(.drone))
        drone.showTourStatus(connected: true, simulator: false)
        await shoot("02-drone-verbonden", .tabs(.drone), dark: true)

        guard let field = makeExampleFields() else { return }
        await shoot("03-route-velden", .tabs(.route))
        await shoot("04-veld-tekenen-leeg", .fieldEditor(nil), seconds: 4)
        await shoot("05-veld-tekenen", .fieldEditor(field), seconds: 5, dark: true)
        await shoot("06-veld-instellingen", .fieldSettings(field))
        route.load(field: field)
        await shoot("07-veld-route", .routeDetail, seconds: 4, dark: true)
        await shoot("08-route-kaart", .routeMap, seconds: 5)

        guard let file = route.file else { return }
        startFlight(file, simulatorOn: false)
        await shoot("09-vlucht-simulator-uit", .flight, seconds: 4)
        startFlight(file, simulatorOn: true)
        await shoot("10-vlucht-klaar", .flight, seconds: 4)
        await shoot("11-controlelijst-simulator", .checklist(simulator: true))
        await shoot("12-controlelijst-echt", .checklist(simulator: false), dark: true)
        flight?.start()
        fly { $0.photoLog.photos.count >= 40 }
        await shoot("13-vlucht-bezig", .flight, seconds: 4, dark: true)
        flight?.pause()
        fly(seconds: 3)
        await shoot("14-vlucht-pauze", .flight, seconds: 3)
        flight?.updateSticks(deflected: true)
        fly(seconds: 1)
        flight?.updateSticks(deflected: false)
        await shoot("15-vlucht-overgenomen", .flight, seconds: 3)
        flight?.resume()
        fly { if case .finished = $0.phase { return true } else { return false } }
        await shoot("16-vlucht-klaar", .flight, seconds: 3)

        await shoot("17-sensoren", .sensors(field), seconds: 5)
        // Receiver test: for 90 seconds the app accepts uploads; the Mac sends one.
        let testReceiver = SensorReceiver(fields: fields)
        self.testReceiver = testReceiver
        testReceiver.start()
        try? "wacht".write(to: ScreenTour.folder.appendingPathComponent("ontvanger.txt"), atomically: true, encoding: .utf8)
        await shoot("17b-ontvanger-aan", .sensors(field), seconds: 3)
        for _ in 0..<90 where testReceiver.uploads == 0 {
            await wait(1)
        }
        await shoot("17c-ontvanger-ontvangen", .sensors(field), seconds: 3)
        testReceiver.stop()
        self.testReceiver = nil
        fields.selectedId = field.id
        await shoot("18-veldkaart-eigen-veld", .field(preselected: nil), seconds: 8, dark: true)
        if case .success(let data) = SampleData.field(field),
           let zone = data.results.waterZones.firstIndex(where: { $0.properties.advice == .water }) {
            await shoot("19-veldkaart-strook-advies", .field(preselected: "zone-\(zone)"), seconds: 6)
        }
        await shoot("20-veldkaart-sensor", .field(preselected: "sensor-\(field.id)-s1"), seconds: 6, dark: true)
        fields.selectedId = nil
        await shoot("21-veldkaart-voorbeeld", .field(preselected: nil), seconds: 6)

        saveExampleFlights()
        await shoot("22-vluchten", .tabs(.flights), seconds: 2, dark: true)
        if savedFlight != nil {
            await shoot("23-vlucht-opgeslagen", .savedFlight, seconds: 5)
        }
        ScreenTour.removeExamples(fields)
        fields.selectedId = selectedBefore
        await shoot("24-vluchten-leeg", .tabs(.flights), seconds: 2)

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

    // MARK: Example fields

    /// Two fields made from the planner's reference files, the first with two calibrated
    /// sensors and a few days of measurements.
    @MainActor
    private func makeExampleFields() -> FieldRecord? {
        guard let data = SampleData.data("voorbeeld-veld.routeplan.json"), let l = try? RoutePlanFile.read(data),
              let data2 = SampleData.data("voorbeeld-veld-schuin.routeplan.json"), let skew = try? RoutePlanFile.read(data2) else { return nil }
        let now = Date()
        var field = FieldRecord(id: ScreenTour.exampleFieldIds[0], name: "Broccoli west", boundary: l.boundary, home: l.home,
                                settings: l.settings, createdAt: now, updatedAt: now)
        let places = FieldStrips.sensorPlaces(boundary: field.boundary, angleDeg: field.lineAngleDeg, count: 2)
        field.sensors = places.enumerated().map {
            FieldSensor(id: "\(field.id)-s\($0.offset + 1)", location: $0.element, calibration: .init(dryRaw: 3100, wetRaw: 1300))
        }
        let other = FieldRecord(id: ScreenTour.exampleFieldIds[1], name: "Kool oost", boundary: skew.boundary, home: skew.home,
                                settings: skew.settings, createdAt: now.addingTimeInterval(-86400), updatedAt: now.addingTimeInterval(-86400))
        do {
            try fields.save(other)
            try fields.save(field)
        } catch {
            return nil
        }
        // s1 dries out over four days (now 25 %), s2 stays moist (about 55 %).
        var measurements: [SensorMeasurement] = []
        for (index, sensor) in field.sensors.enumerated() {
            for day in 0..<5 {
                let raw = index == 0 ? 2300 + Double(day) * 120 : 2110 - Double(day % 2) * 15
                measurements.append(SensorMeasurement(format: SensorMeasurement.format, version: 0, sensorId: sensor.id,
                                                      fieldId: field.id, location: sensor.location, depthCm: 15,
                                                      time: now.addingTimeInterval(Double(day - 4) * 86400 - 7200), raw: raw,
                                                      moisturePercent: nil, calibration: nil, batteryVolt: 3.9))
            }
        }
        SensorStore.add(measurements, fieldId: field.id)
        return field
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
