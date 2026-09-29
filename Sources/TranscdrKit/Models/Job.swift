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
    /// An output image of up to 1 megapixel.
    public static let upTo1mp: Self = "up_to_1mp"
    /// An output image of over 1, up to 4 megapixels.
    public static let upTo4mp: Self = "up_to_4mp"
    /// An output image of over 4 megapixels.
    public static let over4mp: Self = "over_4mp"
    /// The image tiers, by the pixels an output image came out at.
    public static let imageTiers: [Self] = [.upTo1mp, .upTo4mp, .over4mp]

    /// One of `imageTiers`.
    public var isImage: Bool { Self.imageTiers.contains(self) }
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
    /// Image output: the file's format.
    public var format: ImageFormat?
    /// Image output: the rendition it was made for (its label, or the size it came out at).
    public var rendition: String?
    /// Image output of a video with several stills: which still, from 1.
    public var frame: Int?
    /// Image output of a video: the still's time, in seconds.
    public var atSeconds: Double?

    public var id: String { label }

    enum CodingKeys: String, CodingKey {
        case label, width, height, frames, bytes, path, url, format, rendition, frame
        case contentType = "content_type"
        case atSeconds = "at_seconds"
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
        format = try c.decodeIfPresent(ImageFormat.self, forKey: .format)
        rendition = try c.decodeIfPresent(String.self, forKey: .rendition)
        frame = try c.decodeIfPresent(Int.self, forKey: .frame)
        atSeconds = try c.decodeIfPresent(Double.self, forKey: .atSeconds)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(label, forKey: .label)
        try c.encode(width, forKey: .width)
        try c.encode(height, forKey: .height)
        try c.encode(frames, forKey: .frames)
        try c.encode(bytes, forKey: .bytes)
        try c.encode(contentType, forKey: .contentType)
        try c.encode(path, forKey: .path)
        try c.encode(url, forKey: .url)
        try c.encodeIfPresent(format, forKey: .format)
        try c.encodeIfPresent(rendition, forKey: .rendition)
        try c.encodeIfPresent(frame, forKey: .frame)
        try c.encodeIfPresent(atSeconds, forKey: .atSeconds)
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
    /// Image output: the images billed (an image job bills no minutes).
    public var billableImages: Int?
    /// Rounded up to the cent.
    public var amountCents: Int
    /// Exact, in dollars.
    public var amountUsd: Double?
    /// `sd`, `hd` or `uhd`; for an image job one of `Tier.imageTiers`.
    public var tier: Tier?
    /// Seconds of output, once known.
    public var outputDuration: Double?

    enum CodingKeys: String, CodingKey {
        case tier
        case billableMinutes = "billable_minutes"
        case billableImages = "billable_images"
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
    /// The preset version and overrides the spec was resolved from; nil for a job given its
    /// whole spec.
    public var preset: PresetProvenance?
    /// The resolved, complete spec: what runs. Rerunning or duplicating a job uses it.
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
        case id, kind, status, input, preset, output, priority, progress, outputs, error, metadata, attempts, billing, livemode
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
        preset = try c.decodeIfPresent(PresetProvenance.self, forKey: .preset)
        output = try c.decode(OutputSpec.self, forKey: .output)
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

/// What a job makes: a preset (with optional overrides), or a whole spec. There is no third
/// choice: a request always says what it produces.
public enum JobSpec: Hashable, Sendable {
    /// A preset: a system slug (`hls-h264-abr`), your preset's slug or `pre_…` id for its latest
    /// version, or `slug@N` for version N. `overrides` merge over it; the result must be complete.
    case preset(String, overrides: OutputOverrides?)
    /// A whole, complete spec. Checked with `OutputRules` before it is sent.
    case output(OutputSpec)
}

public struct JobCreateParams: Encodable, Sendable {
    public var input: JobInput
    public var spec: JobSpec
    public var priority: Priority?
    public var metadata: Metadata?
    public var webhookUrl: String?
    public var destination: JobDestination?
    /// Refuse the job (`cost_limit_exceeded`) if it would cost more than this.
    public var maxCostCents: Int?

    public init(
        input: JobInput, spec: JobSpec, priority: Priority? = nil, metadata: Metadata? = nil, webhookUrl: String? = nil,
        destination: JobDestination? = nil, maxCostCents: Int? = nil
    ) {
        self.input = input
        self.spec = spec
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
        switch spec {
        case .preset(let preset, let overrides):
            try c.encode(preset, forKey: .preset)
            if let overrides, !overrides.isEmpty { try c.encode(overrides, forKey: .output) }
        case .output(let output):
            try c.encode(output, forKey: .output)
        }
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

/// The group a preset is shown in. More may be added.
public struct PresetCategory: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    /// A single MP4 for browsers.
    public static let web: Self = "web"
    /// A single file for native iOS and Android playback.
    public static let mobile: Self = "mobile"
    /// Adaptive HLS.
    public static let streaming: Self = "streaming"
    /// Smart TVs, set-top boxes and constant bit rate.
    public static let tv: Self = "tv"
    /// Portrait video for social apps.
    public static let social: Self = "social"
    /// Audio-only output.
    public static let audio: Self = "audio"
    /// Preservation and mastering: visually lossless, HDR.
    public static let archive: Self = "archive"
    /// Still images.
    public static let image: Self = "image"
    /// Every known category, in display order.
    public static let all: [Self] = [.web, .mobile, .streaming, .tv, .social, .audio, .archive, .image]
}

/// Where an output plays. More may be added.
public struct Platform: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    /// Current Chrome, Edge, Firefox and Safari.
    public static let web: Self = "web"
    public static let ios: Self = "ios"
    public static let android: Self = "android"
    public static let smartTV: Self = "smart_tv"
    /// Old browsers and devices, set-top boxes.
    public static let legacy: Self = "legacy"
    /// Editing applications.
    public static let editing: Self = "editing"
    /// Every known platform, in display order.
    public static let all: [Self] = [.web, .ios, .android, .smartTV, .legacy, .editing]
}

public struct Preset: Codable, Hashable, Sendable, Identifiable {
    /// `pre_…`, or the slug for system presets.
    public var id: String
    public var slug: String
    public var name: String
    public var description: String
    public var system: Bool
    /// The group it is shown in: its own, else derived from `output`.
    /// Nil from a server that predates categories.
    public var category: PresetCategory?
    /// Where the output plays: its own, else derived from `output`.
    public var compatibility: [Platform]
    /// Minimum versions and conditions, keyed by `Platform.rawValue`, for
    /// each platform in `compatibility`.
    public var compatibilityNotes: [String: String]
    /// Its latest version. Versions never change: editing the output adds one.
    public var version: Int
    /// The latest version's spec, complete.
    public var output: OutputSpec
    public var metadata: Metadata
    public var createdAt: Date?
    public var updatedAt: Date?

    /// `slug@N`: this exact version, as a job's `preset` names it.
    public var pinned: String { "\(slug)@\(version)" }

    /// This platform's note, if it has one.
    public func note(for platform: Platform) -> String? { compatibilityNotes[platform.rawValue] }

    enum CodingKeys: String, CodingKey {
        case id, slug, name, description, system, category, compatibility, version, output, metadata
        case compatibilityNotes = "compatibility_notes"
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
        category = try c.decodeIfPresent(PresetCategory.self, forKey: .category)
        compatibility = try c.decodeList([Platform].self, forKey: .compatibility)
        compatibilityNotes = try c.decodeMap([String: String].self, forKey: .compatibilityNotes)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        output = try c.decode(OutputSpec.self, forKey: .output)
        metadata = try c.decodeMap(Metadata.self, forKey: .metadata)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

/// One version of a preset: a complete spec that never changes.
public struct PresetVersion: Codable, Hashable, Sendable {
    public var version: Int
    public var output: OutputSpec
    /// Nil for a system preset's versions.
    public var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case version, output
        case createdAt = "created_at"
    }
}

/// A new preset (`POST`): `output` is its complete spec, version 1.
public struct PresetCreateParams: Encodable, Sendable {
    public var name: String
    public var output: OutputSpec
    public var slug: String?
    public var description: String?
    public var metadata: Metadata?
    /// Your own category; left out, it is derived from `output`.
    public var category: PresetCategory?
    /// The platforms to claim; left out, they are derived from `output`.
    public var compatibility: [Platform]?
    /// Notes over the derived ones, keyed by `Platform.rawValue`, only for platforms the preset
    /// claims; 1–500 characters each.
    public var compatibilityNotes: [String: String]?

    public init(
        name: String, output: OutputSpec, slug: String? = nil, description: String? = nil, metadata: Metadata? = nil,
        category: PresetCategory? = nil, compatibility: [Platform]? = nil, compatibilityNotes: [String: String]? = nil
    ) {
        self.name = name
        self.output = output
        self.slug = slug
        self.description = description
        self.metadata = metadata
        self.category = category
        self.compatibility = compatibility
        self.compatibilityNotes = compatibilityNotes
    }

    enum CodingKeys: String, CodingKey {
        case name, output, slug, description, metadata, category, compatibility
        case compatibilityNotes = "compatibility_notes"
    }
}

/// A change (`PATCH`): only what changes. `output` merges over the latest version, and a
/// changed spec is a new version.
public struct PresetParams: Encodable, Sendable {
    public var name: String?
    public var slug: String?
    public var description: String?
    /// Fields over the latest version (see `OutputOverrides`); the result must be complete.
    public var output: OutputOverrides?
    public var metadata: Metadata?
    /// Your own category; left out, it is derived from `output`.
    public var category: PresetCategory?
    /// The platforms to claim; left out, they are derived from `output`.
    public var compatibility: [Platform]?
    /// Notes over the derived ones, keyed by `Platform.rawValue`, only for
    /// platforms the preset claims; 1–500 characters each.
    public var compatibilityNotes: [String: String]?
    /// Fields to clear on update: sent as `null` unless they are also set.
    /// Clearing `category`, `compatibility` or `compatibilityNotes` derives
    /// them from `output` again.
    public var clear: Set<Field>

    public enum Field: String, Hashable, Sendable, CaseIterable {
        case description, metadata, category, compatibility
        case compatibilityNotes = "compatibility_notes"
    }

    public init(
        name: String? = nil, slug: String? = nil, description: String? = nil, output: OutputOverrides? = nil, metadata: Metadata? = nil,
        category: PresetCategory? = nil, compatibility: [Platform]? = nil, compatibilityNotes: [String: String]? = nil, clear: Set<Field> = []
    ) {
        self.name = name
        self.slug = slug
        self.description = description
        self.output = output
        self.metadata = metadata
        self.category = category
        self.compatibility = compatibility
        self.compatibilityNotes = compatibilityNotes
        self.clear = clear
    }

    enum CodingKeys: String, CodingKey {
        case name, slug, description, output, metadata, category, compatibility
        case compatibilityNotes = "compatibility_notes"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encodeIfPresent(slug, forKey: .slug)
        if let description { try c.encode(description, forKey: .description) } else if clear.contains(.description) { try c.encodeNil(forKey: .description) }
        try c.encodeIfPresent(output, forKey: .output)
        if let metadata { try c.encode(metadata, forKey: .metadata) } else if clear.contains(.metadata) { try c.encodeNil(forKey: .metadata) }
        if let category { try c.encode(category, forKey: .category) } else if clear.contains(.category) { try c.encodeNil(forKey: .category) }
        if let compatibility { try c.encode(compatibility, forKey: .compatibility) } else if clear.contains(.compatibility) { try c.encodeNil(forKey: .compatibility) }
        if let compatibilityNotes { try c.encode(compatibilityNotes, forKey: .compatibilityNotes) } else if clear.contains(.compatibilityNotes) { try c.encodeNil(forKey: .compatibilityNotes) }
    }
}

/// A whole preset, for `presets.replace` (`PUT`). `output` is the complete spec; a changed
/// spec is a new version. `description` and `metadata` left out are emptied; `category`,
/// `compatibility` and `compatibilityNotes` left out are derived again; `slug` left out is kept.
public struct PresetReplaceParams: Encodable, Sendable {
    public var name: String
    public var output: OutputSpec
    public var slug: String?
    public var description: String?
    public var metadata: Metadata?
    public var category: PresetCategory?
    public var compatibility: [Platform]?
    /// Keyed by `Platform.rawValue`.
    public var compatibilityNotes: [String: String]?

    public init(
        name: String, output: OutputSpec, slug: String? = nil, description: String? = nil, metadata: Metadata? = nil,
        category: PresetCategory? = nil, compatibility: [Platform]? = nil, compatibilityNotes: [String: String]? = nil
    ) {
        self.name = name
        self.output = output
        self.slug = slug
        self.description = description
        self.metadata = metadata
        self.category = category
        self.compatibility = compatibility
        self.compatibilityNotes = compatibilityNotes
    }

    enum CodingKeys: String, CodingKey {
        case name, output, slug, description, metadata, category, compatibility
        case compatibilityNotes = "compatibility_notes"
    }
}
