import Foundation

/// Output-spec helpers shared by every editor: the smallest override against a preset, an
/// override merged over a preset, validation with the API's rules, and a one-line description.
/// None of them fills in a value: a spec states every field it needs.
public enum SpecTools {
    // MARK: Overrides

    /// The smallest override that turns `base` (a preset version's spec) into `spec`, as a JSON
    /// merge patch: changed values, and `null` for what `spec` no longer has. Without a base,
    /// the whole spec.
    public static func diff(_ spec: OutputSpec, base: OutputSpec?) -> OutputOverrides {
        let target = (try? JSONValue.from(spec)) ?? .object([:])
        guard let base else { return OutputOverrides(json: target) }
        let from = (try? JSONValue.from(base)) ?? .object([:])
        return OutputOverrides(json: mergePatch(target, over: from) ?? .object([:]))
    }

    /// `new` as a patch over `old`; nil when they are equal.
    private static func mergePatch(_ new: JSONValue, over old: JSONValue) -> JSONValue? {
        guard new != old else { return nil }
        guard let target = new.objectValue, let before = old.objectValue else { return new }
        var patch: [String: JSONValue] = [:]
        for (k, v) in target {
            if let o = before[k] {
                if let p = mergePatch(v, over: o) { patch[k] = p }
            } else {
                patch[k] = v
            }
        }
        for k in before.keys where target[k] == nil { patch[k] = .null }
        return .object(patch)
    }

    /// The choices of each exclusive group, by the object that holds them: setting one clears
    /// the others, as the API's merge does.
    static let exclusive: [String: [[String]]] = [
        "video": [["quality", "crf", "cbr"]],
        "video.gop": [["frames", "seconds"]],
        "renditions": [["sizes", "ladder", "source_size"]],
        "subtitles": [["tracks", "languages"]],
        "image.frames": [["count", "at_seconds"]],
    ]

    /// `overrides` merged over `base` with the API's rules: objects merge key by key, scalars
    /// and arrays replace, one choice of an exclusive group clears the others, a privacy preset
    /// replaces the privacy section, and `null` removes a field. The result as JSON, which may
    /// be incomplete: check it with `OutputRules.check`.
    public static func merge(_ overrides: OutputOverrides, over base: JSONValue) -> JSONValue {
        merge(overrides.json, over: base, at: "")
    }

    /// `overrides` merged over `base`, as a spec; nil when the result is incomplete.
    public static func merge(_ overrides: OutputOverrides, over base: OutputSpec) -> OutputSpec? {
        let merged = merge(overrides, over: (try? JSONValue.from(base)) ?? .object([:]))
        guard OutputRules.check(merged).isEmpty else { return nil }
        return try? merged.decode(as: OutputSpec.self)
    }

    private static func merge(_ overlay: JSONValue, over base: JSONValue, at path: String) -> JSONValue {
        guard let patch = overlay.objectValue else { return overlay }
        if path == "privacy", let preset = patch["preset"], !preset.isNull {
            return .object(patch.filter { !$0.value.isNull })
        }
        var out = base.objectValue ?? [:]
        for (key, value) in patch where !value.isNull {
            for group in exclusive[path] ?? [] where group.contains(key) {
                for sibling in group where sibling != key { out[sibling] = nil }
            }
        }
        for (key, value) in patch {
            if value.isNull {
                out[key] = nil
            } else {
                let child = path.isEmpty ? key : "\(path).\(key)"
                out[key] = value.objectValue != nil ? merge(value, over: out[key] ?? .object([:]), at: child) : value
            }
        }
        return .object(out)
    }

    // MARK: Rates

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

    /// The rates a constant-bitrate size may ask for, bits per second.
    public static let cbrRange = 100_000...200_000_000

    /// What `video.cbr.bitrate: "standard"` codes a size at, bits per second, as the service
    /// computes it. H.264 up to 30 fps by short side: 144 → 0.2M, 240 → 0.4M, 360 → 0.8M,
    /// 480 → 1.2M, 720 → 3M, 1080 → 5M, 1440 → 9M, 2160 → 16M; linear between rows, by area
    /// above 2160. Above 30 fps it grows by half the extra frame rate (capped at 120 fps).
    /// H.265 is 0.65× and AV1 0.5×. `fps` nil means 30 or less.
    public static func standardCbrRate(codec: VideoCodec, width: Int, height: Int, fps: Double?) -> Int {
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

    /// AAC-LC's rates, bits per second per main channel (the LFE of 5.1 and 7.1 does not count).
    public static let aacBitratePerChannel = 8_000...288_000

    /// An AAC bitrate's error for a channel layout, with the API's message; nil when valid. The
    /// source's layout takes at least 8k.
    public static func aacBitrateError(_ bps: Int, channels: AudioChannels) -> String? {
        let count: Int?
        switch channels {
        case .mono: count = 1
        case .stereo: count = 2
        case .surround51: count = 6
        case .surround71: count = 8
        default: count = nil
        }
        guard let count else { return bps >= aacBitratePerChannel.lowerBound ? nil : "AAC takes at least 8k." }
        let main = count - (count >= 6 ? 1 : 0)
        let lo = aacBitratePerChannel.lowerBound * main
        let hi = aacBitratePerChannel.upperBound * main
        if (lo...hi).contains(bps) { return nil }
        return "AAC takes 8k to 288k per channel: \(lo / 1000)k to \(min(hi / 1000, 512))k for \(channels.rawValue)."
    }

    /// A constant rate's error, with the API's messages; nil when valid.
    private static func cbrRateError(_ s: String) -> String? {
        guard let bps = parseBitrate(s) else { return "Bitrate must look like 800k, 3M or 2500000." }
        return cbrRange.contains(bps) ? nil : "A constant bitrate must be between 100k and 200M."
    }

    /// A quality level: `visually_lossless`, `high`, `standard`, `low` or `vmaf=N` (1–100).
    public static func isQualityLevel(_ level: String) -> Bool {
        if VideoRate.qualityLevels.contains(level) { return true }
        guard level.hasPrefix("vmaf="), let n = Int(level.dropFirst(5)), level.count <= 8 else { return false }
        return (1...100).contains(n)
    }

    // MARK: Sizes and images

    /// A video size's name before it is made: its label, else `<short side>p` of its box. (Its
    /// file is named by the size it comes out at.)
    public static func effectiveLabel(_ size: RenditionSize) -> String {
        size.label == .bySize ? "\(size.shortSide)p" : size.label.rawValue
    }

    /// An image size's name before it is made: its label, else its box, `1920x1080`.
    public static func effectiveImageLabel(_ size: RenditionSize) -> String {
        size.label == .bySize ? "\(size.width)x\(size.height)" : size.label.rawValue
    }

    /// An image size's sides, in pixels; odd sizes are fine.
    public static let imageDimensions = 16...8192
    /// The most files one image job may make: stills × sizes × formats.
    public static let maxImageOutputs = 200
    /// The most stills one video may give.
    public static let maxFrames = 100

    /// The files an image spec makes: stills × sizes (the source size is one) × formats.
    public static func imageOutputCount(_ output: ImageOutput) -> Int {
        let sizes: Int
        if case .sizes(let s) = output.renditions { sizes = max(1, s.count) } else { sizes = 1 }
        return output.image.frames.stillCount * sizes * max(1, output.image.formats.count)
    }

    // MARK: Validation

    /// Every error the API would give this spec, with its params and messages: first the
    /// required-field table (`OutputRules.check`); once that passes, the values against each
    /// other and the plan's limits (`maxShortSide`, `maxSizes`).
    public static func validate(_ spec: OutputSpec, maxShortSide: Int, maxSizes: Int) -> [FieldError] {
        let table = spec.missingFields
        if !table.isEmpty { return table }
        var errors: [FieldError] = []
        func fail(_ path: String, _ message: String) { errors.append(FieldError(param: "output.\(path)", message: message)) }

        if let container = spec.container {
            let allowed = spec.kind == .video ? ContainerFormat.video : ContainerFormat.audio
            if !allowed.contains(container.format) {
                fail("container.format", spec.kind == .video
                    ? "Video output is packaged as mp4 or hls."
                    : "Audio output is packaged as mp3, flac or m4a.")
            }
        }
        let hls = spec.container?.format == .hls
        if hls && spec.privacy.resolved.keepsAny {
            fail("privacy", "HLS output carries no file metadata, so none can be kept: strip every category, or use container mp4.")
        }
        switch spec {
        case .video(let v):
            validateVideo(v.video, hls: hls, fail)
            validateAudio(v.audio, kind: .video, format: v.container.format, fail)
            validateRenditions(v.renditions, image: false, maxShortSide: maxShortSide, maxSizes: maxSizes, fail)
            if case .seconds(let end) = v.trim.end, end <= v.trim.start {
                fail("trim.end", "trim.end must be after trim.start.")
            }
        case .audio(let a):
            validateAudio(a.audio, kind: .audio, format: a.container.format, fail)
        case .image(let i):
            validateImage(i, fail)
            validateRenditions(i.renditions, image: true, maxShortSide: maxShortSide, maxSizes: maxSizes, fail)
        }
        return errors
    }

    private static func validateVideo(_ video: VideoSettings, hls: Bool, _ fail: (String, String) -> Void) {
        if (video.color == .hdr10 || video.color == .hlg) && video.bitDepth == .eight {
            fail("video.bit_depth", "HDR output needs 10-bit: use bit_depth from_color or 10bit.")
        }
        if video.codec == .h264 && video.bitDepth == .ten {
            fail("video.bit_depth", "10-bit H.264 is not offered; use av1 or h265 for 10-bit output.")
        }
        if case .cbr(let cbr) = video.rate, cbr.bitrate != ConstantBitRate.standard, let m = cbrRateError(cbr.bitrate) {
            fail("video.cbr.bitrate", m)
        }
        if video.gop == .segment && !hls {
            fail("video.gop", "gop \"segment\" is for hls; give {\"seconds\": N} or {\"frames\": N}.")
        }
        if video.filters.joined(separator: ",").count > 512 {
            fail("video.filters", "The filter chain is at most 512 characters.")
        }
    }

    private static func validateAudio(_ track: AudioTrack, kind: OutputKind, format: ContainerFormat, _ fail: (String, String) -> Void) {
        if kind == .audio && track == .drop {
            fail("audio.handling", "Audio output needs audio: set audio.handling to auto or encode.")
            return
        }
        guard let a = track.encoding else { return }
        let codec = a.codec
        if track.handling == .auto {
            if format == .mp3 && codec != .mp3 {
                fail("audio.codec", "With handling auto, audio an .mp3 file cannot carry becomes MP3: set codec mp3.")
            } else if format != .mp3 && codec != .opus {
                fail("audio.codec", "With handling auto, audio the container cannot carry becomes Opus: set codec opus, or handling encode to make every track this codec.")
            }
        }
        if format == .flac && codec != .flac {
            fail("audio.codec", "A .flac file holds FLAC only: set codec flac, or container m4a.")
        } else if format == .mp3 && codec != .mp3 {
            fail("audio.codec", "An .mp3 file holds MP3 only, not \(codec.displayName): set codec mp3, or container m4a.")
        } else if format == .hls && codec == .mp3 {
            fail("audio.codec", "MP3 is not available for HLS: use opus or aac there, or an mp4 or audio output for MP3.")
        }
        if codec == .mp3 && a.channels.isSurround {
            fail("audio.channels", "MP3 carries two channels at most: choose source, mono or stereo (a surround source is downmixed to stereo).")
        }
        if a.stereoFallback == true && (a.channels == .mono || a.channels == .stereo) {
            fail("audio.stereo_fallback", "stereo_fallback adds a stereo rendition beside surround audio, so channels must be source, 5.1 or 7.1.")
        }
        if let bitrate = a.bitrate, bitrate != AudioEncoding.standard {
            guard let bps = parseBitrate(bitrate), (6000...512_000).contains(bps) else {
                fail("audio.bitrate", "Audio bitrate must be between 6k and 512k.")
                return
            }
            if codec == .mp3 && !mp3Bitrates.contains(bps) {
                fail("audio.bitrate", "MP3 is constant bitrate at 32k, 40k, 48k, 56k, 64k, 80k, 96k, 112k, 128k, 160k, 192k, 224k, 256k or 320k.")
            }
            if codec == .aac, let m = aacBitrateError(bps, channels: a.channels) {
                fail("audio.bitrate", m)
            }
        }
    }

    private static func validateImage(_ output: ImageOutput, _ fail: (String, String) -> Void) {
        let image = output.image
        for (i, f) in image.formats.enumerated() where image.formats[..<i].contains(f) {
            fail("image.formats", "\(f.rawValue) is listed twice.")
        }
        if image.lossless == true, let f = image.formats.first(where: { $0 != .webp && $0 != .png }) {
            fail("image.lossless", "lossless applies to webp (png is always lossless); \(f.rawValue) has no lossless form.")
        }
        if let quality = image.quality {
            let lossy = image.lossyFormats
            for f in lossy where quality[f] == nil {
                fail("image.quality.\(f.rawValue)", "image.quality needs a quality for \(f.rawValue), which is made lossy.")
            }
            for f in quality.keys.sorted(by: { $0.rawValue < $1.rawValue }) where !lossy.contains(f) {
                fail("image.quality.\(f.rawValue)", "\(f.rawValue) is not made lossy here, so it takes no quality.")
            }
        }
        if case .atSeconds(let times) = image.frames, times.contains(where: { !$0.isFinite || $0 < 0 }) {
            fail("image.frames.at_seconds", "at_seconds are seconds from the start: zero or more.")
        }
        let outputs = imageOutputCount(output)
        if outputs > maxImageOutputs {
            fail("image", "This makes \(outputs) files (frames × sizes × formats); at most \(maxImageOutputs) are allowed.")
        }
    }

    private static func validateRenditions(
        _ renditions: Renditions, image: Bool, maxShortSide: Int, maxSizes: Int, _ fail: (String, String) -> Void
    ) {
        if case .ladder(let ladder) = renditions, !(64...maxShortSide).contains(ladder.maxShortSide) {
            fail("renditions.ladder.max_short_side", "max_short_side must be between 64 and \(maxShortSide).")
        }
        guard case .sizes(let sizes) = renditions else { return }
        if sizes.count > maxSizes { fail("renditions.sizes", "At most \(maxSizes) sizes are allowed.") }
        var labels: [String] = []
        for (i, s) in sizes.enumerated() {
            let at = { (field: String) in "renditions.sizes.\(i).\(field)" }
            if image {
                for (field, side) in [("width", s.width), ("height", s.height)] where !imageDimensions.contains(side) {
                    fail(at(field), "An image size's \(field) must be between 16 and 8192.")
                }
                labels.append(effectiveImageLabel(s))
                continue
            }
            if s.width < 64 || s.width > 7680 {
                fail(at("width"), "Width must be between 64 and 7680.")
            } else if s.height < 64 || s.height > 4320 {
                fail(at("height"), "Height must be between 64 and 4320.")
            } else if s.width % 2 != 0 || s.height % 2 != 0 {
                fail(at("width"), "Width and height must be even (4:2:0 chroma).")
            } else if s.shortSide > maxShortSide {
                fail(at("height"), "Your plan allows renditions up to \(maxShortSide)p.")
            }
            if let rate = s.cbrBitrate, rate != ConstantBitRate.standard, let m = cbrRateError(rate) {
                fail(at("video.cbr.bitrate"), m)
            }
            labels.append(effectiveLabel(s))
        }
        if Set(labels).count != labels.count {
            fail("renditions.sizes", "Two sizes share a label; give them distinct labels.")
        }
    }

    // MARK: Describing

    /// `HLS · AV1 · ladder ≤ 1080p · standard`, or under constant bit rate
    /// `HLS · H.264 · 1080p / 720p · CBR 5 / 3 Mb/s`, or for images
    /// `Images · AVIF / JPEG · 1920x1920 / small · 12 frames`, or `MP3 audio · 128k`.
    public static func describe(_ spec: OutputSpec?) -> String {
        guard let spec else { return "—" }
        switch spec {
        case .image(let i):
            var parts = ["Images", i.image.formats.map { $0.rawValue.uppercased() }.joined(separator: " / ")]
            parts.append(describeSizes(i.renditions, label: effectiveImageLabel))
            if let fit = fit(of: i.renditions), fit != .contain { parts.append(fit.rawValue) }
            if let q = i.image.quality, !q.isEmpty {
                let values = Set(q.values)
                parts.append(values.count == 1 ? "quality \(values.first!)" : q.sorted { $0.key.rawValue < $1.key.rawValue }
                    .map { "\($0.key.rawValue.uppercased()) \($0.value)" }.joined(separator: " / "))
            }
            if i.image.lossless == true { parts.append("lossless") }
            if i.image.frames != .poster {
                let n = i.image.frames.stillCount
                parts.append(n == 1 ? "1 frame" : "\(n) frames")
            }
            return parts.joined(separator: " · ")
        case .audio(let a):
            guard let e = a.audio.encoding else { return "No audio" }
            var parts = ["\(e.codec.displayName) audio"]
            if a.container.format != .mp3 { parts.append(".\(a.container.format.rawValue)") }
            if let bitrate = e.bitrate, bitrate != AudioEncoding.standard { parts.append(bitrate) }
            if e.channels != .source { parts.append(e.channels.rawValue) }
            if let depth = e.bitDepth, depth != .source { parts.append("\(depth.rawValue)-bit") }
            return parts.joined(separator: " · ")
        case .video(let v):
            var parts = [v.container.format == .hls ? "HLS" : "MP4", Catalog.codecName(v.video.codec)]
            parts.append(describeSizes(v.renditions, label: effectiveLabel))
            if let fit = fit(of: v.renditions), fit != .contain { parts.append(fit.rawValue) }
            if upscales(v.renditions) { parts.append("upscale") }
            if v.video.color != .sdr { parts.append(v.video.color.rawValue.uppercased()) }
            switch v.video.rate {
            case .crf(let crf): parts.append("crf \(crf)")
            case .cbr(let cbr): parts.append(describeCbr(v, cbr))
            case .quality(let level): parts.append(level.replacingOccurrences(of: "_", with: " "))
            }
            return parts.joined(separator: " · ")
        }
    }

    private static func describeSizes(_ renditions: Renditions, label: (RenditionSize) -> String) -> String {
        switch renditions {
        case .sizes(let sizes): return sizes.map(label).joined(separator: " / ")
        case .ladder(let ladder): return "ladder ≤ \(ladder.maxShortSide)p"
        case .sourceSize: return "source size"
        }
    }

    /// The fit every size shares; nil when they differ.
    private static func fit(of renditions: Renditions) -> Fit? {
        switch renditions {
        case .sizes(let sizes): return Set(sizes.map(\.fit)).count == 1 ? sizes.first?.fit : nil
        case .ladder(let l): return l.fit
        case .sourceSize(let s): return s.fit
        }
    }

    private static func upscales(_ renditions: Renditions) -> Bool {
        switch renditions {
        case .sizes(let sizes): return sizes.contains(where: \.upscale)
        case .ladder(let l): return l.upscale
        case .sourceSize(let s): return s.upscale
        }
    }

    /// `CBR 5 / 3 Mb/s`, `CBR 5 Mb/s` or `CBR (standard rates)`.
    fileprivate static func describeCbr(_ output: VideoOutput, _ cbr: ConstantBitRate) -> String {
        let shared = cbr.bitrate == ConstantBitRate.standard ? nil : parseBitrate(cbr.bitrate)
        let fps: Double? = { if case .fps(let n) = output.video.frameRate.max { return n }; return nil }()
        let rates: [Int]
        switch output.renditions {
        case .sizes(let sizes) where shared != nil || sizes.contains(where: { $0.cbrBitrate.flatMap(parseBitrate) != nil }):
            rates = sizes.map { s in
                s.cbrBitrate.flatMap(parseBitrate) ?? shared
                    ?? standardCbrRate(codec: output.video.codec, width: s.width, height: s.height, fps: fps)
            }
        default:
            guard let shared else { return "CBR (standard rates)" }
            rates = [shared]
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

    public static let tierLabels: [Tier: String] = [
        .sd: "SD (≤ 576p)", .hd: "HD (≤ 1440p)", .uhd: "UHD (> 1440p)",
        .upTo1mp: "Image (≤ 1 MP)", .upTo4mp: "Image (≤ 4 MP)", .over4mp: "Image (> 4 MP)",
    ]

    /// Tier of an output image by its pixel count.
    public static func imageTier(width: Int, height: Int) -> Tier {
        let pixels = width * height
        return pixels <= 1_000_000 ? .upTo1mp : pixels <= 4_000_000 ? .upTo4mp : .over4mp
    }

    /// Fallback rates (dollars per output minute) when the API has not said.
    public static let rates = (sd: 0.005, hd: 0.01, uhd: 0.025)
}
