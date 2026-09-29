import XCTest
@testable import TranscdrKit

final class ConnectionProvidersTests: XCTestCase {
    func provider(_ id: String) throws -> ConnectionProvider { try XCTUnwrap(ConnectionProviders.provider(id: id)) }

    /// A provider's defaults with some values on top.
    func values(_ p: ConnectionProvider, _ extra: [String: FieldValue]) -> ProviderValues {
        var v = p.defaults
        for (k, value) in extra { v.storage[k] = value }
        return v
    }

    func json<T: Encodable>(_ value: T) throws -> JSONValue { try JSONValue.from(value) }

    // MARK: Catalog

    func testCatalogMatchesTheWeb() {
        XCTAssertEqual(ConnectionProviders.all.map(\.id), ["aws", "r2", "b2", "minio", "gcs", "azure", "sftp", "ftp", "webdav", "http", "sqs", "sns", "webhook"])
        XCTAssertEqual(ConnectionProviders.providers(in: .storage).count, 10)
        XCTAssertEqual(ConnectionProviders.providers(in: .messaging).map(\.id), ["sqs", "sns", "webhook"])
        XCTAssertEqual(Set(ConnectionProviders.all.map(\.id)).count, ConnectionProviders.all.count, "ids are unique")
        for p in ConnectionProviders.all {
            XCTAssertEqual(p.isMessaging, p.kind.isMessaging, p.id)
            XCTAssertEqual(p.isMessaging, p.roles.isEmpty, p.id)
            XCTAssertEqual(p.isMessaging, p.messagingRole != nil, p.id)
            XCTAssertFalse(p.prepare(p.defaults).isEmpty, p.id)
            for key in p.scopeFields { XCTAssertNotNil(p.field(key), "\(p.id) scopes \(key)") }
        }
        XCTAssertEqual(try provider("http").roles, ["source"])
        XCTAssertEqual(try provider("sqs").messagingRole, "trigger")
        XCTAssertEqual(try provider("webhook").messagingRole, "notifications")
        XCTAssertNil(ConnectionProviders.provider(id: "nope"))
    }

    func testRegions() {
        XCTAssertEqual(ConnectionProviders.awsRegions.count, 26)
        XCTAssertEqual(ConnectionProviders.awsRegions.first, FieldOption("us-east-1", "US East (N. Virginia) · us-east-1"))
        XCTAssertEqual(ConnectionProviders.b2Regions.map(\.value), ["us-west-000", "us-west-001", "us-west-002", "us-west-004", "us-east-005", "eu-central-003"])
        XCTAssertEqual(ConnectionProviders.b2Regions.last?.label, "EU Central · eu-central-003")
    }

    // MARK: Fields

    func testVisibleFieldsFollowTheAuthChoice() throws {
        let azure = try provider("azure")
        var v = azure.defaults
        XCTAssertEqual(ConnectionProviders.visibleFields(azure.fields, v).map(\.key), ["account", "bucket", "root", "auth", "sas_token"])
        v[text: "auth"] = "account_key"
        XCTAssertEqual(ConnectionProviders.visibleFields(azure.fields, v).map(\.key), ["account", "bucket", "root", "auth", "account_key"])

        let sftp = try provider("sftp")
        XCTAssertEqual(sftp.credentialFields(sftp.defaults).map(\.key), ["auth", "private_key", "private_key_passphrase"])
        XCTAssertEqual(sftp.credentialFields(values(sftp, ["auth": .text("password")])).map(\.key), ["auth", "password"])

        let http = try provider("http")
        XCTAssertEqual(http.credentialFields(http.defaults).map(\.key), ["auth"])
        XCTAssertEqual(http.credentialFields(values(http, ["auth": .text("basic")])).map(\.key), ["auth", "username", "password"])
        XCTAssertEqual(http.credentialFields(values(http, ["auth": .text("bearer_token")])).map(\.key), ["auth", "bearer_token"])
    }

    func testFieldSections() throws {
        let aws = try provider("aws")
        XCTAssertEqual(aws.settingsFields(aws.defaults).map(\.key), ["bucket", "region", "root"])
        XCTAssertEqual(aws.credentialFields(aws.defaults).map(\.key), ["access_key_id", "secret_access_key"])
        XCTAssertEqual(aws.advancedFields(aws.defaults).map(\.key), ["session_token"])
        let sns = try provider("sns")
        XCTAssertEqual(sns.advancedFields(sns.defaults).map(\.key), ["message_group_id", "endpoint"])
        XCTAssertEqual(try provider("gcs").field("service_account_json")?.acceptsFiles, ["json"])
        XCTAssertTrue(try provider("webhook").credentialFields([:]).isEmpty)
    }

    func testMissingRequired() throws {
        let aws = try provider("aws")
        XCTAssertEqual(ConnectionProviders.missingRequired(aws.fields, aws.defaults).map(\.key), ["bucket", "access_key_id", "secret_access_key"])
        let filled = values(aws, ["bucket": .text("  b "), "access_key_id": .text("AKIA"), "secret_access_key": .text("s")])
        XCTAssertTrue(ConnectionProviders.missingRequired(aws.fields, filled).isEmpty)
        XCTAssertEqual(
            ConnectionProviders.missingRequired(aws.fields, values(aws, ["bucket": .text("   ")])).first?.key, "bucket",
            "whitespace is empty"
        )

        // Hidden fields are never required; checkboxes never count.
        let azure = try provider("azure")
        let v = values(azure, ["account": .text("a"), "bucket": .text("c"), "auth": .text("account_key")])
        XCTAssertEqual(ConnectionProviders.missingRequired(azure.fields, v).map(\.key), ["account_key"])
        let ftp = try provider("ftp")
        XCTAssertEqual(ConnectionProviders.missingRequired(ftp.fields, values(ftp, ["tls": .flag(false)])).map(\.key), ["host", "username", "password"])
    }

    func testValuesSubscripts() {
        var v: ProviderValues = ["port": .text(" 2222 "), "tls": .flag(false)]
        XCTAssertEqual(v.int("port"), 2222)
        XCTAssertEqual(v[text: "tls"], "")
        XCTAssertFalse(v[flag: "tls"])
        XCTAssertTrue(v.isOff("tls"))
        XCTAssertFalse(v.isOff("passive"), "unset is not off")
        v[flag: "passive"] = true
        XCTAssertTrue(v[flag: "passive"])
        XCTAssertNil(v.optional("missing"))
    }

    // MARK: Build

    func testBuildAWS() throws {
        let aws = try provider("aws")
        let v = values(aws, [
            "bucket": .text(" ingest "), "root": .text("/videos"), "access_key_id": .text("AKIA1"), "secret_access_key": .text("s3cr3t"),
            "session_token": .text(""),
        ])
        let params = aws.build(v, name: "Ingest")
        XCTAssertEqual(params.name, "Ingest")
        XCTAssertEqual(params.kind, .s3)
        XCTAssertEqual(params.config, ConnectionConfig(bucket: "ingest", region: "us-east-1", pathStyle: false, root: "videos/"))
        XCTAssertEqual(params.secrets, ConnectionSecrets(accessKeyId: "AKIA1", secretAccessKey: "s3cr3t"), "empty secrets are dropped")
        let body = try json(params)
        XCTAssertEqual(body["config"]?["path_style"], false)
        XCTAssertNil(body["config"]?["endpoint"])
    }

    func testBuildR2AndB2FillTheEndpoint() throws {
        let r2 = try provider("r2").build(["account_id": .text(" abc123 "), "bucket": .text("b")])
        XCTAssertEqual(r2.config.endpoint, "https://abc123.r2.cloudflarestorage.com")
        XCTAssertEqual(r2.config.region, "auto")
        XCTAssertNil(try provider("r2").build([:]).config.endpoint)
        XCTAssertEqual(ConnectionProviders.r2Endpoint("  "), nil)

        let b2 = try provider("b2")
        let built = b2.build(values(b2, ["bucket": .text("b")]))
        XCTAssertEqual(built.config.endpoint, "https://s3.us-west-004.backblazeb2.com")
        XCTAssertEqual(built.config.region, "us-west-004")
        XCTAssertNil(b2.build(values(b2, ["region": .text("")])).config.endpoint)
    }

    func testBuildMinioKeepsPathStyle() throws {
        let minio = try provider("minio")
        XCTAssertEqual(minio.build(minio.defaults).config.pathStyle, true)
        XCTAssertEqual(minio.build(values(minio, ["path_style": .flag(false)])).config.pathStyle, false)
        XCTAssertEqual(minio.build(values(minio, ["endpoint": .text("https://m.example.com")])).config.endpoint, "https://m.example.com")
    }

    func testBuildAzureSecrets() throws {
        let azure = try provider("azure")
        let sas = azure.build(values(azure, ["account": .text("acct"), "bucket": .text("videos"), "sas_token": .text("?sv=1&sig=x"), "account_key": .text("k")]))
        XCTAssertEqual(sas.kind, .azureBlob)
        XCTAssertEqual(sas.config, ConnectionConfig(bucket: "videos", account: "acct"))
        XCTAssertEqual(sas.secrets, ConnectionSecrets(sasToken: "sv=1&sig=x"), "the leading ? is dropped; the other secret is not sent")
        let key = azure.build(values(azure, ["auth": .text("account_key"), "account_key": .text("k"), "sas_token": .text("x")]))
        XCTAssertEqual(key.secrets, ConnectionSecrets(accountKey: "k"))
        XCTAssertEqual(azure.suggestName(values(azure, ["account": .text("acct"), "bucket": .text("videos")])), "acct/videos")
        XCTAssertEqual(azure.suggestName(azure.defaults), "Azure container")
    }

    func testBuildSFTP() throws {
        let sftp = try provider("sftp")
        let v = values(sftp, [
            "host": .text("sftp.example.com"), "username": .text("t"), "private_key": .text("KEY"), "password": .text("pw"),
            "host_key_fingerprint": .text("SHA256:abc"),
        ])
        let built = sftp.build(v)
        XCTAssertEqual(built.config, ConnectionConfig(host: "sftp.example.com", port: 22, username: "t", hostKeyFingerprint: "SHA256:abc"))
        XCTAssertEqual(built.secrets, ConnectionSecrets(privateKey: "KEY"))
        var pw = v
        pw[text: "auth"] = "password"
        XCTAssertEqual(sftp.build(pw).secrets, ConnectionSecrets(password: "pw"))
        XCTAssertNil(sftp.build(values(sftp, ["port": .text("abc")])).config.port, "an unreadable port is left out")
        XCTAssertEqual(sftp.suggestName(v), "sftp.example.com")
        XCTAssertEqual(sftp.suggestName([:]), "File server")
    }

    func testBuildFTPChoosesTheKindFromTLS() throws {
        let ftp = try provider("ftp")
        let tls = ftp.build(values(ftp, ["host": .text("h"), "username": .text("u"), "password": .text("p")]))
        XCTAssertEqual(tls.kind, .ftps)
        XCTAssertEqual(tls.config, ConnectionConfig(host: "h", port: 21, username: "u", passive: true))
        XCTAssertEqual(ftp.build(values(ftp, ["tls": .flag(false)])).kind, .ftp)
        XCTAssertEqual(ftp.build([:]).kind, .ftps, "unset TLS means FTPS")
    }

    func testBuildWebDAVAndHTTP() throws {
        let dav = try provider("webdav")
        let d = dav.build(values(dav, ["endpoint": .text("https://cloud.example.com:8443/dav/"), "password": .text("p"), "bearer_token": .text("t")]))
        XCTAssertEqual(d.secrets, ConnectionSecrets(password: "p"))
        XCTAssertEqual(dav.suggestName(values(dav, ["endpoint": .text("https://cloud.example.com:8443/dav/")])), "cloud.example.com:8443")
        XCTAssertEqual(dav.suggestName(values(dav, ["endpoint": .text("not a url")])), "WebDAV share")
        XCTAssertEqual(dav.build(values(dav, ["auth": .text("bearer_token"), "bearer_token": .text("t")])).secrets, ConnectionSecrets(bearerToken: "t"))

        let http = try provider("http")
        let none = http.build(values(http, ["endpoint": .text("https://media.example.com/"), "username": .text("u"), "password": .text("p")]))
        XCTAssertEqual(none.config, ConnectionConfig(endpoint: "https://media.example.com/"), "without basic auth the username is not sent")
        XCTAssertTrue(none.secrets?.isEmpty == true)
        XCTAssertEqual(try json(none)["secrets"], [:], "an empty secrets object is still sent")
        let basic = http.build(values(http, ["auth": .text("basic"), "username": .text("u"), "password": .text("p")]))
        XCTAssertEqual(basic.config.username, "u")
        XCTAssertEqual(basic.secrets, ConnectionSecrets(password: "p"))
    }

    func testBuildSQSTakesTheRegionFromTheURL() throws {
        let sqs = try provider("sqs")
        let url = "https://sqs.eu-west-1.amazonaws.com/123456789012/transcdr-ingest"
        let built = sqs.build(values(sqs, ["queue_url": .text(url), "access_key_id": .text("A"), "secret_access_key": .text("S")]))
        XCTAssertEqual(built.kind, .sqs)
        XCTAssertEqual(built.config, ConnectionConfig(region: "eu-west-1", queueUrl: url))
        XCTAssertEqual(sqs.build(values(sqs, ["queue_url": .text(url), "region": .text("us-east-2")])).config.region, "us-east-2")
        XCTAssertEqual(sqs.suggestName(values(sqs, ["queue_url": .text(url)])), "transcdr-ingest")
        XCTAssertEqual(sqs.suggestName(sqs.defaults), "SQS queue")
        XCTAssertTrue(sqs.setupReady(values(sqs, ["queue_url": .text(url)])))
        XCTAssertFalse(sqs.setupReady(values(sqs, ["queue_url": .text("https://example.com/q")])))
    }

    func testBuildSNSAndWebhook() throws {
        let sns = try provider("sns")
        let arn = "arn:aws:sns:ap-south-1:123456789012:transcdr-events"
        let built = sns.build(values(sns, ["topic_arn": .text(arn), "message_group_id": .text("g")]))
        XCTAssertEqual(built.config, ConnectionConfig(region: "ap-south-1", topicArn: arn, messageGroupId: "g"))
        XCTAssertEqual(sns.suggestName(values(sns, ["topic_arn": .text(arn)])), "transcdr-events")
        XCTAssertEqual(sns.suggestName(sns.defaults), "SNS topic")

        let hook = try provider("webhook")
        let h = hook.build(["url": .text("https://example.com/hooks")])
        XCTAssertEqual(h.config, ConnectionConfig(url: "https://example.com/hooks"))
        XCTAssertEqual(hook.suggestName(["url": .text("https://example.com/hooks")]), "example.com")
    }

    func testNormalizeRoot() {
        XCTAssertEqual(ConnectionProviders.normalizeRoot("videos/"), "videos/")
        XCTAssertEqual(ConnectionProviders.normalizeRoot("//videos"), "videos/")
        XCTAssertEqual(ConnectionProviders.normalizeRoot("  a/b "), "a/b/")
        XCTAssertEqual(ConnectionProviders.normalizeRoot(""), "")
        XCTAssertEqual(ConnectionProviders.normalizeRoot("/"), "")
    }

    // MARK: Templates

    func testS3PolicyTemplate() {
        let scoped = ConnectionProviders.s3PolicyTemplate(bucket: "ingest", root: "videos")
        XCTAssertEqual(scoped["Version"], "2012-10-17")
        XCTAssertEqual(scoped["Statement"]?[0]?["Resource"], "arn:aws:s3:::ingest")
        XCTAssertEqual(scoped["Statement"]?[0]?["Condition"], ["StringLike": ["s3:prefix": ["videos/*"]]])
        XCTAssertEqual(scoped["Statement"]?[1]?["Resource"], "arn:aws:s3:::ingest/videos/*")
        XCTAssertEqual(scoped["Statement"]?[1]?["Action"]?.arrayValue?.count, 4)

        let open = ConnectionProviders.s3PolicyTemplate(bucket: "", root: "")
        XCTAssertNil(open["Statement"]?[0]?["Condition"], "no folder, no condition")
        XCTAssertEqual(open["Statement"]?[1]?["Resource"], "arn:aws:s3:::<your-bucket>/*")
    }

    func testProviderTemplates() throws {
        let aws = try provider("aws")
        let t = try XCTUnwrap(aws.template(values(aws, ["bucket": .text("b")])))
        XCTAssertEqual(t["iam_policy"]?["Statement"]?[0]?["Resource"], "arn:aws:s3:::b")
        XCTAssertNotNil(t["kms"])
        XCTAssertTrue(aws.setupReady(values(aws, ["bucket": .text("b")])))
        XCTAssertFalse(aws.setupReady(aws.defaults))

        let gcs = try provider("gcs")
        XCTAssertEqual(gcs.template(["bucket": .text("media")])?["command"]?.stringValue?.contains("gs://media "), true)
        XCTAssertEqual(gcs.template([:])?["role"], "roles/storage.objectAdmin")
        XCTAssertEqual(try provider("azure").template([:])?["sas_permissions"], "racwdl (read, add, create, write, delete, list)")
        XCTAssertNil(try provider("sftp").template([:]), "file servers have no template")
        XCTAssertNil(try provider("webhook").template([:]))
        let sns = try XCTUnwrap(try provider("sns").template([:]))
        XCTAssertEqual(sns["iam_policy"]?["Statement"]?[0]?["Resource"], "arn:aws:sns:<region>:<account-id>:<topic>")
        XCTAssertEqual(sns["iam_policy"]?["Statement"]?[0]?["Sid"], "TranscdrPublish")
    }

    func testSQSQueueSetup() {
        let url = "https://sqs.us-east-1.amazonaws.com/123456789012/ingest"
        let setup = ConnectionProviders.sqsQueueSetup(queueUrl: url)
        let arn = "arn:aws:sqs:us-east-1:123456789012:ingest"
        XCTAssertEqual(setup["iam_policy"]?["Statement"]?[0]?["Resource"], .string(arn))
        XCTAssertEqual(setup["iam_policy"]?["Statement"]?[0]?["Action"]?.arrayValue?.count, 4)
        XCTAssertEqual(setup["queue_policy_for_s3"]?["Statement"]?[0]?["Condition"]?["StringEquals"]?["aws:SourceAccount"], "123456789012")
        XCTAssertEqual(
            setup["queue_policy_for_sns"]?["Statement"]?[0]?["Condition"]?["ArnEquals"]?["aws:SourceArn"],
            "arn:aws:sns:us-east-1:123456789012:YOUR-TOPIC"
        )
        XCTAssertEqual(setup["s3_notification"]?["QueueConfigurations"]?[0]?["QueueArn"], .string(arn))
        XCTAssertEqual(setup["notes"]?.arrayValue?.count, 3)

        let placeholder = ConnectionProviders.sqsQueueSetup(queueUrl: "", region: "eu-west-2")
        XCTAssertEqual(placeholder["iam_policy"]?["Statement"]?[0]?["Resource"], "arn:aws:sqs:eu-west-2:<account-id>:<queue>")
        XCTAssertEqual(ConnectionProviders.sqsQueueSetup(queueUrl: "")["iam_policy"]?["Statement"]?[0]?["Resource"], "arn:aws:sqs:<region>:<account-id>:<queue>")
    }

    func testQueueAndTopicParsing() {
        XCTAssertEqual(ConnectionProviders.queueArn(" https://sqs.eu-west-1.amazonaws.com/123456789012/q.fifo "), "arn:aws:sqs:eu-west-1:123456789012:q.fifo")
        XCTAssertEqual(ConnectionProviders.queueArn("https://sqs-fips.us-east-1.amazonaws.com/123456789012/q"), nil, "the host must be sqs.<region>")
        XCTAssertEqual(ConnectionProviders.queueArn("https://sqs-us-east-1.amazonaws.com/123456789012/q"), "arn:aws:sqs:us-east-1:123456789012:q")
        XCTAssertNil(ConnectionProviders.queueArn("http://localhost:4566/000000000000/q"))
        XCTAssertEqual(ConnectionProviders.queueName("http://localhost:4566/000000000000/fanout?x=1"), "fanout")
        XCTAssertEqual(ConnectionProviders.queueRegion("https://sqs.ap-southeast-2.amazonaws.com/1/q"), "ap-southeast-2")
        XCTAssertEqual(ConnectionProviders.topicRegion("arn:aws-us-gov:sns:us-gov-west-1:1:t"), "us-gov-west-1")
        XCTAssertEqual(ConnectionProviders.regionQuery("arn:aws:sns:eu-north-1:1:t", type: "sns"), "?region=eu-north-1")
        XCTAssertEqual(ConnectionProviders.regionQuery("nope", type: "sqs"), "")
        XCTAssertEqual(ConnectionProviders.hostOf("https://Example.com/x"), "Example.com")
        XCTAssertEqual(ConnectionProviders.hostOf("example.com"), "")
    }

    // MARK: Prepare steps

    func testPrepareStepsUseTheValues() throws {
        let aws = try provider("aws")
        let steps = aws.prepare(values(aws, ["region": .text("eu-west-1")]))
        XCTAssertEqual(steps.count, 4)
        XCTAssertEqual(steps[0].links.first?.href, "https://s3.console.aws.amazon.com/s3/bucket/create?region=eu-west-1")
        XCTAssertTrue(steps[0].links.allSatisfy(\.isExternal))

        let gcs = try provider("gcs").prepare(["bucket": .text("my bucket")])
        XCTAssertEqual(gcs[2].links.first?.href, "https://console.cloud.google.com/storage/browser/my%20bucket;tab=permissions")

        let sftp = try provider("sftp").prepare(["host": .text("files.example.com")])
        XCTAssertEqual(sftp[2].code, "ssh-keyscan -t ed25519 files.example.com 2>/dev/null | ssh-keygen -lf -")

        let sqs = try provider("sqs").prepare(["queue_url": .text("https://sqs.us-west-2.amazonaws.com/123456789012/q")])
        XCTAssertEqual(sqs.count, 5)
        XCTAssertEqual(sqs[0].links[0].href, "https://console.aws.amazon.com/sqs/v3/home?region=us-west-2#/create-queue")

        let webhook = try provider("webhook").prepare([:])
        XCTAssertEqual(webhook.last?.links.first, PrepareLink("Verifying signatures", "/docs/webhooks"))
        XCTAssertFalse(webhook.last!.links[0].isExternal)
    }

    // MARK: Setup guide

    func testSetupGuideForAQueue() {
        let guide = SetupGuide(ConnectionProviders.sqsQueueSetup(queueUrl: "https://sqs.us-east-1.amazonaws.com/123456789012/q"))
        XCTAssertEqual(guide.documents.map(\.key), ["iam_policy", "queue_policy_for_s3", "queue_policy_for_sns", "s3_notification"])
        XCTAssertEqual(guide.documents[0].title, "IAM policy for the Transcdr key (JSON)")
        XCTAssertTrue(guide.documents[1].json.contains("s3.amazonaws.com"))
        XCTAssertEqual(guide.notes.first, SetupGuide.Note(label: "Encryption", text: "If the queue is encrypted with a customer-managed KMS key, also allow kms:Decrypt on that key for these credentials."))
        XCTAssertTrue(guide.notes.contains { $0.label == nil && $0.text.contains("Object Created from aws.s3") }, "backticks are dropped")
        XCTAssertTrue(guide.otherText.isEmpty)
    }

    func testSetupGuideForStorage() throws {
        let aws = try provider("aws")
        let guide = SetupGuide(aws.template(values(aws, ["bucket": .text("b")])))
        XCTAssertEqual(guide.documents.map(\.title), ["IAM policy (JSON)"])
        XCTAssertEqual(guide.notes.map(\.label), ["Source only", "Destination only", "Encryption"])
        XCTAssertEqual(guide.notes[0].text, "drop s3:PutObject and s3:DeleteObject.", "the label is not repeated")

        let gcs = SetupGuide(try provider("gcs").template([:]))
        XCTAssertEqual(gcs.role, "roles/storage.objectAdmin")
        XCTAssertEqual(gcs.sourceOnlyRole, "roles/storage.objectViewer")
        XCTAssertNotNil(gcs.command)
        XCTAssertTrue(gcs.documents.isEmpty)

        let unknown = SetupGuide(["summary": "S", "endpoint_hint": "Use https", "policy_x": ["a": 1]])
        XCTAssertEqual(unknown.otherText.map(\.key), ["endpoint_hint"])
        XCTAssertEqual(unknown.documents.map(\.title), ["Policy x"])
        XCTAssertTrue(SetupGuide(nil).isEmpty)
    }

    // MARK: Check reports

    func report(_ json: String) throws -> CheckReport {
        try TranscdrCoding.decoder.decode(CheckReport.self, from: Data(json.utf8))
    }

    func testCheckReportSummaries() throws {
        let storage = try report("""
        {"object":"connection_check","ok":false,
         "steps":[{"id":"connect","label":"Connect","status":"passed","duration_ms":120},
                  {"id":"write","label":"Write","status":"failed","detail":"AccessDenied","hint":"Allow s3:PutObject","duration_ms":80}],
         "identity":{"provider":"aws","arn":"arn:aws:iam::1:user/t","account":"1"},
         "roles":{"source":true,"watch_folder":true,"destination":false}}
        """)
        XCTAssertEqual(storage.failedSteps.map(\.id), ["write"])
        XCTAssertEqual(storage.totalSeconds, 0.2, accuracy: 0.0001)
        XCTAssertEqual(storage.identitySummary, .init(title: "Signed in as", value: "arn:aws:iam::1:user/t", extra: "AWS account 1"))
        XCTAssertEqual(storage.rolesSummary, .storage(["source": true, "watch_folder": true, "destination": false]))
        XCTAssertEqual(storage.unmetRoles(["source", "destination"]).map(\.key), ["destination"])
        XCTAssertTrue(ConnectionProviders.rolesMet(storage, provider: try provider("aws"), wanted: ["source", "watch_folder"]))
        XCTAssertFalse(ConnectionProviders.rolesMet(storage, provider: try provider("aws"), wanted: ["destination"]))

        let queue = try report(#"{"object":"connection_check","ok":true,"steps":[],"roles":{"trigger":true,"notifications":true},"identity":{"provider":"s3_compatible","access_key_id":"K"}}"#)
        XCTAssertEqual(queue.rolesSummary, .trigger(true))
        XCTAssertTrue(ConnectionProviders.rolesMet(queue, provider: try provider("sqs"), wanted: []))
        XCTAssertEqual(queue.identitySummary?.title, "Access key")
        XCTAssertTrue(queue.unmetRoles(["source"]).isEmpty)

        let hook = try report(#"{"object":"webhook_check","ok":false,"steps":[],"roles":{"notifications":false}}"#)
        XCTAssertEqual(hook.rolesSummary, .notifications(false))
        XCTAssertNil(hook.identitySummary)
        XCTAssertFalse(ConnectionProviders.rolesMet(hook, provider: try provider("webhook"), wanted: []))

        let sftp = try report(#"{"object":"connection_check","ok":true,"steps":[],"roles":{},"identity":{"provider":"sftp","user":"t","server":"SSH-2.0"}}"#)
        XCTAssertEqual(sftp.identitySummary?.extra, "on SSH-2.0")
    }

    func testCheckNotes() {
        XCTAssertTrue(ConnectionProviders.checkNote(kind: .sqs).hasPrefix("Confirming"))
        XCTAssertTrue(ConnectionProviders.checkNote(kind: .sqs, saved: true).hasPrefix("Confirms"))
        XCTAssertTrue(ConnectionProviders.checkNote(kind: .gcs).contains(".transcdr-check/"))
        XCTAssertTrue(ConnectionProviders.checkNote(kind: .webhook, saved: true).contains("webhook.test"))
    }

    // MARK: Kinds and targets

    func testKindInfo() {
        XCTAssertEqual(ConnectionKindInfo.all.count, 11)
        XCTAssertEqual(ConnectionKindInfo.storage.map(\.kind), ConnectionKind.storage)
        XCTAssertEqual(ConnectionKindInfo.info(.azureBlob).mono, "AZ")
        XCTAssertEqual(ConnectionKindInfo.info("unknown").kind, .s3, "an unknown kind falls back to S3, as on the web")
        XCTAssertEqual(ConnectionKindInfo.info(.webhook).secrets.count, 0)
        XCTAssertEqual(ConnectionKindInfo.info(.sqs).roleSummary, "Triggers queue automations; receives events")
        XCTAssertEqual(ConnectionKindInfo.info(.http).roleSummary, "Source only")
        XCTAssertEqual(S3Shortcut.all.map(\.id), ["aws", "r2", "b2", "wasabi", "minio"])
        XCTAssertEqual(S3Shortcut.all.last?.config.pathStyle, true)
    }

    func testConnectionTargets() {
        XCTAssertEqual(ConnectionTargets.describe(kind: .s3, config: ConnectionConfig(bucket: "b", root: "/v/")), "b · AWS/v/")
        XCTAssertEqual(
            ConnectionTargets.describe(kind: .s3, config: ConnectionConfig(endpoint: "https://acct.r2.cloudflarestorage.com/", bucket: "b")),
            "b · acct.r2.cloudflarestorage.com"
        )
        XCTAssertEqual(ConnectionTargets.describe(kind: .gcs, config: ConnectionConfig(bucket: "b", root: "x/")), "gs://b/x/")
        XCTAssertEqual(ConnectionTargets.describe(kind: .azureBlob, config: ConnectionConfig(bucket: "c")), "?/c")
        XCTAssertEqual(ConnectionTargets.describe(kind: .sftp, config: ConnectionConfig(host: "h", port: 2222, username: "u")), "u@h:2222")
        XCTAssertEqual(ConnectionTargets.describe(kind: .ftp, config: ConnectionConfig(host: "h")), "h")
        XCTAssertEqual(ConnectionTargets.describe(kind: .webdav, config: ConnectionConfig(endpoint: "https://d/", root: "r/")), "https://d//r/")
        XCTAssertEqual(ConnectionTargets.describe(kind: .sqs, config: ConnectionConfig()), "?")
        XCTAssertEqual(ConnectionTargets.describe(kind: .webhook, config: ConnectionConfig(url: "https://x")), "https://x")
    }

    func connection(_ id: String, kind: String, enabled: Bool = true, capabilities: String = #"{"source":true,"destination":true,"watch":true}"#) throws -> Connection {
        try TranscdrCoding.decoder.decode(Connection.self, from: Data("""
        {"id":"\(id)","name":"\(id) name","kind":"\(kind)","config":{},"capabilities":\(capabilities),"enabled":\(enabled),"disabled_reason":\(enabled ? "null" : "\"AccessDenied\"")}
        """.utf8))
    }

    func testSourcesDestinationsAndQueues() throws {
        let list = try [
            connection("s3", kind: "s3"),
            connection("http", kind: "http", capabilities: #"{"source":true}"#),
            connection("q1", kind: "sqs", capabilities: #"{"trigger":true,"events":true}"#),
            connection("q2", kind: "sqs", enabled: false, capabilities: #"{"trigger":true}"#),
        ]
        XCTAssertEqual(ConnectionTargets.sources(list).map(\.id), ["s3", "http"])
        XCTAssertEqual(ConnectionTargets.destinations(list).map(\.id), ["s3"])
        XCTAssertEqual(ConnectionTargets.queues(list).map(\.id), ["q1"])
        XCTAssertEqual(ConnectionTargets.queues(list, keeping: "q2").map(\.id), ["q1", "q2"], "a turned-off queue stays when chosen")
        XCTAssertEqual(list[3].optionLabel, "q2 name (turned off)")
        XCTAssertEqual(list[0].optionLabel, "s3 name")
        XCTAssertTrue(list[3].isDisabled)
    }

    // MARK: Editing

    func testConnectionEditBody() throws {
        let c = try TranscdrCoding.decoder.decode(Connection.self, from: Data("""
        {"id":"con_1","name":"Ingest","kind":"s3","config":{"bucket":"b","region":"auto","path_style":true,"root":"v/"},"secrets_set":["access_key_id","secret_access_key"]}
        """.utf8))
        var edit = ConnectionEdit(c)
        XCTAssertEqual(edit.config[text: "bucket"], "b")
        XCTAssertTrue(edit.config[flag: "path_style"])
        XCTAssertEqual(edit.config[text: "endpoint"], "")
        XCTAssertTrue(edit.canSave)

        edit.name = " Renamed "
        edit.config[text: "root"] = "  "
        edit.config[text: "region"] = " us-east-1 "
        edit.secrets["secret_access_key"] = "new"
        edit.secrets["access_key_id"] = ""
        edit.clearing = ["session_token"]
        let body = edit.body
        XCTAssertEqual(body["name"], "Renamed")
        XCTAssertEqual(body["config"], ["bucket": "b", "region": "us-east-1", "endpoint": nil, "path_style": true, "root": nil], "empty fields are sent as null")
        XCTAssertEqual(body["secrets"], ["secret_access_key": "new", "session_token": ""], "an empty secret is kept (omitted); a cleared one is \"\"")

        edit.config[text: "bucket"] = ""
        XCTAssertFalse(edit.canSave)

        let ftp = try TranscdrCoding.decoder.decode(Connection.self, from: Data(#"{"id":"c","name":"f","kind":"ftps","config":{"host":"h","port":2121,"username":"u"}}"#.utf8))
        var e2 = ConnectionEdit(ftp)
        XCTAssertEqual(e2.configJSON["port"], 2121)
        e2.config[text: "port"] = ""
        XCTAssertEqual(e2.configJSON["port"], .null)
        XCTAssertEqual(e2.configJSON["passive"], false)
    }

    func testBareFieldErrors() {
        XCTAssertEqual(ConnectionEdit.bareFieldErrors(["config.bucket": "Required.", "secrets.password": "Bad", "name": "Taken"]), [
            "bucket": "Required.", "password": "Bad", "name": "Taken",
        ])
    }

    func testConfigSetByKey() {
        var c = ConnectionConfig()
        c.set("port", "22")
        c.set("path_style", "true")
        c.set("queue_url", "https://q")
        c.set("bucket", "")
        XCTAssertEqual(c.port, 22)
        XCTAssertEqual(c.pathStyle, true)
        XCTAssertEqual(c.queueUrl, "https://q")
        XCTAssertNil(c.bucket)
        XCTAssertEqual(c.fields, ["port": "22", "path_style": "true", "queue_url": "https://q"])
    }

    // MARK: Automations

    func testTemplateVariablesAndPatterns() {
        XCTAssertEqual(AutomationHelpers.templateVariables.map(\.name), ["{job_id}", "{name}", "{stem}", "{ext}", "{dir}", "{date}", "{automation}", "{org}"])
        XCTAssertEqual(AutomationHelpers.patternExamples.first?.pattern, "**/*.{mp4,mov}")
        XCTAssertEqual(AutomationHelpers.pollIntervals.map(\.minutes), [1, 5, 15, 60, 360, 1440])
    }

    func testPrefixPreview() {
        let date = Date(timeIntervalSince1970: 1_790_000_000) // 2026-09-21 UTC
        XCTAssertEqual(
            AutomationHelpers.prefixPreview("{automation}/{date}/{stem}/", sample: "incoming/talk.mov", date: date),
            "aut_7Tq…/2026-09-21/talk/"
        )
        XCTAssertEqual(AutomationHelpers.prefixPreview("{dir}/{name}.{ext}-{unknown}", sample: "a/b/c.tar.gz", date: date), "a/b/c.tar.gz.gz-{unknown}")
        XCTAssertEqual(AutomationHelpers.prefixPreview("{stem}{ext}{dir}", sample: ".hidden", date: date), ".hidden", "a leading dot is not an extension")
        XCTAssertEqual(AutomationHelpers.prefixPreview("", sample: "x", date: date), "")
    }

    func automation(_ json: String) throws -> Automation {
        try TranscdrCoding.decoder.decode(Automation.self, from: Data(json.utf8))
    }

    func testAutomationHelpers() throws {
        let a = try automation(#"{"id":"aut_1","trigger":"queue","trigger_connection_id":"q2","source":{"connection_id":"s3","prefix":"in/","pattern":"**/*"},"destination":{"connection_id":"s3","prefix":"out/"}}"#)
        let list = try [
            connection("s3", kind: "s3"),
            connection("q2", kind: "sqs", enabled: false, capabilities: #"{"trigger":true}"#),
        ]
        XCTAssertEqual(AutomationHelpers.offConnections(a, in: list).map(\.id), ["q2"])
        XCTAssertEqual(AutomationHelpers.usage(a, connection: "q2"), "queue trigger")
        XCTAssertEqual(AutomationHelpers.usage(a, connection: "s3"), "source and destination")
        XCTAssertTrue(AutomationHelpers.uses(a, connection: "s3"))
        XCTAssertFalse(AutomationHelpers.uses(a, connection: "other"))
        XCTAssertEqual(AutomationHelpers.triggerLabel(a, queueName: "ingest"), "queue · ingest")

        let w = try automation(#"{"id":"aut_2","trigger":"watch","poll_interval_seconds":900,"source":{"connection_id":"x"},"destination":{"connection_id":"s3"}}"#)
        XCTAssertEqual(AutomationHelpers.triggerLabel(w, queueName: ""), "watch · 15 min")
        XCTAssertEqual(AutomationHelpers.usage(w, connection: "s3"), "destination")
        XCTAssertTrue(AutomationHelpers.offConnections(w, in: list).isEmpty)
        let h = try automation(#"{"id":"aut_3","trigger":"hook","source":{"connection_id":"x"}}"#)
        XCTAssertEqual(AutomationHelpers.triggerLabel(h, queueName: ""), "hook")
    }

    func testEditableSpecPutsOverridesOnThePreset() throws {
        guard case .video(var hls) = OutputSpecTests.hlsCbr else { return XCTFail() }
        hls.renditions = .ladder(Ladder(maxShortSide: 1080, fit: .contain, upscale: false))
        let preset = OutputSpec.video(hls)
        let override: OutputOverrides = ["video": ["codec": "h265", "crf": 28]]
        XCTAssertNil(AutomationHelpers.editableSpec(override: override, preset: OutputSpecTests.hlsCbr), "its sizes' rates need cbr")
        guard case .video(let spec)? = AutomationHelpers.editableSpec(override: override, preset: preset) else { return XCTFail() }
        XCTAssertEqual(spec.container, .hls(segmentSeconds: 6))
        XCTAssertEqual(spec.video.codec, .h265)
        XCTAssertEqual(spec.video.rate, .crf(28), "crf replaces the preset's cbr")
        let patch = SpecTools.diff(.video(spec), base: preset).json
        XCTAssertNil(patch["container"], "the preset's own values are not overrides")
        XCTAssertEqual(patch["video"]?["codec"], "h265")

        XCTAssertEqual(AutomationHelpers.editableSpec(override: OutputOverrides(json: try JSONValue.from(preset)), preset: nil), preset)
        XCTAssertNil(AutomationHelpers.editableSpec(override: [:], preset: nil), "no preset: the overrides are the whole spec")
        XCTAssertNil(AutomationHelpers.editableSpec(override: ["container": ["segment_seconds": nil]], preset: preset), "incomplete")
    }

    func testAutomationDraftParams() throws {
        var draft = AutomationDraft()
        XCTAssertFalse(draft.isComplete)
        draft.name = " Ingest "
        draft.sourceId = "con_s3"
        draft.prefix = " /incoming "
        draft.pattern = "  "
        draft.metadata = ["team": "video"]
        XCTAssertTrue(draft.isComplete)
        XCTAssertEqual(draft.folder, "incoming/")

        let preset = OutputSpecTests.mp4
        guard case .video(var v) = preset else { return XCTFail() }
        v.video.codec = .av1
        let create = try json(draft.params(spec: .video(v), presetSpec: preset, isNew: true))
        XCTAssertEqual(create["name"], "Ingest")
        XCTAssertEqual(create["source"], ["connection_id": "con_s3", "prefix": "/incoming", "pattern": "**/*"])
        XCTAssertEqual(create["poll_interval_seconds"], 300)
        XCTAssertEqual(create["preset"], "hls-av1-abr")
        XCTAssertEqual(create["output"], ["video": ["codec": "av1"]])
        XCTAssertNil(create["destination"], "no destination on create: left out")
        XCTAssertNil(create["trigger_connection_id"])
        XCTAssertNil(create["webhook_url"])
        XCTAssertEqual(create["metadata"], ["team": "video"])

        draft.preset = ""
        draft.trigger = .queue
        XCTAssertFalse(draft.isComplete, "a queue trigger needs a queue")
        draft.queueId = "con_q"
        let update = try json(draft.params(spec: preset, presetSpec: nil, isNew: false))
        XCTAssertEqual(update["destination"], .null, "update: no destination clears it")
        XCTAssertEqual(update["preset"], "", "update: no preset clears it")
        XCTAssertEqual(update["webhook_url"], "")
        XCTAssertEqual(update["trigger_connection_id"], "con_q")
        XCTAssertEqual(update["output"], try JSONValue.from(preset), "no preset: the whole spec")

        draft.trigger = .hook
        draft.destinationId = "con_out"
        let hook = try json(draft.params(spec: preset, presetSpec: nil, isNew: false))
        XCTAssertEqual(hook["trigger_connection_id"], "", "leaving the queue trigger clears the queue")
        XCTAssertEqual(hook["destination"], ["connection_id": "con_out", "prefix": "{automation}/{date}/{stem}/"])
    }

    func testAutomationDraftFromAutomation() throws {
        let a = try automation(#"{"id":"aut_1","name":"A","enabled":false,"trigger":"watch","poll_interval_seconds":3600,"settle_seconds":30,"source":{"connection_id":"s","prefix":"in","pattern":"*.mov"},"preset":null,"destination":{"connection_id":"d"},"after_success":"delete","priority":"high","webhook_url":"https://x","metadata":{"k":"v"}}"#)
        let d = AutomationDraft(a)
        XCTAssertEqual(d.name, "A")
        XCTAssertFalse(d.enabled)
        XCTAssertEqual(d.pollMinutes, 60)
        XCTAssertEqual(d.settleSeconds, 30)
        XCTAssertEqual(d.prefix, "in")
        XCTAssertEqual(d.folder, "in/")
        XCTAssertEqual(d.preset, "")
        XCTAssertEqual(d.destinationId, "d")
        XCTAssertEqual(d.destinationPrefix, AutomationHelpers.defaultDestinationPrefix)
        XCTAssertEqual(d.afterSuccess, "delete")
        XCTAssertEqual(d.priority, .high)
        XCTAssertEqual(d.metadata, ["k": "v"])
    }

    func testRunSummary() throws {
        func run(_ json: String) throws -> AutomationRun { try TranscdrCoding.decoder.decode(AutomationRun.self, from: Data(json.utf8)) }
        XCTAssertEqual(AutomationHelpers.runSummary(try run(#"{"jobs_created":1,"messages_received":3,"messages_deleted":2}"#), queue: true), "3 messages received, 2 deleted, 1 job created.")
        XCTAssertEqual(AutomationHelpers.runSummary(try run(#"{"jobs_created":0,"messages_received":0}"#), queue: true), "No messages waiting.")
        XCTAssertEqual(AutomationHelpers.runSummary(try run(#"{"jobs_created":2}"#), queue: false), "2 new jobs created.")
        XCTAssertEqual(AutomationHelpers.runSummary(try run(#"{"jobs_created":0}"#), queue: false), "No new files to process.")
    }

    func testHookExamples() {
        let examples = AutomationHelpers.hookExamples(hookURL: "https://api.example.test/v1/hooks/automations/ahk_1", folder: "videos/")
        XCTAssertEqual(examples.map(\.label), ["curl", "AWS S3 (SNS)", "Cloudflare R2", "MinIO"])
        XCTAssertTrue(examples.allSatisfy { $0.code.contains("https://api.example.test/v1/hooks/automations/ahk_1") })
        XCTAssertTrue(examples[1].code.contains(#""Value": "videos/""#))
        let placeholder = AutomationHelpers.hookExamples(hookURL: nil, folder: "")
        XCTAssertTrue(placeholder[0].code.contains("ahk_…"))
        XCTAssertTrue(placeholder[3].code.hasSuffix("--prefix incoming/"))
    }

    // MARK: Browsing

    func testBrowseRowsFoldDeeperKeysIntoFolders() {
        let entries = [
            RemoteObject(path: "in/b.mov", size: 2, lastModified: nil),
            RemoteObject(path: "in/a.mp4", size: 1, lastModified: nil),
            RemoteObject(path: "in/clips/x.mov", size: 3, lastModified: nil),
            RemoteObject(path: "in/clips/y.mov", size: 3, lastModified: nil),
            RemoteObject(path: "in/empty/", size: nil, lastModified: nil),
            RemoteObject(path: "in/", size: nil, lastModified: nil),
        ]
        let rows = BrowseListing.rows(entries, prefix: "in/")
        XCTAssertEqual(rows.folders, [.init(name: "clips/", path: "in/clips/"), .init(name: "empty/", path: "in/empty/")])
        XCTAssertEqual(rows.files.map(\.path), ["in/a.mp4", "in/b.mov"])

        let root = BrowseListing.rows(entries, prefix: "")
        XCTAssertEqual(root.folders.map(\.path), ["in/"])
        XCTAssertTrue(root.files.isEmpty)
    }

    func testBreadcrumbsAndParents() {
        XCTAssertEqual(BrowseListing.crumbs("a/b/"), [.init(name: "a", path: "a/"), .init(name: "b", path: "a/b/")])
        XCTAssertTrue(BrowseListing.crumbs("").isEmpty)
        XCTAssertEqual(BrowseListing.parent("a/b/"), "a/")
        XCTAssertEqual(BrowseListing.parent("a/"), "")
        XCTAssertEqual(BrowseListing.parent(""), "")
        XCTAssertEqual(BrowseListing.basename("a/b/c.mov"), "c.mov")
        XCTAssertEqual(BrowseListing.basename("a/b/"), "b")
    }
}
