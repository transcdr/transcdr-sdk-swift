import Foundation

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
