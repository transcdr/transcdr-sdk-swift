import Foundation

// The arithmetic behind the account screens (Overview, Billing, Usage, API
// keys, Pricing), kept here so it matches the web dashboard and is tested.

// MARK: - Money

extension Format {
    /// Whole dollars without cents when there are none: `5000` → `$50`, `4950` → `$49.50`.
    public static func wholeCents(_ cents: Int) -> String {
        cents % 100 == 0 ? currency(Double(cents) / 100, min: 0, max: 0) : Format.cents(cents)
    }

    /// A per-minute rate: `0.005` → `$0.005`, `0.01` → `$0.01`.
    public static func perMinute(_ dollars: Double) -> String {
        var text = String(format: "%.4f", dollars)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return "$" + text
    }

    /// A signed ledger amount: `+$10.00`, `−$0.0125`.
    public static func signedUsd(_ dollars: Double) -> String {
        let sign = dollars > 0 ? "+" : dollars < 0 ? "−" : ""
        return sign + usd(Swift.abs(dollars), precise: true)
    }

    /// A plan's top resolution: `1080p`, `4K (2160p)`, `8K (4320p)`.
    public static func maxResolution(_ shortSide: Int) -> String {
        if shortSide >= 4320 { return "8K (4320p)" }
        if shortSide >= 2160 { return "4K (2160p)" }
        return "\(shortSide)p"
    }
}

/// Dollar amounts typed into a field, sent as cents.
public enum DollarField {
    /// `"12.5"` → `1250`. Empty or not a number → nil.
    public static func cents(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "$", with: "")
        guard !trimmed.isEmpty, let value = Double(trimmed), value.isFinite, value >= 0 else { return nil }
        return Int((value * 100).rounded())
    }

    /// Cents shown in a field: `1000` → `"10"`, `1050` → `"10.5"`, nil → `""`.
    public static func text(_ cents: Int?) -> String {
        guard let cents else { return "" }
        if cents % 100 == 0 { return String(cents / 100) }
        var text = String(format: "%.2f", Double(cents) / 100)
        if text.hasSuffix("0") { text.removeLast() }
        return text
    }
}

// MARK: - Credit

public enum CreditTools {
    public struct Bucket: Hashable, Sendable, Identifiable {
        /// `plan`, `purchased` or `promo`.
        public let id: String
        public let label: String
        public let usd: Double
        public let note: String
    }

    /// The credit buckets, as the Billing page lists them. Promotional credit
    /// shows only when there is some, or it has an expiry.
    public static func buckets(_ account: CreditAccount) -> [Bucket] {
        guard let credit = account.credit else { return [] }
        var out = [
            Bucket(
                id: "plan", label: "Plan credit", usd: credit.planUsd,
                note: credit.planExpiresAt.map { "Renews \(Format.date($0)); does not roll over" } ?? "Comes with a subscription each month"
            ),
            Bucket(id: "purchased", label: "Bought credit", usd: credit.purchasedUsd, note: "Never expires"),
        ]
        if credit.promoUsd > 0 || credit.promoExpiresAt != nil {
            out.append(Bucket(
                id: "promo", label: "Trial & promotional", usd: credit.promoUsd,
                note: credit.promoExpiresAt.map { "Expires \(Format.date($0))" } ?? "No expiry"
            ))
        }
        return out
    }

    /// What the spend meter measures against: the monthly limit when one is
    /// set, otherwise what was spendable (spent plus still available).
    public static func spendCap(_ account: CreditAccount) -> Double {
        if let limit = account.monthlyLimitCents { return Double(limit) / 100 }
        return (account.thisMonth?.spentUsd ?? 0) + max(0, account.availableUsd)
    }

    /// This month's spend as a fraction of `spendCap` (0 when there is no cap).
    public static func spentFraction(_ account: CreditAccount) -> Double {
        let cap = spendCap(account)
        guard cap > 0 else { return 0 }
        return (account.thisMonth?.spentUsd ?? 0) / cap
    }

    /// Prepaid and under a dollar: new jobs are about to be refused.
    public static func isLow(_ account: CreditAccount) -> Bool {
        !account.isInvoiced && account.availableUsd < 1
    }

    /// Credit bought at a time: the quick amounts and the allowed range, in cents.
    public static let purchasePresets = [1000, 5000, 10_000, 50_000]
    public static let purchaseRange = 1000...1_000_000

    public static let kindLabels: [String: String] = [
        "trial": "Trial", "subscription": "Subscription", "purchase": "Purchase", "auto_recharge": "Auto-recharge",
        "usage": "Usage", "adjustment": "Adjustment", "expiry": "Expired", "service_credit": "Service credit",
    ]

    public static func kindLabel(_ kind: String) -> String {
        kindLabels[kind] ?? kind.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// Credit a statement added (its positive lines).
    public static func creditAdded(_ statement: Statement) -> Double {
        statement.lines.filter { $0.creditUsd > 0 }.reduce(0) { $0 + $1.creditUsd }
    }
}

// MARK: - Plans and the pricing calculator

public enum PlanTools {
    /// `$49` a month, or `Custom`.
    public static func perMonth(_ plan: Plan) -> String {
        plan.priceCents.map(Format.wholeCents) ?? "Custom"
    }

    /// HD output minutes that `cents` of credit buys.
    public static func hdMinutes(_ cents: Int, rates: RateCard?) -> Double {
        let hd = rates?.hd ?? Catalog.rates.hd
        return hd > 0 ? Double(cents) / 100 / hd : 0
    }

    /// Higher plans list only what they add to the plan below.
    static let includedIn: [PlanID: PlanID] = [.growth: .starter, .scale: .growth]

    public static func includedPlan(_ plan: Plan, in plans: [Plan]) -> Plan? {
        includedIn[plan.id].flatMap { id in plans.first { $0.id == id } }
    }

    /// The features a plan card lists: its own, less the plan it includes.
    public static func listedFeatures(_ plan: Plan, in plans: [Plan]) -> [String] {
        guard let parent = includedPlan(plan, in: plans) else { return plan.features }
        let inherited = Set(parent.features)
        return plan.features.filter { !inherited.contains($0) }
    }

    /// The hidden Unlimited plan: jobs are never refused for credit and cost
    /// nothing; minutes are still recorded.
    public static func isUnlimited(_ plan: Plan?) -> Bool {
        guard let plan else { return false }
        return plan.id == .unlimited || plan.features.contains("unlimited")
    }

    public static func isUnlimited(_ organization: Organization?) -> Bool {
        guard let organization else { return false }
        return organization.plan == .unlimited || isUnlimited(organization.planDetails)
    }

    /// Self-serve paid plans, in the order the pricing page shows them.
    public static func paidSelfServe(_ plans: [Plan]) -> [Plan] {
        plans.filter { $0.priceCents != nil && $0.id != .free }
    }
}

/// The pricing page's "Estimate your bill".
public enum PricingCalculator {
    public struct Rung: Hashable, Sendable, Identifiable {
        public let label: String
        public let shortSide: Int
        public var id: String { label }
        public var tier: Tier { Catalog.tier(forShortSide: shortSide) }
    }

    public static let rungs: [Rung] = [
        .init(label: "2160p", shortSide: 2160), .init(label: "1440p", shortSide: 1440),
        .init(label: "1080p", shortSide: 1080), .init(label: "720p", shortSide: 720),
        .init(label: "480p", shortSide: 480), .init(label: "360p", shortSide: 360),
    ]
    public static let defaultSelection: Set<String> = ["1080p", "720p", "480p", "360p"]

    public struct Option: Hashable, Sendable, Identifiable {
        public let plan: Plan
        /// The monthly fee plus credit bought beyond what the plan brings, in dollars.
        public let total: Double
        public let bought: Double
        /// The plan reaches the tallest rendition.
        public let fits: Bool
        public var id: PlanID { plan.id }
    }

    public static func minutes(sourceMinutes: Double, selected: Set<String>) -> MinutesByTier {
        var out = MinutesByTier()
        let source = max(0, sourceMinutes.isFinite ? sourceMinutes : 0)
        for rung in rungs where selected.contains(rung.label) { out.add(rung.tier, source) }
        return out
    }

    public static func tallest(_ selected: Set<String>) -> Int {
        rungs.filter { selected.contains($0.label) }.map(\.shortSide).max() ?? 0
    }

    /// What each ongoing plan costs a month for `usage` dollars of transcoding.
    /// Free is a one-time trial, so it is not an option.
    public static func options(plans: [Plan], usage: Double, tallest: Int) -> [Option] {
        PlanTools.paidSelfServe(plans).map { plan in
            let fee = Double(plan.priceCents ?? 0) / 100
            let bought = max(0, usage - Double(plan.monthlyCreditCents) / 100)
            return Option(plan: plan, total: fee + bought, bought: bought, fits: tallest <= plan.maxResolution)
        }
    }

    public static func cheapest(_ options: [Option]) -> Option? {
        options.filter(\.fits).reduce(nil as Option?) { best, o in
            guard let best else { return o }
            return o.total < best.total - 0.005 ? o : best
        }
    }

    /// A month like this fits inside the free trial's credit.
    public static func fitsTrial(_ trial: Plan?, usage: Double, tallest: Int) -> Bool {
        guard let trial else { return false }
        return usage > 0 && usage <= Double(trial.trialCreditCents) / 100 && tallest <= trial.maxResolution
    }
}

// MARK: - Usage

public enum UsageRange {
    /// The quick ranges: the last 7, 30 or 90 days.
    public static let presets = [7, 30, 90]

    /// The last `days` days up to today, daily (weekly past 60 days).
    public static func last(_ days: Int, now: Date = Date(), calendar: Calendar = .current) -> (from: Date, to: Date, granularity: Granularity) {
        let today = calendar.startOfDay(for: now)
        let from = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: today) ?? today
        return (from, today, days > 60 ? .week : .day)
    }

    /// The first day of this month.
    public static func monthStart(_ now: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
    }

    /// A series point's `YYYY-MM-DD` (or RFC 3339) date as a local date.
    public static func date(_ day: String, calendar: Calendar = .current) -> Date? {
        let parts = day.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

// MARK: - API keys

public enum KeyScopes {
    /// Turn a scope on or off. Write implies read, as the server treats it:
    /// adding a write adds its read; removing a read removes its write.
    public static func toggle(_ scope: String, on: Bool, in scopes: Set<String>) -> Set<String> {
        var out = scopes
        if on {
            out.insert(scope)
            if scope.hasSuffix(":write") { out.insert(scope.replacingOccurrences(of: ":write", with: ":read")) }
        } else {
            out.remove(scope)
            if scope.hasSuffix(":read") { out.remove(scope.replacingOccurrences(of: ":read", with: ":write")) }
        }
        return out
    }

    /// The scopes a restricted key starts with.
    public static let defaultRestricted: Set<String> = ["jobs:read", "jobs:write", "assets:read", "assets:write"]

    /// `Full access` or `3 scopes`.
    public static func summary(_ scopes: [String]) -> String {
        scopes.contains(Scope.wildcard) ? "Full access" : Format.pluralize(scopes.count, "scope")
    }

    /// The expiry choices, in days (nil: never).
    public static let expiryChoices: [Int?] = [nil, 30, 90, 365]

    public static func expiryLabel(_ days: Int?) -> String {
        switch days {
        case nil: return "Never"
        case 365: return "In 1 year"
        case let d?: return "In \(d) days"
        }
    }
}

// MARK: - Overview

public enum JobCounts {
    public struct Group: Hashable, Sendable, Identifiable {
        public let id: String
        public let label: String
        public let statuses: [JobStatus]
        public let count: Int
    }

    /// Jobs grouped the way the Overview's status card shows them.
    public static func groups(_ jobs: [Job]) -> [Group] {
        let defs: [(String, String, [JobStatus])] = [
            ("active", "In progress", [.queued, .scheduled, .running, .uploading]),
            ("completed", "Completed", [.completed]),
            ("failed", "Failed", [.failed]),
            ("canceled", "Canceled", [.canceled]),
        ]
        return defs.map { id, label, statuses in
            Group(id: id, label: label, statuses: statuses, count: jobs.filter { statuses.contains($0.status) }.count)
        }
    }

    /// `Good morning` before noon, `Good afternoon` before six, then `Good evening`.
    public static func greeting(hour: Int) -> String {
        hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
    }
}
