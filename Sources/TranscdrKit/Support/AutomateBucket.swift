import Foundation

// "Automate a bucket": the guided setup that takes a bucket to "new files are
// transcoded automatically" (docs/automate-a-bucket.md), as on the web
// dashboard's `automate.ts`. How files reach Transcdr and which method suits
// which provider, the IAM and resource policies, the bucket notification with
// its filters, the commands to run, what to check when nothing arrives, and the
// create-in-order plan with retry. Pure data and functions: no UI. It builds on
// the connection catalog in `ConnectionProviders`.

// MARK: - Method

/// How new files reach Transcdr.
public enum AutomateMethod: String, CaseIterable, Sendable, Identifiable {
    /// Transcdr lists the prefix on a schedule.
    case watch
    /// S3 notifies an SQS queue (directly or through SNS) that Transcdr consumes.
    case queue
    /// Something POSTs to the automation's hook URL.
    case webhook

    public var id: String { rawValue }

    /// The automation trigger it becomes.
    public var trigger: AutomationTrigger {
        switch self {
        case .watch: .watch
        case .queue: .queue
        case .webhook: .hook
        }
    }

    public var title: String {
        switch self {
        case .watch: "Watch"
        case .queue: "Queue"
        case .webhook: "Webhook"
        }
    }

    /// The short qualifier after the title.
    public var qualifier: String? {
        switch self {
        case .watch: "poll"
        case .queue: "SQS"
        case .webhook: nil
        }
    }

    public var howItWorks: String {
        switch self {
        case .watch: "Transcdr lists the prefix every few minutes and takes files that have stopped changing."
        case .queue: "S3 sends an event notification to an SQS queue, directly or through an SNS topic. Transcdr consumes the queue."
        case .webhook: "Something POSTs to the automation's secret hook URL: on AWS an SNS topic with an HTTPS subscription, MinIO's webhook target, or a script."
        }
    }

    public var latency: String {
        switch self {
        case .watch: "Up to the poll interval"
        case .queue, .webhook: "Seconds"
        }
    }

    public var setup: String {
        switch self {
        case .watch: "Bucket access only"
        case .queue: "Bucket access, a queue, a notification"
        case .webhook: "Bucket access, and a sender"
        }
    }

    public var bestFor: String {
        switch self {
        case .watch: "Any storage; the simplest option; small and medium buckets"
        case .queue: "AWS production: no public endpoint, and the backlog survives outages"
        case .webhook: "Non-AWS event sources, or no queue to run"
        }
    }

    /// The storage roles the bucket connection needs; `destination` too when outputs go back to it.
    public func roles(outputsBack: Bool) -> [String] {
        var roles = self == .watch ? ["source", "watch_folder"] : ["source"]
        if outputsBack { roles.append("destination") }
        return roles
    }

    /// AWS S3: Queue. MinIO: Webhook, since it posts natively. R2, B2 and other S3-compatible services: Watch.
    public static func recommended(providerID: String?) -> AutomateMethod {
        switch providerID {
        case "aws": .queue
        case "minio": .webhook
        default: .watch
        }
    }

    /// Why a method is recommended for a provider, in one sentence.
    public static func recommendationReason(providerID: String?) -> String {
        switch providerID {
        case "aws": "Recommended for AWS S3: events arrive in seconds and wait in the queue through any outage."
        case "minio": "Recommended for MinIO, which posts events to a webhook natively."
        case "r2", "b2": "Recommended here: this provider's native notifications do not reach SQS."
        default: "Recommended here: it works with any storage."
        }
    }
}

/// Queue method: how the bucket's events reach the queue.
public enum QueueFanout: String, CaseIterable, Sendable, Identifiable {
    /// S3 → queue.
    case direct
    /// S3 → SNS topic → queue, for when other consumers need the same events.
    case topic

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .direct: "S3 → queue"
        case .topic: "S3 → SNS topic → queue"
        }
    }

    public var description: String {
        switch self {
        case .direct: "The bucket notifies the queue directly. The simplest wiring."
        case .topic: "The bucket notifies a topic the queue subscribes to, so other consumers can get the same events."
        }
    }
}

/// Webhook method: what posts to the hook URL.
public enum WebhookSender: String, CaseIterable, Sendable, Identifiable {
    /// S3 → SNS → HTTPS.
    case aws
    /// MinIO's webhook notification target.
    case minio
    /// A script, a function, anything else.
    case other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .aws: "AWS (S3 → SNS → HTTPS)"
        case .minio: "MinIO"
        case .other: "Anything else"
        }
    }

    public static func recommended(providerID: String?) -> WebhookSender {
        switch providerID {
        case "aws": .aws
        case "minio": .minio
        default: .other
        }
    }
}

/// Where outputs go.
public enum AutomateDestination: String, CaseIterable, Sendable, Identifiable {
    /// The same bucket, under a prefix template (only when outputs go back).
    case sameBucket
    /// Another destination connection.
    case other
    /// Outputs stay in Transcdr's storage.
    case none

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .sameBucket: "The same bucket"
        case .other: "Another destination"
        case .none: "None: keep outputs in Transcdr"
        }
    }
}

// MARK: - Generated setup

/// One generated document or command, shown with a copy button.
public struct SetupSnippet: Hashable, Sendable, Identifiable {
    public let key: String
    public let title: String
    /// A line above the code, when it needs one.
    public let text: String?
    public let code: String
    public var id: String { key }

    public init(key: String, title: String, text: String? = nil, code: String) {
        self.key = key
        self.title = title
        self.text = text
        self.code = code
    }
}

/// A likely cause when no file arrives.
public struct TroubleshootingItem: Hashable, Sendable, Identifiable {
    public let title: String
    public let detail: String
    public var id: String { title }
}

/// The bucket notification's filters, from the automation's prefix and pattern.
public struct NotificationFilters: Hashable, Sendable {
    /// The key prefix, from the bucket root: the connection's folder and the automation's prefix.
    public var prefix: String
    /// One notification configuration per suffix; none filters by prefix only.
    public var suffixes: [String]
    /// False when the pattern has no simple suffix: the prefix filters, and the automation's pattern does the rest.
    public var exact: Bool
}

/// Where the bucket notification goes.
public enum NotificationTarget: Hashable, Sendable {
    case queue(arn: String)
    case topic(arn: String)
}

public enum AutomateBucket {
    // MARK: Defaults

    public static let defaultPrefix = "incoming/"
    public static let defaultPattern = "**/*.{mp4,mov,mkv,webm,m4v}"
    public static let defaultPreset = "hls-av1-abr"
    public static let defaultOutputPrefix = "transcoded/{stem}/"
    public static let defaultPollSeconds = 300
    public static let defaultMinioAlias = "myminio"
    public static let defaultSettleSeconds = 60
    public static let pollSecondsRange = 60...86_400

    /// The storage providers a bucket can be created with inline: the S3 family of the catalog.
    public static let providerIDs = ["aws", "r2", "b2", "minio"]

    public static var providers: [ConnectionProvider] { providerIDs.compactMap { ConnectionProviders.provider(id: $0) } }

    // MARK: Live test timing

    /// How often the live test reads the automation's items.
    public static let itemsPollSeconds: UInt64 = 3
    /// How often the live test runs a Watch or Queue automation, so the file is picked up now.
    public static let runPollSeconds: UInt64 = 5
    /// How long before the live test shows the likely causes.
    public static let troubleshootAfterSeconds: TimeInterval = 120

    /// Whether the live test also calls `run` while it waits.
    public static func runsWhileWaiting(_ method: AutomateMethod) -> Bool { method != .webhook }

    /// The first file that arrived and made a job, or else the first file that arrived.
    public static func firstArrival(_ items: [AutomationItem]) -> AutomationItem? {
        let byTime = items.sorted { $0.createdAt < $1.createdAt }
        return byTime.first { $0.jobId != nil } ?? byTime.first
    }

    /// Whether outputs delivered to the same bucket would land under the watched prefix and be picked up again.
    public static func outputsLoopBack(prefix: String, destinationPrefix: String) -> Bool {
        let source = ConnectionProviders.normalizeRoot(prefix)
        var fixed = destinationPrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        if let brace = fixed.firstIndex(of: "{") { fixed = String(fixed[..<brace]) }
        while fixed.hasPrefix("/") { fixed.removeFirst() }
        // A fixed start shorter than the source prefix (or none, as with `{dir}/…`) may still render inside it.
        return source.isEmpty || fixed.hasPrefix(source) || source.hasPrefix(fixed)
    }

    // MARK: Draft

    /// The automation form with the wizard's defaults for a method.
    public static func draft(method: AutomateMethod, name: String = "") -> AutomationDraft {
        var d = AutomationDraft()
        d.name = name
        d.trigger = method.trigger
        d.prefix = defaultPrefix
        d.pattern = defaultPattern
        d.preset = defaultPreset
        d.pollMinutes = defaultPollSeconds / 60
        d.settleSeconds = defaultSettleSeconds
        d.destinationPrefix = defaultOutputPrefix
        return d
    }

    /// A name for the automation, from the bucket.
    public static func suggestedName(bucket: String?) -> String {
        guard let bucket, !bucket.isEmpty else { return "Bucket automation" }
        return "\(bucket) automation"
    }

    /// The destination connection for a choice: the bucket itself, another one, or none.
    public static func destinationID(_ choice: AutomateDestination, bucketID: String?, otherID: String) -> String {
        switch choice {
        case .sameBucket: bucketID ?? ""
        case .other: otherID
        case .none: ""
        }
    }

    // MARK: Connections

    /// Where a saved storage connection lives: `aws`, `r2`, `b2`, `minio`, `s3` (another S3-compatible service), or nil for other kinds.
    public static func providerID(for connection: Connection) -> String? {
        guard connection.kind == .s3 else { return nil }
        let endpoint = (connection.config.endpoint ?? "").lowercased()
        if endpoint.isEmpty || ConnectionProviders.captures(#"\.amazonaws\.com(\.cn)?(/|$)"#, in: endpoint) != nil { return "aws" }
        if endpoint.contains("r2.cloudflarestorage.com") { return "r2" }
        if endpoint.contains("backblazeb2.com") { return "b2" }
        if endpoint.contains("minio") { return "minio" }
        return "s3"
    }

    /// Existing storage connections the wizard can automate: enabled sources, listable for Watch, S3 for Queue.
    public static func eligibleBuckets(_ list: [Connection], method: AutomateMethod) -> [Connection] {
        ConnectionTargets.sources(list).filter { c in
            guard !c.isDisabled else { return false }
            switch method {
            case .watch: return c.capabilities.watch
            case .queue: return c.kind == .s3
            case .webhook: return true
            }
        }
    }

    /// Whether the queue connection can reuse the bucket's keys: a new AWS bucket connection with static keys.
    public static func canShareKeys(providerID: String?, values: ProviderValues) -> Bool {
        providerID == "aws"
            && !values.string("access_key_id").isEmpty
            && !values.string("secret_access_key").isEmpty
            && values.string("session_token").isEmpty
    }

    /// The SQS connection form, with the bucket's keys copied in when they are shared.
    public static func queueValues(_ values: ProviderValues, sharingKeysFrom bucket: ProviderValues?) -> ProviderValues {
        guard let bucket else { return values }
        var out = values
        out[text: "access_key_id"] = bucket.string("access_key_id")
        out[text: "secret_access_key"] = bucket.string("secret_access_key")
        return out
    }

    /// Wanted roles the check did not confirm.
    public static func missingRoles(_ report: CheckReport, method: AutomateMethod, outputsBack: Bool) -> [ConnectionRole] {
        report.unmetRoles(method.roles(outputsBack: outputsBack))
    }

    // MARK: IAM policies

    static let bucketPlaceholder = "<your-bucket>"
    static let queuePlaceholder = "arn:aws:sqs:<region>:<account-id>:<queue>"
    static let topicPlaceholder = "arn:aws:sns:<region>:<account-id>:<topic>"
    static let hookPlaceholder = "<hook-url>"

    static func or(_ s: String?, _ fallback: String) -> String {
        let t = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? fallback : t
    }

    /// The bucket statements for exactly these roles, scoped to the connection's folder. Reading (`source`,
    /// `watch_folder`) needs listing and `s3:GetObject`; `destination` adds writing, and deleting (so the
    /// check can remove its probe, and for "delete the source").
    public static func bucketStatements(bucket: String, root: String, roles: [String], deleteSource: Bool = false) -> [JSONValue] {
        let b = or(bucket, bucketPlaceholder)
        let prefix = ConnectionProviders.normalizeRoot(root)
        let reads = roles.contains("source") || roles.contains("watch_folder")
        let writes = roles.contains("destination")
        var statements: [JSONValue] = []
        if reads {
            var list: [String: JSONValue] = [
                "Sid": "TranscdrList",
                "Effect": "Allow",
                "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
                "Resource": .string("arn:aws:s3:::\(b)"),
            ]
            if !prefix.isEmpty {
                list["Condition"] = ["StringLike": ["s3:prefix": [.string("\(prefix)*")]]]
            }
            statements.append(.object(list))
        }
        var actions: [JSONValue] = []
        if reads { actions.append("s3:GetObject") }
        if writes { actions.append("s3:PutObject") }
        if writes || deleteSource { actions.append("s3:DeleteObject") }
        if writes { actions.append("s3:AbortMultipartUpload") }
        if !actions.isEmpty {
            statements.append([
                "Sid": "TranscdrObjects",
                "Effect": "Allow",
                "Action": .array(actions),
                "Resource": .string("arn:aws:s3:::\(b)/\(prefix)*"),
            ])
        }
        return statements
    }

    /// The bucket connection's IAM policy for exactly the roles needed.
    public static func bucketPolicy(bucket: String, root: String, roles: [String], deleteSource: Bool = false) -> JSONValue {
        policy(bucketStatements(bucket: bucket, root: root, roles: roles, deleteSource: deleteSource))
    }

    /// Transcdr's consumer statement on the queue.
    public static func consumerStatement(queueArn: String) -> JSONValue {
        [
            "Sid": "ConsumeTranscdrTriggers",
            "Effect": "Allow",
            "Action": ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:ChangeMessageVisibility", "sqs:GetQueueAttributes"],
            "Resource": .string(or(queueArn, queuePlaceholder)),
        ]
    }

    /// The queue connection's IAM policy.
    public static func consumerPolicy(queueArn: String) -> JSONValue {
        policy([consumerStatement(queueArn: queueArn)])
    }

    /// One document for keys shared by the bucket and the queue: the bucket statements, then the consumer's.
    public static func mergedPolicy(bucket: String, root: String, roles: [String], deleteSource: Bool = false, queueArn: String) -> JSONValue {
        policy(bucketStatements(bucket: bucket, root: root, roles: roles, deleteSource: deleteSource) + [consumerStatement(queueArn: queueArn)])
    }

    static func policy(_ statements: [JSONValue]) -> JSONValue {
        ["Version": "2012-10-17", "Statement": .array(statements)]
    }

    // MARK: Resource policies

    /// The queue's access policy: S3 (direct, conditioned on the bucket) or the topic (fan-out) may send to it.
    /// The direct form also requires the queue's own account as the source account, as the catalog's SQS setup does.
    public static func queueAccessPolicy(queueArn: String, fanout: QueueFanout, bucket: String, topicArn: String = "") -> JSONValue {
        let queue = or(queueArn, queuePlaceholder)
        let parts = queue.components(separatedBy: ":")
        let region = parts.count > 3 ? parts[3] : "<region>"
        let account = parts.count > 4 ? parts[4] : "<account-id>"
        switch fanout {
        case .direct:
            var condition: [String: JSONValue] = ["ArnLike": ["aws:SourceArn": .string("arn:aws:s3:::\(or(bucket, "YOUR-BUCKET"))")]]
            if let account = arnAccount(queue) { condition["StringEquals"] = ["aws:SourceAccount": .string(account)] }
            return policy([[
                "Sid": "S3SendsObjectEvents",
                "Effect": "Allow",
                "Principal": ["Service": "s3.amazonaws.com"],
                "Action": "sqs:SendMessage",
                "Resource": .string(queue),
                "Condition": .object(condition),
            ]])
        case .topic:
            return policy([[
                "Sid": "SnsFansOutObjectEvents",
                "Effect": "Allow",
                "Principal": ["Service": "sns.amazonaws.com"],
                "Action": "sqs:SendMessage",
                "Resource": .string(queue),
                "Condition": ["ArnEquals": ["aws:SourceArn": .string(or(topicArn, "arn:aws:sns:\(region):\(account):YOUR-TOPIC"))]],
            ]])
        }
    }

    /// The 12-digit account in an ARN.
    public static func arnAccount(_ arn: String) -> String? {
        ConnectionProviders.captures(#"^arn:aws[\w-]*:[a-z0-9-]+:[a-z0-9-]*:(\d{12}):"#, in: arn.trimmingCharacters(in: .whitespaces))?.first
    }

    /// The topic's access policy: S3 may publish the bucket's events to it.
    public static func topicPolicy(topicArn: String, bucket: String) -> JSONValue {
        let topic = or(topicArn, topicPlaceholder)
        var condition: [String: JSONValue] = ["ArnLike": ["aws:SourceArn": .string("arn:aws:s3:::\(or(bucket, bucketPlaceholder))")]]
        if let account = arnAccount(topic) { condition["StringEquals"] = ["aws:SourceAccount": .string(account)] }
        return policy([[
            "Sid": "S3PublishesObjectEvents",
            "Effect": "Allow",
            "Principal": ["Service": "s3.amazonaws.com"],
            "Action": "sns:Publish",
            "Resource": .string(topic),
            "Condition": .object(condition),
        ]])
    }

    // MARK: Notification filters

    /// The extensions a pattern ends in: `*.mp4` → `[mp4]`, `*.{mp4,mov}` → `[mp4, mov]`; anything else → `[]`.
    public static func patternExtensions(_ pattern: String) -> [String] {
        let p = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if let single = ConnectionProviders.captures(#"\*\.([A-Za-z0-9]+)$"#, in: p) { return single }
        if let group = ConnectionProviders.captures(#"\*\.\{([A-Za-z0-9]+(?:,[A-Za-z0-9]+)*)\}$"#, in: p)?.first {
            var seen = Set<String>()
            return group.split(separator: ",").map(String.init).filter { seen.insert($0).inserted }
        }
        return []
    }

    /// The S3 suffix filters for a pattern: `*.ext` → `[.ext]`, `*.{a,b}` → `[.a, .b]`; nil without a simple suffix.
    public static func suffixes(forPattern pattern: String) -> [String]? {
        let exts = patternExtensions(pattern)
        return exts.isEmpty ? nil : exts.map { ".\($0)" }
    }

    /// A file name the pattern takes, for examples: `example.<first extension>`.
    public static func sampleFileName(pattern: String) -> String {
        "example.\(patternExtensions(pattern).first ?? "mp4")"
    }

    /// The key prefix from the bucket root: the connection's folder, then the automation's prefix.
    public static func keyPrefix(root: String, prefix: String) -> String {
        ConnectionProviders.normalizeRoot(root) + ConnectionProviders.normalizeRoot(prefix)
    }

    /// One prefix and one suffix per configuration, as S3 filters allow.
    public static func filters(root: String, prefix: String, pattern: String) -> NotificationFilters {
        let suffixes = suffixes(forPattern: pattern)
        return NotificationFilters(prefix: keyPrefix(root: root, prefix: prefix), suffixes: suffixes ?? [], exact: suffixes != nil)
    }

    /// What the filters do, in one sentence.
    public static func filtersSummary(_ filters: NotificationFilters) -> String {
        let prefix = filters.prefix.isEmpty ? "every key" : "keys under \(filters.prefix)"
        if filters.suffixes.isEmpty {
            return "The notification covers \(prefix). The pattern has no simple file extension, so the automation's pattern does the rest of the filtering."
        }
        let list = filters.suffixes.joined(separator: ", ")
        return filters.suffixes.count == 1
            ? "The notification covers \(prefix) ending in \(list)."
            : "One configuration per extension (\(list)), each for \(prefix): S3 filters take one prefix and one suffix."
    }

    /// The bucket notification configuration: `QueueConfigurations` or `TopicConfigurations`, `s3:ObjectCreated:*`,
    /// one configuration per suffix.
    public static func bucketNotification(_ target: NotificationTarget, filters: NotificationFilters) -> JSONValue {
        let (key, arnKey, arn): (String, String, String) = switch target {
        case .queue(let arn): ("QueueConfigurations", "QueueArn", or(arn, queuePlaceholder))
        case .topic(let arn): ("TopicConfigurations", "TopicArn", or(arn, topicPlaceholder))
        }
        let suffixes: [String?] = filters.suffixes.isEmpty ? [nil] : filters.suffixes.map { Optional($0) }
        let configurations: [JSONValue] = suffixes.map { suffix in
            var rules: [JSONValue] = []
            if !filters.prefix.isEmpty { rules.append(["Name": "prefix", "Value": .string(filters.prefix)]) }
            if let suffix { rules.append(["Name": "suffix", "Value": .string(suffix)]) }
            var config: [String: JSONValue] = [
                "Id": .string(suffix.map { "transcdr-\($0.dropFirst())" } ?? "transcdr"),
                arnKey: .string(arn),
                "Events": ["s3:ObjectCreated:*"],
            ]
            if !rules.isEmpty { config["Filter"] = ["Key": ["FilterRules": .array(rules)]] }
            return .object(config)
        }
        return [key: .array(configurations)]
    }

    // MARK: Commands

    /// Compact JSON with sorted keys, for a command line.
    public static func compact(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// A shell argument: as is when safe, otherwise single-quoted.
    public static func shellArg(_ s: String) -> String {
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./:=@%+-")
        if !s.isEmpty && s.unicodeScalars.allSatisfy({ safe.contains($0) }) { return s }
        return "'\(s.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    static func regionFlag(_ region: String?) -> String {
        guard let region, !region.isEmpty, region != "auto" else { return "" }
        return " --region \(shellArg(region))"
    }

    /// `aws s3api put-bucket-notification-configuration …` with the configuration inline.
    public static func putNotificationCommand(bucket: String, region: String?, notification: JSONValue) -> String {
        "aws s3api put-bucket-notification-configuration --bucket \(shellArg(or(bucket, bucketPlaceholder)))\(regionFlag(region)) \\\n"
            + "  --notification-configuration \(shellArg(compact(notification)))"
    }

    /// `aws sqs set-queue-attributes …` setting the queue's access policy.
    public static func setQueuePolicyCommand(queueUrl: String, policy: JSONValue) -> String {
        let url = or(queueUrl, "https://sqs.<region>.amazonaws.com/<account-id>/<queue>")
        let attributes: JSONValue = ["Policy": .string(compact(policy))]
        return "aws sqs set-queue-attributes --queue-url \(shellArg(url))\(regionFlag(ConnectionProviders.queueRegion(url))) \\\n"
            + "  --attributes \(shellArg(compact(attributes)))"
    }

    /// `aws sns set-topic-attributes …` setting the topic's access policy.
    public static func setTopicPolicyCommand(topicArn: String, policy: JSONValue) -> String {
        let arn = or(topicArn, topicPlaceholder)
        return "aws sns set-topic-attributes --topic-arn \(shellArg(arn))\(regionFlag(ConnectionProviders.topicRegion(arn))) \\\n"
            + "  --attribute-name Policy --attribute-value \(shellArg(compact(policy)))"
    }

    /// `aws sns subscribe …`: the queue (`sqs`, by ARN) or the hook URL (`https`) to the topic.
    public static func subscribeCommand(topicArn: String, protocol proto: String, endpoint: String) -> String {
        let arn = or(topicArn, topicPlaceholder)
        return "aws sns subscribe --topic-arn \(shellArg(arn))\(regionFlag(ConnectionProviders.topicRegion(arn))) \\\n"
            + "  --protocol \(proto) --notification-endpoint \(shellArg(endpoint))"
    }

    /// MinIO: the webhook target, a restart, then one event rule per suffix.
    public static func minioCommands(alias: String = defaultMinioAlias, bucket: String, filters: NotificationFilters, hookURL: String) -> String {
        let a = or(alias, defaultMinioAlias)
        var lines = [
            "mc admin config set \(shellArg(a)) notify_webhook:transcdr endpoint=\(shellArg(or(hookURL, hookPlaceholder)))",
            "mc admin service restart \(shellArg(a))",
        ]
        let suffixes: [String?] = filters.suffixes.isEmpty ? [nil] : filters.suffixes.map { Optional($0) }
        for suffix in suffixes {
            var line = "mc event add \(shellArg("\(a)/\(or(bucket, bucketPlaceholder))")) arn:minio:sqs::transcdr:webhook --event put"
            if !filters.prefix.isEmpty { line += " --prefix \(shellArg(filters.prefix))" }
            if let suffix { line += " --suffix \(shellArg(suffix))" }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    /// A push from a script: one path, relative to the connection's folder.
    public static func curlExample(hookURL: String, prefix: String, pattern: String = "") -> String {
        let body = compact(["path": .string("\(ConnectionProviders.normalizeRoot(prefix))\(sampleFileName(pattern: pattern))")])
        return "curl -X POST \(shellArg(or(hookURL, hookPlaceholder))) \\\n"
            + "  -H 'Content-Type: application/json' \\\n"
            + "  -d \(shellArg(body))"
    }

    /// An S3-style `Records[]` payload, which the hook URL understands too.
    public static func recordsExample(bucket: String, key: String) -> JSONValue {
        [
            "Records": [[
                "eventSource": "aws:s3",
                "eventName": "ObjectCreated:Put",
                "s3": [
                    "bucket": ["name": .string(or(bucket, bucketPlaceholder))],
                    "object": ["key": .string(key)],
                ],
            ]],
        ]
    }

    /// Where to upload the test file.
    public static func uploadLocation(connection: Connection?, bucket: String?, root: String, prefix: String) -> String {
        let key = keyPrefix(root: root, prefix: prefix)
        if let connection, connection.kind != .s3 {
            return "\(connection.target)\(key.isEmpty ? "" : "/\(key)")"
        }
        return "s3://\(or(bucket, bucketPlaceholder))/\(key)"
    }

    // MARK: Method setups

    /// Everything the Queue method needs, from the real values, in the order to apply it.
    public struct QueueSetupInput: Hashable, Sendable {
        public var bucket: String
        public var root: String
        public var bucketRegion: String?
        public var prefix: String
        public var pattern: String
        public var queueUrl: String
        public var fanout: QueueFanout
        public var topicArn: String
        /// The queue connection uses the bucket's keys: one merged policy.
        public var sharedKeys: Bool
        public var roles: [String]
        public var deleteSource: Bool

        public init(
            bucket: String, root: String = "", bucketRegion: String? = nil, prefix: String, pattern: String, queueUrl: String,
            fanout: QueueFanout = .direct, topicArn: String = "", sharedKeys: Bool = false, roles: [String] = ["source"], deleteSource: Bool = false
        ) {
            self.bucket = bucket
            self.root = root
            self.bucketRegion = bucketRegion
            self.prefix = prefix
            self.pattern = pattern
            self.queueUrl = queueUrl
            self.fanout = fanout
            self.topicArn = topicArn
            self.sharedKeys = sharedKeys
            self.roles = roles
            self.deleteSource = deleteSource
        }

        public var queueArn: String { ConnectionProviders.queueArn(queueUrl) ?? AutomateBucket.queuePlaceholder }
        public var filters: NotificationFilters { AutomateBucket.filters(root: root, prefix: prefix, pattern: pattern) }
    }

    public static func queueSetup(_ input: QueueSetupInput) -> [SetupSnippet] {
        let queueArn = input.queueArn
        let access = queueAccessPolicy(queueArn: queueArn, fanout: input.fanout, bucket: input.bucket, topicArn: input.topicArn)
        let target: NotificationTarget = input.fanout == .direct ? .queue(arn: queueArn) : .topic(arn: input.topicArn)
        let notification = bucketNotification(target, filters: input.filters)
        var out: [SetupSnippet] = []
        if input.sharedKeys {
            out.append(SetupSnippet(
                key: "iam_policy",
                title: "IAM policy for the shared key",
                text: "The bucket and the queue use the same access key, so one policy covers both.",
                code: mergedPolicy(bucket: input.bucket, root: input.root, roles: input.roles, deleteSource: input.deleteSource, queueArn: queueArn).prettyPrinted()
            ))
        } else {
            out.append(SetupSnippet(
                key: "iam_policy",
                title: "IAM policy for the queue's key",
                text: "Lets Transcdr read and delete messages on this queue only.",
                code: consumerPolicy(queueArn: queueArn).prettyPrinted()
            ))
        }
        out.append(SetupSnippet(
            key: "queue_policy",
            title: input.fanout == .direct ? "Queue access policy: S3 sends to the queue" : "Queue access policy: the topic sends to the queue",
            text: "On the queue's Access policy tab. It replaces the queue's policy: merge it with any statements already there.",
            code: access.prettyPrinted()
        ))
        if input.fanout == .topic {
            let topic = topicPolicy(topicArn: input.topicArn, bucket: input.bucket)
            out.append(SetupSnippet(
                key: "topic_policy",
                title: "Topic access policy: S3 publishes to the topic",
                text: "It replaces the topic's policy: merge it with any statements already there.",
                code: topic.prettyPrinted()
            ))
            out.append(SetupSnippet(
                key: "subscribe",
                title: "Subscribe the queue to the topic",
                text: "Raw message delivery is optional; both forms are understood.",
                code: subscribeCommand(topicArn: input.topicArn, protocol: "sqs", endpoint: queueArn)
            ))
        }
        out.append(SetupSnippet(
            key: "notification",
            title: "Bucket notification (JSON)",
            text: filtersSummary(input.filters),
            code: notification.prettyPrinted()
        ))
        var commands = [setQueuePolicyCommand(queueUrl: input.queueUrl, policy: access)]
        if input.fanout == .topic {
            commands.append(setTopicPolicyCommand(topicArn: input.topicArn, policy: topicPolicy(topicArn: input.topicArn, bucket: input.bucket)))
        }
        commands.append(putNotificationCommand(bucket: input.bucket, region: input.bucketRegion, notification: notification))
        out.append(SetupSnippet(
            key: "commands",
            title: "Apply it with the AWS CLI",
            text: "put-bucket-notification-configuration replaces the bucket's notification configuration: add any existing configurations to it first.",
            code: commands.joined(separator: "\n\n")
        ))
        return out
    }

    /// Everything a Webhook sender needs.
    public struct WebhookSetupInput: Hashable, Sendable {
        public var sender: WebhookSender
        public var bucket: String
        public var root: String
        public var bucketRegion: String?
        public var prefix: String
        public var pattern: String
        public var hookURL: String
        public var topicArn: String
        public var minioAlias: String

        public init(
            sender: WebhookSender, bucket: String, root: String = "", bucketRegion: String? = nil, prefix: String, pattern: String,
            hookURL: String, topicArn: String = "", minioAlias: String = AutomateBucket.defaultMinioAlias
        ) {
            self.sender = sender
            self.bucket = bucket
            self.root = root
            self.bucketRegion = bucketRegion
            self.prefix = prefix
            self.pattern = pattern
            self.hookURL = hookURL
            self.topicArn = topicArn
            self.minioAlias = minioAlias
        }

        public var filters: NotificationFilters { AutomateBucket.filters(root: root, prefix: prefix, pattern: pattern) }
    }

    public static func webhookSetup(_ input: WebhookSetupInput) -> [SetupSnippet] {
        switch input.sender {
        case .aws:
            let topic = topicPolicy(topicArn: input.topicArn, bucket: input.bucket)
            let notification = bucketNotification(.topic(arn: input.topicArn), filters: input.filters)
            return [
                SetupSnippet(
                    key: "topic_policy",
                    title: "Topic access policy: S3 publishes to the topic",
                    text: "It replaces the topic's policy: merge it with any statements already there.",
                    code: topic.prettyPrinted()
                ),
                SetupSnippet(
                    key: "notification",
                    title: "Bucket notification (JSON)",
                    text: filtersSummary(input.filters),
                    code: notification.prettyPrinted()
                ),
                SetupSnippet(
                    key: "commands",
                    title: "Apply it with the AWS CLI",
                    text: "Transcdr confirms the subscription automatically. put-bucket-notification-configuration replaces the bucket's notification configuration: add any existing configurations to it first.",
                    code: [
                        setTopicPolicyCommand(topicArn: input.topicArn, policy: topic),
                        subscribeCommand(topicArn: input.topicArn, protocol: "https", endpoint: input.hookURL),
                        putNotificationCommand(bucket: input.bucket, region: input.bucketRegion, notification: notification),
                    ].joined(separator: "\n\n")
                ),
            ]
        case .minio:
            return [
                SetupSnippet(
                    key: "minio",
                    title: "Point MinIO at the hook URL",
                    text: "Use your mc alias for the server. \(filtersSummary(input.filters))",
                    code: minioCommands(alias: input.minioAlias, bucket: input.bucket, filters: input.filters, hookURL: input.hookURL)
                ),
            ]
        case .other:
            let key = keyPrefix(root: input.root, prefix: input.prefix) + sampleFileName(pattern: input.pattern)
            return [
                SetupSnippet(
                    key: "curl",
                    title: "Push a path",
                    text: "Paths are relative to the connection's folder.",
                    code: curlExample(hookURL: input.hookURL, prefix: input.prefix, pattern: input.pattern)
                ),
                SetupSnippet(
                    key: "records",
                    title: "Or an S3-style event",
                    text: "A Records[] payload with the full object key works too.",
                    code: recordsExample(bucket: input.bucket, key: key).prettyPrinted()
                ),
            ]
        }
    }

    // MARK: Troubleshooting

    /// The likely causes when nothing arrives, for a method (the same list as the web dashboard's).
    public static func troubleshooting(
        method: AutomateMethod, fanout: QueueFanout = .direct, sender: WebhookSender = .aws, keyPrefix: String = ""
    ) -> [TroubleshootingItem] {
        let otherPrefix = TroubleshootingItem(
            title: "The file went to another prefix",
            detail: "Check the key of the file you uploaded.\(keyPrefix.isEmpty ? "" : " It must be under \(keyPrefix).")"
        )
        let filters = TroubleshootingItem(
            title: "A prefix or suffix filter does not match",
            detail: "The notification filters are case-sensitive: .MP4 is not .mp4. The automation pattern must match the key too."
        )
        let saved = TroubleshootingItem(
            title: "The notification configuration was not saved",
            detail: "Run put-bucket-notification-configuration again, or look under the bucket's Properties → Event notifications. It replaces the bucket's existing configuration."
        )
        switch method {
        case .watch:
            return [
                TroubleshootingItem(
                    title: "The settle time has not passed",
                    detail: "A file is taken once it has stayed unchanged for the settle time, so a new upload waits at least that long."
                ),
                otherPrefix,
                TroubleshootingItem(title: "The pattern does not match", detail: "The file name must match the automation's pattern (case-insensitive)."),
            ]
        case .queue:
            var out = [
                saved,
                TroubleshootingItem(
                    title: fanout == .topic ? "The queue policy does not allow the topic" : "The queue policy does not allow the bucket",
                    detail: fanout == .topic
                        ? "The queue access policy must let the topic send (sqs:SendMessage with aws:SourceArn set to the topic ARN), and the topic policy must let S3 publish."
                        : "The queue access policy must let s3.amazonaws.com send, with aws:SourceArn set to the bucket ARN. Without it, S3 refuses the notification configuration."
                ),
                filters,
            ]
            if fanout == .topic {
                out.append(TroubleshootingItem(
                    title: "The SNS subscription is still pending",
                    detail: "Subscriptions in another account need confirming; Transcdr confirms them once the confirmation reaches the queue."
                ))
            }
            out.append(otherPrefix)
            return out
        case .webhook:
            switch sender {
            case .minio:
                return [
                    TroubleshootingItem(
                        title: "The webhook target is not active",
                        detail: "Run mc admin service restart after mc admin config set, then check mc admin config get ALIAS notify_webhook."
                    ),
                    filters,
                    otherPrefix,
                ]
            case .other:
                return [
                    TroubleshootingItem(
                        title: "Nothing has posted yet",
                        detail: "Send the curl example. The path is relative to the connection's folder, not the full key."
                    ),
                    TroubleshootingItem(title: "The path does not match", detail: "It must start with the automation's prefix and match its pattern."),
                ]
            case .aws:
                return [
                    saved,
                    TroubleshootingItem(title: "The topic policy does not allow the bucket", detail: "The topic policy must let s3.amazonaws.com publish from the bucket."),
                    TroubleshootingItem(
                        title: "The SNS subscription is still pending",
                        detail: "It is confirmed automatically once SNS sends the confirmation to the hook URL. Check its status in the SNS console."
                    ),
                    filters,
                    otherPrefix,
                ]
            }
        }
    }
}

// MARK: - What arrives, and what it becomes

/// One step of following a file from the payload to the job.
public struct TranslationStep: Hashable, Sendable, Identifiable {
    public let label: String
    public let value: String
    /// False when this step drops the file: no job.
    public let ok: Bool
    public let note: String?
    public var id: String { label }

    public init(label: String, value: String, ok: Bool, note: String? = nil) {
        self.label = label
        self.value = value
        self.ok = ok
        self.note = note
    }
}

/// A payload followed to its job, step by step.
public struct Translation: Hashable, Sendable {
    public var steps: [TranslationStep]
    /// Whether a job is created.
    public var job: Bool
}

// These mirror the server (`queues.rs`, `glob.rs`, `render_prefix`): how a notification key is decoded, made
// relative to the connection's folder, matched against the prefix and pattern, and how the destination prefix
// template is rendered.
extension AutomateBucket {
    static let sampleETag = "9b2cf535f27731c974343645a3985328"
    static let sampleSize = 734_003_200

    /// Removed from the queue (or answered on the hook) without a job.
    public static let ignoredPayloads = [
        "s3:TestEvent, which S3 sends when a notification configuration is saved",
        "ObjectRemoved:* and other events that do not create an object",
        "an EventBridge event other than Object Created",
    ]

    // MARK: Keys

    /// S3 notification keys are URL-form-encoded: `+` is a space and `%28` is `(`. Invalid escapes stay as they are.
    public static func decodeS3Key(_ key: String) -> String {
        let bytes = Array(key.replacingOccurrences(of: "+", with: " ").utf8)
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        var i = 0
        func hex(_ b: UInt8) -> UInt8? {
            switch b {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): b - UInt8(ascii: "0")
            case UInt8(ascii: "a")...UInt8(ascii: "f"): b - UInt8(ascii: "a") + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"): b - UInt8(ascii: "A") + 10
            default: nil
            }
        }
        while i < bytes.count {
            if bytes[i] == UInt8(ascii: "%"), i + 2 < bytes.count, let hi = hex(bytes[i + 1]), let lo = hex(bytes[i + 2]) {
                out.append(hi << 4 | lo)
                i += 3
            } else {
                out.append(bytes[i])
                i += 1
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    /// How S3 writes a key into a notification: form-encoded, with `/` kept.
    public static func encodeS3Key(_ key: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.~/")
        return (key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key).replacingOccurrences(of: "%20", with: "+")
    }

    /// A key relative to the connection's folder, or nil when it lies outside it (or is the folder itself).
    public static func relativePath(root: String?, key: String) -> String? {
        var k = Substring(key)
        while k.hasPrefix("/") { k = k.dropFirst() }
        let r = (root ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var rest = k
        if !r.isEmpty {
            guard k.hasPrefix("\(r)/") else { return nil }
            rest = k.dropFirst(r.count + 1)
        }
        return rest.isEmpty ? nil : String(rest)
    }

    // MARK: Glob

    enum GlobToken: Equatable {
        case char(Character)
        /// `?`: one character other than `/`.
        case one
        /// `*`: any run of characters other than `/`.
        case star
        /// `**` inside a segment: any run of characters, `/` included.
        case globstar
        /// `**/` at the start of a segment: zero or more whole segments.
        case segments
    }

    /// Case-insensitive glob, like the server: `*` within a folder, `**` across folders, `?`, `{a,b}`.
    public static func globMatch(_ pattern: String, _ path: String) -> Bool {
        let p = Array(String(path.drop { $0 == "/" }).lowercased())
        let pat = String(pattern.drop { $0 == "/" }).lowercased()
        return expandBraces(Array(pat)).contains { matchTokens(tokenize($0), p) }
    }

    /// Expand every `{a,b}` group, nested ones too; an unmatched brace is literal. At most 256 alternatives.
    static func expandBraces(_ pattern: [Character], into out: inout [[Character]]) {
        guard out.count < 256 else { return }
        guard let open = pattern.firstIndex(of: "{") else {
            out.append(pattern)
            return
        }
        var depth = 0
        var close: Int?
        var commas: [Int] = []
        for i in open..<pattern.count {
            switch pattern[i] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { close = i }
            case "," where depth == 1: commas.append(i)
            default: break
            }
            if close != nil { break }
        }
        guard let close else {
            out.append(pattern)
            return
        }
        let head = pattern[..<open]
        let tail = pattern[(close + 1)...]
        var start = open + 1
        for end in commas + [close] {
            expandBraces(Array(head + pattern[start..<end] + tail), into: &out)
            start = end + 1
        }
    }

    static func expandBraces(_ pattern: [Character]) -> [[Character]] {
        var out: [[Character]] = []
        expandBraces(pattern, into: &out)
        return out
    }

    static func tokenize(_ chars: [Character]) -> [GlobToken] {
        var tokens: [GlobToken] = []
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "*", i + 1 < chars.count, chars[i + 1] == "*" {
                var j = i + 2
                while j < chars.count, chars[j] == "*" { j += 1 }
                let atSegmentStart = i == 0 || chars[i - 1] == "/"
                if atSegmentStart, j < chars.count, chars[j] == "/" {
                    tokens.append(.segments)
                    j += 1
                } else {
                    tokens.append(.globstar)
                }
                i = j
                continue
            }
            switch c {
            case "*": tokens.append(.star)
            case "?": tokens.append(.one)
            default: tokens.append(.char(c))
            }
            i += 1
        }
        return tokens
    }

    /// `next[j]`: whether the tokens after this one match `path[j...]`, computed from the last token back.
    static func matchTokens(_ tokens: [GlobToken], _ path: [Character]) -> Bool {
        let n = path.count
        var next = (0...n).map { $0 == n }
        var cur = [Bool](repeating: false, count: n + 1)
        for token in tokens.reversed() {
            switch token {
            case .char(let c):
                for j in 0...n { cur[j] = j < n && path[j] == c && next[j + 1] }
            case .one:
                for j in 0...n { cur[j] = j < n && path[j] != "/" && next[j + 1] }
            case .star:
                cur[n] = next[n]
                for j in stride(from: n - 1, through: 0, by: -1) { cur[j] = next[j] || (path[j] != "/" && cur[j + 1]) }
            case .globstar:
                cur[n] = next[n]
                for j in stride(from: n - 1, through: 0, by: -1) { cur[j] = next[j] || cur[j + 1] }
            case .segments:
                // Zero segments, or any run ending in `/`.
                var endsInSlash = false
                cur[n] = next[n]
                for j in stride(from: n - 1, through: 0, by: -1) {
                    endsInSlash = endsInSlash || (path[j] == "/" && next[j + 1])
                    cur[j] = next[j] || endsInSlash
                }
            }
            swap(&cur, &next)
        }
        return next[0]
    }

    // MARK: Destination prefix

    /// Template variables for a source path. `{job_id}` has no value yet: it is filled once the job exists.
    public static func pathVars(_ path: String, now: Date = Date()) -> [String: String] {
        let name = path.components(separatedBy: "/").last ?? path
        let dot = name.lastIndex(of: ".")
        let (stem, ext): (String, String) = if let dot, dot > name.startIndex {
            (String(name[..<dot]), String(name[name.index(after: dot)...]))
        } else {
            (name, "")
        }
        let dir = path.lastIndex(of: "/").map { String(path[..<$0]) } ?? ""
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        let date = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        return ["name": name, "stem": stem, "ext": ext, "dir": dir, "date": date]
    }

    /// Render a destination prefix template: variables replaced, the path normalized, a trailing `/`. `..` renders empty.
    public static func renderPrefix(_ template: String, vars: [String: String]) -> String {
        var out = template
        for key in vars.keys.sorted() { out = out.replacingOccurrences(of: "{\(key)}", with: vars[key] ?? "") }
        var parts: [String] = []
        for part in out.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "/" || $0 == "\\" }) {
            if part.isEmpty || part == "." { continue }
            if part == ".." || part.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) { return "" }
            parts.append(String(part))
        }
        return parts.isEmpty ? "" : parts.joined(separator: "/") + "/"
    }

    // MARK: Sample payloads

    /// A file the automation takes, relative to the connection's folder: `<prefix>Keynote 2026.<ext>`.
    public static func samplePath(prefix: String, pattern: String) -> String {
        "\(ConnectionProviders.normalizeRoot(prefix))Keynote 2026.\(patternExtensions(pattern).first ?? "mov")"
    }

    /// An S3 event notification for one new object; `key` is the full bucket key, encoded here as S3 sends it.
    public static func s3EventPayload(bucket: String, key: String, source: String = "aws:s3") -> JSONValue {
        [
            "Records": [[
                "eventSource": .string(source),
                "eventName": .string(source == "minio:s3" ? "s3:ObjectCreated:Put" : "ObjectCreated:Put"),
                "s3": [
                    "bucket": ["name": .string(bucket)],
                    "object": ["key": .string(encodeS3Key(key)), "size": .number(Double(sampleSize)), "eTag": .string(sampleETag)],
                ],
            ]],
        ]
    }

    /// The SNS envelope around an S3 event: the event is the JSON string in `Message`.
    public static func snsEnvelopePayload(topicArn: String, inner: JSONValue) -> JSONValue {
        ["Type": "Notification", "TopicArn": .string(topicArn), "Message": .string(compact(inner))]
    }

    public static func snsConfirmationPayload(topicArn: String) -> JSONValue {
        let region = ConnectionProviders.topicRegion(topicArn) ?? "us-east-1"
        return [
            "Type": "SubscriptionConfirmation",
            "TopicArn": .string(topicArn),
            "SubscribeURL": .string("https://sns.\(region).amazonaws.com/?Action=ConfirmSubscription&TopicArn=\(ConnectionProviders.uriComponent(topicArn))&Token=…"),
        ]
    }

    public static func eventBridgePayload(bucket: String, key: String) -> JSONValue {
        [
            "source": "aws.s3",
            "detail-type": "Object Created",
            "detail": [
                "bucket": ["name": .string(bucket)],
                "object": ["key": .string(key), "size": .number(Double(sampleSize)), "etag": .string(sampleETag)],
            ],
        ]
    }

    /// What Transcdr receives for a method, filled in with the bucket, its folder and the automation's prefix.
    public static func payloads(
        method: AutomateMethod, bucket: String, root: String?, prefix: String, pattern: String,
        fanout: QueueFanout = .direct, sender: WebhookSender = .aws, topicArn: String = ""
    ) -> [SetupSnippet] {
        let rel = samplePath(prefix: prefix, pattern: pattern)
        let key = ConnectionProviders.normalizeRoot(root ?? "") + rel
        let topic = or(topicArn, "arn:aws:sns:us-east-1:123456789012:YOUR-TOPIC")
        let b = or(bucket, bucketPlaceholder)
        let event = s3EventPayload(bucket: b, key: key)
        let s3 = SetupSnippet(key: "s3", title: "S3 event notification", text: "Keys arrive URL-form-encoded: + is a space, %28 is (.", code: event.prettyPrinted())
        let envelope = snsEnvelopePayload(topicArn: topic, inner: event).prettyPrinted()
        let confirm = snsConfirmationPayload(topicArn: topic).prettyPrinted()
        let second = "\(ConnectionProviders.normalizeRoot(prefix))\(sampleFileName(pattern: pattern))"
        let direct = SetupSnippet(
            key: "direct", title: "Direct: name the files", text: "Paths relative to the connection's folder, taken as they are.",
            code: "\(compact(["path": .string(rel)]))\n\(compact(["paths": [.string(rel), .string(second)]]))"
        )
        switch method {
        case .watch:
            return [SetupSnippet(
                key: "listing", title: "A listing entry",
                text: "Nothing is sent: Transcdr lists the folder and sees each file like this, relative to the connection's folder.",
                code: JSONValue.object([
                    "path": .string(rel), "size": .number(Double(sampleSize)),
                    "last_modified": "2026-09-27T10:14:03Z", "etag": .string(sampleETag),
                ]).prettyPrinted()
            )]
        case .queue:
            var out: [SetupSnippet] = fanout == .topic
                ? [
                    SetupSnippet(key: "sns", title: "SNS envelope", text: "The S3 event is the JSON string in Message. With raw message delivery on, the queue gets the S3 event itself.", code: envelope),
                    SetupSnippet(key: "s3", title: "S3 event notification (raw message delivery)", text: s3.text, code: s3.code),
                    SetupSnippet(key: "confirm", title: "SNS subscription confirmation", text: "From a topic in another account: Transcdr confirms it when it reaches the queue, then deletes the message.", code: confirm),
                ]
                : [s3]
            out.append(SetupSnippet(
                key: "eventbridge", title: "EventBridge", text: "When an EventBridge rule targets the queue. The key is taken as it is.",
                code: eventBridgePayload(bucket: b, key: key).prettyPrinted()
            ))
            out.append(direct)
            out.append(SetupSnippet(
                key: "job", title: "Job request",
                text: "A POST /v1/jobs body. The automation's settings fill whatever is missing; input may be a plain path in the bucket.",
                code: JSONValue.object(["input": .string(rel), "preset": "hls-h264-abr", "metadata": ["customer": "acme"]]).prettyPrinted()
            ))
            return out
        case .webhook:
            switch sender {
            case .aws:
                return [
                    SetupSnippet(key: "confirm", title: "SNS subscription confirmation", text: "Transcdr confirms it automatically. Nothing becomes a job.", code: confirm),
                    SetupSnippet(key: "sns", title: "SNS envelope", text: "The S3 event is the JSON string in Message.", code: envelope),
                ]
            case .minio:
                return [SetupSnippet(
                    key: "s3", title: "MinIO event notification", text: "MinIO posts S3-style records; the key is URL-form-encoded.",
                    code: s3EventPayload(bucket: b, key: key, source: "minio:s3").prettyPrinted()
                )]
            case .other:
                return [direct, SetupSnippet(key: "s3", title: s3.title, text: "An S3-style Records[] body works too; its key is the full bucket key, URL-form-encoded.", code: s3.code)]
            }
        }
    }

    // MARK: How it becomes a job

    /// Compact JSON for an object whose keys keep this order.
    static func orderedJSON(_ pairs: [(String, String)]) -> String {
        "{" + pairs.map { "\(compact(.string($0.0))):\(compact(.string($0.1)))" }.joined(separator: ",") + "}"
    }

    /// The input to follow a file from its payload.
    public struct TranslationInput: Sendable {
        /// The key or path as the payload carries it.
        public var key: String
        /// The key came from an S3 notification (encoded); otherwise it is taken as it is.
        public var encoded: Bool
        /// The key is already relative to the connection's folder: a direct path or a listing entry.
        public var relative: Bool
        public var bucket: String?
        public var eventBucket: String?
        public var root: String?
        public var prefix: String
        public var pattern: String
        public var sourceConnectionID: String?
        public var automationID: String?
        public var metadata: [String: String]
        /// The destination connection and its prefix template, or nil when outputs stay in Transcdr.
        public var destination: (connectionID: String, template: String)?
        public var now: Date

        public init(
            key: String, encoded: Bool, relative: Bool = false, bucket: String? = nil, eventBucket: String? = nil, root: String? = nil,
            prefix: String, pattern: String, sourceConnectionID: String? = nil, automationID: String? = nil,
            metadata: [String: String] = [:], destination: (connectionID: String, template: String)? = nil, now: Date = Date()
        ) {
            self.key = key
            self.encoded = encoded
            self.relative = relative
            self.bucket = bucket
            self.eventBucket = eventBucket
            self.root = root
            self.prefix = prefix
            self.pattern = pattern
            self.sourceConnectionID = sourceConnectionID
            self.automationID = automationID
            self.metadata = metadata
            self.destination = destination
            self.now = now
        }
    }

    /// Follow one file from the payload to the job, as the server does: decode the key (notifications only),
    /// check the bucket, make it relative to the root, filter by prefix and pattern, then build the job.
    public static func translate(_ input: TranslationInput) -> Translation {
        var steps: [TranslationStep] = []
        func stop(_ step: TranslationStep) -> Translation { Translation(steps: steps + [step], job: false) }

        let decoded = input.encoded ? decodeS3Key(input.key) : input.key
        steps.append(TranslationStep(label: "Key", value: decoded, ok: true, note: input.encoded && decoded != input.key ? "Decoded from \(input.key)" : nil))

        if let eventBucket = input.eventBucket, let bucket = input.bucket, eventBucket != bucket {
            return stop(TranslationStep(label: "Bucket", value: eventBucket, ok: false, note: "Not the connection's bucket (\(bucket)): skipped, and the last error says so."))
        }

        let path: String?
        if input.relative {
            let trimmed = String(decoded.drop { $0 == "/" })
            path = trimmed.isEmpty ? nil : trimmed
        } else {
            path = relativePath(root: input.root, key: decoded)
        }
        guard let path else {
            return stop(TranslationStep(label: "Path", value: "—", ok: false, note: "Outside the connection's folder \(ConnectionProviders.normalizeRoot(input.root ?? "")): skipped."))
        }
        let rootNote = !input.relative && !(input.root ?? "").isEmpty ? "Relative to the folder \(ConnectionProviders.normalizeRoot(input.root ?? ""))" : nil
        steps.append(TranslationStep(label: "Path", value: path, ok: true, note: rootNote))

        let prefix = String(input.prefix.trimmingCharacters(in: .whitespaces).drop { $0 == "/" })
        guard path.hasPrefix(prefix) else {
            return stop(TranslationStep(label: "Prefix", value: prefix, ok: false, note: "The path is not under the prefix: another automation's file, or none. Not an error."))
        }
        let pattern = or(input.pattern, "**/*")
        guard globMatch(pattern, path) else {
            return stop(TranslationStep(label: "Pattern", value: pattern, ok: false, note: "The path does not match the pattern: not this automation's file. Not an error."))
        }
        steps.append(TranslationStep(label: "Match", value: "\(prefix.isEmpty ? "(any prefix)" : prefix) · \(pattern)", ok: true))

        let automationID = or(input.automationID, "aut_…")
        steps.append(TranslationStep(
            label: "Job input",
            value: orderedJSON([("type", "connection"), ("connection_id", or(input.sourceConnectionID, "con_…")), ("path", path)]),
            ok: true
        ))
        let metadata = input.metadata.keys.sorted().map { ($0, input.metadata[$0] ?? "") } + [("automation_id", automationID), ("source_path", path)]
        steps.append(TranslationStep(label: "Metadata", value: orderedJSON(metadata), ok: true))
        if let destination = input.destination {
            var vars = pathVars(path, now: input.now)
            vars["automation"] = automationID
            let rendered = renderPrefix(destination.template, vars: vars)
            steps.append(TranslationStep(
                label: "Destination",
                value: orderedJSON([("connection_id", or(destination.connectionID, "con_…")), ("prefix", rendered)]),
                ok: true,
                note: rendered.contains("{job_id}") ? "{job_id} is filled once the job exists." : nil
            ))
        } else {
            steps.append(TranslationStep(label: "Destination", value: "None: outputs stay in Transcdr", ok: true))
        }
        return Translation(steps: steps, job: true)
    }
}

// MARK: - Create in order

/// The create-in-order plan: the storage connection (if new), the SQS connection (if new), then the automation
/// (created, or updated when the Webhook method made it early). A failed step keeps what was created before it,
/// and a retry resumes from that step without creating duplicates.
public struct AutomatePlan: Hashable, Sendable {
    public enum Step: String, CaseIterable, Sendable, Identifiable {
        case storage, queue, automation
        public var id: String { rawValue }
    }

    public enum Status: Hashable, Sendable {
        case waiting, running, done, failed(String)
    }

    public var method: AutomateMethod
    /// The storage connection is created by the wizard.
    public var newStorage: Bool
    /// The SQS connection is created by the wizard (Queue only).
    public var newQueue: Bool
    public var storageID: String?
    public var queueID: String?
    public var automationID: String?
    /// The automation has its final settings: created here, or updated after an early creation.
    public var automationSaved = false
    public var running: Step?
    public var failedStep: Step?
    public var failure: String?

    public init(method: AutomateMethod, storageID: String?, queueID: String? = nil, automationID: String? = nil) {
        self.method = method
        self.newStorage = storageID == nil
        self.newQueue = method == .queue && queueID == nil
        self.storageID = storageID
        self.queueID = queueID
        self.automationID = automationID
    }

    /// The steps to show, in order.
    public var steps: [Step] {
        var out: [Step] = []
        if newStorage { out.append(.storage) }
        if newQueue { out.append(.queue) }
        out.append(.automation)
        return out
    }

    public func isDone(_ step: Step) -> Bool {
        switch step {
        case .storage: storageID != nil
        case .queue: method != .queue || queueID != nil
        case .automation: automationSaved
        }
    }

    public func status(_ step: Step) -> Status {
        if isDone(step) { return .done }
        if running == step { return .running }
        if failedStep == step { return .failed(failure ?? "Failed.") }
        return .waiting
    }

    /// The next step to run.
    public var next: Step? { steps.first { !isDone($0) } }
    public var isComplete: Bool { next == nil }
    public var canRetry: Bool { failedStep != nil && running == nil }

    /// The automation step updates the one the Webhook method created early.
    public var updatesAutomation: Bool { automationID != nil }

    public func title(_ step: Step) -> String {
        switch step {
        case .storage: "Create the storage connection"
        case .queue: "Create the SQS connection"
        case .automation: updatesAutomation ? "Update the automation" : "Create the automation"
        }
    }

    public mutating func start(_ step: Step) {
        running = step
        failedStep = nil
        failure = nil
    }

    /// Record a step's result: the created connection's or automation's ID.
    public mutating func succeed(_ step: Step, id: String) {
        switch step {
        case .storage: storageID = id
        case .queue: queueID = id
        case .automation:
            automationID = id
            automationSaved = true
        }
        if running == step { running = nil }
    }

    /// The Webhook method's early creation: the automation exists, but step 5 still updates it.
    public mutating func createdEarly(automationID id: String) {
        automationID = id
        automationSaved = false
    }

    public mutating func fail(_ step: Step, message: String) {
        running = nil
        failedStep = step
        failure = message
    }
}
