// The route screen: draw a field in the app (tap its corners; FieldPlanner makes the route),
// or open a route file from the planner. Then check it, see it on the map and fly it.
import SwiftUI
import UniformTypeIdentifiers

final class RouteModel: ObservableObject {
    @Published private(set) var file: RoutePlanFile?
    @Published private(set) var fileName: String?
    /// The field the route was made from, when it was drawn in the app.
    @Published private(set) var field: FieldRecord?
    @Published private(set) var issues: [RouteIssue] = []
    @Published private(set) var summary: RouteSummary?
    @Published private(set) var error: String?
    /// Changes with every load, so the screen can open the route that was just loaded.
    @Published private(set) var loadCount = 0

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

    /// A field drawn in the app: its route comes from FieldPlanner.
    func load(field: FieldRecord) {
        let plan = field.plan()
        self.field = field
        file = plan.file
        fileName = nil
        issues = plan.issues.filter { $0.level == .error } + plan.issues.filter { $0.level == .warning }
        summary = RouteCheck.summary(plan.file)
        error = nil
        loadCount += 1
    }

    /// The field was removed or changed elsewhere.
    func forget(fieldId: String) {
        guard field?.id == fieldId else { return }
        file = nil
        field = nil
        issues = []
        summary = nil
    }

    private func load(data: Data, name: String) {
        do {
            let file = try RoutePlanFile.read(data)
            self.file = file
            fileName = name
            field = nil
            let all = RouteCheck.check(file)
            issues = all.filter { $0.level == .error } + all.filter { $0.level == .warning }
            summary = RouteCheck.summary(file)
            error = nil
            loadCount += 1
        } catch {
            show(error: error.localizedDescription, name: name)
        }
    }

    private func show(error message: String, name: String) {
        file = nil
        field = nil
        issues = []
        summary = nil
        fileName = name
        error = message
    }
}

/// What the field drawing screen opens with: a new field, or one to change.
struct FieldEditRequest: Identifiable {
    let id = UUID()
    var field: FieldRecord?
}

struct RouteView: View {
    @ObservedObject var model: RouteModel
    @ObservedObject var fields: FieldStore
    @ObservedObject var cloud: CloudStore
    let drone: DJIConnection
    @State private var showAccount = false
    @State private var importing = false
    @State private var showRoute = false
    @State private var editing: FieldEditRequest?
    @State private var deleting: FieldRecord?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Design.spacing) {
                    newFieldCard
                    if !fields.fields.isEmpty {
                        SectionHeader(title: "Mijn velden", detail: "\(fields.fields.count)")
                        ForEach(fields.fields) { field in
                            Button {
                                model.load(field: field)
                            } label: {
                                FieldRow(field: field, info: fields.info[field.id])
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    editing = FieldEditRequest(field: field)
                                } label: {
                                    Label("Veld bewerken", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    deleting = field
                                } label: {
                                    Label("Veld verwijderen", systemImage: "trash")
                                }
                            }
                        }
                    }
                    if let error = model.error {
                        errorCard(error)
                    }
                    SectionHeader(title: "Uit de planner")
                    Card(spacing: 10) {
                        Text("Een route die je op de computer in de routeplanner maakte (Download JSON), met AirDrop of iCloud Drive op de iPhone gezet.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button {
                            importing = true
                        } label: {
                            Label("Routebestand openen…", systemImage: "folder")
                        }
                        .buttonStyle(ActionButtonStyle(color: .veld, prominent: false))
                        Button {
                            model.loadSample()
                        } label: {
                            Label("Voorbeeldroute laden", systemImage: "doc.text")
                        }
                        .buttonStyle(ActionButtonStyle(color: .gray, prominent: false))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .screenBackground()
            .navigationTitle("Route")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showAccount = true
                    } label: {
                        Label("Account", systemImage: cloud.isLoggedIn ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                    }
                }
            }
            .sheet(isPresented: $showAccount) {
                AccountView(cloud: cloud)
            }
            .navigationDestination(isPresented: $showRoute) {
                RouteDetailView(model: model, drone: drone) { field in
                    editing = FieldEditRequest(field: field)
                } onDelete: { field in
                    deleting = field
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                if case .success(let url) = result {
                    model.load(url: url)
                }
            }
            .fullScreenCover(item: $editing) { request in
                FieldEditorView(field: request.field, fields: fields) { saved in
                    model.load(field: saved)
                    Task { await cloud.save(saved) }
                }
            }
            .onChange(of: model.loadCount) { _, _ in
                showRoute = model.file != nil
            }
            .confirmationDialog("Veld verwijderen?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible, presenting: deleting) { field in
                Button("Verwijder \(field.name)", role: .destructive) {
                    model.forget(fieldId: field.id)
                    let id = field.id
                    Task { await cloud.delete(id) }
                    fields.delete(id)
                    showRoute = false
                }
            } message: { _ in
                Text("Ook de sensormetingen, het weer en het advies van dit veld verdwijnen, op deze iPhone en in de cloud. Vluchten en foto's blijven bewaard.")
            }
        }
    }

    private var newFieldCard: some View {
        Card(spacing: 14) {
            HStack(spacing: 14) {
                IconBadge(symbol: "hand.tap.fill", color: .veld, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Nieuw veld").font(.title3.weight(.bold))
                    Text("Tik op de kaart de hoeken van je veld aan. De app maakt zelf de vliegbanen en de foto's.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button {
                editing = FieldEditRequest(field: nil)
            } label: {
                Label("Veld tekenen", systemImage: "plus")
            }
            .buttonStyle(ActionButtonStyle(color: .actionGo))
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
}

/// One field in the list: its shape, name and the figures of its route.
private struct FieldRow: View {
    let field: FieldRecord
    let info: FieldStore.Info?

    var body: some View {
        HStack(spacing: 14) {
            FieldShape(boundary: field.boundary)
                .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(field.name).font(.headline).lineLimit(1)
                Text(details)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if info?.hasErrors == true {
                    Label("Nog niet te vliegen", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                } else if !field.sensors.isEmpty {
                    Label(field.sensors.count == 1 ? "1 sensor" : "\(field.sensors.count) sensoren", systemImage: "drop.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.teal)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: Design.tileRadius, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var details: String {
        var parts = [FieldPlanner.hectares(field.areaM2)]
        if let info {
            parts.append("\(info.photoCount) foto's")
            parts.append(RouteCheck.minutes(info.flightTimeS))
        }
        return parts.joined(separator: " · ")
    }
}

/// The outline of a field, as a small green tile.
struct FieldShape: View {
    let boundary: [LatLng]

    var body: some View {
        Canvas { context, size in
            guard boundary.count >= 3 else { return }
            let projection = LocalProjection(origin: Geo.centroid(boundary))
            let points = boundary.map(projection.toXY)
            let xs = points.map(\.x)
            let ys = points.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return }
            let scale = min((size.width - 14) / max(1, maxX - minX), (size.height - 14) / max(1, maxY - minY))
            let offsetX = (size.width - (maxX - minX) * scale) / 2
            let offsetY = (size.height - (maxY - minY) * scale) / 2
            var path = Path()
            for (i, p) in points.enumerated() {
                let point = CGPoint(x: offsetX + (p.x - minX) * scale, y: size.height - offsetY - (p.y - minY) * scale)
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            context.fill(path, with: .color(Color.veld.opacity(0.3)))
            context.stroke(path, with: .color(Color.veld), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
        }
        .background(Color.veld.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// A loaded route: the map, the figures, the checks and the button to fly it.
struct RouteDetailView: View {
    @ObservedObject var model: RouteModel
    let drone: DJIConnection
    var onEdit: (FieldRecord) -> Void
    var onDelete: (FieldRecord) -> Void
    @State private var session: FlightSession?
    @State private var exportURL: URL?

    private var canFly: Bool { model.file != nil && model.errorCount == 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: Design.spacing) {
                if let file = model.file, let summary = model.summary {
                    loaded(file, summary)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .screenBackground()
        .navigationTitle(model.field == nil ? "Route" : "Veld")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    if let field = model.field {
                        Button {
                            onEdit(field)
                        } label: {
                            Label("Veld bewerken", systemImage: "pencil")
                        }
                    }
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Route delen (voor de planner)", systemImage: "square.and.arrow.up")
                        }
                    }
                    if let field = model.field {
                        Button(role: .destructive) {
                            onDelete(field)
                        } label: {
                            Label("Veld verwijderen", systemImage: "trash")
                        }
                    }
                } label: {
                    Label("Meer", systemImage: "ellipsis.circle")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if canFly { flyBar }
        }
        .fullScreenCover(item: $session) { session in
            FlightView(session: session, drone: drone)
        }
        .onAppear(perform: writeExport)
        .onChange(of: model.loadCount) { _, _ in writeExport() }
    }

    /// The route as a .routeplan.json, for AirDrop to the computer or the planner.
    private func writeExport() {
        guard let file = model.file, let data = try? file.encoded() else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(FieldRecord.slug(file.name)).routeplan.json")
        try? data.write(to: url, options: .atomic)
        exportURL = url
    }

    @ViewBuilder
    private func loaded(_ file: RoutePlanFile, _ summary: RouteSummary) -> some View {
        let contentID = "\(model.fileName ?? model.field?.id ?? "")|\(file.createdAt ?? "")"
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
                if model.field != nil {
                    Pill(text: "Getekend in de app", symbol: "hand.tap", color: .veld)
                } else {
                    Pill(text: file.mode == .field ? "Veld met vliegbanen" : "Eigen route",
                         symbol: file.mode == .field ? "square.split.diagonal.2x2" : "scribble.variable", color: .veld)
                }
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
                         detail: batteryText(summary.flightTimeS, file.assumptions))
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

    private func batteryText(_ seconds: Double, _ assumptions: RoutePlanFile.Assumptions) -> String {
        guard assumptions.usableFlightTimeS > 0 else { return "geschat, zonder wind" }
        return "\(Int((seconds / assumptions.usableFlightTimeS * 100).rounded())) % van een accu"
    }

    private func detailRows(_ file: RoutePlanFile, _ summary: RouteSummary) -> [(String, String)] {
        var rows = [
            ("Snelheid", "\(RouteCheck.number(file.settings.speedMps)) m/s"),
            ("Foto-interval", "\(RouteCheck.number(file.settings.photoIntervalS)) s"),
        ]
        if file.mode == .field {
            rows.append(("Baanafstand", "\(RouteCheck.number(file.settings.lineSpacingM)) m"))
        }
        if let far = summary.maxDistanceFromHomeM {
            rows.append(("Verste punt vanaf start", RouteCheck.meters(far)))
        }
        if let area = summary.fieldAreaM2 {
            rows.append(("Veld", FieldPlanner.hectares(area)))
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
                    Text(model.field == nil
                         ? "Met fouten kan deze route niet gevlogen worden. Pas de route aan in de planner en sla hem opnieuw op."
                         : "Met fouten kan deze route niet gevlogen worden. Kies Veld bewerken (rechtsboven) en pas het veld aan.")
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
                    session = FlightSession(file: file, fieldId: model.field?.id, drone: drone)
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
