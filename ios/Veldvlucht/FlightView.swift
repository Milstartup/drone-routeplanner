// Flying a route (steps 3 to 5 of docs/STAPPENPLAN.md). A full screen, so no field-map or
// sensor screens get in the way during a flight (docs/ARCHITECTUUR.md).
// RouteFlight (VeldvluchtKern) decides; this screen shows it and passes on the pilot's taps.
import Combine
import SwiftUI
import UIKit

/// What this iPhone has shown in the simulator. Real flights stay locked until a route was
/// flown to the end in the simulator and a stick take-over worked there (step 3 → step 5).
enum FlightClearance {
    private static let defaults = UserDefaults.standard

    static var simulatorRouteFlown: Bool {
        get { defaults.bool(forKey: "vrijgave.simulatorRoute") }
        set { defaults.set(newValue, forKey: "vrijgave.simulatorRoute") }
    }

    static var stickTakeOverTested: Bool {
        get { defaults.bool(forKey: "vrijgave.stickOvername") }
        set { defaults.set(newValue, forKey: "vrijgave.stickOvername") }
    }

    static var realFlightsFinished: Int {
        get { defaults.integer(forKey: "vrijgave.echteVluchten") }
        set { defaults.set(newValue, forKey: "vrijgave.echteVluchten") }
    }

    static var realFlightsUnlocked: Bool { simulatorRouteFlown && stickTakeOverTested }

    /// Step 5: start with a short route (2 to 3 lines) until three real flights went well.
    static var maxRouteLengthM: Double? { realFlightsFinished < 3 ? 800 : nil }
}

/// How far a route got, so a next flight (new battery) can continue there.
struct RouteProgress: Codable {
    var routeName: String
    var routeCreatedAt: String?
    var nextPhotoIndex: Int
    var photoCount: Int
    var date: Date
}

/// Connects a RouteFlight to the drone, runs its control loop at 10 Hz and saves the photo
/// log, the log and the progress.
final class FlightSession: ObservableObject, Identifiable {
    enum Mode: Hashable {
        case simulator
        case real
    }

    let id = UUID()
    let file: RoutePlanFile
    /// The field id in the photo log: the field drawn in the app, or one made from the route name.
    let fieldId: String
    @Published private(set) var flight: RouteFlight
    @Published private(set) var mode = Mode.simulator
    @Published private(set) var continuing = false
    /// Progress of an earlier flight of this route in the chosen mode (read once, not 10 times a second).
    @Published private(set) var savedProgress: RouteProgress?
    private let drone: DJIConnection
    private let recorder = FlightRecorder()
    private var timer: Timer?
    private var observers: Set<AnyCancellable> = []

    init(file: RoutePlanFile, fieldId: String? = nil, drone: DJIConnection) {
        self.file = file
        self.fieldId = fieldId ?? FlightRecorder.slug(file.name)
        self.drone = drone
        flight = Self.makeFlight(file: file, fieldId: self.fieldId, drone: drone, mode: .simulator, startAtPhoto: 0)
        savedProgress = recorder.progress(for: file, simulator: true)
    }

    /// Before the start only: simulator or real, and from the start or where the last flight stopped.
    func configure(mode: Mode, continuing: Bool) {
        guard flight.phase == .ready else { return }
        if mode == .real && !FlightClearance.realFlightsUnlocked { return }
        self.mode = mode
        savedProgress = recorder.progress(for: file, simulator: mode == .simulator)
        let start = continuing ? savedProgress?.nextPhotoIndex : nil
        self.continuing = start != nil
        flight = Self.makeFlight(file: file, fieldId: fieldId, drone: drone, mode: mode, startAtPhoto: start ?? 0)
        if let telemetry = drone.lastTelemetry {
            flight.update(telemetry)
        }
        observeFlight()
    }

    private static func makeFlight(file: RoutePlanFile, fieldId: String, drone: DJIConnection, mode: Mode, startAtPhoto: Int) -> RouteFlight {
        var settings = RouteFlight.Settings()
        settings.requireSimulator = mode == .simulator
        if mode == .real {
            settings.maxRouteLengthM = FlightClearance.maxRouteLengthM
        }
        let suffix = mode == .simulator ? "-simulator" : ""
        return RouteFlight(plan: FlightPlan(file), drone: drone,
                           flightId: FlightRecorder.flightId(name: file.name, date: Date()) + suffix,
                           fieldId: fieldId, settings: settings, startAtPhoto: startAtPhoto)
    }

    func open() {
        guard timer == nil else { return }
        drone.onTelemetry = { [weak self] telemetry in self?.flight.update(telemetry) }
        drone.onSticks = { [weak self] deflected in self?.flight.updateSticks(deflected: deflected) }
        drone.onPhotoSaved = { [weak self] fileName in self?.flight.photoSaved(fileName: fileName) }
        if let telemetry = drone.lastTelemetry {
            flight.update(telemetry)
        }
        // DJI: send Virtual Stick commands between 5 and 25 times per second.
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.flight.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        observeFlight()
    }

    func close() {
        timer?.invalidate()
        timer = nil
        observers = []
        drone.onTelemetry = nil
        drone.onSticks = nil
        drone.onPhotoSaved = nil
        if flight.phase != .ready {
            recorder.save(log: flight.log, flightId: flight.photoLog.flightId)
            saveProgress()
        }
    }

    private func observeFlight() {
        observers = []
        flight.$photoLog
            .dropFirst()
            .sink { [weak self] log in self?.recorder.save(log) }
            .store(in: &observers)
        flight.$phase
            .sink { [weak self] phase in self?.phaseChanged(phase) }
            .store(in: &observers)
        flight.$stickTakeOverHappened
            .filter { $0 }
            .sink { [weak self] _ in
                if self?.mode == .simulator { FlightClearance.stickTakeOverTested = true }
            }
            .store(in: &observers)
    }

    private func phaseChanged(_ phase: RouteFlight.Phase) {
        guard phase == .finished else { return }
        let attempted = flight.plan.photos.count - flight.firstPhotoIndex
        if mode == .simulator, attempted > 0, Double(flight.photoLog.photos.count) >= 0.9 * Double(attempted) {
            FlightClearance.simulatorRouteFlown = true
        }
        if mode == .real {
            FlightClearance.realFlightsFinished += 1
        }
        saveProgress()
    }

    private func saveProgress() {
        recorder.saveProgress(
            flight.continueAtPhoto.map {
                RouteProgress(routeName: file.name, routeCreatedAt: file.createdAt, nextPhotoIndex: $0,
                              photoCount: flight.plan.photos.count, date: Date())
            },
            for: file, simulator: mode == .simulator
        )
    }
}

/// Saves each flight in the app's Documents folder. The Files app shows it under
/// "Op mijn iPhone › Veldvlucht › Vluchten" (step 6 of the plan).
struct FlightRecorder {
    static var folder: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appendingPathComponent("Vluchten", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private var progressFolder: URL {
        let folder = Self.folder.appendingPathComponent("voortgang", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func save(_ photoLog: PhotoLog) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(photoLog) else { return }
        try? data.write(to: Self.folder.appendingPathComponent("\(photoLog.flightId).fotolog.json"), options: .atomic)
    }

    func save(log: [FlightLogEntry], flightId: String) {
        let text = log.map { "\(FlightScreen.timeText($0.time))  \($0.text)" }.joined(separator: "\n") + "\n"
        try? text.write(to: Self.folder.appendingPathComponent("\(flightId).logboek.txt"), atomically: true, encoding: .utf8)
    }

    private func progressURL(for file: RoutePlanFile, simulator: Bool) -> URL {
        progressFolder.appendingPathComponent("\(Self.slug(file.name))\(simulator ? "-simulator" : "").json")
    }

    /// Only for the same route file: a changed route starts from the beginning.
    func progress(for file: RoutePlanFile, simulator: Bool) -> RouteProgress? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: progressURL(for: file, simulator: simulator)),
              let progress = try? decoder.decode(RouteProgress.self, from: data),
              progress.routeCreatedAt == file.createdAt, progress.photoCount == file.derived.photoPoints.count,
              progress.nextPhotoIndex > 0, progress.nextPhotoIndex < progress.photoCount else { return nil }
        return progress
    }

    /// nil removes the progress: the route is done.
    func saveProgress(_ progress: RouteProgress?, for file: RoutePlanFile, simulator: Bool) {
        let url = progressURL(for: file, simulator: simulator)
        guard let progress = progress else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(progress) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// "2026-10-26-1015-broccoli-noord"
    static func flightId(name: String, date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Amsterdam")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "\(formatter.string(from: date))-\(slug(name))"
    }

    /// "Broccoli noord (voorbeeld)" → "broccoli-noord-voorbeeld"
    static func slug(_ name: String) -> String {
        let plain = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "nl_NL")).lowercased()
        let parts = plain.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return parts.isEmpty ? "route" : parts.joined(separator: "-")
    }
}

struct FlightView: View {
    @ObservedObject var session: FlightSession
    @ObservedObject var drone: DJIConnection

    var body: some View {
        FlightScreen(session: session, flight: session.flight, drone: drone)
            .onAppear { session.open() }
            .onDisappear { session.close() }
    }
}

/// The map fills the top; glass controls float over it; the panel at the bottom holds the
/// phase, the progress and the big buttons.
struct FlightScreen: View {
    @ObservedObject var session: FlightSession
    @ObservedObject var flight: RouteFlight
    @ObservedObject var drone: DJIConnection
    @Environment(\.dismiss) private var dismiss
    @State private var showChecklist = false
    @State private var confirmResume = false
    @State private var showLog = false
    @State private var baseLayer = BaseLayer.pdok

    private var plan: FlightPlan { flight.plan }
    private var isSimulator: Bool { session.mode == .simulator }
    private var canClose: Bool { !(flight.phase.isAirborne || flight.phase == .preparing) }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                MapCanvas(
                    shapes: RouteMapView.shapes(for: session.file),
                    pins: RouteMapView.pins(for: session.file),
                    contentID: session.id.uuidString,
                    baseLayer: baseLayer,
                    pinColors: photoColors,
                    movingPin: dronePin,
                    fitInsets: UIEdgeInsets(top: 235, left: 44, bottom: 60, right: 44),
                    controlInsets: UIEdgeInsets(top: 130, left: 12, bottom: 34, right: 12)
                )
                .ignoresSafeArea(edges: .top)
                .overlay(alignment: .bottomLeading) {
                    MapAttribution(layer: baseLayer).padding(.leading, 12).padding(.bottom, 32)
                }
                VStack(spacing: 8) {
                    topBar
                    telemetryRow
                    extraChips
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }
            panel
                .padding(.top, -24)
        }
        .background(Color.groupedBackground.ignoresSafeArea())
        .animation(.snappy, value: flight.phase)
        .sheet(isPresented: $showLog) {
            FlightLogView(entries: flight.log)
        }
        .sheet(isPresented: $showChecklist) {
            StartChecklist(isSimulator: isSimulator, altitudeM: Int(plan.altitudeM)) {
                flight.start()
            }
        }
        .alert("Hervatten?", isPresented: $confirmResume) {
            Button("Hervatten") { flight.resume() }
            Button("Annuleren", role: .cancel) {}
        } message: {
            Text("De app neemt de besturing over, gaat terug naar waar de route stopte en vliegt verder vanaf foto \(flight.nextPhotoIndex + 1).")
        }
        // Feel it in your hand when the app stops steering or the route is done.
        .sensoryFeedback(trigger: flight.phase) { _, phase in
            switch phase {
            case .takenOver, .failed: return .warning
            case .paused: return .impact(weight: .medium)
            case .finished: return .success
            default: return nil
            }
        }
    }

    // MARK: Over the map

    private var topBar: some View {
        ZStack {
            HStack(spacing: 8) {
                Button {
                    session.close()
                    dismiss()
                } label: {
                    GlassCircle(symbol: "xmark")
                }
                .accessibilityLabel("Sluiten")
                .disabled(!canClose)
                .opacity(canClose ? 1 : 0.45)
                Spacer()
                Button {
                    showLog = true
                } label: {
                    GlassCircle(symbol: "list.bullet.rectangle")
                }
                .accessibilityLabel("Logboek")
                BaseLayerMenu(layer: $baseLayer, style: .floating)
            }
            modeBadge
        }
        .buttonStyle(.plain)
    }

    private var modeBadge: some View {
        let (text, color): (String, Color) = isSimulator
            ? (drone.status.simulatorActive ? ("SIMULATOR", .actionGo) : ("SIMULATOR UIT", .actionTakeOver))
            : ("ECHTE VLUCHT", .actionStop)
        return Text(text)
            .font(.subheadline.weight(.heavy))
            .tracking(0.6)
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(color.gradient, in: Capsule())
            .shadow(color: .black.opacity(0.2), radius: 8, y: 3)
    }

    private var telemetryRow: some View {
        let t = flight.telemetry
        return HStack(spacing: 8) {
            telemetryTile("Hoogte", t.map { dutchNumber($0.altitudeM, digits: 1) } ?? "–", "m")
            telemetryTile("Snelheid", t.map { dutchNumber(hypot($0.velocityNorth, $0.velocityEast), digits: 1) } ?? "–", "m/s")
            telemetryTile("Accu", t?.batteryPercent.map(String.init) ?? "–", "%", color: batteryColor(t?.batteryPercent))
            telemetryTile("GPS", t.map { "\($0.satelliteCount)" } ?? "–", nil, color: t.map { $0.satelliteCount >= 10 ? .primary : .orange } ?? .primary)
        }
    }

    private func telemetryTile(_ label: String, _ value: String, _ unit: String?, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 16)
        .accessibilityElement(children: .combine)
    }

    private func batteryColor(_ percent: Int?) -> Color {
        guard let percent else { return .primary }
        return percent < 30 ? .red : (percent < 50 ? .orange : .primary)
    }

    @ViewBuilder
    private var extraChips: some View {
        let wind = flight.telemetry?.windWarning ?? 0
        if wind > 0 || flight.axisMapping != nil {
            HStack(spacing: 8) {
                if wind > 0 {
                    chip(wind == 1 ? "Harde wind" : "Zeer harde wind", "wind", .orange)
                }
                if let mapping = flight.axisMapping {
                    chip(mapping.description, "move.3d", .secondary)
                }
                Spacer()
            }
        }
    }

    private func chip(_ text: String, _ symbol: String, _ color: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color == .secondary ? Color.primary : color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glass(Capsule())
    }

    // MARK: The panel

    private var panel: some View {
        VStack(alignment: .leading, spacing: 16) {
            phaseHeader
            if flight.phase != .ready {
                progress
            }
            controls
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.15), radius: 16, y: -4)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var phaseHeader: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: phaseSymbol, color: phaseColor, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(flight.phase.label)
                    .font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                if let reason = phaseReason {
                    Text(reason)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(phaseColor)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(phaseHint)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var phaseReason: String? {
        switch flight.phase {
        case .paused(let reason), .takenOver(let reason), .failed(let reason): return reason
        default: return nil
        }
    }

    private var phaseHint: String {
        switch flight.phase {
        case .ready: return "\(plan.name) · \(plan.photos.count) foto's"
        case .preparing: return "Instellingen naar de drone sturen."
        case .takingOff: return "De motoren starten."
        case .climbing: return "Naar \(Int(plan.altitudeM)) m boven het startpunt."
        case .checkingAxes: return "De drone test welke kant hij op gaat."
        case .toStart: return "Naar het eerste routepunt."
        case .flying: return "Foto's maken langs de banen."
        case .toResumePoint: return "Daarna verder vanaf foto \(flight.nextPhotoIndex + 1)."
        case .returningHome: return "De drone vliegt terug naar het startpunt en landt."
        case .finished: return "\(flight.photoLog.photos.count) foto's in het fotolog. Je vindt ze bij Vluchten."
        case .paused, .takenOver, .failed: return ""
        }
    }

    private var phaseSymbol: String {
        switch flight.phase {
        case .ready: return "checklist"
        case .preparing: return "gearshape.fill"
        case .takingOff: return "arrow.up"
        case .climbing: return "arrow.up.to.line"
        case .checkingAxes: return "move.3d"
        case .toStart: return "flag.fill"
        case .flying: return "camera.fill"
        case .toResumePoint: return "arrow.uturn.backward"
        case .paused: return "pause.fill"
        case .takenOver: return "hand.raised.fill"
        case .returningHome: return "house.fill"
        case .finished: return "checkmark"
        case .failed: return "exclamationmark.octagon.fill"
        }
    }

    private var phaseColor: Color {
        switch flight.phase {
        case .ready: return .gray
        case .paused: return .actionHold
        case .takenOver: return .actionTakeOver
        case .returningHome, .failed: return .actionStop
        default: return .actionGo
        }
    }

    private var progress: some View {
        let planned = plan.photos.count - flight.firstPhotoIndex
        let taken = flight.photoLog.photos.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                BigValue(value: "\(taken)", unit: "van \(planned) foto's", size: .title2)
                Spacer()
                Text("Stuk \(min(flight.legIndex + 1, plan.legs.count)) van \(plan.legs.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            ProgressBar(fraction: Double(taken) / Double(max(1, planned)))
            if flight.firstPhotoIndex > 0 || !flight.missedPhotos.isEmpty {
                HStack(spacing: 12) {
                    if flight.firstPhotoIndex > 0 {
                        Label("vanaf foto \(flight.firstPhotoIndex + 1)", systemImage: "arrow.turn.down.right")
                            .foregroundStyle(.secondary)
                    }
                    if !flight.missedPhotos.isEmpty {
                        Label("\(flight.missedPhotos.count) gemist", systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.footnote.weight(.medium))
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        if flight.phase.isAirborne {
            VStack(spacing: 10) {
                // DJI stops just above the ground and waits until the pilot confirms the landing.
                if flight.canConfirmLanding {
                    Button { flight.confirmLanding() } label: { Label("Landen", systemImage: "arrow.down.to.line") }
                        .buttonStyle(ActionButtonStyle(color: .actionGo))
                }
                HStack(spacing: 10) {
                    if flight.phase.canResume {
                        Button { confirmResume = true } label: { Label("Hervatten", systemImage: "play.fill") }
                            .buttonStyle(ActionButtonStyle(color: .actionGo, stacked: true))
                    } else {
                        Button { flight.pause() } label: { Label("Pauze", systemImage: "pause.fill") }
                            .buttonStyle(ActionButtonStyle(color: .actionHold, stacked: true))
                            .disabled(!flight.phase.canPause)
                    }
                    // Also after a take-over: tapping again switches Virtual Stick off once more.
                    Button { flight.takeOver() } label: { Label("Overnemen", systemImage: "hand.raised.fill") }
                        .buttonStyle(ActionButtonStyle(color: .actionTakeOver, stacked: true))
                    Button { flight.goHome() } label: { Label("Naar huis", systemImage: "house.fill") }
                        .buttonStyle(ActionButtonStyle(color: .actionStop, stacked: true))
                        .disabled(flight.phase == .returningHome)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                if flight.phase == .ready {
                    choices
                    readiness
                }
                VStack(spacing: 10) {
                    if isSimulator || drone.status.simulatorActive {
                        if drone.status.simulatorActive {
                            Button { drone.stopSimulator() } label: { Label("Simulator stoppen", systemImage: "stop.circle") }
                                .buttonStyle(ActionButtonStyle(color: .actionHold, prominent: false))
                        } else {
                            Button { drone.startSimulator(at: plan.home) } label: { Label("Simulator starten", systemImage: "play.circle") }
                                .buttonStyle(ActionButtonStyle(color: .actionHold, prominent: flight.phase == .ready))
                                .disabled(!drone.status.aircraftConnected || drone.status.motorsOn)
                        }
                    }
                    if flight.phase == .ready {
                        Button { showChecklist = true } label: {
                            Label(isSimulator ? "Route starten" : "Echt vliegen", systemImage: "airplane.departure")
                        }
                        .buttonStyle(ActionButtonStyle(color: isSimulator ? .actionGo : .actionStop))
                        .disabled(!flight.preflightProblems().isEmpty)
                    } else if canClose {
                        Button {
                            session.close()
                            dismiss()
                        } label: {
                            Label("Sluiten", systemImage: "xmark")
                        }
                        .buttonStyle(ActionButtonStyle(color: .gray, prominent: false))
                    }
                }
            }
        }
    }

    /// Simulator or real, and from the start or where the last flight stopped.
    @ViewBuilder
    private var choices: some View {
        if FlightClearance.realFlightsUnlocked {
            VStack(alignment: .leading, spacing: 6) {
                Picker("Soort vlucht", selection: Binding(
                    get: { session.mode },
                    set: { session.configure(mode: $0, continuing: false) }
                )) {
                    Text("Simulator").tag(FlightSession.Mode.simulator)
                    Text("Echt vliegen").tag(FlightSession.Mode.real)
                }
                .pickerStyle(.segmented)
                if let limit = FlightClearance.maxRouteLengthM, !isSimulator {
                    Text("Eerste echte vluchten: routes tot \(Int(limit)) m (nog \(3 - FlightClearance.realFlightsFinished) vlucht(en)).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("Echt vliegen wordt vrijgegeven na:")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                clearanceItem("een route afgevlogen in de simulator", FlightClearance.simulatorRouteFlown)
                clearanceItem("overnemen met een stick in de simulator", FlightClearance.stickTakeOverTested)
            }
        }
        if let progress = session.savedProgress {
            Toggle(isOn: Binding(
                get: { session.continuing },
                set: { session.configure(mode: session.mode, continuing: $0) }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Verder vanaf foto \(progress.nextPhotoIndex + 1) van \(progress.photoCount)")
                        .font(.subheadline.weight(.semibold))
                    Text("Vorige vlucht: \(progress.date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tint(.veld)
        }
    }

    private func clearanceItem(_ text: String, _ done: Bool) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.green : Color.secondary)
        }
        .font(.footnote)
    }

    /// What still stands in the way of the start, or that everything is ready.
    @ViewBuilder
    private var readiness: some View {
        let problems = flight.preflightProblems()
        if problems.isEmpty {
            Notice(text: "Alles klaar om te starten.", symbol: "checkmark.circle.fill", color: .green)
                .padding(12)
                .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(problems, id: \.self) { problem in
                    Notice(text: problem)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: Map content

    private var photoColors: [String: UIColor] {
        var colors: [String: UIColor] = [:]
        for index in 0..<flight.firstPhotoIndex {
            colors["foto-\(index)"] = .systemGray
        }
        for photo in flight.photoLog.photos {
            if let index = photo.plannedPhotoIndex { colors["foto-\(index)"] = .systemGreen }
        }
        for index in flight.missedPhotos {
            colors["foto-\(index)"] = .systemRed
        }
        return colors
    }

    private var dronePin: MapPin? {
        guard let position = flight.telemetry?.position else { return nil }
        return MapPin(id: "drone", coordinate: position, title: nil, style: .marker(symbol: "airplane", color: .systemRed))
    }

    static func timeText(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .standard)
    }
}

/// A thick progress bar in the app's green.
struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(uiColor: .tertiarySystemFill))
                Capsule()
                    .fill(Color.veld.gradient)
                    .frame(width: max(10, geometry.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 10)
        .animation(.snappy, value: fraction)
        .accessibilityElement()
        .accessibilityValue("\(Int((fraction * 100).rounded())) procent")
    }
}

/// Before the start: tick every item, then start. For a real flight this is the checklist of
/// step 5; in the simulator a short one (propellers off).
struct StartChecklist: View {
    let isSimulator: Bool
    let altitudeM: Int
    let start: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var ticked: Set<Int> = []

    private var items: [String] {
        if isSimulator {
            return [
                "De propellers zijn eraf.",
                "De drone staat op de grond en blijft daar: alleen de simulator vliegt.",
                "Er zit een SD-kaart in: de camera maakt echte foto's.",
            ]
        }
        return [
            "Propellers erop en goed vast.",
            "Je staat bij het startpunt en ziet de drone de hele vlucht.",
            "Geen mensen, dieren of obstakels op de route.",
            "Wind ruim onder 8 m/s, geen regen.",
            "Je mag hier vliegen: registratie, geen no-fly-zone, maximaal 120 m.",
            "Je houdt de afstandsbediening vast. Bij twijfel: een stick bewegen of Overnemen.",
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        IconBadge(symbol: isSimulator ? "airplane.departure" : "exclamationmark.triangle.fill",
                                  color: isSimulator ? .actionGo : .actionStop, size: 48)
                        Text(isSimulator ? "Route starten in de simulator?" : "Echt vliegen?")
                            .font(.title2.weight(.bold))
                    }
                    Text(isSimulator
                         ? "In de simulator stijgt de drone op naar \(altitudeM) m, doet de richtingtest en vliegt de route."
                         : "De drone stijgt echt op naar \(altitudeM) m en vliegt de route zelf. Vink alles af.")
                        .foregroundStyle(.secondary)
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            if index > 0 { Divider().padding(.leading, 46) }
                            Button {
                                if ticked.contains(index) { ticked.remove(index) } else { ticked.insert(index) }
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: ticked.contains(index) ? "checkmark.circle.fill" : "circle")
                                        .font(.title2)
                                        .foregroundStyle(ticked.contains(index) ? Color.green : Color.secondary)
                                    Text(item)
                                        .foregroundStyle(.primary)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(ticked.contains(index) ? .isSelected : [])
                            .sensoryFeedback(.selection, trigger: ticked.contains(index))
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Design.cornerRadius, style: .continuous))
                }
                .padding()
            }
            .screenBackground()
            .safeAreaInset(edge: .bottom) {
                Button {
                    dismiss()
                    start()
                } label: {
                    Label(isSimulator ? "Starten" : "Alles gecontroleerd: opstijgen", systemImage: "airplane.departure")
                }
                .buttonStyle(ActionButtonStyle(color: isSimulator ? .actionGo : .actionStop))
                .disabled(ticked.count < items.count)
                .padding()
                .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleren") { dismiss() }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct FlightLogView: View {
    let entries: [FlightLogEntry]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(entries.reversed()) { entry in
                    LogLineText(time: entry.time, text: entry.text)
                }
            }
            .listStyle(.plain)
            .overlay {
                if entries.isEmpty {
                    Text("Nog niets in het logboek.").foregroundStyle(.secondary)
                }
            }
            .safeAreaInset(edge: .bottom) {
                CopyLogButton(lines: entries.map { ($0.time, $0.text) })
                    .disabled(entries.isEmpty)
                    .padding()
                    .background(.bar)
            }
            .navigationTitle("Logboek van de vlucht")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klaar") { dismiss() }
                }
            }
        }
    }
}
