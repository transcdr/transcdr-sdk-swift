import Foundation

// The connection catalog, ported from the web dashboard's `wizard.ts` and
// `integrations.ts`: one setup wizard per provider (what to prepare in its own
// console, which fields it needs, how the form becomes an API body, and a
// templated setup shown until the live one comes back from the check), the
// per-kind metadata used by lists and the edit form, and the small helpers the
// integration screens share. Pure data and functions: no UI.

// MARK: - Form values

/// One form value: text (numbers are text too) or a checkbox.
public enum FieldValue: Hashable, Sendable {
    case text(String)
    case flag(Bool)
}

/// A wizard's form values, keyed by field: text through `values[text: key]`,
/// checkboxes through `values[flag: key]`.
public struct ProviderValues: Hashable, Sendable, ExpressibleByDictionaryLiteral {
    public var storage: [String: FieldValue]

    public init(_ storage: [String: FieldValue] = [:]) { self.storage = storage }

    public init(dictionaryLiteral elements: (String, FieldValue)...) {
        storage = Dictionary(elements, uniquingKeysWith: { _, last in last })
    }

    /// The raw text of a field ("" for a checkbox or an unset field).
    public subscript(text key: String) -> String {
        get { if case .text(let s) = storage[key] { return s }; return "" }
        set { storage[key] = .text(newValue) }
    }

    /// Whether a checkbox is on.
    public subscript(flag key: String) -> Bool {
        get { storage[key] == .flag(true) }
        set { storage[key] = .flag(newValue) }
    }

    /// The trimmed text of a field.
    public func string(_ key: String) -> String { self[text: key].trimmingCharacters(in: .whitespacesAndNewlines) }
    /// The trimmed text, or nil when empty.
    public func optional(_ key: String) -> String? { let s = string(key); return s.isEmpty ? nil : s }
    /// A number field, nil when empty or unreadable.
    public func int(_ key: String) -> Int? { Int(string(key)) }
    /// A checkbox that is explicitly off (not merely unset).
    public func isOff(_ key: String) -> Bool { storage[key] == .flag(false) }
}

// MARK: - Catalog types

public struct FieldOption: Hashable, Sendable, Identifiable {
    public let value: String
    public let label: String
    public var id: String { value }

    public init(_ value: String, _ label: String) {
        self.value = value
        self.label = label
    }
}

public struct ProviderField: Sendable, Identifiable {
    public enum FieldType: String, Sendable {
        case text, password, textarea, select, checkbox, number, url
    }

    public let key: String
    public let label: String
    public var type: FieldType = .text
    /// Credentials are write-only and grouped separately.
    public var secret = false
    public var required = false
    public var placeholder: String?
    public var hint: String?
    public var options: [FieldOption] = []
    /// Only shown (and only required) when this returns true.
    public var when: (@Sendable (ProviderValues) -> Bool)?
    /// A file can fill this field (e.g. a service account JSON key): the accepted extensions.
    public var acceptsFiles: [String] = []
    /// Hidden behind "Advanced".
    public var advanced = false

    public var id: String { key }

    public func isVisible(_ values: ProviderValues) -> Bool { when?(values) ?? true }
}

public struct PrepareLink: Hashable, Sendable, Identifiable {
    public let label: String
    /// An absolute URL, or a dashboard path such as `/docs/webhooks`.
    public let href: String
    public var id: String { href }

    public init(_ label: String, _ href: String) {
        self.label = label
        self.href = href
    }

    public var isExternal: Bool { href.hasPrefix("http://") || href.hasPrefix("https://") }
}

public struct PrepareStep: Hashable, Sendable, Identifiable {
    public let title: String
    public let body: String
    public var links: [PrepareLink] = []
    public var code: String?
    public var lang: String?
    public var id: String { title }

    public init(title: String, body: String, links: [PrepareLink] = [], code: String? = nil, lang: String? = nil) {
        self.title = title
        self.body = body
        self.links = links
        self.code = code
        self.lang = lang
    }
}

/// A storage role a connection can serve.
public struct ConnectionRole: Hashable, Sendable, Identifiable {
    /// `source`, `watch_folder` or `destination` (as in the check's `roles`).
    public let key: String
    public let label: String
    public let description: String
    public var id: String { key }
}

/// Tiles are grouped: storage holds files, messaging carries events and queue triggers.
public enum ProviderGroup: String, CaseIterable, Sendable, Identifiable {
    case storage, messaging
    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .storage: "Storage"
        case .messaging: "Messaging"
        }
    }

    public var description: String {
        switch self {
        case .storage: "Where inputs come from and outputs go."
        case .messaging: "Queues, topics and webhooks: trigger automations and receive events."
        }
    }
}

/// One setup wizard: a provider (AWS S3, R2, B2…), not just a kind.
public struct ConnectionProvider: Sendable, Identifiable {
    public let id: String
    public let label: String
    public let kind: ConnectionKind
    public let group: ProviderGroup
    public let tagline: String
    /// Storage role keys the provider can serve at all (none for messaging).
    public let roles: [String]
    /// Messaging only: the role the check must confirm (`trigger` or `notifications`).
    public var messagingRole: String?
    /// Messaging only: what the connection is for.
    public var uses: [String] = []
    public let defaults: ProviderValues
    public let fields: [ProviderField]
    /// Fields that scope the setup (bucket, container…), asked for on the Prepare step.
    public var scopeFields: [String] = []
    let suggestNameFn: @Sendable (ProviderValues) -> String
    let prepareFn: @Sendable (ProviderValues) -> [PrepareStep]
    var templateFn: (@Sendable (ProviderValues) -> JSONValue?)?
    var setupReadyFn: (@Sendable (ProviderValues) -> Bool)?
    let buildFn: @Sendable (ProviderValues) -> ConnectionCreateParams

    public var isMessaging: Bool { group == .messaging }

    /// A name suggested from the details.
    public func suggestName(_ values: ProviderValues) -> String { suggestNameFn(values) }
    /// What to do in the provider's own console.
    public func prepare(_ values: ProviderValues) -> [PrepareStep] { prepareFn(values) }
    /// A templated setup (policy, role…) shown until the live one arrives.
    public func template(_ values: ProviderValues) -> JSONValue? { templateFn?(values) }
    /// Whether enough is known to fetch the live setup from the check endpoint.
    public func setupReady(_ values: ProviderValues) -> Bool { setupReadyFn?(values) ?? false }
    /// The API body (without a name) for these values.
    public func build(_ values: ProviderValues, name: String? = nil) -> ConnectionCreateParams {
        var params = buildFn(values)
        params.name = name
        return params
    }

    /// The fields for these values, by section.
    public func settingsFields(_ values: ProviderValues) -> [ProviderField] {
        ConnectionProviders.visibleFields(fields, values).filter { !$0.secret && !$0.advanced }
    }
    public func credentialFields(_ values: ProviderValues) -> [ProviderField] {
        ConnectionProviders.visibleFields(fields, values).filter { $0.secret && !$0.advanced }
    }
    public func advancedFields(_ values: ProviderValues) -> [ProviderField] {
        ConnectionProviders.visibleFields(fields, values).filter(\.advanced)
    }
    public func field(_ key: String) -> ProviderField? { fields.first { $0.key == key } }
}

// MARK: - Providers

public enum ConnectionProviders {
    public static let roles: [ConnectionRole] = [
        ConnectionRole(key: "source", label: "Source", description: "Read input files from it."),
        ConnectionRole(key: "watch_folder", label: "Watch folder", description: "Watch it for new files and transcode them automatically."),
        ConnectionRole(key: "destination", label: "Destination", description: "Deliver finished outputs to it."),
    ]

    public static let awsRegions: [FieldOption] = [
        ("us-east-1", "US East (N. Virginia)"),
        ("us-east-2", "US East (Ohio)"),
        ("us-west-1", "US West (N. California)"),
        ("us-west-2", "US West (Oregon)"),
        ("ca-central-1", "Canada (Central)"),
        ("sa-east-1", "South America (São Paulo)"),
        ("eu-west-1", "Europe (Ireland)"),
        ("eu-west-2", "Europe (London)"),
        ("eu-west-3", "Europe (Paris)"),
        ("eu-central-1", "Europe (Frankfurt)"),
        ("eu-central-2", "Europe (Zurich)"),
        ("eu-north-1", "Europe (Stockholm)"),
        ("eu-south-1", "Europe (Milan)"),
        ("eu-south-2", "Europe (Spain)"),
        ("me-central-1", "Middle East (UAE)"),
        ("il-central-1", "Israel (Tel Aviv)"),
        ("af-south-1", "Africa (Cape Town)"),
        ("ap-south-1", "Asia Pacific (Mumbai)"),
        ("ap-south-2", "Asia Pacific (Hyderabad)"),
        ("ap-northeast-1", "Asia Pacific (Tokyo)"),
        ("ap-northeast-2", "Asia Pacific (Seoul)"),
        ("ap-northeast-3", "Asia Pacific (Osaka)"),
        ("ap-southeast-1", "Asia Pacific (Singapore)"),
        ("ap-southeast-2", "Asia Pacific (Sydney)"),
        ("ap-southeast-3", "Asia Pacific (Jakarta)"),
        ("ap-east-1", "Asia Pacific (Hong Kong)"),
    ].map { FieldOption($0.0, "\($0.1) · \($0.0)") }

    public static let b2Regions: [FieldOption] = [
        ("us-west-000", "US West"),
        ("us-west-001", "US West"),
        ("us-west-002", "US West"),
        ("us-west-004", "US West"),
        ("us-east-005", "US East"),
        ("eu-central-003", "EU Central"),
    ].map { FieldOption($0.0, "\($0.1) · \($0.0)") }

    // MARK: Helpers

    /// `videos/` → `videos/`, `/videos` → `videos/`, `` → ``.
    public static func normalizeRoot(_ root: String) -> String {
        var trimmed = Substring(root.trimmingCharacters(in: .whitespacesAndNewlines))
        while trimmed.hasPrefix("/") { trimmed = trimmed.dropFirst() }
        return !trimmed.isEmpty && !trimmed.hasSuffix("/") ? "\(trimmed)/" : String(trimmed)
    }

    static func rootOrNil(_ v: ProviderValues) -> String? {
        let r = normalizeRoot(v.string("root"))
        return r.isEmpty ? nil : r
    }

    /// Keep only the secrets that were filled in.
    static func secrets(_ v: ProviderValues, _ keys: [String]) -> ConnectionSecrets {
        var out = ConnectionSecrets()
        for key in keys where !v.string(key).isEmpty { out.set(key, v.string(key)) }
        return out
    }

    /// The first match's capture groups (group 0 excluded); nil without a match.
    static func captures(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        return (1..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: text).map { String(text[$0]) } ?? ""
        }
    }

    /// The host (with its port) of a URL, or "".
    public static func hostOf(_ url: String) -> String {
        guard let c = URLComponents(string: url), c.scheme != nil, let host = c.host, !host.isEmpty else { return "" }
        return c.port.map { "\(host):\($0)" } ?? host
    }

    /// The Cloudflare R2 S3 endpoint for an account ID.
    public static func r2Endpoint(_ accountId: String) -> String? {
        let id = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? nil : "https://\(id).r2.cloudflarestorage.com"
    }

    /// `arn:aws:sqs:<region>:<account>:<name>` from a queue URL.
    public static func queueArn(_ queueUrl: String) -> String? {
        let url = queueUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let g = captures(#"^https://sqs[.-]([a-z0-9-]+)\.amazonaws\.com/(\d{12})/([^/?#]+)"#, in: url) else { return nil }
        return "arn:aws:sqs:\(g[0]):\(g[1]):\(g[2])"
    }

    /// The queue name: the last segment of its URL.
    public static func queueName(_ queueUrl: String) -> String {
        captures(#"/\d{12}/([^/?#]+)"#, in: queueUrl)?.first ?? ""
    }

    public static func queueRegion(_ queueUrl: String) -> String? {
        captures(#"^https://sqs[.-]([a-z0-9-]+)\.amazonaws\.com"#, in: queueUrl.trimmingCharacters(in: .whitespacesAndNewlines))?.first
    }

    public static func topicRegion(_ topicArn: String) -> String? {
        captures(#"^arn:aws[\w-]*:sns:([a-z0-9-]+):"#, in: topicArn)?.first.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// `?region=…` for AWS console links, from a topic ARN (`sns`) or a queue URL (`sqs`).
    public static func regionQuery(_ target: String, type: String) -> String {
        let value = target.trimmingCharacters(in: .whitespacesAndNewlines)
        let region = type == "sns" ? topicRegion(value) : queueRegion(value)
        return region.map { "?region=\($0)" } ?? ""
    }

    static func uriComponent(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.!~*'()")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    // MARK: Policy templates

    /// The S3 policy Transcdr needs, scoped to a bucket and folder.
    public static func s3PolicyTemplate(bucket: String, root: String) -> JSONValue {
        let b = bucket.isEmpty ? "<your-bucket>" : bucket
        let prefix = normalizeRoot(root)
        var list: [String: JSONValue] = [
            "Sid": "TranscdrList",
            "Effect": "Allow",
            "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
            "Resource": .string("arn:aws:s3:::\(b)"),
        ]
        if !prefix.isEmpty {
            list["Condition"] = ["StringLike": ["s3:prefix": [.string("\(prefix)*")]]]
        }
        return [
            "Version": "2012-10-17",
            "Statement": [
                .object(list),
                [
                    "Sid": "TranscdrObjects",
                    "Effect": "Allow",
                    "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload"],
                    "Resource": .string("arn:aws:s3:::\(b)/\(prefix)*"),
                ],
            ],
        ]
    }

    static func s3Template(_ v: ProviderValues) -> JSONValue {
        [
            "summary": "Create an IAM user (or role) with this policy, then an access key for it.",
            "iam_policy": s3PolicyTemplate(bucket: v.string("bucket"), root: v.string("root")),
            "source_only": "Source only: drop s3:PutObject and s3:DeleteObject.",
            "destination_only": "Destination only: s3:PutObject and s3:AbortMultipartUpload are enough for delivery; the check also lists, reads and deletes its probe file.",
            "kms": "If the bucket uses a customer-managed KMS key, also allow kms:GenerateDataKey and kms:Decrypt on that key.",
        ]
    }

    /// An IAM policy allowing one action on one resource (publishing events).
    public static func awsPublishPolicy(action: String, resource: String) -> JSONValue {
        [
            "Version": "2012-10-17",
            "Statement": [[
                "Sid": .string(action == "sns:Publish" ? "TranscdrPublish" : "TranscdrSend"),
                "Effect": "Allow",
                "Action": .string(action),
                "Resource": .string(resource),
            ]],
        ]
    }

    /// What an SQS trigger queue needs, mirroring the check's `setup`: Transcdr's consumer policy, the queue
    /// access policies that let S3 or SNS send to the queue, and the bucket notification.
    public static func sqsQueueSetup(queueUrl: String, region: String = "") -> JSONValue {
        let arn = queueArn(queueUrl) ?? "arn:aws:sqs:\(region.isEmpty ? "<region>" : region):<account-id>:<queue>"
        let parts = arn.components(separatedBy: ":")
        let arnRegion = parts.count > 3 ? parts[3] : ""
        let account = parts.count > 4 ? parts[4] : ""
        return [
            "summary": "Give Transcdr's IAM user the consumer policy. Then let your bucket (directly, or through an SNS topic) send to the queue with the matching queue access policy, and turn on the bucket's event notification.",
            "iam_policy": [
                "Version": "2012-10-17",
                "Statement": [[
                    "Sid": "ConsumeTranscdrTriggers",
                    "Effect": "Allow",
                    "Action": ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:ChangeMessageVisibility", "sqs:GetQueueAttributes"],
                    "Resource": .string(arn),
                ]],
            ],
            "queue_policy_for_s3": [
                "Version": "2012-10-17",
                "Statement": [[
                    "Sid": "S3SendsObjectEvents",
                    "Effect": "Allow",
                    "Principal": ["Service": "s3.amazonaws.com"],
                    "Action": "sqs:SendMessage",
                    "Resource": .string(arn),
                    "Condition": [
                        "ArnLike": ["aws:SourceArn": "arn:aws:s3:::YOUR-BUCKET"],
                        "StringEquals": ["aws:SourceAccount": .string(account)],
                    ],
                ]],
            ],
            "queue_policy_for_sns": [
                "Version": "2012-10-17",
                "Statement": [[
                    "Sid": "SnsFansOutObjectEvents",
                    "Effect": "Allow",
                    "Principal": ["Service": "sns.amazonaws.com"],
                    "Action": "sqs:SendMessage",
                    "Resource": .string(arn),
                    "Condition": ["ArnEquals": ["aws:SourceArn": .string("arn:aws:sns:\(arnRegion):\(account):YOUR-TOPIC")]],
                ]],
            ],
            "s3_notification": [
                "QueueConfigurations": [[
                    "QueueArn": .string(arn),
                    "Events": ["s3:ObjectCreated:*"],
                    "Filter": ["Key": ["FilterRules": [["Name": "suffix", "Value": ".mp4"]]]],
                ]],
            ],
            "notes": [
                "SNS fan-out: subscribe the queue to the topic. Raw message delivery is optional; both forms are understood.",
                "EventBridge: a rule on `Object Created` from `aws.s3` with this queue as its target works too.",
                "Set a redrive policy (a dead-letter queue): a message Transcdr cannot act on is retried, then lands there.",
            ],
            "kms": "If the queue is encrypted with a customer-managed KMS key, also allow kms:Decrypt on that key for these credentials.",
        ]
    }

    // MARK: Shared fields and steps

    static let rootField = ProviderField(
        key: "root", label: "Folder", placeholder: "videos/",
        hint: "Optional. Every path is relative to this folder, and the permissions below can be limited to it."
    )

    static func accessKeyFields(_ idHint: String, _ secretHint: String? = nil) -> [ProviderField] {
        [
            ProviderField(key: "access_key_id", label: "Access key ID", secret: true, required: true, placeholder: idHint),
            ProviderField(key: "secret_access_key", label: "Secret access key", type: .password, secret: true, required: true, hint: secretHint),
        ]
    }

    static func iamSteps(_ what: String) -> [PrepareStep] {
        [
            PrepareStep(
                title: "Create a policy",
                body: "In IAM, create a policy from the JSON below (use the JSON tab). It allows only \(what).",
                links: [PrepareLink("Create a policy", "https://console.aws.amazon.com/iam/home#/policies/create")]
            ),
            PrepareStep(
                title: "Create a user and an access key",
                body: "Create an IAM user without console access, attach the policy, then create an access key for \"Application running outside AWS\".",
                links: [
                    PrepareLink("Create a user", "https://console.aws.amazon.com/iam/home#/users/create"),
                    PrepareLink("IAM users", "https://console.aws.amazon.com/iam/home#/users"),
                ]
            ),
        ]
    }

    public static let httpsPrepare: [PrepareStep] = [
        PrepareStep(
            title: "Expose an https endpoint",
            body: "A public URL with a valid certificate that accepts POST requests with a JSON body. Hosts on private networks are refused."
        ),
        PrepareStep(
            title: "Answer quickly with a 2xx",
            body: "Return any 2xx status within a few seconds, then do the work in the background. Anything else is retried with backoff for up to a day."
        ),
        PrepareStep(
            title: "Verify the signature",
            body: "Every delivery carries a Transcdr-Signature header. You get the signing secret once, after saving; check it before trusting the body.",
            links: [PrepareLink("Verifying signatures", "/docs/webhooks")]
        ),
    ]

    public static func snsPrepare(_ target: String) -> [PrepareStep] {
        let q = regionQuery(target, type: "sns")
        return [
            PrepareStep(
                title: "Create a topic",
                body: "Standard, or FIFO (name ends in .fifo) if subscribers need events in order. Copy its ARN.",
                links: [
                    PrepareLink("Create a topic", "https://console.aws.amazon.com/sns/v3/home\(q)#/create-topic"),
                    PrepareLink("Your topics", "https://console.aws.amazon.com/sns/v3/home\(q)#/topics"),
                ]
            ),
        ] + iamSteps("sns:Publish on this topic")
    }

    static let nameFromHost: @Sendable (ProviderValues) -> String = { v in
        let host = v.string("host")
        return host.isEmpty ? "File server" : host
    }

    static func or(_ s: String, _ fallback: String) -> String { s.isEmpty ? fallback : s }

    // MARK: The catalog

    public static let all: [ConnectionProvider] = [aws, r2, b2, minio, gcs, azure, sftp, ftp, webdav, http, sqs, sns, webhook]

    public static func provider(id: String?) -> ConnectionProvider? { all.first { $0.id == id } }

    public static func providers(in group: ProviderGroup) -> [ConnectionProvider] { all.filter { $0.group == group } }

    /// The fields shown for the current values.
    public static func visibleFields(_ fields: [ProviderField], _ values: ProviderValues) -> [ProviderField] {
        fields.filter { $0.isVisible(values) }
    }

    /// Visible required fields that are still empty (checkboxes never count).
    public static func missingRequired(_ fields: [ProviderField], _ values: ProviderValues) -> [ProviderField] {
        visibleFields(fields, values).filter { $0.required && $0.type != .checkbox && values.string($0.key).isEmpty }
    }

    static let aws = ConnectionProvider(
        id: "aws", label: "Amazon S3", kind: .s3, group: .storage,
        tagline: "A bucket in your AWS account, with an IAM access key.",
        roles: ["source", "watch_folder", "destination"],
        defaults: ["region": .text("us-east-1")],
        fields: [
            ProviderField(key: "bucket", label: "Bucket", required: true, placeholder: "my-videos"),
            ProviderField(key: "region", label: "Region", type: .select, required: true, hint: "The region the bucket was created in.", options: awsRegions),
            rootField,
        ] + accessKeyFields("AKIA…") + [
            ProviderField(key: "session_token", label: "Session token", type: .password, secret: true, hint: "Only for temporary credentials, which stop working when they expire.", advanced: true),
        ],
        scopeFields: ["bucket", "root"],
        suggestNameFn: { or($0.string("bucket"), "S3 bucket") },
        prepareFn: { v in
            [
                PrepareStep(
                    title: "Create or pick a bucket",
                    body: "Note its name and region. Keep \"Block all public access\" on: Transcdr signs every request.",
                    links: [
                        PrepareLink("Create a bucket", "https://s3.console.aws.amazon.com/s3/bucket/create?region=\(or(v.string("region"), "us-east-1"))"),
                        PrepareLink("Your buckets", "https://s3.console.aws.amazon.com/s3/buckets"),
                    ]
                ),
                PrepareStep(
                    title: "Create a policy",
                    body: "In IAM, create a policy from the JSON below (use the JSON tab). It only covers this bucket and folder.",
                    links: [PrepareLink("Create a policy", "https://console.aws.amazon.com/iam/home#/policies/create")]
                ),
                PrepareStep(
                    title: "Create a user for Transcdr",
                    body: "Create an IAM user without console access and attach the policy to it directly.",
                    links: [PrepareLink("Create a user", "https://console.aws.amazon.com/iam/home#/users/create")]
                ),
                PrepareStep(
                    title: "Create an access key",
                    body: "On the user, open \"Security credentials\", create an access key for \"Application running outside AWS\" and keep both values for the next step.",
                    links: [PrepareLink("IAM users", "https://console.aws.amazon.com/iam/home#/users")]
                ),
            ]
        },
        templateFn: { s3Template($0) },
        setupReadyFn: { !$0.string("bucket").isEmpty },
        buildFn: { v in
            ConnectionCreateParams(
                name: nil, kind: .s3,
                config: ConnectionConfig(bucket: v.optional("bucket"), region: v.optional("region"), pathStyle: false, root: rootOrNil(v)),
                secrets: secrets(v, ["access_key_id", "secret_access_key", "session_token"])
            )
        }
    )

    static let r2 = ConnectionProvider(
        id: "r2", label: "Cloudflare R2", kind: .s3, group: .storage,
        tagline: "An R2 bucket, with an R2 API token. No egress fees.",
        roles: ["source", "watch_folder", "destination"],
        defaults: [:],
        fields: [
            ProviderField(
                key: "account_id", label: "Account ID", required: true, placeholder: "0123456789abcdef0123456789abcdef",
                hint: "On the R2 overview page, under \"Account details\". Fills in the endpoint."
            ),
            ProviderField(key: "bucket", label: "Bucket", required: true, placeholder: "my-videos"),
            rootField,
        ] + accessKeyFields("32-character key ID", "Shown once, when you create the API token."),
        suggestNameFn: { v in v.string("bucket").isEmpty ? "R2 bucket" : "\(v.string("bucket")) (R2)" },
        prepareFn: { _ in
            [
                PrepareStep(
                    title: "Create or pick a bucket",
                    body: "In the Cloudflare dashboard, open R2 and create a bucket. Note its name and your account ID (shown on the R2 overview page).",
                    links: [PrepareLink("R2 overview", "https://dash.cloudflare.com/?to=/:account/r2/overview")]
                ),
                PrepareStep(
                    title: "Create an R2 API token",
                    body: "Choose \"Manage API tokens\", then \"Create API token\". Pick the \"Object Read & Write\" permission and limit it to this bucket. For a source-only connection, \"Object Read only\" is enough.",
                    links: [PrepareLink("R2 API tokens", "https://dash.cloudflare.com/?to=/:account/r2/api-tokens")]
                ),
                PrepareStep(
                    title: "Copy the S3 credentials",
                    body: "After creating the token, copy the \"Access Key ID\" and \"Secret Access Key\" (not the token value). They are shown only once."
                ),
            ]
        },
        templateFn: { _ in
            [
                "summary": "Create an R2 API token with \"Object Read & Write\" on this bucket and use its S3 access key ID and secret access key.",
                "source_only": "Source only: \"Object Read only\" is enough.",
            ]
        },
        buildFn: { v in
            ConnectionCreateParams(
                name: nil, kind: .s3,
                config: ConnectionConfig(endpoint: r2Endpoint(v.string("account_id")), bucket: v.optional("bucket"), region: "auto", pathStyle: false, root: rootOrNil(v)),
                secrets: secrets(v, ["access_key_id", "secret_access_key"])
            )
        }
    )

    static let b2 = ConnectionProvider(
        id: "b2", label: "Backblaze B2", kind: .s3, group: .storage,
        tagline: "A B2 bucket through its S3-compatible API, with an application key.",
        roles: ["source", "watch_folder", "destination"],
        defaults: ["region": .text("us-west-004")],
        fields: [
            ProviderField(key: "bucket", label: "Bucket", required: true, placeholder: "my-videos"),
            ProviderField(
                key: "region", label: "Region", type: .select, required: true,
                hint: "From the bucket's S3 endpoint, e.g. s3.us-west-004.backblazeb2.com → us-west-004.", options: b2Regions
            ),
            rootField,
        ] + accessKeyFields("keyID, e.g. 004a…", "The applicationKey. Shown once, when you create the key."),
        suggestNameFn: { v in v.string("bucket").isEmpty ? "B2 bucket" : "\(v.string("bucket")) (B2)" },
        prepareFn: { _ in
            [
                PrepareStep(
                    title: "Create or pick a bucket",
                    body: "Private buckets work. Note the bucket name and the \"Endpoint\" shown on it (s3.<region>.backblazeb2.com).",
                    links: [PrepareLink("Your buckets", "https://secure.backblaze.com/b2_buckets.htm")]
                ),
                PrepareStep(
                    title: "Create an application key",
                    body: "Under \"Application Keys\", add a key that can access only this bucket, with \"Read and Write\" access (or \"Read Only\" for a source). Leave \"Allow List All Bucket Names\" off.",
                    links: [PrepareLink("Application keys", "https://secure.backblaze.com/app_keys.htm")]
                ),
                PrepareStep(
                    title: "Copy the key",
                    body: "The keyID is the access key ID and the applicationKey is the secret access key. The applicationKey is shown only once."
                ),
            ]
        },
        templateFn: { _ in
            [
                "summary": "Create an application key limited to this bucket with \"Read and Write\" access.",
                "source_only": "Source only: \"Read Only\" access is enough.",
            ]
        },
        buildFn: { v in
            let region = v.string("region")
            return ConnectionCreateParams(
                name: nil, kind: .s3,
                config: ConnectionConfig(
                    endpoint: region.isEmpty ? nil : "https://s3.\(region).backblazeb2.com",
                    bucket: v.optional("bucket"), region: v.optional("region"), pathStyle: false, root: rootOrNil(v)
                ),
                secrets: secrets(v, ["access_key_id", "secret_access_key"])
            )
        }
    )

    static let minio = ConnectionProvider(
        id: "minio", label: "MinIO or other S3", kind: .s3, group: .storage,
        tagline: "MinIO, Wasabi, Ceph, DigitalOcean Spaces or any S3-compatible API.",
        roles: ["source", "watch_folder", "destination"],
        defaults: ["region": .text("us-east-1"), "path_style": .flag(true)],
        fields: [
            ProviderField(
                key: "endpoint", label: "Endpoint", type: .url, required: true, placeholder: "https://minio.example.com",
                hint: "The S3 API URL, reachable from the public internet. Hosts on private networks are refused."
            ),
            ProviderField(key: "bucket", label: "Bucket", required: true, placeholder: "my-videos"),
            ProviderField(key: "region", label: "Region", placeholder: "us-east-1", hint: "MinIO accepts any region; use the one your provider documents."),
            ProviderField(key: "path_style", label: "Path-style addressing", type: .checkbox, hint: "On for MinIO and most self-hosted stores. Off for Wasabi and Spaces."),
            rootField,
        ] + accessKeyFields("Access key"),
        scopeFields: ["bucket", "root"],
        suggestNameFn: { or($0.string("bucket"), "S3-compatible bucket") },
        prepareFn: { v in
            [
                PrepareStep(
                    title: "Create or pick a bucket",
                    body: "Note the bucket name and the S3 API endpoint. It must be reachable over the internet with a valid TLS certificate.",
                    code: "mc mb myminio/\(or(v.string("bucket"), "my-videos"))", lang: "bash"
                ),
                PrepareStep(
                    title: "Create a policy",
                    body: "MinIO and most S3-compatible stores accept AWS-style policies. Save the JSON below as transcdr-policy.json.",
                    code: "mc admin policy create myminio transcdr transcdr-policy.json", lang: "bash"
                ),
                PrepareStep(
                    title: "Create a user and attach the policy",
                    body: "Create a dedicated user (or service account) for Transcdr. Its access key and secret key go in the next step.",
                    links: [PrepareLink("MinIO access management", "https://min.io/docs/minio/linux/administration/identity-access-management/policy-based-access-control.html")],
                    code: "mc admin user add myminio transcdr '<secret-key>'\nmc admin policy attach myminio transcdr --user transcdr", lang: "bash"
                ),
            ]
        },
        templateFn: { v in
            [
                "summary": "Create a user with this policy and use its access key.",
                "iam_policy": s3PolicyTemplate(bucket: v.string("bucket"), root: v.string("root")),
                "source_only": "Source only: drop s3:PutObject and s3:DeleteObject.",
            ]
        },
        buildFn: { v in
            ConnectionCreateParams(
                name: nil, kind: .s3,
                config: ConnectionConfig(
                    endpoint: v.optional("endpoint"), bucket: v.optional("bucket"), region: v.optional("region"),
                    pathStyle: v[flag: "path_style"], root: rootOrNil(v)
                ),
                secrets: secrets(v, ["access_key_id", "secret_access_key"])
            )
        }
    )

    static let gcs = ConnectionProvider(
        id: "gcs", label: "Google Cloud Storage", kind: .gcs, group: .storage,
        tagline: "A GCS bucket, with a service account key.",
        roles: ["source", "watch_folder", "destination"],
        defaults: [:],
        fields: [
            ProviderField(key: "bucket", label: "Bucket", required: true, placeholder: "my-videos"),
            rootField,
            ProviderField(
                key: "service_account_json", label: "Service account JSON key", type: .textarea, secret: true, required: true,
                placeholder: "{ \"type\": \"service_account\", \"project_id\": \"…\", … }",
                hint: "Paste the key file, or choose it. It never leaves this form except to the Transcdr API.",
                acceptsFiles: ["json"]
            ),
        ],
        scopeFields: ["bucket"],
        suggestNameFn: { or($0.string("bucket"), "GCS bucket") },
        prepareFn: { v in
            let bucket = v.string("bucket")
            return [
                PrepareStep(
                    title: "Create or pick a bucket",
                    body: "Uniform bucket-level access is recommended.",
                    links: [
                        PrepareLink("Create a bucket", "https://console.cloud.google.com/storage/create-bucket"),
                        PrepareLink("Your buckets", "https://console.cloud.google.com/storage/browser"),
                    ]
                ),
                PrepareStep(
                    title: "Create a service account",
                    body: "Create a service account for Transcdr. Skip the optional project-wide roles: access is granted on the bucket only.",
                    links: [PrepareLink("Create a service account", "https://console.cloud.google.com/iam-admin/serviceaccounts/create")]
                ),
                PrepareStep(
                    title: "Grant it access to the bucket",
                    body: "On the bucket's Permissions tab, grant the service account the role below, or run the command.",
                    links: [PrepareLink(
                        "Bucket permissions",
                        bucket.isEmpty
                            ? "https://console.cloud.google.com/storage/browser"
                            : "https://console.cloud.google.com/storage/browser/\(uriComponent(bucket));tab=permissions"
                    )]
                ),
                PrepareStep(
                    title: "Create a JSON key",
                    body: "On the service account, open \"Keys\", then \"Add key\" and \"Create new key\" as JSON. The file downloads once.",
                    links: [PrepareLink("Service accounts", "https://console.cloud.google.com/iam-admin/serviceaccounts")]
                ),
            ]
        },
        templateFn: { v in
            [
                "summary": "Grant the service account this role on the bucket, then create a JSON key for it.",
                "role": "roles/storage.objectAdmin",
                "source_only_role": "roles/storage.objectViewer",
                "command": .string("gcloud storage buckets add-iam-policy-binding gs://\(or(v.string("bucket"), "<your-bucket>")) \\\n  --member=serviceAccount:<name>@<project>.iam.gserviceaccount.com \\\n  --role=roles/storage.objectAdmin"),
            ]
        },
        setupReadyFn: { !$0.string("bucket").isEmpty },
        buildFn: { v in
            ConnectionCreateParams(
                name: nil, kind: .gcs,
                config: ConnectionConfig(bucket: v.optional("bucket"), root: rootOrNil(v)),
                secrets: secrets(v, ["service_account_json"])
            )
        }
    )

    static let azure = ConnectionProvider(
        id: "azure", label: "Azure Blob Storage", kind: .azureBlob, group: .storage,
        tagline: "A container in a storage account, with a SAS token or account key.",
        roles: ["source", "watch_folder", "destination"],
        defaults: ["auth": .text("sas_token")],
        fields: [
            ProviderField(key: "account", label: "Storage account", required: true, placeholder: "mystorageaccount"),
            ProviderField(key: "bucket", label: "Container", required: true, placeholder: "videos"),
            rootField,
            ProviderField(
                key: "auth", label: "Sign in with", type: .select, secret: true,
                options: [
                    FieldOption("sas_token", "SAS token (recommended: limited to the container)"),
                    FieldOption("account_key", "Account key (full access to the account)"),
                ]
            ),
            ProviderField(
                key: "sas_token", label: "SAS token", type: .password, secret: true, required: true, placeholder: "sv=2024-…&sig=…",
                hint: "With or without the leading \"?\". Note its expiry: the connection stops working after it.",
                when: { $0[text: "auth"] != "account_key" }
            ),
            ProviderField(key: "account_key", label: "Account key", type: .password, secret: true, required: true, when: { $0[text: "auth"] == "account_key" }),
        ],
        scopeFields: ["account", "bucket"],
        suggestNameFn: { v in
            let (a, b) = (v.string("account"), v.string("bucket"))
            return !a.isEmpty && !b.isEmpty ? "\(a)/\(b)" : "Azure container"
        },
        prepareFn: { _ in
            [
                PrepareStep(
                    title: "Create or pick a storage account and container",
                    body: "Any general-purpose v2 storage account works. Keep the container private.",
                    links: [
                        PrepareLink("Create a storage account", "https://portal.azure.com/#create/Microsoft.StorageAccount"),
                        PrepareLink("Storage accounts", "https://portal.azure.com/#browse/Microsoft.Storage%2FStorageAccounts"),
                    ]
                ),
                PrepareStep(
                    title: "Generate a SAS token for the container",
                    body: "Open the container, choose \"Shared access tokens\", pick the permissions below and an expiry date, then \"Generate SAS token and URL\". Copy the \"Blob SAS token\"."
                ),
                PrepareStep(
                    title: "Or use an account key",
                    body: "Under \"Security + networking\", \"Access keys\". An account key reaches every container in the account; prefer a SAS token."
                ),
                PrepareStep(
                    title: "Allow access from the internet",
                    body: "Under \"Networking\", public network access must be enabled (for all networks) for Transcdr to reach the account."
                ),
            ]
        },
        templateFn: { _ in
            [
                "summary": "Generate a container SAS token with these permissions, or use an account key.",
                "role": "Storage Blob Data Contributor",
                "sas_permissions": "racwdl (read, add, create, write, delete, list)",
                "source_only_sas_permissions": "rl (read, list)",
            ]
        },
        setupReadyFn: { !$0.string("account").isEmpty && !$0.string("bucket").isEmpty },
        buildFn: { v in
            var sas = v.string("sas_token")
            if sas.hasPrefix("?") { sas.removeFirst() }
            return ConnectionCreateParams(
                name: nil, kind: .azureBlob,
                config: ConnectionConfig(bucket: v.optional("bucket"), account: v.optional("account"), root: rootOrNil(v)),
                secrets: v[text: "auth"] == "account_key" ? secrets(v, ["account_key"]) : ConnectionSecrets(sasToken: sas)
            )
        }
    )

    static let sftp = ConnectionProvider(
        id: "sftp", label: "SFTP", kind: .sftp, group: .storage,
        tagline: "An SSH file server, with a password or a private key.",
        roles: ["source", "watch_folder", "destination"],
        defaults: ["port": .text("22"), "auth": .text("private_key")],
        fields: [
            ProviderField(key: "host", label: "Host", required: true, placeholder: "sftp.example.com"),
            ProviderField(key: "port", label: "Port", type: .number, placeholder: "22"),
            ProviderField(key: "username", label: "Username", required: true, placeholder: "transcdr"),
            ProviderField(
                key: "host_key_fingerprint", label: "Host key fingerprint", placeholder: "SHA256:…",
                hint: "Recommended: any other server key is refused. See the command in the Prepare step."
            ),
            rootField,
            ProviderField(
                key: "auth", label: "Sign in with", type: .select, secret: true,
                options: [FieldOption("private_key", "Private key (recommended)"), FieldOption("password", "Password")]
            ),
            ProviderField(
                key: "private_key", label: "Private key", type: .textarea, secret: true, required: true,
                placeholder: "-----BEGIN OPENSSH PRIVATE KEY-----", when: { $0[text: "auth"] != "password" }
            ),
            ProviderField(
                key: "private_key_passphrase", label: "Key passphrase", type: .password, secret: true,
                hint: "Only if the key has one.", when: { $0[text: "auth"] != "password" }
            ),
            ProviderField(key: "password", label: "Password", type: .password, secret: true, required: true, when: { $0[text: "auth"] == "password" }),
        ],
        suggestNameFn: nameFromHost,
        prepareFn: { v in
            [
                PrepareStep(
                    title: "Create a user for Transcdr",
                    body: "A dedicated account whose home (or a folder it owns) holds the files. It needs to list, read, write and delete there.",
                    code: "sudo adduser --disabled-password transcdr", lang: "bash"
                ),
                PrepareStep(
                    title: "Create a key pair",
                    body: "Add the public key to the user's authorized_keys. The private key goes in the next step.",
                    code: "ssh-keygen -t ed25519 -f transcdr_key -N \"\"\nsudo -u transcdr sh -c 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys' < transcdr_key.pub",
                    lang: "bash"
                ),
                PrepareStep(
                    title: "Get the host key fingerprint",
                    body: "So Transcdr only ever talks to your server. Run this from a trusted machine:",
                    code: "ssh-keyscan -t ed25519 \(or(v.string("host"), "sftp.example.com")) 2>/dev/null | ssh-keygen -lf -", lang: "bash"
                ),
                PrepareStep(
                    title: "Open the port",
                    body: "The server must be reachable from the public internet on its SSH port. Hosts on private networks are refused."
                ),
            ]
        },
        buildFn: { v in
            ConnectionCreateParams(
                name: nil, kind: .sftp,
                config: ConnectionConfig(
                    host: v.optional("host"), port: v.int("port"), username: v.optional("username"), root: rootOrNil(v),
                    hostKeyFingerprint: v.optional("host_key_fingerprint")
                ),
                secrets: v[text: "auth"] == "password" ? secrets(v, ["password"]) : secrets(v, ["private_key", "private_key_passphrase"])
            )
        }
    )

    static let ftp = ConnectionProvider(
        id: "ftp", label: "FTP / FTPS", kind: .ftps, group: .storage,
        tagline: "An FTP server, preferably over TLS.",
        roles: ["source", "watch_folder", "destination"],
        defaults: ["tls": .flag(true), "port": .text("21"), "passive": .flag(true)],
        fields: [
            ProviderField(key: "host", label: "Host", required: true, placeholder: "ftp.example.com"),
            ProviderField(key: "port", label: "Port", type: .number, placeholder: "21"),
            ProviderField(key: "username", label: "Username", required: true),
            ProviderField(key: "tls", label: "Use TLS (FTPS)", type: .checkbox, hint: "Explicit TLS. Without it, the password crosses the internet in clear text."),
            ProviderField(key: "passive", label: "Passive mode", type: .checkbox, hint: "Leave on unless your server only supports active mode."),
            rootField,
            ProviderField(key: "password", label: "Password", type: .password, secret: true, required: true),
        ],
        suggestNameFn: nameFromHost,
        prepareFn: { _ in
            [
                PrepareStep(
                    title: "Create an FTP account for Transcdr",
                    body: "A dedicated account limited to one folder, allowed to list, download, upload and delete there."
                ),
                PrepareStep(
                    title: "Turn on TLS",
                    body: "Enable explicit FTPS (AUTH TLS) with a certificate valid for the host name. Plain FTP works, but sends the password unencrypted."
                ),
                PrepareStep(
                    title: "Open the ports",
                    body: "Allow the control port (usually 21) and the server's passive port range from the internet. Hosts on private networks are refused."
                ),
            ]
        },
        buildFn: { v in
            ConnectionCreateParams(
                name: nil, kind: v.isOff("tls") ? .ftp : .ftps,
                config: ConnectionConfig(
                    host: v.optional("host"), port: v.int("port"), username: v.optional("username"), root: rootOrNil(v), passive: v[flag: "passive"]
                ),
                secrets: secrets(v, ["password"])
            )
        }
    )

    static let webdav = ConnectionProvider(
        id: "webdav", label: "WebDAV", kind: .webdav, group: .storage,
        tagline: "Nextcloud, ownCloud, NAS devices and other WebDAV shares.",
        roles: ["source", "watch_folder", "destination"],
        defaults: ["auth": .text("password")],
        fields: [
            ProviderField(
                key: "endpoint", label: "WebDAV URL", type: .url, required: true,
                placeholder: "https://cloud.example.com/remote.php/dav/files/transcdr/", hint: "The base URL of the share, over https."
            ),
            ProviderField(key: "username", label: "Username"),
            rootField,
            ProviderField(
                key: "auth", label: "Sign in with", type: .select, secret: true,
                options: [FieldOption("password", "Password or app password"), FieldOption("bearer_token", "Bearer token")]
            ),
            ProviderField(key: "password", label: "Password", type: .password, secret: true, required: true, when: { $0[text: "auth"] != "bearer_token" }),
            ProviderField(key: "bearer_token", label: "Bearer token", type: .password, secret: true, required: true, when: { $0[text: "auth"] == "bearer_token" }),
        ],
        suggestNameFn: { or(hostOf($0.string("endpoint")), "WebDAV share") },
        prepareFn: { _ in
            [
                PrepareStep(
                    title: "Create an account or app password",
                    body: "Use a dedicated account, or an app password (Nextcloud: Personal settings → Security → \"Create new app password\"). It needs to read, write and delete in the folder."
                ),
                PrepareStep(
                    title: "Find the WebDAV URL",
                    body: "Nextcloud and ownCloud show it under Files → Settings → WebDAV. It usually ends in /remote.php/dav/files/<user>/."
                ),
                PrepareStep(
                    title: "Make it reachable",
                    body: "The URL must be public and served over https with a valid certificate. Hosts on private networks are refused."
                ),
            ]
        },
        buildFn: { v in
            ConnectionCreateParams(
                name: nil, kind: .webdav,
                config: ConnectionConfig(endpoint: v.optional("endpoint"), username: v.optional("username"), root: rootOrNil(v)),
                secrets: v[text: "auth"] == "bearer_token" ? secrets(v, ["bearer_token"]) : secrets(v, ["password"])
            )
        }
    )

    static let http = ConnectionProvider(
        id: "http", label: "HTTP", kind: .http, group: .storage,
        tagline: "Read inputs from a web server. Read-only: a source, never a destination.",
        roles: ["source"],
        defaults: ["auth": .text("none")],
        fields: [
            ProviderField(
                key: "endpoint", label: "Base URL", type: .url, required: true, placeholder: "https://media.example.com/",
                hint: "Input paths are appended to this URL."
            ),
            ProviderField(
                key: "auth", label: "Authentication", type: .select, secret: true,
                options: [FieldOption("none", "None (public files)"), FieldOption("basic", "Basic auth"), FieldOption("bearer_token", "Bearer token")]
            ),
            ProviderField(key: "username", label: "Username", secret: true, required: true, when: { $0[text: "auth"] == "basic" }),
            ProviderField(key: "password", label: "Password", type: .password, secret: true, required: true, when: { $0[text: "auth"] == "basic" }),
            ProviderField(key: "bearer_token", label: "Bearer token", type: .password, secret: true, required: true, when: { $0[text: "auth"] == "bearer_token" }),
        ],
        suggestNameFn: { or(hostOf($0.string("endpoint")), "Web server") },
        prepareFn: { _ in
            [
                PrepareStep(
                    title: "Serve the files over https",
                    body: "Any web server or CDN works. Transcdr sends GET (and HEAD) requests for the paths you give it, relative to the base URL."
                ),
                PrepareStep(
                    title: "Protect them if needed",
                    body: "Basic auth or a bearer token is sent with every request. Signed URLs from your own storage work as job inputs without a connection."
                ),
            ]
        },
        buildFn: { v in
            let auth = v[text: "auth"]
            return ConnectionCreateParams(
                name: nil, kind: .http,
                config: ConnectionConfig(endpoint: v.optional("endpoint"), username: auth == "basic" ? v.optional("username") : nil),
                secrets: auth == "basic" ? secrets(v, ["password"]) : auth == "bearer_token" ? secrets(v, ["bearer_token"]) : ConnectionSecrets()
            )
        }
    )

    static let sqs = ConnectionProvider(
        id: "sqs", label: "Amazon SQS", kind: .sqs, group: .messaging,
        tagline: "A queue that triggers automations: S3 notifications, EventBridge events or your own job requests.",
        roles: [],
        messagingRole: "trigger",
        uses: [
            "Trigger queue automations: S3 bucket notifications (directly or through SNS), EventBridge \"Object Created\" events, or job requests you send.",
            "Receive events from an event endpoint that sends through this connection.",
        ],
        defaults: ["region": .text("")],
        fields: [
            ProviderField(
                key: "queue_url", label: "Queue URL", type: .url, required: true,
                placeholder: "https://sqs.us-east-1.amazonaws.com/123456789012/transcdr-ingest",
                hint: "On the queue's Details panel in the SQS console. Standard or FIFO."
            ),
            ProviderField(key: "region", label: "Region", type: .select, options: [FieldOption("", "From the queue URL")] + awsRegions),
        ] + accessKeyFields("AKIA…") + [
            ProviderField(
                key: "message_group_id", label: "Message group ID", placeholder: "transcdr",
                hint: "Only when this FIFO queue also receives events: every event message uses this group.", advanced: true
            ),
        ],
        scopeFields: ["queue_url"],
        suggestNameFn: { or(queueName($0.string("queue_url")), "SQS queue") },
        prepareFn: { v in
            let q = regionQuery(v.string("queue_url"), type: "sqs")
            return [
                PrepareStep(
                    title: "Create or pick a queue",
                    body: "A standard queue is the usual choice. Give it a dead-letter queue (redrive policy), so a message Transcdr cannot act on is retried a few times, then set aside.",
                    links: [
                        PrepareLink("Create a queue", "https://console.aws.amazon.com/sqs/v3/home\(q)#/create-queue"),
                        PrepareLink("Your queues", "https://console.aws.amazon.com/sqs/v3/home\(q)#/queues"),
                    ]
                ),
                PrepareStep(
                    title: "Create a policy for Transcdr",
                    body: "In IAM, create a policy from the consumer policy below (JSON tab). It lets Transcdr read and delete messages on this queue only.",
                    links: [PrepareLink("Create a policy", "https://console.aws.amazon.com/iam/home#/policies/create")]
                ),
                PrepareStep(
                    title: "Create a user and an access key",
                    body: "Create an IAM user without console access, attach the policy, then create an access key for \"Application running outside AWS\".",
                    links: [
                        PrepareLink("Create a user", "https://console.aws.amazon.com/iam/home#/users/create"),
                        PrepareLink("IAM users", "https://console.aws.amazon.com/iam/home#/users"),
                    ]
                ),
                PrepareStep(
                    title: "Let your bucket send to the queue",
                    body: "On the queue's \"Access policy\" tab, add the statement for S3 (bucket notifications straight to the queue) or for SNS (a topic that fans out to the queue). Replace YOUR-BUCKET or YOUR-TOPIC. For EventBridge, add a rule on \"Object Created\" from aws.s3 with this queue as its target instead."
                ),
                PrepareStep(
                    title: "Turn on the bucket notification",
                    body: "On the bucket, under Properties → Event notifications, send \"All object create events\" to this queue (or to the SNS topic), or apply the notification JSON below with the CLI. The suffix filter is optional: the automation's own pattern filters too.",
                    code: "aws s3api put-bucket-notification-configuration --bucket YOUR-BUCKET \\\n  --notification-configuration file://notification.json",
                    lang: "bash"
                ),
            ]
        },
        templateFn: { sqsQueueSetup(queueUrl: $0.string("queue_url"), region: $0.string("region")) },
        setupReadyFn: { queueArn($0.string("queue_url")) != nil },
        buildFn: { v in
            ConnectionCreateParams(
                name: nil, kind: .sqs,
                config: ConnectionConfig(
                    region: v.optional("region") ?? queueRegion(v.string("queue_url")),
                    queueUrl: v.optional("queue_url"), messageGroupId: v.optional("message_group_id")
                ),
                secrets: secrets(v, ["access_key_id", "secret_access_key"])
            )
        }
    )

    static let sns = ConnectionProvider(
        id: "sns", label: "Amazon SNS", kind: .sns, group: .messaging,
        tagline: "A topic for events; fan out to email, SQS, Lambda and more.",
        roles: [],
        messagingRole: "notifications",
        uses: ["Receive events from an event endpoint that sends through this connection."],
        defaults: ["region": .text("")],
        fields: [
            ProviderField(
                key: "topic_arn", label: "Topic ARN", required: true, placeholder: "arn:aws:sns:us-east-1:123456789012:transcdr-events",
                hint: "Standard, or FIFO (name ends in .fifo) if subscribers need events in order."
            ),
            ProviderField(key: "region", label: "Region", type: .select, options: [FieldOption("", "From the topic ARN")] + awsRegions),
        ] + accessKeyFields("AKIA…") + [
            ProviderField(
                key: "message_group_id", label: "Message group ID", placeholder: "transcdr",
                hint: "FIFO topics only. Every message uses this group, so events arrive in order.", advanced: true
            ),
            ProviderField(
                key: "endpoint", label: "Service endpoint", type: .url, placeholder: "https://…",
                hint: "Only for an SNS-compatible service other than AWS.", advanced: true
            ),
        ],
        scopeFields: ["topic_arn"],
        suggestNameFn: { or($0.string("topic_arn").components(separatedBy: ":").last ?? "", "SNS topic") },
        prepareFn: { snsPrepare($0.string("topic_arn")) },
        templateFn: { v in
            [
                "summary": "Create an IAM user with this policy, then an access key for it.",
                "iam_policy": awsPublishPolicy(action: "sns:Publish", resource: or(v.string("topic_arn"), "arn:aws:sns:<region>:<account-id>:<topic>")),
                "kms": "If the topic is encrypted with a customer-managed KMS key, also allow kms:GenerateDataKey and kms:Decrypt on that key.",
            ]
        },
        buildFn: { v in
            ConnectionCreateParams(
                name: nil, kind: .sns,
                config: ConnectionConfig(
                    endpoint: v.optional("endpoint"), region: v.optional("region") ?? topicRegion(v.string("topic_arn")),
                    topicArn: v.optional("topic_arn"), messageGroupId: v.optional("message_group_id")
                ),
                secrets: secrets(v, ["access_key_id", "secret_access_key"])
            )
        }
    )

    static let webhook = ConnectionProvider(
        id: "webhook", label: "Webhook", kind: .webhook, group: .messaging,
        tagline: "An https URL on your server that receives signed events.",
        roles: [],
        messagingRole: "notifications",
        uses: ["Receive events from an event endpoint that sends through this connection, signed with that endpoint's secret."],
        defaults: [:],
        fields: [
            ProviderField(
                key: "url", label: "Endpoint URL", type: .url, required: true, placeholder: "https://example.com/hooks/transcdr",
                hint: "A public https URL. Hosts on private networks are refused."
            ),
        ],
        suggestNameFn: { or(hostOf($0.string("url")), "Webhook") },
        prepareFn: { _ in httpsPrepare },
        buildFn: { v in
            ConnectionCreateParams(name: nil, kind: .webhook, config: ConnectionConfig(url: v.optional("url")), secrets: ConnectionSecrets())
        }
    )

    // MARK: Checks

    /// What the check does, per kind. `saved` phrases it for a saved connection.
    public static func checkNote(kind: ConnectionKind, saved: Bool = false) -> String {
        switch (kind, saved) {
        case (.sqs, false): "Confirming who the key belongs to, then reading the queue without hiding or removing any message."
        case (.sqs, true): "Confirms who the key belongs to, then reads the queue without hiding or removing any message."
        case (.sns, false): "Confirming who the key belongs to, then publishing one signed webhook.test message to the topic."
        case (.sns, true): "Confirms who the key belongs to, then publishes one signed webhook.test message."
        case (.webhook, false): "Sending one signed webhook.test event to the URL; it must answer with a 2xx."
        case (.webhook, true): "Sends one signed webhook.test event to the URL."
        case (_, false): "Signing in, listing, then writing, reading back and deleting .transcdr-check/<random>.txt."
        case (_, true): "Signs in, lists, then writes, reads back and deletes a probe file under .transcdr-check/."
        }
    }

    /// Whether a check confirms what the wizard needs: the messaging role, or every wanted storage role.
    public static func rolesMet(_ report: CheckReport, provider: ConnectionProvider, wanted: [String]) -> Bool {
        if let role = provider.messagingRole { return report.roles[role] == true }
        return wanted.allSatisfy { report.roles[$0] == true }
    }
}

// MARK: - Setup guides

/// A check's (or template's) `setup`, sorted into what the setup guide shows.
public struct SetupGuide: Hashable, Sendable {
    public struct Document: Hashable, Sendable, Identifiable {
        public let key: String
        public let title: String
        /// A line above the document, when it needs one.
        public let text: String?
        public let json: String
        public var id: String { key }
    }

    public struct Note: Hashable, Sendable, Identifiable {
        /// `Source only`, `Destination only`, `Encryption`, or nil for a free-form note.
        public let label: String?
        public let text: String
        public var id: String { "\(label ?? "")|\(text)" }
    }

    public var summary: String?
    public var role: String?
    public var sourceOnlyRole: String?
    public var sasPermissions: String?
    public var sourceOnlySasPermissions: String?
    public var command: String?
    /// The IAM policy, then the queue wiring (S3 and SNS queue policies, bucket notification), then any other document.
    public var documents: [Document] = []
    public var notes: [Note] = []
    /// Strings the guide does not know, by key (shown as they are).
    public var otherText: [(key: String, text: String)] { otherTextPairs.map { ($0.key, $0.text) } }
    var otherTextPairs: [Pair] = []

    struct Pair: Hashable, Sendable {
        let key: String
        let text: String
    }

    static let knownText: Set<String> = [
        "summary", "role", "source_only_role", "sas_permissions", "source_only_sas_permissions", "command",
        "source_only", "destination_only", "kms",
    ]
    static let wiring: [(key: String, title: String, text: String)] = [
        ("queue_policy_for_s3", "Queue access policy: S3 sends to the queue", "Bucket notifications straight to the queue. Replace YOUR-BUCKET."),
        ("queue_policy_for_sns", "Queue access policy: an SNS topic fans out to the queue", "When the bucket notifies a topic the queue subscribes to. Replace YOUR-TOPIC."),
        ("s3_notification", "Bucket event notification (JSON)", "For put-bucket-notification-configuration, or the same settings in the console."),
    ]

    public init(_ setup: JSONValue?) {
        guard let object = setup?.objectValue else { return }
        func text(_ key: String) -> String? { object[key]?.stringValue.flatMap { $0.isEmpty ? nil : $0 } }
        summary = text("summary")
        role = text("role")
        sourceOnlyRole = text("source_only_role")
        sasPermissions = text("sas_permissions")
        sourceOnlySasPermissions = text("source_only_sas_permissions")
        command = text("command")

        func isDocument(_ v: JSONValue?) -> Bool {
            switch v {
            case .object?, .array?: return true
            default: return false
            }
        }
        let wiringDocs = Self.wiring.filter { isDocument(object[$0.key]) }
        if let policy = object["iam_policy"], isDocument(policy) {
            documents.append(Document(
                key: "iam_policy",
                title: wiringDocs.isEmpty ? "IAM policy (JSON)" : "IAM policy for the Transcdr key (JSON)",
                text: nil, json: policy.prettyPrinted()
            ))
        }
        for w in wiringDocs {
            documents.append(Document(key: w.key, title: w.title, text: w.text, json: object[w.key]!.prettyPrinted()))
        }
        let handled = Set(["iam_policy", "notes"] + Self.wiring.map(\.key))
        for key in object.keys.sorted() where !handled.contains(key) && isDocument(object[key]) {
            documents.append(Document(key: key, title: Self.title(forKey: key), text: nil, json: object[key]!.prettyPrinted()))
        }

        for (key, label) in [("source_only", "Source only"), ("destination_only", "Destination only"), ("kms", "Encryption")] {
            guard let t = text(key) else { continue }
            notes.append(Note(label: label, text: Self.stripLabel(t)))
        }
        for n in object["notes"]?.arrayValue?.compactMap(\.stringValue) ?? [] {
            notes.append(Note(label: nil, text: n.replacingOccurrences(of: "`", with: "")))
        }
        otherTextPairs = object.keys.sorted().compactMap { key in
            guard !Self.knownText.contains(key), let t = text(key) else { return nil }
            return Pair(key: key, text: t)
        }
    }

    public var isEmpty: Bool {
        summary == nil && role == nil && sasPermissions == nil && command == nil && documents.isEmpty && notes.isEmpty && otherTextPairs.isEmpty
    }

    /// `Source only: drop …` → `drop …`.
    static func stripLabel(_ text: String) -> String {
        for prefix in ["source only:", "destination only:"] where text.lowercased().hasPrefix(prefix) {
            return String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    /// `queue_policy_for_s3` → `Queue policy for s3`.
    public static func title(forKey key: String) -> String {
        let words = key.replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }
}

// MARK: - Check reports

extension CheckReport {
    /// Who the credentials sign in as, as the check report shows it.
    public struct IdentitySummary: Hashable, Sendable {
        public let title: String
        public let value: String
        public let extra: String?
    }

    public var identitySummary: IdentitySummary? {
        guard let identity, !identity.isEmpty else { return nil }
        func nonEmpty(_ s: String?) -> String? { s.flatMap { $0.isEmpty ? nil : $0 } }
        switch identity["provider"] ?? "" {
        case "aws":
            return IdentitySummary(title: "Signed in as", value: identity["arn"] ?? "", extra: nonEmpty(identity["account"]).map { "AWS account \($0)" })
        case "gcp":
            return IdentitySummary(title: "Signed in as", value: identity["service_account"] ?? "", extra: nonEmpty(identity["project"]).map { "Project \($0)" })
        case "azure":
            return IdentitySummary(title: "Storage account", value: identity["account"] ?? "", extra: nonEmpty(identity["auth"]).map { "Signed in with \($0)" })
        case "s3_compatible":
            return IdentitySummary(title: "Access key", value: identity["access_key_id"] ?? "", extra: "This service does not say which account owns the key.")
        case "sftp":
            return IdentitySummary(title: "Signed in as", value: identity["user"] ?? "", extra: nonEmpty(identity["server"]).map { "on \($0)" })
        default:
            let text = identity.keys.sorted().map { "\($0): \(identity[$0]!)" }.joined(separator: ", ")
            return IdentitySummary(title: "Signed in", value: text, extra: nil)
        }
    }

    /// What the roles say: storage roles, or a messaging connection's `trigger` / an endpoint's `notifications`.
    public enum RolesSummary: Hashable, Sendable {
        case storage([String: Bool])
        case trigger(Bool)
        case notifications(Bool)
        case none
    }

    public var rolesSummary: RolesSummary {
        if object == "connection_check", let t = roles["trigger"] { return .trigger(t) }
        if let n = roles["notifications"] { return .notifications(n) }
        if object == "connection_check" || (object.isEmpty && !roles.isEmpty) { return .storage(roles) }
        return .none
    }

    public var failedSteps: [CheckStep] { steps.filter(\.failed) }

    /// Total time of the steps, in seconds.
    public var totalSeconds: Double { Double(steps.reduce(0) { $0 + ($1.durationMs ?? 0) }) / 1000 }

    /// Wanted storage roles the credentials cannot serve yet.
    public func unmetRoles(_ wanted: [String]) -> [ConnectionRole] {
        guard case .storage(let r) = rolesSummary else { return [] }
        return ConnectionProviders.roles.filter { wanted.contains($0.key) && r[$0.key] != true }
    }
}

// MARK: - Kinds

/// What the app knows about each connection kind: which config fields and secrets it takes.
public struct ConnectionKindInfo: Sendable, Identifiable {
    public struct ConfigField: Sendable, Identifiable {
        public enum FieldType: Sendable { case text, number, checkbox }
        public let key: String
        public let label: String
        public var type: FieldType = .text
        public var placeholder: String?
        public var required = false
        public var hint: String?
        public var id: String { key }
    }

    public struct SecretField: Sendable, Identifiable {
        public let key: String
        public let label: String
        public var multiline = false
        public var required = false
        public var hint: String?
        public var id: String { key }
    }

    public let kind: ConnectionKind
    /// `storage` or `messaging`.
    public let connectionClass: String
    public let label: String
    /// A two-letter monogram.
    public let mono: String
    public let description: String
    public let fields: [ConfigField]
    public let secrets: [SecretField]
    /// Which secrets are alternatives.
    public var secretsNote: String?
    public var id: String { kind.rawValue }

    public var isMessaging: Bool { connectionClass == "messaging" }

    static let root = ConfigField(key: "root", label: "Root folder", placeholder: "videos/", hint: "Every path is relative to this folder. Optional.")
    static let accessKeys = [
        SecretField(key: "access_key_id", label: "Access key ID", required: true),
        SecretField(key: "secret_access_key", label: "Secret access key", required: true),
    ]
    static func ftpFields() -> [ConfigField] {
        [
            ConfigField(key: "host", label: "Host", placeholder: "ftp.example.com", required: true),
            ConfigField(key: "port", label: "Port", type: .number, placeholder: "21"),
            ConfigField(key: "username", label: "Username", required: true),
            ConfigField(key: "passive", label: "Passive mode", type: .checkbox, hint: "On by default."),
            root,
        ]
    }

    public static let all: [ConnectionKindInfo] = [
        ConnectionKindInfo(
            kind: .s3, connectionClass: "storage", label: "S3-compatible", mono: "S3",
            description: "AWS S3, Cloudflare R2, Backblaze B2, Wasabi, MinIO and other S3 APIs.",
            fields: [
                ConfigField(key: "bucket", label: "Bucket", placeholder: "my-videos", required: true),
                ConfigField(key: "region", label: "Region", placeholder: "us-east-1", hint: "Use \"auto\" for Cloudflare R2."),
                ConfigField(key: "endpoint", label: "Endpoint", placeholder: "https://<account>.r2.cloudflarestorage.com", hint: "Leave empty for AWS S3."),
                ConfigField(key: "path_style", label: "Path-style addressing", type: .checkbox, hint: "Needed by MinIO and some self-hosted stores."),
                root,
            ],
            secrets: accessKeys + [SecretField(key: "session_token", label: "Session token", hint: "Only for temporary credentials.")]
        ),
        ConnectionKindInfo(
            kind: .gcs, connectionClass: "storage", label: "Google Cloud Storage", mono: "GC",
            description: "A GCS bucket, with a service account key.",
            fields: [ConfigField(key: "bucket", label: "Bucket", placeholder: "my-videos", required: true), root],
            secrets: [SecretField(key: "service_account_json", label: "Service account JSON key", multiline: true, required: true)]
        ),
        ConnectionKindInfo(
            kind: .azureBlob, connectionClass: "storage", label: "Azure Blob Storage", mono: "AZ",
            description: "A container in an Azure storage account.",
            fields: [
                ConfigField(key: "account", label: "Storage account", placeholder: "mystorageaccount", required: true),
                ConfigField(key: "bucket", label: "Container", placeholder: "videos", required: true),
                root,
            ],
            secrets: [SecretField(key: "account_key", label: "Account key"), SecretField(key: "sas_token", label: "SAS token")],
            secretsNote: "Provide an account key or a SAS token."
        ),
        ConnectionKindInfo(
            kind: .ftp, connectionClass: "storage", label: "FTP", mono: "FT",
            description: "A plain FTP server. Prefer FTPS or SFTP where you can.",
            fields: ftpFields(),
            secrets: [SecretField(key: "password", label: "Password", required: true)]
        ),
        ConnectionKindInfo(
            kind: .ftps, connectionClass: "storage", label: "FTPS", mono: "FS",
            description: "FTP over TLS.",
            fields: ftpFields(),
            secrets: [SecretField(key: "password", label: "Password", required: true)]
        ),
        ConnectionKindInfo(
            kind: .sftp, connectionClass: "storage", label: "SFTP", mono: "SF",
            description: "An SSH file server, with a password or a private key.",
            fields: [
                ConfigField(key: "host", label: "Host", placeholder: "sftp.example.com", required: true),
                ConfigField(key: "port", label: "Port", type: .number, placeholder: "22"),
                ConfigField(key: "username", label: "Username", required: true),
                ConfigField(key: "host_key_fingerprint", label: "Host key fingerprint", placeholder: "SHA256:…", hint: "Recommended: refuse any other server key. From ssh-keygen -l."),
                root,
            ],
            secrets: [
                SecretField(key: "password", label: "Password"),
                SecretField(key: "private_key", label: "Private key", multiline: true),
                SecretField(key: "private_key_passphrase", label: "Private key passphrase"),
            ],
            secretsNote: "Provide a password or a private key (with its passphrase if it has one)."
        ),
        ConnectionKindInfo(
            kind: .http, connectionClass: "storage", label: "HTTP (read-only)", mono: "HT",
            description: "Read inputs from a web server. Cannot be a destination or be watched.",
            fields: [
                ConfigField(key: "endpoint", label: "Base URL", placeholder: "https://media.example.com/", required: true),
                ConfigField(key: "username", label: "Basic auth username", hint: "Used with the password below."),
            ],
            secrets: [SecretField(key: "password", label: "Basic auth password"), SecretField(key: "bearer_token", label: "Bearer token")],
            secretsNote: "Optional: basic auth (username + password) or a bearer token."
        ),
        ConnectionKindInfo(
            kind: .webdav, connectionClass: "storage", label: "WebDAV", mono: "DV",
            description: "A WebDAV share (Nextcloud, ownCloud, NAS devices…).",
            fields: [
                ConfigField(key: "endpoint", label: "Base URL", placeholder: "https://dav.example.com/remote.php/dav/files/me/", required: true),
                ConfigField(key: "username", label: "Username"),
                root,
            ],
            secrets: [SecretField(key: "password", label: "Password"), SecretField(key: "bearer_token", label: "Bearer token")],
            secretsNote: "Provide a password or a bearer token."
        ),
        ConnectionKindInfo(
            kind: .sqs, connectionClass: "messaging", label: "Amazon SQS", mono: "SQ",
            description: "A queue that triggers automations, and can receive events.",
            fields: [
                ConfigField(key: "queue_url", label: "Queue URL", placeholder: "https://sqs.us-east-1.amazonaws.com/123456789012/transcdr-ingest", required: true),
                ConfigField(key: "region", label: "Region", placeholder: "us-east-1", hint: "Taken from the queue URL when blank."),
                ConfigField(key: "message_group_id", label: "Message group ID", placeholder: "transcdr", hint: "FIFO queues receiving events only."),
            ],
            secrets: accessKeys
        ),
        ConnectionKindInfo(
            kind: .sns, connectionClass: "messaging", label: "Amazon SNS", mono: "SN",
            description: "A topic that receives events and fans them out.",
            fields: [
                ConfigField(key: "topic_arn", label: "Topic ARN", placeholder: "arn:aws:sns:us-east-1:123456789012:transcdr-events", required: true),
                ConfigField(key: "region", label: "Region", placeholder: "us-east-1", hint: "Taken from the ARN when blank."),
                ConfigField(key: "endpoint", label: "Service endpoint", placeholder: "https://…", hint: "Only for an SNS-compatible service other than AWS."),
                ConfigField(key: "message_group_id", label: "Message group ID", placeholder: "transcdr", hint: "FIFO topics only."),
            ],
            secrets: accessKeys
        ),
        ConnectionKindInfo(
            kind: .webhook, connectionClass: "messaging", label: "Webhook", mono: "WH",
            description: "An https URL that receives signed events.",
            fields: [ConfigField(key: "url", label: "Endpoint URL", placeholder: "https://example.com/hooks/transcdr", required: true)],
            secrets: [],
            secretsNote: "None: events are signed with the event endpoint's secret."
        ),
    ]

    public static let storage: [ConnectionKindInfo] = all.filter { !$0.isMessaging }

    /// The metadata for a kind (S3's for an unknown kind, as on the web).
    public static func info(_ kind: ConnectionKind) -> ConnectionKindInfo { all.first { $0.kind == kind } ?? all[0] }

    /// What a connection of this kind is for, in one line.
    public var roleSummary: String {
        switch kind {
        case .sqs: "Triggers queue automations; receives events"
        case .sns, .webhook: "Receives events"
        case .http: "Source only"
        default: "Source and destination"
        }
    }
}

/// S3-compatible shortcuts that pre-fill the endpoint, region and addressing style.
public struct S3Shortcut: Sendable, Identifiable {
    public let id: String
    public let label: String
    public let config: ConnectionConfig
    public let hint: String

    public static let all: [S3Shortcut] = [
        S3Shortcut(id: "aws", label: "AWS S3", config: ConnectionConfig(endpoint: "", region: "us-east-1", pathStyle: false), hint: "Set the bucket region."),
        S3Shortcut(
            id: "r2", label: "Cloudflare R2",
            config: ConnectionConfig(endpoint: "https://<account-id>.r2.cloudflarestorage.com", region: "auto", pathStyle: false),
            hint: "Replace <account-id> with your Cloudflare account ID and use an R2 API token."
        ),
        S3Shortcut(
            id: "b2", label: "Backblaze B2",
            config: ConnectionConfig(endpoint: "https://s3.us-west-004.backblazeb2.com", region: "us-west-004", pathStyle: false),
            hint: "Use the S3 endpoint shown on your bucket, and an application key."
        ),
        S3Shortcut(
            id: "wasabi", label: "Wasabi",
            config: ConnectionConfig(endpoint: "https://s3.us-east-1.wasabisys.com", region: "us-east-1", pathStyle: false),
            hint: "Match the endpoint to the bucket region."
        ),
        S3Shortcut(
            id: "minio", label: "MinIO",
            config: ConnectionConfig(endpoint: "https://minio.example.com", region: "us-east-1", pathStyle: true),
            hint: "MinIO needs path-style addressing."
        ),
    ]
}

// MARK: - Editing a saved connection

/// The edit form of a saved connection: config fields by kind, and secrets
/// (an empty secret is kept; one marked for clearing is sent as `""`).
public struct ConnectionEdit: Hashable, Sendable {
    public let kind: ConnectionKind
    public var name: String
    public var config: ProviderValues
    /// New secret values typed in.
    public var secrets: [String: String] = [:]
    /// Secrets to clear.
    public var clearing: Set<String> = []

    public init(_ connection: Connection) {
        kind = connection.kind
        name = connection.name
        var values = ProviderValues()
        let info = ConnectionKindInfo.info(connection.kind)
        let set = connection.config.fields
        for f in info.fields {
            if f.type == .checkbox {
                values[flag: f.key] = set[f.key] == "true"
            } else {
                values[text: f.key] = set[f.key] ?? ""
            }
        }
        config = values
    }

    public var info: ConnectionKindInfo { ConnectionKindInfo.info(kind) }

    /// Required config fields filled and a name.
    public var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && info.fields.allSatisfy { !$0.required || $0.type == .checkbox || !config.string($0.key).isEmpty }
    }

    /// The config as sent: every field of the kind, empty ones as `null` (the API merges config, so `null` clears).
    public var configJSON: JSONValue {
        var out: [String: JSONValue] = [:]
        for f in info.fields {
            switch f.type {
            case .checkbox: out[f.key] = .bool(config[flag: f.key])
            case .number: out[f.key] = config.int(f.key).map { .number(Double($0)) } ?? .null
            case .text: out[f.key] = config.optional(f.key).map(JSONValue.string) ?? .null
            }
        }
        return .object(out)
    }

    /// The secrets as sent: cleared ones as `""`, new ones with their value, the rest omitted (kept).
    public var secretsJSON: JSONValue {
        var out: [String: JSONValue] = [:]
        for s in info.secrets {
            if clearing.contains(s.key) {
                out[s.key] = ""
            } else if let v = secrets[s.key], !v.isEmpty {
                out[s.key] = .string(v)
            }
        }
        return .object(out)
    }

    /// The `PATCH /v1/connections/{id}` body.
    public var body: JSONValue {
        ["name": .string(name.trimmingCharacters(in: .whitespacesAndNewlines)), "config": configJSON, "secrets": secretsJSON]
    }

    /// Field errors keyed `config.bucket` / `secrets.password` / `bucket`, by bare field name.
    public static func bareFieldErrors(_ errors: [String: String]) -> [String: String] {
        var out: [String: String] = [:]
        for (key, message) in errors {
            var k = key
            for prefix in ["config.", "secrets."] where k.hasPrefix(prefix) { k = String(k.dropFirst(prefix.count)) }
            out[k] = message
        }
        return out
    }
}

// MARK: - Lists and pickers

extension Connection {
    /// Off after failing (or by hand).
    public var isDisabled: Bool { !enabled }

    /// A short description of where it points.
    public var target: String { ConnectionTargets.describe(kind: kind, config: config) }

    /// A picker label that says when it is off.
    public var optionLabel: String { isDisabled ? "\(name) (turned off)" : name }
}

public enum ConnectionTargets {
    /// Transient failures in a row that turn a connection off.
    public static let failureLimit = 5

    /// A short description of where a connection points, for lists.
    public static func describe(kind: ConnectionKind, config: ConnectionConfig) -> String {
        var root = ""
        if let r = config.root {
            var trimmed = Substring(r)
            while trimmed.hasPrefix("/") { trimmed = trimmed.dropFirst() }
            root = "/\(trimmed)"
        }
        switch kind {
        case .sqs: return config.queueUrl ?? "?"
        case .sns: return config.topicArn ?? "?"
        case .webhook: return config.url ?? "?"
        case .s3:
            var host = "AWS"
            if let endpoint = config.endpoint, !endpoint.isEmpty {
                host = endpoint.replacingOccurrences(of: #"^https?://"#, with: "", options: .regularExpression)
                if host.hasSuffix("/") { host.removeLast() }
            }
            return "\(config.bucket ?? "?") · \(host)\(root)"
        case .gcs: return "gs://\(config.bucket ?? "?")\(root)"
        case .azureBlob: return "\(config.account ?? "?")/\(config.bucket ?? "?")\(root)"
        case .ftp, .ftps, .sftp:
            let user = config.username.map { "\($0)@" } ?? ""
            let port = config.port.map { ":\($0)" } ?? ""
            return "\(user)\(config.host ?? "?")\(port)\(root)"
        default: return "\(config.endpoint ?? "?")\(root)"
        }
    }

    /// Storage connections that can be read from: job inputs and automation sources.
    public static func sources(_ list: [Connection]) -> [Connection] { list.filter { !$0.isMessaging && $0.capabilities.source } }

    /// Storage connections outputs can be delivered to.
    public static func destinations(_ list: [Connection]) -> [Connection] { list.filter { !$0.isMessaging && $0.capabilities.destination } }

    /// SQS connections a queue automation can consume; a turned-off one stays listed only when already chosen.
    public static func queues(_ list: [Connection], keeping chosen: String? = nil) -> [Connection] {
        list.filter { $0.kind == .sqs && (!$0.isDisabled || $0.id == chosen) }
    }
}

// MARK: - Automations

public enum AutomationHelpers {
    public struct TemplateVariable: Hashable, Sendable, Identifiable {
        public let name: String
        public let description: String
        public var id: String { name }
    }

    public struct PatternExample: Hashable, Sendable, Identifiable {
        public let pattern: String
        public let description: String
        public var id: String { pattern }
    }

    public static let templateVariables: [TemplateVariable] = [
        TemplateVariable(name: "{job_id}", description: "The job id, e.g. job_4Qm…"),
        TemplateVariable(name: "{name}", description: "Source file name with extension, e.g. talk.mov"),
        TemplateVariable(name: "{stem}", description: "Source file name without extension, e.g. talk"),
        TemplateVariable(name: "{ext}", description: "Source extension, e.g. mov"),
        TemplateVariable(name: "{dir}", description: "Source folder, e.g. incoming/2026"),
        TemplateVariable(name: "{date}", description: "The date, YYYY-MM-DD (UTC)"),
        TemplateVariable(name: "{automation}", description: "The automation id"),
        TemplateVariable(name: "{org}", description: "Your organization id"),
    ]

    public static let patternExamples: [PatternExample] = [
        PatternExample(pattern: "**/*.{mp4,mov}", description: "MP4 and MOV files in any folder"),
        PatternExample(pattern: "**/*", description: "Every file"),
        PatternExample(pattern: "incoming/*.mkv", description: "MKV files directly inside incoming/"),
        PatternExample(pattern: "**/master_*.mov", description: "MOV files whose name starts with master_"),
    ]

    public static let defaultPattern = "**/*.{mp4,mov}"
    public static let defaultDestinationPrefix = "{automation}/{date}/{stem}/"
    public static let defaultPreset = "hls-av1-abr"
    /// "Check every" choices, in minutes.
    public static let pollIntervals: [(minutes: Int, label: String)] = [
        (1, "1 minute"), (5, "5 minutes"), (15, "15 minutes"), (60, "1 hour"), (360, "6 hours"), (1440, "24 hours"),
    ]

    /// Where a destination prefix writes for a sample source path.
    public static func prefixPreview(_ template: String, sample: String, date: Date = Date()) -> String {
        let name = sample.components(separatedBy: "/").last ?? sample
        let dot = name.lastIndex(of: ".").map { name.distance(from: name.startIndex, to: $0) } ?? -1
        let stem = dot > 0 ? String(name.prefix(dot)) : name
        let ext = dot > 0 ? String(name.dropFirst(dot + 1)) : ""
        let dir = sample.contains("/") ? String(sample[..<sample.lastIndex(of: "/")!]) : ""
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        let vars: [String: String] = [
            "{job_id}": "job_4QmZr8XkT2vLp9cN1bHs7a",
            "{name}": name,
            "{stem}": stem,
            "{ext}": ext,
            "{dir}": dir,
            "{date}": day,
            "{automation}": "aut_7Tq…",
            "{org}": "org_BAZ…",
        ]
        guard let regex = try? NSRegularExpression(pattern: #"\{[a-z_]+\}"#) else { return template }
        var out = ""
        var last = template.startIndex
        for m in regex.matches(in: template, range: NSRange(template.startIndex..., in: template)) {
            guard let r = Range(m.range, in: template) else { continue }
            out += template[last..<r.lowerBound]
            let token = String(template[r])
            out += vars[token] ?? token
            last = r.upperBound
        }
        out += template[last...]
        return out
    }

    /// An automation's stored overrides on top of its preset's spec (the defaults
    /// without one), resolved for the editor. Objects are replaced, not merged, as
    /// the web dashboard does.
    public static func editableSpec(override: OutputSpec, preset: OutputSpec?) -> OutputSpec {
        var out = SpecTools.resolved(preset)
        if let v = override.mode { out.mode = v }
        if let v = override.codec { out.codec = v }
        if let v = override.renditions { out.renditions = v }
        if let v = override.ladder { out.ladder = v }
        if let v = override.quality { out.quality = v }
        if let v = override.gop { out.gop = v }
        if let v = override.segmentSeconds { out.segmentSeconds = v }
        if let v = override.audio { out.audio = v }
        if let v = override.subtitles { out.subtitles = v }
        if let v = override.color { out.color = v }
        if let v = override.bitDepth { out.bitDepth = v }
        if let v = override.maxFps { out.maxFps = v }
        if let v = override.filters { out.filters = v }
        if let v = override.trim { out.trim = v }
        for field in override.clear {
            switch field {
            case .ladder: out.ladder = nil
            case .gop: out.gop = nil
            case .segmentSeconds: out.segmentSeconds = nil
            case .subtitles: out.subtitles = nil
            case .maxFps: out.maxFps = nil
            case .filters: out.filters = nil
            case .trim: out.trim = nil
            default: break
            }
        }
        return SpecTools.resolved(out)
    }

    /// Connections an automation depends on that are turned off: it is paused until they are back on.
    public static func offConnections(_ automation: Automation, in connections: [Connection]) -> [Connection] {
        [automation.source.connectionId, automation.destination?.connectionId, automation.triggerConnectionId]
            .compactMap { id in connections.first { $0.id == id } }
            .filter(\.isDisabled)
    }

    /// Whether an automation reads from, delivers to or consumes a connection.
    public static func uses(_ automation: Automation, connection id: String) -> Bool {
        automation.source.connectionId == id || automation.destination?.connectionId == id || automation.triggerConnectionId == id
    }

    /// How an automation uses a connection.
    public static func usage(_ automation: Automation, connection id: String) -> String {
        if automation.triggerConnectionId == id { return "queue trigger" }
        if automation.source.connectionId == id {
            return automation.destination?.connectionId == id ? "source and destination" : "source"
        }
        return "destination"
    }

    /// `watch · 5 min`, `queue · <name>`, `hook`.
    public static func triggerLabel(_ automation: Automation, queueName: String) -> String {
        switch automation.trigger {
        case .watch: "watch · \(Int((Double(automation.pollIntervalSeconds) / 60).rounded())) min"
        case .queue: "queue · \(queueName)"
        default: automation.trigger.rawValue
        }
    }

    /// What the last queue read did.
    public static func runSummary(_ run: AutomationRun, queue: Bool) -> String {
        func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }
        if queue {
            guard let received = run.messagesReceived, received > 0 else { return "No messages waiting." }
            return "\(plural(received, "message")) received, \(run.messagesDeleted ?? 0) deleted, \(plural(run.jobsCreated, "job")) created."
        }
        return run.jobsCreated > 0 ? "\(plural(run.jobsCreated, "new job")) created." : "No new files to process."
    }

    /// How to push to a hook URL from curl, S3 (through SNS), R2 and MinIO.
    public static func hookExamples(hookURL: String?, folder: String) -> [(label: String, code: String)] {
        let url = (hookURL?.isEmpty == false ? hookURL : nil) ?? "https://api.transcdr.com/v1/hooks/automations/ahk_…"
        let prefix = folder.isEmpty ? "incoming/" : folder
        return [
            ("curl", "# Push one or more paths (relative to the connection root)\ncurl -X POST \(url) \\\n  -H \"Content-Type: application/json\" \\\n  -d '{\"paths\": [\"incoming/talk.mov\"]}'"),
            ("AWS S3 (SNS)", "# 1. An SNS topic with an HTTPS subscription to the hook (confirmed automatically)\naws sns create-topic --name transcdr-ingest\naws sns subscribe --topic-arn arn:aws:sns:us-east-1:123456789012:transcdr-ingest \\\n  --protocol https --notification-endpoint \(url)\n\n# 2. Send the bucket's ObjectCreated events to the topic\naws s3api put-bucket-notification-configuration --bucket my-ingest \\\n  --notification-configuration '{\n    \"TopicConfigurations\": [{\n      \"TopicArn\": \"arn:aws:sns:us-east-1:123456789012:transcdr-ingest\",\n      \"Events\": [\"s3:ObjectCreated:*\"],\n      \"Filter\": { \"Key\": { \"FilterRules\": [{ \"Name\": \"prefix\", \"Value\": \"\(prefix)\" }] } }\n    }]\n  }'"),
            ("Cloudflare R2", "// wrangler queues create transcdr-ingest\n// wrangler r2 bucket notification create my-ingest --event-type object-create --queue transcdr-ingest\n// Then deploy this Worker as the queue's consumer:\nexport default {\n  async queue(batch) {\n    const paths = batch.messages.map((m) => m.body.object.key);\n    await fetch('\(url)', {\n      method: 'POST',\n      headers: { 'Content-Type': 'application/json' },\n      body: JSON.stringify({ paths }),\n    });\n  },\n};"),
            ("MinIO", "mc admin config set myminio notify_webhook:transcdr endpoint=\"\(url)\"\nmc admin service restart myminio\nmc event add myminio/my-ingest arn:minio:sqs::transcdr:webhook --event put --prefix \(prefix)"),
        ]
    }
}

/// The automation editor's form, and the API body it becomes.
public struct AutomationDraft: Hashable, Sendable {
    public var name = ""
    public var enabled = true
    public var sourceId = ""
    public var prefix = ""
    public var pattern = AutomationHelpers.defaultPattern
    public var trigger: AutomationTrigger = .watch
    /// Queue trigger: the SQS connection consumed.
    public var queueId = ""
    public var pollMinutes = 5
    public var settleSeconds = 60
    /// A preset id or system slug; "" for none (the defaults).
    public var preset = AutomationHelpers.defaultPreset
    /// "" keeps outputs in Transcdr.
    public var destinationId = ""
    public var destinationPrefix = AutomationHelpers.defaultDestinationPrefix
    /// `keep` or `delete`.
    public var afterSuccess = "keep"
    public var priority: Priority = .normal
    public var webhookUrl = ""
    public var metadata: Metadata = [:]

    public init() {}

    public init(_ a: Automation) {
        name = a.name
        enabled = a.enabled
        sourceId = a.source.connectionId
        prefix = a.source.prefix ?? ""
        pattern = a.source.pattern ?? ""
        trigger = a.trigger
        queueId = a.triggerConnectionId ?? ""
        pollMinutes = Int((Double(a.pollIntervalSeconds) / 60).rounded())
        settleSeconds = a.settleSeconds
        preset = a.preset ?? ""
        destinationId = a.destination?.connectionId ?? ""
        destinationPrefix = a.destination?.prefix ?? AutomationHelpers.defaultDestinationPrefix
        afterSuccess = a.afterSuccess
        priority = a.priority
        webhookUrl = a.webhookUrl ?? ""
        metadata = a.metadata
    }

    /// The source folder as a path prefix: "" or "incoming/".
    public var folder: String { ConnectionProviders.normalizeRoot(prefix) }

    /// A name, a source, and a queue when the trigger is one.
    public var isComplete: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sourceId.isEmpty && (trigger != .queue || !queueId.isEmpty)
    }

    /// The create or update body. `spec` is the full edited spec; only what differs
    /// from the preset's goes out. On update, emptied values are sent as clears.
    public func params(spec: OutputSpec, presetSpec: OutputSpec?, isNew: Bool) -> AutomationParams {
        func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }
        let pattern = trimmed(self.pattern)
        let destination: JobDestination?? = destinationId.isEmpty
            ? (isNew ? nil : .some(nil))
            : .some(JobDestination(connectionId: destinationId, prefix: destinationPrefix))
        return AutomationParams(
            name: trimmed(name),
            enabled: enabled,
            trigger: trigger,
            triggerConnectionId: trigger == .queue ? queueId : (isNew ? nil : ""),
            source: AutomationSource(connectionId: sourceId, prefix: trimmed(prefix), pattern: pattern.isEmpty ? "**/*" : pattern),
            pollIntervalSeconds: pollMinutes * 60,
            settleSeconds: settleSeconds,
            preset: preset.isEmpty ? (isNew ? nil : "") : preset,
            output: SpecTools.diff(spec, base: presetSpec),
            destination: destination,
            afterSuccess: afterSuccess,
            priority: priority,
            metadata: metadata,
            webhookUrl: trimmed(webhookUrl).isEmpty ? (isNew ? nil : "") : trimmed(webhookUrl)
        )
    }
}

// MARK: - Browsing

public enum BrowseListing {
    public struct Folder: Hashable, Sendable, Identifiable {
        /// `clips/`
        public let name: String
        /// The full prefix, `incoming/clips/`.
        public let path: String
        public var id: String { path }
    }

    public struct Crumb: Hashable, Sendable, Identifiable {
        public let name: String
        public let path: String
        public var id: String { path }
    }

    /// A listing may name folders (`dir/`) or return deeper keys; fold both into the immediate children of `prefix`.
    public static func rows(_ entries: [RemoteObject], prefix: String) -> (folders: [Folder], files: [RemoteObject]) {
        var folders: [String: String] = [:]
        var files: [RemoteObject] = []
        for e in entries {
            let rest = e.path.hasPrefix(prefix) ? String(e.path.dropFirst(prefix.count)) : e.path
            if let slash = rest.firstIndex(of: "/"), rest.index(after: slash) < rest.endIndex {
                let name = String(rest[...slash])
                folders[name] = prefix + name
            } else if rest.hasSuffix("/") {
                folders[rest] = e.path
            } else if !rest.isEmpty {
                files.append(e)
            }
        }
        return (
            folders.map { Folder(name: $0.key, path: $0.value) }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending },
            files.sorted { $0.path.localizedCompare($1.path) == .orderedAscending }
        )
    }

    /// `a/b/` → `[a → a/, b → a/b/]`.
    public static func crumbs(_ prefix: String) -> [Crumb] {
        let parts = prefix.split(separator: "/").map(String.init)
        return parts.indices.map { i in Crumb(name: parts[i], path: parts[...i].joined(separator: "/") + "/") }
    }

    /// The parent of a folder prefix: `a/b/` → `a/`, `a/` → ``.
    public static func parent(_ prefix: String) -> String {
        let parts = prefix.split(separator: "/")
        return parts.count <= 1 ? "" : parts.dropLast().joined(separator: "/") + "/"
    }

    public static func basename(_ path: String) -> String {
        path.split(separator: "/").last.map(String.init) ?? path
    }
}

// MARK: - Config by key

extension ConnectionConfig {
    /// Set a field by its wire name from text (`true`/`false` for flags, digits for the port).
    public mutating func set(_ key: String, _ value: String?) {
        let v = value?.isEmpty == true ? nil : value
        switch key {
        case "endpoint": endpoint = v
        case "bucket": bucket = v
        case "region": region = v
        case "path_style": pathStyle = v.map { $0 == "true" }
        case "account": account = v
        case "host": host = v
        case "port": port = v.flatMap { Int($0) }
        case "username": username = v
        case "root": root = v
        case "passive": passive = v.map { $0 == "true" }
        case "host_key_fingerprint": hostKeyFingerprint = v
        case "queue_url": queueUrl = v
        case "topic_arn": topicArn = v
        case "url": url = v
        case "message_group_id": messageGroupId = v
        default: break
        }
    }
}
