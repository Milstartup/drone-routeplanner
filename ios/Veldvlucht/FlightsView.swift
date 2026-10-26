// Step 6 (docs/STAPPENPLAN.md): the flights saved on this iPhone, each with its photo log
// (veld/fotolog) and log. Share them with AirDrop, together with the photos from the SD card.
import SwiftUI

struct SavedFlight: Identifiable {
    let photoLog: PhotoLog
    let photoLogURL: URL
    let logURL: URL?

    var id: String { photoLog.flightId }
    var isSimulator: Bool { photoLog.flightId.hasSuffix("-simulator") }
    var files: [URL] { [photoLogURL] + (logURL.map { [$0] } ?? []) }
}

final class FlightsModel: ObservableObject {
    @Published private(set) var flights: [SavedFlight] = []
    @Published private(set) var problems: [String] = []

    func reload() {
        let folder = FlightRecorder.folder
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var found: [SavedFlight] = []
        var problems: [String] = []
        for url in urls where url.lastPathComponent.hasSuffix(".fotolog.json") {
            do {
                let log = try PhotoLog.read(Data(contentsOf: url))
                let logURL = folder.appendingPathComponent("\(log.flightId).logboek.txt")
                found.append(SavedFlight(photoLog: log, photoLogURL: url,
                                         logURL: FileManager.default.fileExists(atPath: logURL.path) ? logURL : nil))
            } catch {
                problems.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        // The flight id starts with the date and time, so this is newest first.
        flights = found.sorted { $0.id > $1.id }
        self.problems = problems
    }

    func delete(_ flight: SavedFlight) {
        flight.files.forEach { try? FileManager.default.removeItem(at: $0) }
        reload()
    }
}

struct FlightsView: View {
    @StateObject private var model = FlightsModel()

    var body: some View {
        NavigationStack {
            List {
                if model.flights.isEmpty {
                    Text("Nog geen vluchten met foto's. Na een vlucht (ook in de simulator) staan hier het fotolog en het logboek.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.flights) { flight in
                    NavigationLink {
                        SavedFlightView(flight: flight)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(flight.photoLog.routePlanName).font(.headline)
                            Text("\(flight.photoLog.photos.count) foto's · \(flight.isSimulator ? "simulator" : "echte vlucht")")
                                .font(.subheadline)
                                .foregroundStyle(flight.isSimulator ? .secondary : .primary)
                            if let first = flight.photoLog.photos.first {
                                Text(first.time.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    offsets.map { model.flights[$0] }.forEach(model.delete)
                }
                if !model.problems.isEmpty {
                    Section("Niet te lezen") {
                        ForEach(model.problems, id: \.self) { Text($0).font(.footnote) }
                    }
                }
            }
            .navigationTitle("Vluchten")
            .onAppear { model.reload() }
            .refreshable { model.reload() }
        }
    }
}

private struct SavedFlightView: View {
    let flight: SavedFlight
    @State private var baseLayer = BaseLayer.pdok

    private var photos: [PhotoLog.Photo] { flight.photoLog.photos }

    var body: some View {
        VStack(spacing: 0) {
            MapCanvas(
                shapes: [],
                pins: photos.map {
                    MapPin(id: "foto-\($0.index)", coordinate: LatLng(lat: $0.lat, lng: $0.lng), title: nil,
                           style: .dot(.systemGreen))
                },
                contentID: flight.id,
                baseLayer: baseLayer
            )
            .frame(height: 260)
            .overlay(alignment: .bottom) { MapAttribution(layer: baseLayer).padding(.bottom, 4) }
            List {
                Section {
                    Row(label: "Route", value: flight.photoLog.routePlanName)
                    Row(label: "Soort", value: flight.isSimulator ? "Simulator" : "Echte vlucht")
                    Row(label: "Foto's", value: "\(photos.count)")
                    if let first = photos.first, let last = photos.last {
                        Row(label: "Bestanden", value: "\(first.file) t/m \(last.file)")
                        Row(label: "Tijd", value: "\(first.time.formatted(date: .abbreviated, time: .shortened)) – \(last.time.formatted(date: .omitted, time: .shortened))")
                    }
                }
                Section {
                    ShareLink(items: flight.files) {
                        Label("Fotolog en logboek delen", systemImage: "square.and.arrow.up")
                    }
                } footer: {
                    Text("Bijvoorbeeld met AirDrop naar de Mac. Zet de foto's van de SD-kaart in dezelfde map: het fotolog zegt welk bestand bij welke geplande fotopositie hoort.")
                }
            }
        }
        .navigationTitle(flight.id)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { BaseLayerMenu(layer: $baseLayer) }
    }
}
