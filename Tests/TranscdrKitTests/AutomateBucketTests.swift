import XCTest
@testable import TranscdrKit

final class AutomateBucketTests: XCTestCase {
    let queueUrl = "https://sqs.eu-west-1.amazonaws.com/123456789012/transcdr-ingest"
    let queueArn = "arn:aws:sqs:eu-west-1:123456789012:transcdr-ingest"
    let topicArn = "arn:aws:sns:eu-west-1:123456789012:ingest-events"
    let hook = "https://api.transcdr.com/v1/hooks/automations/ahk_abc123"

    func connection(_ json: String) throws -> Connection {
        try TranscdrCoding.decoder.decode(Connection.self, from: Data(json.utf8))
    }

    func parse(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    func statements(_ policy: JSONValue) -> [JSONValue] { policy["Statement"]?.arrayValue ?? [] }

    func actions(_ statement: JSONValue?) -> [String] { statement?["Action"]?.arrayValue?.compactMap(\.stringValue) ?? [] }

    // MARK: Method

    func testMethodsAndTriggers() {
        XCTAssertEqual(AutomateMethod.allCases, [.watch, .queue, .webhook])
        XCTAssertEqual(AutomateMethod.watch.trigger, .watch)
        XCTAssertEqual(AutomateMethod.queue.trigger, .queue)
        XCTAssertEqual(AutomateMethod.webhook.trigger, .hook)
        for m in AutomateMethod.allCases {
            XCTAssertFalse(m.howItWorks.isEmpty)
            XCTAssertFalse(m.latency.isEmpty)
            XCTAssertFalse(m.setup.isEmpty)
            XCTAssertFalse(m.bestFor.isEmpty)
        }
        XCTAssertEqual(AutomateMethod.queue.latency, "Seconds")
        XCTAssertEqual(AutomateMethod.watch.latency, "Up to the poll interval")
    }

    func testRecommendationByProvider() {
        XCTAssertEqual(AutomateMethod.recommended(providerID: "aws"), .queue)
        XCTAssertEqual(AutomateMethod.recommended(providerID: "r2"), .watch)
        XCTAssertEqual(AutomateMethod.recommended(providerID: "b2"), .watch)
        XCTAssertEqual(AutomateMethod.recommended(providerID: "minio"), .webhook)
        XCTAssertEqual(AutomateMethod.recommended(providerID: nil), .watch)
        XCTAssertEqual(AutomateMethod.recommended(providerID: "gcs"), .watch)
        XCTAssertEqual(WebhookSender.recommended(providerID: "aws"), .aws)
        XCTAssertEqual(WebhookSender.recommended(providerID: "minio"), .minio)
        XCTAssertEqual(WebhookSender.recommended(providerID: "r2"), .other)
    }

    func testRolesPerMethod() {
        XCTAssertEqual(AutomateMethod.watch.roles(outputsBack: false), ["source", "watch_folder"])
        XCTAssertEqual(AutomateMethod.queue.roles(outputsBack: false), ["source"])
        XCTAssertEqual(AutomateMethod.webhook.roles(outputsBack: false), ["source"])
        XCTAssertEqual(AutomateMethod.watch.roles(outputsBack: true), ["source", "watch_folder", "destination"])
        XCTAssertEqual(AutomateMethod.queue.roles(outputsBack: true), ["source", "destination"])
    }

    func testProvidersAreTheS3Family() {
        XCTAssertEqual(AutomateBucket.providers.map(\.id), ["aws", "r2", "b2", "minio"])
        XCTAssertTrue(AutomateBucket.providers.allSatisfy { $0.kind == .s3 })
    }

    // MARK: Connections

    func testProviderInferredFromTheEndpoint() throws {
        func c(_ endpoint: String?, kind: String = "s3") throws -> Connection {
            let e = endpoint.map { "\"endpoint\": \"\($0)\"," } ?? ""
            return try connection(#"{"id": "con_1", "kind": "\#(kind)", "config": {\#(e) "bucket": "b"}}"#)
        }
        XCTAssertEqual(AutomateBucket.providerID(for: try c(nil)), "aws")
        XCTAssertEqual(AutomateBucket.providerID(for: try c("")), "aws")
        XCTAssertEqual(AutomateBucket.providerID(for: try c("https://abc.r2.cloudflarestorage.com")), "r2")
        XCTAssertEqual(AutomateBucket.providerID(for: try c("https://s3.us-west-004.backblazeb2.com")), "b2")
        XCTAssertEqual(AutomateBucket.providerID(for: try c("https://minio.example.com")), "minio")
        XCTAssertEqual(AutomateBucket.providerID(for: try c("https://s3.wasabisys.com")), "s3")
        XCTAssertEqual(AutomateBucket.providerID(for: try c("https://s3.eu-west-1.amazonaws.com")), "aws")
        XCTAssertEqual(AutomateBucket.providerID(for: try c("https://s3.cn-north-1.amazonaws.com.cn")), "aws")
        XCTAssertNil(AutomateBucket.providerID(for: try c(nil, kind: "gcs")))
    }

    func testEligibleBuckets() throws {
        let list = [
            try connection(#"{"id": "s3", "kind": "s3", "config": {}, "capabilities": {"source": true, "watch": true, "destination": true}}"#),
            try connection(#"{"id": "http", "kind": "http", "config": {}, "capabilities": {"source": true}}"#),
            try connection(#"{"id": "off", "kind": "s3", "enabled": false, "config": {}, "capabilities": {"source": true, "watch": true}}"#),
            try connection(#"{"id": "sqs", "kind": "sqs", "config": {}, "capabilities": {"trigger": true}}"#),
            try connection(#"{"id": "gcs", "kind": "gcs", "config": {}, "capabilities": {"source": true, "watch": true}}"#),
        ]
        XCTAssertEqual(AutomateBucket.eligibleBuckets(list, method: .watch).map(\.id), ["s3", "gcs"])
        XCTAssertEqual(AutomateBucket.eligibleBuckets(list, method: .queue).map(\.id), ["s3"])
        XCTAssertEqual(AutomateBucket.eligibleBuckets(list, method: .webhook).map(\.id), ["s3", "http", "gcs"])
    }

    func testSharedKeys() {
        let keys: ProviderValues = ["access_key_id": .text("AKIA1"), "secret_access_key": .text("s3cret")]
        XCTAssertTrue(AutomateBucket.canShareKeys(providerID: "aws", values: keys))
        XCTAssertFalse(AutomateBucket.canShareKeys(providerID: "r2", values: keys))
        XCTAssertFalse(AutomateBucket.canShareKeys(providerID: "aws", values: ["access_key_id": .text("AKIA1")]))
        var temporary = keys
        temporary[text: "session_token"] = "tok"
        XCTAssertFalse(AutomateBucket.canShareKeys(providerID: "aws", values: temporary), "temporary keys expire")

        let queue: ProviderValues = ["queue_url": .text(queueUrl)]
        let shared = AutomateBucket.queueValues(queue, sharingKeysFrom: keys)
        XCTAssertEqual(shared.string("queue_url"), queueUrl)
        XCTAssertEqual(shared.string("access_key_id"), "AKIA1")
        XCTAssertEqual(shared.string("secret_access_key"), "s3cret")
        XCTAssertEqual(AutomateBucket.queueValues(queue, sharingKeysFrom: nil), queue)
        let params = ConnectionProviders.provider(id: "sqs")!.build(shared)
        XCTAssertEqual(params.config.region, "eu-west-1", "the region comes from the URL")
        XCTAssertEqual(params.secrets?.accessKeyId, "AKIA1")
    }

    // MARK: Draft

    func testDraftDefaults() {
        let d = AutomateBucket.draft(method: .queue, name: "media automation")
        XCTAssertEqual(d.name, "media automation")
        XCTAssertEqual(d.trigger, .queue)
        XCTAssertEqual(d.prefix, "incoming/")
        XCTAssertEqual(d.pattern, "**/*.{mp4,mov,mkv,webm,m4v}")
        XCTAssertEqual(d.preset, "hls-av1-abr")
        XCTAssertEqual(d.pollMinutes * 60, 300)
        XCTAssertEqual(d.settleSeconds, 60)
        XCTAssertEqual(d.destinationPrefix, "transcoded/{stem}/")
        XCTAssertEqual(AutomateBucket.draft(method: .webhook).trigger, .hook)
        XCTAssertEqual(AutomateBucket.suggestedName(bucket: "media"), "media automation")
        XCTAssertEqual(AutomateBucket.suggestedName(bucket: ""), "Bucket automation")
        XCTAssertEqual(AutomateBucket.pollSecondsRange, 60...86_400)
    }

    func testDestinationChoice() {
        XCTAssertEqual(AutomateBucket.destinationID(.sameBucket, bucketID: "con_b", otherID: "con_o"), "con_b")
        XCTAssertEqual(AutomateBucket.destinationID(.other, bucketID: "con_b", otherID: "con_o"), "con_o")
        XCTAssertEqual(AutomateBucket.destinationID(.none, bucketID: "con_b", otherID: "con_o"), "")
        XCTAssertEqual(AutomateBucket.destinationID(.sameBucket, bucketID: nil, otherID: ""), "")
    }

    // MARK: IAM policies

    func testBucketPolicyForReading() {
        let p = AutomateBucket.bucketPolicy(bucket: "media", root: "videos", roles: ["source", "watch_folder"])
        XCTAssertEqual(p["Version"], "2012-10-17")
        let s = statements(p)
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s[0]["Sid"], "TranscdrList")
        XCTAssertEqual(actions(s[0]), ["s3:ListBucket", "s3:GetBucketLocation"])
        XCTAssertEqual(s[0]["Resource"], "arn:aws:s3:::media")
        XCTAssertEqual(s[0]["Condition"], ["StringLike": ["s3:prefix": ["videos/*"]]])
        XCTAssertEqual(actions(s[1]), ["s3:GetObject"])
        XCTAssertEqual(s[1]["Resource"], "arn:aws:s3:::media/videos/*")
        // Queue and webhook read too, and a source must be listable to pass the check.
        XCTAssertEqual(AutomateBucket.bucketPolicy(bucket: "media", root: "videos", roles: ["source"]), p)
    }

    func testBucketPolicyWithOutputsBack() {
        let s = statements(AutomateBucket.bucketPolicy(bucket: "media", root: "", roles: ["source", "destination"]))
        XCTAssertNil(s[0]["Condition"], "no folder, no prefix condition")
        XCTAssertEqual(actions(s[1]), ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload"])
        XCTAssertEqual(s[1]["Resource"], "arn:aws:s3:::media/*")
        // Every role: the catalog's full template.
        XCTAssertEqual(
            AutomateBucket.bucketPolicy(bucket: "media", root: "v/", roles: ["source", "watch_folder", "destination"]),
            ConnectionProviders.s3PolicyTemplate(bucket: "media", root: "v/")
        )
    }

    func testBucketPolicyDeletingTheSource() {
        let s = statements(AutomateBucket.bucketPolicy(bucket: "media", root: "", roles: ["source"], deleteSource: true))
        XCTAssertEqual(actions(s[1]), ["s3:GetObject", "s3:DeleteObject"])
    }

    func testBucketPolicyPlaceholder() {
        let s = statements(AutomateBucket.bucketPolicy(bucket: " ", root: "", roles: ["source"]))
        XCTAssertEqual(s[0]["Resource"], "arn:aws:s3:::<your-bucket>")
    }

    func testConsumerAndMergedPolicies() {
        let consumer = AutomateBucket.consumerPolicy(queueArn: queueArn)
        let c = statements(consumer)
        XCTAssertEqual(c.count, 1)
        XCTAssertEqual(c[0]["Sid"], "ConsumeTranscdrTriggers")
        XCTAssertEqual(actions(c[0]), ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:ChangeMessageVisibility", "sqs:GetQueueAttributes"])
        XCTAssertEqual(c[0]["Resource"], .string(queueArn))
        // The same as the catalog's SQS setup.
        XCTAssertEqual(consumer, ConnectionProviders.sqsQueueSetup(queueUrl: queueUrl)["iam_policy"])

        let merged = statements(AutomateBucket.mergedPolicy(bucket: "media", root: "", roles: ["source", "destination"], queueArn: queueArn))
        XCTAssertEqual(merged.compactMap { $0["Sid"]?.stringValue }, ["TranscdrList", "TranscdrObjects", "ConsumeTranscdrTriggers"])
        XCTAssertEqual(statements(AutomateBucket.consumerPolicy(queueArn: ""))[0]["Resource"], "arn:aws:sqs:<region>:<account-id>:<queue>")
    }

    // MARK: Resource policies

    func testQueueAccessPolicyDirect() {
        let s = statements(AutomateBucket.queueAccessPolicy(queueArn: queueArn, fanout: .direct, bucket: "media"))[0]
        XCTAssertEqual(s["Principal"], ["Service": "s3.amazonaws.com"])
        XCTAssertEqual(s["Action"], "sqs:SendMessage")
        XCTAssertEqual(s["Resource"], .string(queueArn))
        XCTAssertEqual(s["Condition"], ["ArnLike": ["aws:SourceArn": "arn:aws:s3:::media"], "StringEquals": ["aws:SourceAccount": "123456789012"]])
        // The same as the catalog's SQS setup, which uses YOUR-BUCKET until the bucket is known.
        XCTAssertEqual(
            AutomateBucket.queueAccessPolicy(queueArn: queueArn, fanout: .direct, bucket: ""),
            ConnectionProviders.sqsQueueSetup(queueUrl: queueUrl)["queue_policy_for_s3"]
        )
        let unknown = statements(AutomateBucket.queueAccessPolicy(queueArn: "", fanout: .direct, bucket: "media"))[0]
        XCTAssertNil(unknown["Condition"]?["StringEquals"], "no account without a queue ARN")
    }

    func testQueueAccessPolicyFromATopic() {
        let s = statements(AutomateBucket.queueAccessPolicy(queueArn: queueArn, fanout: .topic, bucket: "media", topicArn: topicArn))[0]
        XCTAssertEqual(s["Principal"], ["Service": "sns.amazonaws.com"])
        XCTAssertEqual(s["Action"], "sqs:SendMessage")
        XCTAssertEqual(s["Condition"], ["ArnEquals": ["aws:SourceArn": .string(topicArn)]])
        let placeholder = statements(AutomateBucket.queueAccessPolicy(queueArn: queueArn, fanout: .topic, bucket: "media"))[0]
        XCTAssertEqual(placeholder["Condition"]?["ArnEquals"]?["aws:SourceArn"], "arn:aws:sns:eu-west-1:123456789012:YOUR-TOPIC")
    }

    func testTopicPolicy() {
        let s = statements(AutomateBucket.topicPolicy(topicArn: topicArn, bucket: "media"))[0]
        XCTAssertEqual(s["Principal"], ["Service": "s3.amazonaws.com"])
        XCTAssertEqual(s["Action"], "sns:Publish")
        XCTAssertEqual(s["Resource"], .string(topicArn))
        XCTAssertEqual(s["Condition"], ["ArnLike": ["aws:SourceArn": "arn:aws:s3:::media"], "StringEquals": ["aws:SourceAccount": "123456789012"]])
        XCTAssertEqual(AutomateBucket.arnAccount(topicArn), "123456789012")
        XCTAssertNil(AutomateBucket.arnAccount("nope"))
    }

    // MARK: Filters

    func testSuffixesFromThePattern() {
        XCTAssertEqual(AutomateBucket.suffixes(forPattern: "**/*.mp4"), [".mp4"])
        XCTAssertEqual(AutomateBucket.suffixes(forPattern: "*.mov"), [".mov"])
        XCTAssertEqual(AutomateBucket.suffixes(forPattern: "incoming/*.mkv"), [".mkv"])
        XCTAssertEqual(AutomateBucket.suffixes(forPattern: "**/master_*.mov"), [".mov"])
        XCTAssertEqual(AutomateBucket.suffixes(forPattern: "**/*.{mp4,mov,mkv,webm,m4v}"), [".mp4", ".mov", ".mkv", ".webm", ".m4v"])
        XCTAssertEqual(AutomateBucket.suffixes(forPattern: "*.{mp4,mp4}"), [".mp4"])
        XCTAssertEqual(AutomateBucket.patternExtensions("**/*.{mp4,mov}"), ["mp4", "mov"])
        XCTAssertEqual(AutomateBucket.sampleFileName(pattern: "**/*.{mov,mp4}"), "example.mov")
        XCTAssertEqual(AutomateBucket.sampleFileName(pattern: "**/*"), "example.mp4")
        // Only plain alphanumeric extensions become suffixes.
        XCTAssertNil(AutomateBucket.suffixes(forPattern: "*.{mp4, mov}"))
        XCTAssertNil(AutomateBucket.suffixes(forPattern: "**/*.tar.gz"))
        XCTAssertNil(AutomateBucket.suffixes(forPattern: "**/*"))
        XCTAssertNil(AutomateBucket.suffixes(forPattern: ""))
        XCTAssertNil(AutomateBucket.suffixes(forPattern: "**/video.*"))
        XCTAssertNil(AutomateBucket.suffixes(forPattern: "*.m*"))
        XCTAssertNil(AutomateBucket.suffixes(forPattern: "*.{mp4,}"))
        XCTAssertNil(AutomateBucket.suffixes(forPattern: "*.{}"))
        XCTAssertNil(AutomateBucket.suffixes(forPattern: "*.mp[34]"))
        XCTAssertNil(AutomateBucket.suffixes(forPattern: "*.{mp4,m?v}"))
    }

    func testFiltersJoinTheFolderAndThePrefix() {
        let f = AutomateBucket.filters(root: "videos", prefix: "incoming/", pattern: "**/*.mp4")
        XCTAssertEqual(f, NotificationFilters(prefix: "videos/incoming/", suffixes: [".mp4"], exact: true))
        XCTAssertEqual(AutomateBucket.filters(root: "", prefix: "/incoming", pattern: "**/*").prefix, "incoming/")
        let loose = AutomateBucket.filters(root: "", prefix: "", pattern: "**/*")
        XCTAssertEqual(loose, NotificationFilters(prefix: "", suffixes: [], exact: false))
        XCTAssertTrue(AutomateBucket.filtersSummary(loose).contains("the automation's pattern does the rest"))
        XCTAssertTrue(AutomateBucket.filtersSummary(f).contains("videos/incoming/"))
        XCTAssertTrue(AutomateBucket.filtersSummary(AutomateBucket.filters(root: "", prefix: "in/", pattern: "*.{a,b}")).contains("One configuration per extension"))
    }

    // MARK: Notification

    func testQueueNotificationOnePerExtension() {
        let f = AutomateBucket.filters(root: "", prefix: "incoming/", pattern: "**/*.{mp4,mov}")
        let n = AutomateBucket.bucketNotification(.queue(arn: queueArn), filters: f)
        let configs = n["QueueConfigurations"]?.arrayValue ?? []
        XCTAssertEqual(configs.count, 2)
        XCTAssertNil(n["TopicConfigurations"])
        XCTAssertEqual(configs[0]["QueueArn"], .string(queueArn))
        XCTAssertEqual(configs[0]["Id"], "transcdr-mp4")
        XCTAssertEqual(configs[1]["Id"], "transcdr-mov")
        XCTAssertEqual(configs[0]["Events"], ["s3:ObjectCreated:*"])
        XCTAssertEqual(configs[0]["Filter"], ["Key": ["FilterRules": [["Name": "prefix", "Value": "incoming/"], ["Name": "suffix", "Value": ".mp4"]]]])
        XCTAssertEqual(configs[1]["Filter"]?["Key"]?["FilterRules"]?[1]?["Value"], ".mov")
        XCTAssertEqual(configs[1]["Filter"]?["Key"]?["FilterRules"]?[0]?["Value"], "incoming/", "every configuration has the same prefix")
    }

    func testTopicNotificationPrefixOnly() {
        let f = AutomateBucket.filters(root: "", prefix: "incoming/", pattern: "**/*")
        let configs = AutomateBucket.bucketNotification(.topic(arn: topicArn), filters: f)["TopicConfigurations"]?.arrayValue ?? []
        XCTAssertEqual(configs.count, 1)
        XCTAssertEqual(configs[0]["TopicArn"], .string(topicArn))
        XCTAssertEqual(configs[0]["Id"], "transcdr")
        XCTAssertEqual(configs[0]["Filter"], ["Key": ["FilterRules": [["Name": "prefix", "Value": "incoming/"]]]])
    }

    func testNotificationWithoutFilters() {
        let f = AutomateBucket.filters(root: "", prefix: "", pattern: "**/*")
        let configs = AutomateBucket.bucketNotification(.queue(arn: queueArn), filters: f)["QueueConfigurations"]?.arrayValue ?? []
        XCTAssertEqual(configs.count, 1)
        XCTAssertNil(configs[0]["Filter"])
    }

    // MARK: Commands

    func testShellArguments() {
        XCTAssertEqual(AutomateBucket.shellArg("media-bucket"), "media-bucket")
        XCTAssertEqual(AutomateBucket.shellArg(queueUrl), queueUrl)
        XCTAssertEqual(AutomateBucket.shellArg("a b"), "'a b'")
        XCTAssertEqual(AutomateBucket.shellArg("it's"), "'it'\\''s'")
        XCTAssertEqual(AutomateBucket.shellArg(""), "''")
        XCTAssertEqual(AutomateBucket.shellArg("a,b"), "'a,b'")
        XCTAssertEqual(AutomateBucket.compact(["b": 1, "a": "x/y"]), #"{"a":"x/y","b":1}"#)
    }

    func testPutNotificationCommand() throws {
        let f = AutomateBucket.filters(root: "", prefix: "incoming/", pattern: "*.mp4")
        let n = AutomateBucket.bucketNotification(.queue(arn: queueArn), filters: f)
        let cmd = AutomateBucket.putNotificationCommand(bucket: "media", region: "eu-west-1", notification: n)
        XCTAssertTrue(cmd.hasPrefix("aws s3api put-bucket-notification-configuration --bucket media --region eu-west-1 \\\n  --notification-configuration '"))
        let json = try XCTUnwrap(cmd.components(separatedBy: "--notification-configuration '").last?.dropLast())
        XCTAssertEqual(try parse(String(json)), n, "the inline JSON is the configuration")
        XCTAssertFalse(AutomateBucket.putNotificationCommand(bucket: "media", region: "auto", notification: n).contains("--region"))
        XCTAssertFalse(AutomateBucket.putNotificationCommand(bucket: "media", region: nil, notification: n).contains("--region"))
    }

    func testSetQueuePolicyCommand() throws {
        let policy = AutomateBucket.queueAccessPolicy(queueArn: queueArn, fanout: .direct, bucket: "media")
        let cmd = AutomateBucket.setQueuePolicyCommand(queueUrl: queueUrl, policy: policy)
        XCTAssertTrue(cmd.hasPrefix("aws sqs set-queue-attributes --queue-url \(queueUrl) --region eu-west-1 \\\n  --attributes '"))
        let attributes = try parse(String(try XCTUnwrap(cmd.components(separatedBy: "--attributes '").last?.dropLast())))
        let inner = try XCTUnwrap(attributes["Policy"]?.stringValue, "the policy is a JSON string attribute")
        XCTAssertEqual(try parse(inner), policy)
    }

    func testTopicCommands() throws {
        let policy = AutomateBucket.topicPolicy(topicArn: topicArn, bucket: "media")
        let set = AutomateBucket.setTopicPolicyCommand(topicArn: topicArn, policy: policy)
        XCTAssertTrue(set.hasPrefix("aws sns set-topic-attributes --topic-arn \(topicArn) --region eu-west-1 \\\n  --attribute-name Policy --attribute-value '"))
        XCTAssertEqual(try parse(String(try XCTUnwrap(set.components(separatedBy: "--attribute-value '").last?.dropLast()))), policy)

        XCTAssertEqual(
            AutomateBucket.subscribeCommand(topicArn: topicArn, protocol: "sqs", endpoint: queueArn),
            "aws sns subscribe --topic-arn \(topicArn) --region eu-west-1 \\\n  --protocol sqs --notification-endpoint \(queueArn)"
        )
        XCTAssertEqual(
            AutomateBucket.subscribeCommand(topicArn: topicArn, protocol: "https", endpoint: hook),
            "aws sns subscribe --topic-arn \(topicArn) --region eu-west-1 \\\n  --protocol https --notification-endpoint \(hook)"
        )
    }

    func testMinioCommands() {
        let f = AutomateBucket.filters(root: "", prefix: "incoming/", pattern: "**/*.{mp4,mov}")
        XCTAssertEqual(
            AutomateBucket.minioCommands(bucket: "media", filters: f, hookURL: hook),
            """
            mc admin config set myminio notify_webhook:transcdr endpoint=\(hook)
            mc admin service restart myminio
            mc event add myminio/media arn:minio:sqs::transcdr:webhook --event put --prefix incoming/ --suffix .mp4
            mc event add myminio/media arn:minio:sqs::transcdr:webhook --event put --prefix incoming/ --suffix .mov
            """
        )
        let loose = AutomateBucket.filters(root: "", prefix: "", pattern: "**/*")
        XCTAssertEqual(
            AutomateBucket.minioCommands(alias: "lab", bucket: "media", filters: loose, hookURL: hook).components(separatedBy: "\n").last,
            "mc event add lab/media arn:minio:sqs::transcdr:webhook --event put"
        )
    }

    func testCurlAndRecords() throws {
        XCTAssertEqual(
            AutomateBucket.curlExample(hookURL: hook, prefix: "incoming"),
            "curl -X POST \(hook) \\\n  -H 'Content-Type: application/json' \\\n  -d '{\"path\":\"incoming/example.mp4\"}'"
        )
        XCTAssertEqual(
            AutomateBucket.curlExample(hookURL: hook, prefix: "", pattern: "*.mov"),
            "curl -X POST \(hook) \\\n  -H 'Content-Type: application/json' \\\n  -d '{\"path\":\"example.mov\"}'"
        )
        let records = AutomateBucket.recordsExample(bucket: "media", key: "incoming/example.mp4")
        XCTAssertEqual(records["Records"]?[0]?["s3"]?["object"]?["key"], "incoming/example.mp4")
        XCTAssertEqual(records["Records"]?[0]?["s3"]?["bucket"]?["name"], "media")
    }

    func testUploadLocation() throws {
        XCTAssertEqual(AutomateBucket.uploadLocation(connection: nil, bucket: "media", root: "videos", prefix: "incoming/"), "s3://media/videos/incoming/")
        let gcs = try connection(#"{"id": "c", "kind": "gcs", "config": {"bucket": "g"}}"#)
        XCTAssertEqual(AutomateBucket.uploadLocation(connection: gcs, bucket: "g", root: "", prefix: "incoming/"), "gs://g/incoming/")
    }

    // MARK: Setups

    func testQueueSetupDirect() throws {
        let input = AutomateBucket.QueueSetupInput(
            bucket: "media", bucketRegion: "eu-west-1", prefix: "incoming/", pattern: "**/*.mp4", queueUrl: queueUrl
        )
        let setup = AutomateBucket.queueSetup(input)
        XCTAssertEqual(setup.map(\.key), ["iam_policy", "queue_policy", "notification", "commands"])
        XCTAssertEqual(try parse(setup[0].code), AutomateBucket.consumerPolicy(queueArn: queueArn))
        XCTAssertEqual(try parse(setup[1].code), AutomateBucket.queueAccessPolicy(queueArn: queueArn, fanout: .direct, bucket: "media"))
        XCTAssertNotNil(try parse(setup[2].code)["QueueConfigurations"])
        let commands = setup[3].code
        XCTAssertTrue(commands.contains("aws sqs set-queue-attributes"))
        XCTAssertTrue(commands.contains("aws s3api put-bucket-notification-configuration"))
        XCTAssertFalse(commands.contains("aws sns"))
    }

    func testQueueSetupFanoutWithSharedKeys() throws {
        let input = AutomateBucket.QueueSetupInput(
            bucket: "media", prefix: "incoming/", pattern: "**/*.mp4", queueUrl: queueUrl,
            fanout: .topic, topicArn: topicArn, sharedKeys: true, roles: ["source", "destination"]
        )
        let setup = AutomateBucket.queueSetup(input)
        XCTAssertEqual(setup.map(\.key), ["iam_policy", "queue_policy", "topic_policy", "subscribe", "notification", "commands"])
        XCTAssertEqual(
            try parse(setup[0].code),
            AutomateBucket.mergedPolicy(bucket: "media", root: "", roles: ["source", "destination"], queueArn: queueArn)
        )
        XCTAssertEqual(statements(try parse(setup[1].code))[0]["Principal"], ["Service": "sns.amazonaws.com"])
        XCTAssertEqual(setup[3].code, AutomateBucket.subscribeCommand(topicArn: topicArn, protocol: "sqs", endpoint: queueArn))
        XCTAssertNotNil(try parse(setup[4].code)["TopicConfigurations"])
        XCTAssertTrue(setup[5].code.contains("aws sns set-topic-attributes"))
        XCTAssertEqual(setup[5].code.components(separatedBy: "\n\n").count, 3)
    }

    func testWebhookSetups() throws {
        let aws = AutomateBucket.webhookSetup(.init(sender: .aws, bucket: "media", prefix: "incoming/", pattern: "*.mp4", hookURL: hook, topicArn: topicArn))
        XCTAssertEqual(aws.map(\.key), ["topic_policy", "notification", "commands"])
        XCTAssertNotNil(try parse(aws[1].code)["TopicConfigurations"])
        XCTAssertTrue(aws[2].code.contains("--protocol https --notification-endpoint \(hook)"))

        let minio = AutomateBucket.webhookSetup(.init(sender: .minio, bucket: "media", prefix: "incoming/", pattern: "*.mp4", hookURL: hook))
        XCTAssertEqual(minio.map(\.key), ["minio"])
        XCTAssertTrue(minio[0].code.contains("--suffix .mp4"))

        let other = AutomateBucket.webhookSetup(.init(sender: .other, bucket: "media", root: "videos", prefix: "incoming/", pattern: "*.mp4", hookURL: hook))
        XCTAssertEqual(other.map(\.key), ["curl", "records"])
        XCTAssertTrue(other[0].code.contains("\"path\":\"incoming/example.mp4\""), "relative to the connection's folder")
        XCTAssertEqual(try parse(other[1].code)["Records"]?[0]?["s3"]?["object"]?["key"], "videos/incoming/example.mp4", "the full key")
    }

    // MARK: Troubleshooting

    func testTroubleshooting() {
        XCTAssertEqual(AutomateBucket.troubleshooting(method: .watch).map(\.title), [
            "The settle time has not passed",
            "The file went to another prefix",
            "The pattern does not match",
        ])
        XCTAssertEqual(AutomateBucket.troubleshooting(method: .queue).map(\.title), [
            "The notification configuration was not saved",
            "The queue policy does not allow the bucket",
            "A prefix or suffix filter does not match",
            "The file went to another prefix",
        ])
        XCTAssertEqual(AutomateBucket.troubleshooting(method: .queue, fanout: .topic).map(\.title), [
            "The notification configuration was not saved",
            "The queue policy does not allow the topic",
            "A prefix or suffix filter does not match",
            "The SNS subscription is still pending",
            "The file went to another prefix",
        ])
        let hookAWS = AutomateBucket.troubleshooting(method: .webhook, sender: .aws)
        XCTAssertEqual(hookAWS.map(\.title), [
            "The notification configuration was not saved",
            "The topic policy does not allow the bucket",
            "The SNS subscription is still pending",
            "A prefix or suffix filter does not match",
            "The file went to another prefix",
        ])
        XCTAssertTrue(hookAWS[2].detail.contains("confirmed automatically"))
        XCTAssertEqual(AutomateBucket.troubleshooting(method: .webhook, sender: .minio).first?.title, "The webhook target is not active")
        XCTAssertEqual(AutomateBucket.troubleshooting(method: .webhook, sender: .other).map(\.title), ["Nothing has posted yet", "The path does not match"])

        let located = AutomateBucket.troubleshooting(method: .queue, keyPrefix: "videos/incoming/").last
        XCTAssertEqual(located?.detail, "Check the key of the file you uploaded. It must be under videos/incoming/.")
        XCTAssertEqual(AutomateBucket.troubleshooting(method: .watch)[1].detail, "Check the key of the file you uploaded.")
        for m in AutomateMethod.allCases {
            for sender in WebhookSender.allCases {
                let items = AutomateBucket.troubleshooting(method: m, fanout: .topic, sender: sender)
                XCTAssertEqual(Set(items.map(\.id)).count, items.count, "unique ids for \(m)/\(sender)")
            }
        }
    }

    // MARK: Live test

    func testLiveTestTiming() throws {
        XCTAssertEqual(AutomateBucket.itemsPollSeconds, 3)
        XCTAssertEqual(AutomateBucket.runPollSeconds, 5)
        XCTAssertEqual(AutomateBucket.troubleshootAfterSeconds, 120)
        XCTAssertTrue(AutomateBucket.runsWhileWaiting(.watch))
        XCTAssertTrue(AutomateBucket.runsWhileWaiting(.queue))
        XCTAssertFalse(AutomateBucket.runsWhileWaiting(.webhook))

        let items = try TranscdrCoding.decoder.decode([AutomationItem].self, from: Data("""
        [
          {"path": "incoming/b.mp4", "status": "job_created", "job_id": "job_2", "created_at": "2026-09-27T10:00:05Z"},
          {"path": "incoming/a.mp4", "status": "job_created", "job_id": "job_1", "created_at": "2026-09-27T10:00:01Z"}
        ]
        """.utf8))
        XCTAssertEqual(AutomateBucket.firstArrival(items)?.path, "incoming/a.mp4")
        XCTAssertNil(AutomateBucket.firstArrival([]))

        let skipped = try TranscdrCoding.decoder.decode([AutomationItem].self, from: Data("""
        [
          {"path": "incoming/late.mp4", "status": "job_created", "job_id": "job_3", "created_at": "2026-09-27T10:00:09Z"},
          {"path": "incoming/early.txt", "status": "skipped", "created_at": "2026-09-27T10:00:01Z"}
        ]
        """.utf8))
        XCTAssertEqual(AutomateBucket.firstArrival(skipped)?.path, "incoming/late.mp4", "the one with a job is followed")
        XCTAssertEqual(AutomateBucket.firstArrival([skipped[1]])?.path, "incoming/early.txt")
    }

    func testOutputsLoopBack() {
        XCTAssertFalse(AutomateBucket.outputsLoopBack(prefix: "incoming/", destinationPrefix: "transcoded/{stem}/"))
        XCTAssertTrue(AutomateBucket.outputsLoopBack(prefix: "incoming/", destinationPrefix: "incoming/out/{stem}/"))
        XCTAssertTrue(AutomateBucket.outputsLoopBack(prefix: "", destinationPrefix: "transcoded/{stem}/"), "everything is watched")
        XCTAssertTrue(AutomateBucket.outputsLoopBack(prefix: "incoming", destinationPrefix: "/incoming/{stem}/"))
        XCTAssertTrue(AutomateBucket.outputsLoopBack(prefix: "incoming/", destinationPrefix: "{dir}/{stem}/"), "a variable may render inside it")
        XCTAssertFalse(AutomateBucket.outputsLoopBack(prefix: "incoming/", destinationPrefix: "out/{dir}/"))
    }

    // MARK: Plan

    func testPlanCreatesInOrder() {
        var plan = AutomatePlan(method: .queue, storageID: nil)
        XCTAssertEqual(plan.steps, [.storage, .queue, .automation])
        XCTAssertEqual(plan.next, .storage)
        XCTAssertEqual(plan.status(.storage), .waiting)
        plan.start(.storage)
        XCTAssertEqual(plan.status(.storage), .running)
        plan.succeed(.storage, id: "con_s")
        XCTAssertEqual(plan.status(.storage), .done)
        XCTAssertEqual(plan.next, .queue)
        plan.start(.queue)
        plan.succeed(.queue, id: "con_q")
        XCTAssertEqual(plan.next, .automation)
        XCTAssertEqual(plan.title(.automation), "Create the automation")
        plan.start(.automation)
        plan.succeed(.automation, id: "aut_1")
        XCTAssertTrue(plan.isComplete)
        XCTAssertNil(plan.next)
        XCTAssertEqual(plan.storageID, "con_s")
        XCTAssertEqual(plan.queueID, "con_q")
        XCTAssertEqual(plan.automationID, "aut_1")
    }

    func testPlanSkipsWhatExists() {
        XCTAssertEqual(AutomatePlan(method: .watch, storageID: "con_s").steps, [.automation])
        XCTAssertEqual(AutomatePlan(method: .watch, storageID: nil).steps, [.storage, .automation])
        XCTAssertEqual(AutomatePlan(method: .queue, storageID: "con_s", queueID: "con_q").steps, [.automation])
        XCTAssertEqual(AutomatePlan(method: .queue, storageID: "con_s").steps, [.queue, .automation])
        XCTAssertEqual(AutomatePlan(method: .webhook, storageID: nil, queueID: nil).steps, [.storage, .automation], "no queue for a webhook")
    }

    func testPlanRetriesFromTheFailedStep() {
        var plan = AutomatePlan(method: .queue, storageID: nil)
        plan.start(.storage)
        plan.succeed(.storage, id: "con_s")
        plan.start(.queue)
        plan.fail(.queue, message: "The queue URL is not valid.")
        XCTAssertEqual(plan.status(.queue), .failed("The queue URL is not valid."))
        XCTAssertEqual(plan.status(.storage), .done, "what was created is kept")
        XCTAssertTrue(plan.canRetry)
        XCTAssertEqual(plan.next, .queue, "a retry resumes here, without creating the storage connection again")
        plan.start(.queue)
        XCTAssertFalse(plan.canRetry)
        XCTAssertNil(plan.failure)
        plan.succeed(.queue, id: "con_q")
        XCTAssertEqual(plan.next, .automation)
    }

    func testPlanUpdatesAWebhookAutomationMadeEarly() {
        var plan = AutomatePlan(method: .webhook, storageID: nil)
        plan.start(.storage)
        plan.succeed(.storage, id: "con_s")
        plan.createdEarly(automationID: "aut_1")
        XCTAssertTrue(plan.updatesAutomation)
        XCTAssertEqual(plan.next, .automation, "step 5 still updates it")
        XCTAssertEqual(plan.title(.automation), "Update the automation")
        XCTAssertEqual(plan.steps, [.storage, .automation])
        plan.start(.automation)
        plan.succeed(.automation, id: "aut_1")
        XCTAssertTrue(plan.isComplete)
    }
}

// MARK: - What arrives, and what it becomes

final class AutomateBucketTranslationTests: XCTestCase {
    func parse(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    // MARK: Keys

    func testDecodingKeys() {
        XCTAssertEqual(AutomateBucket.decodeS3Key("incoming/Keynote+2026.mov"), "incoming/Keynote 2026.mov")
        XCTAssertEqual(AutomateBucket.decodeS3Key("a%28b%29.mp4"), "a(b).mp4")
        XCTAssertEqual(AutomateBucket.decodeS3Key("price%2B1.mp4"), "price+1.mp4", "an encoded + is a plus")
        XCTAssertEqual(AutomateBucket.decodeS3Key("caf%C3%A9.mov"), "café.mov", "multi-byte UTF-8")
        XCTAssertEqual(AutomateBucket.decodeS3Key("100%zz.mp4"), "100%zz.mp4", "an invalid escape stays")
        XCTAssertEqual(AutomateBucket.decodeS3Key("end%2"), "end%2")
        XCTAssertEqual(AutomateBucket.decodeS3Key("plain/key.mp4"), "plain/key.mp4")
    }

    func testEncodingKeysRoundTrips() {
        XCTAssertEqual(AutomateBucket.encodeS3Key("incoming/Keynote 2026.mov"), "incoming/Keynote+2026.mov")
        XCTAssertEqual(AutomateBucket.encodeS3Key("a(b)+c.mp4"), "a%28b%29%2Bc.mp4")
        for key in ["incoming/Keynote 2026.mov", "a(b)+c!.mp4", "café/ü x.mkv", "x~y_z-1.webm"] {
            XCTAssertEqual(AutomateBucket.decodeS3Key(AutomateBucket.encodeS3Key(key)), key)
        }
    }

    func testRelativeToTheRoot() {
        XCTAssertEqual(AutomateBucket.relativePath(root: "videos/", key: "videos/incoming/a.mov"), "incoming/a.mov")
        XCTAssertEqual(AutomateBucket.relativePath(root: "/videos", key: "/videos/incoming/a.mov"), "incoming/a.mov")
        XCTAssertEqual(AutomateBucket.relativePath(root: nil, key: "incoming/a.mov"), "incoming/a.mov")
        XCTAssertEqual(AutomateBucket.relativePath(root: "", key: "/a.mov"), "a.mov")
        XCTAssertNil(AutomateBucket.relativePath(root: "videos", key: "other/a.mov"), "outside the root")
        XCTAssertNil(AutomateBucket.relativePath(root: "videos", key: "videosx/a.mov"), "a sibling folder with the same start")
        XCTAssertNil(AutomateBucket.relativePath(root: "videos", key: "videos/"), "the folder itself")
    }

    // MARK: Glob (the server's own cases)

    func m(_ pattern: String, _ path: String) -> Bool { AutomateBucket.globMatch(pattern, path) }

    func testGlobLiteralsAndCase() {
        XCTAssertTrue(m("a/b.mp4", "a/b.mp4"))
        XCTAssertTrue(m("A/B.MP4", "a/b.mp4"))
        XCTAssertTrue(m("a/b.mp4", "A/b.Mp4"))
        XCTAssertFalse(m("a/b.mp4", "a/b.mp"))
        XCTAssertFalse(m("a/b.mp4", "a/b.mp44"))
        XCTAssertTrue(m("/a/b", "a/b"))
        XCTAssertTrue(m("", ""))
        XCTAssertFalse(m("", "a"))
    }

    func testGlobStarStaysInASegment() {
        XCTAssertTrue(m("*.mp4", "x.mp4"))
        XCTAssertTrue(m("*.mp4", ".mp4"))
        XCTAssertFalse(m("*.mp4", "d/x.mp4"))
        XCTAssertTrue(m("in/*", "in/x"))
        XCTAssertFalse(m("in/*", "in/d/x"))
        XCTAssertTrue(m("in/*/x.mov", "in/d/x.mov"))
        XCTAssertFalse(m("in/*/x.mov", "in/x.mov"))
        XCTAssertTrue(m("a*b*c", "aXXbYYc"))
        XCTAssertFalse(m("a*b*c", "aXXbYY/c"))
        XCTAssertTrue(m("*", "anything"))
        XCTAssertFalse(m("*", "a/b"))
    }

    func testGlobQuestionMark() {
        XCTAssertTrue(m("clip?.mp4", "clip1.mp4"))
        XCTAssertFalse(m("clip?.mp4", "clip.mp4"))
        XCTAssertFalse(m("clip?.mp4", "clip12.mp4"))
        XCTAssertFalse(m("a?b", "a/b"))
    }

    func testGlobstarCrossesSegments() {
        XCTAssertTrue(m("**/*.mp4", "x.mp4"))
        XCTAssertTrue(m("**/*.mp4", "a/x.mp4"))
        XCTAssertTrue(m("**/*.mp4", "a/b/c/x.mp4"))
        XCTAssertFalse(m("**/*.mp4", "a/b/c/x.mov"))
        XCTAssertTrue(m("incoming/**/*.mp4", "incoming/x.mp4"))
        XCTAssertTrue(m("incoming/**/*.mp4", "incoming/a/b/x.mp4"))
        XCTAssertFalse(m("incoming/**/*.mp4", "other/x.mp4"))
        XCTAssertFalse(m("incoming/**/*.mp4", "incomingx.mp4"))
        XCTAssertTrue(m("a/**/b", "a/b"))
        XCTAssertTrue(m("a/**/b", "a/x/y/b"))
        XCTAssertFalse(m("a/**/b", "a/xb"))
        XCTAssertTrue(m("a/**", "a/x"))
        XCTAssertTrue(m("a/**", "a/x/y"))
        XCTAssertTrue(m("**", "a/b/c"))
        XCTAssertTrue(m("**", ""))
        XCTAssertTrue(m("a**z", "a/b/z"))
        XCTAssertTrue(m("a/***/b", "a/x/b"))
    }

    func testGlobAlternatives() {
        XCTAssertTrue(m("*.{mp4,mov}", "x.mp4"))
        XCTAssertTrue(m("*.{mp4,mov}", "x.MOV"))
        XCTAssertFalse(m("*.{mp4,mov}", "x.mkv"))
        XCTAssertTrue(m("incoming/**/*.{mp4,mov}", "incoming/a/b.mov"))
        XCTAssertTrue(m("{a,b/c}/x", "b/c/x"))
        XCTAssertTrue(m("{a,b{1,2}}.txt", "b2.txt"))
        XCTAssertFalse(m("{a,b{1,2}}.txt", "b3.txt"))
        XCTAssertTrue(m("x{,.bak}", "x"))
        XCTAssertTrue(m("x{,.bak}", "x.bak"))
        XCTAssertTrue(m("a{b", "a{b"), "an unmatched brace is literal")
        XCTAssertTrue(m("a}b", "a}b"))
        XCTAssertTrue(m(AutomateBucket.defaultPattern, "incoming/Keynote 2026.m4v"))
    }

    func testGlobPathologicalPatternsStayCheap() {
        XCTAssertFalse(m("*a*a*a*a*a*a*a*a*a*a*a*a*b", String(repeating: "a", count: 200)))
        _ = m("{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}{a,b}", "ab")
    }

    // MARK: Destination prefix

    let day = ISO8601DateFormatter().date(from: "2026-09-27T23:30:00Z")!

    func testPathVars() {
        XCTAssertEqual(AutomateBucket.pathVars("incoming/2026/Keynote 2026.mov", now: day), [
            "name": "Keynote 2026.mov", "stem": "Keynote 2026", "ext": "mov", "dir": "incoming/2026", "date": "2026-09-27",
        ])
        let dotfile = AutomateBucket.pathVars(".hidden", now: day)
        XCTAssertEqual(dotfile["stem"], ".hidden")
        XCTAssertEqual(dotfile["ext"], "")
        XCTAssertEqual(dotfile["dir"], "")
        XCTAssertEqual(AutomateBucket.pathVars("a/archive.tar.gz", now: day)["stem"], "archive.tar")
    }

    func testRenderingThePrefix() {
        var vars = AutomateBucket.pathVars("incoming/talks/Keynote 2026.mov", now: day)
        vars["automation"] = "aut_7"
        XCTAssertEqual(AutomateBucket.renderPrefix("transcoded/{stem}/", vars: vars), "transcoded/Keynote 2026/")
        XCTAssertEqual(AutomateBucket.renderPrefix("{automation}/{date}/{stem}/", vars: vars), "aut_7/2026-09-27/Keynote 2026/")
        XCTAssertEqual(AutomateBucket.renderPrefix("out/{dir}/{name}.{ext}", vars: vars), "out/incoming/talks/Keynote 2026.mov.mov/")
        XCTAssertEqual(AutomateBucket.renderPrefix("/a//./b", vars: vars), "a/b/", "normalized")
        XCTAssertEqual(AutomateBucket.renderPrefix("out/{job_id}/", vars: vars), "out/{job_id}/", "filled once the job exists")
        XCTAssertEqual(AutomateBucket.renderPrefix("a/../b", vars: vars), "", "never escapes")
        XCTAssertEqual(AutomateBucket.renderPrefix("", vars: vars), "")
    }

    // MARK: Payloads

    func testSamplePath() {
        XCTAssertEqual(AutomateBucket.samplePath(prefix: "incoming", pattern: "**/*.{mp4,mov}"), "incoming/Keynote 2026.mp4")
        XCTAssertEqual(AutomateBucket.samplePath(prefix: "", pattern: "**/*"), "Keynote 2026.mov")
    }

    func testPayloadsPerMethod() throws {
        func keys(_ m: AutomateMethod, fanout: QueueFanout = .direct, sender: WebhookSender = .aws) -> [String] {
            AutomateBucket.payloads(method: m, bucket: "media-in", root: "videos", prefix: "incoming/", pattern: "*.mov", fanout: fanout, sender: sender).map(\.key)
        }
        XCTAssertEqual(keys(.watch), ["listing"])
        XCTAssertEqual(keys(.queue), ["s3", "eventbridge", "direct", "job"])
        XCTAssertEqual(keys(.queue, fanout: .topic), ["sns", "s3", "confirm", "eventbridge", "direct", "job"])
        XCTAssertEqual(keys(.webhook, sender: .aws), ["confirm", "sns"])
        XCTAssertEqual(keys(.webhook, sender: .minio), ["s3"])
        XCTAssertEqual(keys(.webhook, sender: .other), ["direct", "s3"])

        let queue = AutomateBucket.payloads(method: .queue, bucket: "media-in", root: "videos", prefix: "incoming/", pattern: "*.mov")
        let event = try parse(queue[0].code)
        let record = try XCTUnwrap(event["Records"]?[0])
        XCTAssertEqual(record["s3"]?["bucket"]?["name"], "media-in")
        XCTAssertEqual(record["s3"]?["object"]?["key"], "videos/incoming/Keynote+2026.mov", "the full key, encoded")
        XCTAssertEqual(record["eventName"], "ObjectCreated:Put")
        let bridge = try parse(queue[1].code)
        XCTAssertEqual(bridge["detail"]?["object"]?["key"], "videos/incoming/Keynote 2026.mov", "EventBridge keys are plain")
        XCTAssertEqual(bridge["detail-type"], "Object Created")
        XCTAssertEqual(queue[2].code, #"{"path":"incoming/Keynote 2026.mov"}"# + "\n" + #"{"paths":["incoming/Keynote 2026.mov","incoming/example.mov"]}"#)
        XCTAssertEqual(try parse(queue[3].code)["input"], "incoming/Keynote 2026.mov")

        let topic = "arn:aws:sns:eu-west-1:123456789012:uploads"
        let hook = AutomateBucket.payloads(method: .webhook, bucket: "media-in", root: nil, prefix: "incoming/", pattern: "*.mov", sender: .aws, topicArn: topic)
        let confirm = try parse(hook[0].code)
        XCTAssertEqual(confirm["Type"], "SubscriptionConfirmation")
        XCTAssertTrue(confirm["SubscribeURL"]?.stringValue?.hasPrefix("https://sns.eu-west-1.amazonaws.com/?Action=ConfirmSubscription&TopicArn=arn%3Aaws%3Asns") == true)
        let envelope = try parse(hook[1].code)
        XCTAssertEqual(envelope["Type"], "Notification")
        XCTAssertEqual(envelope["TopicArn"], .string(topic))
        let inner = try parse(try XCTUnwrap(envelope["Message"]?.stringValue))
        XCTAssertEqual(inner["Records"]?[0]?["s3"]?["object"]?["key"], "incoming/Keynote+2026.mov", "the S3 event is the JSON string in Message")

        let minio = try parse(AutomateBucket.payloads(method: .webhook, bucket: "b", root: nil, prefix: "", pattern: "", sender: .minio)[0].code)
        XCTAssertEqual(minio["Records"]?[0]?["eventSource"], "minio:s3")
        XCTAssertEqual(minio["Records"]?[0]?["eventName"], "s3:ObjectCreated:Put")
        XCTAssertEqual(AutomateBucket.ignoredPayloads.count, 3)
    }

    // MARK: Translation

    func testNotificationBecomesAJob() {
        let t = AutomateBucket.translate(.init(
            key: "videos/incoming/Keynote+2026.mov", encoded: true, bucket: "media-in", eventBucket: "media-in", root: "videos/",
            prefix: "incoming/", pattern: "**/*.{mp4,mov}", sourceConnectionID: "con_1", automationID: "aut_7",
            metadata: ["team": "events"], destination: (connectionID: "con_1", template: "transcoded/{stem}/"), now: day
        ))
        XCTAssertTrue(t.job)
        XCTAssertEqual(t.steps.map(\.label), ["Key", "Path", "Match", "Job input", "Metadata", "Destination"])
        XCTAssertTrue(t.steps.allSatisfy(\.ok))
        XCTAssertEqual(t.steps[0].value, "videos/incoming/Keynote 2026.mov")
        XCTAssertEqual(t.steps[0].note, "Decoded from videos/incoming/Keynote+2026.mov")
        XCTAssertEqual(t.steps[1].value, "incoming/Keynote 2026.mov")
        XCTAssertEqual(t.steps[1].note, "Relative to the folder videos/")
        XCTAssertEqual(t.steps[2].value, "incoming/ · **/*.{mp4,mov}")
        XCTAssertEqual(t.steps[3].value, #"{"type":"connection","connection_id":"con_1","path":"incoming/Keynote 2026.mov"}"#)
        XCTAssertEqual(t.steps[4].value, #"{"team":"events","automation_id":"aut_7","source_path":"incoming/Keynote 2026.mov"}"#)
        XCTAssertEqual(t.steps[5].value, #"{"connection_id":"con_1","prefix":"transcoded/Keynote 2026/"}"#)
        XCTAssertNil(t.steps[5].note)
    }

    func testDirectPathsAreTakenAsTheyAre() {
        let t = AutomateBucket.translate(.init(key: "incoming/a+b.mov", encoded: false, relative: true, root: "videos", prefix: "incoming/", pattern: "*.mov"))
        XCTAssertFalse(t.job, "`*` stays in one folder, and the pattern sees the whole path")
        XCTAssertEqual(t.steps.last?.label, "Pattern")
        let ok = AutomateBucket.translate(.init(key: "incoming/a+b.mov", encoded: false, relative: true, root: "videos", prefix: "incoming/", pattern: "**/*.mov"))
        XCTAssertTrue(ok.job)
        XCTAssertEqual(ok.steps[1].value, "incoming/a+b.mov", "no decoding, no root")
        XCTAssertNil(ok.steps[0].note)
        XCTAssertNil(ok.steps[1].note)
        XCTAssertEqual(ok.steps.last?.value, "None: outputs stay in Transcdr")
        XCTAssertTrue(ok.steps[3].value.contains(#""connection_id":"con_…""#), "a placeholder before the connection exists")
    }

    func testFilesThatDoNotBecomeJobs() {
        let otherBucket = AutomateBucket.translate(.init(key: "a.mov", encoded: true, bucket: "media-in", eventBucket: "else", prefix: "", pattern: ""))
        XCTAssertFalse(otherBucket.job)
        XCTAssertEqual(otherBucket.steps.last?.label, "Bucket")
        XCTAssertFalse(otherBucket.steps.last!.ok)

        let outside = AutomateBucket.translate(.init(key: "other/a.mov", encoded: true, root: "videos", prefix: "", pattern: ""))
        XCTAssertEqual(outside.steps.last?.label, "Path")
        XCTAssertEqual(outside.steps.last?.note, "Outside the connection's folder videos/: skipped.")

        let prefix = AutomateBucket.translate(.init(key: "uploads/a.mov", encoded: true, prefix: "incoming/", pattern: "**/*"))
        XCTAssertEqual(prefix.steps.last?.label, "Prefix")
        XCTAssertFalse(prefix.job)

        let anything = AutomateBucket.translate(.init(key: "x/y.bin", encoded: true, prefix: "", pattern: " "))
        XCTAssertTrue(anything.job, "an empty pattern is **/*")
        XCTAssertEqual(anything.steps[2].value, "(any prefix) · **/*")
    }

    func testJobIDIsFilledLater() {
        let t = AutomateBucket.translate(.init(
            key: "incoming/a.mp4", encoded: false, relative: true, prefix: "incoming/", pattern: "**/*.mp4",
            destination: (connectionID: "", template: "out/{job_id}/"), now: day
        ))
        XCTAssertEqual(t.steps.last?.value, #"{"connection_id":"con_…","prefix":"out/{job_id}/"}"#)
        XCTAssertEqual(t.steps.last?.note, "{job_id} is filled once the job exists.")
    }
}
