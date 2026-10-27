// foto-analyse: the photo analysis of the central system, on the Mac (docs/ARCHITECTUUR.md,
// chapter 7: the photos are too big for free cloud storage). Reads a folder with the photos of
// one flight from the drone's SD card and the photo log of that flight (Vluchten → Delen),
// finds the plants that need attention (PlantAnalysis), writes aandacht.geojson, and with
// --upload puts them in the central system, which adds them to the field map.
//
//   swift run --package-path ios/VeldvluchtKern foto-analyse <map> [--upload]
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
let upload = arguments.contains("--upload")
arguments.removeAll { $0 == "--upload" }
var maxWidth = 1200
if let i = arguments.firstIndex(of: "--breedte"), arguments.indices.contains(i + 1), let width = Int(arguments[i + 1]) {
    maxWidth = max(400, width)
    arguments.removeSubrange(i...(i + 1))
}
guard arguments.count == 1 else {
    fail("""
    Gebruik: swift run --package-path ios/VeldvluchtKern foto-analyse <map> [--upload] [--breedte 1200]
      <map>      een map met de foto's van één vlucht en het fotolog (….fotolog.json) van die vlucht
      --upload   zet de gevonden planten in het centrale systeem (inloggen met je Veldvlucht-account)
      --breedte  hoe breed de foto's worden geanalyseerd, in pixels (standaard 1200)
    """)
}
let folder = URL(fileURLWithPath: (arguments[0] as NSString).expandingTildeInPath, isDirectory: true)

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

var marks: [(LatLng, PlantAnalysis.Finding, String)] = []
var analysed = 0
var missing: [String] = []
var plantCount = 0
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
    let findings = PlantAnalysis.findings(plants)
    analysed += 1
    plantCount += plants.count
    for finding in findings {
        if let place = PlantAnalysis.position(x: finding.plant.x, y: finding.plant.y, width: image.width,
                                              height: image.height, photo: photo) {
            marks.append((place, finding, photo.file))
        }
    }
    print("  \(photo.file): \(plants.count) planten, \(findings.count) opvallend.")
}
let merged = PlantAnalysis.merge(marks)
print("")
print("\(analysed) foto's bekeken, samen \(plantCount) planten (planten in overlappende foto's tellen dubbel).")
if !missing.isEmpty {
    print("\(missing.count) foto's uit het fotolog staan niet in de map, bijvoorbeeld \(missing.prefix(3).joined(separator: ", ")).")
}
print("\(merged.count) plek(ken) met aandacht nodig.")

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
