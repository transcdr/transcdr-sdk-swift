import XCTest
@testable import TranscdrKit

final class SpecToolsTests: XCTestCase {
    func hls1080() -> OutputSpec {
        var s = SpecTools.resolved(nil)
        s.mode = .hls
        s.ladder = Ladder(maxShortSide: 1080)
        s.segmentSeconds = 4
        s.quality = Quality(target: "standard")
        return s
    }

    func testDiffAgainstThePresetIsMinimal() {
        let preset = hls1080()
        XCTAssertTrue(SpecTools.diff(preset, base: preset).isEmpty)

        var edited = preset
        edited.codec = .h265
        edited.quality = Quality(crf: 30)
        let json = SpecTools.diff(edited, base: preset).json
        XCTAssertEqual(json["codec"], "h265")
        XCTAssertEqual(json["quality"], ["crf": 30, "target": .null], "a nested key removed is cleared explicitly")
        XCTAssertNil(json["mode"])
        XCTAssertNil(json["ladder"])

        var noLadder = preset
        noLadder.ladder = nil
        noLadder.renditions = [Rendition(width: 1280, height: 720)]
        let j2 = SpecTools.diff(noLadder, base: preset).json
        XCTAssertEqual(j2["ladder"], .null, "a field set on the preset and unset here is cleared")
        XCTAssertEqual(j2["renditions"], [["width": 1280, "height": 720]])
    }

    func testNormalizeDropsEditorArtefacts() {
        var s = SpecTools.resolved(nil)
        s.renditions = [Rendition(width: 1920, height: 1080, bitrate: "  ", label: "")]
        s.segmentSeconds = 6
        s.trim = Trim(start: 0, end: nil)
        let n = SpecTools.normalize(s)
        XCTAssertNil(n.renditions?.first?.bitrate)
        XCTAssertNil(n.renditions?.first?.label)
        XCTAssertNil(n.segmentSeconds, "segments only mean something for HLS")
        XCTAssertNil(n.trim)
    }

    func testValidationUsesTheServersRules() {
        var s = SpecTools.resolved(nil)
        s.renditions = [Rendition(width: 1921, height: 1080), Rendition(width: 1280, height: 720, label: "bad label")]
        s.codec = .h264
        s.bitDepth = .ten
        s.maxFps = 500
        s.audio = AudioSettings(mode: .drop, bitrate: "128k")
        let e = SpecTools.validate(s, maxShortSide: 1080)
        XCTAssertEqual(e["output.renditions.0.width"], "Width and height must be even (4:2:0 chroma).")
        XCTAssertNotNil(e["output.renditions.1.label"])
        XCTAssertNotNil(e["output.bit_depth"])
        XCTAssertNotNil(e["output.max_fps"])
        XCTAssertEqual(e["output.audio.bitrate"], "An audio bitrate means nothing when audio is dropped.")
        XCTAssertTrue(SpecTools.validate(hls1080()).isEmpty)
        var big = SpecTools.resolved(nil)
        big.renditions = [Rendition(width: 3840, height: 2160)]
        XCTAssertEqual(SpecTools.validate(big, maxShortSide: 1080)["output.renditions.0.height"], "Your plan allows renditions up to 1080p.")
    }

    func testHelpers() {
        XCTAssertEqual(SpecTools.parseBitrate("800k"), 800_000)
        XCTAssertEqual(SpecTools.parseBitrate("3M"), 3_000_000)
        XCTAssertNil(SpecTools.parseBitrate("fast"))
        XCTAssertTrue(SpecTools.isQualityTarget("vmaf=95"))
        XCTAssertFalse(SpecTools.isQualityTarget("vmaf=101"))
        XCTAssertEqual(SpecTools.describe(hls1080()), "HLS · AV1 · ladder ≤ 1080p · standard")
        XCTAssertEqual(Catalog.tier(forShortSide: 720), .hd)
        XCTAssertEqual(Catalog.tier(forShortSide: 2160), .uhd)
    }

    func testJobRequestCarriesTheOverride() throws {
        var edited = hls1080()
        edited.maxFps = 30
        let params = JobCreateParams(input: .url("https://x/y.mov"), output: SpecTools.diff(edited, base: hls1080()), preset: "hls-av1-abr")
        let json = try JSONValue.from(params)
        XCTAssertEqual(json["output"], ["max_fps": 30])
        let none = try JSONValue.from(JobCreateParams(input: .url("https://x/y.mov"), output: SpecTools.diff(hls1080(), base: hls1080())))
        XCTAssertNil(none["output"])
    }
}
