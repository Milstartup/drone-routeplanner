// Receives the measurements of the sensor boxes (sensor/README.md). A box joins the iPhone's
// Personal Hotspot and sends what it measured to the iPhone (the hotspot's gateway) on port
// 8787, while the app is open. Free and without an account: the measurements stay on the
// iPhone, with the field the sensor is placed in.
import Foundation
import Network

@MainActor
final class SensorReceiver: ObservableObject {
    static let port: UInt16 = 8787
    /// A request larger than this is refused (a box sends a few kB).
    private static let maxRequestBytes = 512 * 1024

    struct Event: Equatable {
        var time: Date
        var text: String
        var ok: Bool
    }

    @Published private(set) var running = false
    @Published private(set) var events: [Event] = []
    /// Changes after every stored upload, so the field map reloads.
    @Published private(set) var uploads = 0

    private var listener: NWListener?
    private let fields: FieldStore
    /// After storing: the upload as it came in, the sensor and the field (for the cloud).
    var onStored: ((Data, String, String) -> Void)?

    init(fields: FieldStore) {
        self.fields = fields
    }

    var lastEvent: Event? { events.last }

    func start() {
        guard listener == nil else { return }
        do {
            let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: Self.port)!)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in self?.listenerChanged(state) }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            note("De ontvanger kan niet starten: \(error.localizedDescription)", ok: false)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        running = false
    }

    private func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            running = true
        case .failed(let error):
            running = false
            listener = nil
            note("De ontvanger is gestopt: \(error.localizedDescription)", ok: false)
        case .cancelled:
            running = false
        default:
            break
        }
    }

    private func note(_ text: String, ok: Bool) {
        events.append(Event(time: Date(), text: text, ok: ok))
        if events.count > 50 { events.removeFirst() }
    }

    // MARK: HTTP

    private func accept(_ connection: NWConnection) {
        // Only boxes on a local network (the hotspot), never someone on the internet.
        guard Self.isLocal(connection.endpoint) else {
            connection.cancel()
            return
        }
        connection.start(queue: .main)
        read(connection, buffer: Data())
    }

    /// Private IPv4 ranges (the hotspot is 172.20.10.x) and local IPv6 addresses.
    static func isLocal(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address):
            let b = [UInt8](address.rawValue)
            guard b.count == 4 else { return false }
            return b[0] == 10 || (b[0] == 172 && (16...31).contains(b[1])) || (b[0] == 192 && b[1] == 168)
                || (b[0] == 169 && b[1] == 254) || b[0] == 127
        case .ipv6(let address):
            if let v4 = address.asIPv4 { return isLocal(.hostPort(host: .ipv4(v4), port: 0)) }
            let b = [UInt8](address.rawValue)
            guard b.count == 16 else { return false }
            return (b[0] == 0xfe && (b[1] & 0xc0) == 0x80) || (b[0] & 0xfe) == 0xfc || address == .loopback
        default:
            return false
        }
    }

    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
            Task { @MainActor in
                guard let self else { return }
                var buffer = buffer
                if let data { buffer.append(data) }
                if let request = HTTPRequest(buffer) {
                    self.answer(request, on: connection)
                } else if error != nil || complete || buffer.count > Self.maxRequestBytes {
                    connection.cancel()
                } else {
                    self.read(connection, buffer: buffer)
                }
            }
        }
    }

    private func answer(_ request: HTTPRequest, on connection: NWConnection) {
        let (status, body) = handle(request)
        let reason = [200: "OK", 400: "Bad Request", 404: "Not Found", 405: "Method Not Allowed"][status] ?? "Error"
        var response = Data("HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n".utf8)
        response.append(Data(body.utf8))
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func handle(_ request: HTTPRequest) -> (Int, String) {
        if request.method == "GET" {
            return (200, #"{"ontvanger":"Veldvlucht","versie":0}"#)
        }
        guard request.method == "POST", request.path == "/sensormetingen" else {
            return (404, #"{"fout":"Gebruik POST /sensormetingen."}"#)
        }
        let upload: SensorUpload
        do {
            upload = try SensorUpload.read(request.body)
        } catch {
            note("Een kastje stuurde iets wat niet te lezen is: \(error.localizedDescription)", ok: false)
            return (400, json(["fout": error.localizedDescription]))
        }
        guard let field = fields.field(forSensor: upload.sensorId),
              let sensor = field.sensors.first(where: { $0.id == upload.sensorId }) else {
            // Not stored: the box keeps its measurements until the sensor is placed in a field.
            note("Kastje \"\(upload.sensorId)\" staat in geen enkel veld. Plaats de sensor bij Sensoren, met dezelfde naam.", ok: false)
            return (404, json(["fout": "Onbekende sensor \(upload.sensorId)"]))
        }
        // A box that sends again (it missed the answer) gives no doubles.
        let unseen = upload.unseen(after: SensorStore.marks(fieldId: field.id)[upload.sensorId])
        var fresh = upload
        fresh.measurements = unseen.measurements
        let measurements = fresh.measurements(field: field, sensor: sensor, receivedAt: Date())
        let added = SensorStore.add(measurements, fieldId: field.id, checkDoubles: !unseen.numbered)
        if let mark = unseen.mark {
            SensorStore.saveMark(mark, sensorId: upload.sensorId, fieldId: field.id)
        }
        let name = sensor.shortName(fieldId: field.id)
        note("Sensor \(name) (\(field.name)): \(upload.measurements.count) meting(en) ontvangen, \(added) nieuw.", ok: true)
        uploads += 1
        onStored?(request.body, upload.sensorId, field.id)
        return (200, #"{"ontvangen":\#(upload.measurements.count)}"#)
    }

    private func json(_ object: [String: String]) -> String {
        (try? JSONSerialization.data(withJSONObject: object)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}

/// A complete HTTP/1.1 request, or nil while not all of it has arrived.
private struct HTTPRequest {
    let method: String
    let path: String
    let body: Data

    init?(_ data: Data) {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: data[..<end.lowerBound], as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        guard parts.count >= 2 else { return nil }
        var length = 0
        for line in lines.dropFirst() {
            let pair = line.split(separator: ":", maxSplits: 1)
            if pair.count == 2, pair[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                length = Int(pair[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }
        let body = data[end.upperBound...]
        guard body.count >= length else { return nil }
        method = String(parts[0])
        path = String(parts[1])
        self.body = Data(body.prefix(length))
    }
}
