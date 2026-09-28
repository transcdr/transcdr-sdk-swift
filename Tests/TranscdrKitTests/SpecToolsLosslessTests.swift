import XCTest
@testable import TranscdrKit

final class SpecToolsLosslessTests: XCTestCase {
    func spec(_ mode: OutputMode, _ audio: AudioSettings) -> OutputSpec {
        var s = SpecTools.resolved(nil)
        s.mode = mode
        s.audio = audio
        return s
    }

    func audioOnly(_ audio: AudioSettings) -> OutputSpec { spec(.audio, audio) }

    func testTheNewFieldsEncodeOnlyWhenSetAndRoundTrip() throws {
        XCTAssertEqual(try JSONValue.from(AudioSettings(mode: .aac)), ["mode": "aac"])
        let a = AudioSettings(mode: .flac, bitDepth: .twentyFour, flacCompression: .best, container: .flac)
        XCTAssertEqual(
            try JSONValue.from(a),
            ["mode": "flac", "bit_depth": "24", "flac_compression": "best", "container": "flac"]
        )
        let json = #"{"mode":"flac","bit_depth":"24","flac_compression":"best","container":"flac"}"#
        XCTAssertEqual(try JSONDecoder().decode(AudioSettings.self, from: Data(json.utf8)), a)

        let alac = AudioSettings(mode: .alac, bitDepth: .sixteen, container: .m4a)
        XCTAssertEqual(try JSONDecoder().decode(AudioSettings.self, from: JSONEncoder().encode(alac)), alac)
        let aac = AudioSettings(mode: .aac, bitrate: "96k", channels: .stereo, container: .m4a)
        XCTAssertEqual(try JSONValue.from(aac), ["mode": "aac", "bitrate": "96k", "channels": "stereo", "container": "m4a"])
        XCTAssertEqual(try JSONDecoder().decode(AudioSettings.self, from: JSONEncoder().encode(aac)), aac)

        let decoded = try JSONDecoder().decode(
            OutputSpec.self,
            from: Data(#"{"mode":"single","audio":{"mode":"flac","bit_depth":"source","flac_compression":"fast"}}"#.utf8)
        )
        XCTAssertEqual(decoded.audio, AudioSettings(mode: .flac, bitDepth: .source, flacCompression: .fast))
    }

    func testValuesAndUnknownOnes() throws {
        XCTAssertEqual(AudioMode.all.map(\.rawValue), ["auto", "opus", "mp3", "aac", "flac", "alac", "drop"])
        XCTAssertEqual(AudioBitDepth.all.map(\.rawValue), ["source", "16", "24"])
        XCTAssertEqual(FlacCompression.all.map(\.rawValue), ["fast", "default", "best"])
        XCTAssertEqual(AudioContainer.all.map(\.rawValue), ["auto", "mp3", "flac", "m4a"])
        let a = try JSONDecoder().decode(AudioSettings.self, from: Data(#"{"bit_depth":"32","flac_compression":"max","container":"ogg"}"#.utf8))
        XCTAssertEqual(a.bitDepth?.rawValue, "32")
        XCTAssertEqual(a.flacCompression?.rawValue, "max")
        XCTAssertEqual(a.container?.rawValue, "ogg")
    }

    func testResolvedNormalizeAndDiffKeepTheNewFields() {
        let s = audioOnly(AudioSettings(mode: .flac, bitDepth: .twentyFour, flacCompression: .best, container: .flac))
        XCTAssertEqual(SpecTools.resolved(s).audio, s.audio)
        XCTAssertEqual(SpecTools.normalize(s).audio, s.audio)
        XCTAssertEqual(SpecTools.normalize(audioOnly(AudioSettings(mode: .aac, container: "mp4"))).audio?.container, .m4a)

        let base = audioOnly(AudioSettings(mode: .mp3, bitrate: "128k"))
        XCTAssertEqual(
            SpecTools.diff(s, base: base).json["audio"],
            ["mode": "flac", "bitrate": .null, "bit_depth": "24", "flac_compression": "best", "container": "flac"]
        )
        XCTAssertEqual(
            SpecTools.diff(audioOnly(AudioSettings(mode: .alac)), base: s).json["audio"],
            ["mode": "alac", "bit_depth": .null, "flac_compression": .null, "container": .null],
            "leaving FLAC clears the preset's depth, effort and file"
        )
    }

    func testContainerAndCodec() {
        XCTAssertNil(SpecTools.audioContainer(spec(.single, AudioSettings(mode: .flac))))
        XCTAssertEqual(SpecTools.audioContainer(audioOnly(AudioSettings(mode: .flac))), .flac)
        XCTAssertEqual(SpecTools.audioContainer(audioOnly(AudioSettings(mode: .alac))), .m4a)
        XCTAssertEqual(SpecTools.audioContainer(audioOnly(AudioSettings(mode: .aac))), .mp3)
        XCTAssertEqual(SpecTools.audioContainer(audioOnly(AudioSettings(mode: .alac, container: .auto))), .m4a)
        XCTAssertEqual(SpecTools.audioCodec(audioOnly(AudioSettings())), .mp3)
        XCTAssertEqual(SpecTools.audioCodec(audioOnly(AudioSettings(container: .m4a))), .opus)
        XCTAssertEqual(SpecTools.audioCodec(spec(.single, AudioSettings())), .opus)
        XCTAssertNil(SpecTools.audioCodec(spec(.single, AudioSettings(mode: .drop))))
        XCTAssertFalse(SpecTools.isMp3Output(audioOnly(AudioSettings(mode: .aac, container: .m4a))))
        XCTAssertTrue(SpecTools.isMp3Output(audioOnly(AudioSettings())))
    }

    func testValidOutputsPass() {
        for s in [
            audioOnly(AudioSettings(mode: .aac, container: .m4a)),
            audioOnly(AudioSettings(mode: .alac)),
            audioOnly(AudioSettings(mode: .flac, bitDepth: .twentyFour, flacCompression: .best)),
            audioOnly(AudioSettings(mode: .flac, container: .m4a)),
            audioOnly(AudioSettings(mode: .opus, container: .m4a)),
            audioOnly(AudioSettings(container: .m4a)),
            audioOnly(AudioSettings(mode: .mp3, container: .mp3)),
            spec(.single, AudioSettings(mode: .flac, bitDepth: .sixteen)),
            spec(.hls, AudioSettings(mode: .alac)),
            spec(.hls, AudioSettings(mode: .aac, channels: .surround51, stereoFallback: true)),
            spec(.single, AudioSettings(mode: .aac, bitrate: "256k", channels: .stereo)),
            spec(.single, AudioSettings(mode: .aac, bitrate: "512k", channels: .surround71)),
            spec(.single, AudioSettings(mode: .aac, bitrate: "8k")),
            spec(.single, AudioSettings(mode: .opus, bitDepth: .source, flacCompression: .default, container: .auto)),
        ] {
            XCTAssertEqual(SpecTools.validate(s), [:], "\(String(describing: s.audio))")
        }
    }

    func testEachMessage() {
        func error(_ s: OutputSpec, _ field: String) -> String? { SpecTools.validate(s)["output.audio.\(field)"] }

        XCTAssertEqual(
            error(audioOnly(AudioSettings(mode: .drop)), "mode"),
            "Audio-only output needs audio: set audio.mode to \"auto\" or a codec."
        )
        XCTAssertEqual(
            error(spec(.single, AudioSettings(mode: .aac, container: .m4a)), "container"),
            "container applies only to mode \"audio\": video output is an MP4 or an HLS package."
        )
        XCTAssertEqual(
            error(audioOnly(AudioSettings(mode: .alac, container: .flac)), "container"),
            "A .flac file holds FLAC only: set audio.mode to \"flac\", or container to \"m4a\"."
        )
        XCTAssertEqual(
            error(audioOnly(AudioSettings(container: .flac)), "container"),
            "A .flac file holds FLAC only: set audio.mode to \"flac\", or container to \"m4a\".",
            "auto audio in a .flac is Opus"
        )
        XCTAssertEqual(
            error(audioOnly(AudioSettings(mode: .flac, container: .mp3)), "container"),
            "An .mp3 file cannot hold lossless audio: set container to \"flac\" or \"m4a\"."
        )
        XCTAssertEqual(
            error(audioOnly(AudioSettings(mode: .aac)), "mode"),
            "An .mp3 file cannot hold AAC: use \"auto\" or \"mp3\", or set container to \"m4a\"."
        )
        XCTAssertEqual(
            error(audioOnly(AudioSettings(mode: .opus, container: .mp3)), "mode"),
            "An .mp3 file cannot hold Opus: use \"auto\" or \"mp3\", or set container to \"m4a\"."
        )
        XCTAssertEqual(
            error(spec(.hls, AudioSettings(mode: .mp3)), "mode"),
            "MP3 is not available for HLS: use \"auto\", \"aac\" or \"opus\" there, or a single file or audio-only output for MP3."
        )
        XCTAssertEqual(
            error(spec(.single, AudioSettings(mode: .aac, bitDepth: .twentyFour)), "bit_depth"),
            "bit_depth applies to FLAC and ALAC only."
        )
        XCTAssertEqual(
            error(spec(.single, AudioSettings(mode: .alac, flacCompression: .best)), "flac_compression"),
            "flac_compression applies to FLAC only."
        )
        XCTAssertEqual(
            error(spec(.single, AudioSettings(mode: .flac, bitrate: "128k")), "bitrate"),
            "FLAC and ALAC are lossless and take no bitrate: remove audio.bitrate."
        )
        XCTAssertEqual(
            error(audioOnly(AudioSettings(mode: .alac, bitrate: "900k")), "bitrate"),
            "FLAC and ALAC are lossless and take no bitrate: remove audio.bitrate."
        )
        XCTAssertEqual(
            error(spec(.single, AudioSettings(mode: .aac, bitrate: "12k", channels: .stereo)), "bitrate"),
            "AAC takes 8k to 288k per channel: 16k to 512k for stereo."
        )
        XCTAssertEqual(
            error(spec(.single, AudioSettings(mode: .aac, bitrate: "300k", channels: .mono)), "bitrate"),
            "AAC takes 8k to 288k per channel: 8k to 288k for mono."
        )
        XCTAssertEqual(
            error(spec(.hls, AudioSettings(mode: .aac, bitrate: "32k", channels: .surround51)), "bitrate"),
            "AAC takes 8k to 288k per channel: 40k to 512k for 5.1."
        )
        XCTAssertEqual(
            error(spec(.single, AudioSettings(mode: .aac, bitrate: "48k", channels: .surround71)), "bitrate"),
            "AAC takes 8k to 288k per channel: 56k to 512k for 7.1."
        )
        XCTAssertEqual(error(spec(.single, AudioSettings(mode: .aac, bitrate: "7k")), "bitrate"), "AAC takes at least 8k.")
        XCTAssertEqual(
            error(spec(.single, AudioSettings(mode: .aac, bitrate: "7k", channels: .source)), "bitrate"),
            "AAC takes at least 8k."
        )
    }

    func testDescribe() {
        XCTAssertEqual(SpecTools.describe(audioOnly(AudioSettings(mode: .mp3, bitrate: "128k"))), "MP3 audio · 128k")
        XCTAssertEqual(SpecTools.describe(audioOnly(AudioSettings(mode: .aac, container: .m4a))), "AAC audio · .m4a")
        XCTAssertEqual(
            SpecTools.describe(audioOnly(AudioSettings(mode: .flac, bitDepth: .twentyFour, flacCompression: .best))),
            "FLAC audio · .flac · 24-bit"
        )
        XCTAssertEqual(SpecTools.describe(audioOnly(AudioSettings(mode: .alac))), "ALAC audio · .m4a")
        XCTAssertEqual(SpecTools.describe(audioOnly(AudioSettings(container: .m4a))), "Opus audio · .m4a")
    }
}
