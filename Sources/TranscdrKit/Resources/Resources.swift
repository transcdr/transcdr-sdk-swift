import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// URL-encode one path segment.
func seg(_ value: String) -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/?#")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

/// Paging parameters shared by list endpoints.
public struct ListParams: Sendable {
    /// 1–100, default 20.
    public var limit: Int?
    public var cursor: String?

    public init(limit: Int? = nil, cursor: String? = nil) {
        self.limit = limit
        self.cursor = cursor
    }

    var query: Query { [("limit", limit.map(String.init)), ("cursor", cursor)] }
}

// MARK: - Auth

public struct AuthResource: Sendable {
    let client: Transcdr

    public func register(_ params: RegisterParams) async throws -> AuthResponse {
        try await client.request("POST", "/v1/auth/register", body: params)
    }

    /// Signs in to `organizationId` when given (else `params.organizationId`,
    /// else the organization used last).
    public func login(_ params: LoginParams, organizationId: String? = nil) async throws -> AuthResponse {
        var params = params
        if let organizationId { params.organizationId = organizationId }
        return try await client.request("POST", "/v1/auth/login", body: params)
    }

    /// A session in another of the user's organizations. The current session
    /// token is revoked, so the client adopts the new one. Sessions only: an
    /// API key gets 403 `session_required`; an organization the user isn't in,
    /// 403 `not_a_member`.
    public func `switch`(to organizationId: String) async throws -> AuthResponse {
        struct Body: Encodable {
            let organizationId: String
            enum CodingKeys: String, CodingKey { case organizationId = "organization_id" }
        }
        let session: AuthResponse = try await client.request("POST", "/v1/auth/switch", body: Body(organizationId: organizationId))
        client.apiKey = session.token
        return session
    }

    public func logout() async throws {
        try await client.requestVoid("POST", "/v1/auth/logout")
    }

    public func changePassword(_ params: ChangePasswordParams) async throws {
        try await client.requestVoid("POST", "/v1/auth/password", body: params)
    }

    public func me() async throws -> Me {
        try await client.request("GET", "/v1/me")
    }
}

// MARK: - Organization

public struct OrganizationResource: Sendable {
    let client: Transcdr

    public var members: MembersResource { .init(client: client) }

    public func retrieve() async throws -> Organization {
        try await client.request("GET", "/v1/organization")
    }

    public func update(_ params: OrganizationUpdateParams) async throws -> Organization {
        try await client.request("PATCH", "/v1/organization", body: params)
    }

    /// A new secret for signing deliveries to per-job webhook URLs.
    public func rotateJobWebhookSecret() async throws -> Organization {
        try await client.request("POST", "/v1/organization/rotate-job-webhook-secret")
    }
}

/// The organizations the signed-in user belongs to (sessions only).
public struct OrganizationsResource: Sendable {
    let client: Transcdr

    /// The user's memberships.
    public func list() async throws -> [Membership] {
        try await client.collection("/v1/organizations", as: Membership.self).data
    }

    /// A new organization, on the free plan, owned by the caller. Returns a
    /// session in it, which the client adopts; the previous token stays valid.
    public func create(name: String) async throws -> AuthResponse {
        struct Body: Encodable { let name: String }
        let session: AuthResponse = try await client.request("POST", "/v1/organizations", body: Body(name: name))
        client.apiKey = session.token
        return session
    }
}

public struct MembersResource: Sendable {
    let client: Transcdr

    public func list() async throws -> [User] {
        try await client.collection("/v1/organization/members", as: User.self).data
    }

    /// Adds an existing user by email, or creates one (with name and password).
    /// Only owners may add owners (403 `role_required`).
    public func create(_ params: MemberCreateParams) async throws -> User {
        try await client.request("POST", "/v1/organization/members", body: params)
    }

    /// Only owners may promote to or demote from owner (403 `role_required`);
    /// the last owner can't be demoted (409 `last_owner`).
    public func update(_ id: String, role: Role) async throws -> User {
        struct Body: Encodable { let role: Role }
        return try await client.request("PATCH", "/v1/organization/members/\(seg(id))", body: Body(role: role))
    }

    /// Removes the membership; your own id leaves the organization. The last
    /// owner can't be removed (409 `last_owner`).
    public func remove(_ id: String) async throws {
        try await client.requestVoid("DELETE", "/v1/organization/members/\(seg(id))")
    }
}

// MARK: - API keys

public struct APIKeysResource: Sendable {
    let client: Transcdr

    public func list(_ params: ListParams = .init()) async throws -> ListResponse<APIKey> {
        try await client.collection("/v1/api-keys", query: params.query)
    }

    public func all() -> Paginator<APIKey> { client.pages("/v1/api-keys") }

    /// The response carries `secret`, shown once.
    public func create(_ params: APIKeyCreateParams) async throws -> APIKey {
        try await client.request("POST", "/v1/api-keys", body: params)
    }

    public func revoke(_ id: String) async throws {
        try await client.requestVoid("DELETE", "/v1/api-keys/\(seg(id))")
    }
}

// MARK: - Uploads and assets

public struct UploadsResource: Sendable {
    let client: Transcdr

    public func create(_ params: UploadCreateParams) async throws -> Upload {
        try await client.request("POST", "/v1/uploads", body: params, idempotencyKey: newIdempotencyKey())
    }

    public func complete(_ id: String) async throws -> Asset {
        try await client.request("POST", "/v1/uploads/\(seg(id))/complete")
    }

    /// Upload a file end to end: open a session, PUT the bytes to storage,
    /// complete it. Returns the ready asset.
    public func uploadFile(
        _ file: URL, filename: String? = nil, contentType: String? = nil, metadata: Metadata? = nil,
        progress: (@Sendable (UploadProgress) -> Void)? = nil
    ) async throws -> Asset {
        let name = filename ?? file.lastPathComponent
        let type = contentType ?? MediaTypes.contentType(forFilename: name)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0

        let upload = try await create(.init(filename: name, contentType: type, sizeBytes: size, metadata: metadata))
        var request = URLRequest(url: client.url(upload.uploadUrl))
        request.httpMethod = upload.uploadMethod.isEmpty ? "PUT" : upload.uploadMethod
        request.timeoutInterval = max(300, Double(size) / 1_000_000)
        request.setValue(type, forHTTPHeaderField: "Content-Type")
        for (k, v) in upload.uploadHeaders { request.setValue(v, forHTTPHeaderField: k) }
        // Uploads to the API's own signed media route are authorised by the
        // URL; presigned storage URLs must not carry our bearer token.
        progress?(UploadProgress(sent: 0, total: size))
        let response: HTTPResponse
        do {
            response = try await client.transport.upload(request, fromFile: file, progress: progress)
        } catch {
            throw TranscdrError(kind: .connection, message: "Upload failed: \(error.localizedDescription)")
        }
        guard (200..<300).contains(response.status) else {
            throw TranscdrError.from(status: response.status, body: response.body, headers: response.headers)
        }
        progress?(UploadProgress(sent: size, total: size))
        return try await complete(upload.id)
    }
}

public struct AssetsResource: Sendable {
    let client: Transcdr

    public func list(_ params: ListParams = .init()) async throws -> ListResponse<Asset> {
        try await client.collection("/v1/assets", query: params.query)
    }

    public func all() -> Paginator<Asset> { client.pages("/v1/assets") }

    /// Link an asset by URL (jobs read the URL directly).
    public func create(_ params: AssetImportParams) async throws -> Asset {
        try await client.request("POST", "/v1/assets", body: params)
    }

    public func retrieve(_ id: String) async throws -> Asset {
        try await client.request("GET", "/v1/assets/\(seg(id))")
    }

    /// A signed, expiring URL to download the asset.
    public func contentURL(_ id: String) async throws -> SignedURL {
        try await client.request("GET", "/v1/assets/\(seg(id))/content", query: [("redirect", "false")])
    }

    public func delete(_ id: String) async throws {
        try await client.requestVoid("DELETE", "/v1/assets/\(seg(id))")
    }
}

// MARK: - Jobs

public struct JobListParams: Sendable {
    public var limit: Int?
    public var cursor: String?
    public var status: JobStatus?
    public var preset: String?
    public var createdAfter: Date?
    public var createdBefore: Date?
    public var metadata: Metadata

    public init(limit: Int? = nil, cursor: String? = nil, status: JobStatus? = nil, preset: String? = nil, createdAfter: Date? = nil, createdBefore: Date? = nil, metadata: Metadata = [:]) {
        self.limit = limit
        self.cursor = cursor
        self.status = status
        self.preset = preset
        self.createdAfter = createdAfter
        self.createdBefore = createdBefore
        self.metadata = metadata
    }

    var query: Query {
        var q: Query = [
            ("limit", limit.map(String.init)),
            ("status", status?.rawValue),
            ("preset", preset),
            ("created_after", createdAfter.map(TranscdrCoding.formatTimestamp)),
            ("created_before", createdBefore.map(TranscdrCoding.formatTimestamp)),
        ]
        for (k, v) in metadata.sorted(by: { $0.key < $1.key }) { q.append(("metadata[\(k)]", v)) }
        return q
    }
}

public struct JobsResource: Sendable {
    let client: Transcdr

    /// Create a job. Safe to retry: it carries an idempotency key.
    public func create(_ params: JobCreateParams, idempotencyKey: String = newIdempotencyKey()) async throws -> Job {
        try await client.request("POST", "/v1/jobs", body: params, idempotencyKey: idempotencyKey)
    }

    public func list(_ params: JobListParams = .init()) async throws -> ListResponse<Job> {
        try await client.page("/v1/jobs", query: params.query, cursor: params.cursor)
    }

    public func all(_ params: JobListParams = .init()) -> Paginator<Job> {
        client.pages("/v1/jobs", query: params.query)
    }

    public func retrieve(_ id: String) async throws -> Job {
        try await client.request("GET", "/v1/jobs/\(seg(id))")
    }

    public func cancel(_ id: String) async throws -> Job {
        try await client.request("POST", "/v1/jobs/\(seg(id))/cancel")
    }

    public func retry(_ id: String) async throws -> Job {
        try await client.request("POST", "/v1/jobs/\(seg(id))/retry")
    }

    public func delete(_ id: String) async throws {
        try await client.requestVoid("DELETE", "/v1/jobs/\(seg(id))")
    }

    public func events(_ id: String) async throws -> [JobEvent] {
        try await client.collection("/v1/jobs/\(seg(id))/events", as: JobEvent.self).data
    }

    public func outputs(_ id: String) async throws -> [JobOutput] {
        try await client.collection("/v1/jobs/\(seg(id))/outputs", as: JobOutput.self).data
    }

    /// A signed, expiring URL for one output.
    public func outputURL(_ id: String, label: String) async throws -> SignedURL {
        try await client.request("GET", "/v1/jobs/\(seg(id))/outputs/\(seg(label))", query: [("redirect", "false")])
    }

    /// A signed URL for any file under the job's output root (an HLS segment, a playlist).
    public func fileURL(_ id: String, path: String) async throws -> SignedURL {
        let encoded = path.split(separator: "/").map { seg(String($0)) }.joined(separator: "/")
        return try await client.request("GET", "/v1/jobs/\(seg(id))/files/\(encoded)", query: [("redirect", "false")])
    }

    public func deliveries(_ id: String) async throws -> [Delivery] {
        try await client.collection("/v1/jobs/\(seg(id))/deliveries", as: Delivery.self).data
    }

    /// Deliver (again) to a connection.
    public func deliver(_ id: String, to destination: JobDestination) async throws -> Delivery {
        try await client.request("POST", "/v1/jobs/\(seg(id))/deliveries", body: destination)
    }

    /// Poll until the job reaches a terminal status.
    public func waitFor(
        _ id: String, pollEvery: TimeInterval = 2, timeout: TimeInterval? = nil,
        onProgress: (@Sendable (Job) -> Void)? = nil
    ) async throws -> Job {
        let deadline = timeout.map { Date().addingTimeInterval($0) }
        while true {
            let job = try await retrieve(id)
            onProgress?(job)
            if job.status.isTerminal { return job }
            if let deadline, Date().addingTimeInterval(pollEvery) > deadline {
                throw TranscdrError(kind: .waitTimeout, message: "Job \(id) was still \(job.status) after \(Int(timeout ?? 0)) seconds.")
            }
            try await Task.sleep(nanoseconds: UInt64(pollEvery * 1e9))
        }
    }
}

public struct ProbeResource: Sendable {
    let client: Transcdr

    /// Probe an input. With `wait`, the call returns once the probe finished (up to 90 s).
    public func create(input: JobInput, wait: Bool = false) async throws -> Job {
        struct Body: Encodable { let input: JobInput }
        return try await client.request(
            "POST", "/v1/probe", query: [("wait", wait ? "true" : nil)], body: Body(input: input),
            timeout: wait ? 90 : nil
        )
    }
}

// MARK: - Presets

public struct PresetsResource: Sendable {
    let client: Transcdr

    public func list(_ params: ListParams = .init()) async throws -> ListResponse<Preset> {
        try await client.collection("/v1/presets", query: params.query)
    }

    public func all() -> Paginator<Preset> { client.pages("/v1/presets", query: [("limit", "100")]) }

    public func create(_ params: PresetParams) async throws -> Preset {
        try await client.request("POST", "/v1/presets", body: params)
    }

    public func retrieve(_ idOrSlug: String) async throws -> Preset {
        try await client.request("GET", "/v1/presets/\(seg(idOrSlug))")
    }

    public func update(_ id: String, _ params: PresetParams) async throws -> Preset {
        try await client.request("PATCH", "/v1/presets/\(seg(id))", body: params)
    }

    public func delete(_ id: String) async throws {
        try await client.requestVoid("DELETE", "/v1/presets/\(seg(id))")
    }
}

// MARK: - Webhooks and events

public struct WebhooksResource: Sendable {
    let client: Transcdr

    public func list(_ params: ListParams = .init()) async throws -> ListResponse<WebhookEndpoint> {
        try await client.collection("/v1/webhooks", query: params.query)
    }

    public func all() -> Paginator<WebhookEndpoint> { client.pages("/v1/webhooks") }

    /// The response carries `secret`, shown once.
    public func create(_ params: WebhookCreateParams) async throws -> WebhookEndpoint {
        try await client.request("POST", "/v1/webhooks", body: params)
    }

    public func retrieve(_ id: String) async throws -> WebhookEndpoint {
        try await client.request("GET", "/v1/webhooks/\(seg(id))")
    }

    public func update(_ id: String, _ params: WebhookUpdateParams) async throws -> WebhookEndpoint {
        try await client.request("PATCH", "/v1/webhooks/\(seg(id))", body: params)
    }

    public func delete(_ id: String) async throws {
        try await client.requestVoid("DELETE", "/v1/webhooks/\(seg(id))")
    }

    public func rotateSecret(_ id: String) async throws -> WebhookEndpoint {
        try await client.request("POST", "/v1/webhooks/\(seg(id))/rotate-secret")
    }

    /// Send a `webhook.test` event.
    public func test(_ id: String) async throws -> WebhookTestResult {
        try await client.request("POST", "/v1/webhooks/\(seg(id))/test")
    }

    /// Check a destination before saving it.
    public func check(_ params: WebhookCreateParams) async throws -> CheckReport {
        try await client.request("POST", "/v1/webhooks/check", body: params)
    }

    public func checkSaved(_ id: String) async throws -> CheckReport {
        try await client.request("POST", "/v1/webhooks/\(seg(id))/check")
    }

    public func deliveries(_ id: String, _ params: ListParams = .init()) async throws -> ListResponse<WebhookDelivery> {
        try await client.page("/v1/webhooks/\(seg(id))/deliveries", query: [("limit", params.limit.map(String.init))], cursor: params.cursor)
    }

    public func redeliver(_ deliveryId: String) async throws -> WebhookDelivery {
        try await client.request("POST", "/v1/webhook-deliveries/\(seg(deliveryId))/redeliver")
    }
}

public struct EventsResource: Sendable {
    let client: Transcdr

    public func list(type: String? = nil, _ params: ListParams = .init()) async throws -> ListResponse<Event> {
        try await client.page("/v1/events", query: [("type", type), ("limit", params.limit.map(String.init))], cursor: params.cursor)
    }

    public func retrieve(_ id: String) async throws -> Event {
        try await client.request("GET", "/v1/events/\(seg(id))")
    }
}

// MARK: - Usage and billing

public struct UsageResource: Sendable {
    let client: Transcdr

    /// `from` / `to` are `YYYY-MM-DD` or RFC 3339.
    public func retrieve(from: String? = nil, to: String? = nil, granularity: Granularity? = nil) async throws -> Usage {
        try await client.request("GET", "/v1/usage", query: [("from", from), ("to", to), ("granularity", granularity?.rawValue)])
    }
}

public struct BillingResource: Sendable {
    let client: Transcdr

    public func retrieve() async throws -> Billing {
        try await client.request("GET", "/v1/billing")
    }

    /// Subscribe, change plan, or buy credit. Open `url` to pay, when set.
    public func checkout(_ params: CheckoutParams) async throws -> Checkout {
        try await client.request("POST", "/v1/billing/checkout", body: params)
    }

    /// The payment provider's customer portal.
    public func portal() async throws -> Portal {
        try await client.request("POST", "/v1/billing/portal", body: [String: String]())
    }

    public func updateSettings(_ params: BillingSettingsParams) async throws -> Billing {
        try await client.request("PUT", "/v1/billing/settings", body: params)
    }

    /// The credit ledger, newest first (1–200; default 50).
    public func transactions(limit: Int? = nil) async throws -> [CreditTransaction] {
        try await client.collection("/v1/billing/transactions", query: [("limit", limit.map(String.init))], as: CreditTransaction.self).data
    }

    /// Monthly statements.
    public func statements(_ params: ListParams = .init()) async throws -> ListResponse<Statement> {
        try await client.page("/v1/billing/invoices", query: [("limit", params.limit.map(String.init))], cursor: params.cursor)
    }

    /// Move to a plan that needs no checkout (free, pay as you go).
    public func changePlan(_ plan: PlanID) async throws -> Billing {
        struct Body: Encodable { let plan: PlanID }
        return try await client.request("PUT", "/v1/billing/plan", body: Body(plan: plan))
    }
}

public struct PlansResource: Sendable {
    let client: Transcdr

    public func list() async throws -> [Plan] {
        try await client.collection("/v1/plans", as: Plan.self).data
    }
}

public struct CapabilitiesResource: Sendable {
    let client: Transcdr

    public func retrieve() async throws -> Capabilities {
        try await client.request("GET", "/v1/capabilities")
    }
}

public struct StatusResource: Sendable {
    let client: Transcdr

    public func retrieve() async throws -> ServiceStatus {
        try await client.request("GET", "/v1/status")
    }
}

public struct StatsResource: Sendable {
    let client: Transcdr

    public func retrieve() async throws -> Stats {
        try await client.request("GET", "/v1/stats")
    }
}

// MARK: - Integrations

public struct ConnectionsResource: Sendable {
    let client: Transcdr

    public func list(_ params: ListParams = .init()) async throws -> ListResponse<Connection> {
        try await client.collection("/v1/connections", query: params.query)
    }

    public func all() -> Paginator<Connection> { client.pages("/v1/connections", query: [("limit", "100")]) }

    /// Tested before it is saved.
    public func create(_ params: ConnectionCreateParams) async throws -> Connection {
        try await client.request("POST", "/v1/connections", body: params)
    }

    public func retrieve(_ id: String) async throws -> Connection {
        try await client.request("GET", "/v1/connections/\(seg(id))")
    }

    public func update(_ id: String, _ params: ConnectionUpdateParams) async throws -> Connection {
        try await client.request("PATCH", "/v1/connections/\(seg(id))", body: params)
    }

    /// Turn it back on: failures reset and it is tested again.
    public func enable(_ id: String) async throws -> Connection {
        try await update(id, .init(enabled: true))
    }

    public func disable(_ id: String) async throws -> Connection {
        try await update(id, .init(enabled: false))
    }

    /// 409 while an automation uses it.
    public func delete(_ id: String) async throws {
        try await client.requestVoid("DELETE", "/v1/connections/\(seg(id))")
    }

    public func test(_ id: String) async throws -> ConnectionTestResult {
        try await client.request("POST", "/v1/connections/\(seg(id))/test")
    }

    /// Check settings before saving: every permission tried for real.
    public func check(_ params: ConnectionCreateParams) async throws -> CheckReport {
        try await client.request("POST", "/v1/connections/check", body: params)
    }

    public func checkSaved(_ id: String) async throws -> CheckReport {
        try await client.request("POST", "/v1/connections/\(seg(id))/check")
    }

    public func browse(_ id: String, prefix: String? = nil, recursive: Bool = false) async throws -> [RemoteObject] {
        try await client.collection(
            "/v1/connections/\(seg(id))/browse",
            query: [("prefix", prefix?.isEmpty == false ? prefix : nil), ("recursive", recursive ? "true" : nil)],
            as: RemoteObject.self
        ).data
    }
}

public struct AutomationsResource: Sendable {
    let client: Transcdr

    public func list(_ params: ListParams = .init()) async throws -> ListResponse<Automation> {
        try await client.collection("/v1/automations", query: params.query)
    }

    public func all() -> Paginator<Automation> { client.pages("/v1/automations", query: [("limit", "100")]) }

    public func create(_ params: AutomationParams) async throws -> Automation {
        try await client.request("POST", "/v1/automations", body: params)
    }

    public func retrieve(_ id: String) async throws -> Automation {
        try await client.request("GET", "/v1/automations/\(seg(id))")
    }

    public func update(_ id: String, _ params: AutomationParams) async throws -> Automation {
        try await client.request("PATCH", "/v1/automations/\(seg(id))", body: params)
    }

    public func delete(_ id: String) async throws {
        try await client.requestVoid("DELETE", "/v1/automations/\(seg(id))")
    }

    /// Poll the source (watch) or read one batch from the queue (queue) now.
    public func run(_ id: String) async throws -> AutomationRun {
        try await client.request("POST", "/v1/automations/\(seg(id))/run")
    }

    /// Name objects to process.
    public func trigger(_ id: String, paths: [String]) async throws -> AutomationRun {
        struct Body: Encodable { let paths: [String] }
        return try await client.request("POST", "/v1/automations/\(seg(id))/trigger", body: Body(paths: paths))
    }

    public func rotateHookToken(_ id: String) async throws -> Automation {
        try await client.request("POST", "/v1/automations/\(seg(id))/rotate-hook-token")
    }

    /// Objects processed so far.
    public func items(_ id: String, _ params: ListParams = .init()) async throws -> [AutomationItem] {
        try await client.collection("/v1/automations/\(seg(id))/items", query: params.query, as: AutomationItem.self).data
    }
}

public struct DeliveriesResource: Sendable {
    let client: Transcdr

    public func retry(_ id: String) async throws -> Delivery {
        try await client.request("POST", "/v1/deliveries/\(seg(id))/retry")
    }
}

// MARK: - Operator console

public struct AdminResource: Sendable {
    let client: Transcdr

    public func overview() async throws -> AdminOverview {
        try await client.request("GET", "/v1/admin/overview")
    }

    public func jobs(status: JobStatus? = nil, _ params: ListParams = .init()) async throws -> ListResponse<AdminJob> {
        try await client.collection("/v1/admin/jobs", query: params.query + [("status", status?.rawValue)])
    }

    public func organizations(_ params: ListParams = .init()) async throws -> ListResponse<Organization> {
        try await client.collection("/v1/admin/organizations", query: params.query)
    }

    public func updateOrganization(_ id: String, _ params: AdminOrganizationUpdateParams) async throws -> Organization {
        try await client.request("PATCH", "/v1/admin/organizations/\(seg(id))", body: params)
    }
}
