import XCTest
@testable import TranscdrKit

final class AccountToolsTests: XCTestCase {
    func testMoneyHelpers() {
        XCTAssertEqual(Format.wholeCents(5000), "$50")
        XCTAssertEqual(Format.wholeCents(4950), "$49.50")
        XCTAssertEqual(Format.wholeCents(1_000_000), "$10,000")
        XCTAssertEqual(Format.perMinute(0.005), "$0.005")
        XCTAssertEqual(Format.perMinute(0.01), "$0.01")
        XCTAssertEqual(Format.perMinute(0.025), "$0.025")
        XCTAssertEqual(Format.signedUsd(10), "+$10.00")
        XCTAssertEqual(Format.signedUsd(-0.0125), "−$0.0125")
        XCTAssertEqual(Format.maxResolution(1080), "1080p")
        XCTAssertEqual(Format.maxResolution(2160), "4K (2160p)")
        XCTAssertEqual(Format.maxResolution(4320), "8K (4320p)")
    }

    func testDollarField() {
        XCTAssertEqual(DollarField.cents("12.5"), 1250)
        XCTAssertEqual(DollarField.cents(" $50 "), 5000)
        XCTAssertNil(DollarField.cents(""))
        XCTAssertNil(DollarField.cents("ten"))
        XCTAssertNil(DollarField.cents("-3"))
        XCTAssertEqual(DollarField.text(1000), "10")
        XCTAssertEqual(DollarField.text(1050), "10.5")
        XCTAssertEqual(DollarField.text(1055), "10.55")
        XCTAssertEqual(DollarField.text(nil), "")
    }

    func testCreditMeterAndBuckets() throws {
        let billing = try decodeFixture("billing", as: Billing.self)
        let account = billing.account
        XCTAssertTrue(account.isInvoiced)
        XCTAssertFalse(CreditTools.isLow(account), "invoiced accounts are never low")
        // No limit: spent + available.
        XCTAssertEqual(CreditTools.spendCap(account), 0.0773 + 0.04602, accuracy: 1e-9)
        XCTAssertEqual(CreditTools.spentFraction(account), 0.0773 / (0.0773 + 0.04602), accuracy: 1e-9)
        let buckets = CreditTools.buckets(account)
        XCTAssertEqual(buckets.map(\.id), ["plan", "purchased"], "promo hides when empty with no expiry")
        XCTAssertEqual(buckets[1].note, "Never expires")
        XCTAssertEqual(CreditTools.kindLabel("auto_recharge"), "Auto-recharge")
        XCTAssertEqual(CreditTools.kindLabel("something_new"), "Something New")
    }

    func testPricingCalculator() throws {
        let plans = try decodeFixture("plans", as: ListResponse<Plan>.self).data
        let selected = PricingCalculator.defaultSelection
        let minutes = PricingCalculator.minutes(sourceMinutes: 1000, selected: selected)
        XCTAssertEqual(minutes.hd, 2000)
        XCTAssertEqual(minutes.sd, 2000)
        XCTAssertEqual(PricingCalculator.tallest(selected), 1080)
        let usage = JobEstimate.cost(minutes, rates: plans.first?.rates)
        let options = PricingCalculator.options(plans: plans, usage: usage, tallest: 1080)
        XCTAssertEqual(options.map(\.plan.id), [.payAsYouGo, .starter, .growth, .scale])
        let starter = try XCTUnwrap(options.first { $0.plan.id == .starter })
        XCTAssertEqual(starter.total, 29 + max(0, usage - 60), accuracy: 1e-9)
        XCTAssertNotNil(PricingCalculator.cheapest(options))
        XCTAssertFalse(PricingCalculator.fitsTrial(plans.first { $0.id == .free }, usage: 100, tallest: 1080))
        XCTAssertTrue(PricingCalculator.fitsTrial(plans.first { $0.id == .free }, usage: 1, tallest: 1080))
        XCTAssertFalse(PricingCalculator.fitsTrial(plans.first { $0.id == .free }, usage: 1, tallest: 2160))

        let growth = try XCTUnwrap(plans.first { $0.id == .growth })
        XCTAssertEqual(PlanTools.includedPlan(growth, in: plans)?.id, .starter)
        XCTAssertEqual(PlanTools.perMonth(growth), "$99")
        XCTAssertEqual(PlanTools.perMonth(try XCTUnwrap(plans.first { $0.id == .enterprise })), "Custom")
    }

    func testScopesAndRanges() {
        var scopes: Set<String> = []
        scopes = KeyScopes.toggle("jobs:write", on: true, in: scopes)
        XCTAssertEqual(scopes, ["jobs:read", "jobs:write"])
        scopes = KeyScopes.toggle("jobs:read", on: false, in: scopes)
        XCTAssertEqual(scopes, [])
        XCTAssertEqual(KeyScopes.summary(["*"]), "Full access")
        XCTAssertEqual(KeyScopes.summary(["jobs:read"]), "1 scope")
        XCTAssertEqual(KeyScopes.expiryLabel(365), "In 1 year")

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let range = UsageRange.last(90, now: now, calendar: calendar)
        XCTAssertEqual(range.granularity, .week)
        XCTAssertEqual(calendar.dateComponents([.day], from: range.from, to: range.to).day, 89)
        XCTAssertEqual(UsageRange.date("2026-09-01", calendar: calendar).map { Format.isoDay($0, calendar: calendar) }, "2026-09-01")

        XCTAssertEqual(JobCounts.greeting(hour: 9), "Good morning")
        XCTAssertEqual(JobCounts.greeting(hour: 20), "Good evening")
    }
}
