import Foundation

/// Event destinations: the `/v1/webhooks` resource, which sends to HTTPS,
/// Amazon SNS or Amazon SQS, directly or through a messaging connection.
/// The web dashboard's `destinations.ts` and the destination providers of `wizard.ts`.
public enum Destinations {
    // MARK: Metadata

    public struct Meta: Hashable, Sendable, Identifiable {
        public let type: WebhookEndpointType
        public let label: String
        /// Short badge text.
        public let short: String
        public let description: String
        /// Label of the target field.
        public let targetLabel: String
        public let placeholder: String
        public let hint: String
        public var id: String { type.rawValue }
    }

    public static let all: [Meta] = [
        Meta(
            type: .https, label: "HTTPS webhook", short: "HTTPS",
            description: "A signed POST to your server.",
            targetLabel: "Endpoint URL", placeholder: "https://example.com/hooks/transcdr",
            hint: "Must be a public https:// URL."
        ),
        Meta(
            type: .sns, label: "Amazon SNS", short: "SNS",
            description: "Publish to a topic; fan out to email, SQS, Lambda.",
            targetLabel: "Topic ARN", placeholder: "arn:aws:sns:us-east-1:123456789012:transcdr-events",
            hint: "Standard or FIFO (.fifo) topic. The key needs sns:Publish on it."
        ),
        Meta(
            type: .sqs, label: "Amazon SQS", short: "SQS",
            description: "Send to a queue your workers or Lambda consume.",
            targetLabel: "Queue URL", placeholder: "https://sqs.us-east-1.amazonaws.com/123456789012/transcdr-events",
            hint: "Standard or FIFO (.fifo) queue. The key needs sqs:SendMessage on it."
        ),
    ]

    /// The metadata of a type; an unknown type reads as HTTPS.
    public static func meta(_ type: WebhookEndpointType?) -> Meta {
        all.first { $0.type == type } ?? all[0]
    }

    /// The HTTPS URL, topic ARN or queue URL.
    public static func target(of endpoint: WebhookEndpoint) -> String {
        switch endpoint.type {
        case .sns: return endpoint.topicArn ?? endpoint.url
        case .sqs: return endpoint.queueUrl ?? endpoint.url
        default: return endpoint.url
        }
    }

    /// The region in a topic ARN or an AWS queue URL, if it has one.
    public static func region(fromTarget target: String, type: WebhookEndpointType) -> String? {
        let value = target.trimmingCharacters(in: .whitespacesAndNewlines)
        switch type {
        case .sns: return firstMatch(#"^arn:aws[\w-]*:sns:([a-z0-9-]+):"#, in: value)?.first
        case .sqs: return firstMatch(#"^https://sqs[.-]([a-z0-9-]+)\.amazonaws\.com"#, in: value)?.first
        default: return nil
        }
    }

    /// A FIFO topic or queue: its name ends in `.fifo`.
    public static func isFifo(_ target: String) -> Bool {
        var value = target.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        return value.hasSuffix(".fifo")
    }

    /// `arn:aws:sqs:<region>:<account>:<name>` from a queue URL.
    public static func queueArn(_ queueUrl: String) -> String? {
        let value = queueUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let m = firstMatch(#"^https://sqs[.-]([a-z0-9-]+)\.amazonaws\.com/(\d{12})/([^/?#]+)"#, in: value), m.count == 3 else { return nil }
        return "arn:aws:sqs:\(m[0]):\(m[1]):\(m[2])"
    }

    // MARK: Form

    /// Form state shared by the wizard and the detail screen.
    public struct Form: Hashable, Sendable {
        public var type: WebhookEndpointType
        public var target: String
        public var accessKeyId: String
        /// Write-only. Blank on edit means "keep the stored key".
        public var secretAccessKey: String
        public var region: String
        public var endpoint: String
        public var messageGroupId: String

        public init(
            type: WebhookEndpointType = .https, target: String = "", accessKeyId: String = "", secretAccessKey: String = "",
            region: String = "", endpoint: String = "", messageGroupId: String = ""
        ) {
            self.type = type
            self.target = target
            self.accessKeyId = accessKeyId
            self.secretAccessKey = secretAccessKey
            self.region = region
            self.endpoint = endpoint
            self.messageGroupId = messageGroupId
        }

        /// The form for a saved endpoint. Never copies a secret: the API does not return one.
        public init(endpoint e: WebhookEndpoint) {
            let target = Destinations.target(of: e)
            let aws = e.aws
            // Leave a region that merely echoes the ARN / queue URL blank, so it keeps following the target.
            let stored = aws?.region ?? ""
            let region = !stored.isEmpty && stored != Destinations.region(fromTarget: target, type: e.type) ? stored : ""
            self.init(
                type: e.type, target: target, accessKeyId: aws?.accessKeyId ?? "", secretAccessKey: "",
                region: region, endpoint: aws?.endpoint ?? "", messageGroupId: aws?.messageGroupId ?? ""
            )
        }

        /// SNS or SQS: needs AWS credentials.
        public var isAws: Bool { type == .sns || type == .sqs }
        public var isFifo: Bool { isAws && Destinations.isFifo(target) }
        /// The region the target implies, shown as the region field's placeholder.
        public var derivedRegion: String? { Destinations.region(fromTarget: target, type: type) }

        /// Whether the required fields are filled. `requireSecret` on create only.
        public func isComplete(requireSecret: Bool) -> Bool {
            guard !trim(target).isEmpty else { return false }
            if !isAws { return true }
            return !trim(accessKeyId).isEmpty && (!requireSecret || !trim(secretAccessKey).isEmpty)
        }

        /// The body of `POST /v1/webhooks` (and of its check).
        public func createParams(events: [String], description: String) -> WebhookCreateParams {
            let desc = opt(description)
            let target = trim(self.target)
            switch type {
            case .sns: return .sns(topicArn: target, aws: createAws, events: events, description: desc)
            case .sqs: return .sqs(queueUrl: target, aws: createAws, events: events, description: desc)
            default: return .https(url: target, events: events, description: desc)
            }
        }

        private var createAws: WebhookAwsParams {
            WebhookAwsParams(
                accessKeyId: trim(accessKeyId), secretAccessKey: trim(secretAccessKey), region: opt(region),
                endpoint: opt(endpoint), messageGroupId: Destinations.isFifo(target) ? opt(messageGroupId) : nil
            )
        }

        /// The destination part of a PATCH. `type` is fixed; a blank secret keeps the stored one.
        /// (The API keeps a stored endpoint or message group when they are left out.)
        public func updateParams() -> WebhookUpdateParams {
            let target = trim(self.target)
            guard isAws else { return WebhookUpdateParams(url: target) }
            let aws = WebhookAwsParams(
                accessKeyId: trim(accessKeyId), secretAccessKey: opt(secretAccessKey), region: opt(region),
                endpoint: opt(endpoint), messageGroupId: Destinations.isFifo(target) ? opt(messageGroupId) : nil
            )
            return type == .sns ? WebhookUpdateParams(topicArn: target, aws: aws) : WebhookUpdateParams(queueUrl: target, aws: aws)
        }

        /// A check without credentials, which returns the exact setup (policy)
        /// for this topic or queue. Nothing is published. Nil for HTTPS or a blank target.
        public func setupCheckParams(events: [String]) -> WebhookCreateParams? {
            let target = trim(self.target)
            guard isAws, !target.isEmpty else { return nil }
            let aws = WebhookAwsParams(accessKeyId: "", secretAccessKey: "")
            return type == .sns ? .sns(topicArn: target, aws: aws, events: events) : .sqs(queueUrl: target, aws: aws, events: events)
        }
    }

    /// Map API field errors (`url`, `topic_arn`, `queue_url`, `aws.access_key_id`, …)
    /// onto the form's keys: `target`, `access_key_id`, `secret_access_key`,
    /// `region`, `endpoint`, `message_group_id`, and the rest unchanged (`events`, …).
    public static func formErrors(_ fields: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for (key, message) in fields {
            let bare = key.hasPrefix("aws.") ? String(key.dropFirst(4)) : key
            out[["url", "topic_arn", "queue_url"].contains(bare) ? "target" : bare] = message
        }
        return out
    }

    // MARK: Events

    /// The event types a destination can subscribe to (every endpoint also gets `webhook.test`).
    public static var subscribableEvents: [String] { EventType.all.filter { $0 != "webhook.test" } }
    /// What a new destination subscribes to.
    public static let defaultEvents = ["job.completed", "job.failed"]

    /// `all events` or `3 events`.
    public static func eventsSummary(_ events: [String]) -> String {
        events.contains("*") ? "All events" : "\(events.count) event\(events.count == 1 ? "" : "s")"
    }

    // MARK: Setup guidance

    public struct Link: Hashable, Sendable {
        public let label: String
        /// An absolute URL, or a path on the web dashboard (`/docs/webhooks`).
        public let href: String
        public var isExternal: Bool { href.hasPrefix("https://") || href.hasPrefix("http://") }
    }

    /// One thing to do in the provider's own console before saving.
    public struct PrepareStep: Hashable, Sendable, Identifiable {
        public let title: String
        public let body: String
        public let links: [Link]
        public var id: String { title }
    }

    public struct Provider: Hashable, Sendable, Identifiable {
        public let type: WebhookEndpointType
        public let label: String
        public let tagline: String
        public var id: String { type.rawValue }
    }

    /// The wizard's first step: where events go.
    public static let providers: [Provider] = [
        Provider(type: .https, label: "HTTPS webhook", tagline: "A signed POST to your server for each event."),
        Provider(type: .sns, label: "Amazon SNS", tagline: "Publish to a topic; fan out to email, SQS, Lambda and more."),
        Provider(type: .sqs, label: "Amazon SQS", tagline: "Send to a queue your workers or Lambda functions consume."),
    ]

    public static func provider(_ type: WebhookEndpointType?) -> Provider? {
        providers.first { $0.type == type }
    }

    /// What to prepare for a destination of `type` (links carry the target's region).
    public static func prepare(_ type: WebhookEndpointType, target: String) -> [PrepareStep] {
        switch type {
        case .sns:
            let region = regionQuery(target, type: .sns)
            return [
                PrepareStep(
                    title: "Create a topic",
                    body: "Standard, or FIFO (name ends in .fifo) if subscribers need events in order. Copy its ARN.",
                    links: [
                        Link(label: "Create a topic", href: "https://console.aws.amazon.com/sns/v3/home\(region)#/create-topic"),
                        Link(label: "Your topics", href: "https://console.aws.amazon.com/sns/v3/home\(region)#/topics"),
                    ]
                ),
            ] + iamSteps("sns:Publish on this topic")
        case .sqs:
            let region = regionQuery(target, type: .sqs)
            return [
                PrepareStep(
                    title: "Create a queue",
                    body: "Standard, or FIFO (name ends in .fifo) for ordered, deduplicated events. Copy its URL.",
                    links: [
                        Link(label: "Create a queue", href: "https://console.aws.amazon.com/sqs/v3/home\(region)#/create-queue"),
                        Link(label: "Your queues", href: "https://console.aws.amazon.com/sqs/v3/home\(region)#/queues"),
                    ]
                ),
            ] + iamSteps("sqs:SendMessage on this queue")
        default:
            return httpsPrepare
        }
    }

    static let httpsPrepare: [PrepareStep] = [
        PrepareStep(
            title: "Expose an https endpoint",
            body: "A public URL with a valid certificate that accepts POST requests with a JSON body. Hosts on private networks are refused.",
            links: []
        ),
        PrepareStep(
            title: "Answer quickly with a 2xx",
            body: "Return any 2xx status within a few seconds, then do the work in the background. Anything else is retried with backoff for up to a day.",
            links: []
        ),
        PrepareStep(
            title: "Verify the signature",
            body: "Every delivery carries a Transcdr-Signature header. You get the signing secret once, after saving; check it before trusting the body.",
            links: [Link(label: "Verifying signatures", href: "/docs/webhooks")]
        ),
    ]

    static func iamSteps(_ what: String) -> [PrepareStep] {
        [
            PrepareStep(
                title: "Create a policy",
                body: "In IAM, create a policy from the JSON below (use the JSON tab). It allows only \(what).",
                links: [Link(label: "Create a policy", href: "https://console.aws.amazon.com/iam/home#/policies/create")]
            ),
            PrepareStep(
                title: "Create a user and an access key",
                body: "Create an IAM user without console access, attach the policy, then create an access key for \"Application running outside AWS\".",
                links: [
                    Link(label: "Create a user", href: "https://console.aws.amazon.com/iam/home#/users/create"),
                    Link(label: "IAM users", href: "https://console.aws.amazon.com/iam/home#/users"),
                ]
            ),
        ]
    }

    static func regionQuery(_ target: String, type: WebhookEndpointType) -> String {
        region(fromTarget: target, type: type).map { "?region=\($0)" } ?? ""
    }

    /// The least-privilege IAM policy for publishing to a topic or sending to a queue.
    public static func iamPolicy(_ type: WebhookEndpointType, target: String) -> JSONValue? {
        let target = target.trimmingCharacters(in: .whitespacesAndNewlines)
        switch type {
        case .sns:
            return publishPolicy("sns:Publish", sid: "TranscdrPublish", resource: target.isEmpty ? "arn:aws:sns:<region>:<account-id>:<topic>" : target)
        case .sqs:
            return publishPolicy("sqs:SendMessage", sid: "TranscdrSend", resource: queueArn(target) ?? "arn:aws:sqs:<region>:<account-id>:<queue>")
        default:
            return nil
        }
    }

    static func publishPolicy(_ action: String, sid: String, resource: String) -> JSONValue {
        [
            "Version": "2012-10-17",
            "Statement": [["Sid": .string(sid), "Effect": "Allow", "Action": .string(action), "Resource": .string(resource)]],
        ]
    }

    /// The setup shown until the live one comes back from the check, in the
    /// shape of `CheckReport.setup` (`summary`, `iam_policy`, `kms`). Nil for HTTPS.
    public static func setupTemplate(_ type: WebhookEndpointType, target: String) -> JSONValue? {
        guard let policy = iamPolicy(type, target: target) else { return nil }
        let what = type == .sns ? "topic" : "queue"
        return [
            "summary": "Create an IAM user with this policy, then an access key for it.",
            "iam_policy": policy,
            "kms": .string("If the \(what) is encrypted with a customer-managed KMS key, also allow kms:GenerateDataKey and kms:Decrypt on that key."),
        ]
    }

    // MARK: Connections

    /// Messaging connections events can go through (`sqs`, `sns`, `webhook`).
    public static func eventConnections(_ connections: [Connection]) -> [Connection] {
        connections.filter { $0.isMessaging && ConnectionKind.messaging.contains($0.kind) }
    }

    /// The queue URL, topic ARN or URL a messaging connection sends to.
    public static func connectionTarget(_ connection: Connection) -> String {
        switch connection.kind {
        case .sqs: return connection.config.queueUrl ?? "?"
        case .sns: return connection.config.topicArn ?? "?"
        case .webhook: return connection.config.url ?? "?"
        default: return connection.config.endpoint ?? connection.config.bucket ?? connection.config.host ?? "?"
        }
    }

    /// `Amazon SQS`, `Amazon SNS`, `Webhook`.
    public static func connectionKindLabel(_ kind: ConnectionKind) -> String {
        switch kind {
        case .sqs: return "Amazon SQS"
        case .sns: return "Amazon SNS"
        case .webhook: return "Webhook"
        default: return kind.rawValue
        }
    }

    // MARK: Events log

    /// Where an event's object lives in the app, by its id prefix.
    public enum ObjectLink: Hashable, Sendable {
        case job(String)
        case asset(String)
    }

    public static func objectLink(_ objectId: String?) -> ObjectLink? {
        guard let id = objectId else { return nil }
        if id.hasPrefix("job_") { return .job(id) }
        if id.hasPrefix("ast_") { return .asset(id) }
        return nil
    }
}

private func trim(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
private func opt(_ s: String) -> String? {
    let t = trim(s)
    return t.isEmpty ? nil : t
}

/// The capture groups of the first match of `pattern`, or nil.
private func firstMatch(_ pattern: String, in value: String) -> [String]? {
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(value.startIndex..., in: value)
    guard let match = regex.firstMatch(in: value, range: range) else { return nil }
    return (1..<match.numberOfRanges).compactMap { i in
        Range(match.range(at: i), in: value).map { String(value[$0]) }
    }
}
