import XCTest
@testable import TranscdrKit

final class ImageOutputTests: XCTestCase {
    func testImageJobDecodes() throws {
        let json = #"""
        {"object":"job","id":"job_1","status":"completed","input":{"type":"asset","asset_id":"ast_1"},
         "output":{"kind":"image","renditions":{"sizes":[{"label":"small","width":640,"height":640,"fit":"contain","orientation":"auto","upscale":false}]},
                   "image":{"formats":["avif","jpeg"],"quality":{"avif":60,"jpeg":82},"color_profile":"srgb","frames":{"count":2}},
                   "privacy":{"location":"strip","capture_time":"strip","device":"strip","descriptive":"strip"}},
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
        guard case .image(let image) = job.output else { return XCTFail("not an image spec") }
        XCTAssertEqual(image.image.formats, [.avif, .jpeg])
        XCTAssertEqual(image.image.quality, [.avif: 60, .jpeg: 82])
        XCTAssertEqual(image.image.frames, .count(2))
        XCTAssertEqual(SpecTools.imageOutputCount(image), 4)
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
        XCTAssertEqual(video.output.kind, .video)
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
}
