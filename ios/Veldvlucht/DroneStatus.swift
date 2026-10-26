// What the screen shows about the drone. Plain Swift without DJI types, so the
// UI never touches the DJI SDK; DJIConnection fills this in.
import Foundation

/// The firmware the iOS SDK 4.16.2 lists for the Mavic Mini. Do not update the drone.
let expectedFirmware = "01.00.0500"

struct DroneStatus {
    enum Registration: Equatable {
        case notStarted
        case busy
        case done
        case failed(String)
    }

    enum Photo: Equatable {
        case idle
        case busy(String)
        case done(String)
        case failed(String)
    }

    var sdkVersion = ""
    var registration = Registration.notStarted
    /// Fly Safe database download, 0...1. nil when no download is running.
    var databaseProgress: Double?

    /// iPhone ↔ remote controller (the cable).
    var remoteConnected = false
    /// Remote controller ↔ drone (the radio link).
    var aircraftConnected = false
    var model: String?
    /// Firmware package version, such as 01.00.0500. For the Mavic Mini the SDK asks DJI's server.
    var firmware: String?
    /// True when the package version could not be read (see the log for the reason).
    var firmwareUnknown = false
    /// The flight controller's own firmware version; readable without internet.
    var flightControllerFirmware: String?

    var batteryPercent: Int?
    var batteryVolts: Double?
    var satelliteCount: Int?
    /// 0 (worst) to 5 (best); nil when the drone reports no GPS at all.
    var gpsLevel: Int?
    var motorsOn = false
    var isFlying = false

    var hasCamera = false
    var sdCard: String?
    var sdCardReady = false
    var photo = Photo.idle

    var canTakePhoto: Bool {
        if case .busy = photo { return false }
        return aircraftConnected && hasCamera && sdCardReady && !isFlying
    }
}

struct LogLine: Identifiable {
    let id = UUID()
    let time: Date
    let text: String
}
