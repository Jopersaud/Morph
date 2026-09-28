# Vendor

Build scripts for the third-party libraries Morph bundles. **No source dumps and no committed
binaries** (SPEC §6): the scripts fetch pinned sources, build `xcframework`s into `Vendor/build/`,
and CI caches the result.

Everything here arrives in **M5**. Planned scripts:

| Script | Builds | Licence | Linking |
|---|---|---|---|
| `build-ffmpeg.sh` | libavcodec, libavformat, libavfilter, libavutil, swscale, swresample | LGPL-2.1+ | dynamic |
| `build-codecs.sh` | libvpx, libopus, libvorbis, libogg, libmp3lame | BSD / LGPL | dynamic |
| `build-libwebp.sh` | libwebp | BSD-3 | static |
| `build-libavif.sh` | libavif + libaom or SVT-AV1 | BSD-2 | static |
| `build-resvg.sh` | resvg (Rust → C ABI) | Apache-2.0 / MIT | static |
| `build-libarchive.sh` | libarchive | BSD-2 | static |

## Rules

- **FFmpeg is LGPL-only**: no `--enable-gpl`, no x264, no x265, no fdk-aac. Hardware H.264/HEVC
  comes from VideoToolbox; VP9 from libvpx.
- FFmpeg ships as a **dynamic** `xcframework`, and the build script plus a link to the exact source
  release stay in the repo, which is what LGPL compliance requires here.
- Call libraries through their C APIs from a thin Swift wrapper. **Never shell out to an `ffmpeg`
  binary** (SPEC §6).
- Builds must be reproducible: pin versions and checksums in the script, not "latest".
- Before adding a library, check whether macOS can already do the job (SPEC §14).
- `THIRD_PARTY_NOTICES.md` is generated from these libraries' licences at build time and shown in
  **About → Acknowledgements**.
