import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A raw HTTP response.
public struct HTTPResponse: Sendable {
    public let status: Int
    public let headers: [String: String]
    public let body: Data

    public init(status: Int, headers: [String: String], body: Data) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    public func header(_ name: String) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }
}

/// Upload progress: bytes sent of the total.
public struct UploadProgress: Sendable, Equatable {
    public let sent: Int64
    public let total: Int64
    public var fraction: Double { total > 0 ? min(1, Double(sent) / Double(total)) : 0 }

    public init(sent: Int64, total: Int64) {
        self.sent = sent
        self.total = total
    }
}

/// What sends requests. The default is `URLSessionTransport`; tests plug in
/// their own.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
    /// PUT (or POST) a file's bytes to `request.url`, reporting progress.
    func upload(_ request: URLRequest, fromFile file: URL, progress: (@Sendable (UploadProgress) -> Void)?) async throws -> HTTPResponse
}

public final class URLSessionTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request)
        return Self.wrap(response, data)
    }

    public func upload(_ request: URLRequest, fromFile file: URL, progress: (@Sendable (UploadProgress) -> Void)?) async throws -> HTTPResponse {
        #if canImport(Darwin)
        let delegate = ProgressDelegate(progress)
        let (data, response) = try await session.upload(for: request, fromFile: file, delegate: delegate)
        return Self.wrap(response, data)
        #else
        let data = try Data(contentsOf: file)
        let (body, response) = try await session.upload(for: request, from: data)
        progress?(UploadProgress(sent: Int64(data.count), total: Int64(data.count)))
        return Self.wrap(response, body)
        #endif
    }

    static func wrap(_ response: URLResponse, _ data: Data) -> HTTPResponse {
        let http = response as? HTTPURLResponse
        var headers: [String: String] = [:]
        for (k, v) in http?.allHeaderFields ?? [:] {
            if let k = k as? String, let v = v as? String { headers[k] = v }
        }
        return HTTPResponse(status: http?.statusCode ?? 0, headers: headers, body: data)
    }
}

#if canImport(Darwin)
private final class ProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let onProgress: (@Sendable (UploadProgress) -> Void)?

    init(_ onProgress: (@Sendable (UploadProgress) -> Void)?) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        onProgress?(UploadProgress(sent: totalBytesSent, total: totalBytesExpectedToSend))
    }
}
#endif
