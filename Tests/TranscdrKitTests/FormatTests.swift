import XCTest
@testable import TranscdrKit

final class FormatTests: XCTestCase {
    func testBytes() {
        XCTAssertEqual(Format.bytes(512), "512 B")
        XCTAssertEqual(Format.bytes(1536), "1.5 KB")
        XCTAssertEqual(Format.bytes(15_493_121), "14.8 MB")
        XCTAssertEqual(Format.bytes(nil), "—")
    }

    func testClockAndDuration() {
        XCTAssertEqual(Format.clock(634.4), "10:34")
        XCTAssertEqual(Format.clock(634.5), "10:35", "rounds half up, as the web does")
        XCTAssertEqual(Format.clock(3725), "1:02:05")
        XCTAssertEqual(Format.duration(0.85), "850ms")
        XCTAssertEqual(Format.duration(42), "42s")
        XCTAssertEqual(Format.duration(192), "3m 12s")
        XCTAssertEqual(Format.duration(3840), "1h 4m")
    }

    func testMoney() {
        XCTAssertEqual(Format.cents(1234), "$12.34")
        XCTAssertEqual(Format.usd(0.0125, precise: true), "$0.0125")
        XCTAssertEqual(Format.usd(12.5), "$12.50")
        XCTAssertEqual(Format.usd(1234.5), "$1,234.50")
        XCTAssertEqual(Format.usd(-3), "-$3.00")
        XCTAssertEqual(Format.minutes(4.25), "4.25 min")
    }

    func testIdsAndPlurals() {
        XCTAssertEqual(Format.shortId("job_Zlwif1p7nBycseUQ"), "job_Zlwif1…")
        XCTAssertEqual(Format.pluralize(1, "job"), "1 job")
        XCTAssertEqual(Format.pluralize(3, "job"), "3 jobs")
    }

    func testTimeAgo() {
        let now = Date()
        XCTAssertEqual(Format.timeAgo(now.addingTimeInterval(-10), now: now), "just now")
        XCTAssertTrue(Format.timeAgo(now.addingTimeInterval(-300), now: now).contains("5"))
    }

    func testContentTypes() {
        XCTAssertEqual(MediaTypes.contentType(forFilename: "talk.MOV"), "video/quicktime")
        XCTAssertEqual(MediaTypes.contentType(forFilename: "x.unknown"), "application/octet-stream")
    }
}
