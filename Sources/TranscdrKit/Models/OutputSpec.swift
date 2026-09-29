import Foundation

// MARK: - Output specification (v2)
//
// What a job produces, declared in sections. Nothing has a default: a spec states every field
// its kind, container, codec and handling need, and a value that follows the source is written
// out (`.source`, `"standard"`, `.fromColor`, `.bySize`, `.poster`, `.segment`, `.all`).
// Mutually exclusive choices are enums, so a spec cannot hold two of them. Fields that apply
// only under a condition (an HLS segment length, an AAC bitrate) are optional here and checked
// by `OutputSpec.validate`, which mirrors the API's required-field table.

/// What a job produces.
public enum OutputSpec: Codable, Hashable, Sendable {
    /// A video: one MP4 per size, or an HLS package.
    case video(VideoOutput)
    /// The audio alone, as one file.
    case audio(AudioOutput)
    /// Still images of an image input, or stills taken from a video.
    case image(ImageOutput)

    public var kind: OutputKind {
        switch self {
        case .video: return .video
        case .audio: return .audio
        case .image: return .image
        }
    }

    /// Which identifying metadata survives.
    public var privacy: Privacy {
        switch self {
        case .video(let v): return v.privacy
        case .audio(let a): return a.privacy
        case .image(let i): return i.privacy
        }
    }

    /// The container, for video and audio.
    public var container: Container? {
        switch self {
        case .video(let v): return v.container
        case .audio(let a): return a.container
        case .image: return nil
        }
    }

    /// The audio section, for video and audio.
    public var audioTrack: AudioTrack? {
        switch self {
        case .video(let v): return v.audio
        case .audio(let a): return a.audio
        case .image: return nil
        }
    }

    /// The sizes, for video and images.
    public var renditions: Renditions? {
        switch self {
        case .video(let v): return v.renditions
        case .image(let i): return i.renditions
        case .audio: return nil
        }
    }

    enum Key: String, CodingKey { case kind }

    public init(from decoder: Decoder) throws {
        let kind = try decoder.container(keyedBy: Key.self).decode(OutputKind.self, forKey: .kind)
        switch kind {
        case .video: self = .video(try VideoOutput(from: decoder))
        case .audio: self = .audio(try AudioOutput(from: decoder))
        case .image: self = .image(try ImageOutput(from: decoder))
        default:
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath + [Key.kind], debugDescription: "Unknown output kind \(kind.rawValue)"
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(kind, forKey: .kind)
        switch self {
        case .video(let v): try v.encode(to: encoder)
        case .audio(let a): try a.encode(to: encoder)
        case .image(let i): try i.encode(to: encoder)
        }
    }
}

public struct OutputKind: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let video: Self = "video"
    public static let audio: Self = "audio"
    public static let image: Self = "image"
    public static let all: [Self] = [.video, .audio, .image]
}

/// `kind: "video"`.
public struct VideoOutput: Codable, Hashable, Sendable {
    /// `.mp4` or `.hls` (with `segmentSeconds`).
    public var container: Container
    public var video: VideoSettings
    public var audio: AudioTrack
    public var renditions: Renditions
    public var subtitles: Subtitles
    public var trim: Trim
    public var privacy: Privacy

    public init(
        container: Container, video: VideoSettings, audio: AudioTrack, renditions: Renditions,
        subtitles: Subtitles, trim: Trim, privacy: Privacy
    ) {
        self.container = container
        self.video = video
        self.audio = audio
        self.renditions = renditions
        self.subtitles = subtitles
        self.trim = trim
        self.privacy = privacy
    }
}

/// `kind: "audio"`: the audio alone, one file labelled `audio`.
public struct AudioOutput: Codable, Hashable, Sendable {
    /// `.mp3` (MP3 only), `.flac` (FLAC only) or `.m4a` (any codec).
    public var container: Container
    /// `.auto` or `.encode`: audio output needs a track.
    public var audio: AudioTrack
    public var privacy: Privacy

    public init(container: Container, audio: AudioTrack, privacy: Privacy) {
        self.container = container
        self.audio = audio
        self.privacy = privacy
    }
}

/// `kind: "image"`: every size is made in every format.
public struct ImageOutput: Codable, Hashable, Sendable {
    public var image: ImageSettings
    /// `.sizes` or `.sourceSize` (no ladder for images).
    public var renditions: Renditions
    public var privacy: Privacy

    public init(image: ImageSettings, renditions: Renditions, privacy: Privacy) {
        self.image = image
        self.renditions = renditions
        self.privacy = privacy
    }
}

// MARK: Container

public struct ContainerFormat: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    /// Video: one faststart MP4 per size.
    public static let mp4: Self = "mp4"
    /// Video: a CMAF/HLS package; needs `segmentSeconds`.
    public static let hls: Self = "hls"
    /// Audio: `audio.mp3`, MP3 only.
    public static let mp3: Self = "mp3"
    /// Audio: `audio.flac`, FLAC only.
    public static let flac: Self = "flac"
    /// Audio: `audio.m4a`, any codec.
    public static let m4a: Self = "m4a"
    public static let video: [Self] = [.mp4, .hls]
    public static let audio: [Self] = [.mp3, .flac, .m4a]
    public static let all: [Self] = video + audio
}

/// The file or package.
public struct Container: Codable, Hashable, Sendable {
    public var format: ContainerFormat
    /// Required for `hls` (1–20), refused otherwise.
    public var segmentSeconds: Double?

    public init(format: ContainerFormat, segmentSeconds: Double?) {
        self.format = format
        self.segmentSeconds = segmentSeconds
    }

    /// An MP4 per size.
    public static let mp4 = Container(format: .mp4, segmentSeconds: nil)
    /// An HLS package cut into segments of this many seconds.
    public static func hls(segmentSeconds: Double) -> Container { Container(format: .hls, segmentSeconds: segmentSeconds) }
    public static let mp3 = Container(format: .mp3, segmentSeconds: nil)
    public static let flac = Container(format: .flac, segmentSeconds: nil)
    public static let m4a = Container(format: .m4a, segmentSeconds: nil)

    enum CodingKeys: String, CodingKey {
        case format
        case segmentSeconds = "segment_seconds"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(format, forKey: .format)
        try c.encodeIfPresent(segmentSeconds, forKey: .segmentSeconds)
    }
}

// MARK: Video

public struct VideoCodec: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let av1: Self = "av1"
    public static let h264: Self = "h264"
    /// Paid plans.
    public static let h265: Self = "h265"
    public static let all: [Self] = [.av1, .h264, .h265]
}

public struct ColorPolicy: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    /// Tonemaps an HDR source.
    public static let sdr: Self = "sdr"
    /// Paid plans.
    public static let hdr10: Self = "hdr10"
    /// Paid plans.
    public static let hlg: Self = "hlg"
    public static let passthrough: Self = "passthrough"
    public static let all: [Self] = [.sdr, .hdr10, .hlg, .passthrough]
}

public struct VideoBitDepth: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    /// 8-bit for `sdr`, 10-bit for `hdr10` and `hlg`, the source's for `passthrough`.
    public static let fromColor: Self = "from_color"
    public static let eight: Self = "8bit"
    /// Not with H.264.
    public static let ten: Self = "10bit"
    public static let all: [Self] = [.fromColor, .eight, .ten]
}

/// How the video is rated: exactly one of a quality level, a CRF, or a constant bit rate.
public enum VideoRate: Hashable, Sendable {
    /// `visually_lossless`, `high`, `standard`, `low` or `vmaf=N`.
    case quality(String)
    /// 0–63.
    case crf(Int)
    case cbr(ConstantBitRate)

    public static let qualityLevels = ["visually_lossless", "high", "standard", "low"]
}

/// `video.cbr`: every size at a constant bit rate.
public struct ConstantBitRate: Codable, Hashable, Sendable {
    /// 100k to 200M, or `"standard"`: a rate for each size by codec, short side and frame rate.
    public var bitrate: String
    /// The rate buffer, 100–10000 ms.
    public var bufferMs: Int

    public init(bitrate: String, bufferMs: Int) {
        self.bitrate = bitrate
        self.bufferMs = bufferMs
    }

    public static let standard = "standard"

    enum CodingKeys: String, CodingKey {
        case bitrate
        case bufferMs = "buffer_ms"
    }
}

/// `video.frame_rate`.
public struct FrameRate: Codable, Hashable, Sendable {
    public var max: FrameRateMax

    public init(max: FrameRateMax) { self.max = max }

    public static let source = FrameRate(max: .source)
    public static func max(_ fps: Double) -> FrameRate { FrameRate(max: .fps(fps)) }
}

/// A frame-rate cap, or the source's rate uncapped.
public enum FrameRateMax: Codable, Hashable, Sendable {
    /// 1–240.
    case fps(Double)
    case source

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let n = try? c.decode(Double.self) { self = .fps(n); return }
        let s = try c.decode(String.self)
        guard s == "source" else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "frame_rate.max: \(s)") }
        self = .source
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .fps(let n): try c.encode(n)
        case .source: try c.encode("source")
        }
    }
}

/// The keyframe interval.
public enum Gop: Codable, Hashable, Sendable {
    /// 1–1200 frames.
    case frames(Int)
    /// 0.1–60 seconds.
    case seconds(Double)
    /// HLS only: one keyframe at the start of each segment.
    case segment

    enum Key: String, CodingKey { case frames, seconds }

    public init(from decoder: Decoder) throws {
        if let s = try? decoder.singleValueContainer().decode(String.self) {
            guard s == "segment" else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "gop: \(s)"))
            }
            self = .segment
            return
        }
        let c = try decoder.container(keyedBy: Key.self)
        if let n = try c.decodeIfPresent(Int.self, forKey: .frames) {
            self = .frames(n)
        } else {
            self = .seconds(try c.decode(Double.self, forKey: .seconds))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .segment:
            var c = encoder.singleValueContainer()
            try c.encode("segment")
        case .frames(let n):
            var c = encoder.container(keyedBy: Key.self)
            try c.encode(n, forKey: .frames)
        case .seconds(let n):
            var c = encoder.container(keyedBy: Key.self)
            try c.encode(n, forKey: .seconds)
        }
    }
}

/// The video track.
public struct VideoSettings: Codable, Hashable, Sendable {
    public var codec: VideoCodec
    /// Sent as `quality`, `crf` or `cbr`.
    public var rate: VideoRate
    public var bitDepth: VideoBitDepth
    public var color: ColorPolicy
    public var frameRate: FrameRate
    public var gop: Gop
    /// One filter per entry, such as `crop=1280:720`; `[]` for none.
    public var filters: [String]

    public init(
        codec: VideoCodec, rate: VideoRate, bitDepth: VideoBitDepth, color: ColorPolicy, frameRate: FrameRate, gop: Gop,
        filters: [String]
    ) {
        self.codec = codec
        self.rate = rate
        self.bitDepth = bitDepth
        self.color = color
        self.frameRate = frameRate
        self.gop = gop
        self.filters = filters
    }

    enum CodingKeys: String, CodingKey {
        case codec, quality, crf, cbr, color, gop, filters
        case bitDepth = "bit_depth"
        case frameRate = "frame_rate"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        codec = try c.decode(VideoCodec.self, forKey: .codec)
        if let q = try c.decodeIfPresent(String.self, forKey: .quality) {
            rate = .quality(q)
        } else if let crf = try c.decodeIfPresent(Int.self, forKey: .crf) {
            rate = .crf(crf)
        } else {
            rate = .cbr(try c.decode(ConstantBitRate.self, forKey: .cbr))
        }
        bitDepth = try c.decode(VideoBitDepth.self, forKey: .bitDepth)
        color = try c.decode(ColorPolicy.self, forKey: .color)
        frameRate = try c.decode(FrameRate.self, forKey: .frameRate)
        gop = try c.decode(Gop.self, forKey: .gop)
        filters = try c.decode([String].self, forKey: .filters)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(codec, forKey: .codec)
        switch rate {
        case .quality(let q): try c.encode(q, forKey: .quality)
        case .crf(let n): try c.encode(n, forKey: .crf)
        case .cbr(let cbr): try c.encode(cbr, forKey: .cbr)
        }
        try c.encode(bitDepth, forKey: .bitDepth)
        try c.encode(color, forKey: .color)
        try c.encode(frameRate, forKey: .frameRate)
        try c.encode(gop, forKey: .gop)
        try c.encode(filters, forKey: .filters)
    }
}

// MARK: Audio

public struct AudioHandling: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    /// Keep the source's audio where the container carries it unchanged, else make it `codec`.
    public static let auto: Self = "auto"
    /// Make it `codec` (a source already in it, with nothing else changed, is copied).
    public static let encode: Self = "encode"
    /// No audio track (video only).
    public static let drop: Self = "drop"
    public static let all: [Self] = [.auto, .encode, .drop]
}

public struct AudioCodec: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let opus: Self = "opus"
    /// Constant bit rate, stereo at most; not in HLS.
    public static let mp3: Self = "mp3"
    /// AAC-LC: the widest device reach.
    public static let aac: Self = "aac"
    /// Lossless; no bitrate.
    public static let flac: Self = "flac"
    /// Lossless Apple Lossless; no bitrate.
    public static let alac: Self = "alac"
    public static let all: [Self] = [.opus, .mp3, .aac, .flac, .alac]

    /// FLAC or ALAC.
    public var isLossless: Bool { self == .flac || self == .alac }
    /// A codec's name in messages: `AAC`, `Opus`, `MP3`, `FLAC`, `ALAC`.
    public var displayName: String { self == .opus ? "Opus" : rawValue.uppercased() }
}

/// An audio channel layout. Every layout but `source` downmixes; none upmixes.
public struct AudioChannels: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    /// The source's layout (MP3 folds a wider one to stereo).
    public static let source: Self = "source"
    public static let mono: Self = "mono"
    public static let stereo: Self = "stereo"
    /// Not with MP3.
    public static let surround51: Self = "5.1"
    /// Not with MP3.
    public static let surround71: Self = "7.1"
    public static let all: [Self] = [.source, .mono, .stereo, .surround51, .surround71]

    /// 5.1 or 7.1.
    public var isSurround: Bool { self == .surround51 || self == .surround71 }
}

/// What an HE-AAC (or HE-AAC v2) source becomes. HE-AAC is decoded only as its AAC-LC core, so
/// the core has half the stream's rate, less bandwidth and, for v2, one channel.
public struct HeAac: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    /// Passed through when only a codec change is asked; its core decoded when the job needs PCM.
    public static let auto: Self = "auto"
    /// Never decoded: a job that would need it decoded fails.
    public static let passthrough: Self = "passthrough"
    /// Its core decoded whenever another codec is asked.
    public static let core: Self = "core"
    public static let all: [Self] = [.auto, .passthrough, .core]
}

/// The sample depth of FLAC and ALAC output.
public struct AudioBitDepth: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    /// 16-bit for a 16-bit or lossy source, 24-bit for a deeper one.
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
    public static let balanced: Self = "balanced"
    public static let best: Self = "best"
    public static let all: [Self] = [.fast, .balanced, .best]
}

/// The audio section: kept or made (`auto`, `encode`), or dropped.
public enum AudioTrack: Codable, Hashable, Sendable {
    /// Keep the source's audio where the container carries it; make the rest `codec` (Opus, or
    /// MP3 in an `.mp3` file).
    case auto(AudioEncoding)
    /// Make the audio `codec`.
    case encode(AudioEncoding)
    /// No audio track. Video only.
    case drop

    public var handling: AudioHandling {
        switch self {
        case .auto: return .auto
        case .encode: return .encode
        case .drop: return .drop
        }
    }

    /// The codec settings; nil for `drop`.
    public var encoding: AudioEncoding? {
        switch self {
        case .auto(let e), .encode(let e): return e
        case .drop: return nil
        }
    }

    enum Key: String, CodingKey { case handling }

    public init(from decoder: Decoder) throws {
        let handling = try decoder.container(keyedBy: Key.self).decode(AudioHandling.self, forKey: .handling)
        switch handling {
        case .drop: self = .drop
        case .auto: self = .auto(try AudioEncoding(from: decoder))
        case .encode: self = .encode(try AudioEncoding(from: decoder))
        default:
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath + [Key.handling], debugDescription: "Unknown audio handling \(handling.rawValue)"
            ))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        try c.encode(handling, forKey: .handling)
        try encoding?.encode(to: encoder)
    }
}

/// How a kept or made track is coded.
public struct AudioEncoding: Codable, Hashable, Sendable {
    public var codec: AudioCodec
    /// Opus, MP3 and AAC: a rate such as `"128k"` (MP3 at its fixed rates; AAC 8k–288k per
    /// main channel), or `"standard"`. Refused for FLAC and ALAC.
    public var bitrate: String?
    public var channels: AudioChannels
    public var heAac: HeAac
    /// HLS only, where it is required: a stereo rendition beside surround audio.
    public var stereoFallback: Bool?
    /// FLAC and ALAC only, where it is required.
    public var bitDepth: AudioBitDepth?
    /// FLAC only, where it is required.
    public var flacCompression: FlacCompression?

    public init(
        codec: AudioCodec, bitrate: String?, channels: AudioChannels, heAac: HeAac, stereoFallback: Bool?,
        bitDepth: AudioBitDepth?, flacCompression: FlacCompression?
    ) {
        self.codec = codec
        self.bitrate = bitrate
        self.channels = channels
        self.heAac = heAac
        self.stereoFallback = stereoFallback
        self.bitDepth = bitDepth
        self.flacCompression = flacCompression
    }

    public static let standard = "standard"

    enum CodingKeys: String, CodingKey {
        case codec, bitrate, channels
        case heAac = "he_aac"
        case stereoFallback = "stereo_fallback"
        case bitDepth = "bit_depth"
        case flacCompression = "flac_compression"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(codec, forKey: .codec)
        try c.encodeIfPresent(bitrate, forKey: .bitrate)
        try c.encode(channels, forKey: .channels)
        try c.encode(heAac, forKey: .heAac)
        try c.encodeIfPresent(stereoFallback, forKey: .stereoFallback)
        try c.encodeIfPresent(bitDepth, forKey: .bitDepth)
        try c.encodeIfPresent(flacCompression, forKey: .flacCompression)
    }
}

// MARK: Image

/// An image output format.
public struct ImageFormat: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let avif: Self = "avif"
    public static let webp: Self = "webp"
    public static let jpeg: Self = "jpeg"
    /// Always lossless.
    public static let png: Self = "png"
    public static let all: [Self] = [.avif, .webp, .jpeg, .png]

    /// Can be lossy: AVIF, WebP and JPEG.
    public var isLossy: Bool { self == .avif || self == .webp || self == .jpeg }
}

public struct ColorProfile: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    /// Convert the pixels to sRGB.
    public static let srgb: Self = "srgb"
    /// Keep the source's profile (PNG, JPEG, WebP).
    public static let keep: Self = "keep"
    public static let all: [Self] = [.srgb, .keep]
}

/// Which frames become stills.
public enum ImageFrames: Codable, Hashable, Sendable {
    /// An image input as it is; a video's frame 10% of the way in.
    case poster
    /// Video input only: 1–100 stills, evenly spaced.
    case count(Int)
    /// Video input only: 1–100 times, seconds from the start.
    case atSeconds([Double])

    enum Key: String, CodingKey {
        case count
        case atSeconds = "at_seconds"
    }

    public init(from decoder: Decoder) throws {
        if let s = try? decoder.singleValueContainer().decode(String.self) {
            guard s == "poster" else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "frames: \(s)"))
            }
            self = .poster
            return
        }
        let c = try decoder.container(keyedBy: Key.self)
        if let n = try c.decodeIfPresent(Int.self, forKey: .count) {
            self = .count(n)
        } else {
            self = .atSeconds(try c.decode([Double].self, forKey: .atSeconds))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .poster:
            var c = encoder.singleValueContainer()
            try c.encode("poster")
        case .count(let n):
            var c = encoder.container(keyedBy: Key.self)
            try c.encode(n, forKey: .count)
        case .atSeconds(let times):
            var c = encoder.container(keyedBy: Key.self)
            try c.encode(times, forKey: .atSeconds)
        }
    }

    /// How many stills: 1 for the poster.
    public var stillCount: Int {
        switch self {
        case .poster: return 1
        case .count(let n): return n
        case .atSeconds(let times): return times.count
        }
    }
}

/// Still images.
public struct ImageSettings: Codable, Hashable, Sendable {
    /// 1–4 distinct formats.
    public var formats: [ImageFormat]
    /// Required when `webp` is made: lossless WebP.
    public var lossless: Bool?
    /// One entry, 1–100, for each format made lossy (AVIF, JPEG, WebP unless lossless) and no
    /// others; nil when none is.
    public var quality: [ImageFormat: Int]?
    public var colorProfile: ColorProfile
    public var frames: ImageFrames

    public init(
        formats: [ImageFormat], lossless: Bool?, quality: [ImageFormat: Int]?, colorProfile: ColorProfile,
        frames: ImageFrames
    ) {
        self.formats = formats
        self.lossless = lossless
        self.quality = quality
        self.colorProfile = colorProfile
        self.frames = frames
    }

    /// The formats made lossy.
    public var lossyFormats: [ImageFormat] {
        formats.filter { $0 == .avif || $0 == .jpeg || ($0 == .webp && lossless != true) }
    }

    enum CodingKeys: String, CodingKey {
        case formats, lossless, quality, frames
        case colorProfile = "color_profile"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formats = try c.decode([ImageFormat].self, forKey: .formats)
        lossless = try c.decodeIfPresent(Bool.self, forKey: .lossless)
        quality = try c.decodeIfPresent([String: Int].self, forKey: .quality)
            .map { Dictionary(uniqueKeysWithValues: $0.map { (ImageFormat(rawValue: $0.key), $0.value) }) }
        colorProfile = try c.decode(ColorProfile.self, forKey: .colorProfile)
        frames = try c.decode(ImageFrames.self, forKey: .frames)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(formats, forKey: .formats)
        try c.encodeIfPresent(lossless, forKey: .lossless)
        if let quality {
            try c.encode(Dictionary(uniqueKeysWithValues: quality.map { ($0.key.rawValue, $0.value) }), forKey: .quality)
        }
        try c.encode(colorProfile, forKey: .colorProfile)
        try c.encode(frames, forKey: .frames)
    }
}

// MARK: Renditions

/// How the picture meets a size's box.
public struct Fit: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    /// Inside the box, keeping the shape.
    public static let contain: Self = "contain"
    /// Fill the box, keeping the shape, and centre-crop the rest.
    public static let cover: Self = "cover"
    /// Keep the shape and add black bars to exactly the box.
    public static let pad: Self = "pad"
    /// Distort the picture to exactly the box.
    public static let stretch: Self = "stretch"
    public static let all: [Self] = [.contain, .cover, .pad, .stretch]
}

/// Whether a size's box turns to the picture's orientation.
public struct Orientation: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    /// 1920×1080 on a portrait video is used as 1080×1920.
    public static let auto: Self = "auto"
    /// The box is used as written.
    public static let fixed: Self = "fixed"
    public static let all: [Self] = [.auto, .fixed]
}

/// A size's label: 1–32 of `A–Z a–z 0–9 - _`, or `.bySize`.
public struct RenditionLabel: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    /// Named by the size it comes out at: `<short side>p` for video, `<width>x<height>` for images.
    public static let bySize: Self = "by_size"
}

/// The sizes produced: exactly one of explicit sizes, an automatic ladder, or the source's size.
public enum Renditions: Codable, Hashable, Sendable {
    /// 1–8 boxes.
    case sizes([RenditionSize])
    /// Video only: the standard short sides up to a cap.
    case ladder(Ladder)
    /// One output at the source's size.
    case sourceSize(SourceSize)

    enum Key: String, CodingKey {
        case sizes, ladder
        case sourceSize = "source_size"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        if let sizes = try c.decodeIfPresent([RenditionSize].self, forKey: .sizes) {
            self = .sizes(sizes)
        } else if let ladder = try c.decodeIfPresent(Ladder.self, forKey: .ladder) {
            self = .ladder(ladder)
        } else {
            self = .sourceSize(try c.decode(SourceSize.self, forKey: .sourceSize))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case .sizes(let s): try c.encode(s, forKey: .sizes)
        case .ladder(let l): try c.encode(l, forKey: .ladder)
        case .sourceSize(let s): try c.encode(s, forKey: .sourceSize)
        }
    }
}

/// One box. `width` × `height` is the largest the output may be; each output reports the size
/// it came out at.
public struct RenditionSize: Codable, Hashable, Sendable {
    public var label: RenditionLabel
    /// Video: even, 64–7680. Images: 16–8192.
    public var width: Int
    /// Video: even, 64–4320. Images: 16–8192.
    public var height: Int
    public var fit: Fit
    public var orientation: Orientation
    public var upscale: Bool
    /// With `video.cbr` only, and optional: this size's own constant rate (sent as
    /// `video.cbr.bitrate`). Without it, the size takes `video.cbr.bitrate`.
    public var cbrBitrate: String?

    public init(
        label: RenditionLabel, width: Int, height: Int, fit: Fit, orientation: Orientation, upscale: Bool,
        cbrBitrate: String?
    ) {
        self.label = label
        self.width = width
        self.height = height
        self.fit = fit
        self.orientation = orientation
        self.upscale = upscale
        self.cbrBitrate = cbrBitrate
    }

    public var shortSide: Int { min(width, height) }

    enum CodingKeys: String, CodingKey { case label, width, height, fit, orientation, upscale, video }
    struct SizeVideo: Codable { struct CBR: Codable { let bitrate: String }; let cbr: CBR }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decode(RenditionLabel.self, forKey: .label)
        width = try c.decode(Int.self, forKey: .width)
        height = try c.decode(Int.self, forKey: .height)
        fit = try c.decode(Fit.self, forKey: .fit)
        orientation = try c.decode(Orientation.self, forKey: .orientation)
        upscale = try c.decode(Bool.self, forKey: .upscale)
        cbrBitrate = try c.decodeIfPresent(SizeVideo.self, forKey: .video)?.cbr.bitrate
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(label, forKey: .label)
        try c.encode(width, forKey: .width)
        try c.encode(height, forKey: .height)
        try c.encode(fit, forKey: .fit)
        try c.encode(orientation, forKey: .orientation)
        try c.encode(upscale, forKey: .upscale)
        if let cbrBitrate { try c.encode(SizeVideo(cbr: .init(bitrate: cbrBitrate)), forKey: .video) }
    }
}

/// An automatic ladder: the standard short sides up to `maxShortSide`, never above the source.
public struct Ladder: Codable, Hashable, Sendable {
    public var maxShortSide: Int
    public var fit: Fit
    public var upscale: Bool

    public init(maxShortSide: Int, fit: Fit, upscale: Bool) {
        self.maxShortSide = maxShortSide
        self.fit = fit
        self.upscale = upscale
    }

    enum CodingKeys: String, CodingKey {
        case fit, upscale
        case maxShortSide = "max_short_side"
    }
}

/// One output at the source's size (even-aligned for video).
public struct SourceSize: Codable, Hashable, Sendable {
    public var label: RenditionLabel
    public var fit: Fit
    public var upscale: Bool

    public init(label: RenditionLabel, fit: Fit, upscale: Bool) {
        self.label = label
        self.fit = fit
        self.upscale = upscale
    }
}

// MARK: Subtitles, trim

public struct SubtitleTracks: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    /// Every subtitle track of the source.
    public static let all: Self = "all"
    public static let none: Self = "none"
}

/// Which subtitle tracks are carried.
public enum Subtitles: Codable, Hashable, Sendable {
    case tracks(SubtitleTracks)
    /// The tracks in these languages (ISO 639 codes such as `eng`), 1 or more.
    case languages([String])

    enum Key: String, CodingKey { case tracks, languages }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        if let t = try c.decodeIfPresent(SubtitleTracks.self, forKey: .tracks) {
            self = .tracks(t)
        } else {
            self = .languages(try c.decode([String].self, forKey: .languages))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Key.self)
        switch self {
        case .tracks(let t): try c.encode(t, forKey: .tracks)
        case .languages(let l): try c.encode(l, forKey: .languages)
        }
    }
}

/// Which part of the source is used.
public struct Trim: Codable, Hashable, Sendable {
    /// Seconds from the start, ≥ 0.
    public var start: Double
    public var end: TrimEnd

    public init(start: Double, end: TrimEnd) {
        self.start = start
        self.end = end
    }

    /// The whole source: `{start: 0, end: "source"}`.
    public static let whole = Trim(start: 0, end: .source)
}

public enum TrimEnd: Codable, Hashable, Sendable {
    /// Seconds from the start, after `start`.
    case seconds(Double)
    /// The end of the source.
    case source

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let n = try? c.decode(Double.self) { self = .seconds(n); return }
        let s = try c.decode(String.self)
        guard s == "source" else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "trim.end: \(s)") }
        self = .source
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .seconds(let n): try c.encode(n)
        case .source: try c.encode("source")
        }
    }
}

// MARK: Privacy

public struct PrivacyPreset: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    /// Strip every category.
    public static let stripAll: Self = "strip_all"
    /// Strip location, keep the rest.
    public static let stripLocation: Self = "strip_location"
    /// Keep every category (`device: keep_all`).
    public static let keepAll: Self = "keep_all"
    public static let all: [Self] = [.stripAll, .stripLocation, .keepAll]
}

public struct LocationHandling: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let strip: Self = "strip"
    /// Rounded to 2 decimal places (about 1 km), no altitude, no place name.
    public static let approximate: Self = "approximate"
    public static let keep: Self = "keep"
    public static let all: [Self] = [.strip, .approximate, .keep]
}

public struct CaptureTimeHandling: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let strip: Self = "strip"
    /// The day, with the time of day zeroed.
    public static let date: Self = "date"
    public static let keep: Self = "keep"
    public static let all: [Self] = [.strip, .date, .keep]
}

public struct DeviceHandling: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let strip: Self = "strip"
    /// Make, model, software and lens.
    public static let keep: Self = "keep"
    /// Also serial numbers and the owner name (images only).
    public static let keepAll: Self = "keep_all"
    public static let all: [Self] = [.strip, .keep, .keepAll]
}

public struct DescriptiveHandling: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let strip: Self = "strip"
    public static let keep: Self = "keep"
    public static let all: [Self] = [.strip, .keep]
}

/// Which identifying metadata survives: a preset, or every category stated. Responses always
/// state every category.
public enum Privacy: Codable, Hashable, Sendable {
    case preset(PrivacyPreset)
    case fields(PrivacyFields)

    enum Key: String, CodingKey { case preset }

    public init(from decoder: Decoder) throws {
        if let preset = try decoder.container(keyedBy: Key.self).decodeIfPresent(PrivacyPreset.self, forKey: .preset) {
            self = .preset(preset)
        } else {
            self = .fields(try PrivacyFields(from: decoder))
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .preset(let p):
            var c = encoder.container(keyedBy: Key.self)
            try c.encode(p, forKey: .preset)
        case .fields(let f): try f.encode(to: encoder)
        }
    }

    /// Every category, a preset expanded.
    public var resolved: PrivacyFields {
        switch self {
        case .fields(let f): return f
        case .preset(.stripLocation): return PrivacyFields(location: .strip, captureTime: .keep, device: .keep, descriptive: .keep)
        case .preset(.keepAll): return PrivacyFields(location: .keep, captureTime: .keep, device: .keepAll, descriptive: .keep)
        case .preset: return PrivacyFields(location: .strip, captureTime: .strip, device: .strip, descriptive: .strip)
        }
    }
}

public struct PrivacyFields: Codable, Hashable, Sendable {
    /// GPS coordinates and place names.
    public var location: LocationHandling
    /// When it was recorded.
    public var captureTime: CaptureTimeHandling
    /// What made it.
    public var device: DeviceHandling
    /// Title, artist, copyright and other tags.
    public var descriptive: DescriptiveHandling

    public init(location: LocationHandling, captureTime: CaptureTimeHandling, device: DeviceHandling, descriptive: DescriptiveHandling) {
        self.location = location
        self.captureTime = captureTime
        self.device = device
        self.descriptive = descriptive
    }

    /// Whether any category is kept in any form.
    public var keepsAny: Bool {
        location != .strip || captureTime != .strip || device != .strip || descriptive != .strip
    }

    enum CodingKeys: String, CodingKey {
        case location, device, descriptive
        case captureTime = "capture_time"
    }
}

// MARK: - Overrides and provenance

/// A preset's partial override, as sent with `preset` on job and automation requests and on a
/// preset `PATCH`: the JSON merged over the preset's version. Objects merge key by key; scalars
/// and arrays replace; one choice of an exclusive group (`quality`/`crf`/`cbr`,
/// `sizes`/`ladder`/`source_size`, `tracks`/`languages`, the forms of `gop` and `frames`)
/// replaces the others; `null` removes a field; `kind` cannot change. The merged result must be
/// complete. Build one by hand, or with `SpecTools.diff`.
public struct OutputOverrides: Codable, Hashable, Sendable, ExpressibleByDictionaryLiteral {
    public var json: JSONValue

    public init(json: JSONValue) { self.json = json }

    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        json = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }

    public var isEmpty: Bool { json.objectValue?.isEmpty ?? true }

    public init(from decoder: Decoder) throws { json = try JSONValue(from: decoder) }
    public func encode(to encoder: Encoder) throws { try json.encode(to: encoder) }
}

/// Where a job's spec came from: the preset version and the request's overrides over it.
public struct PresetProvenance: Codable, Hashable, Sendable {
    /// The preset as the request named it: a slug or a `pre_…` id.
    public var id: String
    /// The version the job resolved against.
    public var version: Int?
    /// The request's `output` over the preset, in v2; nil when none was sent.
    public var overrides: OutputOverrides?

    public init(id: String, version: Int?, overrides: OutputOverrides?) {
        self.id = id
        self.version = version
        self.overrides = overrides
    }

    /// `slug@N`: this exact version, as a job's `preset` would name it.
    public var pinned: String { version.map { "\(id)@\($0)" } ?? id }
}

/// One validation failure: a dotted param (`output.audio.bitrate`) and the message.
public struct FieldError: Codable, Hashable, Sendable {
    public var param: String
    public var message: String

    public init(param: String, message: String) {
        self.param = param
        self.message = message
    }
}

