# Transcdr Swift SDK

The official Swift SDK for the [Transcdr](https://transcdr.com) video
transcoding API, for iOS, macOS and server-side Swift (Linux).

- The whole v1 API, one resource per area: jobs, assets and uploads (with
  progress), presets, webhooks and events, connections and automations,
  usage and billing, and more.
- `async`/`await`, typed errors carrying the API's field errors, retries for
  safe requests, and idempotency keys on job and upload creation.
- Pagination as an `AsyncSequence`.
- The output-spec helpers the Transcdr apps use: validation with the
  server's rules, the smallest override against a preset, and a one-line
  description.

## Install

Swift Package Manager:

```swift
.package(url: "https://github.com/transcdr/transcdr-sdk-swift", from: "0.2.0")
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

Errors are `TranscdrError`, with `kind`, `status`, `code`, `param` and
`fieldErrors` for validation failures.

## Requirements

Swift 5.10+, iOS 17 / macOS 14, or Linux.

## Other languages

- TypeScript: [transcdr-sdk-typescript](https://github.com/transcdr/transcdr-sdk-typescript)
- Go: [transcdr-sdk-go](https://github.com/transcdr/transcdr-sdk-go)

## License

MIT
