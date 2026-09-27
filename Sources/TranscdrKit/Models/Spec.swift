import Foundation

// MARK: - Output specification

public struct OutputMode: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let single: Self = "single"
    public static let hls: Self = "hls"
    public static let all: [Self] = [.single, .hls]
}

public struct VideoCodec: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let av1: Self = "av1"
    public static let h264: Self = "h264"
    public static let h265: Self = "h265"
    public static let all: [Self] = [.av1, .h264, .h265]
}

public struct AudioMode: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let auto: Self = "auto"
    public static let opus: Self = "opus"
    public static let drop: Self = "drop"
    public static let all: [Self] = [.auto, .opus, .drop]
}

public struct ColorPolicy: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let sdr: Self = "sdr"
    public static let hdr10: Self = "hdr10"
    public static let hlg: Self = "hlg"
    public static let passthrough: Self = "passthrough"
    public static let all: [Self] = [.sdr, .hdr10, .hlg, .passthrough]
}

public struct BitDepth: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let auto: Self = "auto"
    public static let eight: Self = "8bit"
    public static let ten: Self = "10bit"
    public static let all: [Self] = [.auto, .eight, .ten]
}

public struct Rendition: Codable, Hashable, Sendable {
    /// Even, 64–7680.
    public var width: Int
    /// Even, 64–4320.
    public var height: Int
    /// This rendition's constant bitrate under `cbr`, e.g. `"3M"` or `"800k"`;
    /// nil takes `quality.bitrate` or the default for its size.
    public var bitrate: String?
    /// 1–32 of `[A-Za-z0-9_-]`; defaults to `"<short side>p"`.
    public var label: String?

    public init(width: Int, height: Int, bitrate: String? = nil, label: String? = nil) {
        self.width = width
        self.height = height
        self.bitrate = bitrate
        self.label = label
    }

    enum CodingKeys: String, CodingKey { case width, height, bitrate, label }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(width, forKey: .width)
        try c.encode(height, forKey: .height)
        try c.encodeIfPresent(bitrate, forKey: .bitrate)
        try c.encodeIfPresent(label, forKey: .label)
    }
}

public struct Ladder: Codable, Hashable, Sendable {
    /// Cap the tallest rung's short side, e.g. 1080.
    public var maxShortSide: Int?

    public init(maxShortSide: Int? = nil) { self.maxShortSide = maxShortSide }

    enum CodingKeys: String, CodingKey { case maxShortSide = "max_short_side" }
}

public struct Quality: Codable, Hashable, Sendable {
    /// `visually_lossless`, `high`, `standard`, `low`, `vmaf=N` or `cbr`.
    public var target: String?
    /// 0–63; wins over `target`. Not with `cbr`.
    public var crf: Int?
    /// `cbr`: the rate for renditions without their own, e.g. `"5M"`.
    public var bitrate: String?
    /// `cbr`: the rate buffer in milliseconds, 100–10000 (default 1000).
    public var bufferMs: Int?

    public init(target: String? = nil, crf: Int? = nil, bitrate: String? = nil, bufferMs: Int? = nil) {
        self.target = target
        self.crf = crf
        self.bitrate = bitrate
        self.bufferMs = bufferMs
    }

    /// Constant bit rate: every rendition is coded at a fixed rate.
    public static let cbr = "cbr"
    public static let targets = ["visually_lossless", "high", "standard", "low", cbr]

    public var isCbr: Bool { target == Self.cbr }

    enum CodingKeys: String, CodingKey {
        case target, crf, bitrate
        case bufferMs = "buffer_ms"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(target, forKey: .target)
        try c.encodeIfPresent(crf, forKey: .crf)
        try c.encodeIfPresent(bitrate, forKey: .bitrate)
        try c.encodeIfPresent(bufferMs, forKey: .bufferMs)
    }
}

public struct AudioSettings: Codable, Hashable, Sendable {
    public var mode: AudioMode?
    /// Opus bitrate such as `"128k"` (6k–512k).
    public var bitrate: String?

    public init(mode: AudioMode? = nil, bitrate: String? = nil) {
        self.mode = mode
        self.bitrate = bitrate
    }

    enum CodingKeys: String, CodingKey { case mode, bitrate }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(mode, forKey: .mode)
        try c.encodeIfPresent(bitrate, forKey: .bitrate)
    }
}

public struct Trim: Codable, Hashable, Sendable {
    public var start: Double?
    public var end: Double?

    public init(start: Double? = nil, end: Double? = nil) {
        self.start = start
        self.end = end
    }
}

/// An output specification. As returned (a job's or preset's resolved spec)
/// every field is set; as sent (overrides merged over a preset) only the
/// fields that are set go out. `clear` names fields to send as `null`, which
/// clears the preset's value.
public struct OutputSpec: Codable, Hashable, Sendable {
    public var mode: OutputMode?
    public var codec: VideoCodec?
    public var renditions: [Rendition]?
    public var ladder: Ladder?
    public var quality: Quality?
    public var gop: Int?
    public var segmentSeconds: Double?
    public var audio: AudioSettings?
    public var subtitles: String?
    public var color: ColorPolicy?
    public var bitDepth: BitDepth?
    public var maxFps: Double?
    public var filters: String?
    public var trim: Trim?
    /// Fields to send as explicit `null` (overrides only).
    public var clear: Set<Field> = []

    public enum Field: String, CodingKey, Hashable, Sendable, CaseIterable {
        case mode, codec, renditions, ladder, quality, gop
        case segmentSeconds = "segment_seconds"
        case audio, subtitles, color
        case bitDepth = "bit_depth"
        case maxFps = "max_fps"
        case filters, trim
    }

    public init(
        mode: OutputMode? = nil, codec: VideoCodec? = nil, renditions: [Rendition]? = nil, ladder: Ladder? = nil,
        quality: Quality? = nil, gop: Int? = nil, segmentSeconds: Double? = nil, audio: AudioSettings? = nil,
        subtitles: String? = nil, color: ColorPolicy? = nil, bitDepth: BitDepth? = nil, maxFps: Double? = nil,
        filters: String? = nil, trim: Trim? = nil
    ) {
        self.mode = mode
        self.codec = codec
        self.renditions = renditions
        self.ladder = ladder
        self.quality = quality
        self.gop = gop
        self.segmentSeconds = segmentSeconds
        self.audio = audio
        self.subtitles = subtitles
        self.color = color
        self.bitDepth = bitDepth
        self.maxFps = maxFps
        self.filters = filters
        self.trim = trim
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Field.self)
        mode = try c.decodeIfPresent(OutputMode.self, forKey: .mode)
        codec = try c.decodeIfPresent(VideoCodec.self, forKey: .codec)
        renditions = try c.decodeIfPresent([Rendition].self, forKey: .renditions)
        ladder = try c.decodeIfPresent(Ladder.self, forKey: .ladder)
        quality = try c.decodeIfPresent(Quality.self, forKey: .quality)
        gop = try c.decodeIfPresent(Int.self, forKey: .gop)
        segmentSeconds = try c.decodeIfPresent(Double.self, forKey: .segmentSeconds)
        audio = try c.decodeIfPresent(AudioSettings.self, forKey: .audio)
        subtitles = try c.decodeIfPresent(String.self, forKey: .subtitles)
        color = try c.decodeIfPresent(ColorPolicy.self, forKey: .color)
        bitDepth = try c.decodeIfPresent(BitDepth.self, forKey: .bitDepth)
        maxFps = try c.decodeIfPresent(Double.self, forKey: .maxFps)
        filters = try c.decodeIfPresent(String.self, forKey: .filters)
        trim = try c.decodeIfPresent(Trim.self, forKey: .trim)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Field.self)
        func put<V: Encodable>(_ v: V?, _ k: Field) throws {
            if let v { try c.encode(v, forKey: k) } else if clear.contains(k) { try c.encodeNil(forKey: k) }
        }
        try put(mode, .mode)
        try put(codec, .codec)
        try put(renditions, .renditions)
        try put(ladder, .ladder)
        try put(quality, .quality)
        try put(gop, .gop)
        try put(segmentSeconds, .segmentSeconds)
        try put(audio, .audio)
        try put(subtitles, .subtitles)
        try put(color, .color)
        try put(bitDepth, .bitDepth)
        try put(maxFps, .maxFps)
        try put(filters, .filters)
        try put(trim, .trim)
    }

    /// Whether nothing is set (an empty override).
    public var isEmpty: Bool {
        self == OutputSpec() || (clear.isEmpty && mode == nil && codec == nil && renditions == nil && ladder == nil
            && quality == nil && gop == nil && segmentSeconds == nil && audio == nil && subtitles == nil
            && color == nil && bitDepth == nil && maxFps == nil && filters == nil && trim == nil)
    }

    public static func == (a: OutputSpec, b: OutputSpec) -> Bool {
        a.mode == b.mode && a.codec == b.codec && a.renditions == b.renditions && a.ladder == b.ladder
            && a.quality == b.quality && a.gop == b.gop && a.segmentSeconds == b.segmentSeconds && a.audio == b.audio
            && a.subtitles == b.subtitles && a.color == b.color && a.bitDepth == b.bitDepth && a.maxFps == b.maxFps
            && a.filters == b.filters && a.trim == b.trim && a.clear == b.clear
    }

    public func hash(into h: inout Hasher) {
        h.combine(mode); h.combine(codec); h.combine(renditions); h.combine(ladder); h.combine(quality)
        h.combine(gop); h.combine(segmentSeconds); h.combine(audio); h.combine(subtitles); h.combine(color)
        h.combine(bitDepth); h.combine(maxFps); h.combine(filters); h.combine(trim); h.combine(clear)
    }
}

// MARK: - Media

public struct AudioStream: Codable, Hashable, Sendable {
    public var codec: String
    public var channels: Int
    public var sampleRate: Int
    public var language: String?

    enum CodingKeys: String, CodingKey {
        case codec, channels, language
        case sampleRate = "sample_rate"
    }
}

public struct SubtitleStream: Codable, Hashable, Sendable {
    public var format: String
    public var language: String?
}

/// What a probe found in an input.
public struct MediaInfo: Codable, Hashable, Sendable {
    public var container: String
    public var videoCodec: String
    public var width: Int
    public var height: Int
    public var frameRate: Double
    /// Seconds.
    public var duration: Double
    public var pixelFormat: String
    public var bitDepth: Int
    public var hdr: Bool
    public var rotation: Int
    public var audio: [AudioStream]
    public var subtitles: [SubtitleStream]
    public var sizeBytes: Int64

    enum CodingKeys: String, CodingKey {
        case container, width, height, duration, hdr, rotation, audio, subtitles
        case videoCodec = "video_codec"
        case frameRate = "frame_rate"
        case pixelFormat = "pixel_format"
        case bitDepth = "bit_depth"
        case sizeBytes = "size_bytes"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        container = try c.decodeIfPresent(String.self, forKey: .container) ?? ""
        videoCodec = try c.decodeIfPresent(String.self, forKey: .videoCodec) ?? ""
        width = try c.decodeIfPresent(Int.self, forKey: .width) ?? 0
        height = try c.decodeIfPresent(Int.self, forKey: .height) ?? 0
        frameRate = try c.decodeIfPresent(Double.self, forKey: .frameRate) ?? 0
        duration = try c.decodeIfPresent(Double.self, forKey: .duration) ?? 0
        pixelFormat = try c.decodeIfPresent(String.self, forKey: .pixelFormat) ?? ""
        bitDepth = try c.decodeIfPresent(Int.self, forKey: .bitDepth) ?? 8
        hdr = try c.decodeIfPresent(Bool.self, forKey: .hdr) ?? false
        rotation = try c.decodeIfPresent(Int.self, forKey: .rotation) ?? 0
        audio = try c.decodeList([AudioStream].self, forKey: .audio)
        subtitles = try c.decodeList([SubtitleStream].self, forKey: .subtitles)
        sizeBytes = try c.decodeIfPresent(Int64.self, forKey: .sizeBytes) ?? 0
    }
}

/// String-to-string metadata: up to 20 keys (≤ 40 chars), values ≤ 500 chars.
public typealias Metadata = [String: String]
