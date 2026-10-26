// The drone screen: is everything connected, how full is the battery, how good is GPS, and
// one test photo on the ground (step 2 of docs/STAPPENPLAN.md).
import SwiftUI
import UIKit

struct DroneTestView: View {
    @ObservedObject var drone: DJIConnection

    private var status: DroneStatus { drone.status }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Design.spacing) {
                    connectionCard
                    metrics
                    firmwareCard
                    photoCard
                    logCard
                    Text("DJI Mobile SDK \(status.sdkVersion.isEmpty ? "–" : status.sdkVersion)")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
                .animation(.snappy, value: status.aircraftConnected)
                .animation(.snappy, value: status.remoteConnected)
            }
            .screenBackground()
            .navigationTitle("Drone")
        }
    }

    // MARK: Connection

    private var readiness: (text: String, symbol: String, color: Color) {
        if status.aircraftConnected { return ("Verbonden", "checkmark.circle.fill", .green) }
        if status.remoteConnected { return ("Zoekt drone", "dot.radiowaves.left.and.right", .orange) }
        return ("Niet verbonden", "bolt.horizontal.circle", .secondary)
    }

    private var connectionCard: some View {
        Card(spacing: 16, tint: status.aircraftConnected ? .green : (status.remoteConnected ? .orange : nil)) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.model ?? "Mavic Mini")
                        .font(.title2.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(status.isFlying ? "Vliegt" : (status.motorsOn ? "Motoren aan" : "Op de grond"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Pill(text: readiness.text, symbol: readiness.symbol, color: readiness.color)
            }
            ConnectionChain(remote: status.remoteConnected, aircraft: status.aircraftConnected)
            if !status.aircraftConnected {
                Text("Sluit DJI Fly af, verbind de iPhone met de kabel en zet daarna de drone aan.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            registration
        }
    }

    @ViewBuilder
    private var registration: some View {
        switch status.registration {
        case .notStarted:
            Check(label: "Aanmelden bij DJI: nog niet gestart", ok: nil).font(.subheadline)
        case .busy:
            HStack(spacing: 10) {
                ProgressView()
                Text("Aanmelden bij DJI… (eerste keer: internet nodig)").font(.subheadline)
            }
        case .done:
            Check(label: "Aangemeld bij DJI", ok: true).font(.subheadline)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 10) {
                Check(label: "Aanmelden bij DJI mislukt", ok: false).font(.subheadline.weight(.semibold))
                Text(message).font(.footnote).foregroundStyle(.red)
                Button {
                    drone.retryRegistration()
                } label: {
                    Label("Opnieuw proberen", systemImage: "arrow.clockwise")
                }
                .buttonStyle(ActionButtonStyle(color: .veld, prominent: false))
            }
        }
        if let progress = status.databaseProgress {
            ProgressView("Fly Safe-database downloaden", value: progress)
                .font(.footnote)
                .tint(.veld)
        }
    }

    // MARK: Battery, GPS, SD card, motors

    private var metrics: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                StatTile(title: "Accu", symbol: batterySymbol, color: batteryColor,
                         value: status.batteryPercent.map(String.init) ?? "–", unit: "%",
                         detail: status.batteryVolts.map { "\(dutchNumber($0, digits: 2)) V" } ?? "nog onbekend")
                StatTile(title: "GPS", symbol: "location.fill", color: gpsColor,
                         value: status.satelliteCount.map(String.init) ?? "–", unit: "satellieten") {
                    HStack(spacing: 6) {
                        SignalBars(level: status.gpsLevel, color: gpsColor)
                        Text(gpsDetail)
                    }
                }
            }
            GridRow {
                StatTile(title: "SD-kaart", symbol: "sdcard.fill", color: sdColor,
                         value: status.sdCard == nil ? "–" : (status.sdCardReady ? "Klaar" : "Let op"),
                         detail: status.sdCard ?? "geen camera")
                StatTile(title: "Motoren", symbol: "fanblades.fill", color: status.motorsOn ? .orange : .gray,
                         value: status.motorsOn ? "Aan" : "Uit",
                         detail: status.simulatorActive ? "simulator staat aan" : "propellers eraf bij testen")
            }
        }
    }

    private var batterySymbol: String {
        guard let percent = status.batteryPercent else { return "battery.0percent" }
        switch percent {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    private var batteryColor: Color {
        guard let percent = status.batteryPercent else { return .gray }
        if percent < 20 { return .red }
        if percent < 50 { return .orange }
        return .green
    }

    private var gpsColor: Color {
        guard let level = status.gpsLevel else { return .gray }
        return level >= 4 ? .green : (level >= 2 ? .orange : .red)
    }

    private var gpsDetail: String {
        guard status.satelliteCount != nil else { return "nog onbekend" }
        guard let level = status.gpsLevel else { return "geen signaal" }
        return "signaal \(level) van 5"
    }

    private var sdColor: Color {
        guard status.sdCard != nil else { return .gray }
        return status.sdCardReady ? .blue : .orange
    }

    // MARK: Firmware

    private var firmwareCard: some View {
        Card {
            HStack(spacing: 10) {
                IconBadge(symbol: "cpu", color: firmwareColor, size: 30)
                Text("Firmware").font(.headline)
                Spacer()
                if status.firmware == expectedFirmware {
                    Pill(text: "Zoals verwacht", symbol: "checkmark", color: .green)
                } else if status.firmware != nil || status.firmwareUnknown {
                    Pill(text: "Controleer", symbol: "exclamationmark", color: .orange)
                }
            }
            VStack(spacing: 10) {
                Row(label: "Drone", value: firmwareText, valueColor: status.firmware == nil ? .secondary : .primary)
                if let flightController = status.flightControllerFirmware {
                    Divider()
                    Row(label: "Vluchtcomputer", value: flightController)
                }
            }
            Text("Verwacht \(expectedFirmware). De DJI-software vraagt die op via internet. Werk de firmware niet bij.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var firmwareText: String {
        if let firmware = status.firmware { return firmware }
        return status.firmwareUnknown ? "onbekend, zie logboek" : "–"
    }

    private var firmwareColor: Color {
        guard let firmware = status.firmware else { return status.firmwareUnknown ? .orange : .gray }
        return firmware == expectedFirmware ? .green : .orange
    }

    // MARK: Test photo

    private var photoCard: some View {
        Card {
            HStack(spacing: 10) {
                IconBadge(symbol: "camera.fill", color: .blue, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Testfoto op de grond").font(.headline)
                    Text("Propellers eraf. Alleen als de drone niet vliegt.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                drone.takePhoto()
            } label: {
                Label("Maak één foto", systemImage: "camera.shutter.button")
            }
            .buttonStyle(ActionButtonStyle(color: .actionHold))
            .disabled(!status.canTakePhoto)
            switch status.photo {
            case .idle:
                EmptyView()
            case .busy(let message):
                HStack(spacing: 10) {
                    ProgressView()
                    Text(message).font(.subheadline)
                }
            case .done(let file):
                Notice(text: "Gelukt: \(file)", symbol: "checkmark.circle.fill", color: .green)
            case .failed(let message):
                Notice(text: message, symbol: "xmark.circle.fill", color: .red)
            }
        }
    }

    // MARK: Log

    private var logCard: some View {
        Card {
            HStack {
                IconBadge(symbol: "list.bullet.rectangle.portrait.fill", color: .gray, size: 30)
                Text("Logboek").font(.headline)
                Spacer()
                Text("\(drone.log.count) regels").font(.subheadline).foregroundStyle(.secondary)
            }
            if drone.log.isEmpty {
                Text("Nog leeg.").font(.footnote).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(drone.log.suffix(3).reversed()) { line in
                        LogLineText(time: line.time, text: line.text)
                    }
                }
            }
            HStack(spacing: 10) {
                NavigationLink {
                    LogScreen(title: "Logboek", lines: drone.log.map { ($0.time, $0.text) })
                } label: {
                    Label("Alles bekijken", systemImage: "text.alignleft")
                }
                .buttonStyle(ActionButtonStyle(color: .veld, prominent: false))
                CopyLogButton(lines: drone.log.map { ($0.time, $0.text) })
            }
            .disabled(drone.log.isEmpty)
        }
    }
}

/// iPhone — remote controller — drone, each link green once it works.
struct ConnectionChain: View {
    let remote: Bool
    let aircraft: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            node(label: "iPhone", on: true) {
                Image(systemName: "iphone").font(.system(size: 24, weight: .semibold))
            }
            link(on: remote, label: "iPhone ↔ afstandsbediening")
            node(label: "Afstands­bediening", on: remote) {
                Image(systemName: "gamecontroller.fill").font(.system(size: 22, weight: .semibold))
            }
            link(on: aircraft, label: "Afstandsbediening ↔ drone")
            node(label: "Drone", on: aircraft) {
                DroneGlyph(color: aircraft ? .white : Color(uiColor: .secondaryLabel)).frame(width: 32, height: 32)
            }
        }
    }

    private func node<Icon: View>(label: String, on: Bool, @ViewBuilder icon: () -> Icon) -> some View {
        VStack(spacing: 6) {
            icon()
                .foregroundStyle(on ? Color.white : Color(uiColor: .secondaryLabel))
                .frame(width: 56, height: 56)
                .background(on ? AnyShapeStyle(Color.veld.gradient) : AnyShapeStyle(Color(uiColor: .tertiarySystemFill)), in: Circle())
            Text(label)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(width: 82)
        .accessibilityHidden(true)
    }

    private func link(on: Bool, label: String) -> some View {
        ZStack {
            Line()
                .stroke(on ? Color.green : Color.secondary.opacity(0.5),
                        style: StrokeStyle(lineWidth: on ? 3 : 2, lineCap: .round, dash: on ? [] : [3, 5]))
                .frame(height: 3)
                .padding(.horizontal, 2)
            Image(systemName: on ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(on ? Color.green : Color.secondary)
                .background(Circle().fill(Color.cardBackground))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .accessibilityElement()
        .accessibilityLabel("\(label): \(on ? "verbonden" : "niet verbonden")")
    }
}

/// A straight horizontal line through the middle.
private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

/// One log line: the time in grey, then the text.
struct LogLineText: View {
    let time: Date
    let text: String

    var body: some View {
        (Text(time.formatted(date: .omitted, time: .standard)).foregroundStyle(.secondary) + Text("  ") + Text(text))
            .font(.footnote.monospaced())
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }
}

/// The whole log, newest first.
struct LogScreen: View {
    let title: String
    let lines: [(Date, String)]

    var body: some View {
        List {
            ForEach(Array(lines.enumerated().reversed()), id: \.offset) { _, line in
                LogLineText(time: line.0, text: line.1)
            }
        }
        .listStyle(.plain)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    UIPasteboard.general.string = logText(lines)
                } label: {
                    Label("Kopieer logboek", systemImage: "doc.on.doc")
                }
            }
        }
    }
}

/// Copies the log, to paste it in a message to Claude.
struct CopyLogButton: View {
    let lines: [(Date, String)]
    @State private var copied = false

    var body: some View {
        Button {
            UIPasteboard.general.string = logText(lines)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
        } label: {
            Label(copied ? "Gekopieerd" : "Kopieer logboek", systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        .buttonStyle(ActionButtonStyle(color: .veld, prominent: false))
        .sensoryFeedback(.success, trigger: copied) { _, new in new }
    }
}

func logText(_ lines: [(Date, String)]) -> String {
    lines.map { "\($0.0.formatted(date: .omitted, time: .standard))  \($0.1)" }.joined(separator: "\n")
}
