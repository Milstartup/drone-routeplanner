@testable import VeldvluchtKern
import XCTest

final class GeoTests: XCTestCase {
    func testDistanceAlongAMeridian() {
        // 0.001 degree of latitude is about 111.2 m everywhere.
        let a = LatLng(lat: 52.5, lng: 5.5)
        let b = LatLng(lat: 52.501, lng: 5.5)
        XCTAssertEqual(Geo.distanceM(a, b), 111.195, accuracy: 0.01)
    }

    func testBearing() {
        let a = LatLng(lat: 52.5, lng: 5.5)
        XCTAssertEqual(Geo.bearingDeg(a, LatLng(lat: 52.501, lng: 5.5)), 0, accuracy: 0.001)
        XCTAssertEqual(Geo.bearingDeg(a, LatLng(lat: 52.5, lng: 5.501)), 90, accuracy: 0.01)
    }

    func testProjectionRoundTrip() {
        let projection = LocalProjection(origin: LatLng(lat: 52.5, lng: 5.5))
        let p = LatLng(lat: 52.5012, lng: 5.4987)
        let back = projection.toLatLng(projection.toXY(p))
        XCTAssertEqual(back.lat, p.lat, accuracy: 1e-12)
        XCTAssertEqual(back.lng, p.lng, accuracy: 1e-12)
    }

    func testPointInPolygonAndArea() {
        let square = [XY(x: 0, y: 0), XY(x: 10, y: 0), XY(x: 10, y: 10), XY(x: 0, y: 10)]
        XCTAssertTrue(Geo.pointInPolygon(XY(x: 5, y: 5), square))
        XCTAssertFalse(Geo.pointInPolygon(XY(x: 15, y: 5), square))
        XCTAssertEqual(Geo.distanceToPolygonEdges(XY(x: 5, y: 12), square), 2, accuracy: 1e-9)

        let projection = LocalProjection(origin: LatLng(lat: 52.5, lng: 5.5))
        let field = [XY(x: 0, y: 0), XY(x: 100, y: 0), XY(x: 100, y: 50), XY(x: 0, y: 50)].map(projection.toLatLng)
        XCTAssertEqual(Geo.polygonAreaM2(field), 5000, accuracy: 1)
    }

    func testValidCoordinates() {
        XCTAssertTrue(LatLng(lat: 52.5, lng: 5.5).isValid)
        XCTAssertFalse(LatLng(lat: 91, lng: 5.5).isValid)
        XCTAssertFalse(LatLng(lat: 52.5, lng: -181).isValid)
        XCTAssertFalse(LatLng(lat: .nan, lng: 5.5).isValid)
    }
}
