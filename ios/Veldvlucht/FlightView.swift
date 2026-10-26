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
    @Published private(set) var flight: RouteFlight
    @Published private(set) var mode = Mode.simulator
    @Published private(set) var continuing = false
    /// Progress of an earlier flight of this route in the chosen mode (read once, not 10 times a second).
    @Published private(set) var savedProgress: RouteProgress?
    private let drone: DJIConnection
    private let recorder = FlightRecorder()
    private var timer: Timer?
    private var observers: Set<AnyCancellable> = []

    init(file: RoutePlanFile, drone: DJIConnection) {
        self.file = file
        self.drone = drone
        flight = Self.makeFlight(file: file, drone: drone, mode: .simulator, startAtPhoto: 0)
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
        flight = Self.makeFlight(file: file, drone: drone, mode: mode, startAtPhoto: start ?? 0)
        if let telemetry = drone.lastTelemetry {
            flight.update(telemetry)
        }
        observeFlight()
    }

    private static func makeFlight(file: RoutePlanFile, drone: DJIConnection, mode: Mode, startAtPhoto: Int) -> RouteFlight {
        var settings = RouteFlight.Settings()
        settings.requireSimulator = mode == .simulator
        if mode == .real {
            settings.maxRouteLengthM = FlightClearance.maxRouteLengthM
        }
        let suffix = mode == .simulator ? "-simulator" : ""
        return RouteFlight(plan: FlightPlan(file), drone: drone,
                           flightId: FlightRecorder.flightId(name: file.name, date: Date()) + suffix,
                           fieldId: FlightRecorder.slug(file.name), settings: settings, startAtPhoto: startAtPhoto)
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

struct FlightScreen: View {
    @ObservedObject var session: FlightSession
    @ObservedObject var flight: RouteFlight
    @ObservedObject var drone: DJIConnection
    @Environment(\.dismiss) private var dismiss
    @State private var confirmStart = false
    @State private var confirmResume = false
    @State private var showLog = false
    @State private var baseLayer = BaseLayer.pdok

    private var plan: FlightPlan { flight.plan }
    private var isSimulator: Bool { session.mode == .simulator }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                phaseBanner
                MapCanvas(
                    shapes: RouteMapView.shapes(for: session.file),
                    pins: RouteMapView.pins(for: session.file),
                    contentID: session.id.uuidString,
                    baseLayer: baseLayer,
                    pinColors: photoColors,
                    movingPin: dronePin
                )
                .overlay(alignment: .topLeading) { telemetryChips.padding(8) }
                .overlay(alignment: .bottom) { MapAttribution(layer: baseLayer).padding(.bottom, 6) }
                progress
                controls
            }
            .navigationTitle(isSimulator ? "Vlucht in de simulator" : "Echte vlucht")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sluiten") {
                        session.close()
                        dismiss()
                    }
                    .disabled(flight.phase.isAirborne || flight.phase == .preparing)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    BaseLayerMenu(layer: $baseLayer)
                    Button {
                        showLog = true
                    } label: {
                        Label("Logboek", systemImage: "list.bullet.rectangle")
                    }
                }
            }
            .sheet(isPresented: $showLog) {
                FlightLogView(entries: flight.log)
            }
            .alert(isSimulator ? "Route starten in de simulator?" : "Echt vliegen?", isPresented: $confirmStart) {
                Button(isSimulator ? "Starten" : "Alles gecontroleerd: opstijgen") { flight.start() }
                Button("Annuleren", role: .cancel) {}
            } message: {
                Text(isSimulator ? simulatorCheck : realCheck)
            }
            .alert("Hervatten?", isPresented: $confirmResume) {
                Button("Hervatten") { flight.resume() }
                Button("Annuleren", role: .cancel) {}
            } message: {
                Text("De app neemt de besturing over, gaat terug naar waar de route stopte en vliegt verder vanaf foto \(flight.nextPhotoIndex + 1).")
            }
        }
    }

    private var simulatorCheck: String {
        "Zijn de propellers eraf? De drone blijft op de grond. In de simulator stijgt hij op naar \(Int(plan.altitudeM)) m, doet de richtingtest en vliegt de route. De camera maakt echt foto's op de SD-kaart."
    }

    private var realCheck: String {
        """
        De drone stijgt echt op naar \(Int(plan.altitudeM)) m en vliegt de route zelf. Controleer:
        • propellers erop en goed vast;
        • je staat bij het startpunt en ziet de drone de hele vlucht;
        • geen mensen, dieren of obstakels op de route;
        • wind ruim onder 8 m/s, geen regen;
        • je mag hier vliegen (registratie, geen no-fly-zone, max. 120 m);
        • je houdt de afstandsbediening vast: bij twijfel een stick bewegen of Overnemen.
        """
    }

    // MARK: Parts

    private var phaseBanner: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(flight.phase.label).font(.headline)
                Spacer()
                Text(isSimulator ? (drone.status.simulatorActive ? "SIMULATOR" : "simulator uit") : "ECHT")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(isSimulator ? (drone.status.simulatorActive ? Color.green : Color.orange) : Color.red, in: Capsule())
                    .foregroundStyle(.white)
            }
            if let reason = phaseReason {
                Text(reason).font(.subheadline).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(phaseColor.opacity(0.15))
    }

    private var phaseReason: String? {
        switch flight.phase {
        case .paused(let reason), .takenOver(let reason), .failed(let reason): return reason
        default: return nil
        }
    }

    private var phaseColor: Color {
        switch flight.phase {
        case .paused, .takenOver: return .orange
        case .failed: return .red
        case .finished: return .green
        case .ready: return .gray
        default: return .blue
        }
    }

    private var telemetryChips: some View {
        let t = flight.telemetry
        return VStack(alignment: .leading, spacing: 4) {
            chip("Hoogte", t.map { "\(dutchNumber($0.altitudeM, digits: 1)) m" } ?? "–")
            chip("Snelheid", t.map { "\(dutchNumber(hypot($0.velocityNorth, $0.velocityEast), digits: 1)) m/s" } ?? "–")
            chip("Accu", t?.batteryPercent.map { "\($0) %" } ?? "–")
            chip("GPS", t.map { "\($0.satelliteCount)" } ?? "–")
            if let wind = t?.windWarning, wind > 0 {
                chip("Wind", wind == 1 ? "hard" : "zeer hard")
            }
            if let mapping = flight.axisMapping {
                chip("Assen", mapping.description)
            }
        }
        .font(.caption)
    }

    private func chip(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            Text(value).bold()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.thinMaterial, in: Capsule())
    }

    private var progress: some View {
        let planned = plan.photos.count - flight.firstPhotoIndex
        return VStack(spacing: 4) {
            ProgressView(value: Double(flight.photoLog.photos.count), total: Double(max(1, planned)))
            HStack {
                Text("Foto's: \(flight.photoLog.photos.count) van \(planned)")
                if flight.firstPhotoIndex > 0 {
                    Text("(vanaf \(flight.firstPhotoIndex + 1))").foregroundStyle(.secondary)
                }
                if !flight.missedPhotos.isEmpty {
                    Text("· \(flight.missedPhotos.count) gemist").foregroundStyle(.orange)
                }
                Spacer()
                Text("Stuk \(min(flight.legIndex + 1, plan.legs.count)) van \(plan.legs.count)")
            }
            .font(.caption)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var controls: some View {
        if flight.phase.isAirborne {
            HStack(spacing: 10) {
                if flight.phase.canResume {
                    bigButton("Hervatten", "play.fill", .green) { confirmResume = true }
                } else {
                    bigButton("Pauze", "pause.fill", .blue) { flight.pause() }
                        .disabled(!flight.phase.canPause)
                }
                // Also after a take-over: tapping again switches Virtual Stick off once more.
                bigButton("Overnemen", "hand.raised.fill", .orange) { flight.takeOver() }
                bigButton("Naar huis", "house.fill", .red) { flight.goHome() }
                    .disabled(flight.phase == .returningHome)
            }
            .padding()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if flight.phase == .ready {
                    choices
                    ForEach(flight.preflightProblems(), id: \.self) { problem in
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                HStack(spacing: 10) {
                    if isSimulator || drone.status.simulatorActive {
                        if drone.status.simulatorActive {
                            bigButton("Simulator stoppen", "stop.circle", .gray) { drone.stopSimulator() }
                        } else {
                            bigButton("Simulator starten", "play.circle", .blue) { drone.startSimulator(at: plan.home) }
                                .disabled(!drone.status.aircraftConnected || drone.status.motorsOn)
                        }
                    }
                    if flight.phase == .ready {
                        bigButton(isSimulator ? "Route starten" : "Echt vliegen", "airplane.departure", isSimulator ? .green : .red) {
                            confirmStart = true
                        }
                        .disabled(!flight.preflightProblems().isEmpty)
                    }
                }
            }
            .padding()
        }
    }

    /// Simulator or real, and from the start or where the last flight stopped.
    @ViewBuilder
    private var choices: some View {
        if FlightClearance.realFlightsUnlocked {
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
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Text("Echt vliegen wordt vrijgegeven na een simulatorvlucht die klaar is \(FlightClearance.simulatorRouteFlown ? "✓" : "✗") en overnemen met een stick in de simulator \(FlightClearance.stickTakeOverTested ? "✓" : "✗").")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if let progress = session.savedProgress {
            Toggle(isOn: Binding(
                get: { session.continuing },
                set: { session.configure(mode: session.mode, continuing: $0) }
            )) {
                Text("Verder vanaf foto \(progress.nextPhotoIndex + 1) van \(progress.photoCount) (vorige vlucht \(progress.date.formatted(date: .abbreviated, time: .shortened)))")
                    .font(.footnote)
            }
        }
    }

    private func bigButton(_ title: String, _ symbol: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
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

private struct FlightLogView: View {
    let entries: [FlightLogEntry]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button {
                    UIPasteboard.general.string = entries
                        .map { "\(FlightScreen.timeText($0.time))  \($0.text)" }
                        .joined(separator: "\n")
                } label: {
                    Label("Kopieer logboek", systemImage: "doc.on.doc")
                }
                ForEach(entries.reversed()) { entry in
                    Text("\(FlightScreen.timeText(entry.time))  \(entry.text)")
                        .font(.footnote.monospaced())
                }
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
