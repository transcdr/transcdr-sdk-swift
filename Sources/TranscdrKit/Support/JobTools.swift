import Foundation

/// Minutes of output by tier, as billed.
public struct MinutesByTier: Hashable, Sendable {
    public var sd: Double = 0
    public var hd: Double = 0
    public var uhd: Double = 0

    public init(sd: Double = 0, hd: Double = 0, uhd: Double = 0) {
        self.sd = sd
        self.hd = hd
        self.uhd = uhd
    }

    public var total: Double { sd + hd + uhd }

    public mutating func add(_ tier: Tier, _ minutes: Double) {
        switch tier {
        case .sd: sd += minutes
        case .uhd: uhd += minutes
        default: hd += minutes
        }
    }

    /// The tier holding the most minutes: the one a job is labelled with.
    public var dominant: Tier {
        if uhd >= hd && uhd >= sd && uhd > 0 { return .uhd }
        if hd >= sd && hd > 0 { return .hd }
        return .sd
    }
}

/// A job's cost before it runs, with the server's rules: billable minutes are
/// output seconds / 60 per rendition, priced by each rendition's tier.
public enum JobEstimate {
    /// The automatic ladder's standard short sides.
    static let ladderShortSides = [2160, 1440, 1080, 720, 480, 360, 240]

    /// The short sides a spec produces from a source of `width`×`height`; audio output is
    /// billed at the SD rate, as one.
    public static func plannedShortSides(_ spec: OutputSpec, sourceWidth: Int, sourceHeight: Int) -> [Int] {
        let sourceShort = max(1, min(sourceWidth, sourceHeight))
        switch spec.renditions {
        case .sizes(let sizes)?:
            return sizes.map(\.shortSide)
        case .ladder(let ladder)?:
            let top = min(ladder.maxShortSide, sourceShort)
            return [top] + ladderShortSides.filter { Double($0) < Double(top) * 0.85 }
        case .sourceSize?:
            return [sourceShort]
        case nil:
            return [min(sourceShort, 480)]
        }
    }

    /// Seconds of output from `duration` seconds of input (after trimming).
    public static func outputSeconds(_ spec: OutputSpec, duration: Double) -> Double {
        let d = duration.isFinite ? max(0, duration) : 0
        guard case .video(let video) = spec else { return d }
        let end: Double
        switch video.trim.end {
        case .seconds(let s): end = min(s, d)
        case .source: end = d
        }
        return max(0, end - max(0, video.trim.start))
    }

    /// Billable minutes for `spec` over a probed input. At least one second is billed.
    public static func minutes(_ spec: OutputSpec, info: MediaInfo) -> MinutesByTier {
        let seconds = max(1, outputSeconds(spec, duration: info.duration))
        var out = MinutesByTier()
        for side in plannedShortSides(spec, sourceWidth: info.width, sourceHeight: info.height) {
            out.add(Catalog.tier(forShortSide: side), seconds / 60)
        }
        return out
    }

    /// Dollars for `minutes` at the plan's rates (or the list rates).
    public static func cost(_ minutes: MinutesByTier, rates: RateCard?) -> Double {
        let sd = rates?.sd ?? Catalog.rates.sd
        let hd = rates?.hd ?? Catalog.rates.hd
        let uhd = rates?.uhd ?? Catalog.rates.uhd
        return minutes.sd * sd + minutes.hd * hd + minutes.uhd * uhd
    }
}

/// Copy-pasteable requests, matching the web dashboard's.
public enum RequestSnippet {
    /// `curl -X POST https://api…/v1/jobs -H … -d '{…}'`.
    public static func curl(_ method: String, path: String, body: JSONValue?, origin: String) -> String {
        var lines = ["curl -X \(method) \(origin)\(path)", "  -H \"Authorization: Bearer $TRANSCDR_API_KEY\""]
        if let body {
            lines.append("  -H \"Content-Type: application/json\"")
            let json = body.prettyPrinted().replacingOccurrences(of: "'", with: "'\\''")
            lines.append("  -d '\(json)'")
        }
        return lines.joined(separator: " \\\n")
    }

    /// The `POST /v1/jobs` body that recreates `job`: its input and resolved
    /// output (complete, so no preset), priority, metadata and webhook URL.
    public static func createBody(for job: Job) -> JSONValue {
        var body: [String: JSONValue] = [:]
        body["input"] = (try? JSONValue.from(job.input)) ?? .null
        body["output"] = (try? JSONValue.from(job.output)) ?? .object([:])
        if job.priority != .normal { body["priority"] = .string(job.priority.rawValue) }
        if !job.metadata.isEmpty { body["metadata"] = .object(job.metadata.mapValues { .string($0) }) }
        if let hook = job.webhookUrl { body["webhook_url"] = .string(hook) }
        return .object(body)
    }
}

extension JobInput {
    /// A short name for lists: the asset id, the file name of a connection
    /// path, or the last path component (else the host) of a URL.
    public var displayName: String {
        switch self {
        case .asset(let id): return id
        case .connection(_, let path):
            let last = path.split(separator: "/").last.map(String.init) ?? ""
            return last.isEmpty ? path : last
        case .url(let s):
            guard let url = URL(string: s), url.scheme != nil else { return s }
            let last = url.path.split(separator: "/").last.map(String.init) ?? ""
            return last.isEmpty ? (url.host ?? s) : last
        case .unknown(let type): return type
        }
    }
}

/// Destination prefix templates (`out/{job_id}/`), as the web previews them.
public enum PrefixTemplate {
    public static let variables: [(name: String, description: String)] = [
        ("{job_id}", "The job id, e.g. job_4Qm…"),
        ("{name}", "Source file name with extension, e.g. talk.mov"),
        ("{stem}", "Source file name without extension, e.g. talk"),
        ("{ext}", "Source extension, e.g. mov"),
        ("{dir}", "Source folder, e.g. incoming/2026"),
        ("{date}", "The date, YYYY-MM-DD (UTC)"),
        ("{automation}", "The automation id"),
        ("{org}", "Your organization id"),
    ]

    /// Where `template` writes for a source at `sample` (a path such as `incoming/talk.mov`).
    public static func preview(_ template: String, sample: String, now: Date = Date()) -> String {
        let name = sample.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? sample
        let dot = name.lastIndex(of: ".")
        let hasExt = dot.map { $0 > name.startIndex } ?? false
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        let vars: [String: String] = [
            "{job_id}": "job_4QmZr8XkT2vLp9cN1bHs7a",
            "{name}": name,
            "{stem}": hasExt ? String(name[..<dot!]) : name,
            "{ext}": hasExt ? String(name[name.index(after: dot!)...]) : "",
            "{dir}": sample.contains("/") ? String(sample[..<sample.lastIndex(of: "/")!]) : "",
            "{date}": Format.isoDay(now, calendar: utc),
            "{automation}": "aut_7Tq…",
            "{org}": "org_BAZ…",
        ]
        var out = template
        for (k, v) in vars { out = out.replacingOccurrences(of: k, with: v) }
        return out
    }
}
