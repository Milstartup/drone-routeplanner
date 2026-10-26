// A MapKit map for SwiftUI with the Dutch aerial photo (PDOK) as base layer, field shapes
// and tappable pins and areas. Used by the route screen and the field map.
import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct MapShape {
    enum Kind {
        case polygon
        case polyline
    }

    var id: String
    var kind: Kind
    var points: [LatLng]
    var stroke: UIColor
    var fill: UIColor?
    var lineWidth: CGFloat = 2
    var dashed = false
    /// A tap inside this polygon calls `onSelect` with its id.
    var tappable = false
}

struct MapPin {
    enum Style {
        /// A small dot, for example a planned photo.
        case dot(UIColor)
        /// A balloon with an SF Symbol inside.
        case marker(symbol: String, color: UIColor)
    }

    var id: String
    var coordinate: LatLng
    var title: String?
    var style: Style
}

enum BaseLayer: String, CaseIterable, Identifiable {
    case pdok
    case apple

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pdok: return "Luchtfoto Nederland (PDOK)"
        case .apple: return "Satelliet (Apple)"
        }
    }

    /// Required credit, shown on the map.
    var attribution: String {
        switch self {
        case .pdok: return "Luchtfoto © Beeldmateriaal Nederland via PDOK (CC BY 4.0)"
        case .apple: return "Kaart: Apple"
        }
    }
}

struct MapCanvas: UIViewRepresentable {
    var shapes: [MapShape]
    var pins: [MapPin]
    /// Change this when the shapes or pins change: the map then redraws and zooms to fit.
    var contentID: String
    var baseLayer = BaseLayer.pdok
    /// Other colours for some dot pins, for example photos already taken. Changes cheaply.
    var pinColors: [String: UIColor] = [:]
    /// A pin that moves without redrawing the rest, such as the drone itself.
    var movingPin: MapPin?
    /// false: a still preview without your own position, compass or scale.
    var interactive = true
    /// Room around the shapes when the map zooms to fit, for panels floating over the map.
    var fitInsets = UIEdgeInsets(top: 40, left: 30, bottom: 70, right: 30)
    /// Keeps the compass, scale and Apple's legal text clear of floating panels.
    var controlInsets: UIEdgeInsets?
    var onSelect: ((String) -> Void)?

    /// Same 8 cm aerial photo as the planner (src/map/providers.ts). Open data, no key needed.
    static let pdokTiles = "https://service.pdok.nl/hwh/luchtfotorgb/wmts/v1_0/Actueel_orthoHR/EPSG:3857/{z}/{x}/{y}.jpeg"

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = FittingMapView()
        map.delegate = context.coordinator
        map.mapType = .satellite
        map.pointOfInterestFilter = .excludingAll
        if let controlInsets {
            map.layoutMargins = controlInsets
        }
        guard interactive else {
            map.isUserInteractionEnabled = false
            return map
        }
        map.showsUserLocation = true
        map.showsCompass = true
        map.showsScale = true
        // Once you pan, pinch or turn the map yourself, it no longer zooms back to the route.
        for gesture in [UIPanGestureRecognizer(), UIPinchGestureRecognizer(), UIRotationGestureRecognizer()] {
            gesture.addTarget(context.coordinator, action: #selector(Coordinator.handleMove(_:)))
            gesture.delegate = context.coordinator
            map.addGestureRecognizer(gesture)
        }
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)
        // A double tap zooms the map; it should not also select a strip.
        let doubleTap = UITapGestureRecognizer(target: nil, action: nil)
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = context.coordinator
        map.addGestureRecognizer(doubleTap)
        tap.require(toFail: doubleTap)
        context.coordinator.requestLocationPermission()
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onSelect = onSelect
        coordinator.fitInsets = fitInsets
        if coordinator.baseLayer != baseLayer {
            coordinator.setBaseLayer(baseLayer, on: map)
        }
        if coordinator.contentID != contentID {
            coordinator.contentID = contentID
            coordinator.show(shapes: shapes, pins: pins, on: map)
        }
        coordinator.apply(colors: pinColors, on: map)
        coordinator.move(movingPin, on: map)
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var onSelect: ((String) -> Void)?
        var contentID: String?
        var baseLayer: BaseLayer?
        var fitInsets = UIEdgeInsets.zero
        private var tiles: MKTileOverlay?
        private var styles: [ObjectIdentifier: MapShape] = [:]
        private var annotationsByID: [String: PinAnnotation] = [:]
        private var appliedColors: [String: UIColor] = [:]
        private var moving: MovingAnnotation?
        private let locationManager = CLLocationManager()
        private var dotImages: [UIColor: UIImage] = [:]

        /// Shows your own position on the map (blue dot), useful in the field.
        func requestLocationPermission() {
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestWhenInUseAuthorization()
            }
        }

        func setBaseLayer(_ layer: BaseLayer, on map: MKMapView) {
            baseLayer = layer
            if let tiles = tiles {
                map.removeOverlay(tiles)
                self.tiles = nil
            }
            guard layer == .pdok else { return }
            let overlay = MKTileOverlay(urlTemplate: MapCanvas.pdokTiles)
            overlay.canReplaceMapContent = true
            overlay.maximumZ = 21
            map.insertOverlay(overlay, at: 0, level: .aboveRoads)
            tiles = overlay
        }

        func show(shapes: [MapShape], pins: [MapPin], on map: MKMapView) {
            map.removeOverlays(map.overlays.filter { !($0 is MKTileOverlay) })
            map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })
            styles = [:]
            appliedColors = [:]
            moving = nil

            var visible = MKMapRect.null
            for shape in shapes where shape.points.count >= 2 {
                var coordinates = shape.points.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
                let overlay: MKOverlay
                switch shape.kind {
                case .polygon:
                    overlay = MKPolygon(coordinates: &coordinates, count: coordinates.count)
                case .polyline:
                    overlay = MKPolyline(coordinates: &coordinates, count: coordinates.count)
                }
                styles[ObjectIdentifier(overlay)] = shape
                map.addOverlay(overlay, level: .aboveRoads)
                visible = visible.union(overlay.boundingMapRect)
            }
            let annotations = pins.map(PinAnnotation.init)
            annotationsByID = Dictionary(annotations.map { ($0.pin.id, $0) }, uniquingKeysWith: { first, _ in first })
            map.addAnnotations(annotations)
            for annotation in annotations {
                let point = MKMapPoint(annotation.coordinate)
                visible = visible.union(MKMapRect(x: point.x, y: point.y, width: 0, height: 0))
            }
            guard !visible.isNull, let map = map as? FittingMapView else { return }
            map.fitInsets = fitInsets
            map.userMoved = false
            map.fitRect = visible
        }

        func apply(colors: [String: UIColor], on map: MKMapView) {
            for (id, color) in colors where appliedColors[id] != color {
                guard let annotation = annotationsByID[id] else { continue }
                annotation.color = color
                if let view = map.view(for: annotation) {
                    view.image = dotImage(color)
                }
            }
            appliedColors = colors
        }

        func move(_ pin: MapPin?, on map: MKMapView) {
            guard let pin = pin else {
                if let moving = moving {
                    map.removeAnnotation(moving)
                    self.moving = nil
                }
                return
            }
            let coordinate = CLLocationCoordinate2D(latitude: pin.coordinate.lat, longitude: pin.coordinate.lng)
            if let moving = moving {
                moving.coordinate = coordinate
            } else {
                let annotation = MovingAnnotation(pin: pin, coordinate: coordinate)
                map.addAnnotation(annotation)
                moving = annotation
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tiles)
            }
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
            if style?.dashed == true {
                renderer.lineDashPattern = [6, 5]
            }
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let moving = annotation as? MovingAnnotation {
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: "moving") as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: moving, reuseIdentifier: "moving")
                view.annotation = moving
                if case .marker(let symbol, let color) = moving.pin.style {
                    view.glyphImage = UIImage(systemName: symbol)
                    view.markerTintColor = color
                }
                view.displayPriority = .required
                view.zPriority = .max
                view.canShowCallout = false
                return view
            }
            guard let annotation = annotation as? PinAnnotation else { return nil }
            switch annotation.pin.style {
            case .dot(let color):
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "dot")
                    ?? MKAnnotationView(annotation: annotation, reuseIdentifier: "dot")
                view.annotation = annotation
                view.image = dotImage(annotation.color ?? color)
                view.canShowCallout = false
                view.displayPriority = .required
                return view
            case .marker(let symbol, let color):
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: "marker") as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "marker")
                view.annotation = annotation
                view.markerTintColor = color
                view.glyphImage = UIImage(systemName: symbol)
                // A still preview stays clean: no names under the markers.
                view.titleVisibility = mapView.isUserInteractionEnabled ? .adaptive : .hidden
                view.displayPriority = .required
                return view
            }
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation as? PinAnnotation else { return }
            mapView.deselectAnnotation(annotation, animated: false)
            onSelect?(annotation.pin.id)
        }

        @objc func handleMove(_ gesture: UIGestureRecognizer) {
            if gesture.state == .began {
                (gesture.view as? FittingMapView)?.userMoved = true
            }
        }

        /// Taps inside a tappable polygon, for example a strip with water advice.
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let map = gesture.view as? MKMapView else { return }
            let location = gesture.location(in: map)
            var hit = map.hitTest(location, with: nil)
            while let view = hit {
                if view is MKAnnotationView { return } // pins report through didSelect
                hit = view.superview
            }
            let tapped = MKMapPoint(map.convert(location, toCoordinateFrom: map))
            for overlay in map.overlays.reversed() {
                guard let polygon = overlay as? MKPolygon,
                      let style = styles[ObjectIdentifier(polygon)], style.tappable else { continue }
                let corners = (0..<polygon.pointCount).map { XY(x: polygon.points()[$0].x, y: polygon.points()[$0].y) }
                if Geo.pointInPolygon(XY(x: tapped.x, y: tapped.y), corners) {
                    onSelect?(style.id)
                    return
                }
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        private func dotImage(_ color: UIColor) -> UIImage {
            if let image = dotImages[color] { return image }
            let size = CGSize(width: 8, height: 8)
            let image = UIGraphicsImageRenderer(size: size).image { context in
                let rect = CGRect(origin: .zero, size: size).insetBy(dx: 0.75, dy: 0.75)
                color.setFill()
                UIColor.black.withAlphaComponent(0.6).setStroke()
                context.cgContext.setLineWidth(1)
                context.cgContext.fillEllipse(in: rect)
                context.cgContext.strokeEllipse(in: rect)
            }
            dotImages[color] = image
            return image
        }
    }
}

/// Zooms to its shapes and pins after every change of size, until you move the map yourself.
/// Fitting only once goes wrong when the map first appears at another size than it ends up.
final class FittingMapView: MKMapView {
    var fitRect: MKMapRect? {
        didSet {
            fittedSize = nil
            setNeedsLayout()
        }
    }
    var fitInsets = UIEdgeInsets.zero
    /// You panned, pinched or turned the map: it stays where you put it.
    var userMoved = false
    private var fittedSize: CGSize?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let rect = fitRect, !userMoved, bounds.width > 0, bounds.height > 0, bounds.size != fittedSize else { return }
        fittedSize = bounds.size
        setVisibleMapRect(rect, edgePadding: usableInsets, animated: false)
    }

    /// The insets for floating panels, smaller when the map is too small for them. MapKit
    /// adds its own layout margins (with the safe area) to the padding, so those come off.
    private var usableInsets: UIEdgeInsets {
        var insets = fitInsets
        let vertical = insets.top + insets.bottom
        if vertical > bounds.height * 0.7 {
            let factor = bounds.height * 0.7 / vertical
            insets.top *= factor
            insets.bottom *= factor
        }
        let horizontal = insets.left + insets.right
        if horizontal > bounds.width * 0.7 {
            let factor = bounds.width * 0.7 / horizontal
            insets.left *= factor
            insets.right *= factor
        }
        let margins = layoutMarginsGuide.layoutFrame
        insets.top = max(8, insets.top - (margins.minY - bounds.minY))
        insets.left = max(8, insets.left - (margins.minX - bounds.minX))
        insets.bottom = max(8, insets.bottom - (bounds.maxY - margins.maxY))
        insets.right = max(8, insets.right - (bounds.maxX - margins.maxX))
        return insets
    }
}

private final class PinAnnotation: NSObject, MKAnnotation {
    let pin: MapPin
    let coordinate: CLLocationCoordinate2D
    /// Replaces the colour of a dot pin.
    var color: UIColor?

    var title: String? { pin.title }

    init(_ pin: MapPin) {
        self.pin = pin
        coordinate = CLLocationCoordinate2D(latitude: pin.coordinate.lat, longitude: pin.coordinate.lng)
    }
}

/// The drone on the map: MapKit moves it smoothly when `coordinate` changes.
private final class MovingAnnotation: NSObject, MKAnnotation {
    let pin: MapPin
    @objc dynamic var coordinate: CLLocationCoordinate2D

    init(pin: MapPin, coordinate: CLLocationCoordinate2D) {
        self.pin = pin
        self.coordinate = coordinate
    }
}

/// The required credit for the base layer, shown at the bottom of a map.
struct MapAttribution: View {
    let layer: BaseLayer

    var body: some View {
        Text(layer.attribution)
            .font(.caption2)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.regularMaterial, in: Capsule())
    }
}

/// Menu to switch between the PDOK aerial photo and Apple's satellite map.
struct BaseLayerMenu: View {
    enum Style {
        /// A button in the navigation bar.
        case toolbar
        /// A round glass button floating over the map.
        case floating
        /// A small round button inside a glass card.
        case inCard
    }

    @Binding var layer: BaseLayer
    var style = Style.toolbar

    var body: some View {
        Menu {
            Picker("Kaart", selection: $layer) {
                ForEach(BaseLayer.allCases) { Text($0.label).tag($0) }
            }
        } label: {
            switch style {
            case .toolbar:
                Label("Kaart", systemImage: "square.3.layers.3d")
            case .floating:
                GlassCircle(symbol: "square.3.layers.3d").accessibilityLabel("Kaart")
            case .inCard:
                Image(systemName: "square.3.layers.3d")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .background(Color(uiColor: .tertiarySystemFill), in: Circle())
                    .accessibilityLabel("Kaart")
            }
        }
    }
}
