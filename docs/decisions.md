# Decisions

Choices worth remembering, newest last. SPEC.md §14 asks for UX decisions here; architecture calls
that deviate from the spec are recorded too, so the deviation is deliberate and reviewable.

## M0 — Scaffold (2026-09-28)

### One package per module, not one umbrella package

SPEC §6 lays out `ConversionKit`, four engines and `MorphIntents` as separate directories. They are
six separate Swift packages, each with its own manifest and tests, rather than one package with six
targets.

*Why:* it makes "the Finder extension links ConversionKit and nothing else" a fact the build
enforces, rather than a convention. *Cost:* `swift test` has to run six times, so
`Scripts/test-packages.sh` loops over them.

### `Converter` requires `init()`

The spec sketches `Converter` with static `id`, `routes` and `isAvailable()`, plus an instance
`convert`. A registry holding heterogeneous converter types cannot create one from a metatype
unless the protocol guarantees an initializer, so `init()` was added to the protocol.

Converters are stateless `Sendable` value types, so this costs nothing and keeps the registry free
of registration closures.

### `ConverterPriority` makes "native first" mechanical

SPEC §6 says priority order is native engine, then bundled library. Rather than leaving that to
registration order, converters declare `static var priority: ConverterPriority` (`.native` by
default). The registry sorts by priority first and registration order second, and
`ConverterRegistryTests` pins the behaviour in both registration orders.

### Formats macOS doesn't know still get a `UTType`

`FileFormat.utType` is non-optional, but macOS has no declared type for MKV, Opus, SRT or VTT on
every supported version. `FileFormat.resolveType` tries the declared identifier, then the
extension, then falls back to a dynamic (`dyn.…`) type. That keeps the catalog honest without
making every call site deal with an optional.

Two formats may share an extension — ALAC and AAC both live in `.m4a` — so catalog ids are unique
but extensions are not. `TAR.GZ` has the double extension `tar.gz`, which `OutputPlanner` will need
to treat as one unit in M1.

### Errors carry their subject

`ConversionError` keeps the spec's cases but attaches the route, URL or format the failure is
about, so the Jobs list can show "Couldn't read photo.heic: not downloaded" without the UI having
to remember which job failed.

### Ad-hoc signing in CI, not disabled signing

SPEC §11 says to build in CI "with code signing disabled". On Apple silicon an unsigned bundle will
not execute, so `CODE_SIGNING_ALLOWED=NO` would break the UI smoke test. CI instead uses the
repo's default ad-hoc identity (`CODE_SIGN_IDENTITY = -` in `Config/Shared.xcconfig`), which needs
no account, no keychain and no secrets. The intent of the spec — no signing identity, no release
steps — is kept.

### Package tests run under `swift test`, app tests under `xcodebuild`

`xcodebuild test` on the `Morph` scheme cannot run the test targets of local Swift packages, so the
M0 gate is both commands. `make test` runs them in order, and CI has a step for each. App-level
tests are limited to things that genuinely need the app target, currently engine registration.

### The network guard is wider than §7, and can be silenced per line

SPEC §7 names `URLSession`, `NWConnection`, `CFNetwork` and socket APIs. The guard also rejects
WebKit (`WKWebView` loads remote resources), network entitlements and Info.plist networking keys,
and a list of analytics and crash-reporting SDKs, since §7 rules those out too.

It refuses to pass when it scans zero files, so a misconfiguration cannot look like a clean run.
A line may be excused with `// network-guard:allow <reason>`; allowances are printed in the report
so they surface in review instead of accumulating quietly. There are none today.

WebKit being on the list is a bet: SPEC §5 renders HTML through `NSAttributedString`, so M3 should
not need it. If a document route later wants WebKit for local HTML, that needs a conscious decision
rather than a silent import.

### The CLI has no dependencies yet

SPEC §8 approves swift-argument-parser and §3 puts the CLI at P2, with the real work in M6. M0's
`morph` handles `--version`, `--help` and `formats` with a `switch`, which keeps the whole M0 build
free of remote dependencies — no network access needed to build, and nothing to resolve or pin.
M6 adds swift-argument-parser along with `morph convert`.

### Info.plist files are committed, not generated

XcodeGen can synthesise Info.plists from `project.yml`. Explicit files are committed instead, so
the `NSExtension` wiring for the Finder extension and the app's bundle keys are readable in a diff
rather than implied by YAML.

## M1 — Images and the main window (2026-11-04)

### Collisions are settled at commit time, with an exclusive rename

`OutputPlanner` doesn't pick a free name up front. The converter writes a hidden temp file
(`.photo.jpg.<token>.morph-tmp`) in the destination folder, and `commit` renames it with
`renamex_np(…, RENAME_EXCL)`, trying `photo.jpg`, then `photo (1).jpg`, and so on. Checking and
claiming a name is one atomic step, so `photo.png` and `photo.tiff` converted in the same batch get
`photo.jpg` and `photo (1).jpg` rather than racing for one name. SPEC §4 names the temp file
`.name.morph-tmp`; the random token is added so concurrent jobs never share one.

### ImageIO routes come from a runtime probe

`ImageIOConverter.routes` is computed from `CGImageSourceCopyTypeIdentifiers()` and
`CGImageDestinationCopyTypeIdentifiers()` rather than written out, so a Mac without a HEIC encoder
never offers HEIC (SPEC §14). The cost is that "advertised" and "available" routes are the same set
for this converter. M1 covers JPEG, PNG, HEIC, TIFF and BMP in every direction, 20 routes; GIF,
WebP and AVIF sources come in M5 with the bundled encoders.

### Re-encode untouched when possible, decode only when needed

A plain conversion uses `CGImageDestinationAddImageFromSource`, which carries every piece of
metadata, the orientation flag included. Morph decodes to pixels only when it has to: resizing,
stripping metadata, flattening transparency into JPEG, or writing BMP, which has no orientation
field and so gets its pixels rotated upright. Stripping removes GPS, maker notes, camera and lens,
and keeps the capture date.

### `ConversionError.unknownFormat`, and `JobEvent.queued`

Two small additions to the M0 types. A readable file in no known format isn't `unreadable`, and its
message shouldn't suggest waiting for a download. And the Jobs list needs to learn about a job
before it starts, so the queue announces each request as it's queued.

### The drop zone ignores files it can't convert instead of disabling everything

SPEC §9 disables chips that don't suit every dropped file. A stray `.DS_Store` or `notes.txt`
would then disable every chip, so files of no known format are left out of the chip calculation and
named in a "Skipping…" note instead. Recognised files still disable chips that don't suit them,
with the reason in the tooltip. Dropping a folder adds the files directly inside it.

### Converting clears the drop zone

After a chip is clicked, the batch moves to the Jobs list and the drop zone empties, ready for the
next drop. Converting the same files to a second format takes another drop, but the common case,
one batch to one format, needs no *Clear* click.

### The read-only prompt is asked once per batch

When some dropped files sit in folders Morph can't write to, the writable ones start at once and a
single dialog offers *Save to…* (one folder for all the blocked files) or *Skip*. The default
"Save to…" behaviour in Settings (SPEC §9) arrives in M6.

### Not in M1

- The per-chip options popover (the gear in SPEC §9) arrives with Settings in M6; M1 uses the
  defaults in `ImageOptions`.
- Copying file dates and *Move original to Trash* are Settings options too (M6).
- Removing temp files left by a crash at launch (SPEC §7): `OutputPlanner.removeStaleTemporaries`
  exists, but the app doesn't yet record which folders to sweep.
