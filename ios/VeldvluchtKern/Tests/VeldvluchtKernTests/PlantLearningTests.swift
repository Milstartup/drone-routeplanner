@testable import VeldvluchtKern
import XCTest

final class PlantLearningTests: XCTestCase {
    private func plant(_ x: Double, _ y: Double, area: Int = 154) -> PlantAnalysis.Plant {
        PlantAnalysis.Plant(x: x, y: y, areaPx: area, greenness: 0.3)
    }

    func testTheSquareAroundAPlantInTheFullPhoto() throws {
        // 154 px is a disc 14 px across; the full photo is 2 times wider than the analysed one.
        let (square, whole) = try XCTUnwrap(PlantLearning.square(for: plant(100, 60), typicalAreaPx: 154, scale: 2,
                                                                 width: 2400, height: 1800))
        XCTAssertTrue(whole)
        XCTAssertEqual(square.side, 70, "2,5 plantbreedtes van 28 px")
        XCTAssertEqual(square.x + square.side / 2, 200)
        XCTAssertEqual(square.y + square.side / 2, 120)
    }

    func testASmallPlantLooksSmallInItsPicture() throws {
        // A quarter of the area of an ordinary plant: the same square, so half as wide in the picture.
        let small = try XCTUnwrap(PlantLearning.square(for: plant(100, 60, area: 39), typicalAreaPx: 154, scale: 2,
                                                       width: 2400, height: 1800))
        XCTAssertEqual(small.square.side, 70)
        // A plant much bigger than the ordinary ones still fits.
        let big = try XCTUnwrap(PlantLearning.square(for: plant(300, 300, area: 154 * 9), typicalAreaPx: 154, scale: 1,
                                                     width: 1200, height: 900))
        XCTAssertEqual(big.square.side, 55, "1,3 keer zijn eigen breedte van 42 px")
        XCTAssertEqual(PlantLearning.typicalArea([plant(0, 0, area: 10), plant(0, 0, area: 100), plant(0, 0, area: 30)]), 30)
    }

    func testATinyPlantStillGetsAUsefulSquare() throws {
        let (square, _) = try XCTUnwrap(PlantLearning.square(for: plant(500, 500, area: 12), typicalAreaPx: 12, scale: 1,
                                                             width: 1200, height: 900))
        XCTAssertEqual(square.side, PlantLearning.minSidePx)
    }

    func testNearTheEdgeTheSquareMovesInside() throws {
        let (square, whole) = try XCTUnwrap(PlantLearning.square(for: plant(5, 897), typicalAreaPx: 154, scale: 1,
                                                                 width: 1200, height: 900))
        XCTAssertFalse(whole)
        XCTAssertEqual(square.x, 0)
        XCTAssertEqual(square.y + square.side, 900)
    }

    func testTheSampleIsSpreadSkipsMarkedPlantsAndEdges() {
        let grid = (0..<10).flatMap { row in (0..<10).map { column in plant(Double(50 + column * 100), Double(50 + row * 80)) } }
        let marked = [grid[44], grid[55]]
        let edge = plant(2, 400)
        let sample = PlantLearning.sample(grid + [edge], excluding: marked, count: 5, width: 1000, height: 800)
        XCTAssertEqual(sample.count, 5)
        XCTAssertFalse(sample.contains(grid[44]) || sample.contains(grid[55]) || sample.contains(edge))
        XCTAssertGreaterThan(Set(sample.map(\.y)).count, 3, "verspreid over de foto")
        XCTAssertEqual(sample, PlantLearning.sample(grid + [edge], excluding: marked, count: 5, width: 1000, height: 800),
                       "steeds dezelfde, zodat opnieuw analyseren geen nieuwe plaatjes geeft")
        XCTAssertTrue(PlantLearning.sample(grid, excluding: [], count: 0, width: 1000, height: 800).isEmpty)
        XCTAssertEqual(PlantLearning.sample(Array(grid.prefix(3)), excluding: [], count: 5, width: 1000, height: 800).count, 3)
    }

    func testPictureNames() {
        let p = plant(634.4, 41.6)
        XCTAssertEqual(PlantLearning.pictureName(flightId: "2026-11-09-0840-echte vlucht", mark: 7, photoFile: "DJI_0451.JPG", plant: p),
                       "2026-11-09-0840-echte-vlucht_plek-007_DJI-0451_x0634_y0042.jpg")
        XCTAssertEqual(PlantLearning.pictureName(flightId: "v1", mark: nil, photoFile: "DJI_0451.JPG", plant: p),
                       "v1_DJI-0451_x0634_y0042.jpg")
        XCTAssertEqual(PlantLearning.pictureKey("v1_plek-007_DJI-0451_x0634_y0042.jpg"), "v1_DJI-0451_x0634_y0042.jpg")
        XCTAssertEqual(PlantLearning.pictureKey("v1_DJI-0451_x0634_y0042.jpg"), "v1_DJI-0451_x0634_y0042.jpg")
    }

    func testEnoughPicturesToLearn() {
        let (usable, messages) = PlantLearning.check(counts: [.gezond: 40, .teDroog: 6, .ziek: 2])
        XCTAssertEqual(usable, [.gezond, .teDroog])
        XCTAssertEqual(messages, ["ziek-of-beschadigd: 2 plaatjes, minstens 5 nodig. Deze soort leert de AI nog niet."])
        let (none, why) = PlantLearning.check(counts: [.gezond: 40, .teNat: 1])
        XCTAssertEqual(none, [.gezond])
        XCTAssertEqual(why.last, "De AI heeft minstens twee soorten nodig met elk 5 plaatjes, bijvoorbeeld gezond en te-droog.")
    }

    func testTheModelLooksAtAPlantInOnePhotoOnly() {
        let photos = (0..<3).map { i in
            PhotoLog.Photo(index: i, plannedPhotoIndex: i, file: "DJI_000\(i + 1).JPG", time: Date(),
                           lat: 52.5, lng: 5.54, altitudeM: 30, headingDeg: 0)
        }
        var spread = photos
        let projection = LocalProjection(origin: LatLng(lat: 52.5, lng: 5.54))
        for i in spread.indices {
            let centre = projection.toLatLng(XY(x: 0, y: Double(i) * 10))
            spread[i].lat = centre.lat
            spread[i].lng = centre.lng
        }
        // 12 m north: nearest to the photo at 10 m, although the others show it too.
        let plant = projection.toLatLng(XY(x: 3, y: 12))
        XCTAssertEqual(spread.filter { PlantLearning.isNearestPhoto(plant, photo: $0, photos: spread) }.map(\.index), [1])
    }

    func testTheVerdictNearAMarker() {
        let origin = LatLng(lat: 52.5, lng: 5.54)
        let projection = LocalProjection(origin: origin)
        let verdicts: [(LatLng, PlantLearning.Verdict)] = [
            (projection.toLatLng(XY(x: 0.5, y: 0)), .init(kind: .gezond, confidence: 0.9)),
            (projection.toLatLng(XY(x: 0.2, y: 0)), .init(kind: .teDroog, confidence: 0.7)),
            (projection.toLatLng(XY(x: 3, y: 0)), .init(kind: .ziek, confidence: 0.9)),
        ]
        XCTAssertEqual(PlantLearning.verdict(near: origin, in: verdicts)?.kind, .teDroog, "de dichtstbijzijnde")
        XCTAssertNil(PlantLearning.verdict(near: projection.toLatLng(XY(x: 10, y: 0)), in: verdicts))
    }

    func testWhatTheModelSaysBecomesAMarkerOnlyWhenItMatters() throws {
        let p = plant(10, 10)
        let dry = try XCTUnwrap(PlantLearning.finding(for: p, verdict: .init(kind: .teDroog, confidence: 0.823)))
        XCTAssertEqual(dry.reason, "AI: te droog (82 % zeker).")
        XCTAssertEqual(dry.confidence, 0.823, accuracy: 1e-9)
        XCTAssertNil(PlantLearning.finding(for: p, verdict: .init(kind: .teDroog, confidence: 0.5)), "niet zeker genoeg")
        XCTAssertNil(PlantLearning.finding(for: p, verdict: .init(kind: .gezond, confidence: 0.99)))
        XCTAssertNil(PlantLearning.finding(for: p, verdict: .init(kind: .geenPlant, confidence: 0.99)))
        XCTAssertNotNil(PlantLearning.finding(for: p, verdict: .init(kind: .ziek, confidence: 0.7)))
        XCTAssertNotNil(PlantLearning.finding(for: p, verdict: .init(kind: .teNat, confidence: 0.7)))

        let rule = PlantAnalysis.Finding(plant: p, reason: "Plant veel minder groen dan de planten eromheen (geler of bleker).", confidence: 0.4)
        let both = PlantLearning.adding(.init(kind: .geenPlant, confidence: 0.9), to: rule)
        XCTAssertEqual(both.reason, "Plant veel minder groen dan de planten eromheen (geler of bleker). AI: geen plant (onkruid, een steen of schaduw) (90 % zeker).")
        XCTAssertEqual(both.confidence, 0.4)
    }
}
