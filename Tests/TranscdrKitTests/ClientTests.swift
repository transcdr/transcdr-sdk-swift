import XCTest
@testable import TranscdrKit

final class ClientTests: XCTestCase {
    let job = """
    {"object":"job","id":"job_1","status":"queued","input":{"type":"url","url":"https://x/y.mov"},"output":{},"priority":"normal",
     "progress":{"percent":0,"stage":"waiting","renditions":[]},"outputs":[],"metadata":{"customer_id":"c1"},"attempts":0,
     "max_attempts":3,"created_at":"2026-09-27T05:18:43.011992Z"}
    """

    func testAuthorizesAndSendsIdempotentJobCreation() async throws {
        let t = MockTransport([MockTransport.json(201, job)])
        let created = try await client(t).jobs.create(.init(input: .asset("ast_1"), preset: "hls-av1-abr", metadata: ["customer_id": "c1"]))
        XCTAssertEqual(created.metadata["customer_id"], "c1", "metadata keys are never rewritten")
        let sent = try XCTUnwrap(t.sent.first)
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.url.absoluteString, "https://api.example.test/v1/jobs")
        XCTAssertEqual(sent.header("Authorization"), "Bearer tdk_test_key")
        XCTAssertNotNil(sent.header("Idempotency-Key"))
        XCTAssertEqual(sent.json?["input"], ["type": "asset", "asset_id": "ast_1"])
        XCTAssertEqual(sent.json?["preset"], "hls-av1-abr")
        XCTAssertNil(sent.json?["output"], "an empty override is not sent")
    }

    func testRetriesServerErrorsOnlyWhenSafe() async throws {
        let t = MockTransport([MockTransport.json(503, "{}"), MockTransport.json(200, job)])
        _ = try await client(t).jobs.retrieve("job_1")
        XCTAssertEqual(t.sent.count, 2, "a GET is retried")

        let post = MockTransport([MockTransport.json(503, #"{"error":{"type":"api_error","message":"down"}}"#), MockTransport.json(200, job)])
        do {
            _ = try await client(post).jobs.cancel("job_1")
            XCTFail("expected an error")
        } catch let e as TranscdrError {
            XCTAssertEqual(e.kind, .api)
            XCTAssertEqual(e.message, "down")
        }
        XCTAssertEqual(post.sent.count, 1, "a POST without an idempotency key is not retried")
    }

    func testValidationErrorsCarryFieldDetails() async throws {
        let body = #"{"error":{"type":"invalid_request_error","code":"validation_failed","message":"Width must be even.","param":"output.renditions.0.width","details":{"output.renditions.0.width":["Width must be even."]},"request_id":"req_9"}}"#
        let t = MockTransport([MockTransport.json(422, body)])
        do {
            _ = try await client(t).presets.create(.init(name: "x"))
            XCTFail("expected an error")
        } catch let e as TranscdrError {
            XCTAssertEqual(e.kind, .invalidRequest)
            XCTAssertEqual(e.status, 422)
            XCTAssertEqual(e.code, "validation_failed")
            XCTAssertEqual(e.requestId, "req_9")
            XCTAssertEqual(e.fieldErrors["output.renditions.0.width"], "Width must be even.")
        }
    }

    func testQuotaErrorIsTyped() async throws {
        let t = MockTransport([MockTransport.json(402, #"{"error":{"type":"quota_error","code":"insufficient_credit","message":"Add credit."}}"#)])
        do {
            _ = try await client(t).jobs.create(.init(input: .url("https://x/y.mov")))
            XCTFail("expected an error")
        } catch let e as TranscdrError {
            XCTAssertEqual(e.kind, .quota)
            XCTAssertEqual(e.code, "insufficient_credit")
        }
    }

    func testUnauthorizedCallsTheHandler() async throws {
        let t = MockTransport([MockTransport.json(401, #"{"error":{"type":"authentication_error","message":"Expired."}}"#)])
        let c = client(t)
        let flag = Flag()
        c.onUnauthorized = { flag.set() }
        _ = try? await c.auth.me()
        XCTAssertTrue(flag.value)

        let login = MockTransport([MockTransport.json(401, #"{"error":{"type":"authentication_error","message":"Wrong password."}}"#)])
        let c2 = client(login)
        let flag2 = Flag()
        c2.onUnauthorized = { flag2.set() }
        _ = try? await c2.auth.login(.init(email: "a@b.c", password: "x"))
        XCTAssertFalse(flag2.value, "a failed login is not an expired session")
    }

    func testQueryEncoding() async throws {
        let t = MockTransport([MockTransport.json(200, #"{"object":"list","data":[],"has_more":false,"next_cursor":null}"#)])
        _ = try await client(t).jobs.list(.init(limit: 5, status: .failed, metadata: ["tag": "a+b"]))
        let url = try XCTUnwrap(t.sent.first?.url.absoluteString)
        XCTAssertTrue(url.contains("limit=5"))
        XCTAssertTrue(url.contains("status=failed"))
        XCTAssertTrue(url.contains("metadata%5Btag%5D=a%2Bb") || url.contains("metadata[tag]=a%2Bb"), url)
    }

    func testPaginatorWalksEveryPage() async throws {
        let t = MockTransport([
            MockTransport.json(200, #"{"data":[\#(job)],"has_more":true,"next_cursor":"c2"}"#),
            MockTransport.json(200, #"{"data":[\#(job.replacingOccurrences(of: "job_1", with: "job_2"))],"has_more":false,"next_cursor":null}"#),
        ])
        let all = try await client(t).jobs.all().collect()
        XCTAssertEqual(all.map(\.id), ["job_1", "job_2"])
        XCTAssertTrue(t.sent[1].url.absoluteString.contains("cursor=c2"))
    }

    func testBareArrayCollections() async throws {
        let t = MockTransport([MockTransport.json(200, #"[{"path":"in/a.mov","size":10,"last_modified":null,"object":"remote_object"}]"#)])
        let objects = try await client(t).connections.browse("con_1", prefix: "in/")
        XCTAssertEqual(objects.first?.path, "in/a.mov")
    }

    func testExplicitNullsClearValues() throws {
        var spec = OutputSpec(codec: .av1)
        spec.clear = [.ladder, .trim]
        let json = try JSONValue.from(spec)
        XCTAssertEqual(json["codec"], "av1")
        XCTAssertEqual(json["ladder"], .null)
        XCTAssertEqual(json["trim"], .null)
        XCTAssertNil(json["gop"], "unset fields are left out")

        let settings = try JSONValue.from(BillingSettingsParams(monthlyLimitCents: .some(nil)))
        XCTAssertEqual(settings["monthly_limit_cents"], .null)
        XCTAssertNil(try JSONValue.from(BillingSettingsParams())["monthly_limit_cents"])

        let automation = try JSONValue.from(AutomationParams(destination: .some(nil)))
        XCTAssertEqual(automation["destination"], .null)
    }

    func testWebhookCreateShapes() throws {
        let viaConnection = try JSONValue.from(WebhookCreateParams.connection(id: "con_1", events: ["*"]))
        XCTAssertEqual(viaConnection, ["connection_id": "con_1", "events": ["*"]])
        let sqs = try JSONValue.from(WebhookCreateParams.sqs(queueUrl: "https://sqs.us-east-1.amazonaws.com/1/q", aws: .init(accessKeyId: "AKIA", secretAccessKey: "s")))
        XCTAssertEqual(sqs["type"], "sqs")
        XCTAssertEqual(sqs["aws"]?["access_key_id"], "AKIA")
    }

    func testTimestampsWithMicroseconds() {
        XCTAssertNotNil(TranscdrCoding.parseTimestamp("2026-09-27T05:18:43.011992Z"))
        XCTAssertNotNil(TranscdrCoding.parseTimestamp("2026-09-27T05:18:43Z"))
        XCTAssertNotNil(TranscdrCoding.parseTimestamp("2026-09-27 05:18:43.011992+00"))
        XCTAssertNotNil(TranscdrCoding.parseTimestamp("2026-09-27"))
    }

    func testUnknownEnumValuesDecode() throws {
        let data = Data(job.replacingOccurrences(of: "\"queued\"", with: "\"paused_for_review\"").utf8)
        let decoded = try TranscdrCoding.decoder.decode(Job.self, from: data)
        XCTAssertEqual(decoded.status.rawValue, "paused_for_review")
        XCTAssertFalse(decoded.status.isTerminal)
    }
}

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool { lock.withLock { _value } }
    func set() { lock.withLock { _value = true } }
}
