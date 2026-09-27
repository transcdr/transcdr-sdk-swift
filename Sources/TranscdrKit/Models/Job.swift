import Foundation

public struct JobStatus: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let queued: Self = "queued"
    public static let scheduled: Self = "scheduled"
    public static let running: Self = "running"
    public static let uploading: Self = "uploading"
    public static let completed: Self = "completed"
    public static let failed: Self = "failed"
    public static let canceled: Self = "canceled"
    public static let all: [Self] = [.queued, .scheduled, .running, .uploading, .completed, .failed, .canceled]
    public static let terminal: [Self] = [.completed, .failed, .canceled]

    /// No further transitions happen on their own.
    public var isTerminal: Bool { Self.terminal.contains(self) }
    /// Waiting for or holding a worker.
    public var isActive: Bool { !isTerminal }
}

public struct JobKind: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let transcode: Self = "transcode"
    public static let probe: Self = "probe"
}

public struct Stage: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let waiting: Self = "waiting"
    public static let fetching: Self = "fetching"
    public static let probing: Self = "probing"
    public static let encoding: Self = "encoding"
    public static let uploading: Self = "uploading"
    public static let done: Self = "done"
}

public struct RenditionStatus: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let pending: Self = "pending"
    public static let running: Self = "running"
    public static let finalizing: Self = "finalizing"
    public static let completed: Self = "completed"
    public static let failed: Self = "failed"
}

public struct Priority: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let normal: Self = "normal"
    public static let high: Self = "high"
}

public struct Tier: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let sd: Self = "sd"
    public static let hd: Self = "hd"
    public static let uhd: Self = "uhd"
    public static let all: [Self] = [.sd, .hd, .uhd]
}

/// Where a job reads its input.
public enum JobInput: Codable, Hashable, Sendable {
    case url(String)
    case asset(String)
    /// A file in one of your connections (Starter plan and above).
    case connection(id: String, path: String)
    case unknown(type: String)

    enum CodingKeys: String, CodingKey {
        case type, url
        case assetId = "asset_id"
        case connectionId = "connection_id"
        case path
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        switch type {
        case "url": self = .url(try c.decodeIfPresent(String.self, forKey: .url) ?? "")
        case "asset": self = .asset(try c.decodeIfPresent(String.self, forKey: .assetId) ?? "")
        case "connection":
            self = .connection(
                id: try c.decodeIfPresent(String.self, forKey: .connectionId) ?? "",
                path: try c.decodeIfPresent(String.self, forKey: .path) ?? ""
            )
        default: self = .unknown(type: type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .url(let url):
            try c.encode("url", forKey: .type)
            try c.encode(url, forKey: .url)
        case .asset(let id):
            try c.encode("asset", forKey: .type)
            try c.encode(id, forKey: .assetId)
        case .connection(let id, let path):
            try c.encode("connection", forKey: .type)
            try c.encode(id, forKey: .connectionId)
            try c.encode(path, forKey: .path)
        case .unknown(let type):
            try c.encode(type, forKey: .type)
        }
    }

    /// A one-line description: the URL, the asset id, or `con_…:path`.
    public var summary: String {
        switch self {
        case .url(let url): return url
        case .asset(let id): return id
        case .connection(let id, let path): return "\(id):\(path)"
        case .unknown(let type): return type
        }
    }
}

/// Where to deliver a job's outputs when it completes.
public struct JobDestination: Codable, Hashable, Sendable {
    public var connectionId: String
    /// A prefix template: `{job_id}`, `{name}`, `{stem}`, `{ext}`, `{dir}`, `{date}`, `{automation}`, `{org}`.
    public var prefix: String?

    public init(connectionId: String, prefix: String? = nil) {
        self.connectionId = connectionId
        self.prefix = prefix
    }

    enum CodingKeys: String, CodingKey {
        case connectionId = "connection_id"
        case prefix
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(connectionId, forKey: .connectionId)
        try c.encodeIfPresent(prefix, forKey: .prefix)
    }
}

public struct RenditionProgress: Codable, Hashable, Sendable, Identifiable {
    public var index: Int
    public var label: String
    public var width: Int
    public var height: Int
    public var status: RenditionStatus
    public var percent: Double
    public var framesDone: Int
    public var framesTotal: Int?
    public var segmentsWritten: Int
    public var bytesOut: Int64
    public var message: String?

    public var id: Int { index }

    enum CodingKeys: String, CodingKey {
        case index, label, width, height, status, percent, message
        case framesDone = "frames_done"
        case framesTotal = "frames_total"
        case segmentsWritten = "segments_written"
        case bytesOut = "bytes_out"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        index = try c.decodeIfPresent(Int.self, forKey: .index) ?? 0
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        width = try c.decodeIfPresent(Int.self, forKey: .width) ?? 0
        height = try c.decodeIfPresent(Int.self, forKey: .height) ?? 0
        status = try c.decodeIfPresent(RenditionStatus.self, forKey: .status) ?? .pending
        percent = try c.decodeIfPresent(Double.self, forKey: .percent) ?? 0
        framesDone = try c.decodeIfPresent(Int.self, forKey: .framesDone) ?? 0
        framesTotal = try c.decodeIfPresent(Int.self, forKey: .framesTotal)
        segmentsWritten = try c.decodeIfPresent(Int.self, forKey: .segmentsWritten) ?? 0
        bytesOut = try c.decodeIfPresent(Int64.self, forKey: .bytesOut) ?? 0
        message = try c.decodeIfPresent(String.self, forKey: .message)
    }
}

public struct Progress: Codable, Hashable, Sendable {
    public var percent: Double
    public var stage: Stage
    public var renditions: [RenditionProgress]

    public init(percent: Double = 0, stage: Stage = .waiting, renditions: [RenditionProgress] = []) {
        self.percent = percent
        self.stage = stage
        self.renditions = renditions
    }

    enum CodingKeys: String, CodingKey { case percent, stage, renditions }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        percent = try c.decodeIfPresent(Double.self, forKey: .percent) ?? 0
        stage = try c.decodeIfPresent(Stage.self, forKey: .stage) ?? .waiting
        renditions = try c.decodeList([RenditionProgress].self, forKey: .renditions)
    }
}

public struct JobOutput: Codable, Hashable, Sendable, Identifiable {
    public var label: String
    public var width: Int
    public var height: Int
    public var frames: Int
    public var bytes: Int64
    public var contentType: String
    /// Relative to the job's output root, e.g. `1080p.mp4`.
    public var path: String
    public var url: String

    public var id: String { label }

    enum CodingKeys: String, CodingKey {
        case label, width, height, frames, bytes, path, url
        case contentType = "content_type"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        width = try c.decodeIfPresent(Int.self, forKey: .width) ?? 0
        height = try c.decodeIfPresent(Int.self, forKey: .height) ?? 0
        frames = try c.decodeIfPresent(Int.self, forKey: .frames) ?? 0
        bytes = try c.decodeIfPresent(Int64.self, forKey: .bytes) ?? 0
        contentType = try c.decodeIfPresent(String.self, forKey: .contentType) ?? "application/octet-stream"
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
    }
}

public struct JobError: Codable, Hashable, Sendable {
    /// Stable code, e.g. `decode_failed`, `input_unreachable`.
    public var code: String
    public var message: String
    public var retryable: Bool
}

public struct JobBilling: Codable, Hashable, Sendable {
    public var billableMinutes: Double
    /// Rounded up to the cent.
    public var amountCents: Int
    /// Exact, in dollars.
    public var amountUsd: Double?
    public var tier: Tier?
    /// Seconds of output, once known.
    public var outputDuration: Double?

    enum CodingKeys: String, CodingKey {
        case tier
        case billableMinutes = "billable_minutes"
        case amountCents = "amount_cents"
        case amountUsd = "amount_usd"
        case outputDuration = "output_duration"
    }
}

public struct Job: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var kind: JobKind?
    public var status: JobStatus
    public var input: JobInput
    public var inputInfo: MediaInfo?
    public var presetId: String?
    public var output: OutputSpec
    public var priority: Priority
    public var progress: Progress
    public var outputs: [JobOutput]
    /// HLS: the bearer-authenticated master playlist.
    public var playlistUrl: String?
    /// Completed jobs: a signed, expiring (6 h) URL a player can load without a header.
    public var playbackUrl: String?
    public var error: JobError?
    public var metadata: Metadata
    public var webhookUrl: String?
    public var attempts: Int
    public var maxAttempts: Int
    public var billing: JobBilling?
    public var livemode: Bool?
    public var createdAt: Date
    public var scheduledAt: Date?
    public var startedAt: Date?
    public var completedAt: Date?
    public var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, kind, status, input, output, priority, progress, outputs, error, metadata, attempts, billing, livemode
        case inputInfo = "input_info"
        case presetId = "preset_id"
        case playlistUrl = "playlist_url"
        case playbackUrl = "playback_url"
        case webhookUrl = "webhook_url"
        case maxAttempts = "max_attempts"
        case createdAt = "created_at"
        case scheduledAt = "scheduled_at"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decodeIfPresent(JobKind.self, forKey: .kind)
        status = try c.decode(JobStatus.self, forKey: .status)
        input = try c.decodeIfPresent(JobInput.self, forKey: .input) ?? .unknown(type: "")
        inputInfo = try c.decodeIfPresent(MediaInfo.self, forKey: .inputInfo)
        presetId = try c.decodeIfPresent(String.self, forKey: .presetId)
        output = try c.decodeIfPresent(OutputSpec.self, forKey: .output) ?? OutputSpec()
        priority = try c.decodeIfPresent(Priority.self, forKey: .priority) ?? .normal
        progress = try c.decodeIfPresent(Progress.self, forKey: .progress) ?? Progress()
        outputs = try c.decodeList([JobOutput].self, forKey: .outputs)
        playlistUrl = try c.decodeIfPresent(String.self, forKey: .playlistUrl)
        playbackUrl = try c.decodeIfPresent(String.self, forKey: .playbackUrl)
        error = try c.decodeIfPresent(JobError.self, forKey: .error)
        metadata = try c.decodeMap(Metadata.self, forKey: .metadata)
        webhookUrl = try c.decodeIfPresent(String.self, forKey: .webhookUrl)
        attempts = try c.decodeIfPresent(Int.self, forKey: .attempts) ?? 0
        maxAttempts = try c.decodeIfPresent(Int.self, forKey: .maxAttempts) ?? 0
        billing = try c.decodeIfPresent(JobBilling.self, forKey: .billing)
        livemode = try c.decodeIfPresent(Bool.self, forKey: .livemode)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        scheduledAt = try c.decodeIfPresent(Date.self, forKey: .scheduledAt)
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

public struct JobCreateParams: Encodable, Sendable {
    public var input: JobInput
    /// Overrides merged over the preset's spec (see `SpecTools.diff`).
    public var output: OutputSpecInput?
    /// A system preset slug (e.g. `hls-av1-abr`) or a `pre_…` id.
    public var preset: String?
    public var priority: Priority?
    public var metadata: Metadata?
    public var webhookUrl: String?
    public var destination: JobDestination?
    /// Refuse the job (`cost_limit_exceeded`) if it would cost more than this.
    public var maxCostCents: Int?

    public init(
        input: JobInput, output: OutputSpecInput? = nil, preset: String? = nil, priority: Priority? = nil,
        metadata: Metadata? = nil, webhookUrl: String? = nil, destination: JobDestination? = nil, maxCostCents: Int? = nil
    ) {
        self.input = input
        self.output = output
        self.preset = preset
        self.priority = priority
        self.metadata = metadata
        self.webhookUrl = webhookUrl
        self.destination = destination
        self.maxCostCents = maxCostCents
    }

    enum CodingKeys: String, CodingKey {
        case input, output, preset, priority, metadata, destination
        case webhookUrl = "webhook_url"
        case maxCostCents = "max_cost_cents"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(input, forKey: .input)
        if let output, !output.isEmpty { try c.encode(output, forKey: .output) }
        try c.encodeIfPresent(preset, forKey: .preset)
        try c.encodeIfPresent(priority, forKey: .priority)
        if let metadata, !metadata.isEmpty { try c.encode(metadata, forKey: .metadata) }
        try c.encodeIfPresent(webhookUrl, forKey: .webhookUrl)
        try c.encodeIfPresent(destination, forKey: .destination)
        try c.encodeIfPresent(maxCostCents, forKey: .maxCostCents)
    }
}

public struct JobEvent: Codable, Hashable, Sendable {
    public var type: String
    public var message: String
    public var data: JSONValue?
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case type, message, data
        case createdAt = "created_at"
    }
}

public struct SignedURL: Codable, Hashable, Sendable {
    public var url: String
    public var expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case url
        case expiresAt = "expires_at"
    }
}

// MARK: - Assets and uploads

public struct AssetStatus: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let pendingUpload: Self = "pending_upload"
    public static let ready: Self = "ready"
    public static let failed: Self = "failed"
    public static let deleted: Self = "deleted"
}

public struct Asset: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var status: AssetStatus
    public var filename: String
    public var contentType: String
    public var sizeBytes: Int64
    public var checksumSha256: String?
    public var inputInfo: MediaInfo?
    public var metadata: Metadata
    public var downloadUrl: String?
    /// Set for assets linked by URL.
    public var sourceUrl: String?
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, status, filename, metadata
        case contentType = "content_type"
        case sizeBytes = "size_bytes"
        case checksumSha256 = "checksum_sha256"
        case inputInfo = "input_info"
        case downloadUrl = "download_url"
        case sourceUrl = "source_url"
        case createdAt = "created_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        status = try c.decodeIfPresent(AssetStatus.self, forKey: .status) ?? .ready
        filename = try c.decodeIfPresent(String.self, forKey: .filename) ?? ""
        contentType = try c.decodeIfPresent(String.self, forKey: .contentType) ?? ""
        sizeBytes = try c.decodeIfPresent(Int64.self, forKey: .sizeBytes) ?? 0
        checksumSha256 = try c.decodeIfPresent(String.self, forKey: .checksumSha256)
        inputInfo = try c.decodeIfPresent(MediaInfo.self, forKey: .inputInfo)
        metadata = try c.decodeMap(Metadata.self, forKey: .metadata)
        downloadUrl = try c.decodeIfPresent(String.self, forKey: .downloadUrl)
        sourceUrl = try c.decodeIfPresent(String.self, forKey: .sourceUrl)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }
}

public struct AssetImportParams: Encodable, Sendable {
    public var url: String
    public var filename: String?
    public var metadata: Metadata?

    public init(url: String, filename: String? = nil, metadata: Metadata? = nil) {
        self.url = url
        self.filename = filename
        self.metadata = metadata
    }
}

public struct Upload: Codable, Hashable, Sendable {
    public var id: String
    public var assetId: String
    public var status: String
    public var uploadUrl: String
    public var uploadMethod: String
    public var uploadHeaders: [String: String]
    public var expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, status
        case assetId = "asset_id"
        case uploadUrl = "upload_url"
        case uploadMethod = "upload_method"
        case uploadHeaders = "upload_headers"
        case expiresAt = "expires_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        assetId = try c.decodeIfPresent(String.self, forKey: .assetId) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "pending"
        uploadUrl = try c.decode(String.self, forKey: .uploadUrl)
        uploadMethod = try c.decodeIfPresent(String.self, forKey: .uploadMethod) ?? "PUT"
        uploadHeaders = try c.decodeMap([String: String].self, forKey: .uploadHeaders)
        expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
    }
}

public struct UploadCreateParams: Encodable, Sendable {
    public var filename: String
    public var contentType: String
    public var sizeBytes: Int64
    public var metadata: Metadata?

    public init(filename: String, contentType: String, sizeBytes: Int64, metadata: Metadata? = nil) {
        self.filename = filename
        self.contentType = contentType
        self.sizeBytes = sizeBytes
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case filename, metadata
        case contentType = "content_type"
        case sizeBytes = "size_bytes"
    }
}

// MARK: - Presets

public struct Preset: Codable, Hashable, Sendable, Identifiable {
    /// `pre_…`, or the slug for system presets.
    public var id: String
    public var slug: String
    public var name: String
    public var description: String
    public var system: Bool
    public var output: OutputSpec
    public var metadata: Metadata
    public var createdAt: Date?
    public var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, slug, name, description, system, output, metadata
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        slug = try c.decodeIfPresent(String.self, forKey: .slug) ?? id
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? slug
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        system = try c.decodeIfPresent(Bool.self, forKey: .system) ?? false
        output = try c.decodeIfPresent(OutputSpec.self, forKey: .output) ?? OutputSpec()
        metadata = try c.decodeMap(Metadata.self, forKey: .metadata)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

/// Create, or update (`PATCH`: only what changes; `output` merges into the stored spec).
public struct PresetParams: Encodable, Sendable {
    public var name: String?
    public var slug: String?
    public var description: String?
    /// A preset's full spec: `OutputSpecInput(spec)`; on update, a diff works too.
    public var output: OutputSpecInput?
    public var metadata: Metadata?
    /// Fields to clear on update: sent as `null` unless they are also set.
    public var clear: Set<Field>

    public enum Field: String, Hashable, Sendable, CaseIterable {
        case description, metadata
    }

    public init(name: String? = nil, slug: String? = nil, description: String? = nil, output: OutputSpecInput? = nil, metadata: Metadata? = nil, clear: Set<Field> = []) {
        self.name = name
        self.slug = slug
        self.description = description
        self.output = output
        self.metadata = metadata
        self.clear = clear
    }

    enum CodingKeys: String, CodingKey { case name, slug, description, output, metadata }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(slug, forKey: .slug)
        if let description { try c.encode(description, forKey: .description) } else if clear.contains(.description) { try c.encodeNil(forKey: .description) }
        try c.encodeIfPresent(output, forKey: .output)
        if let metadata { try c.encode(metadata, forKey: .metadata) } else if clear.contains(.metadata) { try c.encodeNil(forKey: .metadata) }
    }
}

/// A whole preset, for `presets.replace` (`PUT`). `output` is the full spec: a
/// field left out takes its default, as on create. `description` and `metadata`
/// left out are emptied; `slug` left out is kept.
public struct PresetReplaceParams: Encodable, Sendable {
    public var name: String
    public var output: OutputSpecInput
    public var slug: String?
    public var description: String?
    public var metadata: Metadata?

    public init(name: String, output: OutputSpecInput, slug: String? = nil, description: String? = nil, metadata: Metadata? = nil) {
        self.name = name
        self.output = output
        self.slug = slug
        self.description = description
        self.metadata = metadata
    }
}
