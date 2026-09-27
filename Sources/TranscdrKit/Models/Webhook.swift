import Foundation

public enum EventType {
    public static let all = [
        "job.created", "job.scheduled", "job.started", "job.completed", "job.failed", "job.canceled",
        "asset.ready", "asset.deleted", "job.delivered", "job.delivery_failed", "automation.triggered",
        "connection.disabled", "webhook.test",
    ]
}

public struct WebhookEndpointType: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let https: Self = "https"
    public static let sns: Self = "sns"
    public static let sqs: Self = "sqs"
    public static let all: [Self] = [.https, .sns, .sqs]
}

/// AWS settings of an `sns` or `sqs` destination. The secret is never returned.
public struct WebhookAwsConfig: Codable, Hashable, Sendable {
    public var region: String
    public var accessKeyId: String
    public var endpoint: String?
    public var messageGroupId: String?
    public var secretAccessKeySet: Bool

    enum CodingKeys: String, CodingKey {
        case region, endpoint
        case accessKeyId = "access_key_id"
        case messageGroupId = "message_group_id"
        case secretAccessKeySet = "secret_access_key_set"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        region = try c.decodeIfPresent(String.self, forKey: .region) ?? ""
        accessKeyId = try c.decodeIfPresent(String.self, forKey: .accessKeyId) ?? ""
        endpoint = try c.decodeIfPresent(String.self, forKey: .endpoint)
        messageGroupId = try c.decodeIfPresent(String.self, forKey: .messageGroupId)
        secretAccessKeySet = try c.decodeIfPresent(Bool.self, forKey: .secretAccessKeySet) ?? true
    }
}

/// AWS settings sent on create, or on update (omit `secretAccessKey` to keep it).
public struct WebhookAwsParams: Encodable, Hashable, Sendable {
    public var accessKeyId: String?
    public var secretAccessKey: String?
    public var region: String?
    public var endpoint: String?
    public var messageGroupId: String?

    public init(accessKeyId: String? = nil, secretAccessKey: String? = nil, region: String? = nil, endpoint: String? = nil, messageGroupId: String? = nil) {
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.region = region
        self.endpoint = endpoint
        self.messageGroupId = messageGroupId
    }

    enum CodingKeys: String, CodingKey {
        case region, endpoint
        case accessKeyId = "access_key_id"
        case secretAccessKey = "secret_access_key"
        case messageGroupId = "message_group_id"
    }
}

/// An event destination: an HTTPS webhook, an SNS topic or an SQS queue.
public struct WebhookEndpoint: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var type: WebhookEndpointType
    /// The HTTPS URL; for sns/sqs the topic ARN or queue URL.
    public var url: String
    public var topicArn: String?
    public var queueUrl: String?
    public var aws: WebhookAwsConfig?
    public var description: String
    /// Event types, or `["*"]`.
    public var events: [String]
    public var enabled: Bool
    /// Only present on create and rotate.
    public var secret: String?
    public var createdAt: Date
    public var updatedAt: Date?
    public var lastDeliveryAt: Date?
    public var failureCount: Int
    /// The messaging connection events go through, if any.
    public var connectionId: String?

    enum CodingKeys: String, CodingKey {
        case id, type, url, aws, description, events, enabled, secret
        case topicArn = "topic_arn"
        case queueUrl = "queue_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastDeliveryAt = "last_delivery_at"
        case failureCount = "failure_count"
        case connectionId = "connection_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decodeIfPresent(WebhookEndpointType.self, forKey: .type) ?? .https
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        topicArn = try c.decodeIfPresent(String.self, forKey: .topicArn)
        queueUrl = try c.decodeIfPresent(String.self, forKey: .queueUrl)
        aws = try c.decodeIfPresent(WebhookAwsConfig.self, forKey: .aws)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        events = try c.decodeList([String].self, forKey: .events)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        secret = try c.decodeIfPresent(String.self, forKey: .secret)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        lastDeliveryAt = try c.decodeIfPresent(Date.self, forKey: .lastDeliveryAt)
        failureCount = try c.decodeIfPresent(Int.self, forKey: .failureCount) ?? 0
        connectionId = try c.decodeIfPresent(String.self, forKey: .connectionId)
    }

    /// Whether every event type is subscribed.
    public var allEvents: Bool { events.contains("*") }
}

/// How to create an event destination.
public enum WebhookCreateParams: Encodable, Sendable {
    case https(url: String, events: [String]? = nil, description: String? = nil)
    case sns(topicArn: String, aws: WebhookAwsParams, events: [String]? = nil, description: String? = nil)
    case sqs(queueUrl: String, aws: WebhookAwsParams, events: [String]? = nil, description: String? = nil)
    /// Through a messaging connection (`sqs`, `sns` or `webhook`).
    case connection(id: String, events: [String]? = nil, description: String? = nil)

    enum CodingKeys: String, CodingKey {
        case type, url, aws, events, description
        case topicArn = "topic_arn"
        case queueUrl = "queue_url"
        case connectionId = "connection_id"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .https(let url, let events, let description):
            try c.encode("https", forKey: .type)
            try c.encode(url, forKey: .url)
            try c.encodeIfPresent(events, forKey: .events)
            try c.encodeIfPresent(description, forKey: .description)
        case .sns(let arn, let aws, let events, let description):
            try c.encode("sns", forKey: .type)
            try c.encode(arn, forKey: .topicArn)
            try c.encode(aws, forKey: .aws)
            try c.encodeIfPresent(events, forKey: .events)
            try c.encodeIfPresent(description, forKey: .description)
        case .sqs(let queue, let aws, let events, let description):
            try c.encode("sqs", forKey: .type)
            try c.encode(queue, forKey: .queueUrl)
            try c.encode(aws, forKey: .aws)
            try c.encodeIfPresent(events, forKey: .events)
            try c.encodeIfPresent(description, forKey: .description)
        case .connection(let id, let events, let description):
            try c.encode(id, forKey: .connectionId)
            try c.encodeIfPresent(events, forKey: .events)
            try c.encodeIfPresent(description, forKey: .description)
        }
    }
}

/// `type` cannot change after creation.
public struct WebhookUpdateParams: Encodable, Sendable {
    public var url: String?
    public var topicArn: String?
    public var queueUrl: String?
    public var aws: WebhookAwsParams?
    public var events: [String]?
    public var description: String?
    public var enabled: Bool?

    public init(url: String? = nil, topicArn: String? = nil, queueUrl: String? = nil, aws: WebhookAwsParams? = nil, events: [String]? = nil, description: String? = nil, enabled: Bool? = nil) {
        self.url = url
        self.topicArn = topicArn
        self.queueUrl = queueUrl
        self.aws = aws
        self.events = events
        self.description = description
        self.enabled = enabled
    }

    enum CodingKeys: String, CodingKey {
        case url, aws, events, description, enabled
        case topicArn = "topic_arn"
        case queueUrl = "queue_url"
    }
}

public struct WebhookDelivery: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var endpointId: String
    public var eventId: String
    public var eventType: String
    /// `pending`, `succeeded` or `failed`.
    public var status: String
    public var attempts: Int
    public var responseStatus: Int?
    public var responseBody: String?
    public var durationMs: Int?
    public var nextRetryAt: Date?
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, status, attempts
        case endpointId = "endpoint_id"
        case eventId = "event_id"
        case eventType = "event_type"
        case responseStatus = "response_status"
        case responseBody = "response_body"
        case durationMs = "duration_ms"
        case nextRetryAt = "next_retry_at"
        case createdAt = "created_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        endpointId = try c.decodeIfPresent(String.self, forKey: .endpointId) ?? ""
        eventId = try c.decodeIfPresent(String.self, forKey: .eventId) ?? ""
        eventType = try c.decodeIfPresent(String.self, forKey: .eventType) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "pending"
        attempts = try c.decodeIfPresent(Int.self, forKey: .attempts) ?? 0
        responseStatus = try c.decodeIfPresent(Int.self, forKey: .responseStatus)
        responseBody = try c.decodeIfPresent(String.self, forKey: .responseBody)
        durationMs = try c.decodeIfPresent(Int.self, forKey: .durationMs)
        nextRetryAt = try c.decodeIfPresent(Date.self, forKey: .nextRetryAt)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }
}

/// An event, as delivered to endpoints and listed by `GET /v1/events`.
public struct Event: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var type: String
    public var createdAt: Date
    /// `data.object`: a job, an asset, or another object.
    public var object: JSONValue

    enum CodingKeys: String, CodingKey {
        case id, type, data
        case createdAt = "created_at"
    }

    enum DataKeys: String, CodingKey { case object }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        let data = try? c.nestedContainer(keyedBy: DataKeys.self, forKey: .data)
        object = (try? data?.decodeIfPresent(JSONValue.self, forKey: .object)) ?? .null
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(type, forKey: .type)
        try c.encode(createdAt, forKey: .createdAt)
        var d = c.nestedContainer(keyedBy: DataKeys.self, forKey: .data)
        try d.encode(object, forKey: .object)
    }

    /// The object's id (`job_…`, `ast_…`, `con_…`), when it has one.
    public var objectId: String? { object["id"]?.stringValue }
}

/// The result of `webhooks.test`: a delivery, or the event it sent.
public struct WebhookTestResult: Decodable, Sendable {
    public var delivery: WebhookDelivery?
    public var event: Event?

    public init(from decoder: Decoder) throws {
        delivery = try? WebhookDelivery(from: decoder)
        event = delivery == nil ? try? Event(from: decoder) : nil
    }
}
