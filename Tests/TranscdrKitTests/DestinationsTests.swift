import XCTest
@testable import TranscdrKit

final class DestinationsTests: XCTestCase {
    func json<T: Encodable>(_ value: T) throws -> JSONValue {
        try JSONValue.from(value)
    }

    func endpoint(_ body: String) throws -> WebhookEndpoint {
        try TranscdrCoding.decoder.decode(WebhookEndpoint.self, from: Data(body.utf8))
    }

    func testMetaFallsBackToHTTPS() {
        XCTAssertEqual(Destinations.meta(.sns).short, "SNS")
        XCTAssertEqual(Destinations.meta(.sqs).targetLabel, "Queue URL")
        XCTAssertEqual(Destinations.meta(WebhookEndpointType(rawValue: "carrier-pigeon")).type, .https)
        XCTAssertEqual(Destinations.meta(nil).label, "HTTPS webhook")
    }

    func testTargetByType() throws {
        let sns = try endpoint(#"{"id":"whk_1","type":"sns","url":"x","topic_arn":"arn:aws:sns:us-east-1:123456789012:t","events":["*"],"created_at":"2026-01-01T00:00:00Z"}"#)
        XCTAssertEqual(Destinations.target(of: sns), "arn:aws:sns:us-east-1:123456789012:t")
        let sqs = try endpoint(#"{"id":"whk_2","type":"sqs","url":"https://sqs.eu-west-1.amazonaws.com/123456789012/q","events":[],"created_at":"2026-01-01T00:00:00Z"}"#)
        XCTAssertEqual(Destinations.target(of: sqs), "https://sqs.eu-west-1.amazonaws.com/123456789012/q", "falls back to url")
        let legacy = try endpoint(#"{"id":"whk_3","url":"https://example.com/h","events":[],"created_at":"2026-01-01T00:00:00Z"}"#)
        XCTAssertEqual(legacy.type, .https)
        XCTAssertEqual(Destinations.target(of: legacy), "https://example.com/h")
    }

    func testRegionFromTarget() {
        XCTAssertEqual(Destinations.region(fromTarget: " arn:aws:sns:eu-central-1:123456789012:events ", type: .sns), "eu-central-1")
        XCTAssertEqual(Destinations.region(fromTarget: "arn:aws-us-gov:sns:us-gov-west-1:123456789012:e", type: .sns), "us-gov-west-1")
        XCTAssertEqual(Destinations.region(fromTarget: "https://sqs.us-west-2.amazonaws.com/123456789012/q", type: .sqs), "us-west-2")
        XCTAssertEqual(Destinations.region(fromTarget: "https://sqs-ap-south-1.amazonaws.com/123456789012/q", type: .sqs), "ap-south-1")
        XCTAssertNil(Destinations.region(fromTarget: "https://localhost:4566/000000000000/q", type: .sqs))
        XCTAssertNil(Destinations.region(fromTarget: "arn:aws:sns:us-east-1:1:t", type: .https))
        XCTAssertNil(Destinations.region(fromTarget: "", type: .sns))
    }

    func testFifo() {
        XCTAssertTrue(Destinations.isFifo("https://sqs.us-east-1.amazonaws.com/123456789012/q.fifo/"))
        XCTAssertTrue(Destinations.isFifo(" arn:aws:sns:us-east-1:123456789012:t.fifo "))
        XCTAssertFalse(Destinations.isFifo("arn:aws:sns:us-east-1:123456789012:fifo"))
    }

    func testQueueArn() {
        XCTAssertEqual(Destinations.queueArn("https://sqs.us-east-1.amazonaws.com/123456789012/transcdr-events"), "arn:aws:sqs:us-east-1:123456789012:transcdr-events")
        XCTAssertEqual(Destinations.queueArn("https://sqs.eu-west-1.amazonaws.com/123456789012/q.fifo?x=1"), "arn:aws:sqs:eu-west-1:123456789012:q.fifo")
        XCTAssertNil(Destinations.queueArn("https://sqs.us-east-1.amazonaws.com/12345/q"), "the account id is 12 digits")
        XCTAssertNil(Destinations.queueArn("not a url"))
    }

    func testFormFromEndpointLeavesAnEchoedRegionBlank() throws {
        let echoed = try endpoint(#"{"id":"whk_1","type":"sqs","queue_url":"https://sqs.us-east-1.amazonaws.com/123456789012/q","aws":{"region":"us-east-1","access_key_id":"AKIAABCDEFGHIJKLMNOP","endpoint":null,"message_group_id":"g","secret_access_key_set":true},"events":["*"],"created_at":"2026-01-01T00:00:00Z"}"#)
        let form = Destinations.Form(endpoint: echoed)
        XCTAssertEqual(form.type, .sqs)
        XCTAssertEqual(form.target, "https://sqs.us-east-1.amazonaws.com/123456789012/q")
        XCTAssertEqual(form.region, "")
        XCTAssertEqual(form.accessKeyId, "AKIAABCDEFGHIJKLMNOP")
        XCTAssertEqual(form.secretAccessKey, "")
        XCTAssertEqual(form.messageGroupId, "g")

        let custom = try endpoint(#"{"id":"whk_2","type":"sns","topic_arn":"arn:aws:sns:us-east-1:123456789012:t","aws":{"region":"eu-west-1","access_key_id":"AKIA"},"events":[],"created_at":"2026-01-01T00:00:00Z"}"#)
        XCTAssertEqual(Destinations.Form(endpoint: custom).region, "eu-west-1")
    }

    func testCreateParams() throws {
        var form = Destinations.Form(type: .https, target: "  https://example.com/h ")
        XCTAssertEqual(try json(form.createParams(events: ["*"], description: " ")), ["type": "https", "url": "https://example.com/h", "events": ["*"]])
        XCTAssertEqual(try json(form.createParams(events: ["job.failed"], description: " Prod ")), ["type": "https", "url": "https://example.com/h", "events": ["job.failed"], "description": "Prod"])

        form = Destinations.Form(type: .sqs, target: "https://sqs.us-east-1.amazonaws.com/123456789012/q", accessKeyId: " AKIA ", secretAccessKey: " s ", region: "", endpoint: "", messageGroupId: "g")
        XCTAssertEqual(try json(form.createParams(events: ["job.completed"], description: "")), [
            "type": "sqs", "queue_url": "https://sqs.us-east-1.amazonaws.com/123456789012/q", "events": ["job.completed"],
            "aws": ["access_key_id": "AKIA", "secret_access_key": "s"],
        ], "the message group only applies to a FIFO target")

        form.type = .sns
        form.target = "arn:aws:sns:us-east-1:123456789012:t.fifo"
        form.region = "us-east-2"
        XCTAssertEqual(try json(form.createParams(events: ["*"], description: "")), [
            "type": "sns", "topic_arn": "arn:aws:sns:us-east-1:123456789012:t.fifo", "events": ["*"],
            "aws": ["access_key_id": "AKIA", "secret_access_key": "s", "region": "us-east-2", "message_group_id": "g"],
        ])
    }

    func testUpdateParamsKeepsABlankSecret() throws {
        let https = Destinations.Form(type: .https, target: "https://example.com/h ")
        XCTAssertEqual(try json(https.updateParams()), ["url": "https://example.com/h"])

        var form = Destinations.Form(type: .sqs, target: "https://sqs.us-east-1.amazonaws.com/123456789012/q", accessKeyId: "AKIA", secretAccessKey: "  ")
        XCTAssertEqual(try json(form.updateParams()), ["queue_url": "https://sqs.us-east-1.amazonaws.com/123456789012/q", "aws": ["access_key_id": "AKIA"]])

        form.type = .sns
        form.target = "arn:aws:sns:us-east-1:123456789012:t"
        form.secretAccessKey = "new"
        form.endpoint = "https://sns.example.com"
        XCTAssertEqual(try json(form.updateParams()), [
            "topic_arn": "arn:aws:sns:us-east-1:123456789012:t",
            "aws": ["access_key_id": "AKIA", "secret_access_key": "new", "endpoint": "https://sns.example.com"],
        ])
    }

    func testSetupCheckParams() throws {
        XCTAssertNil(Destinations.Form(type: .https, target: "https://x").setupCheckParams(events: ["*"]))
        XCTAssertNil(Destinations.Form(type: .sns, target: " ").setupCheckParams(events: ["*"]))
        let params = try XCTUnwrap(Destinations.Form(type: .sns, target: "arn:aws:sns:us-east-1:123456789012:t").setupCheckParams(events: ["*"]))
        XCTAssertEqual(try json(params), ["type": "sns", "topic_arn": "arn:aws:sns:us-east-1:123456789012:t", "events": ["*"], "aws": ["access_key_id": "", "secret_access_key": ""]])
    }

    func testCompleteness() {
        XCTAssertFalse(Destinations.Form(type: .https, target: " ").isComplete(requireSecret: true))
        XCTAssertTrue(Destinations.Form(type: .https, target: "https://x").isComplete(requireSecret: true))
        let aws = Destinations.Form(type: .sqs, target: "https://sqs.us-east-1.amazonaws.com/1/q", accessKeyId: "AKIA")
        XCTAssertFalse(aws.isComplete(requireSecret: true))
        XCTAssertTrue(aws.isComplete(requireSecret: false))
        XCTAssertFalse(Destinations.Form(type: .sns, target: "arn").isComplete(requireSecret: false))
    }

    func testFormErrors() {
        let mapped = Destinations.formErrors([
            "topic_arn": "Bad ARN", "aws.access_key_id": "Bad key", "aws.region": "Bad region", "events": "Pick one",
        ])
        XCTAssertEqual(mapped, ["target": "Bad ARN", "access_key_id": "Bad key", "region": "Bad region", "events": "Pick one"])
        XCTAssertEqual(Destinations.formErrors(["url": "Must be https"]), ["target": "Must be https"])
        XCTAssertEqual(Destinations.formErrors(["queue_url": "Nope"]), ["target": "Nope"])
    }

    func testPolicies() {
        XCTAssertEqual(Destinations.iamPolicy(.sqs, target: "https://sqs.us-east-1.amazonaws.com/123456789012/q"), [
            "Version": "2012-10-17",
            "Statement": [["Sid": "TranscdrSend", "Effect": "Allow", "Action": "sqs:SendMessage", "Resource": "arn:aws:sqs:us-east-1:123456789012:q"]],
        ])
        XCTAssertEqual(Destinations.iamPolicy(.sns, target: " ")?["Statement"]?[0]?["Resource"], "arn:aws:sns:<region>:<account-id>:<topic>")
        XCTAssertEqual(Destinations.iamPolicy(.sns, target: "arn:aws:sns:us-east-1:1:t")?["Statement"]?[0]?["Sid"], "TranscdrPublish")
        XCTAssertEqual(Destinations.iamPolicy(.sqs, target: "nope")?["Statement"]?[0]?["Resource"], "arn:aws:sqs:<region>:<account-id>:<queue>")
        XCTAssertNil(Destinations.iamPolicy(.https, target: "https://x"))

        let template = Destinations.setupTemplate(.sqs, target: "")
        XCTAssertEqual(template?["summary"], "Create an IAM user with this policy, then an access key for it.")
        XCTAssertTrue(template?["kms"]?.stringValue?.contains("queue is encrypted") == true)
        XCTAssertNil(Destinations.setupTemplate(.https, target: ""))
    }

    func testPrepareStepsCarryTheRegion() {
        let steps = Destinations.prepare(.sqs, target: "https://sqs.eu-west-1.amazonaws.com/123456789012/q")
        XCTAssertEqual(steps.map(\.title), ["Create a queue", "Create a policy", "Create a user and an access key"])
        XCTAssertEqual(steps[0].links[0].href, "https://console.aws.amazon.com/sqs/v3/home?region=eu-west-1#/create-queue")
        XCTAssertEqual(Destinations.prepare(.sns, target: "")[0].links[1].href, "https://console.aws.amazon.com/sns/v3/home#/topics")
        let https = Destinations.prepare(.https, target: "")
        XCTAssertEqual(https.count, 3)
        XCTAssertEqual(https[2].links.first?.href, "/docs/webhooks")
        XCTAssertFalse(https[2].links[0].isExternal)
        XCTAssertEqual(Destinations.providers.map(\.type), [.https, .sns, .sqs])
    }

    func testEventsAndObjectLinks() {
        XCTAssertFalse(Destinations.subscribableEvents.contains("webhook.test"))
        XCTAssertTrue(Destinations.subscribableEvents.contains("job.completed"))
        XCTAssertEqual(Destinations.eventsSummary(["*"]), "All events")
        XCTAssertEqual(Destinations.eventsSummary(["job.failed"]), "1 event")
        XCTAssertEqual(Destinations.eventsSummary(["a", "b"]), "2 events")
        XCTAssertEqual(Destinations.objectLink("job_abc"), .job("job_abc"))
        XCTAssertEqual(Destinations.objectLink("ast_abc"), .asset("ast_abc"))
        XCTAssertNil(Destinations.objectLink("con_abc"))
        XCTAssertNil(Destinations.objectLink(nil))
    }

    func testEventConnections() throws {
        let list = try TranscdrCoding.decoder.decode([Connection].self, from: Data(#"""
        [{"id":"con_1","name":"Bucket","kind":"s3","config":{"bucket":"b"}},
         {"id":"con_2","name":"Queue","kind":"sqs","config":{"queue_url":"https://sqs.us-east-1.amazonaws.com/1/q"},"enabled":false},
         {"id":"con_3","name":"Hook","kind":"webhook","config":{"url":"https://example.com"}}]
        """#.utf8))
        let usable = Destinations.eventConnections(list)
        XCTAssertEqual(usable.map(\.id), ["con_2", "con_3"])
        XCTAssertEqual(Destinations.connectionTarget(usable[0]), "https://sqs.us-east-1.amazonaws.com/1/q")
        XCTAssertEqual(Destinations.connectionKindLabel(.webhook), "Webhook")
    }
}
