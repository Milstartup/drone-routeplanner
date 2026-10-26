// Step 6 (docs/STAPPENPLAN.md): the flights saved on this iPhone, each with its photo log
// (veld/fotolog) and log. Share them with AirDrop, together with the photos from the SD card.
import SwiftUI
import UIKit

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
            Group {
                if model.flights.isEmpty && model.problems.isEmpty {
                    ScrollView {
                        Card {
                            EmptyState(
                                symbol: "airplane.departure",
                                title: "Nog geen vluchten",
                                message: "Na een vlucht, ook in de simulator, staan hier het fotolog en het logboek. Deel ze met AirDrop naar de Mac."
                            ) {
                                EmptyView()
                            }
                        }
                        .padding()
                    }
                } else {
                    List {
                        Section {
                            ForEach(model.flights) { flight in
                                NavigationLink {
                                    SavedFlightView(flight: flight)
                                } label: {
                                    FlightRow(flight: flight)
                                }
                            }
                            .onDelete { offsets in
                                offsets.map { model.flights[$0] }.forEach(model.delete)
                            }
                        } footer: {
                            Text("Veeg naar links om een vlucht te verwijderen. In de Bestanden-app: Op mijn iPhone › Veldvlucht › Vluchten.")
                        }
                        if !model.problems.isEmpty {
                            Section("Niet te lezen") {
                                ForEach(model.problems, id: \.self) { Text($0).font(.footnote) }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .screenBackground()
            .navigationTitle("Vluchten")
            .onAppear { model.reload() }
            .refreshable { model.reload() }
        }
    }
}

private struct FlightRow: View {
    let flight: SavedFlight

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: flight.isSimulator ? "cube.transparent" : "airplane",
                      color: flight.isSimulator ? .indigo : .actionGo, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(flight.photoLog.routePlanName)
                    .font(.headline)
                    .lineLimit(2)
                Text(flight.isSimulator ? "Simulator" : "Echte vlucht")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(flight.isSimulator ? Color.indigo : Color.actionGo)
                if let first = flight.photoLog.photos.first {
                    Text(first.time.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(flight.photoLog.photos.count)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                Text("foto's").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

struct SavedFlightView: View {
    let flight: SavedFlight

    private var photos: [PhotoLog.Photo] { flight.photoLog.photos }

    var body: some View {
        ScrollView {
            VStack(spacing: Design.spacing) {
                MapCanvas(
                    shapes: track,
                    pins: photos.map {
                        MapPin(id: "foto-\($0.index)", coordinate: LatLng(lat: $0.lat, lng: $0.lng), title: nil,
                               style: .dot(.systemGreen))
                    },
                    contentID: flight.id,
                    interactive: false,
                    fitInsets: UIEdgeInsets(top: 30, left: 24, bottom: 40, right: 24)
                )
                .frame(height: 250)
                .overlay(alignment: .bottomLeading) { MapAttribution(layer: .pdok).padding(8) }
                .clipShape(RoundedRectangle(cornerRadius: Design.cornerRadius, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(flight.photoLog.routePlanName).font(.title2.weight(.bold))
                    HStack(spacing: 8) {
                        Pill(text: flight.isSimulator ? "Simulator" : "Echte vlucht",
                             symbol: flight.isSimulator ? "cube.transparent" : "airplane",
                             color: flight.isSimulator ? .indigo : .actionGo)
                        Text(flight.id).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

                Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                    GridRow {
                        StatTile(title: "Foto's", symbol: "camera.fill", color: .teal, value: "\(photos.count)",
                                 detail: "in het fotolog")
                        let duration = RouteDetailView.split(RouteCheck.minutes(durationS))
                        StatTile(title: "Duur", symbol: "timer", color: .purple, value: photos.count > 1 ? duration.value : "–",
                                 unit: photos.count > 1 ? duration.unit : nil, detail: "eerste tot laatste foto")
                    }
                }

                if let first = photos.first, let last = photos.last {
                    Card {
                        Rows(rows: [
                            ("Bestanden", "\(first.file) t/m \(last.file)"),
                            ("Begin", first.time.formatted(date: .abbreviated, time: .shortened)),
                            ("Einde", last.time.formatted(date: .omitted, time: .shortened)),
                        ])
                    }
                }

                VStack(spacing: 8) {
                    ShareLink(items: flight.files) {
                        Label("Fotolog en logboek delen", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(ActionButtonStyle(color: .actionGo))
                    Text("Bijvoorbeeld met AirDrop naar de Mac. Zet de foto's van de SD-kaart in dezelfde map: het fotolog zegt welk bestand bij welke geplande fotopositie hoort.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .screenBackground()
        .navigationTitle("Vlucht")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The photos in order, as the line the drone flew.
    private var track: [MapShape] {
        guard photos.count >= 2 else { return [] }
        return [MapShape(id: "spoor", kind: .polyline, points: photos.map { LatLng(lat: $0.lat, lng: $0.lng) },
                         stroke: UIColor.systemGreen.withAlphaComponent(0.8), lineWidth: 2)]
    }

    private var durationS: Double {
        guard let first = photos.first, let last = photos.last else { return 0 }
        return last.time.timeIntervalSince(first.time)
    }
}
