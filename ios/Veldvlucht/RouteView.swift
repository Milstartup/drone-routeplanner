// Step 3, first part (docs/STAPPENPLAN.md): read a route file from the planner, check it
// again and show it on a map. Flying comes later, after the ground test with the drone.
import SwiftUI
import UniformTypeIdentifiers

final class RouteModel: ObservableObject {
    @Published private(set) var file: RoutePlanFile?
    @Published private(set) var fileName: String?
    @Published private(set) var issues: [RouteIssue] = []
    @Published private(set) var summary: RouteSummary?
    @Published private(set) var error: String?

    var errorCount: Int { issues.filter { $0.level == .error }.count }

    /// From the file picker, AirDrop or "Open with" in the Files app.
    func load(url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            load(data: try Data(contentsOf: url), name: url.lastPathComponent)
        } catch {
            show(error: "Het bestand kan niet geopend worden: \(error.localizedDescription)", name: url.lastPathComponent)
        }
    }

    func loadSample() {
        let name = "voorbeeld.routeplan.json"
        guard let data = SampleData.data(name) else {
            show(error: "Het voorbeeldbestand ontbreekt in de app.", name: name)
            return
        }
        load(data: data, name: name)
    }

    private func load(data: Data, name: String) {
        do {
            let file = try RoutePlanFile.read(data)
            self.file = file
            fileName = name
            let all = RouteCheck.check(file)
            issues = all.filter { $0.level == .error } + all.filter { $0.level == .warning }
            summary = RouteCheck.summary(file)
            error = nil
        } catch {
            show(error: error.localizedDescription, name: name)
        }
    }

    private func show(error message: String, name: String) {
        file = nil
        issues = []
        summary = nil
        fileName = name
        error = message
    }
}

struct RouteView: View {
    @ObservedObject var model: RouteModel
    let drone: DJIConnection
    @State private var importing = false
    @State private var session: FlightSession?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        importing = true
                    } label: {
                        Label("Routebestand openen…", systemImage: "folder")
                    }
                    Button {
                        model.loadSample()
                    } label: {
                        Label("Voorbeeldroute laden", systemImage: "doc.text")
                    }
                } footer: {
                    Text("Sla de route in de planner op met Download JSON. Zet het bestand op de iPhone met AirDrop of iCloud Drive en open het hier, of kies in de Bestanden-app Deel → Veldvlucht.")
                }

                if let error = model.error {
                    Section("Kan niet gelezen worden") {
                        Label(error, systemImage: "xmark.octagon.fill")
                            .foregroundStyle(.red)
                        if let name = model.fileName {
                            Text(name).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }

                if let file = model.file, let summary = model.summary {
                    routeSection(file, summary)
                    checkSection
                    Section {
                        NavigationLink {
                            RouteMapView(file: file, contentID: "\(model.fileName ?? "")|\(file.createdAt ?? "")")
                        } label: {
                            Label("Toon op de kaart", systemImage: "map")
                        }
                    }
                    if model.errorCount == 0 {
                        Section {
                            Button {
                                session = FlightSession(file: file, drone: drone)
                            } label: {
                                Label("Vliegen in de simulator…", systemImage: "airplane.departure")
                            }
                        } footer: {
                            Text("Stap 3: de drone blijft met de propellers eraf op de grond. Alleen de simulator van DJI vliegt de route.")
                        }
                    }
                }
            }
            .navigationTitle("Route")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                if case .success(let url) = result {
                    model.load(url: url)
                }
            }
            .fullScreenCover(item: $session) { session in
                FlightView(session: session, flight: session.flight, drone: drone)
            }
        }
    }

    private func routeSection(_ file: RoutePlanFile, _ summary: RouteSummary) -> some View {
        Section("Route") {
            Row(label: "Naam", value: file.name)
            Row(label: "Soort", value: file.mode == .field ? "Veld met vliegbanen" : "Eigen route")
            Row(label: "Vlieghoogte", value: "\(RouteCheck.number(file.settings.altitudeM)) m boven het startpunt")
            Row(label: "Snelheid", value: "\(RouteCheck.number(file.settings.speedMps)) m/s")
            Row(label: "Foto-interval", value: "\(RouteCheck.number(file.settings.photoIntervalS)) s (elke \(RouteCheck.number(file.settings.speedMps * file.settings.photoIntervalS)) m)")
            Row(label: "Routepunten", value: "\(summary.waypointCount)")
            Row(label: "Foto's", value: "\(summary.photoCount)")
            Row(label: "Afstand", value: RouteCheck.meters(summary.totalDistanceM))
            Row(label: "Geschatte vliegtijd", value: RouteCheck.minutes(summary.flightTimeS))
            if let far = summary.maxDistanceFromHomeM {
                Row(label: "Verste punt vanaf start", value: RouteCheck.meters(far))
            }
            if let area = summary.fieldAreaM2 {
                Row(label: "Veld", value: String(format: "%.2f ha", area / 10_000).replacingOccurrences(of: ".", with: ","))
            }
        }
    }

    private var checkSection: some View {
        Section {
            if model.issues.isEmpty {
                Label("Geen fouten of waarschuwingen", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            ForEach(model.issues) { issue in
                Label {
                    Text(issue.message)
                } icon: {
                    Image(systemName: issue.level == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(issue.level == .error ? .red : .orange)
                }
            }
        } header: {
            Text("Controle in de app")
        } footer: {
            if model.errorCount > 0 {
                Text("Met fouten kan deze route niet gevlogen worden. Pas de route aan in de planner en sla hem opnieuw op.")
            } else {
                Text("Vliegen komt in een volgende stap: eerst de test met de drone (stap 2), daarna de simulator van DJI (stap 3).")
            }
        }
    }
}

struct RouteMapView: View {
    let file: RoutePlanFile
    let contentID: String
    @State private var baseLayer = BaseLayer.pdok

    var body: some View {
        MapCanvas(shapes: shapes, pins: pins, contentID: contentID, baseLayer: baseLayer)
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .bottom) {
                VStack(spacing: 6) {
                    legend
                    MapAttribution(layer: baseLayer)
                }
                .padding(.bottom, 8)
            }
            .navigationTitle(file.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { BaseLayerMenu(layer: $baseLayer) }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            LegendItem(color: .yellow, text: "met foto's")
            LegendItem(color: .orange, text: "zonder foto's")
            LegendItem(color: .white, text: "foto")
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
    }

    private var shapes: [MapShape] { Self.shapes(for: file) }

    private var pins: [MapPin] { Self.pins(for: file) }

    static func shapes(for file: RoutePlanFile) -> [MapShape] {
        var shapes: [MapShape] = []
        if file.boundary.count >= 3 {
            shapes.append(MapShape(id: "veldgrens", kind: .polygon, points: file.boundary, stroke: .white, fill: UIColor.white.withAlphaComponent(0.12)))
        }
        let waypoints = file.derived.waypoints.map(\.latLng)
        for (i, leg) in file.derived.legs.enumerated() where waypoints.indices.contains(leg.to) {
            shapes.append(MapShape(
                id: "stuk-\(i)",
                kind: .polyline,
                points: [waypoints[leg.from], waypoints[leg.to]],
                stroke: leg.capture ? .systemYellow : .systemOrange,
                lineWidth: leg.capture ? 3 : 2,
                dashed: !leg.capture
            ))
        }
        if let home = file.home, let first = waypoints.first, let last = waypoints.last {
            shapes.append(MapShape(id: "heen", kind: .polyline, points: [home, first], stroke: .systemOrange, dashed: true))
            shapes.append(MapShape(id: "terug", kind: .polyline, points: [last, home], stroke: .systemOrange, dashed: true))
        }
        return shapes
    }

    static func pins(for file: RoutePlanFile) -> [MapPin] {
        var pins = file.derived.photoPoints.prefix(5000).map {
            MapPin(id: "foto-\($0.index)", coordinate: $0.latLng, title: nil, style: .dot(.white))
        }
        if let home = file.home {
            pins.append(MapPin(id: "start", coordinate: home, title: "Startpunt", style: .marker(symbol: "house.fill", color: .systemBlue)))
        }
        if let first = file.derived.waypoints.first {
            pins.append(MapPin(id: "eerste", coordinate: first.latLng, title: "Eerste routepunt", style: .marker(symbol: "flag.fill", color: .systemGreen)))
        }
        return pins
    }
}

struct LegendItem: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 10, height: 10)
                .overlay(Circle().stroke(.black.opacity(0.4), lineWidth: 0.5))
            Text(text)
        }
    }
}
