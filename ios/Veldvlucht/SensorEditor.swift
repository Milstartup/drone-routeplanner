// Placing the soil sensors in a field drawn in the app, giving each its name for the sensor
// box, and calibrating it: the raw value in dry and in saturated soil of the field.
import SwiftUI
import UIKit

struct SensorEditorView: View {
    let original: FieldRecord
    @ObservedObject var fields: FieldStore
    @ObservedObject var receiver: SensorReceiver
    @Environment(\.dismiss) private var dismiss

    /// One sensor while editing: the calibration can be half filled in.
    struct Draft: Identifiable, Equatable {
        var id: String
        var location: LatLng
        var depthCm: Double
        var dryRaw: Double?
        var wetRaw: Double?
    }

    @State private var drafts: [Draft]
    @State private var latest: [String: SensorMeasurement] = [:]
    @State private var baseLayer = BaseLayer.pdok
    @State private var saveError: String?

    init(field: FieldRecord, fields: FieldStore, receiver: SensorReceiver) {
        original = field
        self.fields = fields
        self.receiver = receiver
        _drafts = State(initialValue: field.sensors.map {
            Draft(id: $0.id, location: $0.location, depthCm: $0.depthCm, dryRaw: $0.calibration?.dryRaw, wetRaw: $0.calibration?.wetRaw)
        })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                FieldEditMap(
                    mode: .sensors,
                    corners: [],
                    home: nil,
                    sensors: drafts.map { EditPoint(title: shortName($0.id), location: $0.location) },
                    selectedCorner: nil,
                    shapes: shapes,
                    dots: [],
                    baseLayer: baseLayer,
                    fitID: original.id,
                    recenter: 0,
                    fitInsets: UIEdgeInsets(top: 40, left: 40, bottom: 40, right: 40),
                    controlInsets: UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12),
                    onTap: { _ in },
                    onSelectCorner: { _ in },
                    onMoveCorner: { _, _ in },
                    onMoveHome: { _ in },
                    onMoveSensor: { index, point in
                        if drafts.indices.contains(index) { drafts[index].location = point }
                    },
                    onUserLocation: { _ in }
                )
                .frame(height: 290)
                .overlay(alignment: .bottomLeading) { MapAttribution(layer: baseLayer).padding(8) }

                ScrollView {
                    VStack(spacing: Design.spacing) {
                        countCard
                        receiverCard
                        ForEach($drafts) { $draft in
                            sensorCard($draft)
                        }
                    }
                    .padding()
                }
                .screenBackground()
            }
            .navigationTitle("Sensoren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuleren") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bewaren", action: save).bold()
                }
            }
            .onAppear(perform: readLatest)
            .onChange(of: receiver.uploads) { _, _ in readLatest() }
            .alert("Niet bewaard", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private func shortName(_ id: String) -> String {
        id.hasPrefix(original.id + "-") ? String(id.dropFirst(original.id.count + 1)) : id
    }

    private func readLatest() {
        latest = Dictionary(grouping: SensorStore.read(fieldId: original.id), by: \.sensorId)
            .compactMapValues { $0.max { $0.time < $1.time } }
    }

    /// The field and its watering strips, so you can put a sensor in each strip.
    private var shapes: [MapShape] {
        var shapes = FieldStrips.strips(boundary: original.boundary, angleDeg: original.lineAngleDeg, widthM: original.stripWidthM)
            .enumerated().map {
                MapShape(id: "strook-\($0.offset)", kind: .polygon, points: $0.element,
                         stroke: UIColor.white.withAlphaComponent(0.5), fill: UIColor.white.withAlphaComponent(0.06), lineWidth: 1)
            }
        shapes.append(MapShape(id: "veldgrens", kind: .polygon, points: original.boundary, stroke: .white, lineWidth: 3))
        return shapes
    }

    /// New places for `count` sensors; names, depths and calibrations stay with their number.
    private func place(_ count: Int) {
        let places = FieldStrips.sensorPlaces(boundary: original.boundary, angleDeg: original.lineAngleDeg, count: count)
        drafts = places.enumerated().map { index, place in
            let id = "\(original.id)-s\(index + 1)"
            var draft = drafts.first { $0.id == id } ?? Draft(id: id, location: place, depthCm: 15)
            draft.location = place
            return draft
        }
    }

    private func save() {
        var field = original
        field.sensors = drafts.map { draft in
            let calibration = draft.dryRaw.flatMap { dry in draft.wetRaw.map { SensorMeasurement.Calibration(dryRaw: dry, wetRaw: $0) } }
            return FieldSensor(id: draft.id, location: draft.location, depthCm: draft.depthCm, calibration: calibration)
        }
        do {
            try fields.save(field)
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    // MARK: Cards

    private var countCard: some View {
        Card {
            Stepper(value: Binding(get: { drafts.count }, set: place), in: 0...12) {
                HStack(spacing: 10) {
                    IconBadge(symbol: "drop.fill", color: .teal, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Aantal sensoren").font(.headline)
                        Text(drafts.isEmpty ? "Nog geen" : "\(drafts.count) in dit veld").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            Text("De app verdeelt ze over het veld, dwars op de rijrichting van de tractor. Voor advies per strook is in elke strook een sensor het beste. Houd een sensor vast en sleep hem naar de echte plek.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var receiverCard: some View {
        Card(tint: receiver.running ? .green : .orange) {
            HStack(spacing: 10) {
                IconBadge(symbol: "antenna.radiowaves.left.and.right", color: receiver.running ? .green : .orange, size: 30)
                Text(receiver.running ? "Ontvanger staat aan" : "Ontvanger staat uit").font(.headline)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Zet op de iPhone **Persoonlijke hotspot** aan, met **Maximaliseer compatibiliteit**.")
                Text("2. Zet in het kastje de naam en het wachtwoord van de hotspot, en de naam van de sensor hieronder.")
                Text("3. Houd Veldvlucht open. Het kastje stuurt zijn metingen zodra het de hotspot ziet.")
            }
            .font(.footnote)
            if let event = receiver.lastEvent {
                Notice(text: "\(event.time.formatted(date: .omitted, time: .shortened)): \(event.text)",
                       symbol: event.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                       color: event.ok ? .green : .orange)
            }
        }
    }

    private func sensorCard(_ draft: Binding<Draft>) -> some View {
        let d = draft.wrappedValue
        let measurement = latest[d.id]
        return Card {
            HStack(spacing: 10) {
                IconBadge(symbol: "drop.fill", color: .teal, size: 30)
                Text("Sensor \(shortName(d.id))").font(.headline)
                Spacer()
                if let measurement {
                    Pill(text: FieldSummary.ageText(of: measurement.time, now: Date()), symbol: "clock", color: .teal)
                } else {
                    Pill(text: "Nog geen meting", color: .secondary)
                }
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Naam voor in het kastje").font(.footnote).foregroundStyle(.secondary)
                    Text(d.id).font(.body.monospaced().weight(.semibold)).textSelection(.enabled)
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = d.id
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel("Kopieer de naam")
            }
            Stepper(value: draft.depthCm, in: 5...60, step: 5) {
                Row(label: "Diepte", value: "\(RouteCheck.number(d.depthCm)) cm")
            }
            Divider()
            Text("IJken").font(.subheadline.weight(.semibold))
            Text("Steek de sensor in een bak droge grond van dit veld en wacht op een meting: kies dan *Laatste = droog*. Doe hetzelfde met kletsnatte grond voor *nat*.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                rawField("Droog", value: draft.dryRaw)
                rawField("Nat", value: draft.wetRaw)
            }
            if let measurement {
                HStack(spacing: 8) {
                    Button("Laatste = droog") { draft.wrappedValue.dryRaw = measurement.raw }
                        .buttonStyle(ActionButtonStyle(color: .orange, prominent: false))
                    Button("Laatste = nat") { draft.wrappedValue.wetRaw = measurement.raw }
                        .buttonStyle(ActionButtonStyle(color: .blue, prominent: false))
                }
                Text(latestText(measurement, d))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func rawField(_ label: String, value: Binding<Double?>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextField("ruwe waarde", value: value, format: .number.grouping(.never))
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func latestText(_ m: SensorMeasurement, _ d: Draft) -> String {
        var text = "Laatste meting: ruw \(Int(m.raw.rounded()))"
        if let dry = d.dryRaw, let wet = d.wetRaw,
           let percent = SensorMeasurement.Calibration(dryRaw: dry, wetRaw: wet).percent(raw: m.raw) {
            text += " = \(Int(percent.rounded())) % vocht"
        }
        if let volt = m.batteryVolt { text += " · accu \(dutchNumber(volt, digits: 2)) V" }
        return text + "."
    }
}
