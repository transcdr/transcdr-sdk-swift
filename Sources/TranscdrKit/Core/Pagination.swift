import Foundation

/// A cursor-paginated list.
public struct ListResponse<T: Decodable>: Decodable {
    public var data: [T]
    public var hasMore: Bool
    public var nextCursor: String?

    public init(data: [T], hasMore: Bool = false, nextCursor: String? = nil) {
        self.data = data
        self.hasMore = hasMore
        self.nextCursor = nextCursor
    }

    enum CodingKeys: String, CodingKey {
        case data
        case hasMore = "has_more"
        case nextCursor = "next_cursor"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        data = try c.decodeList([T].self, forKey: .data)
        hasMore = try c.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
        nextCursor = try c.decodeIfPresent(String.self, forKey: .nextCursor)
    }

    /// Accept the list envelope, and also a bare array.
    static func decodeLenient(_ data: Data) throws -> ListResponse<T> {
        do {
            if let first = data.first(where: { !$0.isWhitespace }), first == UInt8(ascii: "[") {
                return ListResponse(data: try TranscdrCoding.decoder.decode([T].self, from: data))
            }
            return try TranscdrCoding.decoder.decode(ListResponse<T>.self, from: data.isEmpty ? Data("{}".utf8) : data)
        } catch {
            throw TranscdrError(kind: .decoding, status: 200, message: "The API returned a list the app could not read (\(error)).")
        }
    }
}

extension ListResponse: Sendable where T: Sendable {}

private extension UInt8 {
    var isWhitespace: Bool { self == 0x20 || self == 0x0A || self == 0x0D || self == 0x09 }
}

/// Walks every page of a list endpoint as an `AsyncSequence` of items.
///
/// ```swift
/// for try await job in client.jobs.all(status: .completed) { … }
/// ```
public struct Paginator<T: Decodable & Sendable>: AsyncSequence, Sendable {
    public typealias Element = T
    let fetch: @Sendable (String?) async throws -> ListResponse<T>

    public init(fetch: @escaping @Sendable (String?) async throws -> ListResponse<T>) {
        self.fetch = fetch
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        let fetch: @Sendable (String?) async throws -> ListResponse<T>
        var buffer: [T] = []
        var cursor: String?
        var started = false
        var done = false

        public mutating func next() async throws -> T? {
            while buffer.isEmpty {
                if done { return nil }
                if started && cursor == nil { return nil }
                let page = try await fetch(cursor)
                started = true
                buffer = page.data
                cursor = page.hasMore ? page.nextCursor : nil
                if cursor == nil { done = true }
                if buffer.isEmpty && done { return nil }
            }
            return buffer.removeFirst()
        }
    }

    public func makeAsyncIterator() -> AsyncIterator { AsyncIterator(fetch: fetch) }

    /// Collect items, stopping after `max`.
    public func collect(max: Int = .max) async throws -> [T] {
        var out: [T] = []
        for try await item in self {
            out.append(item)
            if out.count >= max { break }
        }
        return out
    }
}
