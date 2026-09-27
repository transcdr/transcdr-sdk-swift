import Foundation

/// The JSON coders every request and response goes through. Keys are mapped
/// explicitly in each model (`CodingKeys`), never by a key strategy: a
/// strategy would also rewrite the keys of free-form maps such as metadata.
public enum TranscdrCoding {
    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = parseTimestamp(s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Not an RFC 3339 timestamp: \(s)")
        }
        return d
    }()

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(formatTimestamp(date))
        }
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }()

    /// Parse an RFC 3339 timestamp, with or without fractional seconds, or a
    /// bare `YYYY-MM-DD` date (midnight UTC).
    public static func parseTimestamp(_ s: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = fractional.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let d = plain.date(from: s) { return d }
        // Postgres-style `2026-09-27 05:18:43.011992+00` and up to nanosecond
        // fractions, which ISO8601DateFormatter refuses beyond milliseconds.
        var normalized = s.replacingOccurrences(of: " ", with: "T")
        if let dot = normalized.firstIndex(of: ".") {
            var end = normalized.index(after: dot)
            while end < normalized.endIndex, normalized[end].isNumber { end = normalized.index(after: end) }
            let digits = normalized[normalized.index(after: dot)..<end]
            normalized.replaceSubrange(normalized.index(after: dot)..<end, with: String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0))
        }
        if normalized.hasSuffix("+00") { normalized += ":00" }
        if let d = fractional.date(from: normalized) ?? plain.date(from: normalized) { return d }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(identifier: "UTC")
        day.dateFormat = "yyyy-MM-dd"
        return day.date(from: s)
    }

    public static func formatTimestamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }
}

extension KeyedDecodingContainer {
    /// Decode a list that may be missing or null as empty.
    func decodeList<T: Decodable>(_ type: [T].Type, forKey key: Key) throws -> [T] {
        try decodeIfPresent(type, forKey: key) ?? []
    }

    /// Decode a map that may be missing or null as empty.
    func decodeMap<T: Decodable>(_ type: [String: T].Type, forKey key: Key) throws -> [String: T] {
        try decodeIfPresent(type, forKey: key) ?? [:]
    }
}
