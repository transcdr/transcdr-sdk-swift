# Changelog

## 1.0.0

Output spec v2. This release speaks v2 only; see the README's "Migrating from
the v1 output spec" for the whole field mapping.

### Changed

- `OutputSpec` is v2: an enum with one case per kind (`.video`, `.audio`,
  `.image`), each a struct of sections (`container`, `video`, `audio`,
  `image`, `renditions`, `subtitles`, `trim`, `privacy`). Every field a kind
  always needs is non-optional, and every initializer takes every field:
  nothing has a default, and the SDK fills nothing in.
- Exclusive choices are enums with associated values: `VideoRate`
  (`.quality`, `.crf`, `.cbr`), `Renditions` (`.sizes`, `.ladder`,
  `.sourceSize`), `Subtitles`, `Gop`, `ImageFrames`, `Privacy`, `AudioTrack`
  (`.auto`, `.encode`, `.drop`), `TrimEnd` and `FrameRateMax`. `Privacy` is
  `.preset(_, refine:)`, a preset that any category may refine
  (`PrivacyRefinements`), or `.fields(_)` stating all four.
- Values that follow the source are written out: `.source`, `"standard"`,
  `.fromColor`, `.bySize`, `.poster`, `.segment`, `.all`.
- `JobCreateParams(input:spec:)` takes a `JobSpec`: `.preset(ref, overrides:)`
  (a slug, id or `slug@N`) or `.output(OutputSpec)`. A request always says what
  it produces.
- `OutputSpecInput` is replaced by `OutputOverrides`, a JSON merge patch over a
  preset version. `presets.create` takes `PresetCreateParams` (a complete
  spec); `PresetReplaceParams.output` is a complete `OutputSpec`;
  `PresetParams.output` (PATCH) is an `OutputOverrides`.
- `Automation.output` is its `OutputOverrides`.
- `SpecTools` works on v2 specs. `defaultSpec`, `resolved` and `normalize`
  are removed. `validate(_:maxShortSide:maxSizes:)` returns `[FieldError]`
  with the API's params and messages. `diff(_:base:)` returns a merge patch,
  and `merge(_:over:)` applies one with the API's rules. `defaultCbrRate` is
  `standardCbrRate`; `isQualityTarget` is `isQualityLevel`.
- `AutomationHelpers.editableSpec(override:preset:)` takes `OutputOverrides`
  and returns nil when the result is incomplete.
- `FlacCompression.default` is `.balanced`.

### Removed

- The operator console's infrastructure details: `AdminPoolStatus`,
  `AdminOverview.gpuPool`, `AdminJobInternals` and `AdminJob.internals`. They
  describe how the service runs, not the API a customer uses.

### Added

- `OutputRules`: the API's required-field table, and `spec.missingFields` /
  `OutputSpec.validate(_:)`, which report every missing or inapplicable field
  and every exclusive group without exactly one choice, all at once, as the
  API's 422 does.
- `jobs.create`, `presets.create` and `presets.replace` check a whole spec
  against the table and throw `TranscdrError.invalidOutput` without sending
  an incomplete one.
- `TranscdrError.errors`: every failure of a refused output spec
  (`[FieldError]`); `fieldErrors` includes them.
- `Job.preset`: `PresetProvenance` (`id`, `slug`, `version`, `overrides`), nil
  for a job given its whole spec; `pinned` is `slug@version`.
- `Preset.version` and `Preset.pinned`; `presets.versions(_:)`,
  `presets.version(_:_:)` and `presets.retrieve(_:version:)`.
- `Automation.resolvedOutput`: the spec its preset and overrides resolve to now.
- `Capabilities.output` (`OutputCapabilities`): the spec's fields, groups,
  containers, audio codecs, follow values and the v1 compatibility mode.

### Migrating

Every v1 field has an exact v2 form; the README lists them with v1's
defaults written out. 0.x releases keep working until the API's v1
compatibility mode ends: send `Transcdr-Output-Spec: v1` (or
`?output_spec=v1` on a `GET`) to receive `output` in the v1 shape. The mode is
deprecated from launch and removed after 31 March 2027.
