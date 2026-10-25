// Veldvlucht: the iPhone app of docs/STAPPENPLAN.md. Three tabs, each separate:
// - Drone: the feasibility test of step 2 (register, connect, telemetry, one photo);
// - Route: read and check a route file from the planner (first part of step 3);
// - Veldkaart: the field map with sample data (step 7).
// There are no flight commands in this app yet.
import SwiftUI
import UIKit

@main
struct VeldvluchtApp: App {
    @StateObject private var drone = DJIConnection()
    @StateObject private var route = RouteModel()
    @State private var screen = Screen.drone

    private enum Screen {
        case drone
        case route
        case field
    }

    var body: some Scene {
        WindowGroup {
            TabView(selection: $screen) {
                DroneTestView(drone: drone)
                    .tabItem { Label("Drone", systemImage: "antenna.radiowaves.left.and.right") }
                    .tag(Screen.drone)
                RouteView(model: route)
                    .tabItem { Label("Route", systemImage: "point.topleft.down.curvedto.point.bottomright.up") }
                    .tag(Screen.route)
                FieldMapScreen()
                    .tabItem { Label("Veldkaart", systemImage: "map") }
                    .tag(Screen.field)
            }
            .onAppear {
                // The SDK drops the connection when the app goes to the background,
                // so keep the screen from locking while the app is open.
                UIApplication.shared.isIdleTimerDisabled = true
                drone.start()
            }
            .onOpenURL { url in
                // A route file shared with the app (AirDrop, Files app, "Open with").
                route.load(url: url)
                screen = .route
            }
        }
    }
}
