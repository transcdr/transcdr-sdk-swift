import XCTest
@testable import TranscdrKit

final class UnlimitedPlanTests: XCTestCase {
    let organization = """
    {"object":"organization","id":"org_1","name":"Acme","slug":"acme","plan":"unlimited",
     "plan_details":{"id":"unlimited","name":"Unlimited","subscription":false,"price_cents":null,
       "monthly_credit_cents":0,"max_concurrent_jobs":8,"max_resolution":2160,"retention_days":30,
       "features":["api","hls","integrations","unlimited"]},
     "created_at":"2026-09-27T09:00:00Z"}
    """

    func testTheUnlimitedPlanIsHidden() {
        XCTAssertEqual(PlanID.unlimited.rawValue, "unlimited")
        XCTAssertFalse(PlanID.all.contains(.unlimited), "never listed")
        XCTAssertFalse(PlanID.subscriptions.contains(.unlimited), "never sold")
        XCTAssertEqual(Catalog.featureLabels["unlimited"], "Unlimited transcoding at no charge")
    }

    func testAnOrganizationOnUnlimited() throws {
        let org = try TranscdrCoding.decoder.decode(Organization.self, from: Data(organization.utf8))
        XCTAssertEqual(org.plan, .unlimited)
        XCTAssertEqual(org.planDetails?.name, "Unlimited")
        XCTAssertNil(org.planDetails?.priceCents)
        XCTAssertTrue(PlanTools.isUnlimited(org))
        XCTAssertTrue(PlanTools.isUnlimited(org.planDetails))
        XCTAssertEqual(PlanTools.perMonth(try XCTUnwrap(org.planDetails)), "Custom")
    }

    func testOtherPlansAreNotUnlimited() throws {
        let plans = try decodeFixture("plans", as: ListResponse<Plan>.self).data
        XCTAssertFalse(plans.isEmpty)
        XCTAssertFalse(plans.contains { PlanTools.isUnlimited($0) })
        XCTAssertFalse(PlanTools.isUnlimited(nil as Plan?))
        XCTAssertFalse(PlanTools.isUnlimited(nil as Organization?))
        // The feature alone marks it, whatever the plan id.
        let feature = try TranscdrCoding.decoder.decode(Plan.self, from: Data(#"{"id":"enterprise","features":["unlimited"]}"#.utf8))
        XCTAssertTrue(PlanTools.isUnlimited(feature))
    }
}
