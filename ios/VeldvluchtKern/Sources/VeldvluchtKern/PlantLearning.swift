// Learning from the farmer's own photos, level 3 of docs/ARCHITECTUUR.md chapter 7. The photo
// analysis cuts every plant it marks, and a few ordinary ones, out as a small picture. The
// farmer checks those plants in the field and drags each picture into the folder of its kind.
// Create ML learns from those folders on the Mac, and the analysis then asks that model about
// every plant. This is the part without Apple's image frameworks, so `swift test` checks it;
// the Mac tool foto-analyse does the cutting, learning and asking. The app does not use it.
import Foundation

enum PlantLearning {
    /// The kinds the model learns. The raw value is the folder name in the learning folder.
    enum Kind: String, CaseIterable {
        case gezond
        case teDroog = "te-droog"
        case teNat = "te-nat"
        case ziek = "ziek-of-beschadigd"
        case geenPlant = "geen-plant"

        var text: String {
            switch self {
            case .gezond: return "gezond"
            case .teDroog: return "te droog"
            case .teNat: return "te nat"
            case .ziek: return "ziek of beschadigd"
            case .geenPlant: return "geen plant (onkruid, een steen of schaduw)"
            }
        }

        /// A plant of this kind gets a marker on the field map.
        var needsAttention: Bool { self == .teDroog || self == .teNat || self == .ziek }
    }

    /// What the model says about one plant.
    struct Verdict: Equatable {
        var kind: Kind
        var confidence: Double
    }

    /// A square of a photo, in pixels from the top left.
    struct Square: Equatable {
        var x: Int
        var y: Int
        var side: Int
    }

    /// New pictures wait here until the farmer sorts them.
    static let unsortedFolder = "nog-labelen"
    static let modelFile = "planten-model.mlmodel"
    /// With fewer pictures of a kind the model learns nothing about it.
    static let minPicturesPerKind = 5
    /// Below this the model is not sure enough for a marker of its own.
    static let minConfidence = 0.6
    /// The pictures are this many pixels wide and high.
    static let pictureSizePx = 224
    /// A picture shows the plant with some soil around it: this many widths of an ordinary plant
    /// in the same photo. Not of the plant itself: then a small plant would look as big as the
    /// others, and the model could not learn that it stays behind.
    static let spanInPlantWidths = 2.5
    /// The smallest square, in pixels of the full photo: about 50 cm at 30 m.
    static let minSidePx = 48

    /// The size of an ordinary plant in a photo: the median area, in pixels.
    static func typicalArea(_ plants: [PlantAnalysis.Plant]) -> Double {
        PlantAnalysis.medianAndSpread(plants.map { Double($0.areaPx) }).0
    }

    /// The square around a plant, in pixels of the photo the plant was found in times `scale`
    /// (the full photo's width divided by the analysed width). A plant much bigger than the
    /// ordinary ones still fits. Near an edge the square moves inwards; `whole` is false then,
    /// because part of the plant's surroundings is missing.
    static func square(for plant: PlantAnalysis.Plant, typicalAreaPx: Double, scale: Double,
                       width: Int, height: Int) -> (square: Square, whole: Bool)? {
        func diameter(_ area: Double) -> Double { 2 * (area / .pi).squareRoot() * scale }
        let wanted = max(diameter(typicalAreaPx) * spanInPlantWidths, diameter(Double(plant.areaPx)) * 1.3)
        let side = min(max(Int(wanted.rounded()), minSidePx), width, height)
        guard side > 0 else { return nil }
        let left = Int((plant.x * scale - Double(side) / 2).rounded())
        let top = Int((plant.y * scale - Double(side) / 2).rounded())
        let x = min(max(0, left), width - side)
        let y = min(max(0, top), height - side)
        return (Square(x: x, y: y, side: side), x == left && y == top)
    }

    /// A few plants the rules did not mark, spread over the photo, so the model also sees
    /// ordinary plants. Only plants with all their surroundings in the photo.
    static func sample(_ plants: [PlantAnalysis.Plant], excluding marked: [PlantAnalysis.Plant], count: Int,
                       width: Int, height: Int) -> [PlantAnalysis.Plant] {
        let typical = typicalArea(plants)
        let candidates = plants
            .filter { plant in
                !marked.contains(plant)
                    && square(for: plant, typicalAreaPx: typical, scale: 1, width: width, height: height)?.whole == true
            }
            .sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        guard count > 0, !candidates.isEmpty else { return [] }
        let n = min(count, candidates.count)
        return (0..<n).map { candidates[($0 * candidates.count) / n] }
    }

    /// File name of a picture: the flight, the marker number when it has one, the photo and the
    /// plant's place in it. The same plant always gets the same name, so analysing a flight
    /// again does not add it twice.
    static func pictureName(flightId: String, mark: Int?, photoFile: String, plant: PlantAnalysis.Plant) -> String {
        let photo = (photoFile as NSString).deletingPathExtension
        let place = String(format: "x%04d_y%04d", Int(plant.x.rounded()), Int(plant.y.rounded()))
        let parts = [safe(flightId), mark.map { String(format: "plek-%03d", $0) }, safe(photo), place]
        return parts.compactMap { $0 }.joined(separator: "_") + ".jpg"
    }

    /// The name without the marker number: the same plant when a new analysis numbers the
    /// markers differently.
    static func pictureKey(_ name: String) -> String {
        name.split(separator: "_").filter { !$0.hasPrefix("plek-") }.joined(separator: "_")
    }

    private static func safe(_ text: String) -> String {
        String(text.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "-" })
    }

    /// Which kinds have enough pictures to learn, and what to tell the farmer about the rest.
    static func check(counts: [Kind: Int]) -> (usable: [Kind], messages: [String]) {
        var usable: [Kind] = []
        var messages: [String] = []
        for kind in Kind.allCases {
            let count = counts[kind] ?? 0
            if count >= minPicturesPerKind {
                usable.append(kind)
            } else if count > 0 {
                messages.append("\(kind.rawValue): \(count) plaatje\(count == 1 ? "" : "s"), minstens \(minPicturesPerKind) nodig. Deze soort leert de AI nog niet.")
            }
        }
        if usable.count < 2 {
            messages.append("De AI heeft minstens twee soorten nodig met elk \(minPicturesPerKind) plaatjes, bijvoorbeeld gezond en te-droog.")
        }
        return (usable, messages)
    }

    /// Overlapping photos show a plant several times, and the model takes about 0.1 s per look.
    /// So it looks once: in the photo whose centre is nearest, where the camera was right above it.
    static func isNearestPhoto(_ place: LatLng, photo: PhotoLog.Photo, photos: [PhotoLog.Photo]) -> Bool {
        let own = Geo.distanceM(place, LatLng(lat: photo.lat, lng: photo.lng))
        return !photos.contains { $0.index != photo.index && Geo.distanceM(place, LatLng(lat: $0.lat, lng: $0.lng)) < own }
    }

    /// What the model said about the plant at a marker the rules made, perhaps in another photo.
    static func verdict(near place: LatLng, in verdicts: [(LatLng, Verdict)], withinM: Double = 0.75) -> Verdict? {
        verdicts.map { (Geo.distanceM($0.0, place), $0.1) }.filter { $0.0 < withinM }.min { $0.0 < $1.0 }?.1
    }

    static func text(_ verdict: Verdict) -> String {
        "AI: \(verdict.kind.text) (\(Int((verdict.confidence * 100).rounded())) % zeker)."
    }

    /// A marker of its own, when the model is sure enough that a plant needs attention.
    static func finding(for plant: PlantAnalysis.Plant, verdict: Verdict) -> PlantAnalysis.Finding? {
        guard verdict.kind.needsAttention, verdict.confidence >= minConfidence else { return nil }
        return PlantAnalysis.Finding(plant: plant, reason: text(verdict), confidence: min(0.95, verdict.confidence))
    }

    /// A plant the rules marked: what the model says is added to the reason.
    static func adding(_ verdict: Verdict, to finding: PlantAnalysis.Finding) -> PlantAnalysis.Finding {
        var result = finding
        result.reason += " " + text(verdict)
        return result
    }
}
