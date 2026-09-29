import XCTest
@testable import TranscdrKit

final class ImageOutputTests: XCTestCase {
    private func image(_ settings: ImageSettings?, renditions: [Rendition] = [Rendition(width: 1920, height: 1920)]) -> OutputSpec {
        OutputSpec(mode: .image, renditions: renditions, image: settings)
    }

    func testImageSpecEncodesAsSentAndRoundTrips() throws {
        let spec = image(
            ImageSettings(
                formats: [.avif, .jpeg], quality: 70, lossless: false, keepColorProfile: true,
                frames: ImageFrames(atSeconds: [1.5, 10])
            ),
            renditions: [Rendition(width: 1920, height: 1920), Rendition(width: 641, height: 17, label: "small")]
        )
        XCTAssertEqual(
            try JSONValue.from(spec),
            [
                "mode": "image",
                "renditions": [["width": 1920, "height": 1920], ["width": 641, "height": 17, "label": "small"]],
                "image": [
                    "formats": ["avif", "jpeg"],
                    "quality": 70,
                    "lossless": false,
                    "keep_color_profile": true,
                    "frames": ["at_seconds": [1.5, 10]],
                ],
            ]
        )
        XCTAssertEqual(try JSONDecoder().decode(OutputSpec.self, from: JSONEncoder().encode(spec)), spec)
        // Unset fields are left out, and so is `image` when it is nil.
        XCTAssertEqual(try JSONValue.from(ImageSettings(frames: ImageFrames(count: 12))), ["frames": ["count": 12]])
        XCTAssertNil(try JSONValue.from(OutputSpec(mode: .single)).objectValue?["image"])
        var cleared = OutputSpec(mode: .single)
        cleared.clear = [.image]
        XCTAssertEqual(try JSONValue.from(cleared), ["mode": "single", "image": nil])
        XCTAssertFalse(OutputSpec(image: ImageSettings()).isEmpty)

        XCTAssertEqual(OutputMode.all.last, .image)
        XCTAssertEqual(ImageFormat.all.map(\.rawValue), ["avif", "webp", "jpeg", "png"])
        XCTAssertEqual(Tier.imageTiers.map(\.rawValue), ["up_to_1mp", "up_to_4mp", "over_4mp"])
        XCTAssertEqual(PresetCategory.all.last, .image)
    }

    func testImageJobDecodes() throws {
        let json = #"""
        {"object":"job","id":"job_1","status":"completed","input":{"type":"asset","asset_id":"ast_1"},
         "output":{"mode":"image","renditions":[{"width":640,"height":640,"label":"small"}],"fit":"contain","upscale":false,
                   "image":{"formats":["avif","jpeg"],"frames":{"count":2}}},
         "progress":{"percent":100,"stage":"done","renditions":[]},
         "outputs":[
           {"label":"small-001.avif","width":640,"height":480,"frames":1,"bytes":21000,"content_type":"image/avif",
            "path":"small-001.avif","url":"https://x/1","format":"avif","rendition":"small","frame":1,"at_seconds":3.3},
           {"label":"small-002.jpg","width":640,"height":480,"frames":1,"bytes":48000,"content_type":"image/jpeg",
            "path":"small-002.jpg","url":"https://x/2","format":"jpeg","rendition":"small","frame":2,"at_seconds":6.6}],
         "billing":{"billable_minutes":0,"billable_images":2,"amount_cents":1,"amount_usd":0.002,"tier":"up_to_1mp"},
         "metadata":{},"attempts":1,"max_attempts":3,"priority":"normal",
         "created_at":"2026-09-29T00:00:00Z","updated_at":"2026-09-29T00:00:10Z"}
        """#
        let job = try TranscdrCoding.decoder.decode(Job.self, from: Data(json.utf8))
        XCTAssertEqual(job.output.mode, .image)
        XCTAssertEqual(job.output.image?.formats, [.avif, .jpeg])
        XCTAssertEqual(job.output.image?.frames?.count, 2)
        XCTAssertEqual(job.outputs.count, 2)
        let still = job.outputs[1]
        XCTAssertEqual(still.format, .jpeg)
        XCTAssertEqual(still.rendition, "small")
        XCTAssertEqual(still.frame, 2)
        XCTAssertEqual(still.atSeconds, 6.6)
        XCTAssertEqual(job.billing?.billableImages, 2)
        XCTAssertEqual(job.billing?.tier, .upTo1mp)
        XCTAssertTrue(job.billing?.tier?.isImage == true)

        // A video job from an older server has none of the image fields.
        let video = try decodeFixture("job", as: Job.self)
        XCTAssertNil(video.output.image)
        XCTAssertNil(video.billing?.billableImages)
        XCTAssertNil(video.outputs.first?.format)
        XCTAssertNil(video.outputs.first?.frame)
    }

    func testImageBillingUsageAndCapabilitiesDecode() throws {
        let rates = #"{"unit":"output_image","currency":"usd","up_to_1mp":0.001,"up_to_4mp":0.002,"over_4mp":0.004,"tiers":{"up_to_1mp":"up to 1 megapixel"}}"#
        let plan = try TranscdrCoding.decoder.decode(Plan.self, from: Data(#"{"id":"free","image_rates":\#(rates)}"#.utf8))
        XCTAssertEqual(plan.imageRates?.over4mp, 0.004)
        XCTAssertEqual(plan.imageRates?.rate(for: .upTo4mp), 0.002)
        XCTAssertEqual(plan.imageRates?.tiers["up_to_1mp"], "up to 1 megapixel")

        let usage = try TranscdrCoding.decoder.decode(Usage.self, from: Data(#"""
        {"from":"2026-09-01","to":"2026-09-30","granularity":"day",
         "totals":{"jobs":2,"billable_minutes":1.5,"billable_images":4,"input_minutes":1.5,"output_bytes":9,"amount_cents":3,"amount_usd":0.025},
         "by_tier":{"sd":0,"hd":1.5,"uhd":0},"by_image_tier":{"up_to_1mp":1,"up_to_4mp":1,"over_4mp":2},
         "by_codec":{"av1":1.5},
         "series":[{"date":"2026-09-01","jobs":2,"billable_minutes":1.5,"billable_images":4,"amount_cents":3,"amount_usd":0.025}]}
        """#.utf8))
        XCTAssertEqual(usage.totals.billableImages, 4)
        XCTAssertEqual(usage.byImageTier["over_4mp"], 2)
        XCTAssertEqual(usage.series.first?.billableImages, 4)

        let statement = try TranscdrCoding.decoder.decode(Statement.self, from: Data(#"""
        {"id":"inv_1","usage_minutes":1.5,"usage_images":4,"usage_cents":3,
         "lines":[{"description":"Images drawn from credit","kind":"usage","quantity":4,"unit":"output_image","credit_usd":-0.004}]}
        """#.utf8))
        XCTAssertEqual(statement.usageImages, 4)
        XCTAssertEqual(statement.lines.first?.unit, "output_image")

        let caps = try TranscdrCoding.decoder.decode(Capabilities.self, from: Data(#"""
        {"image_formats":[
           {"id":"avif","name":"AVIF","default":true,"lossy":true,"lossless":false,"alpha":true,"default_quality":60},
           {"id":"png","name":"PNG","default":false,"lossy":false,"lossless":true,"alpha":true}],
         "input_image_formats":["jpeg","png","heic"],
         "limits":{"max_renditions":8,"image":{"min_dimension":16,"max_dimension":8192,"max_outputs":200,"max_frames":100,"max_input_megapixels":100}}}
        """#.utf8))
        XCTAssertEqual(caps.imageFormats.map(\.id), [.avif, .png])
        XCTAssertTrue(caps.imageFormats[0].isDefault)
        XCTAssertEqual(caps.imageFormats[0].defaultQuality, 60)
        XCTAssertNil(caps.imageFormats[1].defaultQuality)
        XCTAssertEqual(caps.inputImageFormats, ["jpeg", "png", "heic"])
        XCTAssertEqual(caps.imageLimits?.maxDimension, 8192)
        XCTAssertEqual(caps.imageLimits?.maxOutputs, 200)

        // The recorded responses predate image output: every image field is empty.
        let billing = try decodeFixture("billing", as: Billing.self)
        XCTAssertEqual(billing.usageImages, 0)
        let old = try decodeFixture("capabilities", as: Capabilities.self)
        XCTAssertTrue(old.imageFormats.isEmpty)
        XCTAssertNil(old.imageLimits)
        let oldUsage = try decodeFixture("usage", as: Usage.self)
        XCTAssertEqual(oldUsage.totals.billableImages, 0)
        XCTAssertTrue(oldUsage.byImageTier.isEmpty)
    }

    func testValidateImageSpecs() {
        // Image renditions may be odd and 16–8192 on a side; the video defaults are not "set".
        let ok = image(
            ImageSettings(formats: [.avif, .jpeg], quality: 70),
            renditions: [Rendition(width: 8192, height: 17), Rendition(width: 641, height: 16, label: "small")]
        )
        XCTAssertEqual(SpecTools.validate(SpecTools.resolved(ok)), [:])
        XCTAssertEqual(SpecTools.validate(image(nil, renditions: [])), [:])

        let errors = SpecTools.validate(image(nil, renditions: [
            Rendition(width: 15, height: 9000), Rendition(width: 640, height: 640, bitrate: "3M"),
        ]))
        XCTAssertEqual(errors["output.renditions.0.width"], "An image rendition's width must be between 16 and 8192.")
        XCTAssertEqual(errors["output.renditions.0.height"], "An image rendition's height must be between 16 and 8192.")
        XCTAssertEqual(errors["output.renditions.1.bitrate"], "An image rendition has no bitrate.")
        XCTAssertEqual(
            SpecTools.validate(image(nil, renditions: [Rendition(width: 640, height: 640), Rendition(width: 640, height: 640)]))["output.renditions"],
            "Two renditions share a label; give them distinct labels."
        )

        var video = image(nil)
        video.codec = .h264
        video.trim = Trim(start: 2)
        video.audio = AudioSettings(mode: .aac)
        let refused = SpecTools.validate(video)
        XCTAssertEqual(refused["output.codec"], "Image output makes still images, so codec does not apply.")
        XCTAssertEqual(refused["output.trim"], "Image output makes still images, so trim does not apply.")
        XCTAssertEqual(refused["output.audio"], "Image output makes still images, so audio does not apply.")

        func error(_ settings: ImageSettings, _ key: String) -> String? {
            SpecTools.validate(image(settings))["output.\(key)"]
        }
        XCTAssertEqual(error(ImageSettings(formats: []), "image.formats"), "Give one to four formats: avif, webp, jpeg, png.")
        XCTAssertEqual(error(ImageSettings(formats: [.webp, .webp]), "image.formats"), "webp is listed twice.")
        XCTAssertEqual(
            error(ImageSettings(formats: [.webp, .jpeg], lossless: true), "image.lossless"),
            "lossless applies to webp (png is always lossless); jpeg has no lossless form."
        )
        XCTAssertNil(error(ImageSettings(formats: [.webp, .png], lossless: true), "image.lossless"))
        XCTAssertEqual(error(ImageSettings(quality: 0), "image.quality"), "quality must be between 1 and 100.")
        XCTAssertEqual(
            error(ImageSettings(formats: [.png], quality: 80), "image.quality"),
            "quality applies to lossy formats (avif, webp, jpeg), and none is being made."
        )
        XCTAssertEqual(
            error(ImageSettings(frames: ImageFrames(atSeconds: [1], count: 2)), "image.frames"),
            "Give at_seconds or count, not both."
        )
        XCTAssertEqual(
            error(ImageSettings(frames: ImageFrames(atSeconds: [-1])), "image.frames.at_seconds"),
            "at_seconds are seconds from the start: zero or more."
        )
        XCTAssertEqual(error(ImageSettings(frames: ImageFrames(count: 101)), "image.frames.count"), "count must be between 1 and 100.")
        let many = image(
            ImageSettings(formats: [.avif, .webp, .jpeg], frames: ImageFrames(count: 100)),
            renditions: [Rendition(width: 640, height: 640)]
        )
        XCTAssertEqual(SpecTools.imageOutputCount(many), 300)
        XCTAssertEqual(
            SpecTools.validate(many)["output.image"],
            "This makes 300 files (frames × renditions × formats); at most 200 are allowed."
        )

        // `image` belongs to mode image only.
        XCTAssertEqual(
            SpecTools.validate(OutputSpec(mode: .single, image: ImageSettings()))["output.image"],
            "image applies only to mode \"image\"."
        )
        // Video renditions keep their rules.
        XCTAssertEqual(
            SpecTools.validate(OutputSpec(mode: .single, renditions: [Rendition(width: 641, height: 360)]))["output.renditions.0.width"],
            "Width and height must be even (4:2:0 chroma)."
        )
    }

    func testDiffAndDescribe() throws {
        let preset = image(ImageSettings(formats: [.jpeg], frames: ImageFrames(count: 12)), renditions: [Rendition(width: 480, height: 270)])
        var edited = preset
        edited.image = ImageSettings(formats: [.jpeg], frames: ImageFrames(atSeconds: [1.5, 10]))
        // A nested key removed is cleared, at every level.
        XCTAssertEqual(
            SpecTools.diff(edited, base: preset).json,
            ["image": ["formats": ["jpeg"], "frames": ["at_seconds": [1.5, 10], "count": nil]]]
        )
        // Leaving image mode clears the preset's image settings.
        var video = preset
        video.mode = .single
        let patch = SpecTools.diff(video, base: preset).json.objectValue ?? [:]
        XCTAssertEqual(patch["mode"], "single")
        XCTAssertEqual(patch["image"], .null)
        XCTAssertNil(SpecTools.normalize(video).image)

        XCTAssertEqual(SpecTools.describe(preset), "Images · JPEG · 480x270 · 12 frames")
        XCTAssertEqual(
            SpecTools.describe(image(ImageSettings(formats: [.avif, .jpeg], quality: 70), renditions: [Rendition(width: 640, height: 640, label: "small")])),
            "Images · AVIF / JPEG · small · quality 70"
        )
        XCTAssertEqual(Catalog.imageTier(width: 1280, height: 720), .upTo1mp)
        XCTAssertEqual(Catalog.imageTier(width: 2560, height: 1440), .upTo4mp)
        XCTAssertEqual(Catalog.imageTier(width: 3840, height: 2160), .over4mp)
    }
}
