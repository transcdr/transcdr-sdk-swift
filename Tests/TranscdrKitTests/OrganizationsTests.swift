import XCTest
@testable import TranscdrKit

final class OrganizationsTests: XCTestCase {
    let memberships = """
    [{"object":"membership","organization":{"id":"org_a","name":"Acme","slug":"acme","plan":"starter"},"role":"owner","created_at":"2026-09-01T10:00:00Z"},
     {"object":"membership","organization":{"id":"org_b","name":"Beta","slug":"beta","plan":"free"},"role":"member","created_at":"2026-09-20T10:00:00Z"}]
    """

    func session(_ token: String, org: String, role: String) -> String {
        """
        {"token":"\(token)",
         "user":{"object":"user","id":"usr_1","name":"Ada","email":"ada@acme.com","role":"\(role)","organization_id":"\(org)","created_at":"2026-09-01T10:00:00Z"},
         "organization":{"object":"organization","id":"\(org)","name":"Beta","slug":"beta","plan":"free","billing_email":null,"created_at":"2026-09-20T10:00:00Z"},
         "organizations":\(memberships)}
        """
    }

    func testLoginChoosesAnOrganizationAndListsMemberships() async throws {
        let t = MockTransport([MockTransport.json(200, session("tds_new", org: "org_b", role: "member"))])
        let s = try await client(t, key: nil).auth.login(.init(email: "ada@acme.com", password: "pw"), organizationId: "org_b")
        XCTAssertEqual(t.sent.first?.json?["organization_id"], "org_b")
        XCTAssertEqual(s.token, "tds_new")
        XCTAssertEqual(s.user.role, .member)
        XCTAssertEqual(s.organizations.map(\.id), ["org_a", "org_b"])
        XCTAssertEqual(s.organizations.first?.role, .owner)
        XCTAssertEqual(s.organizations.first?.organization.plan, .starter)
        XCTAssertNotNil(s.organizations.first?.createdAt)

        let plain = MockTransport([MockTransport.json(200, session("tds_x", org: "org_a", role: "owner"))])
        _ = try await client(plain, key: nil).auth.login(.init(email: "ada@acme.com", password: "pw"))
        XCTAssertNil(plain.sent.first?.json?["organization_id"], "no organization is sent unless chosen")
    }

    func testSwitchSendsTheOrganizationAndAdoptsTheNewToken() async throws {
        let t = MockTransport([MockTransport.json(200, session("tds_b", org: "org_b", role: "member"))])
        let c = client(t, key: "tds_a")
        let s = try await c.auth.switch(to: "org_b")
        let sent = try XCTUnwrap(t.sent.first)
        XCTAssertEqual(sent.method, "POST")
        XCTAssertEqual(sent.url.path, "/v1/auth/switch")
        XCTAssertEqual(sent.header("Authorization"), "Bearer tds_a")
        XCTAssertEqual(sent.json?["organization_id"], "org_b")
        XCTAssertEqual(s.organization.id, "org_b")
        XCTAssertEqual(c.apiKey, "tds_b", "the old token is revoked")
    }

    func testSwitchWithAKeyIsRefused() async throws {
        let t = MockTransport([MockTransport.json(403, #"{"error":{"type":"permission_error","code":"session_required","message":"Sign in to switch organizations."}}"#)])
        let c = client(t)
        do {
            _ = try await c.auth.switch(to: "org_b")
            XCTFail("expected an error")
        } catch let e as TranscdrError {
            XCTAssertEqual(e.status, 403)
            XCTAssertEqual(e.code, "session_required")
        }
        XCTAssertEqual(c.apiKey, "tdk_test_key")
    }

    func testListAndCreateOrganizations() async throws {
        let t = MockTransport([
            MockTransport.json(200, #"{"object":"list","data":"# + memberships + #","has_more":false}"#),
            MockTransport.json(201, session("tds_c", org: "org_c", role: "owner")),
        ])
        let c = client(t, key: "tds_a")
        let list = try await c.organizations.list()
        XCTAssertEqual(list.map(\.organization.name), ["Acme", "Beta"])
        XCTAssertEqual(t.sent[0].url.path, "/v1/organizations")

        let s = try await c.organizations.create(name: "Gamma")
        XCTAssertEqual(t.sent[1].method, "POST")
        XCTAssertEqual(t.sent[1].url.path, "/v1/organizations")
        XCTAssertEqual(t.sent[1].json, ["name": "Gamma"])
        XCTAssertEqual(s.user.role, .owner)
        XCTAssertEqual(c.apiKey, "tds_c")
    }

    func testMembershipsDecodeLeniently() throws {
        let me = try decodeFixture("me", as: Me.self)
        XCTAssertEqual(me.organizations, [], "an API key, or an older response without organizations")
        XCTAssertFalse(me.isSession)

        let json = """
        {"object":"me","user":{"object":"user","id":"usr_1","name":"Ada","email":"a@b.c","role":"admin","organization_id":"org_a"},
         "organization":{"object":"organization","id":"org_a","name":"Acme","slug":"acme","plan":"starter"},
         "organizations":[{"object":"membership","organization":{"id":"org_a","name":"Acme","slug":"acme","plan":"starter"},"role":"admin","created_at":"2026-09-01T10:00:00Z"},
                          {"object":"membership","role":"owner"}],
         "api_key":null,"scopes":["*"],"livemode":true}
        """
        let decoded = try TranscdrCoding.decoder.decode(Me.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.organizations.map(\.id), ["org_a"], "an unreadable membership is skipped")
        XCTAssertTrue(decoded.isSession)
        XCTAssertEqual(decoded.role, .admin)
        XCTAssertFalse(decoded.isOwner)

        let nullList = try TranscdrCoding.decoder.decode(AuthResponse.self, from: Data("""
        {"token":"tds_1","user":{"id":"usr_1","name":"Ada","email":"a@b.c","role":"owner"},
         "organization":{"id":"org_a","name":"Acme","slug":"acme","plan":"free"},"organizations":null}
        """.utf8))
        XCTAssertEqual(nullList.organizations, [])
    }

    func testAddingAnExistingUserSendsOnlyEmailAndRole() async throws {
        let user = #"{"object":"user","id":"usr_2","name":"Bo","email":"bo@x.com","role":"admin","organization_id":"org_a"}"#
        let t = MockTransport([MockTransport.json(201, user), MockTransport.json(201, user)])
        let c = client(t)
        _ = try await c.organization.members.create(.init(email: "bo@x.com", role: .admin))
        XCTAssertEqual(t.sent[0].json, ["email": "bo@x.com", "role": "admin"])
        _ = try await c.organization.members.create(.init(name: "Bo", email: "bo@x.com", role: .member, password: "longpassword"))
        XCTAssertEqual(t.sent[1].json, ["name": "Bo", "email": "bo@x.com", "role": "member", "password": "longpassword"])
    }

    func testLastOwnerAndRoleErrorsAreTyped() async throws {
        let t = MockTransport([
            MockTransport.json(409, #"{"error":{"type":"invalid_request_error","code":"last_owner","message":"An organization needs an owner."}}"#),
            MockTransport.json(403, #"{"error":{"type":"permission_error","code":"role_required","message":"Only owners can change owners."}}"#),
        ])
        let c = client(t)
        do {
            try await c.organization.members.remove("usr_1")
            XCTFail("expected an error")
        } catch let e as TranscdrError {
            XCTAssertEqual(e.status, 409)
            XCTAssertEqual(e.code, "last_owner")
        }
        do {
            _ = try await c.organization.members.update("usr_2", role: .owner)
            XCTFail("expected an error")
        } catch let e as TranscdrError {
            XCTAssertEqual(e.status, 403)
            XCTAssertEqual(e.code, "role_required")
        }
        XCTAssertEqual(t.sent[1].json, ["role": "owner"])
    }
}
