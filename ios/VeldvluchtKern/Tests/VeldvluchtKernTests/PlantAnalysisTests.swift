@testable import VeldvluchtKern
import XCTest

final class PlantAnalysisTests: XCTestCase {
    /// A made-up photo: brown soil with rows of green plants, one yellowish and one small.
    private func photo() -> (rgba: [UInt8], width: Int, height: Int) {
        let width = 240
        let height = 160
        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        func paint(_ x: Int, _ y: Int, _ c: (UInt8, UInt8, UInt8)) {
            let i = (y * width + x) * 4
            (rgba[i], rgba[i + 1], rgba[i + 2]) = c
        }
        for y in 0..<height {
            for x in 0..<width { paint(x, y, (122, 92, 64)) }
        }
        for row in 0..<4 {
            for column in 0..<6 {
                let cx = 20 + column * 40
                let cy = 20 + row * 40
                let yellow = row == 1 && column == 2
                let small = row == 3 && column == 4
                let radius = small ? 3 : 7
                let colour: (UInt8, UInt8, UInt8) = yellow ? (150, 150, 70) : (45, 140, 50)
                for y in (cy - radius)...(cy + radius) {
                    for x in (cx - radius)...(cx + radius) where (x - cx) * (x - cx) + (y - cy) * (y - cy) <= radius * radius {
                        paint(x, y, colour)
                    }
                }
            }
        }
        return (rgba, width, height)
    }

    func testFindsThePlantsAndTheTwoThatDiffer() {
        let image = photo()
        let plants = PlantAnalysis.plants(rgba: image.rgba, width: image.width, height: image.height)
        XCTAssertEqual(plants.count, 24)
        let findings = PlantAnalysis.findings(plants)
        XCTAssertEqual(findings.count, 2, "\(findings.map(\.reason))")
        let yellow = findings.first { $0.reason.contains("minder groen") }
        XCTAssertEqual(yellow?.plant.x ?? 0, 100, accuracy: 0.5)
        XCTAssertEqual(yellow?.plant.y ?? 0, 60, accuracy: 0.5)
        let small = findings.first { $0.reason.contains("kleiner") }
        XCTAssertEqual(small?.plant.x ?? 0, 180, accuracy: 0.5)
        XCTAssertEqual(small?.plant.y ?? 0, 140, accuracy: 0.5)
        XCTAssertTrue(findings.allSatisfy { (0.3...0.8).contains($0.confidence) })
    }

    /// Found with made-up overlapping photos (9 November 2026): a plant cut off by the edge of
    /// the photo looked small, and every photo got a row of false markers along its edges.
    func testAPlantCutOffByTheEdgeIsNotMarked() {
        var image = photo()
        // Only a sliver of this plant is in the photo.
        for y in 75...89 {
            for x in 0...1 {
                let i = (y * image.width + x) * 4
                (image.rgba[i], image.rgba[i + 1], image.rgba[i + 2]) = (45, 140, 50)
            }
        }
        let plants = PlantAnalysis.plants(rgba: image.rgba, width: image.width, height: image.height)
        XCTAssertEqual(plants.count, 25)
        XCTAssertEqual(plants.filter(\.touchesEdge).count, 1)
        let findings = PlantAnalysis.findings(plants)
        XCTAssertEqual(findings.count, 2, "\(findings.map(\.reason))")
        XCTAssertFalse(findings.contains { $0.plant.touchesEdge })
    }

    func testAPhotoWithoutPlantsGivesNothing() {
        let width = 50
        let rgba = [UInt8]((0..<(width * width)).flatMap { _ in [UInt8(122), 92, 64, 255] })
        XCTAssertTrue(PlantAnalysis.plants(rgba: rgba, width: width, height: width).isEmpty)
        XCTAssertTrue(PlantAnalysis.findings([]).isEmpty)
    }

    func testWhereAPixelLiesOnTheGround() throws {
        let photo = PhotoLog.Photo(index: 0, plannedPhotoIndex: 0, file: "DJI_0001.JPG", time: Date(),
                                   lat: 52.5, lng: 5.54, altitudeM: 30, headingDeg: 0)
        let projection = LocalProjection(origin: LatLng(lat: 52.5, lng: 5.54))
        let metresPerPixel = try XCTUnwrap(CameraFootprint.at(altitudeM: 30)).widthM / 1000
        // The middle of the photo is right below the drone.
        let middle = try XCTUnwrap(PlantAnalysis.position(x: 500, y: 375, width: 1000, height: 750, photo: photo))
        XCTAssertEqual(Geo.distanceM(middle, LatLng(lat: 52.5, lng: 5.54)), 0, accuracy: 0.01)
        // Heading north: the top of the photo is north.
        let top = projection.toXY(try XCTUnwrap(PlantAnalysis.position(x: 500, y: 0, width: 1000, height: 750, photo: photo)))
        XCTAssertEqual(top.y, 375 * metresPerPixel, accuracy: 0.01)
        XCTAssertEqual(top.x, 0, accuracy: 0.01)
        // Heading east: the top of the photo is east, its right side south.
        var east = photo
        east.headingDeg = 90
        let topEast = projection.toXY(try XCTUnwrap(PlantAnalysis.position(x: 500, y: 0, width: 1000, height: 750, photo: east)))
        XCTAssertEqual(topEast.x, 375 * metresPerPixel, accuracy: 0.01)
        let right = projection.toXY(try XCTUnwrap(PlantAnalysis.position(x: 1000, y: 375, width: 1000, height: 750, photo: east)))
        XCTAssertEqual(right.y, -500 * metresPerPixel, accuracy: 0.01)
    }

    func testAPlantSeenInTwoPhotosCountsOnce() {
        let finding = PlantAnalysis.Finding(plant: .init(x: 0, y: 0, areaPx: 10, greenness: 0.1), reason: "x", confidence: 0.4)
        var surer = finding
        surer.confidence = 0.6
        let a = LatLng(lat: 52.5, lng: 5.54)
        let b = LocalProjection(origin: a).toLatLng(XY(x: 0.3, y: 0))
        let c = LocalProjection(origin: a).toLatLng(XY(x: 5, y: 0))
        let merged = PlantAnalysis.merge([(a, finding, "DJI_0001.JPG"), (b, surer, "DJI_0002.JPG"), (c, finding, "DJI_0002.JPG")])
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(merged.first?.2, "DJI_0002.JPG")
    }
}
