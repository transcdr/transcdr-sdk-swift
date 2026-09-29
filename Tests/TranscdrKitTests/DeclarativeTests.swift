import XCTest
@testable import TranscdrKit

/// Idempotent creates, preset replace, clearing with null, API key lookup,
/// secret fingerprints and telling a session from an API key.
final class DeclarativeTests: XCTestCase {
    let preset = #"{"object":"preset","id":"pre_1","slug":"mine","name":"Mine","output":\#(specJSON)}"#
    let fingerprint = #"{"set":true,"fingerprint":"hmac-sha256:3f9a0c1b2d4e"}"#

    func testEveryCreateSendsAnIdempotencyKey() async throws {
        let created = #"{"id":"x_1","object":"x","token":"tds_x","user":{"id":"usr_1","name":"A","email":"a@b.c","role":"owner"},"organization":{"id":"org_1","name":"A","slug":"a","plan":"free"},"organizations":[]}"#
        let t = MockTransport(Array(repeating: MockTransport.json(201, created), count: 8))
        let c = client(t)
        _ = try? await c.assets.create(.init(url: "https://example.com/a.mp4"))
        _ = try? await c.presets.create(.init(name: "Mine", output: sampleSpec))
        _ = try? await c.webhooks.create(.https(url: "https://example.com/hook"))
        _ = try? await c.connections.create(.init(name: "c", kind: .s3, config: .init(bucket: "b")))
        _ = try? await c.automations.create(.init(name: "a", source: .init(connectionId: "con_1")))
        _ = try? await c.apiKeys.create(.init(name: "CI"))
        _ = try? await c.organization.members.create(.init(email: "a@b.c", role: .member))
        _ = try? await c.organizations.create(name: "Acme")
        XCTAssertEqual(t.sent.map(\.url.path), [
            "/v1/assets", "/v1/presets", "/v1/webhooks", "/v1/connections", "/v1/automations",
            "/v1/api-keys", "/v1/organization/members", "/v1/organizations",
        ])
        for sent in t.sent {
            XCTAssertEqual(sent.method, "POST")
            XCTAssertGreaterThanOrEqual(sent.header("Idempotency-Key")?.count ?? 0, 16, sent.url.path)
        }
    }

    func testCreateIsRetriedWithTheSameKey() async throws {
        let t = MockTransport([
            MockTransport.json(503, #"{"error":{"type":"api_error","message":"down"}}"#),
            .failure(URLError(.networkConnectionLost)),
            MockTransport.json(201, preset, headers: ["Idempotent-Replayed": "true"]),
        ])
        let p = try await client(t).presets.create(.init(name: "Mine", output: sampleSpec), idempotencyKey: "preset-mine")
        XCTAssertEqual(p.id, "pre_1")
        XCTAssertEqual(t.sent.count, 3)
        XCTAssertEqual(Set(t.sent.compactMap { $0.header("Idempotency-Key") }), ["preset-mine"])
    }

    func testKeyReusedIsNotRetried() async throws {
        let t = MockTransport([MockTransport.json(409, #"{"error":{"type":"invalid_request_error","code":"idempotency_key_reused","message":"x"}}"#)])
        do {
            _ = try await client(t).webhooks.create(.https(url: "https://example.com/hook"))
            XCTFail("expected an error")
        } catch let e as TranscdrError {
            XCTAssertEqual(e.code, "idempotency_key_reused")
        }
        XCTAssertEqual(t.sent.count, 1)
    }

    func testPresetReplaceIsPut() async throws {
        let t = MockTransport([MockTransport.json(200, preset)])
        _ = try await client(t).presets.replace("pre_1", .init(name: "Mine", output: sampleSpec))
        XCTAssertEqual(t.sent[0].method, "PUT")
        XCTAssertEqual(t.sent[0].url.path, "/v1/presets/pre_1")
        XCTAssertEqual(t.sent[0].json, ["name": "Mine", "output": try JSONValue.from(sampleSpec)])
        XCTAssertNil(t.sent[0].header("Idempotency-Key"))
    }

    func testClearsAreSentAsNull() throws {
        let presetPatch = try JSONValue.from(PresetParams(name: "x", clear: [.description, .metadata]))
        XCTAssertEqual(presetPatch, ["name": "x", "description": nil, "metadata": nil])
        XCTAssertEqual(try JSONValue.from(PresetParams(description: "kept", clear: [.description])), ["description": "kept"], "a value that is set wins")

        let automation = try JSONValue.from(AutomationParams(clear: Set(AutomationParams.Field.allCases)))
        XCTAssertEqual(automation, [
            "destination": nil, "preset": nil, "output": nil, "metadata": nil,
            "webhook_url": nil, "trigger_connection_id": nil,
        ])
        XCTAssertEqual(try JSONValue.from(AutomationParams(name: "a")), ["name": "a"], "nothing is cleared by default")

        let webhook = try JSONValue.from(WebhookUpdateParams(clear: [.description, .awsEndpoint, .awsMessageGroupId]))
        XCTAssertEqual(webhook, ["description": nil, "aws": ["endpoint": nil, "message_group_id": nil]])
        let keepKey = try JSONValue.from(WebhookUpdateParams(aws: .init(accessKeyId: "AKIA"), clear: [.awsEndpoint]))
        XCTAssertEqual(keepKey, ["aws": ["access_key_id": "AKIA", "endpoint": nil]])

        let connection = try JSONValue.from(ConnectionUpdateParams(config: .init(bucket: "b"), clearConfig: ["endpoint"], clearSecrets: ["session_token"]))
        XCTAssertEqual(connection["config"], ["bucket": "b", "endpoint": nil])
        XCTAssertEqual(connection["secrets"], ["session_token": nil])
        XCTAssertEqual(try JSONValue.from(ConnectionUpdateParams(enabled: true)), ["enabled": true])

        XCTAssertEqual(try JSONValue.from(OrganizationUpdateParams(clear: [.billingEmail])), ["billing_email": nil])
        XCTAssertEqual(try JSONValue.from(OrganizationUpdateParams(name: "Acme")), ["name": "Acme"])
    }

    func testAPIKeyRetrieve() async throws {
        let t = MockTransport([
            MockTransport.json(200, #"{"object":"api_key","id":"key_1","name":"CI","prefix":"tdk_live_ab12","scopes":["*"],"mode":"live","revoked_at":null,"created_at":"2026-09-27T05:18:43Z"}"#),
            MockTransport.json(404, #"{"error":{"type":"invalid_request_error","code":"not_found","message":"No such key."}}"#),
        ])
        let c = client(t)
        let key = try await c.apiKeys.retrieve("key_1")
        XCTAssertEqual(t.sent[0].method, "GET")
        XCTAssertEqual(t.sent[0].url.path, "/v1/api-keys/key_1")
        XCTAssertNil(key.revokedAt)
        do {
            _ = try await c.apiKeys.retrieve("key_1")
            XCTFail("expected a 404")
        } catch let e as TranscdrError {
            XCTAssertEqual(e.status, 404)
        }
    }

    func testSecretFingerprints() throws {
        let connection = try TranscdrCoding.decoder.decode(Connection.self, from: Data("""
        {"object":"connection","id":"con_1","name":"c","kind":"s3","config":{"kind":"s3","bucket":"b"},
         "secrets_set":["access_key_id"],"secrets":{"access_key_id":\(fingerprint)}}
        """.utf8))
        XCTAssertEqual(connection.secrets["access_key_id"]?.fingerprint, "hmac-sha256:3f9a0c1b2d4e")
        let webhook = try TranscdrCoding.decoder.decode(WebhookEndpoint.self, from: Data("""
        {"object":"webhook_endpoint","id":"whk_1","url":"https://example.com/hook","created_at":"2026-09-27T05:18:43Z",
         "secrets":{"secret":\(fingerprint)}}
        """.utf8))
        XCTAssertEqual(webhook.secrets["secret"]?.set, true)
        XCTAssertNil(webhook.secrets["secret_access_key"])
        let older = try TranscdrCoding.decoder.decode(WebhookEndpoint.self, from: Data(#"{"id":"whk_1","created_at":"2026-09-27T05:18:43Z"}"#.utf8))
        XCTAssertEqual(older.secrets, [:])
    }

    func testAPIKeyMeIsNotASession() throws {
        // GET /v1/me with an API key reports the key's creator as the user.
        let me = try decodeFixture("me", as: Me.self)
        XCTAssertNotNil(me.user)
        XCTAssertFalse(me.isSession)
        XCTAssertTrue(me.isManager, "an API key with * holds org:write")

        let session = try TranscdrCoding.decoder.decode(Me.self, from: Data("""
        {"object":"me","user":{"id":"usr_1","name":"Ada","email":"a@b.c","role":"member"},
         "organization":{"id":"org_a","name":"Acme","slug":"acme","plan":"starter"},
         "organizations":[{"object":"membership","organization":{"id":"org_a","name":"Acme","slug":"acme","plan":"starter"},"role":"member","created_at":"2026-09-01T10:00:00Z"}],
         "api_key":{"id":"key_s","name":"session","prefix":"tds_ab12","scopes":["*"],"mode":"live","created_at":"2026-09-27T05:18:43Z"},
         "scopes":["*"]}
        """.utf8))
        XCTAssertTrue(session.isSession)
        XCTAssertFalse(session.isManager, "a session uses the user's role")
    }
}
