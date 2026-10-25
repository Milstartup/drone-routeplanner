// Reading JSON files with explanations in Dutch instead of Swift's decoding errors.
import Foundation

struct FileReadError: LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
}

enum JSONReading {
    /// Decodes ISO 8601 times with a time zone, with or without fractions of a second.
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = parseDate(text) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "\"\(text)\" is geen tijd in ISO 8601 met tijdzone."
                )
            }
            return date
        }
        return decoder
    }()

    static func parseDate(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }

    /// Checks that `data` is a JSON object with the expected `format` and `version`.
    static func checkHeader(_ data: Data, format: String, version: Int, what: String) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            throw FileReadError(message: "Dit is geen geldig JSON-bestand.")
        }
        guard let root = object as? [String: Any] else {
            throw FileReadError(message: "Dit is geen \(what): het bestand bevat geen JSON-object.")
        }
        try checkHeader(root, format: format, version: version, what: what)
    }

    static func checkHeader(_ root: [String: Any], format: String, version: Int, what: String) throws {
        guard root["format"] as? String == format else {
            throw FileReadError(message: "Dit is geen \(what) (verwacht \"format\": \"\(format)\").")
        }
        guard let found = root["version"] as? Int, found == version else {
            throw FileReadError(message: "Onbekende versie \(String(describing: root["version"] ?? "zonder versie")) van \(format); de app leest versie \(version).")
        }
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch let error as DecodingError {
            throw FileReadError(message: explain(error))
        }
    }

    private static func explain(_ error: DecodingError) -> String {
        func path(_ codingPath: [CodingKey]) -> String {
            let parts = codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }
            let joined = parts.joined()
            return joined.hasPrefix(".") ? String(joined.dropFirst()) : joined
        }
        switch error {
        case .keyNotFound(let key, let context):
            let parent = path(context.codingPath)
            return "Veld \"\(parent.isEmpty ? key.stringValue : parent + "." + key.stringValue)\" ontbreekt."
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return "Veld \"\(path(context.codingPath))\" heeft een verkeerd type of is leeg."
        case .dataCorrupted(let context):
            let field = path(context.codingPath)
            return field.isEmpty ? "Het bestand is beschadigd." : "Veld \"\(field)\": \(context.debugDescription)"
        @unknown default:
            return "Het bestand kan niet gelezen worden."
        }
    }
}
