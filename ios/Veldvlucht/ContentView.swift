// The feasibility test screen: one section per step of docs/STAPPENPLAN.md, step 2.
import SwiftUI
import UIKit

struct ContentView: View {
    @ObservedObject var drone: DJIConnection

    private var status: DroneStatus { drone.status }

    var body: some View {
        NavigationStack {
            List {
                registrationSection
                connectionSection
                telemetrySection
                photoSection
                logSection
            }
            .navigationTitle("Veldvlucht")
        }
    }

    private var registrationSection: some View {
        Section("1 · Aanmelden bij DJI") {
            switch status.registration {
            case .notStarted:
                Check(label: "Nog niet gestart", ok: nil)
            case .busy:
                Check(label: "Bezig (eerste keer: internet nodig)", ok: nil)
            case .done:
                Check(label: "Aangemeld", ok: true)
            case .failed(let message):
                Check(label: "Mislukt", ok: false)
                Text(message).font(.footnote).foregroundStyle(.red)
            }
            if let progress = status.databaseProgress {
                ProgressView("Fly Safe-database downloaden", value: progress)
            }
            Row(label: "SDK-versie", value: status.sdkVersion)
        }
    }

    private var connectionSection: some View {
        Section {
            Check(label: "iPhone ↔ afstandsbediening", ok: status.remoteConnected)
            Check(label: "Afstandsbediening ↔ drone", ok: status.aircraftConnected)
            Row(label: "Model", value: status.model ?? "–")
        } header: {
            Text("2 · Verbinding")
        } footer: {
            Text("Sluit DJI Fly af, verbind de iPhone met de kabel en zet daarna de drone aan.")
        }
    }

    private var telemetrySection: some View {
        Section {
            Row(label: "Accu", value: batteryText)
            Row(label: "GPS-satellieten", value: gpsText)
            HStack {
                Text("Firmware")
                Spacer()
                Text(status.firmware ?? "–").foregroundStyle(firmwareColor)
            }
            Row(label: "Motoren", value: status.motorsOn ? "aan" : "uit")
        } header: {
            Text("3 · Drone")
        } footer: {
            Text("Binnen ziet de drone weinig of geen satellieten; GPS test je buiten. Verwacht firmware \(expectedFirmware). Werk de firmware niet bij.")
        }
    }

    private var photoSection: some View {
        Section {
            Row(label: "SD-kaart", value: status.sdCard ?? "–")
            Button {
                drone.takePhoto()
            } label: {
                Label("Maak één foto", systemImage: "camera")
            }
            .disabled(!status.canTakePhoto)
            switch status.photo {
            case .idle:
                EmptyView()
            case .busy(let message):
                HStack {
                    ProgressView()
                    Text(message)
                }
            case .done(let file):
                Check(label: "Gelukt: \(file)", ok: true)
            case .failed(let message):
                Check(label: message, ok: false)
            }
        } header: {
            Text("4 · Foto op de grond")
        } footer: {
            Text("Propellers eraf. Deze app stuurt geen vliegcommando's; de knop werkt alleen als de drone niet vliegt en er een SD-kaart in zit.")
        }
    }

    private var logSection: some View {
        Section("Logboek") {
            Button {
                UIPasteboard.general.string = logText
            } label: {
                Label("Kopieer logboek", systemImage: "doc.on.doc")
            }
            .disabled(drone.log.isEmpty)
            ForEach(drone.log.reversed()) { line in
                Text("\(line.time.formatted(date: .omitted, time: .standard))  \(line.text)")
                    .font(.footnote.monospaced())
            }
        }
    }

    private var batteryText: String {
        guard let percent = status.batteryPercent else { return "–" }
        if let volts = status.batteryVolts {
            return "\(percent) % (\(String(format: "%.2f", volts)) V)"
        }
        return "\(percent) %"
    }

    private var gpsText: String {
        guard let count = status.satelliteCount else { return "–" }
        guard let level = status.gpsLevel else { return "\(count) (geen GPS-signaal)" }
        return "\(count) (signaal \(level) van 5)"
    }

    private var firmwareColor: Color {
        guard let firmware = status.firmware else { return .secondary }
        return firmware == expectedFirmware ? .green : .orange
    }

    private var logText: String {
        drone.log
            .map { "\($0.time.formatted(date: .omitted, time: .standard))  \($0.text)" }
            .joined(separator: "\n")
    }
}

/// A row with a green tick, a red cross or an hourglass (ok == nil: still waiting).
private struct Check: View {
    let label: String
    let ok: Bool?

    var body: some View {
        Label {
            Text(label)
        } icon: {
            switch ok {
            case .some(true):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .some(false):
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            case .none:
                Image(systemName: "hourglass").foregroundStyle(.secondary)
            }
        }
    }
}

private struct Row: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
    }
}
