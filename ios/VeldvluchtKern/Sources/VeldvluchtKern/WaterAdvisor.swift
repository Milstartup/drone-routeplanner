// The central system, version 0 (docs/ARCHITECTUUR.md, chapter 4): water advice per strip of
// the field, with simple rules you can check, from the soil sensors, the weather and what the
// AI of the photo analysis saw: plants that look too dry or too wet.
// For now it runs inside the app, as a part of its own: the field map only shows what this
// returns, in the format veld/resultaten. Every advice says what it is based on.
import Foundation

enum WaterAdvisor {
    /// Moisture between dry (0 %) and saturated (100 %) soil of the field, after calibration.
    static let dryBelowPercent = 35.0
    static let enoughFromPercent = 50.0
    /// Watering brings a strip back to this.
    static let targetPercent = 55.0
    /// A rough rule for the root zone: 1 % moisture is about 0.4 mm of water.
    static let mmPerPercent = 0.4
    /// Older measurements give no advice.
    static let maxAgeS = 48 * 3600.0
    /// Dry, but this much rain is coming in two days: wait.
    static let rainWaitMm = 10.0
    /// In between, and this much more rain than evaporation in two days: enough.
    static let netRainEnoughMm = 5.0
    /// Photos older than this say nothing about the water now.
    static let photoMaxAgeS = 7 * 24 * 3600.0
    /// This many plants the AI found too dry (or too wet) in one strip count for the advice.
    static let photoMinPlants = 3

    /// Strips with advice, plus the field boundary, for the field map. `attention` are the
    /// markers of the photo analysis; the caller adds them to the map itself.
    static func results(field: FieldRecord, measurements: [SensorMeasurement], weather: WeatherForecast?,
                        attention: [FieldResults.Feature] = [], now: Date) -> FieldResults {
        let strips = FieldStrips.strips(boundary: field.boundary, angleDeg: field.lineAngleDeg, widthM: field.stripWidthM)
        let latest = Dictionary(grouping: measurements, by: \.sensorId).compactMapValues { $0.max { $0.time < $1.time } }
        let water = expectedWater(weather, now: now)
        let projection = LocalProjection(origin: Geo.centroid(field.boundary.isEmpty ? [LatLng(lat: 0, lng: 0)] : field.boundary))

        var features: [FieldResults.Feature] = []
        if field.boundary.count >= 3 {
            features.append(FieldResults.Feature(type: "Feature", geometry: .polygon([closed(field.boundary)]),
                                                 properties: .init(kind: .veldgrens, name: field.name)))
        }
        for (index, strip) in strips.enumerated() {
            let photos = photoEvidence(strip, attention: attention, projection: projection, now: now)
            let advice = combine(adviseStrip(strip, field: field, latest: latest, water: water, projection: projection, now: now),
                                 photos: photos, now: now)
            features.append(FieldResults.Feature(
                type: "Feature",
                geometry: .polygon([closed(strip)]),
                properties: .init(kind: .waterzone, name: "Strook \(index + 1)", advice: advice.advice,
                                  amountMm: advice.amountMm, reason: advice.reason, confidence: advice.confidence)
            ))
        }
        return FieldResults(type: "FeatureCollection",
                            properties: .init(format: FieldResults.format, version: FieldResults.version, fieldId: field.id, createdAt: now),
                            features: features)
    }

    struct Advice: Equatable {
        var advice: WaterAdvice?
        var amountMm: Double?
        var reason: String
        var confidence: Double?
    }

    /// Rain and evaporation expected today and tomorrow (Dutch time).
    struct ExpectedWater: Equatable {
        var rainMm: Double
        var evaporationMm: Double
    }

    static func expectedWater(_ weather: WeatherForecast?, now: Date) -> ExpectedWater? {
        guard let weather else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Amsterdam")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: now)
        let days = weather.days.filter { $0.date >= today }.sorted { $0.date < $1.date }.prefix(2)
        guard !days.isEmpty else { return nil }
        return ExpectedWater(rainMm: days.map(\.precipitationMm).reduce(0, +),
                             evaporationMm: days.map { $0.evaporationMm ?? 0 }.reduce(0, +))
    }

    static func adviseStrip(_ strip: [LatLng], field: FieldRecord, latest: [String: SensorMeasurement],
                            water: ExpectedWater?, projection: LocalProjection, now: Date) -> Advice {
        let polygon = strip.map(projection.toXY)
        var near = false
        var sensors = field.sensors.filter { Geo.pointInPolygon(projection.toXY($0.location), polygon) }
        if sensors.isEmpty {
            // No sensor in the strip: the nearest one, if it lies right next to it.
            let distances = field.sensors.map { ($0, Geo.distanceToPolygonEdges(projection.toXY($0.location), polygon)) }
            if let (sensor, distance) = distances.min(by: { $0.1 < $1.1 }), distance <= field.stripWidthM {
                sensors = [sensor]
                near = true
            }
        }
        guard !sensors.isEmpty else {
            return Advice(reason: "Geen sensor in of naast deze strook. Plaats er een bij Sensoren.")
        }

        var readings: [(name: String, percent: Double, time: Date)] = []
        for sensor in sensors {
            let name = sensor.shortName(fieldId: field.id)
            guard let measurement = latest[sensor.id] else {
                return Advice(reason: "Sensor \(name) heeft nog geen meting gestuurd.")
            }
            let age = now.timeIntervalSince(measurement.time)
            if age > maxAgeS {
                return Advice(reason: "De laatste meting van sensor \(name) is van \(FieldSummary.ageText(of: measurement.time, now: now)). Voor advies is een meting van de laatste 2 dagen nodig.")
            }
            guard let percent = measurement.moisturePercent ?? sensor.calibration?.percent(raw: measurement.raw) else {
                return Advice(reason: "Sensor \(name) is nog niet geijkt (ruwe waarde \(Int(measurement.raw.rounded()))). IJk hem bij Sensoren: meet droge en natte grond van dit veld.")
            }
            readings.append((name, percent, measurement.time))
        }
        let moisture = readings.map(\.percent).reduce(0, +) / Double(readings.count)
        let newest = readings.map(\.time).max() ?? now

        let sensorText = readings.map { "\($0.name) \(Int($0.percent.rounded())) % vocht" }.joined(separator: ", ")
        var reason = "Sensor \(sensorText), gemeten \(FieldSummary.ageText(of: newest, now: now))\(near ? " (naast deze strook)" : "")."
        let rain = water?.rainMm ?? 0
        let net = rain - (water?.evaporationMm ?? 0)
        if let water {
            reason += " Verwacht vandaag en morgen \(RouteCheck.number(rounded1(water.rainMm))) mm regen en \(RouteCheck.number(rounded1(water.evaporationMm))) mm verdamping."
        } else {
            reason += " Geen weersverwachting: regen telt niet mee."
        }

        let advice: WaterAdvice
        var amount = 0.0
        let needed = max(0, (targetPercent - moisture) * mmPerPercent)
        if moisture < dryBelowPercent {
            if rain >= rainWaitMm {
                advice = .binnenkort
                amount = max(0, needed - rain)
                reason += " Regel: droger dan \(Int(dryBelowPercent)) %, maar \(Int(rainWaitMm)) mm regen of meer op komst → wacht op de regen en kijk morgen opnieuw."
            } else {
                advice = .water
                amount = needed
                reason += " Regel: droger dan \(Int(dryBelowPercent)) % en weinig regen op komst → nu water geven."
            }
        } else if moisture < enoughFromPercent {
            if net >= netRainEnoughMm {
                advice = .genoeg
                reason += " Regel: tussen \(Int(dryBelowPercent)) en \(Int(enoughFromPercent)) %, maar \(Int(netRainEnoughMm)) mm meer regen dan verdamping → genoeg."
            } else {
                advice = .binnenkort
                amount = needed
                reason += " Regel: tussen \(Int(dryBelowPercent)) en \(Int(enoughFromPercent)) % en weinig regen → binnenkort water geven."
            }
        } else {
            advice = .genoeg
            reason += " Regel: \(Int(enoughFromPercent)) % of natter → genoeg."
        }

        var confidence = near ? 0.4 : 0.6
        if now.timeIntervalSince(newest) < 12 * 3600 { confidence += 0.1 }
        if water == nil { confidence -= 0.1 }
        return Advice(advice: advice, amountMm: amount > 0 ? (amount * 2).rounded() / 2 : 0, reason: reason,
                      confidence: min(0.8, max(0.2, confidence)))
    }

    /// What the AI saw on the photos of the last week in one strip.
    struct PhotoEvidence: Equatable {
        var dry = 0
        var wet = 0
        var newest: Date?

        var looksDry: Bool { dry >= photoMinPlants && wet < photoMinPlants }
        var looksWet: Bool { wet >= photoMinPlants && dry < photoMinPlants }

        func text(now: Date) -> String? {
            guard let newest else { return nil }
            let parts = [dry >= photoMinPlants ? "\(dry) planten lijken te droog" : nil,
                         wet >= photoMinPlants ? "\(wet) planten lijken te nat" : nil].compactMap { $0 }
            guard !parts.isEmpty else { return nil }
            return "Foto's van \(FieldSummary.ageText(of: newest, now: now)): \(parts.joined(separator: " en ")) (AI)."
        }
    }

    static func photoEvidence(_ strip: [LatLng], attention: [FieldResults.Feature], projection: LocalProjection,
                              now: Date) -> PhotoEvidence {
        let polygon = strip.map(projection.toXY)
        var evidence = PhotoEvidence()
        for mark in attention {
            guard case let .point(place) = mark.geometry, let seen = mark.properties.seenAt,
                  seen <= now, now.timeIntervalSince(seen) <= photoMaxAgeS,
                  Geo.pointInPolygon(projection.toXY(place), polygon) else { continue }
            switch mark.properties.plantKind {
            case "te-droog": evidence.dry += 1
            case "te-nat": evidence.wet += 1
            default: continue
            }
            evidence.newest = max(evidence.newest ?? seen, seen)
        }
        return evidence
    }

    /// The sensor's advice, checked against the photos. Agreeing photos make it surer; photos
    /// that disagree send the farmer to look first. Without a usable sensor the photos alone
    /// give a careful advice.
    static func combine(_ sensor: Advice, photos: PhotoEvidence, now: Date) -> Advice {
        guard let text = photos.text(now: now) else { return sensor }
        var result = sensor
        result.reason += " " + text
        guard let advice = sensor.advice else {
            if photos.looksDry {
                return Advice(advice: .binnenkort, amountMm: 0,
                              reason: result.reason + " Zonder meting → binnenkort water geven. Een sensor maakt het advies zekerder.",
                              confidence: 0.3)
            }
            if photos.looksWet {
                return Advice(advice: .genoeg, amountMm: 0, reason: result.reason + " Zonder meting → geen water geven.", confidence: 0.3)
            }
            return result
        }
        var confidence = sensor.confidence ?? 0.5
        switch advice {
        case .genoeg where photos.looksDry:
            result.advice = .binnenkort
            result.reason += " De sensor meet genoeg: kijk in het veld of de sensor goed in de grond zit → binnenkort."
            confidence -= 0.1
        case .water where photos.looksWet:
            result.advice = .binnenkort
            result.reason += " De sensor meet droog: kijk eerst in het veld → binnenkort."
            confidence -= 0.1
        case .binnenkort where photos.looksWet:
            result.reason += " Dat past niet bij de sensor: kijk eerst in het veld."
            confidence -= 0.1
        case .water where photos.looksDry, .binnenkort where photos.looksDry, .genoeg where photos.looksWet:
            result.reason += " Dat past bij de sensor."
            confidence += 0.1
        default:
            break
        }
        result.confidence = min(0.8, max(0.2, confidence))
        return result
    }

    private static func rounded1(_ value: Double) -> Double { (value * 10).rounded() / 10 }

    private static func closed(_ ring: [LatLng]) -> [LatLng] {
        guard let first = ring.first, ring.last != first else { return ring }
        return ring + [first]
    }
}
