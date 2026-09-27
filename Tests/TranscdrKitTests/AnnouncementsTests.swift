import XCTest
@testable import TranscdrKit

final class AnnouncementsTests: XCTestCase {
    let changelog = """
    {"object":"announcement","id":"ann_1","kind":"changelog","title":"Automate a bucket",
     "body":"Markdown. **Bold**, _italics_, `code`, [links](/docs/integrations), and - lists.",
     "published_at":"2026-09-27T09:00:00Z","link":{"label":"Try it","url":"/app/integrations/automate"},
     "tags":["integrations"],"credit":null,"seen":false,"seen_at":null}
    """

    let credit = """
    {"object":"announcement","id":"ann_2","kind":"service_credit","title":"Dropped audio on some outputs",
     "body":"Some outputs had no audio track.\\n\\nWe credited 3× what those jobs cost.",
     "published_at":"2026-09-26T18:00:00Z","link":null,"tags":[],
     "credit":{"incident_id":"inc_1","amount_usd":0.2563,"multiplier":3,"jobs":["job_1","job_2"],"applied_at":"2026-09-26T18:00:00Z"},
     "seen":true,"seen_at":"2026-09-27T08:00:00.123456Z"}
    """

    func testDecodesAChangelogEntry() throws {
        let a = try TranscdrCoding.decoder.decode(Announcement.self, from: Data(changelog.utf8))
        XCTAssertEqual(a.id, "ann_1")
        XCTAssertEqual(a.kind, .changelog)
        XCTAssertFalse(a.isServiceCredit)
        XCTAssertEqual(a.title, "Automate a bucket")
        XCTAssertTrue(a.body.hasPrefix("Markdown."))
        XCTAssertEqual(a.publishedAt, TranscdrCoding.parseTimestamp("2026-09-27T09:00:00Z"))
        XCTAssertEqual(a.link, AnnouncementLink(label: "Try it", url: "/app/integrations/automate"))
        XCTAssertEqual(a.link?.isRelative, true)
        XCTAssertEqual(a.tags, ["integrations"])
        XCTAssertNil(a.credit)
        XCTAssertFalse(a.seen)
        XCTAssertNil(a.seenAt)
    }

    func testDecodesAServiceCredit() throws {
        let a = try TranscdrCoding.decoder.decode(Announcement.self, from: Data(credit.utf8))
        XCTAssertEqual(a.kind, .serviceCredit)
        XCTAssertTrue(a.isServiceCredit)
        XCTAssertNil(a.link)
        XCTAssertEqual(a.tags, [])
        let c = try XCTUnwrap(a.credit)
        XCTAssertEqual(c.incidentId, "inc_1")
        XCTAssertEqual(c.amountUsd, 0.2563, accuracy: 1e-9)
        XCTAssertEqual(c.multiplier, 3)
        XCTAssertEqual(c.jobs, ["job_1", "job_2"])
        XCTAssertNotNil(c.appliedAt)
        XCTAssertTrue(a.seen)
        XCTAssertNotNil(a.seenAt)
    }

    func testDecodesLeniently() throws {
        // A draft from the admin list, an unknown kind, and missing optional fields.
        let a = try TranscdrCoding.decoder.decode(Announcement.self, from: Data(#"{"id":"ann_3","kind":"maintenance","published_at":null}"#.utf8))
        XCTAssertEqual(a.kind.rawValue, "maintenance")
        XCTAssertTrue(a.isDraft)
        XCTAssertEqual(a.title, "")
        XCTAssertEqual(a.tags, [])
        XCTAssertNil(a.link)
        XCTAssertNil(a.credit)
        XCTAssertFalse(a.seen)
    }

    func testListsUnseen() async throws {
        let t = MockTransport([MockTransport.json(200, #"{"object":"list","data":[\#(credit),\#(changelog)],"has_more":false,"next_cursor":null}"#)])
        let list = try await client(t, key: "tds_session").announcements.list(unseen: true, limit: 50)
        XCTAssertEqual(list.data.map(\.id), ["ann_2", "ann_1"])
        let sent = try XCTUnwrap(t.sent.first)
        XCTAssertEqual(sent.method, "GET")
        XCTAssertEqual(sent.url.path, "/v1/announcements")
        let query = Dictionary(uniqueKeysWithValues: (URLComponents(url: sent.url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value) })
        XCTAssertEqual(query["unseen"], "true")
        XCTAssertEqual(query["limit"], "50")
        XCTAssertNil(query["kind"])
    }

    func testListsByKindWithoutUnseen() async throws {
        let t = MockTransport([MockTransport.json(200, #"{"object":"list","data":[],"has_more":false}"#)])
        _ = try await client(t).announcements.list(kind: .serviceCredit)
        XCTAssertEqual(t.sent.first?.url.absoluteString, "https://api.example.test/v1/announcements?kind=service_credit")
    }

    func testMarksSeen() async throws {
        let t = MockTransport([MockTransport.json(204, ""), MockTransport.json(204, "")])
        let c = client(t, key: "tds_session")
        try await c.announcements.markSeen(["ann_1", "ann_2"])
        try await c.announcements.markAllSeen()
        try await c.announcements.markSeen([])
        XCTAssertEqual(t.sent.count, 2, "nothing is sent for no ids")
        XCTAssertEqual(t.sent[0].method, "POST")
        XCTAssertEqual(t.sent[0].url.path, "/v1/announcements/seen")
        XCTAssertEqual(t.sent[0].json, ["ids": ["ann_1", "ann_2"]])
        XCTAssertEqual(t.sent[1].url.path, "/v1/announcements/seen")
        XCTAssertEqual(t.sent[1].json, ["all": true])
    }

    func testPublicChangelog() async throws {
        let t = MockTransport([MockTransport.json(200, #"{"object":"list","data":[\#(changelog)],"has_more":true,"next_cursor":"ann_1"}"#)])
        let page = try await client(t, key: nil).announcements.changelog(.init(limit: 10, cursor: "ann_9"))
        XCTAssertEqual(page.data.count, 1)
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.nextCursor, "ann_1")
        XCTAssertEqual(t.sent.first?.url.absoluteString, "https://api.example.test/v1/changelog?limit=10&cursor=ann_9")
        XCTAssertNil(t.sent.first?.header("Authorization"))
    }

    func testAdminCreatesAndPublishes() async throws {
        let t = MockTransport([MockTransport.json(201, changelog), MockTransport.json(201, changelog)])
        let c = client(t, key: "tds_operator")
        _ = try await c.admin.createAnnouncement(.init(
            title: "Automate a bucket", body: "**New.**",
            link: .some(AnnouncementLink(label: "Try it", url: "/app/integrations/automate")), tags: ["integrations"]
        ))
        let sent = t.sent[0]
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.url.path, "/v1/admin/announcements")
        XCTAssertEqual(sent.json, [
            "title": "Automate a bucket", "body": "**New.**",
            "link": ["label": "Try it", "url": "/app/integrations/automate"], "tags": ["integrations"],
        ], "published_at is left out: the server publishes now")

        _ = try await c.admin.createAnnouncement(.init(title: "Draft", body: "", publishedAt: .some(nil)))
        XCTAssertEqual(t.sent[1].json, ["title": "Draft", "body": "", "published_at": nil], "null saves a draft")
    }

    func testAdminUpdatesListsAndDeletes() async throws {
        let t = MockTransport([
            MockTransport.json(200, changelog),
            MockTransport.json(200, #"{"object":"list","data":[\#(changelog)],"has_more":false}"#),
            MockTransport.json(204, ""),
        ])
        let c = client(t, key: "tds_operator")
        let when = try XCTUnwrap(TranscdrCoding.parseTimestamp("2026-09-28T09:00:00Z"))
        _ = try await c.admin.updateAnnouncement("ann_1", .init(link: .some(nil), publishedAt: .some(when)))
        XCTAssertEqual(t.sent[0].method, "PATCH")
        XCTAssertEqual(t.sent[0].url.path, "/v1/admin/announcements/ann_1")
        XCTAssertEqual(t.sent[0].json, ["link": nil, "published_at": "2026-09-28T09:00:00Z"], "only what changed is sent")

        let all = try await c.admin.announcements(.init(limit: 100))
        XCTAssertEqual(all.data.first?.id, "ann_1")
        XCTAssertEqual(t.sent[1].url.absoluteString, "https://api.example.test/v1/admin/announcements?limit=100")

        try await c.admin.deleteAnnouncement("ann_1")
        XCTAssertEqual(t.sent[2].method, "DELETE")
        XCTAssertEqual(t.sent[2].url.path, "/v1/admin/announcements/ann_1")
    }
}
