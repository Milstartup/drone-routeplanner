// Step 7 (docs/STAPPENPLAN.md): the field map, for now with the sample data from
// docs/voorbeelden. It only shows what the central system provides; the app works out no
// advice itself (docs/ARCHITECTUUR.md, chapter 5).
import Charts
import SwiftUI
import UIKit

struct FieldMapScreen: View {
    @State private var data = SampleData.field()
    @State private var baseLayer = BaseLayer.pdok
    @State private var selected: Selected?

    private struct Selected: Identifiable {
        let id: String
    }

    var body: some View {
        NavigationStack {
            switch data {
            case .failure(let error):
                Label(error.message, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                    .padding()
                    .navigationTitle("Veldkaart")
            case .success(let field):
                content(field)
            }
        }
    }

    private func content(_ field: FieldData) -> some View {
        VStack(spacing: 0) {
            WeatherBar(weather: field.weather)
            MapCanvas(
                shapes: shapes(field),
                pins: pins(field),
                contentID: "\(field.results.properties.fieldId)|\(field.results.properties.createdAt)",
                baseLayer: baseLayer
            ) { id in
                selected = Selected(id: id)
            }
            .overlay(alignment: .top) {
                Text("Voorbeeldgegevens: het centrale systeem bestaat nog niet")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.top, 8)
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 6) {
                    FieldLegend()
                    MapAttribution(layer: baseLayer)
                }
                .padding(.bottom, 8)
            }
        }
        .navigationTitle(field.results.boundary?.properties.name ?? "Veldkaart")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { BaseLayerMenu(layer: $baseLayer) }
        .sheet(item: $selected) { selected in
            NavigationStack {
                detail(selected.id, field)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Klaar") { self.selected = nil }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }

    @ViewBuilder
    private func detail(_ id: String, _ field: FieldData) -> some View {
        if let zone = feature(id, prefix: "zone-", in: field.results.waterZones) {
            ZoneDetail(zone: zone)
        } else if let marker = feature(id, prefix: "aandacht-", in: field.results.attention) {
            AttentionDetail(marker: marker)
        } else if let sensor = field.sensors.first(where: { "sensor-\($0.sensorId)" == id }) {
            SensorDetail(sensor: sensor)
        } else {
            Text("Niets gevonden.")
        }
    }

    private func feature(_ id: String, prefix: String, in features: [FieldResults.Feature]) -> FieldResults.Feature? {
        guard id.hasPrefix(prefix), let index = Int(id.dropFirst(prefix.count)), features.indices.contains(index) else {
            return nil
        }
        return features[index]
    }

    private func shapes(_ field: FieldData) -> [MapShape] {
        var shapes = field.results.waterZones.enumerated().map { index, zone -> MapShape in
            let color = (zone.properties.advice ?? .genoeg).uiColor
            return MapShape(
                id: "zone-\(index)",
                kind: .polygon,
                points: zone.geometry.outerRing,
                stroke: color.withAlphaComponent(0.9),
                fill: color.withAlphaComponent(0.35),
                lineWidth: 1,
                tappable: true
            )
        }
        if let boundary = field.results.boundary {
            shapes.append(MapShape(id: "veldgrens", kind: .polygon, points: boundary.geometry.outerRing, stroke: .white, lineWidth: 3))
        }
        return shapes
    }

    private func pins(_ field: FieldData) -> [MapPin] {
        let markers = field.results.attention.enumerated().compactMap { index, marker -> MapPin? in
            guard case .point(let p) = marker.geometry else { return nil }
            return MapPin(id: "aandacht-\(index)", coordinate: p, title: nil, style: .marker(symbol: "exclamationmark", color: .systemPurple))
        }
        let sensors = field.sensors.map {
            MapPin(id: "sensor-\($0.sensorId)", coordinate: $0.location, title: "\($0.shortName) · \($0.valueText)", style: .marker(symbol: "drop.fill", color: .systemTeal))
        }
        return markers + sensors
    }
}

extension WaterAdvice {
    var uiColor: UIColor {
        switch self {
        case .genoeg: return .systemBlue
        case .binnenkort: return .systemYellow
        case .water: return .systemRed
        }
    }

    var color: Color { Color(uiColor: uiColor) }
}

private struct FieldLegend: View {
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 10) {
                ForEach(WaterAdvice.allCases, id: \.self) { advice in
                    LegendItem(color: advice.color, text: shortLabel(advice))
                }
            }
            HStack(spacing: 10) {
                LegendItem(color: Color(uiColor: .systemPurple), text: "aandacht")
                LegendItem(color: Color(uiColor: .systemTeal), text: "sensor")
                Text("Tik voor details").foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func shortLabel(_ advice: WaterAdvice) -> String {
        switch advice {
        case .genoeg: return "genoeg"
        case .binnenkort: return "binnenkort"
        case .water: return "nu water"
        }
    }
}

// MARK: - Weather

private struct WeatherBar: View {
    let weather: WeatherForecast

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let window = weather.flightWindows?.first {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Beste vliegmoment: \(FieldSummary.windowLabel(window))").font(.subheadline.bold())
                        Text(window.reason).font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "airplane").foregroundStyle(.green)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(weather.days) { DayCell(day: $0) }
                }
            }
            Text(weather.attribution).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
    }
}

private struct DayCell: View {
    let day: WeatherForecast.Day

    var body: some View {
        VStack(spacing: 2) {
            Text(FieldSummary.dayLabel(day.date)).font(.caption.bold())
            Image(systemName: symbol).symbolRenderingMode(.multicolor)
            Text(String(format: "%.1f mm", day.precipitationMm).replacingOccurrences(of: ".", with: ","))
                .font(.caption)
            Text("\(Int(day.tempMinC.rounded()))–\(Int(day.tempMaxC.rounded())) °C").font(.caption2)
            Text("wind \(Int(day.windMaxMps.rounded())) · stoot \(Int(day.gustMaxMps.rounded())) m/s")
                .font(.caption2)
                // The Mavic Mini handles wind up to 8 m/s.
                .foregroundStyle(day.gustMaxMps >= 8 ? .orange : .secondary)
        }
        .padding(6)
        .frame(minWidth: 96)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 8))
    }

    private var symbol: String {
        if day.precipitationMm >= 1 { return "cloud.rain.fill" }
        if day.precipitationMm > 0.1 { return "cloud.drizzle.fill" }
        return "sun.max.fill"
    }
}

// MARK: - Details

private struct ZoneDetail: View {
    let zone: FieldResults.Feature

    var body: some View {
        List {
            Section {
                if let advice = zone.properties.advice {
                    Label {
                        Text(advice.label).bold()
                    } icon: {
                        Circle().fill(advice.color).frame(width: 14, height: 14)
                    }
                }
                if let amount = zone.properties.amountMm {
                    Row(label: "Hoeveelheid", value: "\(RouteCheck.number(amount)) mm")
                }
                if let confidence = zone.properties.confidence {
                    Row(label: "Zekerheid", value: "\(Int((confidence * 100).rounded())) %")
                }
            }
            if let reason = zone.properties.reason {
                Section("Waarop gebaseerd") {
                    Text(reason)
                }
            }
            Section {
                Text("Dit is een advies. Jij beslist en controleert het in het veld.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(zone.properties.name ?? "Strook")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AttentionDetail: View {
    let marker: FieldResults.Feature

    var body: some View {
        List {
            Section("Waarom") {
                Text(marker.properties.reason ?? "Geen reden opgegeven.")
            }
            Section {
                if let confidence = marker.properties.confidence {
                    Row(label: "Zekerheid", value: "\(Int((confidence * 100).rounded())) %")
                }
                if let photo = marker.properties.photoFile {
                    Row(label: "Foto", value: photo)
                }
                if let flight = marker.properties.flightId {
                    Row(label: "Vlucht", value: flight)
                }
            } footer: {
                Text("De foto zelf staat op de SD-kaart van de drone. Die komt later via het centrale systeem in de app.")
            }
        }
        .navigationTitle("Aandacht nodig")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SensorDetail: View {
    let sensor: SensorSummary

    private var calibrated: Bool { sensor.history.allSatisfy { $0.moisturePercent != nil } }

    var body: some View {
        List {
            Section {
                Row(label: "Laatste meting", value: sensor.valueText)
                Row(label: "Gemeten", value: "\(sensor.latest.time.formatted(date: .abbreviated, time: .shortened)) (\(FieldSummary.ageText(of: sensor.latest.time, now: Date())))")
                Row(label: "Diepte", value: "\(RouteCheck.number(sensor.latest.depthCm)) cm")
                if let volt = sensor.latest.batteryVolt {
                    Row(label: "Accu", value: String(format: "%.2f V", volt))
                }
            }
            Section {
                Chart(sensor.history) { measurement in
                    let value = calibrated ? (measurement.moisturePercent ?? 0) : measurement.raw
                    LineMark(x: .value("Tijd", measurement.time), y: .value("Waarde", value))
                    PointMark(x: .value("Tijd", measurement.time), y: .value("Waarde", value))
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 180)
            } header: {
                Text(calibrated ? "Verloop (% vocht)" : "Verloop (ruwe waarde)")
            } footer: {
                if let calibration = sensor.latest.calibration {
                    Text("Geijkt: droog = \(RouteCheck.number(calibration.dryRaw)), nat = \(RouteCheck.number(calibration.wetRaw)).")
                } else {
                    Text("Nog niet geijkt. Bij deze sensor betekent een hogere ruwe waarde meestal droger.")
                }
            }
        }
        .navigationTitle("Sensor \(sensor.shortName)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
