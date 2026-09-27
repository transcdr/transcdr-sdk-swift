import XCTest
@testable import TranscdrKit

final class SpecToolsCbrTests: XCTestCase {
    func hlsH264Cbr() -> OutputSpec {
        var s = SpecTools.resolved(nil)
        s.mode = .hls
        s.codec = .h264
        s.renditions = [Rendition(width: 1920, height: 1080), Rendition(width: 1280, height: 720)]
        s.quality = Quality(target: "cbr")
        return s
    }

    func testTheDefaultRateIsTheServicesTable() {
        let h264 = { (side: Int) in SpecTools.defaultCbrRate(codec: .h264, width: side * 16 / 9, height: side) }
        XCTAssertEqual(h264(1080), 5_000_000)
        XCTAssertEqual(h264(720), 3_000_000)
        XCTAssertEqual(h264(480), 1_200_000)
        XCTAssertEqual(h264(360), 800_000)
        XCTAssertEqual(h264(2160), 16_000_000)
        XCTAssertEqual(SpecTools.defaultCbrRate(codec: .h264, width: 960, height: 540), 1_650_000, "interpolated")
        XCTAssertEqual(SpecTools.defaultCbrRate(codec: .h264, width: 100, height: 100), 200_000, "floored below 144")
        XCTAssertEqual(SpecTools.defaultCbrRate(codec: .h264, width: 7680, height: 4320), 64_000_000, "by area above 2160")
        XCTAssertEqual(SpecTools.defaultCbrRate(codec: .h264, width: 1080, height: 1920), 5_000_000, "by the short side")
        XCTAssertEqual(SpecTools.defaultCbrRate(codec: .h265, width: 1920, height: 1080), 3_250_000)
        XCTAssertEqual(SpecTools.defaultCbrRate(codec: .av1, width: 1920, height: 1080), 2_500_000)
        XCTAssertEqual(SpecTools.defaultCbrRate(codec: .h264, width: 1920, height: 1080, fps: 24), 5_000_000)
        XCTAssertEqual(SpecTools.defaultCbrRate(codec: .h264, width: 1920, height: 1080, fps: 60), 7_500_000)
        XCTAssertEqual(SpecTools.defaultCbrRate(codec: .h264, width: 1920, height: 1080, fps: 240), 12_500_000, "capped at 120 fps")
        XCTAssertEqual(SpecTools.formatBitrate(3_250_000), "3.25M")
        XCTAssertEqual(SpecTools.formatBitrate(800_000), "800k")
    }

    func testTheNewFieldsEncodeOnlyWhenSetAndRoundTrip() throws {
        XCTAssertEqual(try JSONValue.from(Quality(target: "cbr")), ["target": "cbr"])
        let q = Quality(target: "cbr", bitrate: "4M", bufferMs: 500)
        XCTAssertEqual(try JSONValue.from(q), ["target": "cbr", "bitrate": "4M", "buffer_ms": 500])
        let decoded = try JSONDecoder().decode(Quality.self, from: Data(#"{"target":"cbr","bitrate":"4M","buffer_ms":500}"#.utf8))
        XCTAssertEqual(decoded, q)
        XCTAssertTrue(SpecTools.isQualityTarget("cbr"))
    }

    func testNormalizeAndDiffCarryTheNewFields() {
        var s = hlsH264Cbr()
        s.quality = Quality(target: "cbr", bitrate: " 4M ", bufferMs: 500)
        XCTAssertEqual(SpecTools.normalize(s).quality, Quality(target: "cbr", bitrate: "4M", bufferMs: 500))
        s.quality?.bitrate = "  "
        XCTAssertNil(SpecTools.normalize(s).quality?.bitrate)

        var preset = hlsH264Cbr()
        preset.quality = Quality(target: "cbr", bitrate: "4M", bufferMs: 500)
        var back = preset
        back.quality = Quality(target: "standard")
        XCTAssertEqual(
            SpecTools.diff(back, base: preset).json["quality"],
            ["target": "standard", "bitrate": .null, "buffer_ms": .null],
            "leaving cbr clears the preset's rate and buffer"
        )
        var rates = hlsH264Cbr()
        rates.renditions?[0].bitrate = "6M"
        rates.quality?.bufferMs = 2000
        let json = SpecTools.diff(rates, base: hlsH264Cbr()).json
        XCTAssertEqual(json["quality"], ["target": "cbr", "buffer_ms": 2000])
        XCTAssertEqual(json["renditions"], [["width": 1920, "height": 1080, "bitrate": "6M"], ["width": 1280, "height": 720]])
    }

    func testValidationMirrorsTheServersRefusals() {
        XCTAssertTrue(SpecTools.validate(hlsH264Cbr()).isEmpty)

        var withCrf = hlsH264Cbr()
        withCrf.quality = Quality(target: "cbr", crf: 30)
        XCTAssertEqual(SpecTools.validate(withCrf)["output.quality.crf"], "crf names a quality level and cbr a bit rate: use one or the other.")

        var bad = hlsH264Cbr()
        bad.quality = Quality(target: "cbr", bitrate: "50k", bufferMs: 50)
        bad.renditions?[0].bitrate = "fast"
        bad.renditions?[1].bitrate = "300M"
        let e = SpecTools.validate(bad)
        XCTAssertEqual(e["output.quality.bitrate"], "A constant bitrate must be between 100k and 200M.")
        XCTAssertEqual(e["output.quality.buffer_ms"], "buffer_ms must be between 100 and 10000.")
        XCTAssertEqual(e["output.renditions.0.bitrate"], "Bitrate must look like 800k, 3M or 2500000.")
        XCTAssertEqual(e["output.renditions.1.bitrate"], "A constant bitrate must be between 100k and 200M.")

        var notCbr = hlsH264Cbr()
        notCbr.quality = Quality(target: "standard", bufferMs: 1000)
        notCbr.renditions?[0].bitrate = "3M"
        let n = SpecTools.validate(notCbr)
        XCTAssertEqual(n["output.renditions.0.bitrate"], "A rendition bitrate is a constant bit rate: set quality.target to \"cbr\", or remove the bitrate to code to a quality level.")
        XCTAssertEqual(n["output.quality.buffer_ms"], "A bitrate and buffer apply to constant bit rate: set quality.target to \"cbr\".")
        notCbr.quality?.bitrate = "3M"
        XCTAssertNotNil(SpecTools.validate(notCbr)["output.quality.bitrate"], "the rate is named first")
    }

    func testDescribeShowsTheRates() {
        var s = hlsH264Cbr()
        XCTAssertEqual(SpecTools.describe(s), "HLS · H.264 · 1080p / 720p · CBR (default rates)")
        s.renditions?[0].bitrate = "5M"
        s.renditions?[1].bitrate = "3M"
        XCTAssertEqual(SpecTools.describe(s), "HLS · H.264 · 1080p / 720p · CBR 5 / 3 Mb/s")
        s.renditions?[1].bitrate = nil
        XCTAssertEqual(SpecTools.describe(s), "HLS · H.264 · 1080p / 720p · CBR 5 / 3 Mb/s", "a rendition without a rate shows its default")
        var ladder = SpecTools.resolved(nil)
        ladder.ladder = Ladder(maxShortSide: 1080)
        ladder.quality = Quality(target: "cbr", bitrate: "5M")
        XCTAssertEqual(SpecTools.describe(ladder), "MP4 · AV1 · ladder ≤ 1080p · CBR 5 Mb/s")
    }
}
