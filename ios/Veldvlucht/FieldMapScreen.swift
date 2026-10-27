// Step 7 (docs/STAPPENPLAN.md): the field map. For a field drawn in the app it shows the
// sensors, the weather and the water advice per strip of the central system (WaterAdvisor,
// version 0); otherwise the sample data from docs/voorbeelden. The screen itself works out
// no advice (docs/ARCHITECTUUR.md, chapter 5).
import Charts
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct FieldMapScreen: View {
    @ObservedObject var fields: FieldStore
    @ObservedObject var receiver: SensorReceiver
    @ObservedObject var cloud: CloudStore
    @ObservedObject var weather: WeatherService
    /// Opens the details of this zone, marker or sensor right away (for the screen tour).
    var preselected: String?
    @State private var data: Result<FieldData, FileReadError> = SampleData.field()
    @State private var baseLayer = BaseLayer.pdok
    @State private var selected: Selected?
    @State private var importing = false
    @State private var editingSensors: FieldRecord?
    @State private var sharing: FieldRecord?
    @State private var showAccount = false
    @State private var message: String?
    @State private var notify = FlightNotifier.enabled

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
                                useOwnAdviceOrSamples()
                            } label: {
                                Label(fields.selection == nil ? "Terug naar de voorbeeldgegevens" : "Terug naar het berekende advies",
                                      systemImage: "arrow.uturn.backward")
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
            .onAppear(perform: reload)
            .onChange(of: fields.selectedId) { _, _ in reload() }
            .onChange(of: fields.fields) { _, _ in reload() }
            .onChange(of: receiver.uploads) { _, _ in reload() }
            .onChange(of: weather.updates) { _, _ in reload() }
            .onChange(of: cloud.updates) { _, _ in reload() }
            .task(id: fields.selectedId) {
                // Shared fields get their weather from the cloud.
                if let field = fields.selected { await weather.refresh(field) }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json, UTType(filenameExtension: "geojson") ?? .json]) { result in
                guard case .success(let url) = result else { return }
                do {
                    let kind = try SampleData.importFile(url, fieldId: fields.selected?.id)
                    reload()
                    message = "Geladen: \(kind). De rest blijft zoals het was."
                } catch {
                    message = "Niet geladen: \(error.localizedDescription)"
                }
            }
            .fullScreenCover(item: $editingSensors) { field in
                SensorEditorView(field: field, fields: fields, receiver: receiver, cloud: cloud)
            }
            .sheet(item: $sharing) { field in
                ShareView(field: field, cloud: cloud)
            }
            .sheet(isPresented: $showAccount) {
                AccountView(cloud: cloud)
            }
            .alert("Veldkaart", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func reload() {
        if let selection = fields.selection {
            data = SampleData.field(selection.record, key: selection.key)
        } else {
            data = SampleData.field()
        }
    }

    private func useOwnAdviceOrSamples() {
        if let selection = fields.selection {
            SampleData.removeOwnResults(fieldId: selection.key)
        } else {
            SampleData.removeOwnData()
        }
        reload()
    }

    private func content(_ field: FieldData) -> some View {
        MapCanvas(
            shapes: shapes(field),
            pins: pins(field),
            contentID: "\(field.fieldId ?? "voorbeeld")|\(field.results.properties.createdAt)|\(field.waitingSensors.count)|\(field.sensors.count)",
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
                FieldLegend(showsNoAdvice: field.results.waterZones.contains { $0.properties.advice == nil })
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
                    Text(field.name)
                        .font(.title3.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    dataMenu(field)
                }
                Spacer(minLength: 0)
                BaseLayerMenu(layer: $baseLayer, style: .inCard)
            }
            if let forecast = field.weather {
                WeatherStrip(weather: forecast)
            } else if weather.loading {
                Label("Weer ophalen…", systemImage: "cloud.sun")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let problem = weather.problem, field.fieldId != nil {
                Notice(text: problem, symbol: "wifi.exclamationmark", color: .orange)
            }
        }
        .padding(14)
        .glass()
    }

    private var sourceText: String {
        guard case .success(let field) = data else { return "" }
        if field.fieldId == nil {
            return field.ownData.isEmpty ? "Voorbeeldgegevens" : "Eigen gegevens: \(field.ownData.joined(separator: ", "))"
        }
        if field.shared { return "Gedeeld met je" }
        if !field.ownData.isEmpty { return "Eigen resultaten-bestand" }
        let count = field.sensors.count + field.waitingSensors.count
        return count == 0 ? "Nog geen sensoren" : (count == 1 ? "1 sensor" : "\(count) sensoren")
    }

    /// Which field, own files, sensors and the notification. Tap the line under the name.
    private func dataMenu(_ field: FieldData) -> some View {
        Menu {
            Section("Welk veld") {
                ForEach(fields.fields) { record in
                    Button {
                        fields.selectedId = record.id
                    } label: {
                        if record.id == fields.selectedId {
                            Label(record.name, systemImage: "checkmark")
                        } else {
                            Text(record.name)
                        }
                    }
                }
                Button {
                    fields.selectedId = nil
                } label: {
                    if fields.selectedId == nil {
                        Label("Voorbeeldveld", systemImage: "checkmark")
                    } else {
                        Text("Voorbeeldveld")
                    }
                }
            }
            if !fields.shared.isEmpty {
                Section("Gedeeld met mij") {
                    ForEach(fields.shared) { other in
                        Button {
                            fields.selectedId = other.id
                        } label: {
                            if other.id == fields.selectedId {
                                Label(other.record.name, systemImage: "checkmark")
                            } else {
                                Text(other.record.name)
                            }
                        }
                    }
                }
            }
            if let record = fields.selected {
                Section {
                    Button {
                        editingSensors = record
                    } label: {
                        Label("Sensoren plaatsen en ijken…", systemImage: "drop")
                    }
                    Button {
                        sharing = record
                    } label: {
                        Label("Delen met anderen…", systemImage: "person.2")
                    }
                    if cloud.isLoggedIn {
                        Button {
                            Task { await cloud.recalculate(record.id) }
                        } label: {
                            Label("Advies nu laten berekenen", systemImage: "function")
                        }
                    }
                    Button {
                        Task { await weather.refresh(record, force: true) }
                    } label: {
                        Label("Weer vernieuwen", systemImage: "arrow.clockwise")
                    }
                }
            }
            Section {
                Button {
                    showAccount = true
                } label: {
                    Label(cloud.isLoggedIn ? "Account en cloud…" : "Inloggen bij de cloud…", systemImage: "icloud")
                }
                if cloud.isLoggedIn {
                    Button {
                        Task { await cloud.sync() }
                    } label: {
                        Label("Nu synchroniseren", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
            Section {
                Toggle(isOn: Binding(get: { notify }, set: { on in
                    Task {
                        if on {
                            notify = await FlightNotifier.enable()
                            if let record = fields.selected { await weather.refresh(record, force: true) }
                            if !notify { message = "Meldingen staan uit voor Veldvlucht. Zet ze aan in Instellingen › Meldingen." }
                        } else {
                            FlightNotifier.disable()
                            notify = false
                        }
                    }
                })) {
                    Label("Melding bij goed vliegweer", systemImage: "bell")
                }
            }
            if !field.shared {
            Section("Eigen bestanden") {
                Button {
                    importing = true
                } label: {
                    Label("Eigen bestand laden…", systemImage: "folder")
                }
                if fields.selected == nil || !field.ownData.isEmpty {
                    Button {
                        useOwnAdviceOrSamples()
                    } label: {
                        Label(fields.selected == nil ? "Voorbeeldgegevens gebruiken" : "Berekend advies gebruiken", systemImage: "arrow.uturn.backward")
                    }
                }
            }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: field.fieldId == nil ? "tray.full" : "square.dashed.inset.filled")
                Text(sourceText)
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
            ZoneDetail(zone: zone, source: field.adviceSource)
        } else if let marker = feature(id, prefix: "aandacht-", in: field.results.attention) {
            AttentionDetail(marker: marker)
        } else if let sensor = field.sensors.first(where: { "sensor-\($0.sensorId)" == id }) {
            SensorDetail(sensor: sensor)
        } else if let sensor = field.waitingSensors.first(where: { "wacht-\($0.id)" == id }), let fieldId = field.fieldId {
            WaitingSensorDetail(sensor: sensor, fieldId: fieldId, receiving: receiver.running) {
                self.selected = nil
                editingSensors = fields.field(fieldId)
            }
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
            let color = zone.properties.advice?.uiColor ?? .systemGray
            return MapShape(
                id: "zone-\(index)",
                kind: .polygon,
                points: zone.geometry.outerRing,
                stroke: color.withAlphaComponent(0.9),
                fill: color.withAlphaComponent(zone.properties.advice == nil ? 0.2 : 0.35),
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
        let waiting = field.waitingSensors.map {
            MapPin(id: "wacht-\($0.id)", coordinate: $0.location, title: "\($0.shortName(fieldId: field.fieldId ?? "")) · wacht",
                   style: .marker(symbol: "drop", color: .systemGray))
        }
        return markers + sensors + waiting
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
    var showsNoAdvice = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                ForEach(WaterAdvice.allCases, id: \.self) { advice in
                    LegendItem(color: advice.color, text: advice.shortLabel)
                }
            }
            HStack(spacing: 12) {
                if showsNoAdvice {
                    LegendItem(color: Color(uiColor: .systemGray), text: "geen advies")
                }
                LegendItem(color: Color(uiColor: .systemPurple), text: "aandacht")
                LegendItem(color: Color(uiColor: .systemTeal), text: "sensor")
                if !showsNoAdvice {
                    Label("Tik voor details", systemImage: "hand.tap")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.footnote.weight(.medium))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glass(cornerRadius: 18)
        .padding(.horizontal, 12)
    }
}

/// A sensor that is placed but has not sent anything yet.
private struct WaitingSensorDetail: View {
    let sensor: FieldSensor
    let fieldId: String
    let receiving: Bool
    var openSensors: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Design.spacing) {
                Card(tint: .gray) {
                    HStack(spacing: 14) {
                        IconBadge(symbol: "drop", color: .gray, size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Nog geen meting").font(.title3.weight(.bold))
                            Text("Sensor \(sensor.shortName(fieldId: fieldId))").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                Card(spacing: 6) {
                    Text("Naam voor in het kastje").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    Text(sensor.id).font(.body.monospaced().weight(.semibold)).textSelection(.enabled)
                    Text("Het kastje stuurt zijn metingen naar deze iPhone zodra het de hotspot ziet en Veldvlucht open is. \(receiving ? "De ontvanger staat aan." : "De ontvanger staat nu uit.")")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button(action: openSensors) {
                    Label("Sensoren plaatsen en ijken", systemImage: "drop")
                }
                .buttonStyle(ActionButtonStyle(color: .teal))
            }
            .padding()
        }
        .screenBackground()
        .navigationTitle("Sensor")
        .navigationBarTitleDisplayMode(.inline)
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
    var source = FieldData.AdviceSource.file

    var body: some View {
        ScrollView {
            VStack(spacing: Design.spacing) {
                let advice = zone.properties.advice
                DetailHeader(symbol: advice?.symbol ?? "questionmark", color: advice?.color ?? .gray,
                             title: advice?.label ?? "Nog geen advies", subtitle: zone.properties.name)
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
                Notice(text: noteText,
                       symbol: "info.circle", color: .secondary)
                    .padding(.horizontal, 4)
            }
            .padding()
        }
        .screenBackground()
        .navigationTitle(zone.properties.name ?? "Strook")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension ZoneDetail {
    var noteText: String {
        switch source {
        case .cloud: return "Berekend door het centrale systeem in de cloud, met eenvoudige regels (versie 0), zonder AI. Dit is een advies: jij beslist en controleert het in het veld."
        case .app: return "Berekend in de app met eenvoudige regels (centraal systeem, versie 0), zonder AI. Dit is een advies: jij beslist en controleert het in het veld."
        case .file: return "Dit is een advies. Jij beslist en controleert het in het veld."
        }
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
