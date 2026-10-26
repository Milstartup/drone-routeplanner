// Drawing a field in the app: tap the corners on the aerial photo, and FieldPlanner makes
// the flight lines and photo positions while you draw. Drag a corner or the take-off point
// (H) to move it. Also used to place the soil sensors (SensorEditorView).
import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct FieldEditorView: View {
    let original: FieldRecord?
    @ObservedObject var fields: FieldStore
    var onSave: (FieldRecord) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var input: FieldPlanInput
    @State private var result: FieldPlanner.Result
    @State private var history: [FieldPlanInput] = []
    @State private var selectedCorner: Int?
    @State private var userLocation: LatLng?
    @State private var recenter = 0
    @State private var baseLayer = BaseLayer.pdok
    @State private var showSettings = false
    @State private var naming = false
    @State private var name: String
    @State private var confirmDiscard = false
    @State private var saveError: String?

    init(field: FieldRecord?, fields: FieldStore, onSave: @escaping (FieldRecord) -> Void) {
        original = field
        self.fields = fields
        self.onSave = onSave
        let input = field?.planInput ?? FieldPlanInput(name: fields.newName(), boundary: [], home: nil)
        _input = State(initialValue: input)
        _result = State(initialValue: FieldPlanner.plan(input))
        _name = State(initialValue: input.name)
    }

    private var corners: [LatLng] { input.boundary }
    private var changed: Bool { original?.planInput != input && !(original == nil && input.boundary.isEmpty) }
    private var canSave: Bool { corners.count >= 3 && !result.hasErrors }

    var body: some View {
        ZStack(alignment: .top) {
            FieldEditMap(
                mode: .corners,
                corners: corners,
                home: input.home,
                sensors: [],
                selectedCorner: selectedCorner,
                shapes: previewShapes,
                dots: result.photos.count <= 4000 ? result.photos.map(\.position) : [],
                baseLayer: baseLayer,
                fitID: original?.id ?? "nieuw",
                recenter: recenter,
                fitInsets: UIEdgeInsets(top: 150, left: 40, bottom: 300, right: 40),
                controlInsets: UIEdgeInsets(top: 110, left: 12, bottom: 280, right: 12),
                onTap: addCorner,
                onSelectCorner: { selectedCorner = $0 },
                onMoveCorner: moveCorner,
                onMoveHome: { point in change { $0.home = point } },
                onMoveSensor: { _, _ in },
                onUserLocation: { userLocation = $0 }
            )
            .ignoresSafeArea()

            VStack(spacing: 8) {
                topBar
                if let hint {
                    Text(hint)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .glass(Capsule())
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
        }
        .safeAreaInset(edge: .bottom) {
            panel
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
        }
        .animation(.snappy, value: corners.count)
        .animation(.snappy, value: selectedCorner)
        .onChange(of: input) { _, new in result = FieldPlanner.plan(new) }
        .sensoryFeedback(.impact(weight: .light), trigger: corners.count)
        .sheet(isPresented: $showSettings) {
            FieldSettingsSheet(input: $input, boundary: corners)
                .presentationDetents([.medium, .large])
        }
        .alert("Hoe heet dit veld?", isPresented: $naming) {
            TextField("Naam", text: $name)
            Button("Bewaren") { save() }
            Button("Annuleren", role: .cancel) {}
        } message: {
            Text("Bijvoorbeeld de naam van de akker of het gewas.")
        }
        .alert("Niet bewaard", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .confirmationDialog("Wijzigingen weggooien?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Weggooien", role: .destructive) { dismiss() }
            Button("Verder tekenen", role: .cancel) {}
        }
    }

    // MARK: Editing

    private func change(_ edit: (inout FieldPlanInput) -> Void) {
        history.append(input)
        if history.count > 100 { history.removeFirst() }
        edit(&input)
    }

    private func addCorner(_ point: LatLng) {
        if selectedCorner != nil {
            selectedCorner = nil
            return
        }
        change { input in
            input.boundary.append(point)
            if input.home == nil {
                // Where you stand is usually where the drone takes off.
                if let here = userLocation, Geo.distanceM(here, point) < 1000 {
                    input.home = here
                } else {
                    input.home = point
                }
            }
        }
    }

    private func moveCorner(_ index: Int, _ point: LatLng) {
        guard input.boundary.indices.contains(index) else { return }
        change { $0.boundary[index] = point }
    }

    private func deleteCorner(_ index: Int) {
        guard input.boundary.indices.contains(index) else { return }
        change { $0.boundary.remove(at: index) }
        selectedCorner = nil
    }

    private func undo() {
        guard let previous = history.popLast() else { return }
        input = previous
        selectedCorner = nil
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let finalName = trimmed.isEmpty ? input.name : trimmed
        let now = Date()
        var record = original ?? FieldRecord(id: fields.newId(for: finalName), name: finalName, boundary: [], home: nil,
                                             settings: input.settings, createdAt: now, updatedAt: now)
        record.name = finalName
        record.boundary = input.boundary
        record.home = input.home
        record.settings = input.settings
        if record != original { record.updatedAt = now }
        do {
            try fields.save(record)
            // The field map shows the field you just drew, unless you chose another one.
            if fields.selectedId == nil { fields.selectedId = record.id }
            onSave(record)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    // MARK: Parts

    private var hint: String? {
        if selectedCorner != nil { return nil }
        switch corners.count {
        case 0: return "Tik op de kaart de hoeken van je veld aan, één voor één rondom."
        case 1, 2: return "Nog \(3 - corners.count) \(corners.count == 2 ? "hoek" : "hoeken") nodig. Tik de volgende hoek aan."
        default: return nil
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button {
                if changed { confirmDiscard = true } else { dismiss() }
            } label: {
                GlassCircle(symbol: "xmark")
            }
            .accessibilityLabel("Annuleren")
            Spacer()
            Text(original == nil ? "Nieuw veld" : input.name)
                .font(.headline)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .glass(Capsule())
            Spacer()
            Button {
                recenter += 1
            } label: {
                GlassCircle(symbol: "location.fill")
            }
            .accessibilityLabel("Naar mijn plek")
            BaseLayerMenu(layer: $baseLayer, style: .floating)
        }
        .buttonStyle(.plain)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let index = selectedCorner {
                HStack {
                    Label("Hoek \(index + 1)", systemImage: "circle.circle")
                        .font(.headline)
                    Spacer()
                    Button(role: .destructive) {
                        deleteCorner(index)
                    } label: {
                        Label("Verwijderen", systemImage: "trash")
                    }
                    .buttonStyle(ActionButtonStyle(color: .actionStop, prominent: false))
                    .frame(width: 170)
                }
                Text("Houd een hoek vast en sleep hem om hem te verplaatsen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if corners.count >= 3 {
                stats
                status
            } else if input.home == nil {
                Label("Zoom eerst in op je veld, met twee vingers. Met de pijl rechtsboven ga je naar je eigen plek.", systemImage: "hand.pinch")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Label("Het blauwe huisje is het startpunt. Zet het waar de drone opstijgt: houd het vast en sleep.", systemImage: "house.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button(action: undo) {
                    Label("Terug", systemImage: "arrow.uturn.backward").labelStyle(.iconOnly)
                }
                .buttonStyle(ActionButtonStyle(color: .gray, prominent: false))
                .frame(width: 60)
                .disabled(history.isEmpty)
                Button {
                    showSettings = true
                } label: {
                    Label("Instellingen", systemImage: "slider.horizontal.3").labelStyle(.iconOnly)
                }
                .buttonStyle(ActionButtonStyle(color: .veld, prominent: false))
                .frame(width: 60)
                Button {
                    name = input.name
                    naming = true
                } label: {
                    Label("Bewaren", systemImage: "checkmark")
                }
                .buttonStyle(ActionButtonStyle(color: .actionGo))
                .disabled(!canSave)
            }
            if input.home != nil, let here = userLocation, corners.count >= 3, selectedCorner == nil,
               Geo.distanceM(here, input.home!) > 15 {
                Button {
                    change { $0.home = here }
                } label: {
                    Label("Startpunt op mijn plek zetten", systemImage: "location.fill")
                        .font(.footnote.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(14)
        .glass(cornerRadius: 26)
    }

    private var stats: some View {
        HStack(spacing: 0) {
            stat(RouteCheck.meters(result.estimate.totalDistanceM), "afstand")
            Divider().frame(height: 30)
            stat(RouteCheck.minutes(result.estimate.flightTimeS), "vliegtijd")
            Divider().frame(height: 30)
            stat("\(result.photos.count)", "foto's")
            Divider().frame(height: 30)
            stat(FieldPlanner.hectares(result.estimate.fieldAreaM2 ?? 0), "veld")
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var status: some View {
        if let error = result.issues.first(where: { $0.level == .error }) {
            Notice(text: error.message, symbol: "xmark.octagon.fill", color: .red)
        } else if let warning = result.issues.first(where: { $0.level == .warning }) {
            Notice(text: warning.message)
        } else {
            let share = result.estimate.flightTimeS / max(1, input.assumptions.usableFlightTimeS)
            Notice(text: "Klaar om te bewaren. Deze route gebruikt ongeveer \(Int((share * 100).rounded())) % van een accu.",
                   symbol: "checkmark.circle.fill", color: .green)
        }
    }

    /// The field, the flight lines and the flights to and from the take-off point.
    private var previewShapes: [MapShape] {
        var shapes = RouteMapView.shapes(for: result.file)
        if corners.count == 2 {
            shapes.append(MapShape(id: "rand", kind: .polyline, points: corners, stroke: .white, lineWidth: 2, dashed: true))
        }
        return shapes
    }
}

// MARK: - Settings

struct FieldSettingsSheet: View {
    @Binding var input: FieldPlanInput
    let boundary: [LatLng]
    @Environment(\.dismiss) private var dismiss

    private var s: RoutePlanFile.Settings { input.settings }

    var body: some View {
        NavigationStack {
            Form {
                Section("Naam") {
                    TextField("Naam van het veld", text: $input.name)
                }
                Section {
                    Stepper(value: $input.settings.altitudeM, in: 15...120, step: 5) {
                        Row(label: "Vlieghoogte", value: "\(RouteCheck.number(s.altitudeM)) m")
                    }
                    Stepper(value: $input.settings.lineSpacingM, in: 5...60, step: 1) {
                        Row(label: "Baanafstand", value: "\(RouteCheck.number(s.lineSpacingM)) m")
                    }
                    Stepper(value: $input.settings.speedMps, in: 2...8, step: 0.5) {
                        Row(label: "Snelheid", value: "\(RouteCheck.number(s.speedMps)) m/s")
                    }
                    Stepper(value: $input.settings.photoIntervalS, in: 2...10, step: 0.5) {
                        Row(label: "Foto-interval", value: "\(RouteCheck.number(s.photoIntervalS)) s")
                    }
                } header: {
                    Text("Vlucht")
                } footer: {
                    Text(footprintText)
                }
                Section {
                    Toggle("Automatisch", isOn: Binding(
                        get: { s.lineAngleDeg == nil },
                        set: { input.settings.lineAngleDeg = $0 ? nil : FieldPlanner.lineAngle(boundary: boundary, setting: nil).rounded() }
                    ))
                    .tint(.veld)
                    if let angle = s.lineAngleDeg {
                        VStack(alignment: .leading) {
                            Row(label: "Richting", value: "\(Int(angle))° (\(compass(angle)))")
                            Slider(value: Binding(get: { angle }, set: { input.settings.lineAngleDeg = $0.rounded() }), in: 0...179)
                                .tint(.veld)
                        }
                    }
                    Stepper(value: $input.settings.edgeMarginM, in: 0...30, step: 1) {
                        Row(label: "Randmarge", value: "\(RouteCheck.number(s.edgeMarginM)) m")
                    }
                } header: {
                    Text("Vliegbanen")
                } footer: {
                    Text("Automatisch: de banen lopen langs de langste rand van het veld. De randmarge is de afstand tussen de buitenste baan en de rand.")
                }
                Section {
                    Button("Standaardwaarden") {
                        input.settings = .planner
                    }
                }
            }
            .navigationTitle("Instellingen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klaar") { dismiss() }
                }
            }
        }
    }

    private var footprintText: String {
        guard let footprint = CameraFootprint.at(altitudeM: s.altitudeM) else { return "" }
        let side = CameraFootprint.overlap(footprintM: footprint.widthM, distanceM: s.lineSpacingM)
        let spacing = s.speedMps * s.photoIntervalS
        let front = CameraFootprint.overlap(footprintM: footprint.lengthM, distanceM: spacing)
        return "Eén foto dekt \(Int(footprint.widthM.rounded())) × \(Int(footprint.lengthM.rounded())) m, \(dutchNumber(footprint.gsdCm, digits: 1)) cm per pixel. Een foto elke \(RouteCheck.number(spacing)) m. Overlap naast elkaar \(Int((side * 100).rounded())) %, achter elkaar \(Int((front * 100).rounded())) %."
    }

    private func compass(_ angle: Double) -> String {
        let names = ["noord-zuid", "noordoost-zuidwest", "oost-west", "zuidoost-noordwest"]
        return names[Int(((angle + 22.5) / 45).rounded(.down)) % 4]
    }
}

// MARK: - The map for drawing

/// A point you can drag on the edit map: a sensor with its short name.
struct EditPoint: Equatable {
    var title: String
    var location: LatLng
}

struct FieldEditMap: UIViewRepresentable {
    enum Mode {
        /// Tap to add corners; corners and the take-off point can be dragged.
        case corners
        /// Only the sensors can be dragged.
        case sensors
    }

    var mode: Mode
    var corners: [LatLng]
    var home: LatLng?
    var sensors: [EditPoint]
    var selectedCorner: Int?
    var shapes: [MapShape]
    var dots: [LatLng]
    var baseLayer: BaseLayer
    /// Change this to zoom to the field again.
    var fitID: String
    /// Change this to fly to your own position.
    var recenter: Int
    var fitInsets: UIEdgeInsets
    var controlInsets: UIEdgeInsets
    var onTap: (LatLng) -> Void
    var onSelectCorner: (Int?) -> Void
    var onMoveCorner: (Int, LatLng) -> Void
    var onMoveHome: (LatLng) -> Void
    var onMoveSensor: (Int, LatLng) -> Void
    var onUserLocation: (LatLng) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> FittingMapView {
        let map = FittingMapView()
        map.delegate = context.coordinator
        map.mapType = .satellite
        map.pointOfInterestFilter = .excludingAll
        map.showsUserLocation = true
        map.showsCompass = true
        map.showsScale = true
        map.layoutMargins = controlInsets
        for gesture in [UIPanGestureRecognizer(), UIPinchGestureRecognizer(), UIRotationGestureRecognizer()] {
            gesture.addTarget(context.coordinator, action: #selector(Coordinator.handleMove(_:)))
            gesture.delegate = context.coordinator
            map.addGestureRecognizer(gesture)
        }
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)
        let doubleTap = UITapGestureRecognizer(target: nil, action: nil)
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = context.coordinator
        map.addGestureRecognizer(doubleTap)
        tap.require(toFail: doubleTap)
        let manager = context.coordinator.locationManager
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        return map
    }

    func updateUIView(_ map: FittingMapView, context: Context) {
        let c = context.coordinator
        c.parent = self
        c.setBaseLayer(baseLayer, on: map)
        c.showShapes(shapes, dots: dots, on: map)
        c.syncAnnotations(on: map)
        if c.fitID != fitID {
            c.fitID = fitID
            c.fit(on: map)
        }
        if c.recenter != recenter {
            c.recenter = recenter
            c.centerOnUser(map)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: FieldEditMap?
        var fitID: String?
        var recenter = 0
        let locationManager = CLLocationManager()
        private var baseLayer: BaseLayer?
        private var tiles: MKTileOverlay?
        private var shapesKey = ""
        private var styles: [ObjectIdentifier: MapShape] = [:]
        private var cornerAnnotations: [EditAnnotation] = []
        private var sensorAnnotations: [EditAnnotation] = []
        private var homeAnnotation: EditAnnotation?
        /// Only a new field without corners waits for your position to centre on it.
        private var waitingForUser = false

        func setBaseLayer(_ layer: BaseLayer, on map: MKMapView) {
            guard baseLayer != layer else { return }
            baseLayer = layer
            if let tiles { map.removeOverlay(tiles) }
            tiles = nil
            guard layer == .pdok else { return }
            let overlay = MKTileOverlay(urlTemplate: MapCanvas.pdokTiles)
            overlay.canReplaceMapContent = true
            overlay.maximumZ = 21
            map.insertOverlay(overlay, at: 0, level: .aboveRoads)
            tiles = overlay
        }

        func showShapes(_ shapes: [MapShape], dots: [LatLng], on map: MKMapView) {
            let key = shapes.map { "\($0.id):\($0.points.count):\($0.points.first?.lat ?? 0):\($0.points.last?.lng ?? 0)" }.joined()
                + "|\(dots.count):\(dots.first?.lat ?? 0):\(dots.last?.lng ?? 0)"
            guard key != shapesKey else { return }
            shapesKey = key
            map.removeOverlays(map.overlays.filter { !($0 is MKTileOverlay) })
            styles = [:]
            for shape in shapes where shape.points.count >= 2 {
                var coordinates = shape.points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
                let overlay: MKOverlay = shape.kind == .polygon
                    ? MKPolygon(coordinates: &coordinates, count: coordinates.count)
                    : MKPolyline(coordinates: &coordinates, count: coordinates.count)
                styles[ObjectIdentifier(overlay)] = shape
                map.addOverlay(overlay, level: .aboveRoads)
            }
            if !dots.isEmpty {
                map.addOverlay(DotsOverlay(points: dots, color: .white), level: .aboveLabels)
            }
        }

        func syncAnnotations(on map: MKMapView) {
            guard let parent else { return }
            let editable = parent.mode == .corners
            // Corners: rebuild when the number changes, otherwise only move them.
            if cornerAnnotations.count != parent.corners.count {
                map.removeAnnotations(cornerAnnotations)
                cornerAnnotations = parent.corners.enumerated().map {
                    EditAnnotation(kind: .corner($0.offset), coordinate: $0.element, title: nil)
                }
                map.addAnnotations(cornerAnnotations)
            }
            for (i, annotation) in cornerAnnotations.enumerated() {
                annotation.move(to: parent.corners[i])
                let selected = parent.selectedCorner == i
                if annotation.selected != selected {
                    annotation.selected = selected
                    (map.view(for: annotation) as? CornerView)?.update(number: i + 1, selected: selected, editable: editable)
                }
            }
            if let home = parent.home {
                if let homeAnnotation {
                    homeAnnotation.move(to: home)
                } else {
                    let annotation = EditAnnotation(kind: .home, coordinate: home, title: "Startpunt")
                    map.addAnnotation(annotation)
                    homeAnnotation = annotation
                }
            } else if let homeAnnotation {
                map.removeAnnotation(homeAnnotation)
                self.homeAnnotation = nil
            }
            if sensorAnnotations.count != parent.sensors.count || zip(sensorAnnotations, parent.sensors).contains(where: { $0.title != $1.title }) {
                map.removeAnnotations(sensorAnnotations)
                sensorAnnotations = parent.sensors.enumerated().map {
                    EditAnnotation(kind: .sensor($0.offset), coordinate: $0.element.location, title: $0.element.title)
                }
                map.addAnnotations(sensorAnnotations)
            }
            for (i, annotation) in sensorAnnotations.enumerated() {
                annotation.move(to: parent.sensors[i].location)
            }
        }

        /// Zooms to the field, or waits for your own position when there is no field yet.
        func fit(on map: FittingMapView) {
            guard let parent else { return }
            let points = parent.corners + (parent.home.map { [$0] } ?? []) + parent.sensors.map(\.location)
                + parent.shapes.flatMap(\.points)
            guard !points.isEmpty else {
                // Until your position is known: the Netherlands.
                waitingForUser = true
                map.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 52.25, longitude: 5.4),
                                                 span: MKCoordinateSpan(latitudeDelta: 2.6, longitudeDelta: 2.6)), animated: false)
                return
            }
            waitingForUser = false
            map.userMoved = false
            var rect = MKMapRect.null
            for p in points {
                let point = MKMapPoint(CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng))
                rect = rect.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
            }
            // A single point or a tiny field: show at least about 150 m around it.
            let minimum = 150 * MKMapPointsPerMeterAtLatitude(points[0].lat)
            if rect.width < minimum || rect.height < minimum {
                rect = rect.insetBy(dx: -(minimum - rect.width) / 2, dy: -(minimum - rect.height) / 2)
            }
            map.fitInsets = parent.fitInsets
            map.fitRect = rect
        }

        func centerOnUser(_ map: FittingMapView) {
            guard let location = map.userLocation.location else {
                waitingForUser = true
                return
            }
            map.userMoved = true
            map.setRegion(MKCoordinateRegion(center: location.coordinate, latitudinalMeters: 400, longitudinalMeters: 400), animated: true)
        }

        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            guard let location = userLocation.location else { return }
            parent?.onUserLocation(LatLng(lat: location.coordinate.latitude, lng: location.coordinate.longitude))
            if waitingForUser, let map = mapView as? FittingMapView {
                waitingForUser = false
                centerOnUser(map)
            }
        }

        @objc func handleMove(_ gesture: UIGestureRecognizer) {
            if gesture.state == .began {
                (gesture.view as? FittingMapView)?.userMoved = true
                waitingForUser = false
            }
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let map = gesture.view as? MKMapView, parent?.mode == .corners else { return }
            let location = gesture.location(in: map)
            var hit = map.hitTest(location, with: nil)
            while let view = hit {
                if view is MKAnnotationView { return }
                hit = view.superview
            }
            let coordinate = map.convert(location, toCoordinateFrom: map)
            parent?.onTap(LatLng(lat: coordinate.latitude, lng: coordinate.longitude))
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay { return MKTileOverlayRenderer(tileOverlay: tiles) }
            if let dots = overlay as? DotsOverlay { return DotsRenderer(dots: dots) }
            let style = styles[ObjectIdentifier(overlay)]
            let renderer: MKOverlayPathRenderer
            if let polygon = overlay as? MKPolygon {
                renderer = MKPolygonRenderer(polygon: polygon)
            } else if let line = overlay as? MKPolyline {
                renderer = MKPolylineRenderer(polyline: line)
            } else {
                return MKOverlayRenderer(overlay: overlay)
            }
            renderer.strokeColor = style?.stroke ?? .white
            renderer.fillColor = style?.fill
            renderer.lineWidth = style?.lineWidth ?? 2
            if style?.dashed == true { renderer.lineDashPattern = [6, 5] }
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let annotation = annotation as? EditAnnotation, let parent else { return nil }
            switch annotation.kind {
            case .corner(let index):
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: "hoek") as? CornerView)
                    ?? CornerView(annotation: annotation, reuseIdentifier: "hoek")
                view.annotation = annotation
                view.update(number: index + 1, selected: parent.selectedCorner == index, editable: parent.mode == .corners)
                return view
            case .home, .sensor:
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: "marker") as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "marker")
                view.annotation = annotation
                if case .home = annotation.kind {
                    view.markerTintColor = .systemBlue
                    view.glyphImage = UIImage(systemName: "house.fill")
                    view.isDraggable = parent.mode == .corners
                } else {
                    view.markerTintColor = .systemTeal
                    view.glyphImage = UIImage(systemName: "drop.fill")
                    view.isDraggable = parent.mode == .sensors
                }
                view.titleVisibility = .visible
                view.displayPriority = .required
                view.canShowCallout = false
                return view
            }
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation as? EditAnnotation else { return }
            if case .corner(let index) = annotation.kind, parent?.mode == .corners {
                parent?.onSelectCorner(parent?.selectedCorner == index ? nil : index)
            }
            mapView.deselectAnnotation(annotation, animated: false)
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView,
                     didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
            switch newState {
            case .starting:
                view.dragState = .dragging
            case .ending, .canceling:
                view.dragState = .none
                guard let annotation = view.annotation as? EditAnnotation else { return }
                let point = LatLng(lat: annotation.coordinate.latitude, lng: annotation.coordinate.longitude)
                switch annotation.kind {
                case .corner(let index): parent?.onMoveCorner(index, point)
                case .home: parent?.onMoveHome(point)
                case .sensor(let index): parent?.onMoveSensor(index, point)
                }
            default:
                break
            }
        }
    }
}

/// A corner, the take-off point or a sensor on the edit map.
final class EditAnnotation: NSObject, MKAnnotation {
    enum Kind {
        case corner(Int)
        case home
        case sensor(Int)
    }

    let kind: Kind
    @objc dynamic var coordinate: CLLocationCoordinate2D
    let title: String?
    var selected = false

    init(kind: Kind, coordinate: LatLng, title: String?) {
        self.kind = kind
        self.coordinate = CLLocationCoordinate2D(latitude: coordinate.lat, longitude: coordinate.lng)
        self.title = title
    }

    func move(to point: LatLng) {
        if abs(coordinate.latitude - point.lat) > 1e-10 || abs(coordinate.longitude - point.lng) > 1e-10 {
            coordinate = CLLocationCoordinate2D(latitude: point.lat, longitude: point.lng)
        }
    }
}

/// A numbered white dot for a corner of the field; green when selected.
final class CornerView: MKAnnotationView {
    func update(number: Int, selected: Bool, editable: Bool) {
        isDraggable = editable
        canShowCallout = false
        displayPriority = .required
        zPriority = .max
        let size: CGFloat = 30
        let green = UIColor(named: "AccentColor") ?? .systemGreen
        image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { _ in
            let rect = CGRect(x: 2, y: 2, width: size - 4, height: size - 4)
            let circle = UIBezierPath(ovalIn: rect)
            (selected ? green : .white).setFill()
            circle.fill()
            green.setStroke()
            circle.lineWidth = 3
            circle.stroke()
            let text = "\(number)" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13, weight: .bold),
                .foregroundColor: selected ? UIColor.white : green,
            ]
            let textSize = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: (size - textSize.width) / 2, y: (size - textSize.height) / 2), withAttributes: attributes)
        }
        alpha = editable ? 1 : 0.7
    }
}

/// Many small dots (the planned photos) in one overlay, cheaper than an annotation each.
final class DotsOverlay: NSObject, MKOverlay {
    let points: [MKMapPoint]
    let color: UIColor
    let boundingMapRect: MKMapRect
    let coordinate: CLLocationCoordinate2D

    init(points: [LatLng], color: UIColor) {
        self.points = points.map { MKMapPoint(CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)) }
        self.color = color
        var rect = MKMapRect.null
        for p in self.points { rect = rect.union(MKMapRect(x: p.x, y: p.y, width: 0, height: 0)) }
        boundingMapRect = rect.insetBy(dx: -500, dy: -500)
        coordinate = rect.isNull ? CLLocationCoordinate2D() : MKMapPoint(x: rect.midX, y: rect.midY).coordinate
    }
}

final class DotsRenderer: MKOverlayRenderer {
    private let dots: DotsOverlay

    init(dots: DotsOverlay) {
        self.dots = dots
        super.init(overlay: dots)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let radius = 3.5 / zoomScale
        let area = mapRect.insetBy(dx: -radius * 2, dy: -radius * 2)
        context.setFillColor(dots.color.cgColor)
        context.setStrokeColor(UIColor.black.withAlphaComponent(0.6).cgColor)
        context.setLineWidth(1 / zoomScale)
        for p in dots.points where area.contains(p) {
            let center = point(for: p)
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.fillEllipse(in: rect)
            context.strokeEllipse(in: rect)
        }
    }
}
