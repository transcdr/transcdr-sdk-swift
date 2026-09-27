import Foundation

public enum Scope {
    public static let all = [
        "jobs:read", "jobs:write", "assets:read", "assets:write", "presets:read", "presets:write",
        "webhooks:read", "webhooks:write", "usage:read", "billing:read", "billing:write", "keys:read",
        "keys:write", "org:read", "org:write", "connections:read", "connections:write",
        "automations:read", "automations:write",
    ]
    /// Every scope.
    public static let wildcard = "*"
}

public struct KeyMode: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let live: Self = "live"
    public static let test: Self = "test"
}

public struct APIKey: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var prefix: String
    public var scopes: [String]
    public var mode: KeyMode
    public var lastUsedAt: Date?
    public var expiresAt: Date?
    public var createdAt: Date
    /// Only present on create.
    public var secret: String?

    enum CodingKeys: String, CodingKey {
        case id, name, prefix, scopes, mode, secret
        case lastUsedAt = "last_used_at"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        prefix = try c.decodeIfPresent(String.self, forKey: .prefix) ?? ""
        scopes = try c.decodeList([String].self, forKey: .scopes)
        mode = try c.decodeIfPresent(KeyMode.self, forKey: .mode) ?? .live
        lastUsedAt = try c.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        secret = try c.decodeIfPresent(String.self, forKey: .secret)
    }
}

public struct APIKeyCreateParams: Encodable, Sendable {
    public var name: String
    public var scopes: [String]?
    public var mode: KeyMode?
    public var expiresAt: Date?

    public init(name: String, scopes: [String]? = nil, mode: KeyMode? = nil, expiresAt: Date? = nil) {
        self.name = name
        self.scopes = scopes
        self.mode = mode
        self.expiresAt = expiresAt
    }

    enum CodingKeys: String, CodingKey {
        case name, scopes, mode
        case expiresAt = "expires_at"
    }
}

public struct PlanID: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let free: Self = "free"
    public static let payAsYouGo: Self = "pay_as_you_go"
    public static let starter: Self = "starter"
    public static let growth: Self = "growth"
    public static let scale: Self = "scale"
    public static let enterprise: Self = "enterprise"
    public static let all: [Self] = [.free, .payAsYouGo, .starter, .growth, .scale, .enterprise]
    /// Bought as a monthly subscription through checkout.
    public static let subscriptions: [Self] = [.starter, .growth, .scale]
}

public struct Role: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let owner: Self = "owner"
    public static let admin: Self = "admin"
    public static let member: Self = "member"
    public static let all: [Self] = [.owner, .admin, .member]
}

public struct Organization: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var slug: String
    public var plan: PlanID
    public var billingEmail: String?
    /// Signs deliveries to per-job webhook URLs; owners and admins only.
    public var jobWebhookSecret: String?
    public var planDetails: Plan?
    public var suspended: Bool?
    public var createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, slug, plan, suspended
        case billingEmail = "billing_email"
        case jobWebhookSecret = "job_webhook_secret"
        case planDetails = "plan_details"
        case createdAt = "created_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // The operator console lists organizations with numeric ids.
        if let s = try? c.decode(String.self, forKey: .id) { id = s } else { id = String(try c.decode(Int.self, forKey: .id)) }
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        slug = try c.decodeIfPresent(String.self, forKey: .slug) ?? ""
        plan = try c.decodeIfPresent(PlanID.self, forKey: .plan) ?? .free
        billingEmail = try c.decodeIfPresent(String.self, forKey: .billingEmail)
        jobWebhookSecret = try c.decodeIfPresent(String.self, forKey: .jobWebhookSecret)
        planDetails = try? c.decodeIfPresent(Plan.self, forKey: .planDetails)
        suspended = try c.decodeIfPresent(Bool.self, forKey: .suspended)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
    }
}

public struct OrganizationUpdateParams: Encodable, Sendable {
    public var name: String?
    public var billingEmail: String?

    public init(name: String? = nil, billingEmail: String? = nil) {
        self.name = name
        self.billingEmail = billingEmail
    }

    enum CodingKeys: String, CodingKey {
        case name
        case billingEmail = "billing_email"
    }
}

public struct User: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var email: String
    public var role: Role
    public var organizationId: String?
    public var createdAt: Date?
    /// Platform operators see the operator console.
    public var isPlatformAdmin: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, email, role
        case organizationId = "organization_id"
        case createdAt = "created_at"
        case isPlatformAdmin = "is_platform_admin"
    }
}

public struct MemberCreateParams: Encodable, Sendable {
    public var name: String
    public var email: String
    public var role: Role
    public var password: String

    public init(name: String, email: String, role: Role, password: String) {
        self.name = name
        self.email = email
        self.role = role
        self.password = password
    }
}

public struct RegisterParams: Encodable, Sendable {
    public var name: String
    public var email: String
    public var password: String
    public var organizationName: String

    public init(name: String, email: String, password: String, organizationName: String) {
        self.name = name
        self.email = email
        self.password = password
        self.organizationName = organizationName
    }

    enum CodingKeys: String, CodingKey {
        case name, email, password
        case organizationName = "organization_name"
    }
}

public struct LoginParams: Encodable, Sendable {
    public var email: String
    public var password: String

    public init(email: String, password: String) {
        self.email = email
        self.password = password
    }
}

public struct ChangePasswordParams: Encodable, Sendable {
    public var currentPassword: String
    public var newPassword: String

    public init(currentPassword: String, newPassword: String) {
        self.currentPassword = currentPassword
        self.newPassword = newPassword
    }

    enum CodingKeys: String, CodingKey {
        case currentPassword = "current_password"
        case newPassword = "new_password"
    }
}

public struct AuthResponse: Codable, Sendable {
    public var token: String
    public var user: User
    public var organization: Organization
}

public struct Me: Codable, Sendable {
    /// Nil when authenticated with an API key.
    public var user: User?
    public var organization: Organization
    public var apiKey: APIKey?
    public var scopes: [String]
    /// False for test-mode keys.
    public var livemode: Bool?
    /// Platform operator.
    public var isPlatformAdmin: Bool?

    enum CodingKeys: String, CodingKey {
        case user, organization, scopes, livemode
        case apiKey = "api_key"
        case isPlatformAdmin = "is_platform_admin"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        user = try c.decodeIfPresent(User.self, forKey: .user)
        organization = try c.decode(Organization.self, forKey: .organization)
        apiKey = try? c.decodeIfPresent(APIKey.self, forKey: .apiKey)
        scopes = try c.decodeList([String].self, forKey: .scopes)
        livemode = try c.decodeIfPresent(Bool.self, forKey: .livemode)
        isPlatformAdmin = try c.decodeIfPresent(Bool.self, forKey: .isPlatformAdmin)
    }

    /// Whether the session may use `scope` (a `*` grants everything).
    public func can(_ scope: String) -> Bool {
        scopes.contains("*") || scopes.contains(scope)
    }

    /// Owner or admin.
    public var isManager: Bool {
        guard let role = user?.role else { return apiKey != nil && can("org:write") }
        return role == .owner || role == .admin
    }

    public var isOperator: Bool { isPlatformAdmin == true || user?.isPlatformAdmin == true }
}
