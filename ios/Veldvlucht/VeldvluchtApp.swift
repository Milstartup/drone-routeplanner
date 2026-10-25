// Veldvlucht, step 2 of docs/STAPPENPLAN.md: a feasibility test that registers
// with DJI, connects to the Mavic Mini, shows battery, GPS and firmware, and
// takes one photo on the ground. No flight commands.
import SwiftUI
import UIKit

@main
struct VeldvluchtApp: App {
    @StateObject private var drone = DJIConnection()

    var body: some Scene {
        WindowGroup {
            ContentView(drone: drone)
                .onAppear {
                    // The SDK drops the connection when the app goes to the background,
                    // so keep the screen from locking while the app is open.
                    UIApplication.shared.isIdleTimerDisabled = true
                    drone.start()
                }
        }
    }
}
