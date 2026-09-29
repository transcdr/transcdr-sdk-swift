import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Query parameters. `metadata: [k: v]` is sent as `metadata[k]=v`.
public typealias Query = [(String, String?)]

/// The Transcdr API client.
///
/// ```swift
/// let client = Transcdr(apiKey: "tdk_live_…")
/// let job = try await client.jobs.create(.init(input: .url("https://…/talk.mov"), preset: "hls-av1-abr"))
/// ```
public final class Transcdr: @unchecked Sendable {
    public static let defaultBaseURL = URL(string: "https://api.transcdr.com")!
    public static let version = "0.9.0"

    public let baseURL: URL
    public let maxRetries: Int
    public let timeout: TimeInterval
    public let retryDelay: TimeInterval
    let transport: HTTPTransport
    private let lock = NSLock()
    private var _apiKey: String?
    private var _onUnauthorized: (@Sendable () -> Void)?

    public init(
        apiKey: String? = nil,
        baseURL: URL = Transcdr.defaultBaseURL,
        transport: HTTPTransport = URLSessionTransport(),
        maxRetries: Int = 2,
        timeout: TimeInterval = 60,
        retryDelay: TimeInterval = 0.5
    ) {
        self._apiKey = apiKey
        self.baseURL = baseURL
        self.transport = transport
        self.maxRetries = max(0, maxRetries)
        self.timeout = timeout
        self.retryDelay = retryDelay
    }

    /// A secret API key (`tdk_live_…`, `tdk_test_…`) or a session token (`tds_…`).
    public var apiKey: String? {
        get { lock.withLock { _apiKey } }
        set { lock.withLock { _apiKey = newValue } }
    }

    /// Called when an authenticated request comes back 401: the session
    /// expired or was revoked.
    public var onUnauthorized: (@Sendable () -> Void)? {
        get { lock.withLock { _onUnauthorized } }
        set { lock.withLock { _onUnauthorized = newValue } }
    }

    // MARK: Resources

    public var auth: AuthResource { .init(client: self) }
    public var organization: OrganizationResource { .init(client: self) }
    public var organizations: OrganizationsResource { .init(client: self) }
    public var apiKeys: APIKeysResource { .init(client: self) }
    public var uploads: UploadsResource { .init(client: self) }
    public var assets: AssetsResource { .init(client: self) }
    public var jobs: JobsResource { .init(client: self) }
    public var probe: ProbeResource { .init(client: self) }
    public var presets: PresetsResource { .init(client: self) }
    public var webhooks: WebhooksResource { .init(client: self) }
    public var events: EventsResource { .init(client: self) }
    public var usage: UsageResource { .init(client: self) }
    public var billing: BillingResource { .init(client: self) }
    public var plans: PlansResource { .init(client: self) }
    public var capabilities: CapabilitiesResource { .init(client: self) }
    public var status: StatusResource { .init(client: self) }
    public var stats: StatsResource { .init(client: self) }
    public var connections: ConnectionsResource { .init(client: self) }
    public var automations: AutomationsResource { .init(client: self) }
    public var deliveries: DeliveriesResource { .init(client: self) }
    public var announcements: AnnouncementsResource { .init(client: self) }
    public var admin: AdminResource { .init(client: self) }

    // MARK: Requests

    /// Resolve an API path (`/v1/…`) or an absolute URL.
    public func url(_ path: String, query: Query = []) -> URL {
        var components: URLComponents
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            components = URLComponents(string: path) ?? URLComponents()
        } else {
            let base = baseURL.absoluteString.hasSuffix("/") ? String(baseURL.absoluteString.dropLast()) : baseURL.absoluteString
            components = URLComponents(string: base + (path.hasPrefix("/") ? path : "/" + path)) ?? URLComponents()
        }
        let items = query.compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } }
        if !items.isEmpty {
            components.queryItems = (components.queryItems ?? []) + items
            // `+` is a space to most servers; encode it.
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        return components.url ?? baseURL
    }

    /// Send a request and decode the response as `T`.
    public func request<T: Decodable>(
        _ method: String, _ path: String, query: Query = [], body: (any Encodable)? = nil,
        idempotencyKey: String? = nil, timeout: TimeInterval? = nil, as type: T.Type = T.self
    ) async throws -> T {
        let data = try await send(method, path, query: query, body: body, idempotencyKey: idempotencyKey, timeout: timeout)
        if T.self == Empty.self { return Empty() as! T }
        do {
            return try TranscdrCoding.decoder.decode(T.self, from: data.isEmpty ? Data("{}".utf8) : data)
        } catch {
            throw TranscdrError(kind: .decoding, status: 200, message: "The API returned a response the app could not read (\(describe(error))).")
        }
    }

    /// Send a request whose response body is not needed.
    public func requestVoid(_ method: String, _ path: String, query: Query = [], body: (any Encodable)? = nil) async throws {
        _ = try await send(method, path, query: query, body: body, idempotencyKey: nil, timeout: nil)
    }

    /// A non-paginated collection, normalised to a list.
    public func collection<T: Decodable>(_ path: String, query: Query = [], as type: T.Type = T.self) async throws -> ListResponse<T> {
        let data = try await send("GET", path, query: query, body: nil, idempotencyKey: nil, timeout: nil)
        return try ListResponse<T>.decodeLenient(data)
    }

    /// One page of a list endpoint.
    public func page<T: Decodable>(_ path: String, query: Query = [], cursor: String? = nil, as type: T.Type = T.self) async throws -> ListResponse<T> {
        var q = query
        if let cursor { q.append(("cursor", cursor)) }
        return try await collection(path, query: q)
    }

    /// Every page of a list endpoint, lazily.
    public func pages<T: Decodable & Sendable>(_ path: String, query: Query = [], as type: T.Type = T.self) -> Paginator<T> {
        Paginator { [self] cursor in try await page(path, query: query, cursor: cursor) }
    }

    func send(_ method: String, _ path: String, query: Query, body: (any Encodable)?, idempotencyKey: String?, timeout: TimeInterval?) async throws -> Data {
        let method = method.uppercased()
        var request = URLRequest(url: url(path, query: query))
        request.httpMethod = method
        request.timeoutInterval = timeout ?? self.timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("transcdr-swift/\(Self.version)", forHTTPHeaderField: "X-Transcdr-Client")
        let token = apiKey
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let idempotencyKey { request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try TranscdrCoding.encoder.encode(AnyEncodable(body))
        }

        let retryable = ["GET", "HEAD", "PUT", "DELETE", "OPTIONS"].contains(method) || idempotencyKey != nil
        let retries = retryable ? maxRetries : 0
        var attempt = 0
        while true {
            let response: HTTPResponse
            do {
                response = try await transport.send(request)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if (error as? URLError)?.code == .cancelled { throw CancellationError() }
                if attempt < retries {
                    try await Task.sleep(nanoseconds: backoff(attempt, retryAfter: nil))
                    attempt += 1
                    continue
                }
                let timedOut = (error as? URLError)?.code == .timedOut
                throw TranscdrError(
                    kind: .connection,
                    message: timedOut ? "The request timed out." : "Could not reach the Transcdr API: \(error.localizedDescription)"
                )
            }
            if (200..<300).contains(response.status) { return response.status == 204 ? Data() : response.body }
            if (response.status == 429 || response.status >= 500) && attempt < retries {
                try await Task.sleep(nanoseconds: backoff(attempt, retryAfter: response.header("retry-after")))
                attempt += 1
                continue
            }
            if response.status == 401, token != nil, !path.hasPrefix("/v1/auth/login"), !path.hasPrefix("/v1/auth/register") {
                onUnauthorized?()
            }
            throw TranscdrError.from(status: response.status, body: response.body, headers: response.headers)
        }
    }

    private func backoff(_ attempt: Int, retryAfter: String?) -> UInt64 {
        if let retryAfter, let seconds = Double(retryAfter), seconds >= 0 {
            return UInt64(min(seconds, 60) * 1e9)
        }
        let exp = min(retryDelay * pow(2, Double(attempt)), 8)
        return UInt64((exp / 2 + Double.random(in: 0...(exp / 2))) * 1e9)
    }

    private func describe(_ error: Error) -> String {
        switch error {
        case DecodingError.keyNotFound(let key, let ctx):
            return "missing \(path(ctx.codingPath + [key]))"
        case DecodingError.typeMismatch(_, let ctx), DecodingError.valueNotFound(_, let ctx):
            return "unexpected value at \(path(ctx.codingPath))"
        case DecodingError.dataCorrupted(let ctx):
            return ctx.debugDescription
        default:
            return error.localizedDescription
        }
    }

    private func path(_ keys: [CodingKey]) -> String {
        keys.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
    }
}

/// A random idempotency key.
public func newIdempotencyKey() -> String { UUID().uuidString.lowercased() }

/// An empty response.
public struct Empty: Codable, Sendable {
    public init() {}
}

struct AnyEncodable: Encodable {
    let value: any Encodable
    init(_ value: any Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}
