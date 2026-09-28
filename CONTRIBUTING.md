# Contributing to Morph

Morph is a personal, local-use app whose source happens to be public. Issues and pull requests are
welcome, but the rules below are not negotiable — they are what makes Morph worth trusting with
your files.

## The hard rules

1. **No network code.** No `URLSession`, `NWConnection`, `CFNetwork`, BSD sockets, WebKit, or
   network entitlements, anywhere. `Scripts/network-guard.sh` enforces this in CI. If you think you
   have a genuine exception, open an issue first.
2. **No analytics, telemetry, or crash-reporting SDKs.** Not even optional ones.
3. **No GPL code.** Morph is MIT and the repo must stay licence-clean. That rules out x264, x265
   and fdk-aac. FFmpeg is used LGPL-only, dynamically linked, with no `--enable-gpl`.
4. **No new dependencies** beyond those listed in SPEC.md §8 without asking first.
5. **Prefer Apple frameworks.** Before bundling a library for a route, check at runtime whether
   macOS can already do it — for example `CGImageDestinationCopyTypeIdentifiers()` for image
   encoders. The native path always comes first.
6. **Keep the Finder Sync extension thin.** It is sandboxed, it builds menus, and it must never
   link an engine package. `Scripts/lint.sh` checks this.

## Getting set up

```sh
brew install xcodegen
make generate
make test
```

You need Xcode 16+ (not just the Command Line Tools) and macOS 14 or later.

## Adding a converter

Every new conversion route needs four things (SPEC §14):

1. A type conforming to `Converter`, in the engine package that fits it.
2. Registration: add it to that engine's `converters` list.
3. At least one fixture under `Tests/Fixtures/`, **smaller than 200 KB**.
4. Tests that convert the fixture and assert the output exists, its `UTType` matches the target,
   its dimensions / duration / page count are what you expect, and the native reader can open it
   (ImageIO, `AVAsset`, `PDFDocument`).

Converters are `Sendable` value types with an `init()`, made on demand by the registry, so keep
them stateless. Use Swift concurrency — actors and `async`/`await` — not GCD, except where an Apple
API only offers callbacks.

## Style

- `make format` before committing; `make lint` must pass.
- swift-format with 4-space indent and a 100-column limit (`.swift-format`).
- Force unwraps and `try!` are linted against. In tests, use `try #require(…)` instead.
- Errors are `ConversionError` cases with messages that read as sentences — they are shown to the
  user verbatim in the Jobs list.
- One bad file must never stop a batch.

## Tests

| Command | Covers |
|---|---|
| `make test-packages` | converter logic and the core, via `swift test` |
| `make test-app` | app wiring and the UI smoke test, via `xcodebuild test` |
| `make test` | both |
| `make lint` | network guard, formatting, architecture rules |

Put unit tests in the package that owns the code — that is the fast loop, and it needs no app
bundle. `Tests/MorphTests/` is only for things that need the app target.

## Commits and pull requests

- One milestone or one concern per pull request. SPEC.md §12 is the running order.
- Say what you tested. "All tests pass" is only useful if you ran them.
- Record UX and architecture decisions in `docs/decisions.md`, especially when the choice was not
  obvious. When a UX call is close, choose whatever keeps the user in Finder with the fewest
  clicks.
