# Morph

A native macOS app that converts a file into a closely related format — HEIC → JPG, MOV → MP4,
DOCX → PDF, WAV → MP3 — **entirely on your Mac**. The converted file lands next to the original,
so you never leave Finder.

> Right-click a file in Finder → **Convert to ▸ PNG**. A second later, `photo.png` appears beside
> `photo.heic`.

Free, open source (MIT), and inspired by [Tangerine](https://tangerineformac.com).

## Status: M0, scaffold only

**Morph does not convert anything yet.** This milestone builds the skeleton — the project, the
packages, the tests, the CI, and the local-only guard — so the conversion work has somewhere to go.

| Milestone | What it adds | State |
|---|---|---|
| M0 | Project, packages, CI, lint, network guard, docs | ✅ done |
| M1 | ConversionKit core, ImageIO engine, drop zone, Jobs list | next |
| M2 | Finder `Convert to ▸` submenu, Services, Picker panel | |
| M3 | Documents: PDF, DOCX, RTF, subtitles, CSV/JSON | |
| M4 | Audio and video through AVFoundation | |
| M5 | Bundled libraries: FFmpeg, libwebp, libavif, resvg, libarchive | |
| M6 | Settings, menu bar extra, Shortcuts, CLI, polish | |

See [SPEC.md](SPEC.md) for the full plan and [docs/decisions.md](docs/decisions.md) for decisions
made along the way.

## Everything stays on your Mac

In plain language:

- **No network code.** Morph has no networking of any kind. Not for updates, not for licences, not
  for "anonymous usage statistics". CI runs [`Scripts/network-guard.sh`](Scripts/network-guard.sh),
  which fails the build if `URLSession`, `NWConnection`, `CFNetwork`, a BSD socket call, WebKit, or
  a network entitlement ever appears in the code.
- **No accounts, no telemetry, no analytics, no crash-reporting SDK.** Crash logs stay in macOS's
  own diagnostics, where you control them.
- **No auto-updates.** To update, run `git pull && make install`.
- **Your files stay put.** Output is written beside the source. Originals are kept unless you turn
  on *Move original to Trash*, which uses the Trash and never deletes outright.
- **Writes are atomic.** Morph writes to a temporary file in the destination folder and renames it
  into place, so a cancelled or failed job cannot leave a half-written file behind.
- **The app is not sandboxed**, on purpose: that is what lets it write beside any file you pick
  without asking for folder permission every time. It runs with Hardened Runtime enabled. The
  Finder extension *is* sandboxed, as Apple requires, and does no conversion at all — it only
  builds the menu.

## Build it yourself

Morph is not notarized, signed for distribution, or published anywhere. You build it from source.
**A paid Apple Developer account is not required.**

1. Install Xcode from the Mac App Store, then open it once to accept the licence.
2. Install XcodeGen:
   ```sh
   brew install xcodegen
   ```
3. *(Optional but recommended)* Add your free Apple ID in **Xcode → Settings → Accounts**, then put
   your team id in `Local.xcconfig`:
   ```sh
   cp Local.xcconfig.example Local.xcconfig
   # edit DEVELOPMENT_TEAM
   ```
   `Local.xcconfig` is git-ignored. Without it, Morph is signed ad-hoc, which is fine for the app
   but means **the Finder extension may refuse to load** — macOS is strict about ad-hoc signed
   extensions. The Services menu, the drop zone and the menu bar entry point all still work.
4. Install:
   ```sh
   make install          # or: make install APP_DIR=~/Applications
   ```
5. Open Morph once. If **Convert to** is missing from Finder's context menu, turn it on in
   **System Settings → General → Login Items & Extensions → Finder**.

To remove it again:

```sh
make uninstall
```

### Requirements

- macOS 14 Sonoma or later
- Apple silicon (Intel builds are untested)
- Xcode 16 or later, with Swift 6

## Development

```sh
make generate        # regenerate Morph.xcodeproj from project.yml
make build           # Debug build
make test            # package tests + xcodebuild test
make test-packages   # just the Swift package tests (fast)
make lint            # network guard, swift-format, architecture checks
make format          # reformat in place
```

`Morph.xcodeproj` is **generated** and git-ignored. Edit [`project.yml`](project.yml) and run
`make generate`; never commit the project file.

### Layout

```
Apps/MorphApp/          SwiftUI app
Apps/MorphFinderSync/   Finder Sync extension (sandboxed, thin, no engines)
Apps/morph-cli/         the `morph` command
Packages/ConversionKit/ core: formats, converter protocol, registry, errors
Packages/Engines/       ImageEngine, MediaEngine, DocumentEngine, ArchiveEngine
Packages/MorphIntents/  App Intents for Shortcuts
Scripts/                network guard, lint, package tests
Tests/                  app tests, UI smoke test, fixtures
Vendor/                 build scripts for the bundled libraries
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The short version: no network code, no GPL code, prefer
Apple frameworks, and every converter needs a fixture test.

## License

Morph is [MIT licensed](LICENSE).

Bundled third-party libraries keep their own licences — FFmpeg is LGPL-2.1+ and dynamically linked,
with its build script in `Vendor/scripts/`. `THIRD_PARTY_NOTICES.md` is generated at build time
from M5 onward and shown in **About → Acknowledgements**. GPL components (x264, x265, fdk-aac) are
not used.
