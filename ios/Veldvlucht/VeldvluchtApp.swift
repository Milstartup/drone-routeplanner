// Veldvlucht: the iPhone app of docs/STAPPENPLAN.md. Four tabs, each separate:
// - Drone: connection, battery, GPS and a test photo (step 2);
// - Route: read and check a route file from the planner, and fly it (steps 3 to 5);
// - Veldkaart: the field map with sample data or your own files (step 7);
// - Vluchten: the saved photo logs and logs, to share (step 6).
// Real flights stay locked until the simulator tests went well (FlightClearance).
import SwiftUI
import UIKit

@main
struct VeldvluchtApp: App {
    @StateObject private var drone = DJIConnection()
    @StateObject private var route = RouteModel()
    @StateObject private var fields: FieldStore
    @StateObject private var receiver: SensorReceiver
    @StateObject private var weather = WeatherService()
    @State private var screen = Screen.drone
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let fields = FieldStore()
        _fields = StateObject(wrappedValue: fields)
        _receiver = StateObject(wrappedValue: SensorReceiver(fields: fields))
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ScreenTour.isRequested {
                ScreenTourView()
            } else {
                main
            }
            #else
            main
            #endif
        }
    }

    private var main: some View {
        MainTabs(drone: drone, route: route, fields: fields, receiver: receiver, weather: weather, screen: $screen)
            .onChange(of: scenePhase) { _, phase in
                // Sensor boxes can only send while the app is open.
                if phase == .active { receiver.start() } else if phase == .background { receiver.stop() }
            }
            .onAppear {
                // The SDK drops the connection when the app goes to the background,
                // so keep the screen from locking while the app is open.
                UIApplication.shared.isIdleTimerDisabled = true
                #if DEBUG
                // The screenshots and examples of an earlier screen tour are no longer needed.
                ScreenTour.cleanUp(fields)
                #endif
                drone.start()
            }
            .onOpenURL { url in
                // A route file shared with the app (AirDrop, Files app, "Open with").
                route.load(url: url)
                screen = .route
            }
    }
}

enum Screen {
    case drone
    case route
    case field
    case flights
}

struct MainTabs: View {
    @ObservedObject var drone: DJIConnection
    @ObservedObject var route: RouteModel
    @ObservedObject var fields: FieldStore
    @ObservedObject var receiver: SensorReceiver
    @ObservedObject var weather: WeatherService
    @Binding var screen: Screen

    var body: some View {
        TabView(selection: $screen) {
            DroneTestView(drone: drone)
                .tabItem { Label { Text("Drone") } icon: { Image(uiImage: DroneGlyph.tabImage) } }
                .tag(Screen.drone)
            RouteView(model: route, fields: fields, drone: drone)
                .tabItem { Label("Route", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                .tag(Screen.route)
            FieldMapScreen(fields: fields, receiver: receiver, weather: weather)
                .tabItem { Label("Veldkaart", systemImage: "map") }
                .tag(Screen.field)
            FlightsView()
                .tabItem { Label("Vluchten", systemImage: "photo.stack") }
                .tag(Screen.flights)
        }
        .tint(.veld)
    }
}
