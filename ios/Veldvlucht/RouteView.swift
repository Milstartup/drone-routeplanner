// The route screen (step 3 of docs/STAPPENPLAN.md): read a route file from the planner,
// check it again, show it on a map and open the flight screen.
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

    private var canFly: Bool { model.file != nil && model.errorCount == 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Design.spacing) {
                    if let error = model.error {
                        errorCard(error)
                    }
                    if let file = model.file, let summary = model.summary {
                        loaded(file, summary)
                    } else {
                        Card {
                            EmptyState(
                                symbol: "point.topleft.down.to.point.bottomright.curvepath",
                                title: model.error == nil ? "Nog geen route" : "Kies een ander bestand",
                                message: "Maak een route in de planner en kies Download JSON. Zet het bestand met AirDrop of iCloud Drive op de iPhone, of kies in de Bestanden-app Deel → Veldvlucht."
                            ) {
                                openButton.buttonStyle(ActionButtonStyle(color: .actionGo))
                                sampleButton.buttonStyle(ActionButtonStyle(color: .veld, prominent: false))
                            }
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .screenBackground()
            .navigationTitle("Route")
            .toolbar {
                if model.file != nil || model.error != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            openButton
                            sampleButton
                        } label: {
                            Label("Andere route", systemImage: "folder")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if canFly { flyBar }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                if case .success(let url) = result {
                    model.load(url: url)
                }
            }
            .fullScreenCover(item: $session) { session in
                FlightView(session: session, drone: drone)
            }
        }
    }

    private var openButton: some View {
        Button {
            importing = true
        } label: {
            Label("Routebestand openen…", systemImage: "folder")
        }
    }

    private var sampleButton: some View {
        Button {
            model.loadSample()
        } label: {
            Label("Voorbeeldroute laden", systemImage: "doc.text")
        }
    }

    private func errorCard(_ error: String) -> some View {
        Card(tint: .red) {
            HStack(spacing: 10) {
                IconBadge(symbol: "xmark.octagon.fill", color: .red, size: 30)
                Text("Kan niet gelezen worden").font(.headline)
            }
            Text(error).font(.subheadline)
            if let name = model.fileName {
                Label(name, systemImage: "doc").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: A loaded route

    @ViewBuilder
    private func loaded(_ file: RoutePlanFile, _ summary: RouteSummary) -> some View {
        let contentID = "\(model.fileName ?? "")|\(file.createdAt ?? "")"
        NavigationLink {
            RouteMapView(file: file, contentID: contentID)
        } label: {
            MapCanvas(shapes: RouteMapView.shapes(for: file), pins: RouteMapView.pins(for: file),
                      contentID: contentID, interactive: false,
                      fitInsets: UIEdgeInsets(top: 50, left: 24, bottom: 40, right: 24))
                .frame(height: 230)
                .overlay(alignment: .topTrailing) {
                    Label("Toon op de kaart", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .glass(Capsule())
                        .padding(10)
                }
                .overlay(alignment: .bottomLeading) {
                    MapAttribution(layer: .pdok).padding(8)
                }
                .clipShape(RoundedRectangle(cornerRadius: Design.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)

        VStack(alignment: .leading, spacing: 6) {
            Text(file.name)
                .font(.title2.weight(.bold))
            HStack(spacing: 8) {
                Pill(text: file.mode == .field ? "Veld met vliegbanen" : "Eigen route",
                     symbol: file.mode == .field ? "square.split.diagonal.2x2" : "scribble.variable", color: .veld)
                if let name = model.fileName {
                    Text(name).font(.footnote).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)

        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                let distance = Self.split(RouteCheck.meters(summary.totalDistanceM))
                StatTile(title: "Afstand", symbol: "ruler", color: .blue, value: distance.value, unit: distance.unit,
                         detail: "\(summary.waypointCount) routepunten")
                let time = Self.split(RouteCheck.minutes(summary.flightTimeS))
                StatTile(title: "Vliegtijd", symbol: "timer", color: .purple, value: time.value, unit: time.unit,
                         detail: "geschat, zonder wind")
            }
            GridRow {
                StatTile(title: "Foto's", symbol: "camera.fill", color: .teal, value: "\(summary.photoCount)",
                         detail: "elke \(RouteCheck.number(file.settings.speedMps * file.settings.photoIntervalS)) m")
                StatTile(title: "Hoogte", symbol: "arrow.up.to.line", color: .orange,
                         value: RouteCheck.number(file.settings.altitudeM), unit: "m", detail: "boven het startpunt")
            }
        }

        Card {
            Rows(rows: detailRows(file, summary))
        }

        checkCard
    }

    private func detailRows(_ file: RoutePlanFile, _ summary: RouteSummary) -> [(String, String)] {
        var rows = [
            ("Snelheid", "\(RouteCheck.number(file.settings.speedMps)) m/s"),
            ("Foto-interval", "\(RouteCheck.number(file.settings.photoIntervalS)) s"),
        ]
        if let far = summary.maxDistanceFromHomeM {
            rows.append(("Verste punt vanaf start", RouteCheck.meters(far)))
        }
        if let area = summary.fieldAreaM2 {
            rows.append(("Veld", String(format: "%.2f ha", area / 10_000).replacingOccurrences(of: ".", with: ",")))
        }
        return rows
    }

    /// "2,52 km" → ("2,52", "km"), for a big number with a small unit.
    static func split(_ text: String) -> (value: String, unit: String?) {
        guard let space = text.lastIndex(of: " ") else { return (text, nil) }
        return (String(text[..<space]), String(text[text.index(after: space)...]))
    }

    private var checkCard: some View {
        Card(tint: model.errorCount > 0 ? .red : (model.issues.isEmpty ? .green : .orange)) {
            if model.issues.isEmpty {
                HStack(spacing: 12) {
                    IconBadge(symbol: "checkmark.seal.fill", color: .green, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Route is in orde").font(.headline)
                        Text("Geen fouten of waarschuwingen bij de controle in de app.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    IconBadge(symbol: model.errorCount > 0 ? "xmark.octagon.fill" : "exclamationmark.triangle.fill",
                              color: model.errorCount > 0 ? .red : .orange, size: 30)
                    Text("Controle in de app").font(.headline)
                }
                ForEach(model.issues) { issue in
                    Notice(text: issue.message,
                           symbol: issue.level == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill",
                           color: issue.level == .error ? .red : .orange)
                }
                if model.errorCount > 0 {
                    Text("Met fouten kan deze route niet gevlogen worden. Pas de route aan in de planner en sla hem opnieuw op.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var flyBar: some View {
        VStack(spacing: 6) {
            Button {
                if let file = model.file {
                    session = FlightSession(file: file, drone: drone)
                }
            } label: {
                Label(FlightClearance.realFlightsUnlocked ? "Vliegen…" : "Vliegen in de simulator…", systemImage: "airplane.departure")
            }
            .buttonStyle(ActionButtonStyle(color: .actionGo))
            Text(FlightClearance.realFlightsUnlocked
                 ? "In het vluchtscherm kies je: simulator of echt vliegen."
                 : "De drone blijft met de propellers eraf op de grond. Alleen de simulator van DJI vliegt.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.bar)
    }
}

struct RouteMapView: View {
    let file: RoutePlanFile
    let contentID: String
    @State private var baseLayer = BaseLayer.pdok

    var body: some View {
        MapCanvas(shapes: shapes, pins: pins, contentID: contentID, baseLayer: baseLayer,
                  fitInsets: UIEdgeInsets(top: 50, left: 50, bottom: 130, right: 50))
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .bottom) {
                VStack(spacing: 8) {
                    legend
                    MapAttribution(layer: baseLayer)
                }
                .padding(.bottom, 10)
            }
            .navigationTitle(file.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { BaseLayerMenu(layer: $baseLayer) }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            LegendItem(color: .yellow, text: "met foto's", mark: .line)
            LegendItem(color: .orange, text: "zonder foto's", mark: .dashed)
            LegendItem(color: .white, text: "foto")
        }
        .font(.footnote.weight(.medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glass(Capsule())
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
    enum Mark {
        case dot
        case line
        case dashed
    }

    let color: Color
    let text: String
    var mark = Mark.dot

    var body: some View {
        HStack(spacing: 5) {
            switch mark {
            case .dot:
                Circle().fill(color).frame(width: 11, height: 11)
                    .overlay(Circle().stroke(.black.opacity(0.35), lineWidth: 0.5))
            case .line, .dashed:
                Capsule()
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: mark == .dashed ? [4, 3] : []))
                    .frame(width: 18, height: 3)
            }
            Text(text)
        }
    }
}
