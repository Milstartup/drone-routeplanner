// foto-analyse: the photo analysis of the central system, on the Mac (docs/ARCHITECTUUR.md,
// chapter 7: the photos are too big for free cloud storage). Reads a folder with the photos of
// one flight from the drone's SD card and the photo log of that flight (Vluchten → Delen),
// finds the plants that need attention (PlantAnalysis), writes aandacht.geojson, and with
// --upload puts them in the central system, which adds them to the field map.
// It also cuts plants out as small pictures for the farmer to sort, and once Create ML has
// learned from those (foto-analyse leer), it asks that model about every plant (Leren.swift).
//
//   swift run --package-path ios/VeldvluchtKern foto-analyse <map> [--upload]
//   swift run --package-path ios/VeldvluchtKern foto-analyse leer
//
// It uses the app's core in debug builds (`swift run` builds those), through @testable.
@testable import VeldvluchtKern
import CoreGraphics
import Foundation
import ImageIO

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

var arguments = Array(CommandLine.arguments.dropFirst())

/// Takes a flag out of the arguments.
func flag(_ name: String) -> Bool {
    defer { arguments.removeAll { $0 == name } }
    return arguments.contains(name)
}

/// Takes an option and its value out of the arguments.
func option(_ name: String) -> String? {
    guard let i = arguments.firstIndex(of: name), arguments.indices.contains(i + 1) else { return nil }
    defer { arguments.removeSubrange(i...(i + 1)) }
    return arguments[i + 1]
}

func path(_ text: String) -> URL {
    URL(fileURLWithPath: (text as NSString).expandingTildeInPath, isDirectory: true)
}

let upload = flag("--upload")
let cutting = !flag("--niet-knippen")
let maxWidth = option("--breedte").flatMap(Int.init).map { max(400, $0) } ?? 1200
let sampleCount = option("--steekproef").flatMap(Int.init).map { max(0, $0) } ?? 5
let learningPath = option("--lesmap").map(path) ?? path("~/Documents/Veldvlucht-AI")
guard arguments.count == 1 else {
    fail("""
    Gebruik:
      swift run --package-path ios/VeldvluchtKern foto-analyse <map> [--upload] [--breedte 1200] [--lesmap <map>] [--steekproef 5] [--niet-knippen]
      swift run --package-path ios/VeldvluchtKern foto-analyse leer [--lesmap <map>]

      <map>           een map met de foto's van één vlucht en het fotolog (….fotolog.json) van die vlucht
      --upload        zet de gevonden planten in het centrale systeem (inloggen met je Veldvlucht-account)
      --breedte       hoe breed de foto's worden geanalyseerd, in pixels (standaard 1200)
      --lesmap        de map waarin de AI leert (standaard ~/Documents/Veldvlucht-AI)
      --steekproef    hoeveel gewone planten per foto als plaatje worden uitgeknipt (standaard 5)
      --niet-knippen  knip geen plaatjes uit
      leer            laat de AI leren van de plaatjes die je in de lesmap hebt gesorteerd
    """)
}
let learning: LearningFolder
do {
    learning = try LearningFolder(url: learningPath)
} catch {
    fail("Kan de lesmap \(learningPath.path) niet maken: \(error.localizedDescription)")
}
if arguments[0] == "leer" {
    do {
        try learn(learning)
        exit(0)
    } catch {
        fail("Leren lukte niet: \(error.localizedDescription)")
    }
}
let folder = path(arguments[0])

// ---- The photo log ----

let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
let logs = files.filter { $0.lastPathComponent.hasSuffix(".fotolog.json") }
guard logs.count == 1 else {
    fail(logs.isEmpty
         ? "Geen fotolog in \(folder.path). Deel het vanuit de app (Vluchten → Fotolog en logboek delen) en zet het bij de foto's."
         : "Meer dan één fotolog in \(folder.path). Zet de foto's van elke vlucht in een eigen map.")
}
let log: PhotoLog
do {
    log = try PhotoLog.read(Data(contentsOf: logs[0]))
} catch {
    fail("Het fotolog is niet te lezen: \(error.localizedDescription)")
}
let byName = Dictionary(files.map { ($0.lastPathComponent.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
print("Vlucht \(log.flightId), veld \(log.fieldId): \(log.photos.count) foto's in het fotolog.")

// ---- The photos ----

/// The photo, made smaller (fast, through ImageIO), as RGBA pixels.
func pixels(of url: URL) -> (rgba: [UInt8], width: Int, height: Int)? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: maxWidth,
        kCGImageSourceCreateThumbnailWithTransform: true,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    let width = image.width
    let height = image.height
    var rgba = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = rgba.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    return drawn ? (rgba, width, height) : nil
}

// ---- The model the farmer trained, if there is one ----

var plantModel: PlantModel?
if FileManager.default.fileExists(atPath: learning.model.path) {
    do {
        plantModel = try await PlantModel(url: learning.model)
        print("De AI uit \(learning.model.path) kijkt naar elke plant.")
    } catch {
        print("De AI in \(learning.model.path) is niet te laden (\(error.localizedDescription)); alleen de vaste regels.")
    }
}

var marks: [(LatLng, PlantAnalysis.Finding, String)] = []
/// What the model said about each plant, where it stands.
var verdicts: [(LatLng, PlantLearning.Verdict)] = []
/// The picture of each marked plant, on disk until the markers are numbered: a big field has
/// thousands, and most are the same plant in an overlapping photo.
let pictureTemp = FileManager.default.temporaryDirectory.appendingPathComponent("foto-analyse-\(UUID().uuidString)", isDirectory: true)
try? FileManager.default.createDirectory(at: pictureTemp, withIntermediateDirectories: true)
var markPictures: [String: URL] = [:]
func markKey(_ file: String, _ plant: PlantAnalysis.Plant) -> String { "\(file) \(plant.x) \(plant.y)" }
var analysed = 0
var missing: [String] = []
var plantCount = 0
var cut = 0
let present = log.photos.filter { byName[$0.file.lowercased()] != nil }
for photo in log.photos {
    guard let url = byName[photo.file.lowercased()] else {
        missing.append(photo.file)
        continue
    }
    guard let image = pixels(of: url) else {
        print("  \(photo.file): niet te lezen, overgeslagen.")
        continue
    }
    let plants = PlantAnalysis.plants(rgba: image.rgba, width: image.width, height: image.height)
    var findings = PlantAnalysis.findings(plants)
    analysed += 1
    plantCount += plants.count

    // Pictures come from the full photo: the analysed one is too small to see a leaf.
    let full = cutting || plantModel != nil ? fullImage(of: url) : nil
    let typicalArea = PlantLearning.typicalArea(plants)
    func pictureOf(_ plant: PlantAnalysis.Plant) -> CGImage? {
        guard let full,
              let (square, _) = PlantLearning.square(for: plant, typicalAreaPx: typicalArea,
                                                     scale: Double(full.width) / Double(image.width),
                                                     width: full.width, height: full.height) else { return nil }
        return picture(of: full, square)
    }

    var byModel = 0
    let started = Date()
    if let plantModel {
        // A plant partly outside the photo looks small to the model too.
        for plant in plants where !plant.touchesEdge {
            guard let place = PlantAnalysis.position(x: plant.x, y: plant.y, width: image.width, height: image.height, photo: photo),
                  PlantLearning.isNearestPhoto(place, photo: photo, photos: present),
                  let picture = pictureOf(plant), let verdict = plantModel.verdict(for: picture) else { continue }
            verdicts.append((place, verdict))
            if !findings.contains(where: { $0.plant == plant }), let finding = PlantLearning.finding(for: plant, verdict: verdict) {
                findings.append(finding)
                byModel += 1
            }
        }
    }

    for finding in findings {
        if let place = PlantAnalysis.position(x: finding.plant.x, y: finding.plant.y, width: image.width,
                                              height: image.height, photo: photo) {
            marks.append((place, finding, photo.file))
            if cutting, let picture = pictureOf(finding.plant), let data = jpeg(picture) {
                let file = pictureTemp.appendingPathComponent("\(markPictures.count).jpg")
                if (try? data.write(to: file)) != nil { markPictures[markKey(photo.file, finding.plant)] = file }
            }
        }
    }
    if cutting {
        for plant in PlantLearning.sample(plants, excluding: findings.map(\.plant), count: sampleCount,
                                          width: image.width, height: image.height) {
            let name = PlantLearning.pictureName(flightId: log.flightId, mark: nil, photoFile: photo.file, plant: plant)
            if let picture = pictureOf(plant), let data = jpeg(picture), (try? learning.save(data, name: name)) == true {
                cut += 1
            }
        }
    }
    let seconds = Int(Date().timeIntervalSince(started).rounded())
    print("  \(photo.file): \(plants.count) planten, \(findings.count) opvallend\(plantModel == nil ? "" : " (\(byModel) alleen door de AI, \(seconds) s)").")
}
// Numbered, so a marker on the field map and its picture belong together: "Plek 7".
let merged = PlantAnalysis.merge(marks).enumerated().map { index, mark -> (LatLng, PlantAnalysis.Finding, String) in
    let (place, finding, file) = mark
    if let picture = markPictures[markKey(file, finding.plant)], let data = try? Data(contentsOf: picture) {
        let name = PlantLearning.pictureName(flightId: log.flightId, mark: index + 1, photoFile: file, plant: finding.plant)
        if (try? learning.save(data, name: name)) == true { cut += 1 }
    }
    var numbered = finding
    // A marker of the rules: add what the model said about that plant, perhaps in another photo.
    if !finding.reason.hasPrefix("AI:"), let verdict = PlantLearning.verdict(near: place, in: verdicts) {
        numbered = PlantLearning.adding(verdict, to: numbered)
    }
    numbered.reason = "Plek \(index + 1): \(numbered.reason)"
    return (place, numbered, file)
}
try? FileManager.default.removeItem(at: pictureTemp)
print("")
print("\(analysed) foto's bekeken, samen \(plantCount) planten (planten in overlappende foto's tellen dubbel).")
if !missing.isEmpty {
    print("\(missing.count) foto's uit het fotolog staan niet in de map, bijvoorbeeld \(missing.prefix(3).joined(separator: ", ")).")
}
print("\(merged.count) plek(ken) met aandacht nodig.")
if cutting {
    print("\(cut) plaatje(s) van planten in \(learning.unsorted.path). Sleep ze naar de map van hun soort; daarna: foto-analyse leer.")
}

// ---- aandacht.geojson (format veld/resultaten, only markers) ----

let formatter = ISO8601DateFormatter()
let geojson: [String: Any] = [
    "type": "FeatureCollection",
    "properties": ["format": FieldResults.format, "version": FieldResults.version, "fieldId": log.fieldId,
                   "createdAt": formatter.string(from: Date())],
    "features": merged.map { place, finding, file -> [String: Any] in
        ["type": "Feature",
         "geometry": ["type": "Point", "coordinates": [place.lng, place.lat]],
         "properties": ["kind": "aandacht", "reason": finding.reason, "photoFile": file, "flightId": log.flightId,
                        "confidence": (finding.confidence * 100).rounded() / 100]]
    },
]
let output = folder.appendingPathComponent("aandacht.geojson")
do {
    try JSONSerialization.data(withJSONObject: geojson, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
    print("Geschreven: \(output.path)")
} catch {
    fail("Kan \(output.path) niet schrijven: \(error.localizedDescription)")
}

guard upload else {
    print("Met --upload zet je de plekken in het centrale systeem; dan staan ze op de veldkaart in de app.")
    exit(0)
}

// ---- Upload to the central system ----

/// The cloud project from ios/Config/Lokaal.xcconfig, like the app.
func cloudConfig() -> CloudConfig? {
    let file = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Config/Lokaal.xcconfig")
    guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
    var values: [String: String] = [:]
    for line in text.split(separator: "\n") where !line.hasPrefix("//") {
        let pair = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        if pair.count == 2 { values[pair[0]] = pair[1] }
    }
    let config = CloudConfig(projectRef: values["SUPABASE_PROJECT"] ?? "", key: values["SUPABASE_KEY"] ?? "")
    return config.isUsable ? config : nil
}

guard let config = cloudConfig() else {
    fail("De cloud is nog niet ingesteld in ios/Config/Lokaal.xcconfig (zie centraal/README.md).")
}
print("")
print("Inloggen bij het centrale systeem (je Veldvlucht-account).")
print("E-mailadres: ", terminator: "")
guard let email = readLine()?.trimmingCharacters(in: .whitespaces), !email.isEmpty else { fail("Geen e-mailadres.") }
guard let typed = getpass("Wachtwoord: ") else { fail("Geen wachtwoord.") }
let password = String(cString: typed)

let api = CloudAPI(config: config, session: nil) { request in
    let (data, response) = try await URLSession.shared.data(for: request)
    return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
}
do {
    let session = try await api.signIn(email: email, password: password)
    guard let field = try await api.fields().first(where: { $0.veldId == log.fieldId && $0.eigenaar == session.userId }) else {
        fail("Het veld \(log.fieldId) staat niet in jouw account. Open de app, log in en synchroniseer eerst.")
    }
    let rows = merged.map { place, finding, file in
        CloudAPI.AttentionMark(position: place, reason: finding.reason, photo: file, confidence: (finding.confidence * 100).rounded() / 100)
    }
    try await api.saveAttention(field: field.id, flightId: log.flightId, marks: rows)
    try? await api.recalculate(field: field.id)
    print("Klaar: \(rows.count) plek(ken) staan in het centrale systeem bij \(field.naam). Synchroniseer de app om ze te zien.")
    await api.signOut()
} catch {
    fail("Niet gelukt: \(error.localizedDescription)")
}
