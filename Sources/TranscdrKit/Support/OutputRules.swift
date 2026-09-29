import Foundation

/// Which fields an output spec needs, as data: a copy of the API's required-field table (the
/// same one `GET /v1/capabilities` lists under `output.fields` and `output.groups`), and the
/// check that reads it. The check reports every missing field, every field that does not apply,
/// and every exclusive group with no choice or more than one, in the API's order and with the
/// API's params and messages, so a spec can be checked before it is sent.
public enum OutputRules {
    /// One term of a condition: a path and the values it may have there (an array holds when
    /// any element does); `"*"` means present and `"!"` absent.
    public typealias Term = (path: String, values: [String])
    /// Any one of its clauses; a clause holds when each of its terms does.
    public typealias Condition = [[Term]]

    public enum Need: Hashable, Sendable {
        /// Needed whenever its condition holds.
        case required
        /// Allowed whenever its condition holds.
        case optional
        /// One choice of an exclusive group.
        case choice(String)
    }

    public struct Field: @unchecked Sendable {
        /// Relative to `output`; `[]` stands for each entry of a list.
        public let path: String
        public let need: Need
        /// An object whose own fields are checked; never reported missing itself.
        public let object: Bool
        public let when: Condition

        init(path: String, _ need: Need, object: Bool, when: Condition) {
            self.path = path
            self.need = need
            self.object = object
            self.when = when
        }
    }

    public struct Group: @unchecked Sendable {
        public let name: String
        public let parent: String
        public let members: [String]
        public let when: Condition
    }

    /// Every field, in document order.
    public static let fields: [Field] = [
        Field(path: "kind", .required, object: false, when: [[]]),
        Field(path: "container", .required, object: true, when: [[("kind", ["video", "audio"])]]),
        Field(path: "container.format", .required, object: false, when: [[("kind", ["video", "audio"])]]),
        Field(path: "container.segment_seconds", .required, object: false, when: [[("kind", ["video"]), ("container.format", ["hls"])]]),
        Field(path: "video", .required, object: true, when: [[("kind", ["video"])]]),
        Field(path: "video.codec", .required, object: false, when: [[("kind", ["video"])]]),
        Field(path: "video.quality", .choice("video.rate"), object: false, when: [[("kind", ["video"])]]),
        Field(path: "video.crf", .choice("video.rate"), object: false, when: [[("kind", ["video"])]]),
        Field(path: "video.cbr", .choice("video.rate"), object: true, when: [[("kind", ["video"])]]),
        Field(path: "video.cbr.bitrate", .required, object: false, when: [[("kind", ["video"]), ("video.cbr", ["*"])]]),
        Field(path: "video.cbr.buffer_ms", .required, object: false, when: [[("kind", ["video"]), ("video.cbr", ["*"])]]),
        Field(path: "video.bit_depth", .required, object: false, when: [[("kind", ["video"])]]),
        Field(path: "video.color", .required, object: false, when: [[("kind", ["video"])]]),
        Field(path: "video.frame_rate", .required, object: true, when: [[("kind", ["video"])]]),
        Field(path: "video.frame_rate.max", .required, object: false, when: [[("kind", ["video"])]]),
        Field(path: "video.gop", .required, object: false, when: [[("kind", ["video"])]]),
        Field(path: "video.filters", .required, object: false, when: [[("kind", ["video"])]]),
        Field(path: "audio", .required, object: true, when: [[("kind", ["video", "audio"])]]),
        Field(path: "audio.handling", .required, object: false, when: [[("kind", ["video", "audio"])]]),
        Field(path: "audio.codec", .required, object: false, when: [[("kind", ["video", "audio"]), ("audio.handling", ["auto", "encode"])]]),
        Field(path: "audio.bitrate", .required, object: false, when: [[("kind", ["video", "audio"]), ("audio.handling", ["auto", "encode"]), ("audio.codec", ["opus", "mp3", "aac"])]]),
        Field(path: "audio.channels", .required, object: false, when: [[("kind", ["video", "audio"]), ("audio.handling", ["auto", "encode"])]]),
        Field(path: "audio.he_aac", .required, object: false, when: [[("kind", ["video", "audio"]), ("audio.handling", ["auto", "encode"])]]),
        Field(path: "audio.stereo_fallback", .required, object: false, when: [[("kind", ["video"]), ("container.format", ["hls"]), ("audio.handling", ["auto", "encode"])]]),
        Field(path: "audio.bit_depth", .required, object: false, when: [[("kind", ["video", "audio"]), ("audio.handling", ["auto", "encode"]), ("audio.codec", ["flac", "alac"])]]),
        Field(path: "audio.flac_compression", .required, object: false, when: [[("kind", ["video", "audio"]), ("audio.handling", ["auto", "encode"]), ("audio.codec", ["flac"])]]),
        Field(path: "image", .required, object: true, when: [[("kind", ["image"])]]),
        Field(path: "image.formats", .required, object: false, when: [[("kind", ["image"])]]),
        Field(path: "image.lossless", .required, object: false, when: [[("kind", ["image"]), ("image.formats", ["webp"])]]),
        Field(path: "image.quality", .required, object: false, when: [[("kind", ["image"]), ("image.formats", ["avif", "jpeg"])], [("kind", ["image"]), ("image.formats", ["webp"]), ("image.lossless", ["false"])]]),
        Field(path: "image.color_profile", .required, object: false, when: [[("kind", ["image"])]]),
        Field(path: "image.frames", .required, object: false, when: [[("kind", ["image"])]]),
        Field(path: "renditions", .required, object: true, when: [[("kind", ["video", "image"])]]),
        Field(path: "renditions.sizes", .choice("renditions"), object: false, when: [[("kind", ["video", "image"])]]),
        Field(path: "renditions.ladder", .choice("renditions"), object: true, when: [[("kind", ["video"])]]),
        Field(path: "renditions.source_size", .choice("renditions"), object: true, when: [[("kind", ["video", "image"])]]),
        Field(path: "renditions.sizes[].label", .required, object: false, when: [[("kind", ["video", "image"]), ("renditions.sizes", ["*"])]]),
        Field(path: "renditions.sizes[].width", .required, object: false, when: [[("kind", ["video", "image"]), ("renditions.sizes", ["*"])]]),
        Field(path: "renditions.sizes[].height", .required, object: false, when: [[("kind", ["video", "image"]), ("renditions.sizes", ["*"])]]),
        Field(path: "renditions.sizes[].fit", .required, object: false, when: [[("kind", ["video", "image"]), ("renditions.sizes", ["*"])]]),
        Field(path: "renditions.sizes[].orientation", .required, object: false, when: [[("kind", ["video", "image"]), ("renditions.sizes", ["*"])]]),
        Field(path: "renditions.sizes[].upscale", .required, object: false, when: [[("kind", ["video", "image"]), ("renditions.sizes", ["*"])]]),
        Field(path: "renditions.sizes[].video", .optional, object: false, when: [[("kind", ["video"]), ("video.cbr", ["*"]), ("renditions.sizes", ["*"])]]),
        Field(path: "renditions.ladder.max_short_side", .required, object: false, when: [[("kind", ["video"]), ("renditions.ladder", ["*"])]]),
        Field(path: "renditions.ladder.fit", .required, object: false, when: [[("kind", ["video"]), ("renditions.ladder", ["*"])]]),
        Field(path: "renditions.ladder.upscale", .required, object: false, when: [[("kind", ["video"]), ("renditions.ladder", ["*"])]]),
        Field(path: "renditions.source_size.label", .required, object: false, when: [[("kind", ["video", "image"]), ("renditions.source_size", ["*"])]]),
        Field(path: "renditions.source_size.fit", .required, object: false, when: [[("kind", ["video", "image"]), ("renditions.source_size", ["*"])]]),
        Field(path: "renditions.source_size.upscale", .required, object: false, when: [[("kind", ["video", "image"]), ("renditions.source_size", ["*"])]]),
        Field(path: "subtitles", .required, object: true, when: [[("kind", ["video"])]]),
        Field(path: "subtitles.tracks", .choice("subtitles"), object: false, when: [[("kind", ["video"])]]),
        Field(path: "subtitles.languages", .choice("subtitles"), object: false, when: [[("kind", ["video"])]]),
        Field(path: "trim", .required, object: true, when: [[("kind", ["video"])]]),
        Field(path: "trim.start", .required, object: false, when: [[("kind", ["video"])]]),
        Field(path: "trim.end", .required, object: false, when: [[("kind", ["video"])]]),
        Field(path: "privacy", .required, object: true, when: [[]]),
        Field(path: "privacy.preset", .optional, object: false, when: [[]]),
        Field(path: "privacy.location", .required, object: false, when: [[("privacy.preset", ["!"])]]),
        Field(path: "privacy.capture_time", .required, object: false, when: [[("privacy.preset", ["!"])]]),
        Field(path: "privacy.device", .required, object: false, when: [[("privacy.preset", ["!"])]]),
        Field(path: "privacy.descriptive", .required, object: false, when: [[("privacy.preset", ["!"])]]),
    ]

    /// The exclusive groups.
    public static let groups: [Group] = [
        Group(name: "video.rate", parent: "video", members: ["video.quality", "video.crf", "video.cbr"], when: [[("kind", ["video"])]]),
        Group(name: "renditions", parent: "renditions", members: ["renditions.sizes", "renditions.ladder", "renditions.source_size"], when: [[("kind", ["video", "image"])]]),
        Group(name: "subtitles", parent: "subtitles", members: ["subtitles.tracks", "subtitles.languages"], when: [[("kind", ["video"])]]),
    ]

    // MARK: Reading a document

    /// The value at a dotted path; nil when absent or `null`.
    public static func lookup(_ document: JSONValue, _ path: String) -> JSONValue? {
        var at = document
        for key in path.split(separator: ".", omittingEmptySubsequences: false) {
            guard let next = at[String(key)] else { return nil }
            at = next
        }
        return at.isNull ? nil : at
    }

    private static func text(_ value: JSONValue) -> String? {
        switch value {
        case .string(let s): return s
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return n.rounded() == n && abs(n) < 1e15 ? String(Int64(n)) : String(n)
        default: return nil
        }
    }

    private static func termHolds(_ document: JSONValue, _ path: String, _ values: [String]) -> Bool {
        let found = lookup(document, path)
        if values == ["*"] { return found != nil }
        if values == ["!"] { return found == nil }
        switch found {
        case .array(let items)?: return items.contains { text($0).map(values.contains) ?? false }
        case let value?: return text(value).map(values.contains) ?? false
        case nil: return false
        }
    }

    /// Whether a condition holds for a document.
    public static func holds(_ document: JSONValue, _ condition: Condition) -> Bool {
        condition.contains { clause in clause.allSatisfy { termHolds(document, $0.path, $0.values) } }
    }

    private static func orList(_ items: [String]) -> String {
        items.count <= 1 ? items.joined() : items.dropLast().joined(separator: ", ") + " or " + items[items.count - 1]
    }

    /// A condition in words: `kind is video and container.format is hls`.
    public static func describe(_ condition: Condition) -> String {
        condition.map { clause in
            clause.map { term in
                switch term.values {
                case ["*"]: return "\(term.path) is given"
                case ["!"]: return "\(term.path) is not given"
                default: return "\(term.path) is \(orList(term.values))"
                }
            }.joined(separator: " and ")
        }.joined(separator: ", or ")
    }

    /// A field's instances: one for a plain path, one per entry below a `[]`.
    private static func instances(_ document: JSONValue, _ path: String) -> [(String, JSONValue?)] {
        guard let marker = path.range(of: "[].") else { return [(path, lookup(document, path))] }
        let list = String(path[..<marker.lowerBound])
        let rest = String(path[marker.upperBound...])
        guard case .array(let items)? = lookup(document, list) else { return [] }
        return items.enumerated().map { i, item in ("\(list).\(i).\(rest)", item.objectValue != nil ? lookup(item, rest) : nil) }
    }

    private static func error(_ path: String, _ message: String) -> FieldError {
        FieldError(param: path.isEmpty ? "output" : "output.\(path)", message: message)
    }

    /// Check a document (an `output` as JSON) against the table. Every failure is reported, in
    /// the API's order: missing and inapplicable fields in document order, then the groups.
    /// Values against each other (HDR needs 10-bit, an `.mp3` holds MP3) are
    /// `SpecTools.validate`'s.
    public static func check(_ document: JSONValue) -> [FieldError] {
        guard document.objectValue != nil else { return [error("", "output must be an object.")] }
        guard let kind = lookup(document, "kind") else {
            return [error("kind", "output.kind is required: video, audio or image.")]
        }
        guard let k = kind.stringValue, ["video", "audio", "image"].contains(k) else {
            return [error("kind", "output.kind must be video, audio or image.")]
        }
        var errors: [FieldError] = []
        let privacyMissing = lookup(document, "privacy") == nil
        if privacyMissing {
            errors.append(error(
                "privacy",
                "output.privacy is required: give privacy.preset (strip_all, strip_location or keep_all), or all of location, capture_time, device and descriptive."
            ))
        }
        var refused: [String] = []
        for field in fields {
            if privacyMissing && field.path.hasPrefix("privacy") { continue }
            let applies = holds(document, field.when)
            for (path, value) in instances(document, field.path) {
                if refused.contains(where: { path.hasPrefix($0 + ".") }) { continue }
                if value != nil && !applies { refused.append(path) }
                if value == nil, applies, field.need == .required, !field.object {
                    errors.append(error(path, "output.\(path) is required when \(describe(field.when))."))
                } else if value != nil, !applies {
                    errors.append(error(
                        path,
                        "output.\(path) does not apply here: it applies when \(describe(field.when)). Remove it (or set it to null)."
                    ))
                }
            }
        }
        for group in groups where holds(document, group.when) {
            let given = group.members.filter { lookup(document, $0) != nil }
            let names = group.members.map { $0.split(separator: ".").last.map(String.init) ?? $0 }
            if given.isEmpty {
                errors.append(error(group.parent, "output.\(group.parent) needs one of \(orList(names))."))
            } else if given.count > 1 {
                errors.append(error(
                    given[1],
                    "output.\(group.parent) takes one of \(orList(names)), not \(given.joined(separator: " and "))."
                ))
            }
        }
        return errors
    }
}

extension OutputSpec {
    /// This spec against the API's required-field table: every missing or inapplicable field and
    /// every exclusive group without exactly one choice. Empty when it is complete.
    public var missingFields: [FieldError] {
        guard let json = try? JSONValue.from(self) else { return [] }
        return OutputRules.check(json)
    }

    /// A document (an `output` as JSON) against the API's required-field table.
    public static func validate(_ document: JSONValue) -> [FieldError] { OutputRules.check(document) }
}
