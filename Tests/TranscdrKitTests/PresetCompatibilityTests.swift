import XCTest
@testable import TranscdrKit

/// A preset's category and where its output plays.
final class PresetCompatibilityTests: XCTestCase {
    let preset = #"""
    {"object":"preset","id":"web-av1-1080p","slug":"web-av1-1080p","name":"Web AV1 1080p","system":true,
     "category":"web","compatibility":["web","android","smart_tv","vr_headset"],
     "compatibility_notes":{"web":"Chrome 70+","android":"Android 10+","smart_tv":"TVs with AV1 decode"},
     "output":\#(specJSON)}
    """#

    func testCategoryCompatibilityAndNotesDecode() throws {
        let p = try TranscdrCoding.decoder.decode(Preset.self, from: Data(preset.utf8))
        XCTAssertEqual(p.category, .web)
        XCTAssertEqual(p.compatibility, [.web, .android, .smartTV, "vr_headset"], "unknown platforms decode")
        XCTAssertEqual(p.note(for: .smartTV), "TVs with AV1 decode")
        XCTAssertNil(p.note(for: .ios))
    }

    func testAnOlderServerDecodesWithoutThem() throws {
        let p = try TranscdrCoding.decoder.decode(Preset.self, from: Data(#"{"id":"pre_1","output":\#(specJSON)}"#.utf8))
        XCTAssertNil(p.category)
        XCTAssertEqual(p.compatibility, [])
        XCTAssertEqual(p.compatibilityNotes, [:])
    }

    func testListSendsTheFilters() async throws {
        let t = MockTransport([MockTransport.json(200, #"{"object":"list","data":[\#(preset)],"has_more":false}"#)])
        let page = try await client(t).presets.list(category: [.web, .social], compatibleWith: [.ios, .smartTV])
        XCTAssertEqual(page.data.first?.category, .web)
        let query = Dictionary(uniqueKeysWithValues: (URLComponents(url: t.sent[0].url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(query["category"], "web,social")
        XCTAssertEqual(query["compatible_with"], "ios,smart_tv")
    }

    func testAnUnfilteredListSendsNoFilters() async throws {
        let t = MockTransport([MockTransport.json(200, #"{"object":"list","data":[],"has_more":false}"#)])
        _ = try await client(t).presets.list()
        XCTAssertNil(t.sent[0].url.query)
    }

    func testCreateSetsAndUpdateClearsBackToDerived() async throws {
        let t = MockTransport(Array(repeating: MockTransport.json(200, preset), count: 3))
        let c = client(t)
        _ = try await c.presets.create(.init(
            name: "Phones", output: sampleSpec, category: .mobile,
            compatibility: [.ios, .android], compatibilityNotes: ["ios": "Our app only."]
        ))
        XCTAssertEqual(t.sent[0].json?["category"], "mobile")
        XCTAssertEqual(t.sent[0].json?["compatibility"], ["ios", "android"])
        XCTAssertEqual(t.sent[0].json?["compatibility_notes"], ["ios": "Our app only."])

        _ = try await c.presets.update("pre_1", .init(clear: [.category, .compatibility, .compatibilityNotes]))
        XCTAssertEqual(t.sent[1].json, ["category": nil, "compatibility": nil, "compatibility_notes": nil])

        _ = try await c.presets.replace("pre_1", .init(name: "Phones", output: sampleSpec, category: .tv))
        XCTAssertEqual(t.sent[2].json, ["name": "Phones", "output": try JSONValue.from(sampleSpec), "category": "tv"])
    }
}
