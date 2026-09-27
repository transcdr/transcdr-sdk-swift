import Foundation

/// A string enum that tolerates values it does not know: the API may add a
/// status or kind, and an app built before it must still decode the rest of
/// the response. Known values are static members; `rawValue` carries any.
public protocol OpenEnum: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible,
    ExpressibleByStringLiteral where RawValue == String
{
    init(rawValue: String)
}

extension OpenEnum {
    public init(stringLiteral value: String) { self.init(rawValue: value) }

    public init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    public var description: String { rawValue }
}

/// Declares an open enum's storage. Each conforming type adds its known
/// values as `static let`.
public protocol OpenEnumStorage {}
