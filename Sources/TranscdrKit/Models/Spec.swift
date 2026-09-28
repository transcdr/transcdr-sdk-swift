import Foundation

// MARK: - Output specification

public struct OutputMode: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let single: Self = "single"
    public static let hls: Self = "hls"
    /// The audio alone, as one file (label `audio`, width and height 0): an `.mp3`, `.flac`
    /// or `.m4a`, as `AudioSettings.container` picks.
    public static let audio: Self = "audio"
    public static let all: [Self] = [.single, .hls, .audio]
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
    /// Pass compatible audio through and transcode the rest: to Opus, or to MP3 in an
    /// audio-only `.mp3`.
    public static let auto: Self = "auto"
    public static let opus: Self = "opus"
    /// Constant bit rate MP3, stereo at most, in a single MP4 or audio-only output (not HLS).
    public static let mp3: Self = "mp3"
    /// AAC-LC, the audio that plays on the most devices (an AAC source passes through).
    public static let aac: Self = "aac"
    /// Lossless FLAC (a FLAC source is copied). No bitrate.
    public static let flac: Self = "flac"
    /// Lossless ALAC, Apple Lossless (an ALAC source is copied). No bitrate.
    public static let alac: Self = "alac"
    public static let drop: Self = "drop"
    public static let all: [Self] = [.auto, .opus, .mp3, .aac, .flac, .alac, .drop]

    /// FLAC or ALAC.
    public var isLossless: Bool { self == .flac || self == .alac }
}

/// The sample depth of FLAC and ALAC output.
public struct AudioBitDepth: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    /// 16-bit for a 16-bit or lossy source, 24-bit for a deeper one (the default).
    public static let source: Self = "source"
    public static let sixteen: Self = "16"
    public static let twentyFour: Self = "24"
    public static let all: [Self] = [.source, .sixteen, .twentyFour]
}

/// FLAC's compression effort: the same audio either way, a smaller file for more work.
public struct FlacCompression: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let fast: Self = "fast"
    /// The default.
    public static let `default`: Self = "default"
    public static let best: Self = "best"
    public static let all: [Self] = [.fast, .default, .best]
}

/// What an HE-AAC (or HE-AAC v2) source becomes. HE-AAC is decoded only as its AAC-LC core:
/// spectral band replication and parametric stereo are not decoded, so the core has half the
/// stream's rate, less bandwidth and, for v2, one channel. AAC-LC sources are decoded in full
/// whatever it says.
public struct HeAac: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    /// The default: passed through when only a codec change is asked; its core decoded when
    /// the job needs PCM (a downmix, an `.mp3` or `.flac` file).
    public static let auto: Self = "auto"
    /// Never decoded: a job that would need it decoded fails.
    public static let passthrough: Self = "passthrough"
    /// Its core decoded whenever another codec is asked.
    public static let core: Self = "core"
    public static let all: [Self] = [.auto, .passthrough, .core]
}

/// The file audio-only output is.
public struct AudioContainer: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    /// Follow the codec: a `.flac` for FLAC, an `.m4a` for ALAC, an `.mp3` otherwise
    /// (`auto` audio is then MP3). The default.
    public static let auto: Self = "auto"
    /// `audio.mp3` (`audio/mpeg`): MP3 only.
    public static let mp3: Self = "mp3"
    /// `audio.flac` (`audio/flac`): FLAC only.
    public static let flac: Self = "flac"
    /// `audio.m4a` (`audio/mp4`): any codec (`auto` audio in an `.m4a` is Opus).
    public static let m4a: Self = "m4a"
    public static let all: [Self] = [.auto, .mp3, .flac, .m4a]
}

/// An audio channel layout. Every layout but `source` downmixes; none upmixes.
public struct AudioChannels: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    /// The source's layout (the default).
    public static let source: Self = "source"
    public static let mono: Self = "mono"
    public static let stereo: Self = "stereo"
    /// 5.1 surround; not with MP3.
    public static let surround51: Self = "5.1"
    /// 7.1 surround; not with MP3.
    public static let surround71: Self = "7.1"
    public static let all: [Self] = [.source, .mono, .stereo, .surround51, .surround71]

    /// 5.1 or 7.1.
    public var isSurround: Bool { self == .surround51 || self == .surround71 }
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

/// How the video meets a rendition's box.
public struct Fit: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    /// Inside the box, keeping the video's shape. The default.
    public static let contain: Self = "contain"
    /// Fill the box, keeping the shape, and centre-crop the rest.
    public static let cover: Self = "cover"
    /// Keep the shape and add black bars to exactly the box.
    public static let pad: Self = "pad"
    /// Distort the picture to exactly the box.
    public static let stretch: Self = "stretch"
    public static let all: [Self] = [.contain, .cover, .pad, .stretch]
}

/// Whether a rendition's box turns to the video's orientation.
public struct Orientation: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    /// 1920×1080 on a portrait video is used as 1080×1920. The default.
    public static let auto: Self = "auto"
    /// The box is used as written.
    public static let fixed: Self = "fixed"
    public static let all: [Self] = [.auto, .fixed]
}

/// One output. `width` × `height` is the largest it may be: the video keeps its
/// shape inside that box (see `OutputSpec.fit`) and is not enlarged past its own
/// size unless `upscale` is on. Each output reports the size it came out at.
public struct Rendition: Codable, Hashable, Sendable {
    /// The maximum width; even, 64–7680.
    public var width: Int
    /// The maximum height; even, 64–4320.
    public var height: Int
    /// This rendition's constant bitrate under `cbr`, e.g. `"3M"` or `"800k"`;
    /// nil takes `quality.bitrate` or the default for its size.
    public var bitrate: String?
    /// 1–32 of `[A-Za-z0-9_-]`; defaults to `"<short side>p"` of the size it comes out at.
    public var label: String?
    /// This rendition's own fit, over `OutputSpec.fit`.
    public var fit: Fit?
    /// `.fixed` keeps this rendition's box as written, e.g. a 9:16 `.cover`
    /// rendition that crops a landscape video.
    public var orientation: Orientation?
    /// This rendition's own upscale, over `OutputSpec.upscale`.
    public var upscale: Bool?

    public init(
        width: Int, height: Int, bitrate: String? = nil, label: String? = nil, fit: Fit? = nil,
        orientation: Orientation? = nil, upscale: Bool? = nil
    ) {
        self.width = width
        self.height = height
        self.bitrate = bitrate
        self.label = label
        self.fit = fit
        self.orientation = orientation
        self.upscale = upscale
    }

    enum CodingKeys: String, CodingKey { case width, height, bitrate, label, fit, orientation, upscale }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(width, forKey: .width)
        try c.encode(height, forKey: .height)
        try c.encodeIfPresent(bitrate, forKey: .bitrate)
        try c.encodeIfPresent(label, forKey: .label)
        try c.encodeIfPresent(fit, forKey: .fit)
        try c.encodeIfPresent(orientation, forKey: .orientation)
        try c.encodeIfPresent(upscale, forKey: .upscale)
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
    /// Bitrate such as `"128k"` (6k–512k). MP3 takes one of `SpecTools.mp3Bitrates`
    /// (default 128k stereo, 64k mono). AAC takes 8k to 288k per main channel (the LFE does
    /// not count; default 64k mono, 128k stereo, 384k 5.1, 512k 7.1). Not with FLAC or ALAC.
    public var bitrate: String?
    /// The channel layout; nil is the source's.
    public var channels: AudioChannels?
    /// HLS with surround audio: also add a stereo rendition to the same audio group.
    public var stereoFallback: Bool?
    /// FLAC and ALAC: the output's sample depth; nil is `source`.
    public var bitDepth: AudioBitDepth?
    /// FLAC: the compression effort; nil is `default`.
    public var flacCompression: FlacCompression?
    /// Audio-only output: the file it is; nil is `auto`.
    public var container: AudioContainer?
    /// What an HE-AAC source becomes; nil is `auto`. Not with `drop`.
    public var heAac: HeAac?

    public init(
        mode: AudioMode? = nil, bitrate: String? = nil, channels: AudioChannels? = nil, stereoFallback: Bool? = nil,
        bitDepth: AudioBitDepth? = nil, flacCompression: FlacCompression? = nil, container: AudioContainer? = nil,
        heAac: HeAac? = nil
    ) {
        self.mode = mode
        self.bitrate = bitrate
        self.channels = channels
        self.stereoFallback = stereoFallback
        self.bitDepth = bitDepth
        self.flacCompression = flacCompression
        self.container = container
        self.heAac = heAac
    }

    enum CodingKeys: String, CodingKey {
        case mode, bitrate, channels, container
        case stereoFallback = "stereo_fallback"
        case bitDepth = "bit_depth"
        case flacCompression = "flac_compression"
        case heAac = "he_aac"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(mode, forKey: .mode)
        try c.encodeIfPresent(bitrate, forKey: .bitrate)
        try c.encodeIfPresent(channels, forKey: .channels)
        try c.encodeIfPresent(stereoFallback, forKey: .stereoFallback)
        try c.encodeIfPresent(bitDepth, forKey: .bitDepth)
        try c.encodeIfPresent(flacCompression, forKey: .flacCompression)
        try c.encodeIfPresent(container, forKey: .container)
        try c.encodeIfPresent(heAac, forKey: .heAac)
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
    /// How the video meets each rendition's box; `.contain` unless set.
    public var fit: Fit?
    /// Let a rendition be larger than the source; false unless set.
    public var upscale: Bool?
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
        case mode, codec, renditions, fit, upscale, ladder, quality, gop
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
        filters: String? = nil, trim: Trim? = nil, fit: Fit? = nil, upscale: Bool? = nil
    ) {
        self.mode = mode
        self.codec = codec
        self.renditions = renditions
        self.fit = fit
        self.upscale = upscale
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
        fit = try c.decodeIfPresent(Fit.self, forKey: .fit)
        upscale = try c.decodeIfPresent(Bool.self, forKey: .upscale)
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
        try put(fit, .fit)
        try put(upscale, .upscale)
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
        self == OutputSpec() || (clear.isEmpty && mode == nil && codec == nil && renditions == nil && fit == nil
            && upscale == nil && ladder == nil
            && quality == nil && gop == nil && segmentSeconds == nil && audio == nil && subtitles == nil
            && color == nil && bitDepth == nil && maxFps == nil && filters == nil && trim == nil)
    }

    public static func == (a: OutputSpec, b: OutputSpec) -> Bool {
        a.mode == b.mode && a.codec == b.codec && a.renditions == b.renditions && a.fit == b.fit
            && a.upscale == b.upscale && a.ladder == b.ladder
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
    /// Non-square pixels only: the size the picture is shown at (720×576 at
    /// 64:45 is shown 1024×576).
    public var displayWidth: Int?
    public var displayHeight: Int?

    enum CodingKeys: String, CodingKey {
        case container, width, height, duration, hdr, rotation, audio, subtitles
        case displayWidth = "display_width"
        case displayHeight = "display_height"
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
        displayWidth = try c.decodeIfPresent(Int.self, forKey: .displayWidth)
        displayHeight = try c.decodeIfPresent(Int.self, forKey: .displayHeight)
    }
}

/// String-to-string metadata: up to 20 keys (≤ 40 chars), values ≤ 500 chars.
public typealias Metadata = [String: String]
