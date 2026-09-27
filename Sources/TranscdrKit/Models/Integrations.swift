import Foundation

public struct ConnectionKind: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let s3: Self = "s3"
    public static let gcs: Self = "gcs"
    public static let azureBlob: Self = "azure_blob"
    public static let ftp: Self = "ftp"
    public static let ftps: Self = "ftps"
    public static let sftp: Self = "sftp"
    public static let http: Self = "http"
    public static let webdav: Self = "webdav"
    public static let sqs: Self = "sqs"
    public static let sns: Self = "sns"
    public static let webhook: Self = "webhook"

    public static let storage: [Self] = [.s3, .gcs, .azureBlob, .ftp, .ftps, .sftp, .http, .webdav]
    public static let messaging: [Self] = [.sqs, .sns, .webhook]

    /// Never a job input, a destination or an automation source.
    public var isMessaging: Bool { Self.messaging.contains(self) }
}

/// Non-secret settings. Which fields apply depends on the kind.
public struct ConnectionConfig: Codable, Hashable, Sendable {
    public var endpoint: String?
    public var bucket: String?
    public var region: String?
    public var pathStyle: Bool?
    public var account: String?
    public var host: String?
    public var port: Int?
    public var username: String?
    public var root: String?
    public var passive: Bool?
    public var hostKeyFingerprint: String?
    public var queueUrl: String?
    public var topicArn: String?
    public var url: String?
    public var messageGroupId: String?

    public init(
        endpoint: String? = nil, bucket: String? = nil, region: String? = nil, pathStyle: Bool? = nil,
        account: String? = nil, host: String? = nil, port: Int? = nil, username: String? = nil, root: String? = nil,
        passive: Bool? = nil, hostKeyFingerprint: String? = nil, queueUrl: String? = nil, topicArn: String? = nil,
        url: String? = nil, messageGroupId: String? = nil
    ) {
        self.endpoint = endpoint
        self.bucket = bucket
        self.region = region
        self.pathStyle = pathStyle
        self.account = account
        self.host = host
        self.port = port
        self.username = username
        self.root = root
        self.passive = passive
        self.hostKeyFingerprint = hostKeyFingerprint
        self.queueUrl = queueUrl
        self.topicArn = topicArn
        self.url = url
        self.messageGroupId = messageGroupId
    }

    enum CodingKeys: String, CodingKey {
        case endpoint, bucket, region, account, host, port, username, root, passive, url
        case pathStyle = "path_style"
        case hostKeyFingerprint = "host_key_fingerprint"
        case queueUrl = "queue_url"
        case topicArn = "topic_arn"
        case messageGroupId = "message_group_id"
    }

    /// The set fields as a flat map (for display and generic forms).
    public var fields: [String: String] {
        var out: [String: String] = [:]
        if let v = endpoint { out["endpoint"] = v }
        if let v = bucket { out["bucket"] = v }
        if let v = region { out["region"] = v }
        if let v = pathStyle { out["path_style"] = v ? "true" : "false" }
        if let v = account { out["account"] = v }
        if let v = host { out["host"] = v }
        if let v = port { out["port"] = String(v) }
        if let v = username { out["username"] = v }
        if let v = root { out["root"] = v }
        if let v = passive { out["passive"] = v ? "true" : "false" }
        if let v = hostKeyFingerprint { out["host_key_fingerprint"] = v }
        if let v = queueUrl { out["queue_url"] = v }
        if let v = topicArn { out["topic_arn"] = v }
        if let v = url { out["url"] = v }
        if let v = messageGroupId { out["message_group_id"] = v }
        return out
    }
}

/// Write-only credentials. On update an omitted secret is kept and `""` clears it.
public struct ConnectionSecrets: Codable, Hashable, Sendable {
    public var accessKeyId: String?
    public var secretAccessKey: String?
    public var sessionToken: String?
    public var password: String?
    public var privateKey: String?
    public var privateKeyPassphrase: String?
    public var serviceAccountJson: String?
    public var accountKey: String?
    public var sasToken: String?
    public var bearerToken: String?

    public init(
        accessKeyId: String? = nil, secretAccessKey: String? = nil, sessionToken: String? = nil, password: String? = nil,
        privateKey: String? = nil, privateKeyPassphrase: String? = nil, serviceAccountJson: String? = nil,
        accountKey: String? = nil, sasToken: String? = nil, bearerToken: String? = nil
    ) {
        self.accessKeyId = accessKeyId
        self.secretAccessKey = secretAccessKey
        self.sessionToken = sessionToken
        self.password = password
        self.privateKey = privateKey
        self.privateKeyPassphrase = privateKeyPassphrase
        self.serviceAccountJson = serviceAccountJson
        self.accountKey = accountKey
        self.sasToken = sasToken
        self.bearerToken = bearerToken
    }

    public enum CodingKeys: String, CodingKey, CaseIterable, Sendable {
        case accessKeyId = "access_key_id"
        case secretAccessKey = "secret_access_key"
        case sessionToken = "session_token"
        case password
        case privateKey = "private_key"
        case privateKeyPassphrase = "private_key_passphrase"
        case serviceAccountJson = "service_account_json"
        case accountKey = "account_key"
        case sasToken = "sas_token"
        case bearerToken = "bearer_token"
    }

    /// Set a secret by its wire name.
    public mutating func set(_ name: String, _ value: String?) {
        switch CodingKeys(rawValue: name) {
        case .accessKeyId: accessKeyId = value
        case .secretAccessKey: secretAccessKey = value
        case .sessionToken: sessionToken = value
        case .password: password = value
        case .privateKey: privateKey = value
        case .privateKeyPassphrase: privateKeyPassphrase = value
        case .serviceAccountJson: serviceAccountJson = value
        case .accountKey: accountKey = value
        case .sasToken: sasToken = value
        case .bearerToken: bearerToken = value
        case nil: break
        }
    }

    public var isEmpty: Bool { self == ConnectionSecrets() }
}

public struct ConnectionCapabilities: Codable, Hashable, Sendable {
    /// Storage: a job input or automation source.
    public var source: Bool
    /// Storage: outputs can be delivered here.
    public var destination: Bool
    /// Storage: can be listed, so a watch automation can poll it.
    public var watch: Bool
    /// Messaging (sqs): can trigger queue automations.
    public var trigger: Bool
    /// Messaging: can receive events.
    public var events: Bool

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decodeIfPresent(Bool.self, forKey: .source) ?? false
        destination = try c.decodeIfPresent(Bool.self, forKey: .destination) ?? false
        watch = try c.decodeIfPresent(Bool.self, forKey: .watch) ?? false
        trigger = try c.decodeIfPresent(Bool.self, forKey: .trigger) ?? false
        events = try c.decodeIfPresent(Bool.self, forKey: .events) ?? false
    }

    public init(source: Bool = false, destination: Bool = false, watch: Bool = false, trigger: Bool = false, events: Bool = false) {
        self.source = source
        self.destination = destination
        self.watch = watch
        self.trigger = trigger
        self.events = events
    }

    enum CodingKeys: String, CodingKey { case source, destination, watch, trigger, events }
}

public struct Connection: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var kind: ConnectionKind
    public var config: ConnectionConfig
    /// Names of the stored secrets (values are never returned).
    public var secretsSet: [String]
    public var capabilities: ConnectionCapabilities
    /// `untested`, `ok` or `error`.
    public var status: String
    /// `storage` or `messaging`.
    public var connectionClass: String
    /// Off after a permanent failure, or 5 transient ones in a row.
    public var enabled: Bool
    public var failureCount: Int
    public var disabledReason: String?
    public var disabledAt: Date?
    public var lastError: String?
    public var lastCheckedAt: Date?
    public var createdAt: Date?
    public var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, kind, config, capabilities, status, enabled
        case secretsSet = "secrets_set"
        case connectionClass = "class"
        case failureCount = "failure_count"
        case disabledReason = "disabled_reason"
        case disabledAt = "disabled_at"
        case lastError = "last_error"
        case lastCheckedAt = "last_checked_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        kind = try c.decode(ConnectionKind.self, forKey: .kind)
        config = try c.decodeIfPresent(ConnectionConfig.self, forKey: .config) ?? ConnectionConfig()
        secretsSet = try c.decodeList([String].self, forKey: .secretsSet)
        capabilities = try c.decodeIfPresent(ConnectionCapabilities.self, forKey: .capabilities) ?? ConnectionCapabilities()
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "untested"
        connectionClass = try c.decodeIfPresent(String.self, forKey: .connectionClass) ?? (kind.isMessaging ? "messaging" : "storage")
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        failureCount = try c.decodeIfPresent(Int.self, forKey: .failureCount) ?? 0
        disabledReason = try c.decodeIfPresent(String.self, forKey: .disabledReason)
        disabledAt = try c.decodeIfPresent(Date.self, forKey: .disabledAt)
        lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
        lastCheckedAt = try c.decodeIfPresent(Date.self, forKey: .lastCheckedAt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    public var isMessaging: Bool { connectionClass == "messaging" || kind.isMessaging }
}

public struct ConnectionCreateParams: Encodable, Sendable {
    public var name: String?
    public var kind: ConnectionKind
    public var config: ConnectionConfig
    public var secrets: ConnectionSecrets?

    public init(name: String?, kind: ConnectionKind, config: ConnectionConfig, secrets: ConnectionSecrets? = nil) {
        self.name = name
        self.kind = kind
        self.config = config
        self.secrets = secrets
    }
}

public struct ConnectionUpdateParams: Encodable, Sendable {
    public var name: String?
    /// `true` turns it back on (failures reset, tested again); `false` turns it off.
    public var enabled: Bool?
    /// Merged into the stored config.
    public var config: ConnectionConfig?
    public var secrets: ConnectionSecrets?

    public init(name: String? = nil, enabled: Bool? = nil, config: ConnectionConfig? = nil, secrets: ConnectionSecrets? = nil) {
        self.name = name
        self.enabled = enabled
        self.config = config
        self.secrets = secrets
    }
}

public struct ConnectionTestResult: Codable, Sendable {
    public var ok: Bool
    public var error: String?
    public var connection: Connection
}

// MARK: - Checks

public struct CheckStep: Codable, Hashable, Sendable, Identifiable {
    /// `settings`, `connect`, `identity`, `list`, `write`, `read`, `delete`, `deliver`, `publish`, `send`.
    public var id: String
    public var label: String
    /// `passed`, `failed` or `skipped`.
    public var status: String
    public var detail: String?
    /// On failure: what to change.
    public var hint: String?
    public var durationMs: Int?

    enum CodingKeys: String, CodingKey {
        case id, label, status, detail, hint
        case durationMs = "duration_ms"
    }

    public var passed: Bool { status == "passed" }
    public var failed: Bool { status == "failed" }
}

/// A connection or event-destination check: every permission tried for real.
public struct CheckReport: Decodable, Sendable {
    /// `connection_check` or `webhook_check`.
    public var object: String
    public var ok: Bool
    public var steps: [CheckStep]
    /// Who the credentials sign in as (`provider`, `arn`, `account`, …).
    public var identity: [String: String]?
    /// Provider-specific setup: `iam_policy`, `queue_policy_for_s3`, `notes`, …
    public var setup: JSONValue?
    /// Roles the target can serve: `source`, `watch_folder`, `destination`, `trigger`, `notifications`.
    public var roles: [String: Bool]
    /// Saved connections: the connection with its updated status.
    public var connection: Connection?
    /// Saved endpoints.
    public var endpoint: WebhookEndpoint?

    enum CodingKeys: String, CodingKey { case object, ok, steps, identity, setup, roles, connection, endpoint }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        object = try c.decodeIfPresent(String.self, forKey: .object) ?? ""
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? false
        steps = try c.decodeList([CheckStep].self, forKey: .steps)
        if let raw = try c.decodeIfPresent([String: JSONValue].self, forKey: .identity) {
            identity = raw.compactMapValues { $0.stringValue ?? $0.doubleValue.map { String(Int($0)) } }
        }
        setup = try c.decodeIfPresent(JSONValue.self, forKey: .setup)
        roles = (try? c.decodeMap([String: Bool].self, forKey: .roles)) ?? [:]
        connection = try? c.decodeIfPresent(Connection.self, forKey: .connection)
        endpoint = try? c.decodeIfPresent(WebhookEndpoint.self, forKey: .endpoint)
    }

    /// Setup notes, one line each.
    public var notes: [String] { setup?["notes"]?.arrayValue?.compactMap(\.stringValue) ?? [] }

    /// Setup documents (policies, notification configs) as pretty JSON, by key.
    public var setupDocuments: [(key: String, json: String)] {
        guard let object = setup?.objectValue else { return [] }
        return object.keys.sorted().compactMap { key in
            guard let value = object[key] else { return nil }
            switch value {
            case .object, .array: return key == "notes" ? nil : (key, value.prettyPrinted())
            default: return nil
            }
        }
    }

    /// Setup strings (role names, commands, SAS letters), by key.
    public var setupText: [(key: String, text: String)] {
        guard let object = setup?.objectValue else { return [] }
        return object.keys.sorted().compactMap { key in object[key]?.stringValue.map { (key, $0) } }
    }
}

/// A file (or, when `path` ends in `/`, a folder) in a connection.
public struct RemoteObject: Codable, Hashable, Sendable, Identifiable {
    public var path: String
    public var size: Int64?
    public var lastModified: Date?
    public var id: String { path }
    public var isFolder: Bool { path.hasSuffix("/") }

    enum CodingKeys: String, CodingKey {
        case path, size
        case lastModified = "last_modified"
    }
}

// MARK: - Automations

public struct AutomationTrigger: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    /// Polls the source.
    public static let watch: Self = "watch"
    /// Takes pushes at `hook_url`.
    public static let hook: Self = "hook"
    /// Consumes an SQS connection.
    public static let queue: Self = "queue"
    public static let all: [Self] = [.watch, .hook, .queue]
}

public struct AutomationSource: Codable, Hashable, Sendable {
    public var connectionId: String
    public var prefix: String?
    public var pattern: String?

    public init(connectionId: String, prefix: String? = nil, pattern: String? = nil) {
        self.connectionId = connectionId
        self.prefix = prefix
        self.pattern = pattern
    }

    enum CodingKeys: String, CodingKey {
        case connectionId = "connection_id"
        case prefix, pattern
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if !connectionId.isEmpty { try c.encode(connectionId, forKey: .connectionId) }
        try c.encodeIfPresent(prefix, forKey: .prefix)
        try c.encodeIfPresent(pattern, forKey: .pattern)
    }
}

public struct Automation: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var enabled: Bool
    public var trigger: AutomationTrigger
    /// `queue`: the sqs connection it consumes.
    public var triggerConnectionId: String?
    public var source: AutomationSource
    public var pollIntervalSeconds: Int
    public var settleSeconds: Int
    public var preset: String?
    /// Overrides merged over the preset.
    public var output: OutputSpec
    public var destination: JobDestination?
    /// `keep` or `delete`.
    public var afterSuccess: String
    public var priority: Priority
    public var metadata: Metadata
    public var webhookUrl: String?
    /// Push endpoint for trigger `hook`.
    public var hookUrl: String?
    public var jobsCreated: Int
    public var lastPolledAt: Date?
    public var lastTriggeredAt: Date?
    public var lastError: String?
    public var createdAt: Date?
    public var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, enabled, trigger, source, preset, output, destination, priority, metadata
        case triggerConnectionId = "trigger_connection_id"
        case pollIntervalSeconds = "poll_interval_seconds"
        case settleSeconds = "settle_seconds"
        case afterSuccess = "after_success"
        case webhookUrl = "webhook_url"
        case hookUrl = "hook_url"
        case jobsCreated = "jobs_created"
        case lastPolledAt = "last_polled_at"
        case lastTriggeredAt = "last_triggered_at"
        case lastError = "last_error"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        trigger = try c.decodeIfPresent(AutomationTrigger.self, forKey: .trigger) ?? .watch
        triggerConnectionId = try c.decodeIfPresent(String.self, forKey: .triggerConnectionId)
        source = try c.decodeIfPresent(AutomationSource.self, forKey: .source) ?? AutomationSource(connectionId: "")
        pollIntervalSeconds = try c.decodeIfPresent(Int.self, forKey: .pollIntervalSeconds) ?? 300
        settleSeconds = try c.decodeIfPresent(Int.self, forKey: .settleSeconds) ?? 60
        preset = try c.decodeIfPresent(String.self, forKey: .preset)
        output = (try? c.decodeIfPresent(OutputSpec.self, forKey: .output)) ?? OutputSpec()
        destination = try c.decodeIfPresent(JobDestination.self, forKey: .destination)
        afterSuccess = try c.decodeIfPresent(String.self, forKey: .afterSuccess) ?? "keep"
        priority = try c.decodeIfPresent(Priority.self, forKey: .priority) ?? .normal
        metadata = try c.decodeMap(Metadata.self, forKey: .metadata)
        webhookUrl = try c.decodeIfPresent(String.self, forKey: .webhookUrl)
        hookUrl = try c.decodeIfPresent(String.self, forKey: .hookUrl)
        jobsCreated = try c.decodeIfPresent(Int.self, forKey: .jobsCreated) ?? 0
        lastPolledAt = try c.decodeIfPresent(Date.self, forKey: .lastPolledAt)
        lastTriggeredAt = try c.decodeIfPresent(Date.self, forKey: .lastTriggeredAt)
        lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

/// Create (every required field set) or update (only what changes).
public struct AutomationParams: Encodable, Sendable {
    public var name: String?
    public var enabled: Bool?
    public var trigger: AutomationTrigger?
    /// Required for `queue`; `""` clears it.
    public var triggerConnectionId: String?
    public var source: AutomationSource?
    /// 60–86400.
    public var pollIntervalSeconds: Int?
    /// 0–86400.
    public var settleSeconds: Int?
    /// `""` clears it.
    public var preset: String?
    /// Overrides merged over the preset.
    public var output: OutputSpecInput?
    /// `.some(nil)` clears it.
    public var destination: JobDestination??
    public var afterSuccess: String?
    public var priority: Priority?
    public var metadata: Metadata?
    /// `""` clears it.
    public var webhookUrl: String?

    public init(
        name: String? = nil, enabled: Bool? = nil, trigger: AutomationTrigger? = nil, triggerConnectionId: String? = nil,
        source: AutomationSource? = nil, pollIntervalSeconds: Int? = nil, settleSeconds: Int? = nil, preset: String? = nil,
        output: OutputSpecInput? = nil, destination: JobDestination?? = nil, afterSuccess: String? = nil,
        priority: Priority? = nil, metadata: Metadata? = nil, webhookUrl: String? = nil
    ) {
        self.name = name
        self.enabled = enabled
        self.trigger = trigger
        self.triggerConnectionId = triggerConnectionId
        self.source = source
        self.pollIntervalSeconds = pollIntervalSeconds
        self.settleSeconds = settleSeconds
        self.preset = preset
        self.output = output
        self.destination = destination
        self.afterSuccess = afterSuccess
        self.priority = priority
        self.metadata = metadata
        self.webhookUrl = webhookUrl
    }

    enum CodingKeys: String, CodingKey {
        case name, enabled, trigger, source, preset, output, destination, priority, metadata
        case triggerConnectionId = "trigger_connection_id"
        case pollIntervalSeconds = "poll_interval_seconds"
        case settleSeconds = "settle_seconds"
        case afterSuccess = "after_success"
        case webhookUrl = "webhook_url"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(enabled, forKey: .enabled)
        try c.encodeIfPresent(trigger, forKey: .trigger)
        try c.encodeIfPresent(triggerConnectionId, forKey: .triggerConnectionId)
        try c.encodeIfPresent(source, forKey: .source)
        try c.encodeIfPresent(pollIntervalSeconds, forKey: .pollIntervalSeconds)
        try c.encodeIfPresent(settleSeconds, forKey: .settleSeconds)
        try c.encodeIfPresent(preset, forKey: .preset)
        try c.encodeIfPresent(output, forKey: .output)
        if let destination {
            if let destination { try c.encode(destination, forKey: .destination) } else { try c.encodeNil(forKey: .destination) }
        }
        try c.encodeIfPresent(afterSuccess, forKey: .afterSuccess)
        try c.encodeIfPresent(priority, forKey: .priority)
        try c.encodeIfPresent(metadata, forKey: .metadata)
        try c.encodeIfPresent(webhookUrl, forKey: .webhookUrl)
    }
}

public struct AutomationRun: Codable, Hashable, Sendable {
    public var jobsCreated: Int
    public var jobIds: [String]
    /// Queue automations: messages read in this batch.
    public var messagesReceived: Int?
    /// Queue automations: messages handled and removed.
    public var messagesDeleted: Int?

    enum CodingKeys: String, CodingKey {
        case jobsCreated = "jobs_created"
        case jobIds = "job_ids"
        case messagesReceived = "messages_received"
        case messagesDeleted = "messages_deleted"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        jobsCreated = try c.decodeIfPresent(Int.self, forKey: .jobsCreated) ?? 0
        jobIds = try c.decodeList([String].self, forKey: .jobIds)
        messagesReceived = try c.decodeIfPresent(Int.self, forKey: .messagesReceived)
        messagesDeleted = try c.decodeIfPresent(Int.self, forKey: .messagesDeleted)
    }
}

public struct AutomationItem: Codable, Hashable, Sendable, Identifiable {
    public var path: String
    public var sizeBytes: Int64?
    public var status: String
    public var jobId: String?
    public var error: String?
    public var createdAt: Date

    public var id: String { "\(path)#\(createdAt.timeIntervalSince1970)" }

    enum CodingKeys: String, CodingKey {
        case path, status, error
        case sizeBytes = "size_bytes"
        case jobId = "job_id"
        case createdAt = "created_at"
    }
}

public struct Delivery: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var connectionId: String
    public var prefix: String
    /// `waiting`, `pending`, `running`, `succeeded`, `failed`.
    public var status: String
    public var files: Int
    public var bytes: Int64
    public var attempts: Int
    public var error: String?
    public var nextRetryAt: Date?
    public var createdAt: Date
    public var completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, prefix, status, files, bytes, attempts, error
        case connectionId = "connection_id"
        case nextRetryAt = "next_retry_at"
        case createdAt = "created_at"
        case completedAt = "completed_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        connectionId = try c.decodeIfPresent(String.self, forKey: .connectionId) ?? ""
        prefix = try c.decodeIfPresent(String.self, forKey: .prefix) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "pending"
        files = try c.decodeIfPresent(Int.self, forKey: .files) ?? 0
        bytes = try c.decodeIfPresent(Int64.self, forKey: .bytes) ?? 0
        attempts = try c.decodeIfPresent(Int.self, forKey: .attempts) ?? 0
        error = try c.decodeIfPresent(String.self, forKey: .error)
        nextRetryAt = try c.decodeIfPresent(Date.self, forKey: .nextRetryAt)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
    }
}
