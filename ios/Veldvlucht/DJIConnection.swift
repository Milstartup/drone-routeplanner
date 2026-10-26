// The only file that talks to the DJI SDK (the "DJI adapter" from
// docs/DJI-MOBILE-SDK-V4.md, section 6.1). It registers the app, connects to the
// drone, publishes telemetry as a DroneStatus and can take one photo.
// It never sends flight commands.
import DJISDK
import Foundation

final class DJIConnection: NSObject, ObservableObject {
    @Published private(set) var status = DroneStatus()
    @Published private(set) var log: [LogLine] = []

    private var started = false
    private var photoAttempt = 0
    // Battery and GPS go into the log once per connection, so the log holds the whole test.
    private var loggedBattery = false
    private var loggedGPS = false
    private var loggedGoodGPS = false
    private let connectionKey = DJIProductKey(param: DJIParamConnection)

    private var aircraft: DJIAircraft? { DJISDKManager.product() as? DJIAircraft }

    /// Step 1: register with DJI. The rest follows from the delegate callbacks.
    func start() {
        guard !started else { return }
        started = true
        status.sdkVersion = DJISDKManager.sdkVersion()
        status.registration = .busy
        addLog("Aanmelden bij DJI (SDK \(status.sdkVersion))…")
        DJISDKManager.registerApp(with: self)
    }

    /// Step 1 again after a failed registration, for example without internet.
    func retryRegistration() {
        guard case .failed = status.registration else { return }
        started = false
        start()
    }

    /// Step 4: one photo on the ground, saved on the drone's microSD card.
    func takePhoto() {
        guard let camera = aircraft?.camera else {
            photoFailed("Geen camera gevonden. Staat de drone aan?")
            return
        }
        guard !status.isFlying else {
            photoFailed("De drone vliegt. Deze test is alleen voor op de grond.")
            return
        }
        photoAttempt += 1
        status.photo = .busy("Camera in de fotostand zetten…")
        addLog("Foto: camera in de fotostand zetten…")

        // Newer cameras combine mode and photo type into one "flat" mode.
        if camera.isFlatCameraModeSupported() {
            camera.setFlatMode(.photoSingle) { [weak self] error in
                self?.shoot(with: camera, afterModeError: error)
            }
        } else {
            camera.setMode(.shootPhoto) { [weak self] error in
                if let error = error {
                    self?.photoFailed("Fotostand lukt niet: \(error.localizedDescription)")
                    return
                }
                camera.setShootPhotoMode(.single) { [weak self] error in
                    self?.shoot(with: camera, afterModeError: error)
                }
            }
        }
    }

    private func shoot(with camera: DJICamera, afterModeError error: Error?) {
        if let error = error {
            photoFailed("Fotostand lukt niet: \(error.localizedDescription)")
            return
        }
        status.photo = .busy("Foto maken…")
        addLog("Foto: opdracht naar de camera gestuurd…")
        let attempt = photoAttempt
        camera.startShootPhoto { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.photoFailed("Foto mislukt: \(error.localizedDescription)")
                return
            }
            self.status.photo = .busy("Foto genomen, wachten tot hij op de SD-kaart staat…")
            self.addLog("Foto: de camera meldt dat de foto genomen is.")
            // camera(_:didGenerateNewMediaFile:) confirms the file. If it never comes, say so.
            DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                guard attempt == self.photoAttempt, case .busy = self.status.photo else { return }
                self.photoFailed("Geen bevestiging van een nieuw bestand binnen 15 s. Kijk op de SD-kaart of er toch een foto staat.")
            }
        }
    }

    private func photoFailed(_ message: String) {
        status.photo = .failed(message)
        addLog("Foto: \(message)")
    }

    /// Hooks this object up to the drone's parts. Called whenever a part (dis)connects.
    private func bindComponents() {
        let product = DJISDKManager.product()
        status.model = product?.model
        aircraft?.flightController?.delegate = self
        product?.battery?.delegate = self
        product?.camera?.delegate = self
        status.hasCamera = product?.camera != nil

        if aircraft?.flightController == nil {
            status.satelliteCount = nil
            status.gpsLevel = nil
            status.motorsOn = false
            status.isFlying = false
        }
        if product?.battery == nil {
            status.batteryPercent = nil
            status.batteryVolts = nil
        }
        if product?.camera == nil {
            status.sdCard = nil
            status.sdCardReady = false
        }
    }

    /// The drone counts as connected when its flight controller is there. DJIParamConnection
    /// is already true when only the remote controller is connected ("Only RemoteController").
    private func updateAircraftConnection() {
        let onlyRemote = DJISDKManager.product()?.model == DJIAircraftModeNameOnlyRemoteController
        setAircraftConnected(!onlyRemote && aircraft?.flightController?.isConnected == true)
    }

    private func setAircraftConnected(_ connected: Bool) {
        guard connected != status.aircraftConnected else { return }
        status.aircraftConnected = connected
        loggedBattery = false
        loggedGPS = false
        loggedGoodGPS = false
        addLog(connected ? "Drone verbonden met de afstandsbediening." : "Drone niet (meer) verbonden met de afstandsbediening.")
        bindComponents()
        if connected {
            readFirmware()
            readFlightControllerFirmware()
        } else {
            status.firmware = nil
            status.firmwareUnknown = false
            status.flightControllerFirmware = nil
        }
    }

    /// The package version needs DJI's server for the Mavic Mini (DJIBaseProduct.h), and right
    /// after connecting the drone may not answer yet, so try a few times.
    private func readFirmware(triesLeft: Int = 3) {
        status.firmwareUnknown = false
        DJISDKManager.product()?.getFirmwarePackageVersion { [weak self] version, error in
            guard let self = self, self.status.aircraftConnected else { return }
            if let version = version, !version.isEmpty {
                self.status.firmware = version
                let note = version == expectedFirmware ? "zoals verwacht" : "LET OP: verwacht \(expectedFirmware)"
                self.addLog("Firmwarepakket van de drone: \(version) (\(note)).")
            } else if triesLeft > 1 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    guard self.status.aircraftConnected else { return }
                    self.readFirmware(triesLeft: triesLeft - 1)
                }
            } else {
                self.status.firmwareUnknown = true
                let reason = error?.localizedDescription ?? "geen antwoord"
                self.addLog("Firmwarepakket lezen lukt niet: \(reason). Voor de Mavic Mini vraagt de DJI-software dit op bij DJI, via internet.")
            }
        }
    }

    private func readFlightControllerFirmware() {
        aircraft?.flightController?.getFirmwareVersion { [weak self] version, error in
            guard let self = self, self.status.aircraftConnected else { return }
            if let version = version, !version.isEmpty {
                self.status.flightControllerFirmware = version
                self.addLog("Firmware van de vluchtcomputer: \(version).")
            } else {
                self.addLog("Firmware van de vluchtcomputer lezen lukt niet: \(error?.localizedDescription ?? "geen antwoord").")
            }
        }
    }

    /// DJI only documents completion blocks as running on the main queue. Delegate
    /// and key-listener callbacks go through here, because SwiftUI state may only
    /// change on the main thread.
    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    private func addLog(_ text: String) {
        log.append(LogLine(time: Date(), text: text))
        if log.count > 300 { log.removeFirst(log.count - 300) }
    }

    /// Plain-language explanation of the DJISDKRegistrationError codes that matter here.
    private func registrationMessage(_ error: Error) -> String {
        let code = (error as NSError).code
        let hint: String
        switch code {
        case -1:
            hint = "Geen internet. De iPhone heeft internet nodig bij de eerste aanmelding."
        case -3:
            hint = "De DJI-server reageert niet. Probeer het later opnieuw."
        case -2, -9, -15:
            hint = "De App Key klopt niet. Controleer DJI_APP_KEY in ios/Config/Lokaal.xcconfig."
        case -5:
            hint = "De Bundle ID past niet bij de App Key (moet nl.milanmehrzad.veldvlucht zijn)."
        case -7, -16:
            hint = "Deze App Key is op te veel toestellen geactiveerd."
        default:
            hint = error.localizedDescription
        }
        return "\(hint) (DJI-code \(code))"
    }
}

// MARK: - Registration and connection

extension DJIConnection: DJISDKManagerDelegate {
    func appRegisteredWithError(_ error: Error?) {
        onMain { [self] in
            if let error = error {
                let message = registrationMessage(error)
                status.registration = .failed(message)
                addLog("Aanmelden mislukt: \(message)")
                return
            }
            status.registration = .done
            addLog("Aangemeld bij DJI. Verbinding met de afstandsbediening zoeken…")

            if let key = connectionKey {
                DJISDKManager.keyManager()?.startListeningForChanges(on: key, withListener: self) { [weak self] _, _ in
                    self?.onMain { self?.updateAircraftConnection() }
                }
            }
            if !DJISDKManager.startConnectionToProduct() {
                addLog("Verbinding zoeken kon niet starten.")
            }
        }
    }

    func didUpdateDatabaseDownloadProgress(_ progress: Progress) {
        let fraction = progress.isFinished ? nil : progress.fractionCompleted
        onMain { [self] in status.databaseProgress = fraction }
    }

    func productConnected(_ product: DJIBaseProduct?) {
        onMain { [self] in
            status.remoteConnected = product != nil
            guard let product = product else { return }
            addLog("Afstandsbediening verbonden (\(product.model ?? "onbekend model")).")
            bindComponents()
            updateAircraftConnection()
        }
    }

    func productDisconnected() {
        onMain { [self] in
            status.remoteConnected = false
            setAircraftConnected(false)
            status.model = nil
            addLog("Afstandsbediening losgekoppeld.")
            bindComponents()
        }
    }

    func productChanged(_ product: DJIBaseProduct?) {
        onMain { [self] in
            addLog("Product gewijzigd: \(product?.model ?? "geen").")
            bindComponents()
            updateAircraftConnection()
        }
    }

    func componentConnected(withKey key: String?, andIndex index: Int) {
        onMain { [self] in
            bindComponents()
            updateAircraftConnection()
        }
    }

    func componentDisconnected(withKey key: String?, andIndex index: Int) {
        onMain { [self] in
            bindComponents()
            updateAircraftConnection()
        }
    }
}

// MARK: - Telemetry

extension DJIConnection: DJIFlightControllerDelegate {
    func flightController(_ fc: DJIFlightController, didUpdate state: DJIFlightControllerState) {
        let satellites = Int(state.satelliteCount)
        let level = gpsLevel(state.gpsSignalLevel)
        let motorsOn = state.areMotorsOn
        let isFlying = state.isFlying
        onMain { [self] in
            status.satelliteCount = satellites
            status.gpsLevel = level
            status.motorsOn = motorsOn
            status.isFlying = isFlying
            if !loggedGPS {
                loggedGPS = true
                addLog("GPS: \(satellites) satellieten, \(level.map { "signaal \($0) van 5" } ?? "geen GPS-signaal").")
            }
            if satellites >= 10, !loggedGoodGPS {
                loggedGoodGPS = true
                addLog("GPS goed: \(satellites) satellieten.")
            }
        }
    }

    private func gpsLevel(_ level: DJIGPSSignalLevel) -> Int? {
        switch level {
        case .level0: return 0
        case .level1: return 1
        case .level2: return 2
        case .level3: return 3
        case .level4: return 4
        case .level5: return 5
        default: return nil
        }
    }
}

extension DJIConnection: DJIBatteryDelegate {
    func battery(_ battery: DJIBattery, didUpdate state: DJIBatteryState) {
        let percent = Int(state.chargeRemainingInPercent)
        let volts = Double(state.voltage) / 1000 // the SDK reports millivolts
        onMain { [self] in
            status.batteryPercent = percent
            status.batteryVolts = volts
            if !loggedBattery {
                loggedBattery = true
                addLog("Accu van de drone: \(percent) % (\(dutchNumber(volts, digits: 2)) V).")
            }
        }
    }
}

// MARK: - Camera

extension DJIConnection: DJICameraDelegate {
    func camera(_ camera: DJICamera, didUpdate storageState: DJICameraStorageState) {
        let text: String
        if storageState.isInitializing {
            text = "wordt gelezen…"
        } else if !storageState.isInserted {
            text = "geen kaart in de drone"
        } else if storageState.hasError {
            text = "fout op de kaart"
        } else if storageState.isFull {
            text = "kaart is vol"
        } else {
            text = "ruimte voor \(storageState.availableCaptureCount) foto's"
        }
        let ready = storageState.isInserted && !storageState.isInitializing
            && !storageState.hasError && !storageState.isFull
        onMain { [self] in
            status.sdCard = text
            status.sdCardReady = ready
        }
    }

    func camera(_ camera: DJICamera, didGenerateNewMediaFile newMedia: DJIMediaFile) {
        let sizeMB = Double(newMedia.fileSizeInBytes) / 1_000_000
        let text = "\(newMedia.fileName) (\(dutchNumber(sizeMB, digits: 1)) MB)"
        onMain { [self] in
            status.photo = .done(text)
            addLog("Foto opgeslagen op de SD-kaart: \(text).")
        }
    }
}
