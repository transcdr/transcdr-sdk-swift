import Foundation

// MARK: - Announcements

/// The changelog and service-credit notices, with what the signed-in user has seen.
public struct AnnouncementsResource: Sendable {
    let client: Transcdr

    /// Newest first. With `unseen`, service credits come before changelog
    /// entries. `limit` is 1–100 (default 20).
    public func list(unseen: Bool = false, kind: AnnouncementKind? = nil, limit: Int? = nil) async throws -> ListResponse<Announcement> {
        try await client.collection("/v1/announcements", query: [
            ("unseen", unseen ? "true" : nil),
            ("kind", kind?.rawValue),
            ("limit", limit.map(String.init)),
        ])
    }

    /// Record that the signed-in user has seen these. Idempotent; sessions only.
    public func markSeen(_ ids: [String]) async throws {
        guard !ids.isEmpty else { return }
        struct Body: Encodable { let ids: [String] }
        try await client.requestVoid("POST", "/v1/announcements/seen", body: Body(ids: ids))
    }

    /// Record every announcement as seen. Sessions only.
    public func markAllSeen() async throws {
        struct Body: Encodable { let all: Bool }
        try await client.requestVoid("POST", "/v1/announcements/seen", body: Body(all: true))
    }

    /// Published changelog entries (public, no `seen`).
    public func changelog(_ params: ListParams = .init()) async throws -> ListResponse<Announcement> {
        try await client.collection("/v1/changelog", query: params.query)
    }
}

// MARK: - Admin

extension AdminResource {
    /// Every announcement, drafts included.
    public func announcements(_ params: ListParams = .init()) async throws -> ListResponse<Announcement> {
        try await client.collection("/v1/admin/announcements", query: params.query)
    }

    /// Create a changelog entry. Published now unless `publishedAt` is set;
    /// `.some(nil)` saves a draft.
    public func createAnnouncement(_ params: AnnouncementParams) async throws -> Announcement {
        try await client.request("POST", "/v1/admin/announcements", body: params)
    }

    public func updateAnnouncement(_ id: String, _ params: AnnouncementParams) async throws -> Announcement {
        try await client.request("PATCH", "/v1/admin/announcements/\(seg(id))", body: params)
    }

    public func deleteAnnouncement(_ id: String) async throws {
        try await client.requestVoid("DELETE", "/v1/admin/announcements/\(seg(id))")
    }
}
