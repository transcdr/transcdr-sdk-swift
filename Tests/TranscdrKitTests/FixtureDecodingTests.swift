import XCTest
@testable import TranscdrKit

/// Every fixture is a real API response (scrubbed): the models must read all
/// of them, and read the fields the screens rely on correctly.
final class FixtureDecodingTests: XCTestCase {
    func testAccount() throws {
        let me = try decodeFixture("me", as: Me.self)
        XCTAssertFalse(me.organization.id.isEmpty)
        XCTAssertFalse(me.scopes.isEmpty)
        let org = try decodeFixture("organization", as: Organization.self)
        XCTAssertTrue(org.id.hasPrefix("org_"))
        let members = try decodeFixture("members", as: ListResponse<User>.self)
        XCTAssertFalse(members.data.isEmpty)
        let keys = try decodeFixture("api_keys", as: ListResponse<APIKey>.self)
        XCTAssertTrue(keys.data.allSatisfy { $0.secret == nil })
    }

    func testJobs() throws {
        let jobs = try decodeFixture("jobs", as: ListResponse<Job>.self)
        XCTAssertEqual(jobs.data.count, 10)
        XCTAssertTrue(jobs.data.allSatisfy { $0.id.hasPrefix("job_") })
        let job = try decodeFixture("job", as: Job.self)
        XCTAssertEqual(job.status, .completed)
        XCTAssertFalse(job.outputs.isEmpty)
        XCTAssertNotNil(job.completedAt)
        XCTAssertNotNil(job.output.codec)
        XCTAssertNotNil(job.billing)
        let events = try decodeFixture("job_events", as: ListResponse<JobEvent>.self)
        XCTAssertFalse(events.data.isEmpty)
    }

    func testMediaAndPresets() throws {
        let assets = try decodeFixture("assets", as: ListResponse<Asset>.self)
        XCTAssertEqual(assets.data.count, 5)
        let presets = try decodeFixture("presets", as: ListResponse<Preset>.self)
        XCTAssertTrue(presets.data.contains { $0.system })
        XCTAssertTrue(presets.data.allSatisfy { $0.output.codec != nil })
        let caps = try decodeFixture("capabilities", as: Capabilities.self)
        XCTAssertEqual(caps.codecs.map(\.id), ["av1", "h264", "h265"])
        XCTAssertEqual(caps.modes.map(\.id), ["single", "hls"])
        XCTAssertFalse(caps.systemPresets.isEmpty)
    }

    func testBilling() throws {
        let billing = try decodeFixture("billing", as: Billing.self)
        XCTAssertFalse(billing.period.isEmpty)
        let plans = try decodeFixture("plans", as: ListResponse<Plan>.self)
        XCTAssertEqual(plans.data.map(\.id), PlanID.all)
        let growth = try XCTUnwrap(plans.data.first { $0.id == .growth })
        XCTAssertEqual(growth.priceCents, 9900)
        XCTAssertEqual(growth.monthlyCreditCents, 20000)
        let usage = try decodeFixture("usage", as: Usage.self)
        XCTAssertFalse(usage.series.isEmpty)
        let transactions = try decodeFixture("transactions", as: ListResponse<CreditTransaction>.self)
        XCTAssertFalse(transactions.data.isEmpty)
        _ = try decodeFixture("statements", as: ListResponse<Statement>.self)
    }

    func testIntegrations() throws {
        let connections = try decodeFixture("connections", as: ListResponse<Connection>.self)
        let sqs = try XCTUnwrap(connections.data.first { $0.kind == .sqs })
        XCTAssertTrue(sqs.isMessaging)
        XCTAssertTrue(sqs.capabilities.trigger)
        XCTAssertNotNil(sqs.config.queueUrl)
        let s3 = try XCTUnwrap(connections.data.first { $0.kind == .s3 })
        XCTAssertFalse(s3.isMessaging)
        let automations = try decodeFixture("automations", as: ListResponse<Automation>.self)
        XCTAssertTrue(automations.data.contains { $0.trigger == .queue && $0.triggerConnectionId != nil })
        _ = try decodeFixture("automation_items", as: ListResponse<AutomationItem>.self)
        let webhooks = try decodeFixture("webhooks", as: ListResponse<WebhookEndpoint>.self)
        XCTAssertTrue(webhooks.data.contains { $0.connectionId != nil })
        XCTAssertTrue(webhooks.data.contains { $0.type == .https && $0.connectionId == nil })
        let events = try decodeFixture("events", as: ListResponse<Event>.self)
        XCTAssertTrue(events.data.allSatisfy { !$0.type.isEmpty })
    }

    func testService() throws {
        let status = try decodeFixture("status", as: ServiceStatus.self)
        XCTAssertFalse(status.status.isEmpty)
        let stats = try decodeFixture("stats", as: Stats.self)
        XCTAssertEqual(stats.daily.count, 30)
    }
}
