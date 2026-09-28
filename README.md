# Transcdr Swift SDK

The official Swift SDK for the [Transcdr](https://transcdr.com) video
transcoding API, for iOS, macOS and server-side Swift (Linux).

- The whole v1 API, one resource per area: jobs, assets and uploads (with
  progress), presets, webhooks and events, connections and automations,
  usage and billing, and more.
- `async`/`await`, typed errors carrying the API's field errors, retries for
  safe requests, and an idempotency key on every create, so a retried create
  never makes a duplicate.
- Pagination as an `AsyncSequence`.
- The output-spec helpers the Transcdr apps use: validation with the
  server's rules, the smallest override against a preset, and a one-line
  description.

## Install

Swift Package Manager:

```swift
.package(url: "https://github.com/transcdr/transcdr-sdk-swift", from: "0.5.0")
```

and depend on the `TranscdrKit` product.

## Use

```swift
import TranscdrKit

let client = Transcdr(apiKey: ProcessInfo.processInfo.environment["TRANSCDR_API_KEY"])

let job = try await client.jobs.create(.init(
    input: .url("https://example.com/talk.mov"),
    preset: "hls-av1-abr"
))
let done = try await client.jobs.waitFor(job.id)
print(done.status, done.outputs.map(\.label))
```

Upload a local file, then transcode it:

```swift
let asset = try await client.uploads.uploadFile(fileURL) { progress in
    print(Int(progress.fraction * 100), "%")
}
_ = try await client.jobs.create(.init(input: .asset(asset.id), preset: "web-av1-1080p"))
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
_ = try await client.presets.replace(presetId, .init(name: "Web 1080p", output: OutputSpecInput(spec)))
```

Every preset has a `category` (`.web`, `.mobile`, `.streaming`, `.tv`,
`.social`, `.audio`, `.archive`) and a `compatibility` list of the platforms
its output plays on (`.web`, `.ios`, `.android`, `.smartTV`, `.legacy`,
`.editing`). Each platform has a note giving minimum versions and conditions,
such as audio that has to be AAC in the source. Both are derived from the
output spec. Your own presets can set them, and clearing them derives them
again. Both types accept values this SDK doesn't know yet.

```swift
let phones = try await client.presets.list(category: [.mobile], compatibleWith: [.ios, .android])
for preset in phones.data {
    print(preset.name, preset.compatibility, preset.note(for: .ios) ?? "")
}
_ = try await client.presets.update(id, .init(category: .tv, compatibilityNotes: ["smart_tv": "Tested on our set-top box."]))
_ = try await client.presets.update(id, .init(clear: [.category, .compatibility, .compatibilityNotes]))
```

A rendition's `width` × `height` is the largest it may be, not its exact size.
The video keeps its shape inside the box, a portrait video turns a landscape
box portrait, and nothing is enlarged past the source: a 640×480 video through
a 1920×1080 rendition comes out 640×480 (and bills as SD). Each output reports
the size it came out at. `fit` is `.contain` (the default), `.cover` (fill and
centre-crop), `.pad` (black bars to exactly the box) or `.stretch`;
`upscale: true` allows enlarging. A rendition may set its own `fit`, `upscale`
and `orientation` (`.fixed` keeps its box as written).

```swift
let vertical = OutputSpec(
    renditions: [
        Rendition(width: 1920, height: 1080),
        Rendition(width: 1080, height: 1920, fit: .cover, orientation: .fixed),
    ],
    fit: .contain
)
```

`AudioMode` is `.auto` (the default: compatible audio passes through, the
rest becomes Opus), `.opus`, `.aac`, `.mp3`, `.flac`, `.alac` or `.drop`.

- `.aac` is AAC-LC, the audio that plays on the most devices: every browser,
  iPhone, Android phone and TV. An AAC source passes through. It works in a
  single MP4, HLS and audio-only `.m4a` output. `bitrate` is 8k to 288k per
  main channel (the LFE of 5.1 and 7.1 does not count); the default is 64k
  mono, 128k stereo, 384k 5.1 and 512k 7.1.
- `.flac` and `.alac` are lossless: a source already in that codec is copied,
  and they take no `bitrate`. Both work in a single MP4, HLS and audio-only
  output. `bitDepth` is `.source` (the default: 16-bit for a 16-bit or lossy
  source, 24-bit for a deeper one), `.sixteen` or `.twentyFour`. For FLAC,
  `flacCompression` is `.fast`, `.default` or `.best`: the same audio either
  way, a smaller file for more work.
- `.mp3` is constant bit rate, stereo at most, in a single MP4 or audio-only
  output (not HLS), at one of `SpecTools.mp3Bitrates` (default 128k stereo,
  64k mono).

`mode: .audio` writes the audio alone as one file (label `audio`, width and
height 0), billed per output minute at the SD rate. `container` picks the
file: `.auto` (the default) follows the codec, a `.flac` for FLAC, an `.m4a`
for ALAC and an `.mp3` otherwise (`.auto` audio is then MP3); `.m4a` holds any
codec (`.auto` audio in an `.m4a` is Opus); `.flac` holds FLAC only and `.mp3`
MP3 only. The file is `audio.mp3` (`audio/mpeg`), `audio.flac` (`audio/flac`)
or `audio.m4a` (`audio/mp4`); `SpecTools.audioContainer` and
`SpecTools.audioCodec` say which file and codec a spec makes. `container`
applies only to `mode: .audio`. A `single` job whose input has no video
becomes audio-only by itself; with AAC or Opus audio it is an `.m4a`.

`channels` is `.source` (the default), `.mono`, `.stereo`, `.surround51` or
`.surround71`, downmixing and never upmixing. In HLS with surround audio,
`stereoFallback: true` adds a stereo rendition to the same audio group.
`SpecTools.validate` checks all of these with the server's messages.

```swift
let podcast = OutputSpec(mode: .audio, audio: AudioSettings(mode: .mp3, bitrate: "128k", channels: .stereo))
_ = try await client.jobs.create(.init(input: .asset(asset.id), output: OutputSpecInput(podcast)))
let m4a = OutputSpec(mode: .audio, audio: AudioSettings(mode: .aac, container: .m4a))
let master = OutputSpec(mode: .audio, audio: AudioSettings(mode: .flac, bitDepth: .twentyFour, flacCompression: .best))
let surround = OutputSpec(mode: .hls, codec: .h264, audio: AudioSettings(mode: .aac, channels: .surround51, stereoFallback: true))
```

Audio system presets (category `.audio`): `audio-mp3-podcast` and
`audio-mp3-speech` (MP3 at 128k stereo and 64k mono), `audio-aac-m4a` (AAC in
an `.m4a`) and `audio-alac-m4a` (Apple Lossless in an `.m4a`). In category
`.archive`, `audio-flac` is a native `.flac` at best compression and
`archive-av1-flac` is visually lossless AV1 with FLAC audio in one MP4. The
reach presets (`mp4-h264-compat-1080p`, `mp4-h265-1080p`, `hls-h264-abr`,
`hls-h264-cbr`, `social-vertical-1080x1920`, `hls-h264-surround` and
`mp4-h264-surround-1080p`, now in category `.tv`) use AAC audio.

Connections and webhooks never return their secrets: `secrets` lists the ones
that are set, each with a `fingerprint` that changes when the secret does.
`auth.me()` returns a `user` for API keys too (the key's creator); `me.isSession`
tells a session from an API key.

Errors are `TranscdrError`, with `kind`, `status`, `code`, `param` and
`fieldErrors` for validation failures.

## Requirements

Swift 5.10+, iOS 17 / macOS 14, or Linux.

## Other languages

- TypeScript: [transcdr-sdk-typescript](https://github.com/transcdr/transcdr-sdk-typescript)
- Python: [transcdr-sdk-python](https://github.com/transcdr/transcdr-sdk-python)
- Go: [transcdr-sdk-go](https://github.com/transcdr/transcdr-sdk-go)

## License

MIT
