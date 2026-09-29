# Transcdr Swift SDK

The official Swift SDK for the [Transcdr](https://transcdr.com) video
transcoding API, for iOS, macOS and server-side Swift (Linux).

- The whole v1 API, one resource per area: jobs, assets and uploads (with
  progress), presets and their versions, webhooks and events, connections and
  automations, usage and billing, and more.
- Output spec v2: typed sections in which every required field is
  non-optional and every exclusive choice is an enum, and the API's
  required-field table built in, so an incomplete spec is caught before it is
  sent, with the API's own messages.
- `async`/`await`, typed errors carrying every field error, retries for safe
  requests, and an idempotency key on every create, so a retried create never
  makes a duplicate.
- Pagination as an `AsyncSequence`.
- The output-spec helpers the Transcdr apps use: validation with the API's
  rules, the smallest override against a preset, and a one-line description.

Version 1.0 speaks output spec v2 only. Coming from 0.x, see
[Migrating from v1](#migrating-from-the-v1-output-spec).

## Install

Swift Package Manager:

```swift
.package(url: "https://github.com/transcdr/transcdr-sdk-swift", from: "1.0.0")
```

and depend on the `TranscdrKit` product.

## Use

```swift
import TranscdrKit

let client = Transcdr(apiKey: ProcessInfo.processInfo.environment["TRANSCDR_API_KEY"])

let job = try await client.jobs.create(.init(
    input: .url("https://example.com/talk.mov"),
    spec: .preset("hls-av1-abr", overrides: nil)
))
let done = try await client.jobs.waitFor(job.id)
print(done.status, done.outputs.map(\.label))
```

Upload a local file, then transcode it:

```swift
let asset = try await client.uploads.uploadFile(fileURL) { progress in
    print(Int(progress.fraction * 100), "%")
}
_ = try await client.jobs.create(.init(input: .asset(asset.id), spec: .preset("web-av1-1080p", overrides: nil)))
```

Walk every page:

```swift
for try await job in client.jobs.all(.init(status: .failed)) {
    print(job.id, job.error?.message ?? "")
}
```

One login can belong to several organizations. A session token belongs to
one of them; switching revokes it, and the client adopts the new one:

```swift
let session = try await client.auth.login(.init(email: email, password: password))
client.apiKey = session.token
for membership in session.organizations {
    print(membership.organization.name, membership.role)
}
_ = try await client.auth.switch(to: session.organizations[1].organization.id)
```

Every create sends an `Idempotency-Key` (a random one unless you pass
`idempotencyKey:`), so it is retried safely and a retry replays the first
response. Keys last 24 hours per organization; the same key with a different
body is a 409 `idempotency_key_reused`.

Updates send `PATCH`: a field left out keeps its value, and `clear` names
fields to send as `null`, which empties them. `presets.replace` sends the
whole preset (`PUT`):

```swift
_ = try await client.automations.update(id, .init(clear: [.destination, .webhookUrl]))
_ = try await client.webhooks.update(id, .init(clear: [.description, .awsEndpoint]))
_ = try await client.presets.replace(presetId, .init(name: "Web 1080p", output: spec))
```

## The output spec

A job's `output` says what it produces, in sections. **Nothing has a
default**: a spec states every field its kind, container, codec and audio
handling need, and the SDK never fills one in. `OutputSpec` is an enum with
one case per kind:

| Kind | Sections |
|---|---|
| `.video(VideoOutput)` | `container`, `video`, `audio`, `renditions`, `subtitles`, `trim`, `privacy` |
| `.audio(AudioOutput)` | `container`, `audio`, `privacy` |
| `.image(ImageOutput)` | `image`, `renditions`, `privacy` |

Every initializer takes every field, with no default arguments. Choices of
which exactly one applies are enums, so a spec cannot hold two:
`VideoRate` (`.quality`, `.crf`, `.cbr`), `Renditions` (`.sizes`, `.ladder`,
`.sourceSize`), `Subtitles` (`.tracks`, `.languages`), `Gop` (`.frames`,
`.seconds`, `.segment`), `ImageFrames` (`.poster`, `.count`, `.atSeconds`),
`Privacy` (`.preset`, `.fields`) and `AudioTrack` (`.auto`, `.encode`, `.drop`).

"Follow the source" is a value you write: `FrameRate.source`,
`AudioChannels.source`, `"standard"` bitrates, `VideoBitDepth.fromColor`,
`RenditionLabel.bySize`, `ImageFrames.poster`, `Gop.segment`,
`SubtitleTracks.all` and `TrimEnd.source`.

An ABR HLS ladder at constant bit rate:

```swift
let hls = OutputSpec.video(VideoOutput(
    container: .hls(segmentSeconds: 6),
    video: VideoSettings(
        codec: .h264, rate: .cbr(ConstantBitRate(bitrate: "standard", bufferMs: 1000)),
        bitDepth: .eight, color: .sdr, frameRate: .source, gop: .segment, filters: []
    ),
    audio: .encode(AudioEncoding(
        codec: .aac, bitrate: "standard", channels: .source, heAac: .auto,
        stereoFallback: false, bitDepth: nil, flacCompression: nil
    )),
    renditions: .sizes([
        RenditionSize(label: .bySize, width: 1920, height: 1080, fit: .contain, orientation: .auto, upscale: false, cbrBitrate: "5M"),
        RenditionSize(label: .bySize, width: 1280, height: 720, fit: .contain, orientation: .auto, upscale: false, cbrBitrate: "3M"),
    ]),
    subtitles: .tracks(.all),
    trim: .whole,
    privacy: .preset(.stripAll)
))
let job = try await client.jobs.create(.init(input: .asset(asset.id), spec: .output(hls)))
// An automatic ladder instead:
// renditions: .ladder(Ladder(maxShortSide: 1080, fit: .contain, upscale: false))
```

A single vertical MP4, capped at 30 fps:

```swift
let vertical = OutputSpec.video(VideoOutput(
    container: .mp4,
    video: VideoSettings(
        codec: .h264, rate: .quality("high"), bitDepth: .fromColor, color: .sdr,
        frameRate: .max(30), gop: .seconds(2), filters: []
    ),
    audio: .encode(AudioEncoding(
        codec: .aac, bitrate: "standard", channels: .source, heAac: .auto,
        stereoFallback: nil, bitDepth: nil, flacCompression: nil
    )),
    renditions: .sizes([
        RenditionSize(label: .bySize, width: 1080, height: 1920, fit: .cover, orientation: .fixed, upscale: false, cbrBitrate: nil),
    ]),
    subtitles: .tracks(.all),
    trim: .whole,
    privacy: .preset(.stripAll)
))
```

An audio-only MP3:

```swift
let podcast = OutputSpec.audio(AudioOutput(
    container: .mp3,
    audio: .encode(AudioEncoding(
        codec: .mp3, bitrate: "64k", channels: .mono, heAac: .auto,
        stereoFallback: nil, bitDepth: nil, flacCompression: nil
    )),
    privacy: .preset(.stripAll)
))
```

Twelve JPEG stills of a video:

```swift
let stills = OutputSpec.image(ImageOutput(
    image: ImageSettings(formats: [.jpeg], lossless: nil, quality: [.jpeg: 80], colorProfile: .srgb, frames: .count(12)),
    renditions: .sizes([
        RenditionSize(label: "sheet", width: 320, height: 320, fit: .contain, orientation: .auto, upscale: false, cbrBitrate: nil),
    ]),
    privacy: .preset(.stripAll)
))
```

### Fields that depend on others

Some fields apply only under a condition, and are optional in the types:

| Field | Required when |
|---|---|
| `Container.segmentSeconds` | format `hls` (1–20) |
| `AudioEncoding.bitrate` | codec `opus`, `mp3` or `aac` |
| `AudioEncoding.stereoFallback` | container `hls` |
| `AudioEncoding.bitDepth` | codec `flac` or `alac` |
| `AudioEncoding.flacCompression` | codec `flac` |
| `ImageSettings.lossless` | `webp` among the formats |
| `ImageSettings.quality` | a lossy format is made: one entry per lossy format |
| `RenditionSize.cbrBitrate` | optional, with `.cbr` only |

A field is refused where it does not apply. `OutputRules` holds the API's
required-field table (the same one `GET /v1/capabilities` lists under
`output`), and `spec.missingFields` checks a spec against it, reporting
every problem at once with the API's params and messages.
`jobs.create`, `presets.create` and `presets.replace` run that check on a
whole spec and throw `TranscdrError` (code `validation_failed`, every
problem in `errors`) without sending the request.
`SpecTools.validate(_:maxShortSide:maxSizes:)` goes on to check the values
against each other and the plan's limits (HDR needs 10-bit, an `.mp3` holds
MP3 only, even sizes), as the API does.

```swift
for problem in hls.missingFields { print(problem.param, problem.message) }
```

### Presets, versions and overrides

A preset is a complete spec, and presets are versioned: editing one's output
adds a version, and a version never changes. Name one by slug or id for its
latest version, or `slug@N` for version N. With a preset, `overrides` give
only what to change: objects merge key by key, scalars and arrays replace,
one choice of an exclusive group replaces the others, `null` removes a field,
and `kind` cannot change. The result must be complete.

```swift
let job = try await client.jobs.create(.init(
    input: .asset(asset.id),
    spec: .preset("social-vertical-1080x1920@1", overrides: ["video": ["frame_rate": ["max": 24]]])
))
print(job.preset?.slug, job.preset?.version, job.preset?.overrides)  // where the spec came from
print(job.output)  // the resolved, complete spec: what runs

let versions = try await client.presets.versions("my-preset")
let v2 = try await client.presets.version("my-preset", 2)
```

`SpecTools.diff(spec, base: preset.output)` is the smallest override that
turns a preset's spec into `spec`, and `SpecTools.merge(overrides, over:)`
applies one with the API's rules. An automation stores a preset reference and
overrides; `automation.resolvedOutput` is the spec they resolve to now.

### Audio

`AudioTrack` is `.auto` (keep the source's audio where the container carries
it, make the rest `codec`, which is Opus, or MP3 in an `.mp3`), `.encode`
(make `codec`; a source already in it is copied) or `.drop` (video only).

- `aac` is AAC-LC, the audio that plays on the most devices. `bitrate` is 8k
  to 288k per main channel (the LFE does not count), or `"standard"`: 64k
  mono, 128k stereo, 384k 5.1, 512k 7.1.
- `mp3` is constant bit rate, stereo at most, for an MP4 or an `.mp3`, not
  HLS, at one of `SpecTools.mp3Bitrates`.
- `flac` and `alac` are lossless and take no bitrate; `bitDepth` is
  `.source`, `.sixteen` or `.twentyFour`; `flacCompression` is `.fast`,
  `.balanced` or `.best`, the same audio either way.
- `channels` sets the layout, or `.source` to keep the source's; it never
  upmixes. `stereoFallback` (HLS) adds a stereo rendition beside surround
  audio.
- `heAac` says what an HE-AAC source becomes. HE-AAC is decoded only as its
  AAC-LC core: `.auto` keeps it where only a codec change is asked and decodes
  its core where the job needs PCM; `.passthrough` never decodes it; `.core`
  decodes its core whenever another codec is asked.

`.audio` output writes one file labelled `audio`: `container` `.mp3` (MP3
only), `.flac` (FLAC only) or `.m4a` (any codec).

### Sizes

A size's `width` × `height` is the largest the output may be, not its exact
size. `fit` is `.contain` (inside the box), `.cover` (fill and centre-crop),
`.pad` (black bars to exactly the box) or `.stretch`. `orientation: .auto`
turns the box to the picture's orientation; `.fixed` uses it as written.
Nothing is enlarged past the source unless `upscale` is true. Each output
reports the size it came out at.

### Image jobs

`.image` output makes still images of an image input (JPEG, PNG, WebP, AVIF,
GIF, TIFF, BMP, HEIC) or of a video. Every size is made in every format:
`.avif`, `.webp`, `.jpeg`, `.png`. `quality` names each lossy format made;
`lossless` is WebP's (PNG always is). `colorProfile` is `.srgb` or `.keep`.
`frames` is `.poster` (an image as it is, a video's frame 10% in), `.count(N)`
or `.atSeconds([...])`. Images are billed per output image by pixel count
(`billing.billableImages`, `billing.tier`).

### Privacy

`privacy` is a preset (`.preset(.stripAll)`, `.preset(.stripLocation)` or
`.preset(.keepAll)`), which any of the four categories may refine, or
`.fields(PrivacyFields(location:captureTime:device:descriptive:))` stating
every category. Responses state every category, without a preset.

```swift
let dated = Privacy.preset(.stripAll, refine: PrivacyRefinements(location: nil, captureTime: .date, device: nil, descriptive: nil))
```

### Errors

Errors are `TranscdrError`, with `kind`, `status`, `code`, `param` and
`message`. A refused output spec lists every problem in `errors`
(`[FieldError]`, each a `param` and a `message`), missing fields first;
`fieldErrors` gives them by param.

## Migrating from the v1 output spec

1.0 replaces the flat v1 `OutputSpec` (`mode`, `codec`, `quality`,
`renditions` as a list, `audio.mode`, top-level `fit` and `upscale`, …) with
the sections above, and the API returns v2 in every response. In code:

- `JobCreateParams(input:output:preset:)` is now `JobCreateParams(input:spec:)`
  with `.preset(ref, overrides:)` or `.output(spec)`.
- `OutputSpecInput` is `OutputOverrides` (a JSON merge patch) for overrides;
  a whole spec is an `OutputSpec`. `presets.create` takes
  `PresetCreateParams`, whose `output` is a complete `OutputSpec`.
- `SpecTools.defaultSpec`, `resolved` and `normalize` are gone: there are no
  defaults to fill in. `SpecTools.validate` returns `[FieldError]`.
- `AudioSettings`, `Quality`, `Rendition`, `OutputMode`, `AudioMode`,
  `AudioContainer` and `BitDepth` are replaced by the section types.

Every v1 field has an exact v2 form. Where v1 had a default, write it out:

| v1 | v2 | v1 default, written out |
|---|---|---|
| `mode: single` | `kind: video`, `container.format: mp4` | `single` |
| `mode: hls` | `kind: video`, `container.format: hls` | |
| `segment_seconds` | `container.segment_seconds` | `4` |
| `mode: audio` | `kind: audio` | |
| `audio.container` | `container.format` (`mp4` read as `m4a`) | `auto` → `flac` for flac, `m4a` for alac, else `mp3` |
| `mode: image` | `kind: image` | |
| `codec` | `video.codec` | `av1` |
| `quality.target` (a level) | `video.quality` | none set → `quality: "standard"` |
| `quality.crf` | `video.crf` (a level `target` is dropped: crf won) | |
| `quality.target: cbr` | `video.cbr` | |
| `quality.bitrate` | `video.cbr.bitrate` | `"standard"` |
| `quality.buffer_ms` | `video.cbr.buffer_ms` | `1000` |
| `bit_depth` | `video.bit_depth` (`auto` → `from_color`) | `from_color` |
| `color` | `video.color` | `sdr` |
| `max_fps` | `video.frame_rate.max` | `"source"` |
| `gop` | `video.gop.frames` | mp4: `{ seconds: 2 }`; hls: `"segment"` |
| `filters: "a,b"` | `video.filters: ["a", "b"]` | `[]` |
| `renditions[]` | `renditions.sizes[]` | none and no ladder → `source_size`, with the top-level `fit` and `upscale` |
| `renditions[].label` | `sizes[].label` | `by_size` |
| `renditions[].fit` / `upscale` | `sizes[].fit` / `upscale` | the top-level `fit` / `upscale`, which default to `contain` / `false` |
| `renditions[].orientation` | `sizes[].orientation` | `auto` |
| `renditions[].bitrate` | `sizes[].video.cbr.bitrate` | |
| `fit`, `upscale` (top level) | written onto every size, the ladder or the source size; dropped for audio | `contain`, `false` |
| `ladder` | `renditions.ladder` (dropped when `renditions` is non-empty, as v1 ignored it) | `max_short_side` → `1080` |
| `audio.mode: auto` | `handling: auto`, `codec: opus` (`mp3` in an mp3 container) | |
| `audio.mode: opus` \| `mp3` \| `aac` \| `flac` \| `alac` | `handling: encode`, `codec` | |
| `audio.mode: drop` | `handling: drop` | |
| `audio.bitrate` | `audio.bitrate` | `"standard"` (lossy) |
| `audio.channels` | `audio.channels` | `source` |
| `audio.he_aac` | `audio.he_aac` | `auto` |
| `audio.stereo_fallback` | `audio.stereo_fallback` | `false` (hls) |
| `audio.bit_depth` | `audio.bit_depth` | `source` (flac/alac) |
| `audio.flac_compression` | `audio.flac_compression` (`default` → `balanced`) | `balanced` (flac) |
| `subtitles: all\|none` | `subtitles.tracks` | `all` |
| `subtitles: "eng,deu"` | `subtitles.languages` | |
| `trim` | `trim` | `{ start: 0, end: "source" }`; `end` unset → `"source"` |
| `image.formats` | `image.formats` | `["avif"]` |
| `image.quality: 70` | `image.quality: { <each lossy format>: 70 }` | avif 60, webp 80, jpeg 82 |
| `image.lossless` | `image.lossless` | `false` (webp) |
| `image.keep_color_profile` | `image.color_profile: keep \| srgb` | `srgb` |
| `image.frames` | `image.frames` | `"poster"` |
| `privacy` | `privacy`, all four fields resolved | `{ preset: "strip_all" }` |

**Older SDK versions keep working** until the compatibility mode's sunset. The
API still accepts v1 requests, with v1's defaults. Responses are v2, which a
0.x `OutputSpec` reads as an empty spec; the API's compatibility mode returns
`output` in the v1 shape instead, when a request carries the
`Transcdr-Output-Spec: v1` header (or `?output_spec=v1` on a `GET`). With 0.x,
send that header through your `HTTPTransport`. The mode is deprecated from the
start (its responses carry `Deprecation` and `Sunset` headers) and is removed
after 31 March 2027: move to 1.0 before then.

## Requirements

Swift 5.10+, iOS 17 / macOS 14, or Linux.

## Other languages

- TypeScript: [transcdr-sdk-typescript](https://github.com/transcdr/transcdr-sdk-typescript)
- Python: [transcdr-sdk-python](https://github.com/transcdr/transcdr-sdk-python)
- Go: [transcdr-sdk-go](https://github.com/transcdr/transcdr-sdk-go)

## License

MIT
