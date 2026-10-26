// Rest of step 3 (docs/STAPPENPLAN.md): fly a route in DJI's simulator. A full screen, so
// no field-map or sensor screens get in the way during a flight (docs/ARCHITECTUUR.md).
// RouteFlight (VeldvluchtKern) decides; this screen shows it and passes on the pilot's taps.
import Combine
import SwiftUI
import UIKit

/// Connects a RouteFlight to the drone, runs its control loop at 10 Hz and saves the photo log.
final class FlightSession: ObservableObject, Identifiable {
    let id = UUID()
    let file: RoutePlanFile
    let flight: RouteFlight
    private let drone: DJIConnection
    private let recorder = FlightRecorder()
    private var timer: Timer?
    private var saving: AnyCancellable?

    init(file: RoutePlanFile, drone: DJIConnection) {
        self.file = file
        self.drone = drone
        let flightId = FlightRecorder.flightId(name: file.name, date: Date())
        flight = RouteFlight(plan: FlightPlan(file), drone: drone, flightId: flightId,
                             fieldId: FlightRecorder.slug(file.name))
    }

    func open() {
        guard timer == nil else { return }
        drone.onTelemetry = { [weak self] telemetry in self?.flight.update(telemetry) }
        drone.onSticksMoved = { [weak self] in self?.flight.sticksMoved() }
        drone.onPhotoSaved = { [weak self] fileName in self?.flight.photoSaved(fileName: fileName) }
        if let telemetry = drone.lastTelemetry {
            flight.update(telemetry)
        }
        // DJI: send Virtual Stick commands between 5 and 25 times per second.
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.flight.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        saving = flight.$photoLog
            .dropFirst()
            .sink { [weak self] log in self?.recorder.save(log) }
    }

    func close() {
        timer?.invalidate()
        timer = nil
        saving = nil
        drone.onTelemetry = nil
        drone.onSticksMoved = nil
        drone.onPhotoSaved = nil
        if !flight.log.isEmpty {
            recorder.save(log: flight.log, flightId: flight.photoLog.flightId)
        }
    }
}

/// Saves each flight in the app's Documents folder. The Files app shows it under
/// "Op mijn iPhone › Veldvlucht › Vluchten" (step 6 of the plan).
struct FlightRecorder {
    let folder: URL = {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appendingPathComponent("Vluchten", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    func save(_ photoLog: PhotoLog) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(photoLog) else { return }
        try? data.write(to: folder.appendingPathComponent("\(photoLog.flightId).fotolog.json"), options: .atomic)
    }

    func save(log: [FlightLogEntry], flightId: String) {
        let text = log.map { "\(FlightView.timeText($0.time))  \($0.text)" }.joined(separator: "\n") + "\n"
        try? text.write(to: folder.appendingPathComponent("\(flightId).logboek.txt"), atomically: true, encoding: .utf8)
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
    @ObservedObject var flight: RouteFlight
    @ObservedObject var drone: DJIConnection
    @Environment(\.dismiss) private var dismiss
    @State private var confirmStart = false
    @State private var confirmResume = false
    @State private var showLog = false
    @State private var baseLayer = BaseLayer.pdok

    private var plan: FlightPlan { flight.plan }

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
            .navigationTitle("Vlucht in de simulator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Sluiten") {
                        session.close()
                        dismiss()
                    }
                    .disabled(flight.phase.isAirborne)
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
            .alert("Route starten in de simulator?", isPresented: $confirmStart) {
                Button("Starten") { flight.start() }
                Button("Annuleren", role: .cancel) {}
            } message: {
                Text("Zijn de propellers eraf? De drone blijft op de grond. In de simulator stijgt hij op naar \(Int(plan.altitudeM)) m, doet de richtingtest en vliegt de route met \(plan.photos.count) foto's. De camera maakt echt foto's op de SD-kaart.")
            }
            .alert("Hervatten?", isPresented: $confirmResume) {
                Button("Hervatten") { flight.resume() }
                Button("Annuleren", role: .cancel) {}
            } message: {
                Text("De app neemt de besturing over, gaat terug naar waar de route stopte en vliegt verder vanaf foto \(flight.nextPhotoIndex + 1).")
            }
        }
        .onAppear { session.open() }
        .onDisappear { session.close() }
    }

    // MARK: Parts

    private var phaseBanner: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(flight.phase.label).font(.headline)
                Spacer()
                Text(drone.status.simulatorActive ? "SIMULATOR" : "simulator uit")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(drone.status.simulatorActive ? Color.green : Color.orange, in: Capsule())
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
        VStack(spacing: 4) {
            ProgressView(value: Double(flight.photoLog.photos.count), total: Double(max(1, plan.photos.count)))
            HStack {
                Text("Foto's: \(flight.photoLog.photos.count) van \(plan.photos.count)")
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
                bigButton("Overnemen", "hand.raised.fill", .orange) { flight.takeOver() }
                    .disabled(!(flight.phase.isSteering || flight.phase == .takingOff || flight.phase == .returningHome))
                bigButton("Naar huis", "house.fill", .red) { flight.goHome() }
                    .disabled(flight.phase == .returningHome)
            }
            .padding()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if flight.phase == .ready {
                    ForEach(flight.preflightProblems(), id: \.self) { problem in
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                HStack(spacing: 10) {
                    if drone.status.simulatorActive {
                        bigButton("Simulator stoppen", "stop.circle", .gray) { drone.stopSimulator() }
                    } else {
                        bigButton("Simulator starten", "play.circle", .blue) { drone.startSimulator(at: plan.home) }
                            .disabled(!drone.status.aircraftConnected || drone.status.motorsOn)
                    }
                    if flight.phase == .ready {
                        bigButton("Route starten", "airplane.departure", .green) { confirmStart = true }
                            .disabled(!flight.preflightProblems().isEmpty)
                    }
                }
            }
            .padding()
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
                        .map { "\(FlightView.timeText($0.time))  \($0.text)" }
                        .joined(separator: "\n")
                } label: {
                    Label("Kopieer logboek", systemImage: "doc.on.doc")
                }
                ForEach(entries.reversed()) { entry in
                    Text("\(FlightView.timeText(entry.time))  \(entry.text)")
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
