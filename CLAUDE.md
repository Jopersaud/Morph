# CLAUDE.md

Working notes for Claude Code. Read [SPEC.md](SPEC.md) for the full spec; this file is the
operational summary.

Morph is a native macOS app that converts files into adjacent formats entirely on-device, writing
the output beside the source. Swift 6, SwiftUI, macOS 14+, MIT.

## Commands

```sh
make generate        # regenerate Morph.xcodeproj from project.yml (after adding files)
make build           # Debug build
make test            # package tests + xcodebuild test  ← the gate for every milestone
make test-packages   # swift test in each local package (fast inner loop)
make test-app        # xcodebuild test: app wiring + UI smoke test
make lint            # network guard, swift-format --strict, architecture checks
make format          # swift-format in place
make install         # Release build → /Applications, registers the Finder extension
```

Needs **Xcode** (not just the Command Line Tools) and `brew install xcodegen`. If `xcodebuild`
reports "requires Xcode", run `sudo xcode-select -s /Applications/Xcode.app`.

`Morph.xcodeproj` is generated and git-ignored: edit `project.yml`, then `make generate`. Never
commit the project file, and never hand-edit it.

## Layout

```
project.yml              XcodeGen definition — the source of truth for targets
Config/Shared.xcconfig   shared build settings; #include? "../Local.xcconfig"
Apps/MorphApp/           SwiftUI app (not sandboxed, Hardened Runtime)
Apps/MorphFinderSync/    Finder Sync extension (sandboxed, thin, ConversionKit only)
Apps/morph-cli/          `morph` CLI
Packages/ConversionKit/  FileFormat, FormatCatalog, Converter, ConverterRegistry, errors
Packages/Engines/        ImageEngine, MediaEngine, DocumentEngine, ArchiveEngine
Packages/MorphIntents/   App Intents
Scripts/                 network-guard.sh, lint.sh, test-packages.sh
Tests/MorphTests/        app-level tests (need the app target)
Tests/MorphUITests/      XCUITest launch smoke test
Tests/Fixtures/          sample files, < 200 KB each
Vendor/scripts/          build scripts for bundled libraries (M5)
docs/decisions.md        decision log
```

Unit tests belong in the package that owns the code — they run under `swift test` without an app
bundle. `Tests/MorphTests/` is only for things that genuinely need the app target, because
`xcodebuild test` does not run local package test targets.

## Milestones

Work **one milestone at a time**. At the start, restate its scope and acceptance criteria; at the
end, run the full suite and report what passed. Commit at every milestone.

| | Scope | Done when |
|---|---|---|
| M0 ✅ | Scaffold: project, packages, CI, lint, network guard, docs | `xcodegen && xcodebuild test` passes |
| M1 ✅ | ConversionKit core, ImageIO engine, OutputPlanner, JobQueue, drop zone, Jobs list | 50 HEICs in → 50 JPGs beside them |
| M2 ✅ | Finder Sync + `morph://` handoff, Services, Picker panel, notifications, onboarding | right-click → Convert to ▸ PNG works |
| M3 | NSAttributedString + PDFKit routes, subtitles, CSV/JSON | every document route has a fixture test |
| M4 | AVFoundation audio/video routes and presets | MOV→MP4, WAV→M4A, video→M4A |
| M5 | FFmpeg (LGPL), libwebp, libavif, resvg, libarchive; GIF; archives | the full §5 matrix is green |
| M6 | Settings, menu bar extra, App Intents, CLI, accessibility, performance | `make install` on a clean clone gives a working app |

The core pipeline is `JobQueue` → `FormatDetector` → `ConverterRegistry` → `OutputPlanner`:
converters write to `job.destination`, a hidden temp file, and the queue commits it into place.
Image fixtures are regenerated with `swift Tests/Fixtures/make-images.swift`.

Entry points all end in `AppDelegate`: `morph://` handoffs (`Handoff`, built by the Finder
extension), Services, and the main window. The extension reads its menu from the `RouteTable` the
app publishes into its container. UI tests can't open `morph://` URLs (XCUITest starts a second app
copy), so Debug builds take one in `MORPH_UI_TEST_HANDOFF`.

## Hard rules

- **No network code.** No `URLSession`, `NWConnection`, `CFNetwork`, sockets, WebKit, or network
  entitlements. `Scripts/network-guard.sh` fails the build on any of them. Don't add one; ask
  first. A genuine false positive gets `// network-guard:allow <reason>` and shows up in the
  report.
- **No analytics, telemetry or crash-reporting SDKs.**
- **No GPL code** (x264, x265, fdk-aac). FFmpeg stays LGPL-only, dynamically linked.
- **No dependency** that isn't in SPEC §8 without asking.
- **Prefer Apple frameworks.** Probe at runtime (e.g. `CGImageDestinationCopyTypeIdentifiers()`)
  before reaching for a bundled library, and keep the native path first. `ConverterPriority`
  encodes this: `.native` beats `.bundled`.
- **Keep the Finder extension thin.** Sandboxed, ConversionKit only, no engine packages ever.
  `Scripts/lint.sh` checks both the imports and the target's dependencies.
- **Swift concurrency**, not GCD, except where an Apple API requires callbacks.
- **Every new converter needs**: a `Converter` type, registration in its engine's `converters`,
  a fixture under 200 KB, and tests.
- When a UX call is close, pick whatever keeps the user in Finder with the fewest clicks, and write
  the decision down in `docs/decisions.md`.

## Conventions

- swift-format, 4-space indent, 100 columns (`.swift-format`). `make format` before committing.
- Force unwrap and `try!` are lint errors. In tests use `try #require(…)`.
- Swift Testing (`@Test`, `#expect`) for unit tests; XCTest only for the UI smoke test.
- `ConversionError` messages are user-facing sentences.
- One bad file never stops a batch.
- Output goes beside the source; collisions become `name (1).ext`; writes are atomic via a temp
  file in the destination folder.
