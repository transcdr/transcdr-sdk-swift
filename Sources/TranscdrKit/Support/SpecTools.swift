import Foundation

/// An `output` override as sent on job, preset and automation requests: the
/// JSON the server merges over the preset (objects merge, arrays replace,
/// `null` clears). Build one from a full spec, or diff two with `SpecTools.diff`.
public struct OutputSpecInput: Encodable, Hashable, Sendable {
    public var json: JSONValue

    public init(json: JSONValue) { self.json = json }

    /// Every set field of `spec`.
    public init(_ spec: OutputSpec) {
        json = (try? JSONValue.from(spec)) ?? .object([:])
    }

    public var isEmpty: Bool { json.objectValue?.isEmpty ?? true }

    public func encode(to encoder: Encoder) throws { try json.encode(to: encoder) }
}

/// Output-spec helpers shared by every editor: defaults, normalising editor
/// state, the minimal override against a preset, validation with the
/// server's rules, and a one-line description.
public enum SpecTools {
    /// The API's defaults.
    public static let defaultSpec = OutputSpec(
        mode: .single, codec: .av1, renditions: [], ladder: nil, quality: Quality(), gop: nil, segmentSeconds: nil,
        audio: AudioSettings(mode: .auto), subtitles: nil, color: .sdr, bitDepth: .auto, maxFps: nil, filters: nil, trim: nil
    )

    /// A spec with every field resolved (the defaults where unset), for editing.
    public static func resolved(_ spec: OutputSpec?) -> OutputSpec {
        let d = defaultSpec
        guard let spec else { return d }
        var out = spec
        out.mode = spec.mode ?? d.mode
        out.codec = spec.codec ?? d.codec
        out.renditions = spec.renditions ?? []
        out.quality = spec.quality ?? Quality()
        var audio = spec.audio ?? AudioSettings()
        audio.mode = audio.mode ?? .auto
        out.audio = audio
        out.color = spec.color ?? d.color
        out.bitDepth = spec.bitDepth ?? d.bitDepth
        out.clear = []
        return out
    }

    private static func blank(_ s: String?) -> Bool { s?.trimmingCharacters(in: .whitespaces).isEmpty ?? true }
    private static func trimmed(_ s: String?) -> String? { blank(s) ? nil : s!.trimmingCharacters(in: .whitespaces) }

    /// Drop empty strings and editor artefacts so the spec is what the API expects.
    public static func normalize(_ spec: OutputSpec) -> OutputSpec {
        var out = resolved(spec)
        out.renditions = (out.renditions ?? []).map { r in
            Rendition(width: r.width, height: r.height, bitrate: trimmed(r.bitrate), label: trimmed(r.label))
        }
        out.quality = Quality(
            target: trimmed(out.quality?.target), crf: out.quality?.crf,
            bitrate: trimmed(out.quality?.bitrate), bufferMs: out.quality?.bufferMs
        )
        var audio = out.audio ?? AudioSettings()
        audio.mode = audio.mode ?? .auto
        audio.bitrate = trimmed(audio.bitrate)
        out.audio = audio
        if out.mode != .hls { out.segmentSeconds = nil }
        out.subtitles = trimmed(out.subtitles)
        out.filters = trimmed(out.filters)
        if let trim = out.trim {
            let start = trim.start ?? 0
            out.trim = (start == 0 && trim.end == nil) ? nil : Trim(start: start, end: trim.end)
        }
        return out
    }

    /// The smallest override that turns `base` (a preset's spec, or the
    /// defaults) into `spec`.
    public static func diff(_ spec: OutputSpec, base: OutputSpec? = nil) -> OutputSpecInput {
        let target = (try? JSONValue.from(normalize(spec)).objectValue) ?? [:]
        let from = (try? JSONValue.from(normalize(base ?? defaultSpec)).objectValue) ?? [:]
        var out: [String: JSONValue] = [:]
        for key in OutputSpec.Field.allCases.map(\.stringValue) {
            let t = target[key] ?? .null
            let f = from[key] ?? .null
            guard t != f else { continue }
            if key == "quality" || key == "audio", var patch = t.objectValue, let old = f.objectValue {
                // Nested objects merge on the server: a key removed here must be cleared.
                for k in old.keys where patch[k] == nil { patch[k] = .null }
                out[key] = .object(patch)
            } else {
                out[key] = t
            }
        }
        return OutputSpecInput(json: .object(out))
    }

    /// `800k` → 800000, `3M` → 3000000; nil when unreadable.
    public static func parseBitrate(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let last = t.last else { return nil }
        let mult: Double = "kK".contains(last) ? 1e3 : "mM".contains(last) ? 1e6 : 1
        guard let n = Double(mult == 1 ? t : String(t.dropLast())), n.isFinite, n > 0 else { return nil }
        return Int((n * mult).rounded(.down))
    }

    /// `5000000` → `5M`, `3250000` → `3.25M`, `800000` → `800k`.
    public static func formatBitrate(_ bps: Int) -> String {
        if bps >= 1_000_000 { return trimNumber(Double(bps) / 1e6) + "M" }
        if bps >= 1000 { return trimNumber(Double(bps) / 1e3) + "k" }
        return String(bps)
    }

    /// Up to two decimals, without trailing zeros.
    fileprivate static func trimNumber(_ n: Double) -> String {
        var s = String(format: "%.2f", n)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }

    /// The rates a constant-bitrate rendition may ask for, bits per second.
    public static let cbrRange = 100_000...200_000_000

    /// The rate a `cbr` rendition without one of its own (nor `quality.bitrate`)
    /// is coded at, bits per second, as the service computes it. H.264 up to
    /// 30 fps by short side: 144 → 0.2M, 240 → 0.4M, 360 → 0.8M, 480 → 1.2M,
    /// 720 → 3M, 1080 → 5M, 1440 → 9M, 2160 → 16M; linear between rows, by
    /// area above 2160. Above 30 fps it grows by half the extra frame rate
    /// (capped at 120 fps). H.265 is 0.65× and AV1 0.5×. `fps` nil means 30.
    public static func defaultCbrRate(codec: VideoCodec, width: Int, height: Int, fps: Double? = nil) -> Int {
        let table: [(side: Double, bps: Double)] = [
            (144, 200_000), (240, 400_000), (360, 800_000), (480, 1_200_000),
            (720, 3_000_000), (1080, 5_000_000), (1440, 9_000_000), (2160, 16_000_000),
        ]
        let side = Double(max(1, min(width, height)))
        let base: Double
        if side <= table[0].side {
            base = table[0].bps
        } else if side >= table[table.count - 1].side {
            let scale = side / table[table.count - 1].side
            base = table[table.count - 1].bps * scale * scale
        } else {
            let i = table.firstIndex { side <= $0.side }!
            let (lo, hi) = (table[i - 1], table[i])
            base = lo.bps + (hi.bps - lo.bps) * (side - lo.side) / (hi.side - lo.side)
        }
        let rate = fps.flatMap { $0.isFinite && $0 > 30 ? min($0, 120) : nil } ?? 30
        let codecScale = codec == .h265 ? 0.65 : codec == .av1 ? 0.5 : 1
        let bps = (base * (1 + 0.5 * (rate / 30 - 1)) * codecScale / 1000).rounded() * 1000
        return Int(max(1000, bps))
    }

    /// The rates MP3 is coded at, bits per second (constant bit rate).
    public static let mp3Bitrates = [
        32_000, 40_000, 48_000, 56_000, 64_000, 80_000, 96_000, 112_000, 128_000, 160_000, 192_000, 224_000, 256_000, 320_000,
    ]

    /// Whether the spec's audio is MP3: `audio.mode` `mp3`, or audio-only output.
    public static func isMp3Output(_ spec: OutputSpec) -> Bool {
        spec.mode == .audio || spec.audio?.mode == .mp3
    }

    /// A constant-bitrate rate's error, with the server's messages; nil when valid.
    private static func cbrRateError(_ s: String) -> String? {
        guard let bps = parseBitrate(s) else { return "Bitrate must look like 800k, 3M or 2500000." }
        return cbrRange.contains(bps) ? nil : "A constant bitrate must be between 100k and 200M."
    }

    public static func isQualityTarget(_ target: String) -> Bool {
        if Quality.targets.contains(target) { return true }
        guard target.hasPrefix("vmaf="), let n = Int(target.dropFirst(5)), target.count <= 8 else { return false }
        return (1...100).contains(n)
    }

    public static func shortSide(_ r: Rendition) -> Int { min(r.width, r.height) }

    public static func effectiveLabel(_ r: Rendition) -> String {
        if let label = r.label, !label.isEmpty { return label }
        return "\(shortSide(r))p"
    }

    /// Errors keyed by the contract's dotted param (`output.renditions.0.width`),
    /// with the server's rules.
    public static func validate(_ input: OutputSpec, maxShortSide: Int = 4320) -> [String: String] {
        let s = normalize(input)
        var errors: [String: String] = [:]
        func set(_ param: String, _ message: String) {
            let key = "output.\(param)"
            if errors[key] == nil { errors[key] = message }
        }
        if s.mode == .audio {
            // Audio-only output writes no video.
            let q = s.quality
            let video: [(String, Bool)] = [
                ("renditions", !(s.renditions ?? []).isEmpty),
                ("ladder", s.ladder != nil),
                ("quality", q?.target != nil || q?.crf != nil || q?.bitrate != nil || q?.bufferMs != nil),
                ("gop", s.gop != nil),
                ("codec", (s.codec ?? .av1) != .av1),
                ("color", (s.color ?? .sdr) != .sdr),
                ("bit_depth", (s.bitDepth ?? .auto) != .auto),
                ("max_fps", s.maxFps != nil),
                ("filters", s.filters != nil),
                ("subtitles", s.subtitles != nil),
            ]
            for (field, present) in video where present {
                set(field, "Audio-only output writes no video, so \(field) does not apply.")
            }
            if s.trim != nil { set("trim", "A trim is not available for audio-only output.") }
        }
        let renditions = s.mode == .audio ? [] : (s.renditions ?? [])
        if renditions.count > 8 { set("renditions", "At most 8 renditions are allowed.") }
        for (i, r) in renditions.enumerated() {
            let at = { (f: String) in "renditions.\(i).\(f)" }
            if r.width < 64 || r.width > 7680 { set(at("width"), "Width must be between 64 and 7680.") }
            else if r.width % 2 != 0 { set(at("width"), "Width and height must be even (4:2:0 chroma).") }
            if r.height < 64 || r.height > 4320 { set(at("height"), "Height must be between 64 and 4320.") }
            else if r.height % 2 != 0 { set(at("height"), "Width and height must be even (4:2:0 chroma).") }
            if shortSide(r) > maxShortSide { set(at("height"), "Your plan allows renditions up to \(maxShortSide)p.") }
            if let b = r.bitrate {
                if s.quality?.isCbr != true {
                    set(at("bitrate"), "A rendition bitrate is a constant bit rate: set quality.target to \"cbr\", or remove the bitrate to code to a quality level.")
                } else if let message = cbrRateError(b) {
                    set(at("bitrate"), message)
                }
            }
            if let l = r.label, l.range(of: "^[A-Za-z0-9_-]{1,32}$", options: .regularExpression) == nil {
                set(at("label"), "Labels are 1–32 characters of A–Z, a–z, 0–9, - and _.")
            }
        }
        let labels = renditions.map(effectiveLabel)
        if Set(labels).count != labels.count { set("renditions", "Two renditions share a label; give them distinct labels.") }
        if let side = s.ladder?.maxShortSide, side < 64 || side > maxShortSide {
            set("ladder.max_short_side", "max_short_side must be between 64 and \(maxShortSide).")
        }
        if let target = s.quality?.target, !isQualityTarget(target) {
            set("quality.target", "Target must be visually_lossless, high, standard, low or vmaf=N (N between 1 and 100).")
        }
        if let q = s.quality, q.isCbr {
            if q.crf != nil { set("quality.crf", "crf names a quality level and cbr a bit rate: use one or the other.") }
            if let b = q.bitrate, let message = cbrRateError(b) { set("quality.bitrate", message) }
            if let ms = q.bufferMs, !(100...10_000).contains(ms) { set("quality.buffer_ms", "buffer_ms must be between 100 and 10000.") }
        } else if let q = s.quality, q.bitrate != nil || q.bufferMs != nil {
            set(q.bitrate != nil ? "quality.bitrate" : "quality.buffer_ms", "A bitrate and buffer apply to constant bit rate: set quality.target to \"cbr\".")
        }
        if let crf = s.quality?.crf, crf < 0 || crf > 63 { set("quality.crf", "crf must be between 0 and 63.") }
        if let gop = s.gop, gop < 1 || gop > 1200 { set("gop", "gop must be between 1 and 1200 frames.") }
        if s.mode == .hls, let seg = s.segmentSeconds, seg < 1 || seg > 20 {
            set("segment_seconds", "segment_seconds must be between 1 and 20.")
        }
        let audioMode = s.audio?.mode ?? .auto
        let channels = s.audio?.channels
        if s.mode == .audio && audioMode == .drop {
            set("audio.mode", "Audio-only output needs audio: use \"auto\" or \"mp3\".")
        }
        if s.mode == .audio && audioMode == .opus {
            set("audio.mode", "Audio-only output is an MP3 file, which cannot hold Opus: use \"auto\" or \"mp3\".")
        }
        if s.mode == .hls && audioMode == .mp3 {
            set("audio.mode", "MP3 is not available for HLS: use \"auto\" or \"opus\" there, or a single file or audio-only output for MP3.")
        }
        if audioMode == .drop, let channels, channels != .source {
            set("audio.channels", "Audio channels mean nothing when audio is dropped.")
        }
        if isMp3Output(s), channels?.isSurround == true {
            set("audio.channels", "MP3 carries two channels at most: choose source, mono or stereo (a surround source is downmixed to stereo).")
        }
        if s.audio?.stereoFallback == true {
            if s.mode != .hls {
                set("audio.stereo_fallback", "stereo_fallback applies only to mode \"hls\".")
            } else if audioMode == .drop {
                set("audio.stereo_fallback", "stereo_fallback means nothing when audio is dropped.")
            } else if channels == .mono || channels == .stereo {
                set("audio.stereo_fallback", "stereo_fallback adds a stereo rendition beside surround audio, so channels must be source, 5.1 or 7.1.")
            }
        }
        if let bitrate = s.audio?.bitrate {
            if let bps = parseBitrate(bitrate), (6000...512_000).contains(bps) {
                if s.audio?.mode == .drop { set("audio.bitrate", "An audio bitrate means nothing when audio is dropped.") }
                else if isMp3Output(s), !mp3Bitrates.contains(bps) {
                    set("audio.bitrate", "MP3 is constant bitrate at 32k, 40k, 48k, 56k, 64k, 80k, 96k, 112k, 128k, 160k, 192k, 224k, 256k or 320k.")
                }
            } else {
                set("audio.bitrate", "Audio bitrate must be between 6k and 512k.")
            }
        }
        if let subs = s.subtitles, subs != "all", subs != "none",
           !subs.split(separator: ",").allSatisfy({ String($0).range(of: "^[a-z]{2,3}$", options: .regularExpression) != nil })
        {
            set("subtitles", "subtitles must be all, none, or ISO 639 codes such as eng,deu.")
        }
        if (s.color == .hdr10 || s.color == .hlg) && s.bitDepth == .eight {
            set("bit_depth", "HDR output needs 10-bit; use bit_depth \"auto\" or \"10bit\".")
        }
        if s.codec == .h264 && s.bitDepth == .ten {
            set("bit_depth", "10-bit H.264 is not offered; use av1 or h265 for 10-bit output.")
        }
        if let fps = s.maxFps, fps < 1 || fps > 240 { set("max_fps", "max_fps must be between 1 and 240.") }
        if let f = s.filters, f.count > 512 || f.contains(where: \.isWhitespace) {
            set("filters", "filters must be a filter chain such as crop=1280:720,hflip.")
        }
        if let trim = s.trim {
            if (trim.start ?? 0) < 0 { set("trim.start", "trim.start must be zero or more seconds.") }
            if let end = trim.end, end <= (trim.start ?? 0) { set("trim.end", "trim.end must be after trim.start.") }
        }
        return errors
    }

    /// `HLS · AV1 · ladder ≤ 1080p · standard`, or under constant bit rate
    /// `HLS · H.264 · 1080p / 720p · CBR 5 / 3 Mb/s`.
    public static func describe(_ spec: OutputSpec?) -> String {
        guard let spec else { return "—" }
        if spec.mode == .audio {
            var parts = ["MP3 audio"]
            if let bitrate = spec.audio?.bitrate { parts.append(bitrate) }
            if let channels = spec.audio?.channels, channels != .source { parts.append(channels.rawValue) }
            return parts.joined(separator: " · ")
        }
        var parts = [spec.mode == .hls ? "HLS" : "MP4", Catalog.codecName(spec.codec ?? .av1)]
        if let r = spec.renditions, !r.isEmpty {
            parts.append(r.map(effectiveLabel).joined(separator: " / "))
        } else if let ladder = spec.ladder {
            parts.append(ladder.maxShortSide.map { "ladder ≤ \($0)p" } ?? "auto ladder")
        } else {
            parts.append("source resolution")
        }
        if let color = spec.color, color != .sdr { parts.append(color.rawValue.uppercased()) }
        if let crf = spec.quality?.crf { parts.append("crf \(crf)") }
        else if let q = spec.quality, q.isCbr { parts.append(describeCbr(spec, q)) }
        else if let target = spec.quality?.target { parts.append(target.replacingOccurrences(of: "_", with: " ")) }
        return parts.joined(separator: " · ")
    }
}

extension SpecTools {
    /// `CBR 5 / 3 Mb/s`, `CBR 5 Mb/s` or `CBR (default rates)`.
    fileprivate static func describeCbr(_ spec: OutputSpec, _ q: Quality) -> String {
        let shared = q.bitrate.flatMap(parseBitrate)
        let renditions = spec.renditions ?? []
        let rates: [Int]
        if !renditions.isEmpty, shared != nil || renditions.contains(where: { $0.bitrate != nil }) {
            rates = renditions.map { r in
                r.bitrate.flatMap(parseBitrate) ?? shared
                    ?? defaultCbrRate(codec: spec.codec ?? .av1, width: r.width, height: r.height, fps: spec.maxFps)
            }
        } else if let shared {
            rates = [shared]
        } else {
            return "CBR (default rates)"
        }
        return "CBR " + rates.map { trimNumber(Double($0) / 1e6) }.joined(separator: " / ") + " Mb/s"
    }
}

/// Static product data mirrored from the service (for labels and pickers).
public enum Catalog {
    public struct ResolutionOption: Hashable, Sendable, Identifiable {
        public let label: String
        public let width: Int
        public let height: Int
        public var id: String { label }
    }

    public static let commonResolutions: [ResolutionOption] = [
        .init(label: "2160p", width: 3840, height: 2160),
        .init(label: "1440p", width: 2560, height: 1440),
        .init(label: "1080p", width: 1920, height: 1080),
        .init(label: "720p", width: 1280, height: 720),
        .init(label: "540p", width: 960, height: 540),
        .init(label: "480p", width: 854, height: 480),
        .init(label: "360p", width: 640, height: 360),
        .init(label: "240p", width: 426, height: 240),
        .init(label: "9:16 1080", width: 1080, height: 1920),
    ]

    public static let qualityTargets: [(value: String, label: String)] = [
        ("visually_lossless", "Visually lossless"), ("high", "High"), ("standard", "Standard"), ("low", "Low"),
    ]

    public static let codecs: [(codec: VideoCodec, label: String, hint: String)] = [
        (.av1, "AV1", "Best compression. Every modern browser."),
        (.h264, "H.264", "Plays everywhere, including legacy devices."),
        (.h265, "H.265", "Apple ecosystem and smart TVs."),
    ]

    public static func codecName(_ codec: VideoCodec) -> String {
        codecs.first { $0.codec == codec }?.label ?? codec.rawValue.uppercased()
    }

    public static let eventDescriptions: [String: String] = [
        "job.created": "A job was accepted and queued.",
        "job.scheduled": "Capacity was reserved and the job is about to start.",
        "job.started": "Processing started: the input is being fetched.",
        "job.completed": "Every rendition finished and the outputs are downloadable.",
        "job.failed": "The job failed and will not be retried automatically.",
        "job.canceled": "The job was canceled.",
        "asset.ready": "An upload or import finished and the asset can be transcoded.",
        "asset.deleted": "An asset was deleted.",
        "job.delivered": "A job's outputs were delivered to a connection.",
        "job.delivery_failed": "Delivering outputs to a connection failed after every retry.",
        "automation.triggered": "An automation picked up a new source file and created a job.",
        "connection.disabled": "A connection was turned off after failing; data.object says why and which automations paused.",
        "webhook.test": "Sent by the \"Send test\" button; every endpoint receives it.",
    ]

    public struct ScopeGroup: Hashable, Sendable, Identifiable {
        public let resource: String
        public let label: String
        public let scopes: [String]
        public var id: String { resource }
    }

    public static let scopeGroups: [ScopeGroup] = [
        .init(resource: "jobs", label: "Jobs, probes & events", scopes: ["jobs:read", "jobs:write"]),
        .init(resource: "assets", label: "Assets & uploads", scopes: ["assets:read", "assets:write"]),
        .init(resource: "presets", label: "Presets", scopes: ["presets:read", "presets:write"]),
        .init(resource: "webhooks", label: "Webhooks", scopes: ["webhooks:read", "webhooks:write"]),
        .init(resource: "usage", label: "Usage", scopes: ["usage:read"]),
        .init(resource: "billing", label: "Billing", scopes: ["billing:read", "billing:write"]),
        .init(resource: "keys", label: "API keys", scopes: ["keys:read", "keys:write"]),
        .init(resource: "org", label: "Organization & members", scopes: ["org:read", "org:write"]),
        .init(resource: "connections", label: "Connections", scopes: ["connections:read", "connections:write"]),
        .init(resource: "automations", label: "Automations", scopes: ["automations:read", "automations:write"]),
    ]

    public static let featureLabels: [String: String] = [
        "api": "REST API & SDKs", "hls": "HLS / CMAF packaging", "av1": "AV1", "h264": "H.264", "h265": "H.265 / HEVC",
        "test_mode": "Free test mode", "webhooks": "Signed webhooks", "presets": "Custom presets", "hdr": "HDR10 & HLG",
        "auto_recharge": "Auto-recharge & spend limits", "priority_queue": "Priority queue", "team": "Team members & roles",
        "integrations": "Storage integrations & automations", "sso": "SSO", "dedicated_capacity": "Dedicated capacity",
        "sla": "Uptime SLA", "invoicing": "Invoicing", "unlimited": "Unlimited transcoding at no charge",
    ]

    /// Tier of a rendition by its short side.
    public static func tier(forShortSide side: Int) -> Tier {
        side <= 576 ? .sd : side <= 1440 ? .hd : .uhd
    }

    public static let tierLabels: [Tier: String] = [.sd: "SD (≤ 576p)", .hd: "HD (≤ 1440p)", .uhd: "UHD (> 1440p)"]

    /// Fallback rates (dollars per output minute) when the API has not said.
    public static let rates = (sd: 0.005, hd: 0.01, uhd: 0.025)
}
