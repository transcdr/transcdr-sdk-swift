import XCTest
@testable import TranscdrKit

final class SpecToolsFitTests: XCTestCase {
    func testFitAndUpscaleEncodeOnlyWhenSetAndRoundTrip() throws {
        let r = Rendition(width: 1080, height: 1920, fit: .cover, orientation: .fixed, upscale: false)
        XCTAssertEqual(
            try JSONValue.from(r),
            ["width": 1080, "height": 1920, "fit": "cover", "orientation": "fixed", "upscale": false]
        )
        XCTAssertEqual(try JSONValue.from(Rendition(width: 1280, height: 720)), ["width": 1280, "height": 720])
        XCTAssertEqual(try JSONDecoder().decode(Rendition.self, from: JSONEncoder().encode(r)), r)

        let spec = OutputSpec(renditions: [r], fit: .pad, upscale: true)
        let json = try JSONValue.from(spec).objectValue ?? [:]
        XCTAssertEqual(json["fit"], "pad")
        XCTAssertEqual(json["upscale"], true)
        XCTAssertEqual(try JSONDecoder().decode(OutputSpec.self, from: JSONEncoder().encode(spec)), spec)
        XCTAssertFalse(spec.isEmpty)
        XCTAssertTrue(OutputSpec().isEmpty)
    }

    func testDefaultsDiffAndDescribe() throws {
        let resolved = SpecTools.resolved(OutputSpec(renditions: [Rendition(width: 1920, height: 1080)]))
        XCTAssertEqual(resolved.fit, .contain)
        XCTAssertEqual(resolved.upscale, false)
        // The defaults are not an override; a change is, and a rendition keeps its own fitting.
        XCTAssertEqual(SpecTools.diff(SpecTools.defaultSpec).json, .object([:]))
        var changed = resolved
        changed.fit = .cover
        changed.renditions = [Rendition(width: 1080, height: 1920, fit: .cover, orientation: .fixed)]
        let patch = SpecTools.diff(changed).json.objectValue ?? [:]
        XCTAssertEqual(patch["fit"], "cover")
        XCTAssertNil(patch["upscale"])
        XCTAssertEqual(
            patch["renditions"],
            [["width": 1080, "height": 1920, "fit": "cover", "orientation": "fixed"]]
        )
        XCTAssertTrue(SpecTools.describe(changed).contains("cover"))
        XCTAssertEqual(Fit.all.map(\.rawValue), ["contain", "cover", "pad", "stretch"])
        XCTAssertEqual(Orientation.all.map(\.rawValue), ["auto", "fixed"])
    }

    func testDisplaySizeDecodes() throws {
        let info = try JSONDecoder().decode(
            MediaInfo.self, from: Data(#"{"width":720,"height":576,"display_width":1024,"display_height":576}"#.utf8)
        )
        XCTAssertEqual(info.displayWidth, 1024)
        XCTAssertEqual(info.displayHeight, 576)
        let square = try JSONDecoder().decode(MediaInfo.self, from: Data(#"{"width":1920,"height":1080}"#.utf8))
        XCTAssertNil(square.displayWidth)
    }
}
