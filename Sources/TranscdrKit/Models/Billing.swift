import Foundation

public struct Granularity: OpenEnum {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let day: Self = "day"
    public static let week: Self = "week"
    public static let month: Self = "month"
    public static let all: [Self] = [.day, .week, .month]
}

public struct UsagePoint: Codable, Hashable, Sendable, Identifiable {
    public var date: String
    public var jobs: Int
    public var billableMinutes: Double
    /// Output images billed; 0 from a server without image output.
    public var billableImages: Int
    public var amountCents: Int
    public var amountUsd: Double

    public var id: String { date }

    enum CodingKeys: String, CodingKey {
        case date, jobs
        case billableMinutes = "billable_minutes"
        case billableImages = "billable_images"
        case amountCents = "amount_cents"
        case amountUsd = "amount_usd"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        jobs = try c.decodeIfPresent(Int.self, forKey: .jobs) ?? 0
        billableMinutes = try c.decodeIfPresent(Double.self, forKey: .billableMinutes) ?? 0
        billableImages = try c.decodeIfPresent(Int.self, forKey: .billableImages) ?? 0
        amountCents = try c.decodeIfPresent(Int.self, forKey: .amountCents) ?? 0
        amountUsd = try c.decodeIfPresent(Double.self, forKey: .amountUsd) ?? Double(amountCents) / 100
    }
}

public struct Usage: Codable, Hashable, Sendable {
    public struct Totals: Codable, Hashable, Sendable {
        public var jobs: Int
        public var billableMinutes: Double
        /// Output images billed; 0 from a server without image output.
        public var billableImages: Int
        public var inputMinutes: Double
        public var outputBytes: Int64
        public var amountCents: Int
        public var amountUsd: Double

        enum CodingKeys: String, CodingKey {
            case jobs
            case billableMinutes = "billable_minutes"
            case billableImages = "billable_images"
            case inputMinutes = "input_minutes"
            case outputBytes = "output_bytes"
            case amountCents = "amount_cents"
            case amountUsd = "amount_usd"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            jobs = try c.decodeIfPresent(Int.self, forKey: .jobs) ?? 0
            billableMinutes = try c.decodeIfPresent(Double.self, forKey: .billableMinutes) ?? 0
            billableImages = try c.decodeIfPresent(Int.self, forKey: .billableImages) ?? 0
            inputMinutes = try c.decodeIfPresent(Double.self, forKey: .inputMinutes) ?? 0
            outputBytes = try c.decodeIfPresent(Int64.self, forKey: .outputBytes) ?? 0
            amountCents = try c.decodeIfPresent(Int.self, forKey: .amountCents) ?? 0
            amountUsd = try c.decodeIfPresent(Double.self, forKey: .amountUsd) ?? Double(amountCents) / 100
        }
    }

    public var from: String
    public var to: String
    public var granularity: Granularity
    public var totals: Totals
    /// Billable minutes per tier (`sd`, `hd`, `uhd`).
    public var byTier: [String: Double]
    /// Output images billed per image tier (`up_to_1mp`, `up_to_4mp`, `over_4mp`); empty from
    /// a server without image output.
    public var byImageTier: [String: Int]
    /// Billable minutes per codec (image jobs are not counted here).
    public var byCodec: [String: Double]
    public var series: [UsagePoint]

    enum CodingKeys: String, CodingKey {
        case from, to, granularity, totals, series
        case byTier = "by_tier"
        case byImageTier = "by_image_tier"
        case byCodec = "by_codec"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        from = try c.decodeIfPresent(String.self, forKey: .from) ?? ""
        to = try c.decodeIfPresent(String.self, forKey: .to) ?? ""
        granularity = try c.decodeIfPresent(Granularity.self, forKey: .granularity) ?? .day
        totals = try c.decode(Totals.self, forKey: .totals)
        byTier = try c.decodeMap([String: Double].self, forKey: .byTier)
        byImageTier = try c.decodeMap([String: Int].self, forKey: .byImageTier)
        byCodec = try c.decodeMap([String: Double].self, forKey: .byCodec)
        series = try c.decodeList([UsagePoint].self, forKey: .series)
    }
}

/// Price per output minute, in dollars: the same for every plan and codec.
public struct RateCard: Codable, Hashable, Sendable {
    public var sd: Double
    public var hd: Double
    public var uhd: Double
    /// What each tier covers, e.g. `"577p to 1440p"`.
    public var tiers: [String: String]

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sd = try c.decodeIfPresent(Double.self, forKey: .sd) ?? 0
        hd = try c.decodeIfPresent(Double.self, forKey: .hd) ?? 0
        uhd = try c.decodeIfPresent(Double.self, forKey: .uhd) ?? 0
        tiers = try c.decodeMap([String: String].self, forKey: .tiers)
    }

    enum CodingKeys: String, CodingKey { case sd, hd, uhd, tiers }

    public func rate(for tier: Tier) -> Double {
        switch tier {
        case .sd: return sd
        case .uhd: return uhd
        default: return hd
        }
    }
}

/// Price per output image, in dollars, by the pixels it came out at.
public struct ImageRateCard: Codable, Hashable, Sendable {
    public var upTo1mp: Double
    public var upTo4mp: Double
    public var over4mp: Double
    /// What each tier covers, e.g. `"up to 1 megapixel"`.
    public var tiers: [String: String]

    enum CodingKeys: String, CodingKey {
        case tiers
        case upTo1mp = "up_to_1mp"
        case upTo4mp = "up_to_4mp"
        case over4mp = "over_4mp"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        upTo1mp = try c.decodeIfPresent(Double.self, forKey: .upTo1mp) ?? 0
        upTo4mp = try c.decodeIfPresent(Double.self, forKey: .upTo4mp) ?? 0
        over4mp = try c.decodeIfPresent(Double.self, forKey: .over4mp) ?? 0
        tiers = try c.decodeMap([String: String].self, forKey: .tiers)
    }

    public func rate(for tier: Tier) -> Double {
        switch tier {
        case .upTo1mp: return upTo1mp
        case .upTo4mp: return upTo4mp
        default: return over4mp
        }
    }
}

public struct Plan: Codable, Hashable, Sendable, Identifiable {
    public var id: PlanID
    public var name: String
    public var tagline: String?
    public var subscription: Bool
    /// Monthly price; nil means "contact us".
    public var priceCents: Int?
    public var monthlyCreditCents: Int
    public var creditValueRatio: Double?
    public var trialCreditCents: Int
    public var trialDays: Int
    public var rates: RateCard?
    /// Image output prices; nil from a server without image output.
    public var imageRates: ImageRateCard?
    public var maxConcurrentJobs: Int
    public var maxResolution: Int
    public var maxInputBytes: Int64?
    public var priority: Bool
    public var retentionDays: Int
    public var requestsPerMinute: Int?
    public var features: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, tagline, subscription, rates, priority, features
        case priceCents = "price_cents"
        case imageRates = "image_rates"
        case monthlyCreditCents = "monthly_credit_cents"
        case creditValueRatio = "credit_value_ratio"
        case trialCreditCents = "trial_credit_cents"
        case trialDays = "trial_days"
        case maxConcurrentJobs = "max_concurrent_jobs"
        case maxResolution = "max_resolution"
        case maxInputBytes = "max_input_bytes"
        case retentionDays = "retention_days"
        case requestsPerMinute = "requests_per_minute"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(PlanID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id.rawValue
        tagline = try c.decodeIfPresent(String.self, forKey: .tagline)
        subscription = try c.decodeIfPresent(Bool.self, forKey: .subscription) ?? false
        priceCents = try c.decodeIfPresent(Int.self, forKey: .priceCents)
        monthlyCreditCents = try c.decodeIfPresent(Int.self, forKey: .monthlyCreditCents) ?? 0
        creditValueRatio = try c.decodeIfPresent(Double.self, forKey: .creditValueRatio)
        trialCreditCents = try c.decodeIfPresent(Int.self, forKey: .trialCreditCents) ?? 0
        trialDays = try c.decodeIfPresent(Int.self, forKey: .trialDays) ?? 0
        rates = try? c.decodeIfPresent(RateCard.self, forKey: .rates)
        imageRates = try? c.decodeIfPresent(ImageRateCard.self, forKey: .imageRates)
        maxConcurrentJobs = try c.decodeIfPresent(Int.self, forKey: .maxConcurrentJobs) ?? 1
        maxResolution = try c.decodeIfPresent(Int.self, forKey: .maxResolution) ?? 1080
        maxInputBytes = try c.decodeIfPresent(Int64.self, forKey: .maxInputBytes)
        priority = try c.decodeIfPresent(Bool.self, forKey: .priority) ?? false
        retentionDays = try c.decodeIfPresent(Int.self, forKey: .retentionDays) ?? 0
        requestsPerMinute = try c.decodeIfPresent(Int.self, forKey: .requestsPerMinute)
        features = try c.decodeList([String].self, forKey: .features)
    }
}

public struct AutoRecharge: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var thresholdCents: Int
    public var amountCents: Int
    /// Nil for no cap.
    public var monthlyCapCents: Int?
    public var pending: Bool
    public var lastError: String?

    enum CodingKeys: String, CodingKey {
        case enabled, pending
        case thresholdCents = "threshold_cents"
        case amountCents = "amount_cents"
        case monthlyCapCents = "monthly_cap_cents"
        case lastError = "last_error"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        thresholdCents = try c.decodeIfPresent(Int.self, forKey: .thresholdCents) ?? 0
        amountCents = try c.decodeIfPresent(Int.self, forKey: .amountCents) ?? 0
        monthlyCapCents = try c.decodeIfPresent(Int.self, forKey: .monthlyCapCents)
        pending = try c.decodeIfPresent(Bool.self, forKey: .pending) ?? false
        lastError = try c.decodeIfPresent(String.self, forKey: .lastError)
    }
}

public struct CreditAccount: Codable, Hashable, Sendable {
    public struct Credit: Codable, Hashable, Sendable {
        public var planUsd: Double
        public var planExpiresAt: Date?
        public var purchasedUsd: Double
        public var promoUsd: Double
        public var promoExpiresAt: Date?

        enum CodingKeys: String, CodingKey {
            case planUsd = "plan_usd"
            case planExpiresAt = "plan_expires_at"
            case purchasedUsd = "purchased_usd"
            case promoUsd = "promo_usd"
            case promoExpiresAt = "promo_expires_at"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            planUsd = try c.decodeIfPresent(Double.self, forKey: .planUsd) ?? 0
            planExpiresAt = try c.decodeIfPresent(Date.self, forKey: .planExpiresAt)
            purchasedUsd = try c.decodeIfPresent(Double.self, forKey: .purchasedUsd) ?? 0
            promoUsd = try c.decodeIfPresent(Double.self, forKey: .promoUsd) ?? 0
            promoExpiresAt = try c.decodeIfPresent(Date.self, forKey: .promoExpiresAt)
        }
    }

    public struct Month: Codable, Hashable, Sendable {
        public var period: String
        public var spentUsd: Double
        public var autoRechargedUsd: Double

        enum CodingKeys: String, CodingKey {
            case period
            case spentUsd = "spent_usd"
            case autoRechargedUsd = "auto_recharged_usd"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            period = try c.decodeIfPresent(String.self, forKey: .period) ?? ""
            spentUsd = try c.decodeIfPresent(Double.self, forKey: .spentUsd) ?? 0
            autoRechargedUsd = try c.decodeIfPresent(Double.self, forKey: .autoRechargedUsd) ?? 0
        }
    }

    public struct Subscription: Codable, Hashable, Sendable {
        public var status: String?
        public var currentPeriodEnd: Date?
        public var cancelAtPeriodEnd: Bool

        enum CodingKeys: String, CodingKey {
            case status
            case currentPeriodEnd = "current_period_end"
            case cancelAtPeriodEnd = "cancel_at_period_end"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            status = try c.decodeIfPresent(String.self, forKey: .status)
            currentPeriodEnd = try c.decodeIfPresent(Date.self, forKey: .currentPeriodEnd)
            cancelAtPeriodEnd = try c.decodeIfPresent(Bool.self, forKey: .cancelAtPeriodEnd) ?? false
        }
    }

    /// `prepaid` or `invoiced`.
    public var mode: String
    /// What new jobs can spend: the balance minus reservations.
    public var availableUsd: Double
    public var balanceUsd: Double
    public var reservedUsd: Double
    public var credit: Credit?
    public var thisMonth: Month?
    public var monthlyLimitCents: Int?
    public var autoRecharge: AutoRecharge?
    public var subscription: Subscription?
    /// e.g. `"Visa •••• 4242"`.
    public var paymentMethod: String?

    enum CodingKeys: String, CodingKey {
        case mode, credit, subscription
        case availableUsd = "available_usd"
        case balanceUsd = "balance_usd"
        case reservedUsd = "reserved_usd"
        case thisMonth = "this_month"
        case monthlyLimitCents = "monthly_limit_cents"
        case autoRecharge = "auto_recharge"
        case paymentMethod = "payment_method"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? "prepaid"
        availableUsd = try c.decodeIfPresent(Double.self, forKey: .availableUsd) ?? 0
        balanceUsd = try c.decodeIfPresent(Double.self, forKey: .balanceUsd) ?? 0
        reservedUsd = try c.decodeIfPresent(Double.self, forKey: .reservedUsd) ?? 0
        credit = try c.decodeIfPresent(Credit.self, forKey: .credit)
        thisMonth = try c.decodeIfPresent(Month.self, forKey: .thisMonth)
        monthlyLimitCents = try c.decodeIfPresent(Int.self, forKey: .monthlyLimitCents)
        autoRecharge = try c.decodeIfPresent(AutoRecharge.self, forKey: .autoRecharge)
        subscription = try c.decodeIfPresent(Subscription.self, forKey: .subscription)
        paymentMethod = try c.decodeIfPresent(String.self, forKey: .paymentMethod)
    }

    public var isInvoiced: Bool { mode == "invoiced" }
}

public struct Billing: Codable, Hashable, Sendable {
    public var plan: Plan
    public var rates: RateCard?
    /// Image output prices; nil from a server without image output.
    public var imageRates: ImageRateCard?
    public var account: CreditAccount
    public var period: String
    public var periodStart: Date?
    public var periodEnd: Date?
    public var usageMinutes: Double
    /// Output images billed this period.
    public var usageImages: Int
    public var usageUsd: Double
    /// False when this installation takes no payments.
    public var paymentsEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case plan, rates, account, period
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case imageRates = "image_rates"
        case usageMinutes = "usage_minutes"
        case usageImages = "usage_images"
        case usageUsd = "usage_usd"
        case paymentsEnabled = "payments_enabled"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        plan = try c.decode(Plan.self, forKey: .plan)
        rates = try? c.decodeIfPresent(RateCard.self, forKey: .rates)
        imageRates = try? c.decodeIfPresent(ImageRateCard.self, forKey: .imageRates)
        account = try c.decode(CreditAccount.self, forKey: .account)
        period = try c.decodeIfPresent(String.self, forKey: .period) ?? ""
        periodStart = try c.decodeIfPresent(Date.self, forKey: .periodStart)
        periodEnd = try c.decodeIfPresent(Date.self, forKey: .periodEnd)
        usageMinutes = try c.decodeIfPresent(Double.self, forKey: .usageMinutes) ?? 0
        usageImages = try c.decodeIfPresent(Int.self, forKey: .usageImages) ?? 0
        usageUsd = try c.decodeIfPresent(Double.self, forKey: .usageUsd) ?? 0
        paymentsEnabled = try c.decodeIfPresent(Bool.self, forKey: .paymentsEnabled) ?? true
    }
}

/// `plan` subscribes (or moves a subscription); `creditCents` buys credit.
public enum CheckoutParams: Encodable, Sendable {
    case plan(PlanID)
    case credit(cents: Int)

    enum CodingKeys: String, CodingKey {
        case plan
        case creditCents = "credit_cents"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .plan(let id): try c.encode(id, forKey: .plan)
        case .credit(let cents): try c.encode(cents, forKey: .creditCents)
        }
    }
}

public struct Checkout: Codable, Hashable, Sendable {
    /// Send the customer here to pay; nil when nothing needs paying.
    public var url: String?
    /// An existing subscription moved to another plan in place.
    public var changed: Bool
    public var plan: PlanID?

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        changed = try c.decodeIfPresent(Bool.self, forKey: .changed) ?? false
        plan = try c.decodeIfPresent(PlanID.self, forKey: .plan)
    }

    enum CodingKeys: String, CodingKey { case url, changed, plan }
}

public struct Portal: Codable, Hashable, Sendable {
    public var url: String
}

public struct AutoRechargeParams: Encodable, Sendable, Hashable {
    public var enabled: Bool?
    public var thresholdCents: Int?
    /// $10 to $10,000.
    public var amountCents: Int?
    /// `.some(nil)` removes the cap.
    public var monthlyCapCents: Int??

    public init(enabled: Bool? = nil, thresholdCents: Int? = nil, amountCents: Int? = nil, monthlyCapCents: Int?? = nil) {
        self.enabled = enabled
        self.thresholdCents = thresholdCents
        self.amountCents = amountCents
        self.monthlyCapCents = monthlyCapCents
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case thresholdCents = "threshold_cents"
        case amountCents = "amount_cents"
        case monthlyCapCents = "monthly_cap_cents"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(enabled, forKey: .enabled)
        try c.encodeIfPresent(thresholdCents, forKey: .thresholdCents)
        try c.encodeIfPresent(amountCents, forKey: .amountCents)
        if let cap = monthlyCapCents {
            if let cap { try c.encode(cap, forKey: .monthlyCapCents) } else { try c.encodeNil(forKey: .monthlyCapCents) }
        }
    }
}

public struct BillingSettingsParams: Encodable, Sendable {
    /// `.some(nil)` clears the limit.
    public var monthlyLimitCents: Int??
    public var autoRecharge: AutoRechargeParams?

    public init(monthlyLimitCents: Int?? = nil, autoRecharge: AutoRechargeParams? = nil) {
        self.monthlyLimitCents = monthlyLimitCents
        self.autoRecharge = autoRecharge
    }

    enum CodingKeys: String, CodingKey {
        case monthlyLimitCents = "monthly_limit_cents"
        case autoRecharge = "auto_recharge"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let limit = monthlyLimitCents {
            if let limit { try c.encode(limit, forKey: .monthlyLimitCents) } else { try c.encodeNil(forKey: .monthlyLimitCents) }
        }
        try c.encodeIfPresent(autoRecharge, forKey: .autoRecharge)
    }
}

public struct CreditTransaction: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    /// `trial`, `subscription`, `purchase`, `auto_recharge`, `usage`, `adjustment`, `expiry`, `service_credit`.
    public var kind: String
    /// `promo`, `plan`, `purchased`, or `mixed`.
    public var bucket: String
    /// Positive adds credit, negative spends it.
    public var amountUsd: Double
    public var description: String
    public var jobId: String?
    public var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, kind, bucket, description
        case amountUsd = "amount_usd"
        case jobId = "job_id"
        case createdAt = "created_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        bucket = try c.decodeIfPresent(String.self, forKey: .bucket) ?? ""
        amountUsd = try c.decodeIfPresent(Double.self, forKey: .amountUsd) ?? 0
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        jobId = try c.decodeIfPresent(String.self, forKey: .jobId)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }
}

public struct StatementLine: Codable, Hashable, Sendable {
    public var description: String
    public var kind: String
    public var creditUsd: Double
    public var date: Date?
    public var quantity: Double?
    /// `output_minute` or `output_image`.
    public var unit: String?

    enum CodingKeys: String, CodingKey {
        case description, kind, date, quantity, unit
        case creditUsd = "credit_usd"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        creditUsd = try c.decodeIfPresent(Double.self, forKey: .creditUsd) ?? 0
        date = try c.decodeIfPresent(Date.self, forKey: .date)
        quantity = try c.decodeIfPresent(Double.self, forKey: .quantity)
        unit = try c.decodeIfPresent(String.self, forKey: .unit)
    }
}

/// A monthly statement: credit added and the usage drawn from it.
public struct Statement: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var period: String
    public var periodStart: Date?
    public var periodEnd: Date?
    /// `open` or `closed`.
    public var status: String
    public var lines: [StatementLine]
    public var usageMinutes: Double
    /// Output images billed this period.
    public var usageImages: Int
    public var usageCents: Int

    enum CodingKeys: String, CodingKey {
        case id, period, status, lines
        case periodStart = "period_start"
        case periodEnd = "period_end"
        case usageMinutes = "usage_minutes"
        case usageImages = "usage_images"
        case usageCents = "usage_cents"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        period = try c.decodeIfPresent(String.self, forKey: .period) ?? ""
        periodStart = try c.decodeIfPresent(Date.self, forKey: .periodStart)
        periodEnd = try c.decodeIfPresent(Date.self, forKey: .periodEnd)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "open"
        lines = try c.decodeList([StatementLine].self, forKey: .lines)
        usageMinutes = try c.decodeIfPresent(Double.self, forKey: .usageMinutes) ?? 0
        usageImages = try c.decodeIfPresent(Int.self, forKey: .usageImages) ?? 0
        usageCents = try c.decodeIfPresent(Int.self, forKey: .usageCents) ?? 0
    }
}

// MARK: - Public service info

public struct CodecInfo: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var bitDepths: [Int]
    public var hdr: Bool
    public var isDefault: Bool
    public var royaltyFree: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, hdr
        case bitDepths = "bit_depths"
        case isDefault = "default"
        case royaltyFree = "royalty_free"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id.uppercased()
        bitDepths = try c.decodeList([Int].self, forKey: .bitDepths)
        hdr = try c.decodeIfPresent(Bool.self, forKey: .hdr) ?? false
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        royaltyFree = try c.decodeIfPresent(Bool.self, forKey: .royaltyFree) ?? false
    }
}

public struct ModeInfo: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var description: String
}

/// An image output format the service offers.
public struct ImageFormatInfo: Codable, Hashable, Sendable, Identifiable {
    public var id: ImageFormat
    public var name: String
    public var isDefault: Bool
    /// Takes `ImageSettings.quality`.
    public var lossy: Bool
    /// Can be lossless (PNG always, WebP with `ImageSettings.lossless`).
    public var lossless: Bool
    /// Keeps transparency.
    public var alpha: Bool
    /// The quality a v1 request without one was given; lossy formats only. A v2 spec states
    /// its own (`ImageSettings.quality`).
    public var defaultQuality: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, lossy, lossless, alpha
        case isDefault = "default"
        case defaultQuality = "default_quality"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(ImageFormat.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id.rawValue.uppercased()
        isDefault = try c.decodeIfPresent(Bool.self, forKey: .isDefault) ?? false
        lossy = try c.decodeIfPresent(Bool.self, forKey: .lossy) ?? false
        lossless = try c.decodeIfPresent(Bool.self, forKey: .lossless) ?? false
        alpha = try c.decodeIfPresent(Bool.self, forKey: .alpha) ?? false
        defaultQuality = try c.decodeIfPresent(Int.self, forKey: .defaultQuality)
    }
}

/// Image output limits (`limits.image`).
public struct ImageLimits: Codable, Hashable, Sendable {
    /// The smallest rendition side.
    public var minDimension: Int
    /// The largest rendition side.
    public var maxDimension: Int
    /// The most files one job may make: stills × renditions × formats.
    public var maxOutputs: Int
    /// The most stills one video may give.
    public var maxFrames: Int
    /// The largest image input.
    public var maxInputMegapixels: Double

    enum CodingKeys: String, CodingKey {
        case minDimension = "min_dimension"
        case maxDimension = "max_dimension"
        case maxOutputs = "max_outputs"
        case maxFrames = "max_frames"
        case maxInputMegapixels = "max_input_megapixels"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        minDimension = try c.decodeIfPresent(Int.self, forKey: .minDimension) ?? 16
        maxDimension = try c.decodeIfPresent(Int.self, forKey: .maxDimension) ?? 8192
        maxOutputs = try c.decodeIfPresent(Int.self, forKey: .maxOutputs) ?? 200
        maxFrames = try c.decodeIfPresent(Int.self, forKey: .maxFrames) ?? 100
        maxInputMegapixels = try c.decodeIfPresent(Double.self, forKey: .maxInputMegapixels) ?? 100
    }
}

/// What the service can do: codecs, modes, filters, limits and the system presets.
public struct Capabilities: Codable, Sendable {
    public var codecs: [CodecInfo]
    public var modes: [ModeInfo]
    public var audio: [String]
    public var bitDepth: [String]
    public var color: [String]
    public var filters: [String]
    public var qualityTargets: [String]
    public var inputContainers: [String]
    public var inputVideoCodecs: [String]
    public var inputAudioCodecs: [String]
    /// Image output formats; empty when image output is unavailable or the server predates it.
    public var imageFormats: [ImageFormatInfo]
    /// Image inputs read: `jpeg`, `png`, `webp`, `avif`, `gif` (first frame), `tiff`, `bmp`, `heic`.
    public var inputImageFormats: [String]
    public var limits: [String: JSONValue]
    public var systemPresets: [Preset]
    /// The output spec (v2) as data: every field, when it is required, what it takes. Nil from
    /// a server that predates it.
    public var output: OutputCapabilities?

    /// `limits.image`; nil when the service does not list it.
    public var imageLimits: ImageLimits? { try? limits["image"]?.decode(as: ImageLimits.self) }

    enum CodingKeys: String, CodingKey {
        case codecs, modes, audio, color, filters, limits, output
        case imageFormats = "image_formats"
        case inputImageFormats = "input_image_formats"
        case bitDepth = "bit_depth"
        case qualityTargets = "quality_targets"
        case inputContainers = "input_containers"
        case inputVideoCodecs = "input_video_codecs"
        case inputAudioCodecs = "input_audio_codecs"
        case systemPresets = "system_presets"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        codecs = (try? c.decodeList([CodecInfo].self, forKey: .codecs)) ?? []
        modes = (try? c.decodeList([ModeInfo].self, forKey: .modes)) ?? []
        audio = (try? c.decodeList([String].self, forKey: .audio)) ?? []
        bitDepth = (try? c.decodeList([String].self, forKey: .bitDepth)) ?? []
        color = (try? c.decodeList([String].self, forKey: .color)) ?? []
        filters = (try? c.decodeList([String].self, forKey: .filters)) ?? []
        qualityTargets = (try? c.decodeList([String].self, forKey: .qualityTargets)) ?? []
        inputContainers = (try? c.decodeList([String].self, forKey: .inputContainers)) ?? []
        inputVideoCodecs = (try? c.decodeList([String].self, forKey: .inputVideoCodecs)) ?? []
        inputAudioCodecs = (try? c.decodeList([String].self, forKey: .inputAudioCodecs)) ?? []
        imageFormats = (try? c.decodeList([ImageFormatInfo].self, forKey: .imageFormats)) ?? []
        inputImageFormats = (try? c.decodeList([String].self, forKey: .inputImageFormats)) ?? []
        limits = (try? c.decodeMap([String: JSONValue].self, forKey: .limits)) ?? [:]
        systemPresets = (try? c.decodeList([Preset].self, forKey: .systemPresets)) ?? []
        output = try? c.decodeIfPresent(OutputCapabilities.self, forKey: .output)
    }
}

/// `capabilities.output`: the v2 output spec described as data, for checking a spec's
/// completeness generically. `OutputRules` holds a copy of the same table.
public struct OutputCapabilities: Codable, Hashable, Sendable {
    /// 2.
    public var version: Int
    public var kinds: [OutputKind]
    public var fields: [OutputField]
    public var groups: [OutputGroup]
    /// How to read `when`.
    public var conditions: String?
    public var containers: [ContainerInfo]
    public var audioCodecs: [AudioCodecInfo]
    /// What each value that follows the source resolves to, keyed `path: value`.
    public var followValues: [String: String]
    public var compatibility: OutputCompatibility?

    enum CodingKeys: String, CodingKey {
        case version, kinds, fields, groups, conditions, containers, compatibility
        case audioCodecs = "audio_codecs"
        case followValues = "follow_values"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 2
        kinds = try c.decodeList([OutputKind].self, forKey: .kinds)
        fields = try c.decodeList([OutputField].self, forKey: .fields)
        groups = try c.decodeList([OutputGroup].self, forKey: .groups)
        conditions = try c.decodeIfPresent(String.self, forKey: .conditions)
        containers = try c.decodeList([ContainerInfo].self, forKey: .containers)
        audioCodecs = try c.decodeList([AudioCodecInfo].self, forKey: .audioCodecs)
        followValues = try c.decodeMap([String: String].self, forKey: .followValues)
        compatibility = try c.decodeIfPresent(OutputCompatibility.self, forKey: .compatibility)
    }

    /// One field: needed (or, when `required` is false, allowed) when any object in `when`
    /// matches; an object matches when every path in it has one of the listed values (`"*"`:
    /// present, `"!"`: absent). Outside `when` it is refused.
    public struct OutputField: Codable, Hashable, Sendable {
        /// Relative to `output`; `[]` stands for each entry of a list.
        public var path: String
        public var required: Bool
        public var when: [[String: [String]]]
        /// The value's shape: `{"type": "enum", "values": [...]}`, `{"type": "number", "min": …}`, …
        public var shape: JSONValue
        /// Its exclusive group, if it is one of several choices.
        public var group: String?
        public var description: String?
    }

    /// Choices of which exactly one is given whenever `when` holds.
    public struct OutputGroup: Codable, Hashable, Sendable {
        public var name: String
        public var members: [String]
        public var when: [[String: [String]]]
        public var exactlyOne: Bool

        enum CodingKeys: String, CodingKey {
            case name, members, when
            case exactlyOne = "exactly_one"
        }
    }

    /// A container format, its kind and the audio codecs it holds.
    public struct ContainerInfo: Codable, Hashable, Sendable, Identifiable {
        public var id: ContainerFormat
        public var kind: OutputKind
        public var audioCodecs: [AudioCodec]

        enum CodingKeys: String, CodingKey {
            case id, kind
            case audioCodecs = "audio_codecs"
        }
    }

    public struct AudioCodecInfo: Codable, Hashable, Sendable, Identifiable {
        public var id: AudioCodec
        public var name: String
        public var lossless: Bool
        public var maxChannels: Int
        /// The fixed rates, for a codec that has them (MP3).
        public var bitrates: [String]?

        enum CodingKeys: String, CodingKey {
            case id, name, lossless, bitrates
            case maxChannels = "max_channels"
        }
    }

    /// How clients still on the v1 shape are served.
    public struct OutputCompatibility: Codable, Hashable, Sendable {
        public var v1Requests: String?
        public var v1Responses: V1Responses?

        /// The header (`Transcdr-Output-Spec: v1`) or query (`output_spec=v1`, GET) that asks for
        /// v1 responses, and when that mode goes.
        public struct V1Responses: Codable, Hashable, Sendable {
            public var header: String
            public var value: String
            public var query: String?
            public var sunset: String?
        }

        enum CodingKeys: String, CodingKey {
            case v1Requests = "v1_requests"
            case v1Responses = "v1_responses"
        }
    }
}

public struct ServiceStatus: Codable, Hashable, Sendable {
    /// `operational`, `degraded`, …
    public var status: String
    public var queueDepth: Int
    public var runningJobs: Int
    public var version: String?

    enum CodingKeys: String, CodingKey {
        case status, version
        case queueDepth = "queue_depth"
        case runningJobs = "running_jobs"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "unknown"
        queueDepth = try c.decodeIfPresent(Int.self, forKey: .queueDepth) ?? 0
        runningJobs = try c.decodeIfPresent(Int.self, forKey: .runningJobs) ?? 0
        version = try c.decodeIfPresent(String.self, forKey: .version)
    }
}

/// Public platform-wide counters.
public struct Stats: Codable, Hashable, Sendable {
    public struct Totals: Codable, Hashable, Sendable {
        public var jobsCompleted: Int
        public var outputMinutes: Double
        public var sourceMinutes: Double
        public var bytesDelivered: Int64
        public var renditionsDelivered: Int
        public var customers: Int

        enum CodingKeys: String, CodingKey {
            case customers
            case jobsCompleted = "jobs_completed"
            case outputMinutes = "output_minutes"
            case sourceMinutes = "source_minutes"
            case bytesDelivered = "bytes_delivered"
            case renditionsDelivered = "renditions_delivered"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            jobsCompleted = try c.decodeIfPresent(Int.self, forKey: .jobsCompleted) ?? 0
            outputMinutes = try c.decodeIfPresent(Double.self, forKey: .outputMinutes) ?? 0
            sourceMinutes = try c.decodeIfPresent(Double.self, forKey: .sourceMinutes) ?? 0
            bytesDelivered = try c.decodeIfPresent(Int64.self, forKey: .bytesDelivered) ?? 0
            renditionsDelivered = try c.decodeIfPresent(Int.self, forKey: .renditionsDelivered) ?? 0
            customers = try c.decodeIfPresent(Int.self, forKey: .customers) ?? 0
        }
    }

    public struct Day: Codable, Hashable, Sendable, Identifiable {
        public var date: String
        public var jobsCompleted: Int
        public var outputMinutes: Double
        public var id: String { date }

        enum CodingKeys: String, CodingKey {
            case date
            case jobsCompleted = "jobs_completed"
            case outputMinutes = "output_minutes"
        }
    }

    public struct Recent: Codable, Hashable, Sendable {
        public var jobsCompleted: Int
        public var outputMinutes: Double

        enum CodingKeys: String, CodingKey {
            case jobsCompleted = "jobs_completed"
            case outputMinutes = "output_minutes"
        }
    }

    public var since: Date?
    public var updatedAt: Date?
    public var totals: Totals
    public var last24h: Recent?
    public var daily: [Day]

    enum CodingKeys: String, CodingKey {
        case since, totals, daily
        case updatedAt = "updated_at"
        case last24h = "last_24h"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        since = try c.decodeIfPresent(Date.self, forKey: .since)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        totals = try c.decode(Totals.self, forKey: .totals)
        last24h = try c.decodeIfPresent(Recent.self, forKey: .last24h)
        daily = try c.decodeList([Day].self, forKey: .daily)
    }
}

// MARK: - Operator console

public struct AdminOverview: Codable, Hashable, Sendable {
    public var organizations: Int
    public var jobsByStatus: [String: Int]

    enum CodingKeys: String, CodingKey {
        case organizations
        case jobsByStatus = "jobs_by_status"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        organizations = try c.decodeIfPresent(Int.self, forKey: .organizations) ?? 0
        jobsByStatus = try c.decodeMap([String: Int].self, forKey: .jobsByStatus)
    }
}

/// A job as the operator console sees it: with its organization.
public struct AdminJob: Decodable, Hashable, Sendable, Identifiable {
    public var job: Job
    public var organization: String
    public var id: String { job.id }

    enum CodingKeys: String, CodingKey { case organization }

    public init(from decoder: Decoder) throws {
        job = try Job(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .organization) {
            organization = s
        } else {
            organization = (try? c.decode(Int.self, forKey: .organization)).map(String.init) ?? ""
        }
    }
}

public struct AdminOrganizationUpdateParams: Encodable, Sendable {
    public var plan: PlanID?
    public var suspended: Bool?

    public init(plan: PlanID? = nil, suspended: Bool? = nil) {
        self.plan = plan
        self.suspended = suspended
    }
}
