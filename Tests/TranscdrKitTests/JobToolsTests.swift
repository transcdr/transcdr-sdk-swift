import XCTest
@testable import TranscdrKit

final class JobToolsTests: XCTestCase {
    func info(_ w: Int, _ h: Int, duration: Double) throws -> MediaInfo {
        try TranscdrCoding.decoder.decode(MediaInfo.self, from: Data(#"{"width":\#(w),"height":\#(h),"duration":\#(duration)}"#.utf8))
    }

    func video(_ renditions: Renditions, trim: Trim = .whole) -> OutputSpec {
        guard case .video(var v) = OutputSpecTests.mp4 else { fatalError() }
        v.renditions = renditions
        v.trim = trim
        return .video(v)
    }

    func size(_ w: Int, _ h: Int) -> RenditionSize {
        RenditionSize(label: .bySize, width: w, height: h, fit: .contain, orientation: .auto, upscale: false, cbrBitrate: nil)
    }

    func testMinutesArePerRenditionByTier() throws {
        let spec = video(.sizes([size(1920, 1080), size(1280, 720), size(640, 360)]))
        let m = JobEstimate.minutes(spec, info: try info(1920, 1080, duration: 600))
        XCTAssertEqual(m.hd, 20)
        XCTAssertEqual(m.sd, 10)
        XCTAssertEqual(m.dominant, .hd)
        // 20 HD minutes at $0.01 and 10 SD at $0.005 is $0.25.
        XCTAssertEqual(JobEstimate.cost(m, rates: nil), 0.25, accuracy: 1e-9)
    }

    func testLadderFollowsTheSourceAndCap() {
        let ladder = video(.ladder(Ladder(maxShortSide: 1080, fit: .contain, upscale: false)))
        XCTAssertEqual(JobEstimate.plannedShortSides(ladder, sourceWidth: 3840, sourceHeight: 2160), [1080, 720, 480, 360, 240])
        XCTAssertEqual(JobEstimate.plannedShortSides(ladder, sourceWidth: 1280, sourceHeight: 720), [720, 480, 360, 240])
        let source = video(.sourceSize(SourceSize(label: .bySize, fit: .contain, upscale: false)))
        XCTAssertEqual(JobEstimate.plannedShortSides(source, sourceWidth: 1080, sourceHeight: 1920), [1080])
    }

    func testTrimShortensTheOutputAndASecondIsBilled() throws {
        let spec = video(.sizes([size(1920, 1080)]), trim: Trim(start: 10, end: .seconds(70)))
        XCTAssertEqual(JobEstimate.outputSeconds(spec, duration: 600), 60)
        XCTAssertEqual(JobEstimate.outputSeconds(video(.sizes([size(1920, 1080)]), trim: Trim(start: 30, end: .source)), duration: 20), 0)
        XCTAssertGreaterThan(JobEstimate.minutes(OutputSpecTests.mp4, info: try info(1280, 720, duration: 0)).total, 0)
    }

    func testCurlQuotesTheBody() {
        let curl = RequestSnippet.curl("POST", path: "/v1/jobs", body: ["url": "it's"], origin: "https://api.example.test")
        XCTAssertTrue(curl.hasPrefix("curl -X POST https://api.example.test/v1/jobs \\\n"))
        XCTAssertTrue(curl.contains(#"it'\''s"#))
        XCTAssertFalse(RequestSnippet.curl("GET", path: "/v1/me", body: nil, origin: "x").contains("-d"))
    }

    func testInputDisplayNames() {
        XCTAssertEqual(JobInput.url("https://cdn.example.com/a/talk.mov?x=1").displayName, "talk.mov")
        XCTAssertEqual(JobInput.url("https://cdn.example.com/").displayName, "cdn.example.com")
        XCTAssertEqual(JobInput.connection(id: "con_1", path: "incoming/2026/clip.mkv").displayName, "clip.mkv")
        XCTAssertEqual(JobInput.asset("ast_1").displayName, "ast_1")
    }

    func testPrefixPreview() {
        let p = PrefixTemplate.preview("out/{dir}/{stem}.{ext}/{job_id}/", sample: "incoming/2026/talk.mov")
        XCTAssertEqual(p, "out/incoming/2026/talk.mov/job_4QmZr8XkT2vLp9cN1bHs7a/")
        XCTAssertEqual(PrefixTemplate.preview("{stem}-{ext}", sample: "README"), "README-")
    }
}
