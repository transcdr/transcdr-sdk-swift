import XCTest
@testable import TranscdrKit

final class SpecToolsAudioTests: XCTestCase {
    func audioOnly(_ audio: AudioSettings = AudioSettings(mode: .mp3, bitrate: "128k")) -> OutputSpec {
        var s = SpecTools.resolved(nil)
        s.mode = .audio
        s.audio = audio
        return s
    }

    func testTheNewFieldsEncodeOnlyWhenSetAndRoundTrip() throws {
        XCTAssertEqual(try JSONValue.from(AudioSettings(mode: .mp3)), ["mode": "mp3"])
        let a = AudioSettings(mode: .opus, bitrate: "320k", channels: .surround51, stereoFallback: true)
        XCTAssertEqual(
            try JSONValue.from(a),
            ["mode": "opus", "bitrate": "320k", "channels": "5.1", "stereo_fallback": true]
        )
        let json = #"{"mode":"opus","bitrate":"320k","channels":"5.1","stereo_fallback":true}"#
        XCTAssertEqual(try JSONDecoder().decode(AudioSettings.self, from: Data(json.utf8)), a)

        let spec = try JSONDecoder().decode(OutputSpec.self, from: Data(#"{"mode":"audio","audio":{"mode":"mp3","channels":"7.1"}}"#.utf8))
        XCTAssertEqual(spec.mode, .audio)
        XCTAssertEqual(spec.audio?.mode, .mp3)
        XCTAssertEqual(spec.audio?.channels, .surround71)
        XCTAssertNil(spec.audio?.stereoFallback)
        XCTAssertEqual(try JSONValue.from(OutputSpec(mode: .audio, audio: AudioSettings(channels: .mono))), ["mode": "audio", "audio": ["channels": "mono"]])
    }

    func testUnknownValuesDecodeAsTheyAre() throws {
        let a = try JSONDecoder().decode(AudioSettings.self, from: Data(#"{"mode":"future","channels":"22.2"}"#.utf8))
        XCTAssertEqual(a.mode?.rawValue, "future")
        XCTAssertEqual(a.channels?.rawValue, "22.2")
        XCTAssertEqual(AudioChannels.all.map(\.rawValue), ["source", "mono", "stereo", "5.1", "7.1"])
        XCTAssertTrue(AudioMode.all.contains(.mp3))
        XCTAssertTrue(OutputMode.all.contains(.audio))
    }

    func testNormalizeAndDiffCarryTheNewFields() {
        var s = SpecTools.resolved(nil)
        s.mode = .hls
        s.audio = AudioSettings(mode: .opus, bitrate: " 320k ", channels: .surround51, stereoFallback: true)
        XCTAssertEqual(SpecTools.normalize(s).audio, AudioSettings(mode: .opus, bitrate: "320k", channels: .surround51, stereoFallback: true))
        XCTAssertEqual(SpecTools.resolved(s).audio?.channels, .surround51)

        var base = SpecTools.resolved(nil)
        base.mode = .hls
        XCTAssertEqual(
            SpecTools.diff(s, base: base).json["audio"],
            ["mode": "opus", "bitrate": "320k", "channels": "5.1", "stereo_fallback": true]
        )
        var back = s
        back.audio = AudioSettings(mode: .opus)
        XCTAssertEqual(
            SpecTools.diff(back, base: s).json["audio"],
            ["mode": "opus", "bitrate": .null, "channels": .null, "stereo_fallback": .null],
            "leaving surround clears the preset's layout and fallback"
        )
    }

    func testValidationMirrorsTheServer() {
        XCTAssertEqual(SpecTools.validate(audioOnly()), [:])
        XCTAssertEqual(SpecTools.validate(audioOnly(AudioSettings(mode: .auto, channels: .mono))), [:])

        var video = audioOnly()
        video.renditions = [Rendition(width: 1280, height: 720)]
        video.codec = .h264
        video.trim = Trim(start: 5)
        let errors = SpecTools.validate(video)
        XCTAssertEqual(errors["output.renditions"], "Audio-only output writes no video, so renditions does not apply.")
        XCTAssertEqual(errors["output.codec"], "Audio-only output writes no video, so codec does not apply.")
        XCTAssertEqual(errors["output.trim"], "A trim is not available for audio-only output.")

        XCTAssertEqual(
            SpecTools.validate(audioOnly(AudioSettings(mode: .drop)))["output.audio.mode"],
            "Audio-only output needs audio: set audio.mode to \"auto\" or a codec."
        )
        XCTAssertEqual(
            SpecTools.validate(audioOnly(AudioSettings(mode: .opus)))["output.audio.mode"],
            "An .mp3 file cannot hold Opus: use \"auto\" or \"mp3\", or set container to \"m4a\"."
        )
        var hls = SpecTools.resolved(nil)
        hls.mode = .hls
        hls.audio = AudioSettings(mode: .mp3)
        XCTAssertEqual(
            SpecTools.validate(hls)["output.audio.mode"],
            "MP3 is not available for HLS: use \"auto\", \"aac\" or \"opus\" there, or a single file or audio-only output for MP3."
        )

        var single = SpecTools.resolved(nil)
        single.audio = AudioSettings(mode: .drop, channels: .stereo)
        XCTAssertEqual(SpecTools.validate(single)["output.audio.channels"], "Audio channels mean nothing when audio is dropped.")
        single.audio = AudioSettings(mode: .mp3, channels: .surround51)
        XCTAssertEqual(
            SpecTools.validate(single)["output.audio.channels"],
            "MP3 carries two channels at most: choose source, mono or stereo (a surround source is downmixed to stereo)."
        )
        single.audio = AudioSettings(mode: .opus, channels: .surround51)
        XCTAssertEqual(SpecTools.validate(single), [:], "Opus carries surround")

        single.audio = AudioSettings(stereoFallback: true)
        XCTAssertEqual(SpecTools.validate(single)["output.audio.stereo_fallback"], "stereo_fallback applies only to mode \"hls\".")
        hls.audio = AudioSettings(mode: .drop, stereoFallback: true)
        XCTAssertEqual(SpecTools.validate(hls)["output.audio.stereo_fallback"], "stereo_fallback means nothing when audio is dropped.")
        hls.audio = AudioSettings(channels: .stereo, stereoFallback: true)
        XCTAssertEqual(
            SpecTools.validate(hls)["output.audio.stereo_fallback"],
            "stereo_fallback adds a stereo rendition beside surround audio, so channels must be source, 5.1 or 7.1."
        )
        hls.audio = AudioSettings(channels: .surround71, stereoFallback: true)
        XCTAssertEqual(SpecTools.validate(hls), [:])

        XCTAssertEqual(
            SpecTools.validate(audioOnly(AudioSettings(mode: .mp3, bitrate: "100k")))["output.audio.bitrate"],
            "MP3 is constant bitrate at 32k, 40k, 48k, 56k, 64k, 80k, 96k, 112k, 128k, 160k, 192k, 224k, 256k or 320k."
        )
        XCTAssertNil(SpecTools.validate(audioOnly(AudioSettings(bitrate: "320000")))["output.audio.bitrate"])
        single.audio = AudioSettings(mode: .opus, bitrate: "100k")
        XCTAssertNil(SpecTools.validate(single)["output.audio.bitrate"], "any rate for Opus")
    }

    func testDescribe() {
        XCTAssertEqual(SpecTools.describe(audioOnly()), "MP3 audio · 128k")
        XCTAssertEqual(SpecTools.describe(audioOnly(AudioSettings(mode: .mp3, bitrate: "64k", channels: .mono))), "MP3 audio · 64k · mono")
    }
}
