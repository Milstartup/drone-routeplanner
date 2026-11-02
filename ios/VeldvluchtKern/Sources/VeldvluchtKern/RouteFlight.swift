// Flies a route with Virtual Stick: the control loop, the photo moments and the safety
// rules of docs/DJI-MOBILE-SDK-V4.md, chapter 6. Plain Swift without DJI code: the app
// connects it to the drone through DroneControl, and the tests to a fake drone.
//
// Rules this class keeps:
// - Only in the DJI simulator while `requireSimulator` is on (step 3 of the plan).
// - Every flight first measures which way pitch and roll move the drone.
// - The loop runs at about 10 Hz (DJI: 5 to 25 Hz) and stops steering as soon as the data
//   from the drone is old; it never catches up with old commands.
// - Moving a stick, losing the connection or tapping "Overnemen" hands control back to
//   the pilot. The app never continues by itself: resuming always takes a tap.
// - At least 2 s between photos, the shortest interval of the Mavic Mini's camera.
import Combine
import Foundation

struct FlightError: LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
}

/// Raw Virtual Stick values: pitch and roll as velocity (m/s) in the ground coordinate
/// system, yaw as angular velocity (degrees/s, clockwise positive), and the height above
/// the take-off point (vertical position mode).
struct StickValues: Equatable {
    var pitch: Double
    var roll: Double
    var yawRate: Double
    var altitudeM: Double
}

struct DroneTelemetry: Equatable {
    var time: Date
    /// Remote controller and drone connected.
    var connected: Bool
    var simulatorActive: Bool
    var position: LatLng?
    var satelliteCount: Int
    /// Height above the take-off point (barometer).
    var altitudeM: Double
    /// Compass heading, 0...360.
    var headingDeg: Double
    var velocityNorth: Double
    var velocityEast: Double
    var isFlying: Bool
    var motorsOn: Bool
    var batteryPercent: Int?
    /// From DJI's own estimate (goHomeAssessment).
    var batteryNeededToGoHome: Int?
    /// 0 (worst) to 5 (best); nil without GPS.
    var gpsLevel: Int? = nil
    /// The drone has recorded its take-off point (needed for going home).
    var homePointSet = true
    /// DJI's wind warning: 0 none, 1 strong wind, 2 very strong wind.
    var windWarning = 0
    /// Below DJI's "serious low battery" threshold.
    var seriousLowBattery = false
    /// The drone is going home or landing on its own (low battery, failsafe or the RC button).
    var droneReturningHome = false
    /// The last part of that: the drone comes down to land.
    var droneLanding = false
    /// DJI: less than 0.3 m above the ground, the drone waits until the landing is confirmed.
    var landingConfirmationNeeded = false
    /// DJI's name for the flight mode, only for the log.
    var flightMode = ""
}

/// What the flight needs from the drone. DJIConnection implements it in the app.
protocol DroneControl: AnyObject {
    /// Failsafe "go home" on connection loss, go-home height, remote controller in P mode,
    /// camera in single-photo mode.
    func prepareForRoute(goHomeHeightM: Double, completion: @escaping (Error?) -> Void)
    func takeOff(completion: @escaping (Error?) -> Void)
    /// Also sets the control modes (velocity, angular velocity, height, ground system).
    func setVirtualStick(enabled: Bool, completion: @escaping (Error?) -> Void)
    func send(_ sticks: StickValues)
    func shootPhoto(completion: @escaping (Error?) -> Void)
    func goHome(completion: @escaping (Error?) -> Void)
    func cancelGoHome(completion: @escaping (Error?) -> Void)
    /// Going home ends in a landing; only this stops that last part.
    func cancelLanding(completion: @escaping (Error?) -> Void)
}

struct FlightLogEntry: Identifiable, Equatable {
    let id = UUID()
    let time: Date
    let text: String
}

final class RouteFlight: ObservableObject {
    enum Phase: Equatable {
        case ready
        case preparing
        case takingOff
        case climbing
        case checkingAxes
        case toStart
        case flying
        case toResumePoint
        case paused(String)
        case takenOver(String)
        case returningHome
        case finished
        case failed(String)

        var label: String {
            switch self {
            case .ready: return "Klaar om te starten"
            case .preparing: return "Voorbereiden"
            case .takingOff: return "Opstijgen"
            case .climbing: return "Klimmen naar vlieghoogte"
            case .checkingAxes: return "Richtingtest"
            case .toStart: return "Naar het begin van de route"
            case .flying: return "Route vliegen"
            case .toResumePoint: return "Terug naar waar de route stopte"
            case .paused: return "Pauze: de drone hangt stil"
            case .takenOver: return "Overgenomen: jij vliegt"
            case .returningHome: return "Naar huis en landen"
            case .finished: return "Klaar"
            case .failed: return "Gestopt"
            }
        }

        /// The app steers the drone with Virtual Stick in these phases.
        var isSteering: Bool {
            switch self {
            case .climbing, .checkingAxes, .toStart, .flying, .toResumePoint, .paused: return true
            default: return false
            }
        }

        var canPause: Bool {
            switch self {
            case .climbing, .checkingAxes, .toStart, .flying, .toResumePoint: return true
            default: return false
            }
        }

        var canResume: Bool {
            switch self {
            case .paused, .takenOver: return true
            default: return false
            }
        }

        var isAirborne: Bool {
            switch self {
            case .takingOff, .climbing, .checkingAxes, .toStart, .flying, .toResumePoint, .paused, .takenOver, .returningHome:
                return true
            default:
                return false
            }
        }
    }

    struct Settings {
        /// Step 3 of the plan: fly only in DJI's simulator.
        var requireSimulator = true
        var minSatellites = 8
        var minBatteryPercent = 30
        /// Go home when the battery is this close to what DJI says is needed to get back.
        var batteryMarginPercent = 10
        var maxStartDistanceM = 30.0
        var arriveRadiusM = 1.0
        var arriveSpeedMps = 0.8
        var brakingMps2 = 1.0
        var crossGain = 0.5
        var maxCrossSpeedMps = 1.5
        var maxCrossTrackM = 8.0
        var photoLeadM = 0.3
        var photoLateM = 3.0
        var minPhotoIntervalS = 2.0
        var telemetryTimeoutS = 1.0
        var takeoffTimeoutS = 20.0
        var axisTestSpeedMps = 1.0
        var axisMoveS = 2.0
        var axisSettleS = 2.0
        var maxYawRate = 30.0
        /// Wind compensation: how fast a steady offset from the line or target is corrected.
        var windGain = 0.1
        var maxWindCorrectionMps = 3.0
        // Stricter checks for a real flight (requireSimulator off).
        var minSatellitesReal = 10
        var minGPSLevelReal = 4
        var minBatteryPercentReal = 50
        /// For the first real flights: a short route (step 5 of the plan). nil = no limit.
        var maxRouteLengthM: Double?
    }

    private struct PendingShot {
        let plannedIndex: Int
        let time: Date
        let position: LatLng
        let altitudeM: Double
        let headingDeg: Double
        /// The camera reported an error; the photo may still have been taken.
        var cameraError: String?
    }

    private enum AxisStep {
        case settle
        case pitch
        case afterPitch
        case roll
        case afterRoll
    }

    @Published private(set) var phase = Phase.ready
    @Published private(set) var legIndex = 0
    /// The next planned photo the flight will take.
    @Published private(set) var nextPhotoIndex = 0
    /// Confirmed photos in the format veld/fotolog.
    @Published private(set) var photoLog: PhotoLog
    @Published private(set) var missedPhotos: [Int] = []
    @Published private(set) var axisMapping: AxisMapping?
    @Published private(set) var log: [FlightLogEntry] = []
    @Published private(set) var telemetry: DroneTelemetry?

    let plan: FlightPlan
    let settings: Settings
    private weak var drone: DroneControl?
    private let clock: () -> Date

    private var phaseStart: Date
    /// Changes with every phase change, so a late completion can tell it is outdated.
    private var phaseVersion = 0
    private var waitingForDrone = false
    /// Virtual Stick still has to be switched off (a take-over whose first attempt failed).
    private var needsStickRelease = false
    private var lastReleaseAttempt: Date?
    private var releaseFailed = false
    /// The take-over came from a stick; counts once Virtual Stick is really off.
    private var stickReleasePending = false
    /// goHome() is still switching Virtual Stick off; the go-home command has not gone out.
    private var homeCommandPending = false
    /// A take-over asked the drone to stop going home or landing; waiting for its answer.
    private var cancellingReturn = false
    private var wasLanding = false
    private var wasWaitingToLand = false
    /// The last time the drone's data showed it going home or landing.
    private var lastReturnSeen: Date?
    /// The drone confirmed the take-off command.
    private var takeOffAccepted = false
    /// Distance along the route at the last tick with a position, for resuming without GPS.
    private var lastAlongM: Double?
    private var lastFileNumber: Int?
    /// A stick is out of the centre right now.
    @Published private(set) var sticksDeflected = false
    private var routeStarted = false
    private var resumeAlongM: Double?
    private var pendingShots: [PendingShot] = []
    private var shootInProgress = false
    private var lastShotTime: Date?
    private var axisStep = AxisStep.settle
    private var axisStepStart: Date
    private var axisMarks: [(time: Date, point: XY)] = []
    /// Built up from steady offsets, to cancel wind the drone does not cancel itself.
    private var windCorrection = XY(x: 0, y: 0)
    private var lastSteerTime: Date?
    /// Where the drone holds still while climbing or paused.
    private var holdPoint: XY?
    /// The pilot took over by moving a stick (the simulator test of that safety rule).
    @Published private(set) var stickTakeOverHappened = false
    /// First planned photo of this flight; earlier ones were done in a previous flight.
    let firstPhotoIndex: Int

    /// `startAtPhoto`: continue a route from an earlier flight (for example with a new
    /// battery) at this planned photo (docs/DJI-MOBILE-SDK-V4.md, 6.8).
    init(plan: FlightPlan, drone: DroneControl, flightId: String, fieldId: String,
         settings: Settings = Settings(), startAtPhoto: Int = 0, clock: @escaping () -> Date = Date.init) {
        self.plan = plan
        self.drone = drone
        self.settings = settings
        self.clock = clock
        photoLog = PhotoLog(format: PhotoLog.format, version: PhotoLog.version, flightId: flightId,
                            fieldId: fieldId, routePlanName: plan.name, photos: [])
        phaseStart = clock()
        axisStepStart = phaseStart
        firstPhotoIndex = min(max(0, startAtPhoto), plan.photos.count)
        if firstPhotoIndex > 0 {
            nextPhotoIndex = firstPhotoIndex
            routeStarted = true
            // A few metres before the photo, so the drone is up to speed there.
            resumeAlongM = plan.photos.indices.contains(firstPhotoIndex) ? max(0, plan.photos[firstPhotoIndex].alongM - 3) : plan.lengthM
        }
    }

    /// The first planned photo the next flight should start at, or nil when the route is done.
    var continueAtPhoto: Int? {
        nextPhotoIndex < plan.photos.count ? nextPhotoIndex : nil
    }

    // MARK: - Pilot actions

    /// Reasons the route cannot start now; empty when it can.
    func preflightProblems() -> [String] {
        guard let t = telemetry, t.connected else { return ["Geen verbinding met de drone."] }
        var problems: [String] = []
        let real = !settings.requireSimulator
        if !real && !t.simulatorActive {
            problems.append("De simulator staat uit. Start eerst de simulator.")
        }
        if real && t.simulatorActive {
            problems.append("De simulator staat nog aan. Stop hem en zet de drone uit en weer aan.")
        }
        if t.isFlying || t.motorsOn {
            problems.append("De motoren draaien al.")
        }
        if sticksDeflected {
            problems.append("Laat de sticks los.")
        }
        let minBattery = real ? settings.minBatteryPercentReal : settings.minBatteryPercent
        if let battery = t.batteryPercent {
            if battery < minBattery {
                problems.append("Accu te leeg: \(battery) % (minimaal \(minBattery) %).")
            }
        } else {
            problems.append("De accu is nog onbekend.")
        }
        if firstPhotoIndex >= plan.photos.count, !plan.photos.isEmpty {
            problems.append("Alle foto's van deze route zijn al gemaakt.")
        }
        if let maximum = settings.maxRouteLengthM, plan.lengthM > maximum {
            problems.append("Voor de eerste echte vluchten: een korte route van maximaal \(Int(maximum)) m. Deze is \(Int(plan.lengthM.rounded())) m (stap 5: 2 à 3 banen).")
        }
        if real {
            if t.windWarning >= 1 {
                problems.append("De drone meldt harde wind. Vlieg niet.")
            }
            if !t.homePointSet {
                problems.append("De drone heeft nog geen thuispunt. Wacht op GPS tot het thuispunt gezet is.")
            }
            if (t.gpsLevel ?? 0) < settings.minGPSLevelReal {
                problems.append("GPS-signaal te zwak: \(t.gpsLevel.map { "\($0)" } ?? "geen") van 5 (minimaal \(settings.minGPSLevelReal)).")
            }
        }
        guard let position = t.position else {
            problems.append("De drone heeft nog geen GPS-positie.")
            return problems
        }
        let minSatellites = real ? settings.minSatellitesReal : settings.minSatellites
        if t.satelliteCount < minSatellites {
            problems.append("Te weinig GPS-satellieten: \(t.satelliteCount) (minimaal \(minSatellites)).")
        }
        let distance = Geo.distanceM(position, plan.home)
        if distance > settings.maxStartDistanceM {
            problems.append("De drone staat \(Int(distance.rounded())) m van het startpunt van de route (maximaal \(Int(settings.maxStartDistanceM)) m).")
        }
        return problems
    }

    func start() {
        guard phase == .ready, let drone = drone else { return }
        let problems = preflightProblems()
        guard problems.isEmpty else {
            problems.forEach { addLog("Kan niet starten: \($0)") }
            return
        }
        setPhase(.preparing)
        addLog("Start\(settings.requireSimulator ? " in de simulator" : " (echte vlucht)"): \(plan.name), \(plan.photos.count) foto's op \(Int(plan.altitudeM)) m.")
        if firstPhotoIndex > 0 {
            addLog("Verder vanaf foto \(firstPhotoIndex + 1); foto 1 t/m \(firstPhotoIndex) zijn in een eerdere vlucht gemaakt.")
        }
        let goHomeHeight = max(20, plan.altitudeM)
        drone.prepareForRoute(goHomeHeightM: goHomeHeight) { [weak self] error in
            guard let self = self, self.phase == .preparing else { return }
            if let error = error {
                self.setPhase(.failed("Voorbereiden mislukt: \(error.localizedDescription)"))
                self.addLog("Voorbereiden mislukt: \(error.localizedDescription)")
                return
            }
            self.addLog("Failsafe: naar huis op \(Int(goHomeHeight)) m bij verbindingsverlies. Camera op losse foto's.")
            self.setPhase(.takingOff)
            self.addLog("Opstijgen…")
            // DJI: the completion can report an error while the take-off works, so the
            // loop decides from the telemetry whether the drone flies.
            self.drone?.takeOff { [weak self] error in
                if let error = error {
                    self?.addLog("Opstijgen meldt: \(error.localizedDescription) (de app kijkt of de drone toch vliegt).")
                } else {
                    self?.takeOffAccepted = true
                }
            }
        }
    }

    func pause() {
        guard phase.canPause else { return }
        rememberResumePoint()
        setPhase(.paused("Pauze door de piloot."))
        addLog("Pauze. De drone hangt stil; de voortgang is bewaard.")
    }

    /// From a pause or after a take-over. Always flies back to where the route stopped first.
    func resume() {
        guard !sticksDeflected else {
            addLog("Laat eerst de sticks los; daarna kun je hervatten.")
            return
        }
        switch phase {
        case .paused:
            addLog("Hervatten.")
            setPhase(.climbing)
        case .takenOver:
            addLog("Hervatten: de app neemt de besturing weer over.")
            enableSteering(then: .climbing)
        default:
            return
        }
    }

    /// Also works when already taken over: then it switches Virtual Stick off once more
    /// (for example when the first attempt failed, or a resume was being set up).
    func takeOver(reason: String = "Overgenomen door de piloot.", byStick: Bool = false) {
        switch phase {
        case .returningHome:
            if homeCommandPending {
                // The new phase stops goHome() from sending the command.
                setPhase(.takenOver(reason))
                addLog("\(reason) Naar huis is afgebroken; jij vliegt.")
                return
            }
            // The drone is going home or landing: it is only taken over once it agrees. Until
            // then the phase stays, so the screen never says "jij vliegt" while it is not true.
            guard !cancellingReturn else { return }
            cancellingReturn = true
            let landing = telemetry?.droneLanding == true
            let what = landing ? "Landen" : "Naar huis"
            let version = phaseVersion
            addLog("\(reason) \(what) afbreken…")
            let done: (Error?) -> Void = { [weak self] error in
                guard let self = self else { return }
                self.cancellingReturn = false
                guard self.phaseVersion == version else { return }
                if let error = error {
                    self.addLog("\(what) afbreken lukt niet: \(error.localizedDescription). De drone gaat zelf verder. Stoppen kan met de pauzeknop op de afstandsbediening.")
                    return
                }
                self.setPhase(.takenOver(reason))
                self.addLog("\(what) is afgebroken; jij vliegt.")
            }
            if landing {
                drone?.cancelLanding(completion: done)
            } else {
                drone?.cancelGoHome(completion: done)
            }
        case .takenOver:
            setPhase(.takenOver(reason))
            addLog("\(reason) Virtual Stick opnieuw uitzetten.")
            releaseSticks(byStick: byStick)
        case _ where phase.isSteering || phase == .takingOff:
            rememberResumePoint()
            setPhase(.takenOver(reason))
            addLog("\(reason) Virtual Stick staat uit; jij vliegt met de sticks.")
            releaseSticks(byStick: byStick)
        default:
            return
        }
    }

    /// Switches Virtual Stick off; on failure the loop tries again every second.
    private func releaseSticks(byStick: Bool) {
        needsStickRelease = true
        if byStick { stickReleasePending = true }
        lastReleaseAttempt = clock()
        drone?.setVirtualStick(enabled: false) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                if !self.releaseFailed {
                    self.addLog("Virtual Stick uitzetten lukt niet: \(error.localizedDescription). De app probeert het elke seconde opnieuw.")
                }
                self.releaseFailed = true
                return
            }
            if self.releaseFailed {
                self.addLog("Virtual Stick staat nu uit.")
            }
            self.releaseFailed = false
            self.needsStickRelease = false
            if self.stickReleasePending {
                self.stickReleasePending = false
                self.stickTakeOverHappened = true
            }
        }
    }

    func goHome(reason: String = "Naar huis door de piloot.") {
        guard phase.isAirborne, phase != .returningHome else { return }
        rememberResumePoint()
        setPhase(.returningHome)
        addLog(reason)
        let version = phaseVersion
        homeCommandPending = true
        drone?.setVirtualStick(enabled: false) { [weak self] _ in
            guard let self = self else { return }
            self.homeCommandPending = false
            // Taken over in the meantime: then the pilot flies, no go-home.
            guard self.phaseVersion == version else { return }
            self.lastReturnSeen = self.clock()
            self.drone?.goHome { [weak self] error in
                guard let self = self, self.phaseVersion == version else { return }
                // The 3 s before "no longer going home" count from the drone's answer.
                self.lastReturnSeen = self.clock()
                guard let error = error else { return }
                self.setPhase(.takenOver("Naar huis lukt niet: \(error.localizedDescription). Vlieg zelf terug."))
                self.addLog("Naar huis lukt niet: \(error.localizedDescription). Vlieg zelf terug.")
            }
        }
    }

    // MARK: - Input from the drone

    func update(_ telemetry: DroneTelemetry) {
        self.telemetry = telemetry
    }

    /// Where the sticks are: called on every change by the adapter.
    func updateSticks(deflected: Bool) {
        let wasDeflected = sticksDeflected
        sticksDeflected = deflected
        if deflected && !wasDeflected { sticksMoved() }
    }

    /// The pilot moved a stick on the remote controller.
    func sticksMoved() {
        let settingUpResume: Bool
        if case .takenOver = phase { settingUpResume = waitingForDrone } else { settingUpResume = false }
        guard phase.isSteering || phase == .takingOff || settingUpResume else { return }
        takeOver(reason: "Je bewoog een stick: de app stuurt niet meer.", byStick: true)
    }

    /// The camera reports a new file on the SD card. Files come in the order of the shots;
    /// a skipped file number means the camera did not report an earlier file, so the log
    /// never shifts one photo along.
    func photoSaved(fileName: String) {
        expireShots(clock())
        let number = Self.fileNumber(fileName)
        if let number = number, let last = lastFileNumber, number > last + 1 {
            for missing in (last + 1)..<number where pendingShots.count > 1 {
                let shot = pendingShots.removeFirst()
                missedPhotos.append(shot.plannedIndex)
                addLog("Foto \(shot.plannedIndex + 1): de camera meldde het bestand niet (waarschijnlijk nummer \(missing)). Kijk op de SD-kaart.")
            }
        }
        if let number = number { lastFileNumber = number }
        guard !pendingShots.isEmpty else {
            addLog("Nieuw bestand \(fileName), maar de app had geen foto gevraagd.")
            return
        }
        let shot = pendingShots.removeFirst()
        if let error = shot.cameraError {
            addLog("Foto \(shot.plannedIndex + 1) is toch gemaakt (de camera meldde eerst: \(error)).")
        }
        photoLog.photos.append(PhotoLog.Photo(
            index: photoLog.photos.count,
            plannedPhotoIndex: shot.plannedIndex,
            file: fileName,
            time: shot.time,
            lat: shot.position.lat,
            lng: shot.position.lng,
            altitudeM: (shot.altitudeM * 10).rounded() / 10,
            headingDeg: shot.headingDeg.rounded()
        ))
    }

    // MARK: - Control loop

    /// Call about 10 times per second.
    func tick() {
        let now = clock()
        expireShots(now)
        if needsStickRelease, case .takenOver = phase, !waitingForDrone,
           now.timeIntervalSince(lastReleaseAttempt ?? .distantPast) >= 1 {
            releaseSticks(byStick: false)
        }
        switch phase {
        case .takingOff:
            tickTakeOff(now)
        case .returningHome:
            if let t = telemetry, !t.isFlying, !t.motorsOn {
                setPhase(.finished)
                let planned = plan.photos.count - firstPhotoIndex
                addLog("Geland. \(photoLog.photos.count) van \(planned) foto's bevestigd, \(missedPhotos.count) gemist.")
                if let next = continueAtPhoto {
                    addLog("Route nog niet af: een volgende vlucht kan verder vanaf foto \(next + 1).")
                }
            } else if let t = telemetry, t.connected {
                noteLanding(t)
                if t.droneReturningHome { lastReturnSeen = now }
                // The drone stopped going home or landing by itself, for example with the pause
                // button on the remote controller: then the pilot flies. The 3 s cover the moment
                // before the drone's data shows a return that was just sent.
                let since = max(phaseStart, lastReturnSeen ?? phaseStart)
                if !t.droneReturningHome, t.isFlying, !homeCommandPending, !cancellingReturn,
                   now.timeIntervalSince(since) >= 3 {
                    setPhase(.takenOver("De drone keert niet meer terug."))
                    addLog("De drone keert niet meer terug (bijvoorbeeld door de pauzeknop op de afstandsbediening). Jij vliegt\(Self.modeNote(t)).")
                }
            }
        case .takenOver:
            if let t = telemetry, t.connected, !t.isFlying, !t.motorsOn {
                setPhase(.finished)
                addLog("Geland door de piloot. \(photoLog.photos.count) foto's bevestigd.")
                if let next = continueAtPhoto {
                    addLog("Een volgende vlucht kan verder vanaf foto \(next + 1).")
                }
            } else if let t = telemetry, t.connected, t.droneReturningHome, now.timeIntervalSince(phaseStart) >= 2 {
                // After a lost connection the drone may go home by itself (failsafe): show that.
                // Not in the first 2 s, while the drone's data may still show a cancelled return.
                // A landing here is the pilot's own (left stick down): noteLanding() reports it.
                setPhase(.returningHome)
                wasLanding = false
                wasWaitingToLand = false
                if !t.droneLanding {
                    addLog("De drone keert zelf terug (failsafe of de terugkeerknop). Overnemen kan met de knop of de afstandsbediening.")
                }
            }
        case _ where phase.isSteering:
            tickSteering(now)
        default:
            break
        }
    }

    /// ", vluchtstand: …" for the log, when the drone gave its flight mode.
    private static func modeNote(_ t: DroneTelemetry) -> String {
        t.flightMode.isEmpty ? "" : ", vluchtstand: \(t.flightMode)"
    }

    /// Says in the log when the return turns into a landing, and when the drone waits for the pilot.
    private func noteLanding(_ t: DroneTelemetry) {
        if t.droneLanding && !wasLanding {
            addLog("De drone landt.")
        }
        if t.landingConfirmationNeeded && !wasWaitingToLand {
            addLog("De drone hangt net boven de grond en wacht. Landen: houd de linkerstick omlaag tot de motoren stoppen.")
        }
        wasLanding = t.droneLanding
        wasWaitingToLand = t.landingConfirmationNeeded
    }

    private func tickTakeOff(_ now: Date) {
        guard !waitingForDrone else { return }
        if sticksDeflected {
            takeOver(reason: "Je houdt een stick vast: de app stuurt niet.", byStick: true)
            return
        }
        if let t = telemetry, t.isFlying, t.altitudeM >= 0.9, now.timeIntervalSince(phaseStart) >= 2 {
            addLog("In de lucht op \(String(format: "%.1f", t.altitudeM)) m. Virtual Stick aan.")
            enableSteering(then: .climbing)
        } else if now.timeIntervalSince(phaseStart) > settings.takeoffTimeoutS, telemetry?.isFlying != true {
            setPhase(.failed("De drone is niet opgestegen."))
            addLog("De drone is niet opgestegen binnen \(Int(settings.takeoffTimeoutS)) s.")
            // What the drone said, for finding out why (simulator test of 2 November 2026).
            let answer = takeOffAccepted ? "nam het commando aan" : "gaf geen antwoord op het commando"
            if let t = telemetry {
                addLog("De drone \(answer). Motoren \(t.motorsOn ? "aan" : "uit"), hoogte \(String(format: "%.1f", t.altitudeM)) m\(Self.modeNote(t)).")
            } else {
                addLog("De drone \(answer). Geen gegevens van de drone.")
            }
        }
    }

    private func tickSteering(_ now: Date) {
        guard !waitingForDrone, let drone = drone else { return }
        guard let t = telemetry, t.connected else {
            takeOver(reason: "Verbinding met de drone weg. Bij verlies van de verbinding keert de drone na 3 s zelf terug.")
            return
        }
        guard now.timeIntervalSince(t.time) <= settings.telemetryTimeoutS, let position = t.position else {
            if case .paused = phase {} else {
                rememberResumePoint()
                setPhase(.paused("Geen actuele gegevens van de drone."))
                addLog("Geen actuele gegevens van de drone: pauze.")
            }
            drone.send(StickValues(pitch: 0, roll: 0, yawRate: 0, altitudeM: plan.altitudeM))
            return
        }
        if settings.requireSimulator && !t.simulatorActive {
            takeOver(reason: "De simulator staat niet meer aan.")
            return
        }
        // The drone's own return (low battery, RC button) always wins: never fight it.
        if t.droneReturningHome {
            rememberResumePoint()
            setPhase(.returningHome)
            addLog("De drone keert zelf terug. De app stuurt niet meer; de voortgang is bewaard.")
            drone.setVirtualStick(enabled: false) { _ in }
            return
        }
        if let battery = t.batteryPercent,
           t.seriousLowBattery || battery <= max(15, (t.batteryNeededToGoHome ?? 0) + settings.batteryMarginPercent) {
            goHome(reason: "Accu bijna op (\(battery) %): naar huis. De voortgang is bewaard.")
            return
        }
        if t.windWarning >= 2 {
            goHome(reason: "De drone meldt zeer harde wind: naar huis. De voortgang is bewaard.")
            return
        }

        let p = plan.projection.toXY(position)
        let dt = min(0.3, max(0, now.timeIntervalSince(lastSteerTime ?? now)))
        lastSteerTime = now
        var velocity = XY(x: 0, y: 0)
        var heading: Double?

        switch phase {
        case .paused:
            velocity = hold(p, t, dt: dt)
        case .climbing:
            velocity = hold(p, t, dt: dt)
            if abs(t.altitudeM - plan.altitudeM) < 1.0 {
                if axisMapping == nil {
                    startAxisTest(now)
                } else if !routeStarted {
                    setPhase(.toStart)
                    addLog("Op hoogte. Naar het begin van de route.")
                } else {
                    setPhase(.toResumePoint)
                    addLog("Op hoogte. Terug naar waar de route stopte.")
                }
            }
        case .checkingAxes:
            sendAxisTest(now, p)
            return
        case .toStart:
            let target = plan.waypoints.first ?? p
            velocity = goTo(target, from: p, dt: dt)
            heading = plan.legs.first?.bearingDeg
            if arrived(at: target, from: p, t) {
                routeStarted = true
                legIndex = 0
                setPhase(.flying)
                addLog("Begin van de route bereikt. Route vliegen.")
            }
        case .toResumePoint:
            let target = plan.point(alongM: resumeAlongM ?? 0)
            velocity = goTo(target.point, from: p, dt: dt)
            heading = plan.legs.indices.contains(target.legIndex) ? plan.legs[target.legIndex].bearingDeg : nil
            if arrived(at: target.point, from: p, t) {
                legIndex = target.legIndex
                resumeAlongM = nil
                setPhase(.flying)
                addLog("Terug op de route. Verder met foto \(nextPhotoIndex + 1).")
            }
        case .flying:
            guard plan.legs.indices.contains(legIndex) else {
                goHome(reason: "Route klaar: naar huis.")
                return
            }
            let leg = plan.legs[legIndex]
            let track = plan.track(p, onLeg: legIndex)
            lastAlongM = leg.startAlongM + min(max(track.alongLegM, 0), leg.lengthM)
            if abs(track.crossM) > settings.maxCrossTrackM {
                rememberResumePoint()
                setPhase(.paused("Te ver van de route (\(Int(abs(track.crossM).rounded())) m)."))
                addLog("Te ver van de route (\(Int(abs(track.crossM).rounded())) m): pauze.")
                break
            }
            if leg.capture {
                triggerPhotos(alongLegM: track.alongLegM, now: now, t: t)
            }
            velocity = followLeg(leg, track: track, dt: dt)
            heading = leg.bearingDeg
            let speed = hypot(t.velocityEast, t.velocityNorth)
            if leg.lengthM - track.alongLegM < settings.arriveRadiusM, abs(track.crossM) < 2, speed < settings.arriveSpeedMps {
                missRemainingPhotos(onLeg: legIndex)
                legIndex += 1
                if legIndex >= plan.legs.count {
                    goHome(reason: "Route klaar: naar huis en landen.")
                    return
                }
            }
        default:
            break
        }

        send(velocity: velocity, heading: heading, t: t)
    }

    // MARK: - Steering

    private func send(velocity: XY, heading: Double?, t: DroneTelemetry) {
        guard let drone = drone else { return }
        let mapping = axisMapping ?? .documented
        let raw = mapping.sticks(east: velocity.x, north: velocity.y)
        var yawRate = 0.0
        if let heading = heading {
            yawRate = yawRateToward(heading, from: t.headingDeg)
        }
        drone.send(StickValues(pitch: raw.pitch, roll: raw.roll, yawRate: yawRate, altitudeM: plan.altitudeM))
    }

    /// Straight to a point, braking so the drone stops on it.
    private func goTo(_ target: XY, from p: XY, dt: Double) -> XY {
        let dx = target.x - p.x
        let dy = target.y - p.y
        let distance = hypot(dx, dy)
        // Only close to the target, so the correction does not build up on the way there.
        if distance < 2 {
            addWindCorrection(XY(x: dx, y: dy), dt: dt)
        }
        guard distance > 0.05 else { return windCorrection }
        let speed = min(plan.speedMps, (2 * settings.brakingMps2 * max(0, distance - 0.3)).squareRoot())
        return XY(x: dx / distance * speed + windCorrection.x, y: dy / distance * speed + windCorrection.y)
    }

    /// Brake first, then hang still on the spot where the drone came to rest.
    private func hold(_ p: XY, _ t: DroneTelemetry, dt: Double) -> XY {
        // Before the direction test the app does not know which way the sticks push. A
        // correction could then push the drone away, so leave holding to its own GPS hold.
        guard axisMapping != nil else { return XY(x: 0, y: 0) }
        if holdPoint == nil {
            guard hypot(t.velocityEast, t.velocityNorth) < 0.5 else { return windCorrection }
            holdPoint = p
        }
        return goTo(holdPoint ?? p, from: p, dt: dt)
    }

    private func addWindCorrection(_ error: XY, dt: Double) {
        var c = XY(x: windCorrection.x + settings.windGain * error.x * dt,
                   y: windCorrection.y + settings.windGain * error.y * dt)
        let size = hypot(c.x, c.y)
        if size > settings.maxWindCorrectionMps {
            c = XY(x: c.x / size * settings.maxWindCorrectionMps, y: c.y / size * settings.maxWindCorrectionMps)
        }
        windCorrection = c
    }

    /// Along the leg at flight speed, braking towards its end, and steering back onto the
    /// line when wind pushes the drone aside.
    private func followLeg(_ leg: FlightPlan.Leg, track: (alongLegM: Double, crossM: Double), dt: Double) -> XY {
        guard leg.lengthM > 0 else { return windCorrection }
        let ux = (leg.to.x - leg.from.x) / leg.lengthM
        let uy = (leg.to.y - leg.from.y) / leg.lengthM
        let remaining = leg.lengthM - track.alongLegM
        let along = remaining < 0
            ? max(-1, remaining * 0.5)
            : min(plan.speedMps, (2 * settings.brakingMps2 * max(0, remaining - 0.3)).squareRoot())
        let cross = min(settings.maxCrossSpeedMps, max(-settings.maxCrossSpeedMps, -settings.crossGain * track.crossM))
        // The right-hand normal of (ux, uy) is (uy, -ux). Wind: correct the sideways offset,
        // and near the end of the leg also the offset along it.
        let alongError = abs(remaining) < 2 ? remaining : 0
        if abs(track.crossM) < 3 {
            addWindCorrection(XY(x: ux * alongError - uy * track.crossM, y: uy * alongError + ux * track.crossM), dt: dt)
        }
        return XY(x: ux * along + uy * cross + windCorrection.x, y: uy * along - ux * cross + windCorrection.y)
    }

    private func arrived(at target: XY, from p: XY, _ t: DroneTelemetry) -> Bool {
        hypot(target.x - p.x, target.y - p.y) < settings.arriveRadiusM
            && hypot(t.velocityEast, t.velocityNorth) < settings.arriveSpeedMps
    }

    /// Turns the nose along the line, or straight against it, whichever is closer: the long
    /// side of the photo then lies across the flight direction, as the planner assumes.
    private func yawRateToward(_ bearing: Double, from heading: Double) -> Double {
        func difference(_ target: Double) -> Double {
            var d = (target - heading).truncatingRemainder(dividingBy: 360)
            if d > 180 { d -= 360 }
            if d < -180 { d += 360 }
            return d
        }
        let forward = difference(bearing)
        let backward = difference(bearing + 180)
        let d = abs(forward) <= abs(backward) ? forward : backward
        guard abs(d) > 2 else { return 0 }
        return min(settings.maxYawRate, max(-settings.maxYawRate, d))
    }

    private func enableSteering(then next: Phase) {
        waitingForDrone = true
        needsStickRelease = false
        let version = phaseVersion
        drone?.setVirtualStick(enabled: true) { [weak self] error in
            guard let self = self else { return }
            self.waitingForDrone = false
            // The pilot took over or chose go-home while this was on its way: undo it.
            guard self.phaseVersion == version else {
                if !self.phase.isSteering { self.releaseSticks(byStick: false) }
                return
            }
            if let error = error {
                self.setPhase(.takenOver("Virtual Stick aanzetten lukt niet: \(error.localizedDescription)"))
                self.addLog("Virtual Stick aanzetten lukt niet: \(error.localizedDescription). Jij vliegt.")
                return
            }
            self.setPhase(next)
        }
    }

    private func rememberResumePoint() {
        guard phase == .flying, plan.legs.indices.contains(legIndex) else { return }
        let leg = plan.legs[legIndex]
        guard let position = telemetry?.position else {
            // No GPS right now: the last known point on the route.
            resumeAlongM = lastAlongM ?? leg.startAlongM
            return
        }
        let track = plan.track(plan.projection.toXY(position), onLeg: legIndex)
        resumeAlongM = leg.startAlongM + min(max(track.alongLegM, 0), leg.lengthM)
    }

    // MARK: - Direction test

    private func startAxisTest(_ now: Date) {
        setPhase(.checkingAxes)
        axisStep = .settle
        axisStepStart = now
        axisMarks = []
        addLog("Richtingtest: eerst stilhangen, dan alleen pitch, dan alleen roll, elk \(Int(settings.axisMoveS)) s met \(Int(settings.axisTestSpeedMps)) m/s.")
    }

    private func sendAxisTest(_ now: Date, _ p: XY) {
        let elapsed = now.timeIntervalSince(axisStepStart)
        switch axisStep {
        case .settle:
            // Raw zero for 3 s; the last 2 s show how far wind makes the drone drift.
            if axisMarks.isEmpty, elapsed >= 1 { axisMarks.append((now, p)) }
            if elapsed >= 3 { nextAxisStep(.pitch, now, mark: p) }
        case .pitch where elapsed >= settings.axisMoveS:
            nextAxisStep(.afterPitch, now)
        case .afterPitch where elapsed >= settings.axisSettleS:
            nextAxisStep(.roll, now, mark: p)
        case .roll where elapsed >= settings.axisMoveS:
            nextAxisStep(.afterRoll, now)
        case .afterRoll where elapsed >= settings.axisSettleS:
            axisMarks.append((now, p))
            finishAxisTest()
            return
        default:
            break
        }
        let speed = settings.axisTestSpeedMps
        drone?.send(StickValues(pitch: axisStep == .pitch ? speed : 0, roll: axisStep == .roll ? speed : 0,
                                yawRate: 0, altitudeM: plan.altitudeM))
    }

    private func nextAxisStep(_ step: AxisStep, _ now: Date, mark: XY? = nil) {
        if let mark = mark { axisMarks.append((now, mark)) }
        axisStep = step
        axisStepStart = now
    }

    private func finishAxisTest() {
        // Marks: drift start, before pitch, before roll (= after pitch), after roll.
        guard axisMarks.count == 4 else { return }
        let m = axisMarks
        let driftTime = m[1].time.timeIntervalSince(m[0].time)
        let drift = driftTime > 0
            ? XY(x: (m[1].point.x - m[0].point.x) / driftTime, y: (m[1].point.y - m[0].point.y) / driftTime)
            : XY(x: 0, y: 0)
        func move(_ a: Int, _ b: Int) -> XY {
            let seconds = m[b].time.timeIntervalSince(m[a].time)
            return XY(x: m[b].point.x - m[a].point.x - drift.x * seconds, y: m[b].point.y - m[a].point.y - drift.y * seconds)
        }
        let pitchMove = move(1, 2)
        let rollMove = move(2, 3)
        do {
            let mapping = try AxisMapping.measure(pitchMove: pitchMove, rollMove: rollMove)
            axisMapping = mapping
            windCorrection = XY(x: 0, y: 0)
            let same = mapping == .documented ? "zoals DJI beschrijft" : "ANDERS dan DJI beschrijft; de app stuurt daarop bij"
            addLog("Richtingtest gelukt: \(mapping.description) (\(same)).")
            if routeStarted {
                setPhase(.toResumePoint)
            } else {
                setPhase(.toStart)
                addLog("Naar het begin van de route.")
            }
        } catch {
            setPhase(.paused(error.localizedDescription))
            addLog("\(error.localizedDescription) De route start niet. Kies Overnemen of Naar huis.")
        }
    }

    // MARK: - Photos

    private func triggerPhotos(alongLegM: Double, now: Date, t: DroneTelemetry) {
        let leg = plan.legs[legIndex]
        while nextPhotoIndex < plan.photos.count {
            let photo = plan.photos[nextPhotoIndex]
            if photo.legIndex < legIndex {
                markMissed(photo.index, "de drone was al voorbij")
                continue
            }
            guard photo.legIndex == legIndex else { return }
            let photoOnLeg = photo.alongM - leg.startAlongM
            // A photo at the very end of a leg: the drone stops within the arrival radius.
            let lead = photoOnLeg > leg.lengthM - settings.arriveRadiusM ? settings.arriveRadiusM + 0.2 : settings.photoLeadM
            guard alongLegM >= photoOnLeg - lead else { return }
            if canShoot(now) {
                shoot(photo, now: now, t: t)
                nextPhotoIndex += 1
            } else if alongLegM > photoOnLeg + settings.photoLateM {
                markMissed(photo.index, "de camera was nog niet klaar")
            }
            return
        }
    }

    /// Photos on the leg the drone is leaving that were not taken.
    private func missRemainingPhotos(onLeg index: Int) {
        while nextPhotoIndex < plan.photos.count, plan.photos[nextPhotoIndex].legIndex <= index {
            markMissed(plan.photos[nextPhotoIndex].index, "de drone was al voorbij")
        }
    }

    private func canShoot(_ now: Date) -> Bool {
        guard !shootInProgress else { return false }
        guard let last = lastShotTime else { return true }
        return now.timeIntervalSince(last) >= settings.minPhotoIntervalS
    }

    private func shoot(_ photo: FlightPlan.Photo, now: Date, t: DroneTelemetry) {
        guard let position = t.position else { return }
        shootInProgress = true
        lastShotTime = now
        pendingShots.append(PendingShot(plannedIndex: photo.index, time: now, position: position,
                                        altitudeM: t.altitudeM, headingDeg: t.headingDeg))
        drone?.shootPhoto { [weak self] error in
            guard let self = self else { return }
            self.shootInProgress = false
            if let error = error, let i = self.pendingShots.firstIndex(where: { $0.plannedIndex == photo.index }) {
                // DJI sometimes reports an error although it worked; a file may still come.
                self.pendingShots[i].cameraError = error.localizedDescription
            }
        }
    }

    /// Shots without a file: after a camera error 2 s (before the next shot's file can
    /// arrive), otherwise 10 s.
    private func expireShots(_ now: Date) {
        while let shot = pendingShots.first {
            let limit = shot.cameraError == nil ? 10.0 : 2.0
            guard now.timeIntervalSince(shot.time) > limit else { return }
            pendingShots.removeFirst()
            missedPhotos.append(shot.plannedIndex)
            addLog("Foto \(shot.plannedIndex + 1) gemist: \(shot.cameraError.map { "camera: \($0)" } ?? "de camera meldde geen bestand").")
        }
    }

    /// 96 for "DJI_0096.jpg".
    static func fileNumber(_ fileName: String) -> Int? {
        let name = (fileName as NSString).deletingPathExtension
        let digits = name.reversed().prefix { $0.isNumber }
        return digits.isEmpty ? nil : Int(String(digits.reversed()))
    }

    private func markMissed(_ index: Int, _ reason: String, advance: Bool = true) {
        missedPhotos.append(index)
        if advance { nextPhotoIndex += 1 }
        addLog("Foto \(index + 1) gemist: \(reason).")
    }

    // MARK: - Helpers

    private func setPhase(_ next: Phase) {
        phase = next
        phaseVersion += 1
        phaseStart = clock()
        holdPoint = nil
    }

    private func addLog(_ text: String) {
        log.append(FlightLogEntry(time: clock(), text: text))
    }
}
