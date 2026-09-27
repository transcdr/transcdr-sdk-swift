import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import TranscdrKit

/// A transport that answers from a script and records what it was sent.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    struct Sent {
        let method: String
        let url: URL
        let headers: [String: String]
        let body: Data?

        var json: JSONValue? { body.flatMap { try? JSONDecoder().decode(JSONValue.self, from: $0) } }
        func header(_ name: String) -> String? {
            headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
    }

    private let lock = NSLock()
    private var responses: [Result<HTTPResponse, Error>]
    private(set) var sent: [Sent] = []

    init(_ responses: [Result<HTTPResponse, Error>]) {
        self.responses = responses
    }

    static func json(_ status: Int = 200, _ body: String, headers: [String: String] = [:]) -> Result<HTTPResponse, Error> {
        .success(HTTPResponse(status: status, headers: ["Content-Type": "application/json"].merging(headers) { $1 }, body: Data(body.utf8)))
    }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        try lock.withLock {
            sent.append(Sent(
                method: request.httpMethod ?? "GET",
                url: request.url!,
                headers: request.allHTTPHeaderFields ?? [:],
                body: request.httpBody
            ))
            guard !responses.isEmpty else { return HTTPResponse(status: 500, headers: [:], body: Data()) }
            return try responses.removeFirst().get()
        }
    }

    func upload(_ request: URLRequest, fromFile file: URL, progress: (@Sendable (UploadProgress) -> Void)?) async throws -> HTTPResponse {
        try await send(request)
    }
}

func fixture(_ name: String) throws -> Data {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
        throw TranscdrError(kind: .unknown, message: "no fixture \(name)")
    }
    return try Data(contentsOf: url)
}

func decodeFixture<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
    try TranscdrCoding.decoder.decode(T.self, from: fixture(name))
}

func client(_ transport: MockTransport, key: String? = "tdk_test_key") -> Transcdr {
    Transcdr(apiKey: key, baseURL: URL(string: "https://api.example.test")!, transport: transport, maxRetries: 2, retryDelay: 0.001)
}
