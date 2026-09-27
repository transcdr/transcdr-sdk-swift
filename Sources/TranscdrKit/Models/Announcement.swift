import Foundation

public struct AnnouncementKind: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let changelog: Self = "changelog"
    public static let serviceCredit: Self = "service_credit"
    public static let all: [Self] = [.changelog, .serviceCredit]
}

/// Where an announcement points. A `url` that is a path (`/app/…`, `/docs/…`)
/// is a page on the web dashboard.
public struct AnnouncementLink: Codable, Hashable, Sendable {
    public var label: String
    public var url: String

    public init(label: String, url: String) {
        self.label = label
        self.url = url
    }

    enum CodingKeys: String, CodingKey { case label, url }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
    }

    /// Whether `url` is a path on the dashboard rather than an absolute URL.
    public var isRelative: Bool { url.hasPrefix("/") }
}

/// What a service credit made good on: the incident, the amount, and the
/// jobs it covered.
public struct ServiceCredit: Codable, Hashable, Sendable {
    public var incidentId: String
    public var amountUsd: Double
    /// How many times the affected jobs' cost was credited.
    public var multiplier: Double?
    public var jobs: [String]
    public var appliedAt: Date?

    enum CodingKeys: String, CodingKey {
        case multiplier, jobs
        case incidentId = "incident_id"
        case amountUsd = "amount_usd"
        case appliedAt = "applied_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        incidentId = try c.decodeIfPresent(String.self, forKey: .incidentId) ?? ""
        amountUsd = try c.decodeIfPresent(Double.self, forKey: .amountUsd) ?? 0
        multiplier = try c.decodeIfPresent(Double.self, forKey: .multiplier)
        jobs = try c.decodeList([String].self, forKey: .jobs)
        appliedAt = try? c.decodeIfPresent(Date.self, forKey: .appliedAt)
    }
}

/// A changelog entry or a service-credit notice.
public struct Announcement: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var kind: AnnouncementKind
    public var title: String
    /// Markdown: bold, italics, code, links (paths are on the dashboard) and `-` lists.
    public var body: String
    /// Nil for a draft.
    public var publishedAt: Date?
    public var link: AnnouncementLink?
    /// Changelog entries only; may be empty.
    public var tags: [String]
    /// Service credits only.
    public var credit: ServiceCredit?
    /// Always false for API keys, which have no user to record it against.
    public var seen: Bool
    public var seenAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, kind, title, body, link, tags, credit, seen
        case publishedAt = "published_at"
        case seenAt = "seen_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decodeIfPresent(AnnouncementKind.self, forKey: .kind) ?? .changelog
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        publishedAt = try? c.decodeIfPresent(Date.self, forKey: .publishedAt)
        link = (try? c.decodeIfPresent(AnnouncementLink.self, forKey: .link)).flatMap { $0.url.isEmpty ? nil : $0 }
        tags = (try? c.decodeList([String].self, forKey: .tags)) ?? []
        credit = try? c.decodeIfPresent(ServiceCredit.self, forKey: .credit)
        seen = try c.decodeIfPresent(Bool.self, forKey: .seen) ?? false
        seenAt = try? c.decodeIfPresent(Date.self, forKey: .seenAt)
    }

    public var isServiceCredit: Bool { kind == .serviceCredit }
    public var isDraft: Bool { publishedAt == nil }
}

/// Create or update a changelog entry (operators).
public struct AnnouncementParams: Encodable, Sendable {
    public var title: String?
    public var body: String?
    /// `.some(nil)` removes the link.
    public var link: AnnouncementLink??
    public var tags: [String]?
    /// Left out: now on create, unchanged on update. `.some(nil)` saves a draft.
    public var publishedAt: Date??

    public init(title: String? = nil, body: String? = nil, link: AnnouncementLink?? = nil, tags: [String]? = nil, publishedAt: Date?? = nil) {
        self.title = title
        self.body = body
        self.link = link
        self.tags = tags
        self.publishedAt = publishedAt
    }

    enum CodingKeys: String, CodingKey {
        case title, body, link, tags
        case publishedAt = "published_at"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(body, forKey: .body)
        if let link {
            if let link { try c.encode(link, forKey: .link) } else { try c.encodeNil(forKey: .link) }
        }
        try c.encodeIfPresent(tags, forKey: .tags)
        if let publishedAt {
            if let publishedAt { try c.encode(publishedAt, forKey: .publishedAt) } else { try c.encodeNil(forKey: .publishedAt) }
        }
    }
}
