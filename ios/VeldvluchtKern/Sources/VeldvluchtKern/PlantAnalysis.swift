// The photo analysis, level 1 of docs/ARCHITECTUUR.md chapter 7 (no trained AI): find the
// single plants in a drone photo, measure how green and how big each one is, and mark the
// plants that clearly differ from their neighbours as "aandacht nodig". Then work out where
// such a plant is on the ground, from the drone's position, height and heading in the photo log.
// Plain Swift on a pixel buffer; the Mac tool `foto-analyse` reads the JPEGs.
import Foundation

enum PlantAnalysis {
    /// A plant found in a photo.
    struct Plant: Equatable {
        /// Centre in pixels (x to the right, y down).
        var x: Double
        var y: Double
        var areaPx: Int
        /// Mean greenness: 2g − r − b of the chromatic colours (0 = grey, higher = greener).
        var greenness: Double
        /// Part of the plant lies outside the photo, so it looks smaller than it is.
        var touchesEdge = false
    }

    /// A plant that needs attention, with why and how sure.
    struct Finding: Equatable {
        var plant: Plant
        var reason: String
        var confidence: Double
    }

    struct Settings {
        /// Smaller blobs are noise (weeds, stones), in pixels of the analysed image.
        var minAreaPx = 12
        /// How far below its neighbours (in robust standard deviations) a plant must be.
        var outlierZ = 2.5
        /// Fewer plants in a photo give no reliable neighbours.
        var minPlants = 8
    }

    /// Greenness of one pixel: excess green of the chromatic colours, −1...2.
    @inline(__always)
    static func excessGreen(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Double {
        let sum = Double(r) + Double(g) + Double(b)
        guard sum > 0 else { return 0 }
        return (2 * Double(g) - Double(r) - Double(b)) / sum
    }

    /// Plants in an RGBA image (4 bytes per pixel, rows of `width`).
    static func plants(rgba: [UInt8], width: Int, height: Int, settings: Settings = Settings()) -> [Plant] {
        guard width > 0, height > 0, rgba.count >= width * height * 4 else { return [] }
        var index = [Double](repeating: 0, count: width * height)
        for i in 0..<(width * height) {
            index[i] = excessGreen(rgba[i * 4], rgba[i * 4 + 1], rgba[i * 4 + 2])
        }
        // Otsu separates soil and green plants; capped low, so yellowing plants still count.
        let threshold = min(max(0.05, otsu(index)), 0.12)
        var mask = index.map { $0 > threshold }

        // Connected parts of the mask (4 neighbours), with a stack instead of recursion.
        var plants: [Plant] = []
        var stack: [Int] = []
        for start in 0..<mask.count where mask[start] {
            mask[start] = false
            stack.append(start)
            var count = 0
            var sumX = 0.0
            var sumY = 0.0
            var sumGreen = 0.0
            var touchesEdge = false
            while let p = stack.popLast() {
                let x = p % width
                let y = p / width
                touchesEdge = touchesEdge || x == 0 || y == 0 || x == width - 1 || y == height - 1
                count += 1
                sumX += Double(x)
                sumY += Double(y)
                sumGreen += index[p]
                for (q, inside) in [(p - 1, x > 0), (p + 1, x < width - 1), (p - width, y > 0), (p + width, y < height - 1)]
                    where inside && mask[q] {
                    mask[q] = false
                    stack.append(q)
                }
            }
            if count >= settings.minAreaPx {
                plants.append(Plant(x: sumX / Double(count), y: sumY / Double(count), areaPx: count,
                                    greenness: sumGreen / Double(count), touchesEdge: touchesEdge))
            }
        }
        return plants
    }

    /// Otsu's threshold on values in −1...2: the split that separates soil and plants best.
    static func otsu(_ values: [Double]) -> Double {
        let bins = 256
        var histogram = [Double](repeating: 0, count: bins)
        for v in values {
            let b = min(bins - 1, max(0, Int((v + 1) / 3 * Double(bins))))
            histogram[b] += 1
        }
        let total = Double(values.count)
        let sumAll = histogram.enumerated().reduce(0) { $0 + Double($1.offset) * $1.element }
        var weightBelow = 0.0
        var sumBelow = 0.0
        var best = 0.0
        var bestBin = 0
        for b in 0..<bins {
            weightBelow += histogram[b]
            guard weightBelow > 0, weightBelow < total else { continue }
            sumBelow += Double(b) * histogram[b]
            let meanBelow = sumBelow / weightBelow
            let meanAbove = (sumAll - sumBelow) / (total - weightBelow)
            let between = weightBelow * (total - weightBelow) * pow(meanBelow - meanAbove, 2)
            if between > best {
                best = between
                bestBin = b
            }
        }
        return (Double(bestBin) + 1) / Double(bins) * 3 - 1
    }

    /// Plants much less green or much smaller than the other plants in the same photo. A plant
    /// partly outside the photo only looks small: the overlapping photo shows it whole.
    static func findings(_ plants: [Plant], settings: Settings = Settings()) -> [Finding] {
        let plants = plants.filter { !$0.touchesEdge }
        guard plants.count >= settings.minPlants else { return [] }
        let greens = plants.map(\.greenness)
        let areas = plants.map { Double($0.areaPx) }
        // At least a small spread, so very even plants do not make tiny differences count.
        let (greenMedian, greenMAD) = medianAndSpread(greens)
        let greenSpread = max(greenMAD, 0.05)
        let (areaMedian, areaMAD) = medianAndSpread(areas)
        let areaSpread = max(areaMAD, 0.1 * areaMedian)
        var findings: [Finding] = []
        for plant in plants {
            let zGreen = greenSpread > 0 ? (plant.greenness - greenMedian) / greenSpread : 0
            let zArea = areaSpread > 0 ? (Double(plant.areaPx) - areaMedian) / areaSpread : 0
            var reasons: [String] = []
            if zGreen < -settings.outlierZ {
                reasons.append("veel minder groen dan de planten eromheen (geler of bleker)")
            }
            if zArea < -settings.outlierZ {
                let share = Int((Double(plant.areaPx) / areaMedian * 100).rounded())
                reasons.append("kleiner dan de planten eromheen (\(share) % van hun grootte)")
            }
            guard !reasons.isEmpty else { continue }
            let strength = max(-zGreen, -zArea)
            findings.append(Finding(plant: plant, reason: "Plant " + reasons.joined(separator: " en ") + ".",
                                    confidence: min(0.8, 0.3 + (strength - settings.outlierZ) * 0.1)))
        }
        return findings
    }

    /// Median, and the median absolute deviation scaled to a standard deviation.
    static func medianAndSpread(_ values: [Double]) -> (Double, Double) {
        func median(_ list: [Double]) -> Double {
            let sorted = list.sorted()
            guard !sorted.isEmpty else { return 0 }
            let middle = sorted.count / 2
            return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
        }
        let m = median(values)
        return (m, 1.4826 * median(values.map { abs($0 - m) }))
    }

    /// Where a pixel of a photo lies on the ground. The camera looks straight down; the top of
    /// the photo points in the drone's heading, and the long side lies across it.
    static func position(x: Double, y: Double, width: Int, height: Int, photo: PhotoLog.Photo) -> LatLng? {
        guard let footprint = CameraFootprint.at(altitudeM: photo.altitudeM), width > 0 else { return nil }
        let metresPerPixel = footprint.widthM / Double(width)
        let right = (x - Double(width) / 2) * metresPerPixel
        let forward = (Double(height) / 2 - y) * metresPerPixel
        let h = photo.headingDeg * Geo.deg
        let east = right * cos(h) + forward * sin(h)
        let north = -right * sin(h) + forward * cos(h)
        return LocalProjection(origin: LatLng(lat: photo.lat, lng: photo.lng)).toLatLng(XY(x: east, y: north))
    }

    /// Findings seen in more than one photo (the photos overlap) count once: the surest one.
    static func merge(_ marks: [(LatLng, Finding, String)], withinM: Double = 0.75) -> [(LatLng, Finding, String)] {
        var kept: [(LatLng, Finding, String)] = []
        for mark in marks.sorted(by: { $0.1.confidence > $1.1.confidence }) {
            if !kept.contains(where: { Geo.distanceM($0.0, mark.0) < withinM }) {
                kept.append(mark)
            }
        }
        return kept
    }
}
