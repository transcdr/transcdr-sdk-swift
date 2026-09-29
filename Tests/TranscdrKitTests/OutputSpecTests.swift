import XCTest
@testable import TranscdrKit

/// The v2 output spec: its shape on the wire, the required-field table, and the requests that
/// carry it.
final class OutputSpecTests: XCTestCase {
    private func j(_ value: JSONValue) -> JSONValue { value }

    // MARK: The documented examples, built in code

    /// ABR HLS, H.264 at a constant bit rate.
    static let hlsCbr = OutputSpec.video(VideoOutput(
        container: .hls(segmentSeconds: 6),
        video: VideoSettings(
            codec: .h264, rate: .cbr(ConstantBitRate(bitrate: "standard", bufferMs: 1000)), bitDepth: .eight, color: .sdr,
            frameRate: .source, gop: .segment, filters: []
        ),
        audio: .encode(AudioEncoding(
            codec: .aac, bitrate: "standard", channels: .source, heAac: .auto, stereoFallback: false, bitDepth: nil,
            flacCompression: nil
        )),
        renditions: .sizes([
            RenditionSize(label: .bySize, width: 1920, height: 1080, fit: .contain, orientation: .auto, upscale: false, cbrBitrate: "5M"),
            RenditionSize(label: .bySize, width: 1280, height: 720, fit: .contain, orientation: .auto, upscale: false, cbrBitrate: "3M"),
        ]),
        subtitles: .tracks(.all), trim: .whole, privacy: .preset(.stripAll)
    ))

    static let hlsCbrJSON: JSONValue = [
        "kind": "video",
        "container": ["format": "hls", "segment_seconds": 6],
        "video": [
            "codec": "h264", "cbr": ["bitrate": "standard", "buffer_ms": 1000], "bit_depth": "8bit",
            "color": "sdr", "frame_rate": ["max": "source"], "gop": "segment", "filters": [],
        ],
        "audio": [
            "handling": "encode", "codec": "aac", "bitrate": "standard", "channels": "source",
            "he_aac": "auto", "stereo_fallback": false,
        ],
        "renditions": ["sizes": [
            ["label": "by_size", "width": 1920, "height": 1080, "fit": "contain", "orientation": "auto", "upscale": false, "video": ["cbr": ["bitrate": "5M"]]],
            ["label": "by_size", "width": 1280, "height": 720, "fit": "contain", "orientation": "auto", "upscale": false, "video": ["cbr": ["bitrate": "3M"]]],
        ]],
        "subtitles": ["tracks": "all"], "trim": ["start": 0, "end": "source"], "privacy": ["preset": "strip_all"],
    ]

    /// A single vertical MP4.
    static let mp4 = OutputSpec.video(VideoOutput(
        container: .mp4,
        video: VideoSettings(
            codec: .h264, rate: .quality("high"), bitDepth: .fromColor, color: .sdr, frameRate: .max(30),
            gop: .seconds(2), filters: []
        ),
        audio: .encode(AudioEncoding(
            codec: .aac, bitrate: "standard", channels: .source, heAac: .auto, stereoFallback: nil, bitDepth: nil,
            flacCompression: nil
        )),
        renditions: .sizes([
            RenditionSize(label: .bySize, width: 1080, height: 1920, fit: .cover, orientation: .fixed, upscale: false, cbrBitrate: nil),
        ]),
        subtitles: .tracks(.all), trim: .whole, privacy: .preset(.stripAll)
    ))

    /// Audio-only MP3.
    static let mp3 = OutputSpec.audio(AudioOutput(
        container: .mp3,
        audio: .encode(AudioEncoding(
            codec: .mp3, bitrate: "64k", channels: .mono, heAac: .auto, stereoFallback: nil, bitDepth: nil, flacCompression: nil
        )),
        privacy: .preset(.stripAll)
    ))

    /// Stills from a video.
    static let stills = OutputSpec.image(ImageOutput(
        image: ImageSettings(formats: [.jpeg], lossless: nil, quality: [.jpeg: 80], colorProfile: .srgb, frames: .count(12)),
        renditions: .sizes([
            RenditionSize(label: "sheet", width: 320, height: 320, fit: .contain, orientation: .auto, upscale: false, cbrBitrate: nil),
        ]),
        privacy: .preset(.stripAll)
    ))

    func testTheDocumentedExamplesEncodeAsWrittenAndRoundTrip() throws {
        XCTAssertEqual(try JSONValue.from(Self.hlsCbr), Self.hlsCbrJSON)
        XCTAssertEqual(try JSONValue.from(Self.mp4), [
            "kind": "video", "container": ["format": "mp4"],
            "video": [
                "codec": "h264", "quality": "high", "bit_depth": "from_color", "color": "sdr",
                "frame_rate": ["max": 30], "gop": ["seconds": 2], "filters": [],
            ],
            "audio": ["handling": "encode", "codec": "aac", "bitrate": "standard", "channels": "source", "he_aac": "auto"],
            "renditions": ["sizes": [["label": "by_size", "width": 1080, "height": 1920, "fit": "cover", "orientation": "fixed", "upscale": false]]],
            "subtitles": ["tracks": "all"], "trim": ["start": 0, "end": "source"], "privacy": ["preset": "strip_all"],
        ])
        XCTAssertEqual(try JSONValue.from(Self.mp3), [
            "kind": "audio", "container": ["format": "mp3"],
            "audio": ["handling": "encode", "codec": "mp3", "bitrate": "64k", "channels": "mono", "he_aac": "auto"],
            "privacy": ["preset": "strip_all"],
        ])
        XCTAssertEqual(try JSONValue.from(Self.stills), [
            "kind": "image",
            "image": ["formats": ["jpeg"], "quality": ["jpeg": 80], "color_profile": "srgb", "frames": ["count": 12]],
            "renditions": ["sizes": [["label": "sheet", "width": 320, "height": 320, "fit": "contain", "orientation": "auto", "upscale": false]]],
            "privacy": ["preset": "strip_all"],
        ])
        for spec in [Self.hlsCbr, Self.mp4, Self.mp3, Self.stills] {
            XCTAssertEqual(try TranscdrCoding.decoder.decode(OutputSpec.self, from: TranscdrCoding.encoder.encode(spec)), spec)
            XCTAssertEqual(spec.missingFields, [], "\(spec.kind) is complete")
            XCTAssertEqual(SpecTools.validate(spec, maxShortSide: 2160, maxSizes: 8), [])
        }
    }

    func testEveryExclusiveChoiceDecodes() throws {
        func video(_ fields: JSONValue) throws -> VideoSettings {
            var json = Self.hlsCbrJSON["video"]!.objectValue!
            for k in ["cbr", "gop"] { json[k] = nil }
            for (k, v) in fields.objectValue! { json[k] = v }
            return try JSONValue.object(json).decode(as: VideoSettings.self)
        }
        XCTAssertEqual(try video(["crf": 23, "gop": ["frames": 48]]).rate, .crf(23))
        XCTAssertEqual(try video(["crf": 23, "gop": ["frames": 48]]).gop, .frames(48))
        XCTAssertEqual(try video(["quality": "vmaf=93", "gop": "segment"]).rate, .quality("vmaf=93"))
        XCTAssertEqual(try JSONValue.from(Renditions.ladder(Ladder(maxShortSide: 1080, fit: .contain, upscale: false))),
                       ["ladder": ["max_short_side": 1080, "fit": "contain", "upscale": false]])
        XCTAssertEqual(try j(["source_size": ["label": "by_size", "fit": "pad", "upscale": true]]).decode(as: Renditions.self),
                       .sourceSize(SourceSize(label: .bySize, fit: .pad, upscale: true)))
        XCTAssertEqual(try j(["languages": ["eng", "deu"]]).decode(as: Subtitles.self), .languages(["eng", "deu"]))
        XCTAssertEqual(try j("poster").decode(as: ImageFrames.self), .poster)
        XCTAssertEqual(try j(["at_seconds": [1.5, 10]]).decode(as: ImageFrames.self), .atSeconds([1.5, 10]))
        XCTAssertEqual(try j(["start": 2, "end": 7.5]).decode(as: Trim.self), Trim(start: 2, end: .seconds(7.5)))
        XCTAssertEqual(try j(["handling": "drop"]).decode(as: AudioTrack.self), .drop)
        XCTAssertEqual(try JSONValue.from(AudioTrack.drop), ["handling": "drop"])
        let fields = PrivacyFields(location: .approximate, captureTime: .date, device: .keep, descriptive: .strip)
        XCTAssertEqual(try JSONValue.from(Privacy.fields(fields)),
                       ["location": "approximate", "capture_time": "date", "device": "keep", "descriptive": "strip"])
        XCTAssertEqual(try JSONValue.from(Privacy.fields(fields)).decode(as: Privacy.self), .fields(fields))
        XCTAssertEqual(Privacy.preset(.stripLocation).resolved.captureTime, .keep)
        XCTAssertThrowsError(try j(["kind": "hologram", "privacy": ["preset": "strip_all"]]).decode(as: OutputSpec.self))
    }

    // MARK: The required-field table

    struct Case: Decodable {
        let name: String
        let output: JSONValue
        let errors: [FieldError]
    }

    /// The shared cases every SDK checks: the API's params and messages, every failure, in order.
    func testTheTableReportsWhatTheAPIReports() throws {
        let cases = try decodeFixture("output_validation_cases", as: [Case].self)
        XCTAssertGreaterThan(cases.count, 20)
        for c in cases {
            XCTAssertEqual(OutputRules.check(c.output), c.errors, c.name)
        }
    }

    func testTheTableMatchesCapabilities() throws {
        let caps = try XCTUnwrap(try decodeFixture("capabilities", as: Capabilities.self).output)
        XCTAssertEqual(caps.version, 2)
        XCTAssertEqual(caps.fields.map(\.path), OutputRules.fields.map(\.path))
        XCTAssertEqual(caps.groups.map(\.members), OutputRules.groups.map(\.members))
        XCTAssertEqual(caps.fields.first { $0.path == "audio.bitrate" }?.when.first?["audio.codec"], ["opus", "mp3", "aac"])
        XCTAssertEqual(caps.containers.first { $0.id == .hls }?.audioCodecs.contains(.mp3), false)
        XCTAssertEqual(caps.audioCodecs.first { $0.id == .mp3 }?.maxChannels, 2)
        XCTAssertEqual(caps.compatibility?.v1Responses?.header, "Transcdr-Output-Spec")
    }

    func testConditionalFieldsAreCheckedOnTypedSpecs() {
        guard case .video(var v) = Self.hlsCbr else { return XCTFail() }
        v.audio = .encode(AudioEncoding(codec: .aac, bitrate: nil, channels: .source, heAac: .auto, stereoFallback: nil, bitDepth: nil, flacCompression: nil))
        v.container = Container(format: .hls, segmentSeconds: nil)
        XCTAssertEqual(OutputSpec.video(v).missingFields.map(\.param), [
            "output.container.segment_seconds", "output.audio.bitrate", "output.audio.stereo_fallback",
        ])
        v.container = .mp4
        v.audio = .encode(AudioEncoding(codec: .flac, bitrate: "128k", channels: .source, heAac: .auto, stereoFallback: true, bitDepth: nil, flacCompression: nil))
        XCTAssertEqual(OutputSpec.video(v).missingFields, [
            FieldError(param: "output.audio.bitrate", message: "output.audio.bitrate does not apply here: it applies when kind is video or audio and audio.handling is auto or encode and audio.codec is opus, mp3 or aac. Remove it (or set it to null)."),
            FieldError(param: "output.audio.stereo_fallback", message: "output.audio.stereo_fallback does not apply here: it applies when kind is video and container.format is hls and audio.handling is auto or encode. Remove it (or set it to null)."),
            FieldError(param: "output.audio.bit_depth", message: "output.audio.bit_depth is required when kind is video or audio and audio.handling is auto or encode and audio.codec is flac or alac."),
            FieldError(param: "output.audio.flac_compression", message: "output.audio.flac_compression is required when kind is video or audio and audio.handling is auto or encode and audio.codec is flac."),
        ])
    }

    func testValuesAgainstEachOther() {
        guard case .video(var v) = Self.mp4 else { return XCTFail() }
        v.video.color = .hdr10
        v.video.bitDepth = .eight
        v.video.gop = .segment
        v.audio = .encode(AudioEncoding(codec: .aac, bitrate: "4k", channels: .stereo, heAac: .auto, stereoFallback: nil, bitDepth: nil, flacCompression: nil))
        XCTAssertEqual(SpecTools.validate(.video(v), maxShortSide: 1080, maxSizes: 8), [
            FieldError(param: "output.video.bit_depth", message: "HDR output needs 10-bit: use bit_depth from_color or 10bit."),
            FieldError(param: "output.video.gop", message: "gop \"segment\" is for hls; give {\"seconds\": N} or {\"frames\": N}."),
            FieldError(param: "output.audio.bitrate", message: "Audio bitrate must be between 6k and 512k."),
        ])
        guard case .audio(var a) = Self.mp3 else { return XCTFail() }
        a.audio = .drop
        XCTAssertEqual(SpecTools.validate(.audio(a), maxShortSide: 1080, maxSizes: 8).map(\.param), ["output.audio.handling"])
        a.audio = .auto(AudioEncoding(codec: .aac, bitrate: "32k", channels: .surround51, heAac: .auto, stereoFallback: nil, bitDepth: nil, flacCompression: nil))
        XCTAssertEqual(SpecTools.validate(.audio(a), maxShortSide: 1080, maxSizes: 8).map(\.message), [
            "With handling auto, audio an .mp3 file cannot carry becomes MP3: set codec mp3.",
            "An .mp3 file holds MP3 only, not AAC: set codec mp3, or container m4a.",
            "AAC takes 8k to 288k per channel: 40k to 512k for 5.1.",
        ])
        guard case .image(var i) = Self.stills else { return XCTFail() }
        i.image.quality = [.jpeg: 80, .avif: 60]
        XCTAssertEqual(SpecTools.validate(.image(i), maxShortSide: 1080, maxSizes: 8), [
            FieldError(param: "output.image.quality.avif", message: "avif is not made lossy here, so it takes no quality."),
        ])
        XCTAssertEqual(SpecTools.validate(Self.hlsCbr, maxShortSide: 720, maxSizes: 8).map(\.message), ["Your plan allows renditions up to 720p."])
    }

    // MARK: Overrides

    func testDiffIsAMergePatchAndMergeUndoesIt() throws {
        guard case .video(var v) = Self.mp4 else { return XCTFail() }
        v.video.rate = .crf(23)
        v.video.frameRate = .max(24)
        v.renditions = .ladder(Ladder(maxShortSide: 720, fit: .contain, upscale: false))
        let changed = OutputSpec.video(v)
        let patch = SpecTools.diff(changed, base: Self.mp4)
        XCTAssertEqual(patch.json, [
            "video": ["quality": nil, "crf": 23, "frame_rate": ["max": 24]],
            "renditions": ["sizes": nil, "ladder": ["max_short_side": 720, "fit": "contain", "upscale": false]],
        ])
        XCTAssertEqual(SpecTools.merge(patch, over: Self.mp4), changed)
        XCTAssertEqual(SpecTools.diff(Self.mp4, base: Self.mp4).json, [:])
        XCTAssertEqual(SpecTools.diff(Self.mp4, base: nil).json, try JSONValue.from(Self.mp4), "without a base, the whole spec")

        // One choice of a group clears the others, as the API's merge does.
        let crf: OutputOverrides = ["video": ["crf": 20]]
        guard case .video(let merged)? = SpecTools.merge(crf, over: Self.mp4) else { return XCTFail() }
        XCTAssertEqual(merged.video.rate, .crf(20))
        let privacy: OutputOverrides = ["privacy": ["preset": "keep_all"]]
        XCTAssertEqual(SpecTools.merge(privacy, over: Self.mp3)?.privacy, .preset(.keepAll))
        // A field left dangling makes the result incomplete.
        XCTAssertNil(SpecTools.merge(["container": ["format": "hls"]], over: Self.mp4))
        XCTAssertNotNil(SpecTools.merge(["container": ["format": "hls", "segment_seconds": 4], "video": ["gop": "segment"], "audio": ["stereo_fallback": false]], over: Self.mp4))
    }

    // MARK: Requests

    let job = """
    {"object":"job","id":"job_1","status":"queued","input":{"type":"url","url":"https://x/y.mov"},"priority":"normal",
     "preset":{"id":"social-vertical-1080x1920","version":1,"overrides":{"video":{"frame_rate":{"max":24}}}},
     "output":\(String(decoding: try! TranscdrCoding.encoder.encode(OutputSpecTests.mp4), as: UTF8.self)),
     "progress":{"percent":0,"stage":"waiting","renditions":[]},"outputs":[],"metadata":{},"attempts":0,
     "max_attempts":3,"created_at":"2026-09-27T05:18:43Z"}
    """

    func testAPresetWithOverridesIsSentAsIs() async throws {
        let t = MockTransport([MockTransport.json(201, job)])
        let created = try await client(t).jobs.create(.init(
            input: .url("https://x/y.mov"),
            spec: .preset("social-vertical-1080x1920@1", overrides: ["video": ["frame_rate": ["max": 24]]])
        ))
        XCTAssertEqual(t.sent[0].json?["preset"], "social-vertical-1080x1920@1")
        XCTAssertEqual(t.sent[0].json?["output"], ["video": ["frame_rate": ["max": 24]]])
        XCTAssertEqual(created.preset?.version, 1)
        XCTAssertEqual(created.preset?.pinned, "social-vertical-1080x1920@1")
        XCTAssertEqual(created.preset?.overrides, ["video": ["frame_rate": ["max": 24]]])
        XCTAssertEqual(created.output, Self.mp4)
    }

    func testAWholeSpecIsSentWhole() async throws {
        let t = MockTransport([MockTransport.json(201, job)])
        _ = try await client(t).jobs.create(.init(input: .url("https://x/y.mov"), spec: .output(Self.hlsCbr)))
        XCTAssertNil(t.sent[0].json?["preset"])
        XCTAssertEqual(t.sent[0].json?["output"], Self.hlsCbrJSON)
    }

    func testAnIncompleteSpecIsRefusedBeforeItIsSent() async throws {
        guard case .audio(var a) = Self.mp3 else { return XCTFail() }
        a.audio = .encode(AudioEncoding(codec: .aac, bitrate: nil, channels: .source, heAac: .auto, stereoFallback: nil, bitDepth: nil, flacCompression: nil))
        a.container = .m4a
        let t = MockTransport([MockTransport.json(201, job)])
        do {
            _ = try await client(t).jobs.create(.init(input: .url("https://x/y.mov"), spec: .output(.audio(a))))
            XCTFail("expected an error")
        } catch let e as TranscdrError {
            XCTAssertEqual(e.kind, .invalidRequest)
            XCTAssertEqual(e.code, "validation_failed")
            XCTAssertEqual(e.param, "output.audio.bitrate")
            XCTAssertEqual(e.errors.map(\.param), ["output.audio.bitrate"])
            XCTAssertEqual(e.message, "output.audio.bitrate is required when kind is video or audio and audio.handling is auto or encode and audio.codec is opus, mp3 or aac.")
        }
        XCTAssertTrue(t.sent.isEmpty)
        do {
            _ = try await client(t).presets.create(.init(name: "x", output: .audio(a)))
            XCTFail("expected an error")
        } catch let e as TranscdrError {
            XCTAssertEqual(e.errors.count, 1)
        }
        XCTAssertTrue(t.sent.isEmpty)
    }

    func testEveryFailureOfA422IsKept() async throws {
        let body = #"""
        {"error":{"type":"invalid_request_error","code":"validation_failed","param":"output.audio.bitrate",
         "message":"output.audio.bitrate is required for audio.codec=aac.",
         "errors":[{"param":"output.audio.bitrate","message":"output.audio.bitrate is required for audio.codec=aac."},
                   {"param":"output.video.frame_rate.max","message":"output.video.frame_rate.max is required for kind=video."},
                   {"param":"output.privacy","message":"output.privacy is required."}]}}
        """#
        let t = MockTransport([MockTransport.json(422, body)])
        do {
            _ = try await client(t).jobs.create(.init(input: .url("https://x/y.mov"), spec: .preset("web-av1-1080p", overrides: ["kind": "video"])))
            XCTFail("expected an error")
        } catch let e as TranscdrError {
            XCTAssertEqual(e.status, 422)
            XCTAssertEqual(e.errors.map(\.param), ["output.audio.bitrate", "output.video.frame_rate.max", "output.privacy"])
            XCTAssertEqual(e.fieldErrors["output.privacy"], "output.privacy is required.")
        }
    }

    func testPresetVersions() async throws {
        let spec = String(decoding: try TranscdrCoding.encoder.encode(Self.mp3), as: UTF8.self)
        let preset = #"{"object":"preset","id":"pre_1","slug":"podcast","name":"Podcast","version":3,"output":\#(spec)}"#
        let t = MockTransport([
            MockTransport.json(200, #"{"object":"list","data":[{"object":"preset_version","version":1,"output":\#(spec),"created_at":"2026-09-01T00:00:00Z"},{"object":"preset_version","version":2,"output":\#(spec),"created_at":null}],"has_more":false}"#),
            MockTransport.json(200, preset),
        ])
        let c = client(t)
        let versions = try await c.presets.versions("podcast")
        XCTAssertEqual(versions.map(\.version), [1, 2])
        XCTAssertNotNil(versions[0].createdAt)
        XCTAssertEqual(versions[1].output, Self.mp3)
        XCTAssertEqual(t.sent[0].url.path, "/v1/presets/podcast/versions")
        let two = try await c.presets.version("podcast", 3)
        XCTAssertEqual(t.sent[1].url.path, "/v1/presets/podcast@3")
        XCTAssertEqual(two.version, 3)
        let decoded = try TranscdrCoding.decoder.decode(Preset.self, from: Data(preset.utf8))
        XCTAssertEqual(decoded.pinned, "podcast@3")
    }

    func testRecordedResponsesDecode() throws {
        let jobs = try decodeFixture("jobs", as: ListResponse<Job>.self)
        XCTAssertTrue(jobs.data.allSatisfy { $0.output.missingFields.isEmpty })
        let fromPreset = try XCTUnwrap(jobs.data.first { $0.presetId != nil })
        XCTAssertEqual(fromPreset.preset?.id, fromPreset.presetId)
        XCTAssertNil(jobs.data.first { $0.presetId == nil }?.preset)
        let automations = try decodeFixture("automations", as: ListResponse<Automation>.self)
        XCTAssertTrue(automations.data.allSatisfy { $0.output.isEmpty && $0.resolvedOutput != nil })
        let presets = try decodeFixture("presets", as: ListResponse<Preset>.self)
        XCTAssertTrue(presets.data.allSatisfy { $0.version == 1 })
        let resolved = presets.data.first { $0.slug == automations.data[0].preset }?.output
        XCTAssertEqual(AutomationHelpers.editableSpec(override: automations.data[0].output, preset: resolved), resolved)
    }

    // MARK: Describing and estimating

    func testDescribe() {
        XCTAssertEqual(SpecTools.describe(Self.hlsCbr), "HLS · H.264 · 1080p / 720p · CBR 5 / 3 Mb/s")
        XCTAssertEqual(SpecTools.describe(Self.mp4), "MP4 · H.264 · 1080p · cover · high")
        XCTAssertEqual(SpecTools.describe(Self.mp3), "MP3 audio · 64k · mono")
        XCTAssertEqual(SpecTools.describe(Self.stills), "Images · JPEG · sheet · quality 80 · 12 frames")
        guard case .video(var v) = Self.hlsCbr else { return XCTFail() }
        v.renditions = .ladder(Ladder(maxShortSide: 1080, fit: .contain, upscale: false))
        XCTAssertEqual(SpecTools.describe(.video(v)), "HLS · H.264 · ladder ≤ 1080p · CBR (standard rates)")
        XCTAssertEqual(SpecTools.describe(nil), "—")
    }

    func testStandardCbrRates() {
        let h264 = { (side: Int) in SpecTools.standardCbrRate(codec: .h264, width: side * 16 / 9, height: side, fps: nil) }
        XCTAssertEqual([h264(360), h264(480), h264(720), h264(1080)], [800_000, 1_200_000, 3_000_000, 5_000_000])
        XCTAssertEqual(SpecTools.standardCbrRate(codec: .h265, width: 1920, height: 1080, fps: nil), 3_250_000)
        XCTAssertEqual(SpecTools.standardCbrRate(codec: .av1, width: 1920, height: 1080, fps: nil), 2_500_000)
        XCTAssertEqual(SpecTools.standardCbrRate(codec: .h264, width: 1920, height: 1080, fps: 60), 7_500_000)
        XCTAssertEqual(SpecTools.formatBitrate(3_250_000), "3.25M")
        XCTAssertTrue(SpecTools.isQualityLevel("vmaf=93"))
        XCTAssertFalse(SpecTools.isQualityLevel("cbr"))
    }

    func testDisplaySizeDecodes() throws {
        let info = try JSONDecoder().decode(
            MediaInfo.self, from: Data(#"{"width":720,"height":576,"display_width":1024,"display_height":576}"#.utf8)
        )
        XCTAssertEqual(info.displayWidth, 1024)
        XCTAssertEqual(info.displayHeight, 576)
    }
}
