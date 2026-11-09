// The learning part of foto-analyse (PlantLearning in the app's core explains the idea):
// cutting plants out of the full photo, learning with Create ML, and asking the model.
@testable import VeldvluchtKern
import CoreGraphics
import CoreML
import CreateML
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// The whole photo, upright, in full size.
func fullImage(of url: URL) -> CGImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: max(width, height),
        kCGImageSourceCreateThumbnailWithTransform: true,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
}

/// The square of the photo, scaled to the picture size the model learns from.
func picture(of image: CGImage, _ square: PlantLearning.Square) -> CGImage? {
    let size = PlantLearning.pictureSizePx
    guard let part = image.cropping(to: CGRect(x: square.x, y: square.y, width: square.side, height: square.side)),
          let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
    context.interpolationQuality = .high
    context.draw(part, in: CGRect(x: 0, y: 0, width: size, height: size))
    return context.makeImage()
}

func jpeg(_ image: CGImage) -> Data? {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
    return CGImageDestinationFinalize(destination) ? data as Data : nil
}

/// The learning folder: a folder per kind, plus nog-labelen for new pictures.
final class LearningFolder {
    let url: URL
    /// Pictures the farmer already sorted, by PlantLearning.pictureKey.
    private var sortedKeys: Set<String> = []
    private var unsortedByKey: [String: URL] = [:]

    var unsorted: URL { url.appendingPathComponent(PlantLearning.unsortedFolder, isDirectory: true) }
    var model: URL { url.appendingPathComponent(PlantLearning.modelFile) }

    func folder(_ kind: PlantLearning.Kind) -> URL { url.appendingPathComponent(kind.rawValue, isDirectory: true) }

    /// Makes the folders, so the farmer sees where the pictures go.
    init(url: URL) throws {
        self.url = url
        for folder in [unsorted] + PlantLearning.Kind.allCases.map(folder) {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        sortedKeys = Set(PlantLearning.Kind.allCases.flatMap { pictures(in: folder($0)) }
            .map { PlantLearning.pictureKey($0.lastPathComponent) })
        for picture in pictures(in: unsorted) {
            unsortedByKey[PlantLearning.pictureKey(picture.lastPathComponent)] = picture
        }
    }

    func pictures(in folder: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { ["jpg", "jpeg", "png", "heic"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Writes a new picture to nog-labelen, in place of an older one of the same plant (its
    /// marker number may have changed). false when the farmer already sorted that plant.
    func save(_ data: Data, name: String) throws -> Bool {
        let key = PlantLearning.pictureKey(name)
        guard !sortedKeys.contains(key) else { return false }
        if let old = unsortedByKey[key], old.lastPathComponent != name {
            try? FileManager.default.removeItem(at: old)
        }
        let url = unsorted.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
        unsortedByKey[key] = url
        return true
    }
}

/// The model the farmer trained, asked about one picture at a time.
final class PlantModel {
    private let model: VNCoreMLModel

    init(url: URL) async throws {
        let compiled = try await MLModel.compileModel(at: url)
        model = try VNCoreMLModel(for: MLModel(contentsOf: compiled))
    }

    func verdict(for picture: CGImage) -> PlantLearning.Verdict? {
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFill
        try? VNImageRequestHandler(cgImage: picture).perform([request])
        guard let best = (request.results as? [VNClassificationObservation])?.first,
              let kind = PlantLearning.Kind(rawValue: best.identifier) else { return nil }
        return PlantLearning.Verdict(kind: kind, confidence: Double(best.confidence))
    }
}

/// foto-analyse leer: Create ML learns from the sorted pictures and writes planten-model.mlmodel.
func learn(_ folder: LearningFolder) throws {
    print("Plaatjes in \(folder.url.path):")
    var files: [PlantLearning.Kind: [URL]] = [:]
    for kind in PlantLearning.Kind.allCases {
        files[kind] = folder.pictures(in: folder.folder(kind))
        print("  \(kind.rawValue): \(files[kind]?.count ?? 0)")
    }
    let waiting = folder.pictures(in: folder.unsorted).count
    if waiting > 0 {
        print("  (nog \(waiting) in \(PlantLearning.unsortedFolder); die tellen niet mee)")
    }
    let (usable, messages) = PlantLearning.check(counts: files.mapValues(\.count))
    messages.forEach { print($0) }
    guard usable.count >= 2 else { exit(1) }

    print("")
    print("De AI leert \(usable.map(\.rawValue).joined(separator: ", ")). Dat duurt een paar minuten…")
    let start = Date()
    var byLabel: [String: [URL]] = [:]
    for kind in usable { byLabel[kind.rawValue] = files[kind] }
    // Seen from above a plant has no up or down: turned and mirrored pictures teach the same.
    let parameters = MLImageClassifier.ModelParameters(validation: .split(strategy: .automatic), maxIterations: 25,
                                                       augmentation: [.flip, .rotation])
    let classifier = try MLImageClassifier(trainingData: .filesByLabel(byLabel), parameters: parameters)
    print("Klaar in \(Int(Date().timeIntervalSince(start).rounded())) s.")

    let training = classifier.trainingMetrics
    if training.isValid {
        print("Plaatjes waarvan hij leerde: \(percent(1 - training.classificationError)) goed.")
    }
    let validation = classifier.validationMetrics
    if validation.isValid {
        print("Plaatjes die hij niet had gezien: \(percent(1 - validation.classificationError)) goed. Dit getal telt.")
    } else {
        print("Te weinig plaatjes om de AI te controleren met plaatjes die hij niet had gezien.")
    }

    let metadata = MLModelMetadata(author: "Veldvlucht (foto-analyse leer)",
                                   shortDescription: "Herkent per plant: \(usable.map(\.rawValue).joined(separator: ", ")).",
                                   version: ISO8601DateFormatter().string(from: Date()))
    try classifier.write(to: folder.model, metadata: metadata)
    print("Geschreven: \(folder.model.path)")
    print("De volgende analyse gebruikt deze AI vanzelf.")
}

func percent(_ fraction: Double) -> String {
    "\(Int((fraction * 100).rounded())) %"
}
