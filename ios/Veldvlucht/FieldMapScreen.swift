// Step 7 (docs/STAPPENPLAN.md): the field map, for now with the sample data from
// docs/voorbeelden. It only shows what the central system provides; the app works out no
// advice itself (docs/ARCHITECTUUR.md, chapter 5).
import Charts
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct FieldMapScreen: View {
    /// Opens the details of this zone, marker or sensor right away (for the screen tour).
    var preselected: String?
    @State private var data = SampleData.field()
    @State private var baseLayer = BaseLayer.pdok
    @State private var selected: Selected?
    @State private var importing = false
    @State private var message: String?

    private struct Selected: Identifiable {
        let id: String
    }

    var body: some View {
        NavigationStack {
            Group {
                switch data {
                case .failure(let error):
                    ScrollView {
                        Card(tint: .red) {
                            HStack(spacing: 10) {
                                IconBadge(symbol: "xmark.octagon.fill", color: .red, size: 30)
                                Text("Gegevens niet te lezen").font(.headline)
                            }
                            Text(error.message).font(.subheadline)
                            Button {
                                useSamples()
                            } label: {
                                Label("Terug naar de voorbeeldgegevens", systemImage: "arrow.uturn.backward")
                            }
                            .buttonStyle(ActionButtonStyle(color: .veld, prominent: false))
                        }
                        .padding()
                    }
                    .screenBackground()
                    .navigationTitle("Veldkaart")
                case .success(let field):
                    content(field)
                }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json, UTType(filenameExtension: "geojson") ?? .json]) { result in
                guard case .success(let url) = result else { return }
                do {
                    let kind = try SampleData.importFile(url)
                    data = SampleData.field()
                    message = "Geladen: \(kind). De rest blijft zoals het was."
                } catch {
                    message = "Niet geladen: \(error.localizedDescription)"
                }
            }
            .alert("Veldkaart", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func useSamples() {
        SampleData.removeOwnData()
        data = SampleData.field()
    }

    private func content(_ field: FieldData) -> some View {
        MapCanvas(
            shapes: shapes(field),
            pins: pins(field),
            contentID: "\(field.results.properties.fieldId)|\(field.results.properties.createdAt)",
            baseLayer: baseLayer,
            fitInsets: UIEdgeInsets(top: 380, left: 30, bottom: 130, right: 30),
            controlInsets: UIEdgeInsets(top: 320, left: 12, bottom: 100, right: 12)
        ) { id in
            selected = Selected(id: id)
        }
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .top) {
            header(field)
                .padding(.horizontal, 12)
                .padding(.top, 4)
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 8) {
                FieldLegend()
                MapAttribution(layer: baseLayer)
            }
            .padding(.bottom, 10)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if let preselected { selected = Selected(id: preselected) }
        }
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

    /// The field name, where the data comes from, and the weather, in one glass card.
    private func header(_ field: FieldData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(field.results.boundary?.properties.name ?? "Veldkaart")
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    dataMenu(field)
                }
                Spacer(minLength: 0)
                BaseLayerMenu(layer: $baseLayer, style: .inCard)
            }
            WeatherStrip(weather: field.weather)
        }
        .padding(14)
        .glass()
    }

    /// Own files or the samples. Tapping the line under the field name opens it.
    private func dataMenu(_ field: FieldData) -> some View {
        Menu {
            Section(field.ownData.isEmpty ? "Het centrale systeem bestaat nog niet" : "Eigen gegevens: \(field.ownData.joined(separator: ", "))") {
                Button {
                    importing = true
                } label: {
                    Label("Eigen bestand laden…", systemImage: "folder")
                }
                Button {
                    useSamples()
                } label: {
                    Label("Voorbeeldgegevens gebruiken", systemImage: "arrow.uturn.backward")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: field.ownData.isEmpty ? "tray.full" : "person.crop.circle")
                Text(field.ownData.isEmpty ? "Voorbeeldgegevens" : "Eigen gegevens: \(field.ownData.joined(separator: ", "))")
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.veld)
        }
        .accessibilityLabel("Gegevens")
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

    var symbol: String {
        switch self {
        case .genoeg: return "checkmark"
        case .binnenkort: return "clock.fill"
        case .water: return "drop.fill"
        }
    }

    var shortLabel: String {
        switch self {
        case .genoeg: return "genoeg"
        case .binnenkort: return "binnenkort"
        case .water: return "nu water"
        }
    }
}

private struct FieldLegend: View {
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                ForEach(WaterAdvice.allCases, id: \.self) { advice in
                    LegendItem(color: advice.color, text: advice.shortLabel)
                }
            }
            HStack(spacing: 12) {
                LegendItem(color: Color(uiColor: .systemPurple), text: "aandacht")
                LegendItem(color: Color(uiColor: .systemTeal), text: "sensor")
                Label("Tik voor details", systemImage: "hand.tap")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote.weight(.medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glass(cornerRadius: 18)
    }
}

// MARK: - Weather

private struct WeatherStrip: View {
    let weather: WeatherForecast

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let window = weather.flightWindows?.first {
                HStack(spacing: 10) {
                    IconBadge(symbol: "airplane", color: .actionGo, size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Beste vliegmoment: \(FieldSummary.windowLabel(window))")
                            .font(.subheadline.weight(.bold))
                        Text(window.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(weather.days) { DayCell(day: $0) }
                }
            }
            Text(weather.attribution)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private struct DayCell: View {
    let day: WeatherForecast.Day

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: symbol).symbolRenderingMode(.multicolor)
                Text(FieldSummary.dayLabel(day.date)).font(.caption.weight(.bold))
            }
            Text("\(Int(day.tempMinC.rounded()))–\(Int(day.tempMaxC.rounded()))° · \(dutchNumber(day.precipitationMm, digits: 1)) mm")
                .font(.caption2)
            Text("wind \(Int(day.windMaxMps.rounded())) · stoot \(Int(day.gustMaxMps.rounded())) m/s")
                .font(.caption2.weight(day.gustMaxMps >= 8 ? .bold : .medium))
                // The Mavic Mini handles wind up to 8 m/s.
                .foregroundStyle(day.gustMaxMps >= 8 ? Color.orange : Color.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        if day.precipitationMm >= 1 { return "cloud.rain.fill" }
        if day.precipitationMm > 0.1 { return "cloud.drizzle.fill" }
        return "sun.max.fill"
    }
}

// MARK: - Details

/// The top of a detail sheet: a big coloured icon, a title and a subtitle.
private struct DetailHeader: View {
    let symbol: String
    let color: Color
    let title: String
    var subtitle: String?

    var body: some View {
        Card(tint: color) {
            HStack(spacing: 14) {
                IconBadge(symbol: symbol, color: color, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.title3.weight(.bold))
                    if let subtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// A short text card with a heading, such as "Waarop gebaseerd".
private struct TextCard: View {
    let title: String
    let text: String

    var body: some View {
        Card(spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ZoneDetail: View {
    let zone: FieldResults.Feature

    var body: some View {
        ScrollView {
            VStack(spacing: Design.spacing) {
                let advice = zone.properties.advice
                DetailHeader(symbol: advice?.symbol ?? "square.dashed", color: advice?.color ?? .gray,
                             title: advice?.label ?? "Geen advies", subtitle: zone.properties.name)
                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        StatTile(title: "Hoeveelheid", symbol: "drop.fill", color: .blue,
                                 value: zone.properties.amountMm.map(RouteCheck.number) ?? "–", unit: "mm",
                                 detail: "water geven")
                        StatTile(title: "Zekerheid", symbol: "gauge.with.dots.needle.67percent", color: .purple,
                                 value: zone.properties.confidence.map { "\(Int(($0 * 100).rounded()))" } ?? "–", unit: "%") {
                            ProgressBar(fraction: zone.properties.confidence ?? 0)
                        }
                    }
                }
                if let reason = zone.properties.reason {
                    TextCard(title: "Waarop gebaseerd", text: reason)
                }
                Notice(text: "Dit is een advies. Jij beslist en controleert het in het veld.", symbol: "info.circle", color: .secondary)
                    .padding(.horizontal, 4)
            }
            .padding()
        }
        .screenBackground()
        .navigationTitle(zone.properties.name ?? "Strook")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AttentionDetail: View {
    let marker: FieldResults.Feature

    var body: some View {
        ScrollView {
            VStack(spacing: Design.spacing) {
                DetailHeader(symbol: "exclamationmark", color: .purple, title: "Aandacht nodig",
                             subtitle: marker.properties.confidence.map { "Zekerheid \(Int(($0 * 100).rounded())) %" })
                TextCard(title: "Waarom", text: marker.properties.reason ?? "Geen reden opgegeven.")
                let rows = [("Foto", marker.properties.photoFile), ("Vlucht", marker.properties.flightId)]
                    .compactMap { label, value in value.map { (label, $0) } }
                if !rows.isEmpty {
                    Card { Rows(rows: rows) }
                }
                Notice(text: "De foto zelf staat op de SD-kaart van de drone. Die komt later via het centrale systeem in de app.",
                       symbol: "info.circle", color: .secondary)
                    .padding(.horizontal, 4)
            }
            .padding()
        }
        .screenBackground()
        .navigationTitle("Aandacht nodig")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SensorDetail: View {
    let sensor: SensorSummary

    private var calibrated: Bool { sensor.history.allSatisfy { $0.moisturePercent != nil } }

    var body: some View {
        ScrollView {
            VStack(spacing: Design.spacing) {
                DetailHeader(symbol: "drop.fill", color: .teal, title: sensor.valueText,
                             subtitle: "Gemeten \(FieldSummary.ageText(of: sensor.latest.time, now: Date()))")
                Card {
                    Text(calibrated ? "Verloop (% vocht)" : "Verloop (ruwe waarde)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Chart(sensor.history) { measurement in
                        let value = self.value(measurement)
                        AreaMark(x: .value("Tijd", measurement.time), yStart: .value("Onder", chartFloor), yEnd: .value("Waarde", value))
                            .foregroundStyle(LinearGradient(colors: [Color.teal.opacity(0.35), Color.teal.opacity(0.02)],
                                                            startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("Tijd", measurement.time), y: .value("Waarde", value))
                            .foregroundStyle(Color.teal)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                        PointMark(x: .value("Tijd", measurement.time), y: .value("Waarde", value))
                            .foregroundStyle(Color.teal)
                            .symbolSize(30)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 190)
                    Text(calibrationText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Card {
                    Rows(rows: rows)
                }
            }
            .padding()
        }
        .screenBackground()
        .navigationTitle("Sensor \(sensor.shortName)")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func value(_ measurement: SensorMeasurement) -> Double {
        calibrated ? (measurement.moisturePercent ?? 0) : measurement.raw
    }

    /// A little below the lowest value, so the line is not squashed against the top.
    private var chartFloor: Double {
        let values = sensor.history.map(value)
        guard let low = values.min(), let high = values.max() else { return 0 }
        return low - max(1, (high - low) * 0.3)
    }

    private var calibrationText: String {
        if let calibration = sensor.latest.calibration {
            return "Geijkt: droog = \(RouteCheck.number(calibration.dryRaw)), nat = \(RouteCheck.number(calibration.wetRaw))."
        }
        return "Nog niet geijkt. Bij deze sensor betekent een hogere ruwe waarde meestal droger."
    }

    private var rows: [(String, String)] {
        var rows = [
            ("Laatste meting", sensor.valueText),
            ("Gemeten", sensor.latest.time.formatted(date: .abbreviated, time: .shortened)),
            ("Diepte", "\(RouteCheck.number(sensor.latest.depthCm)) cm"),
        ]
        if let volt = sensor.latest.batteryVolt {
            rows.append(("Accu", "\(dutchNumber(volt, digits: 2)) V"))
        }
        return rows
    }
}
