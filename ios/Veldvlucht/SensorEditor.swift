// Placing the soil sensors in a field drawn in the app, giving each its name for the sensor
// box, pairing the box (it gets its settings over its own WiFi network), and calibrating it:
// the raw value in dry and in saturated soil of the field.
import SwiftUI
import UIKit

struct SensorEditorView: View {
    let original: FieldRecord
    @ObservedObject var fields: FieldStore
    @ObservedObject var receiver: SensorReceiver
    @ObservedObject var cloud: CloudStore
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
    @State private var saving = false
    /// The key of each sensor box, from the central system.
    @State private var keys: [String: String] = [:]
    /// The sensor whose box is being paired.
    @State private var pairing: Draft?

    init(field: FieldRecord, fields: FieldStore, receiver: SensorReceiver, cloud: CloudStore) {
        original = field
        self.fields = fields
        self.receiver = receiver
        self.cloud = cloud
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
                    if saving {
                        ProgressView()
                    } else {
                        Button("Bewaren", action: save).bold()
                    }
                }
            }
            .onAppear {
                readLatest()
                keys = cloud.link(original.id).keys
            }
            .onChange(of: receiver.uploads) { _, _ in readLatest() }
            .sheet(item: $pairing) { draft in
                // The cloud only with the sensor's key: that comes after Bewaren, when logged in.
                let key = keys[draft.id]
                PairBoxView(sensorId: draft.id, depthCm: Int(draft.depthCm.rounded()), sensorKey: key,
                            cloud: cloud.isLoggedIn && key != nil ? cloud.config : nil)
            }
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
        } catch {
            saveError = error.localizedDescription
            return
        }
        // In the cloud too, so every sensor gets its key for the box.
        saving = true
        Task {
            await cloud.save(field)
            saving = false
            dismiss()
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
                Text("2. Koppel het kastje met **Kastje koppelen** bij de sensor hieronder.")
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
            if let key = keys[d.id] {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sleutel voor het kastje (SENSOR_SLEUTEL)").font(.footnote).foregroundStyle(.secondary)
                        Text(key).font(.footnote.monospaced()).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                    }
                    Spacer()
                    Button {
                        UIPasteboard.general.string = key
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .accessibilityLabel("Kopieer de sleutel")
                }
            } else if cloud.isLoggedIn {
                Text("De sleutel voor het kastje verschijnt hier na Bewaren.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button {
                pairing = d
            } label: {
                Label("Kastje koppelen", systemImage: "wifi")
            }
            .buttonStyle(ActionButtonStyle(color: .teal, prominent: false))
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

/// Gives a sensor box its settings: the iPhone joins the box's own WiFi network, and the app
/// sends the hotspot, the sensor's name and key and the cloud (SensorPairing).
private struct PairBoxView: View {
    let sensorId: String
    let depthCm: Int
    let sensorKey: String?
    let cloud: CloudConfig?
    @Environment(\.dismiss) private var dismiss
    /// Not secret: the name of the iPhone. The password is never kept.
    @AppStorage("koppelen.hotspotNaam") private var hotspotName = ""
    @State private var password = ""
    @State private var sending = false
    @State private var outcome: SensorPairing.Outcome?
    @State private var failure: String?

    private var settings: SensorPairing.Settings {
        SensorPairing.Settings(hotspotName: hotspotName.trimmingCharacters(in: .whitespaces), hotspotPassword: password,
                               sensorId: sensorId, sensorKey: cloud == nil ? nil : sensorKey,
                               cloudProject: cloud?.projectRef, cloudKey: cloud?.key, depthCm: depthCm)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Design.spacing) {
                    Card {
                        Text("Zo koppel je het kastje").font(.headline)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("1. Zet het kastje aan, of druk op de knop **EN** op het bordje. Het maakt 2 minuten lang een eigen wifi-netwerk: **\(SensorPairing.networkPrefix)…**")
                            Text("2. Ga op je iPhone naar **Instellingen → Wifi** en kies dat netwerk. Het wachtwoord is **\(SensorPairing.networkPassword)**. Kom daarna terug naar Veldvlucht.")
                            Text("3. Vul hieronder je hotspot in en druk op **Koppelen**.")
                        }
                        .font(.footnote)
                    }
                    Card {
                        Text("Je hotspot").font(.headline)
                        TextField("Naam van je hotspot", text: $hotspotName)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)
                        Text("Precies de naam van je iPhone: Instellingen → Algemeen → Info → Naam.")
                            .font(.footnote).foregroundStyle(.secondary)
                        SecureField("Wachtwoord van je hotspot", text: $password)
                            .textFieldStyle(.roundedBorder)
                        Text("Staat bij Instellingen → Persoonlijke hotspot. De app bewaart het niet; alleen het kastje.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Card {
                        Rows(rows: [("Sensor", sensorId), ("Diepte", "\(depthCm) cm"),
                                    ("Naar de cloud", cloud == nil ? "nee, alleen naar de app" : "ja")])
                        if cloud == nil {
                            Text("Voor de cloud: log in (Route → Account) en druk op Bewaren bij Sensoren. Koppel het kastje daarna opnieuw.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if !hotspotName.isEmpty || !password.isEmpty {
                        ForEach(SensorPairing.problems(settings), id: \.self) { Notice(text: $0) }
                    }
                    Button(action: send) {
                        if sending {
                            ProgressView()
                        } else {
                            Label("Koppelen", systemImage: "link")
                        }
                    }
                    .buttonStyle(ActionButtonStyle(color: .teal))
                    .disabled(sending || !SensorPairing.problems(settings).isEmpty)
                    if let failure {
                        Notice(text: failure)
                    }
                    switch outcome {
                    case let .paired(id, raw):
                        Notice(text: "Gekoppeld: het kastje is nu sensor \(id) en meet ruw \(raw). Ga op je iPhone terug naar je gewone wifi en zet je Persoonlijke hotspot aan. Het kastje stuurt zo zijn eerste meting.",
                               symbol: "checkmark.circle.fill", color: .green)
                    case let .refused(reason):
                        Notice(text: "Het kastje bewaarde het niet: \(reason)")
                    case nil:
                        EmptyView()
                    }
                }
                .padding()
            }
            .screenBackground()
            .navigationTitle("Kastje koppelen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Klaar") { dismiss() }
                }
            }
        }
    }

    private func send() {
        let request = SensorPairing.request(settings)
        sending = true
        outcome = nil
        failure = nil
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                outcome = SensorPairing.outcome(data: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
                if case .paired = outcome { password = "" }
            } catch {
                failure = SensorPairing.noAnswer
            }
            sending = false
        }
    }
}
