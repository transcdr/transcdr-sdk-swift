import Foundation

/// Every error the client throws. `kind` mirrors the API's `error.type`.
public struct TranscdrError: Error, LocalizedError, Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        /// 400, 404, 409, 422: the request was wrong.
        case invalidRequest = "invalid_request_error"
        /// 401: missing, invalid, expired or revoked token.
        case authentication = "authentication_error"
        /// 403: the key lacks a scope, or the user lacks a role.
        case permission = "permission_error"
        /// 429.
        case rateLimit = "rate_limit_error"
        /// 402: `insufficient_credit`, `cost_limit_exceeded`, `spend_limit_reached`.
        case quota = "quota_error"
        /// 5xx.
        case api = "api_error"
        /// No response: DNS, TLS, reset or timeout.
        case connection = "connection_error"
        /// `jobs.waitFor` gave up.
        case waitTimeout = "wait_timeout"
        /// A response the client could not decode.
        case decoding = "decoding_error"
        case unknown
    }

    public let kind: Kind
    /// HTTP status; 0 when no response arrived.
    public let status: Int
    public let message: String
    /// Machine-readable code, e.g. `validation_failed`.
    public let code: String?
    /// The offending parameter in dotted form, e.g. `output.renditions.0.width`.
    public let param: String?
    /// Per-field validation messages, keyed by dotted param.
    public let details: [String: [String]]
    public let requestId: String?
    /// Seconds to wait, from `Retry-After`, on 429.
    public let retryAfter: Double?

    public init(
        kind: Kind, status: Int = 0, message: String, code: String? = nil, param: String? = nil,
        details: [String: [String]] = [:], requestId: String? = nil, retryAfter: Double? = nil
    ) {
        self.kind = kind
        self.status = status
        self.message = message
        self.code = code
        self.param = param
        self.details = details
        self.requestId = requestId
        self.retryAfter = retryAfter
    }

    public var errorDescription: String? { message }

    /// Field errors of a 422, keyed by dotted param, including `param` itself.
    public var fieldErrors: [String: String] {
        var out: [String: String] = [:]
        for (key, messages) in details { if let first = messages.first { out[key] = first } }
        if let param, out[param] == nil { out[param] = message }
        return out
    }

    /// Build the error for a failed response.
    static func from(status: Int, body: Data, headers: [String: String]) -> TranscdrError {
        struct Envelope: Decodable {
            struct Body: Decodable {
                let type: String?
                let code: String?
                let message: String?
                let param: String?
                let details: [String: [String]]?
                let request_id: String?
            }
            let error: Body?
        }
        let envelope = try? JSONDecoder().decode(Envelope.self, from: body)
        let e = envelope?.error
        let text = String(decoding: body.prefix(500), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let kind = e?.type.flatMap(Kind.init(rawValue:)) ?? defaultKind(status)
        let retry = headers.first { $0.key.lowercased() == "retry-after" }.flatMap { Double($0.value) }
        return TranscdrError(
            kind: kind,
            status: status,
            message: e?.message ?? (text.isEmpty ? "Request failed with status \(status)" : text),
            code: e?.code,
            param: e?.param,
            details: e?.details ?? [:],
            requestId: e?.request_id ?? headers.first { $0.key.lowercased() == "x-request-id" }?.value,
            retryAfter: retry
        )
    }

    static func defaultKind(_ status: Int) -> Kind {
        switch status {
        case 401: return .authentication
        case 402: return .quota
        case 403: return .permission
        case 429: return .rateLimit
        case 500...: return .api
        case 400..<500: return .invalidRequest
        default: return .unknown
        }
    }
}

/// A human message for any thrown error, preferring the API's own.
public func errorMessage(_ error: Error, fallback: String = "Something went wrong.") -> String {
    if let e = error as? TranscdrError { return e.message.isEmpty ? fallback : e.message }
    if error is CancellationError { return "Cancelled." }
    let text = (error as NSError).localizedDescription
    return text.isEmpty ? fallback : text
}
