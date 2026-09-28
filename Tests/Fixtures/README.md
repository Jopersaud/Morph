# Fixtures

Small sample files, one or more per format, used by the converter tests.

## Rules

- **Under 200 KB each** (SPEC §6). A 64×64 image or a one-second clip is plenty.
- Only files that may be redistributed: generate them, or take them from a public-domain or
  CC0 source. Record where each one came from in `SOURCES.md` when the first non-generated fixture
  arrives.
- Name them `<format>-<what-is-interesting>.<ext>`, for example `heic-12mp.heic`,
  `png-transparent.png`, `docx-50-pages.docx`.
- Prefer generating fixtures with a script over committing large binaries. Odd cases — unicode
  filenames, a file with no extension, a CMYK JPEG, a GIF with several frames — matter more than
  pretty content.

## Coverage

SPEC §11 requires **every advertised route to have at least one fixture test**, and CI fails if a
route has none. `ConverterRegistry.advertisedRoutes` is what that check reads.

M0 registers no converters, so there are no routes and no fixtures yet. M1 brings the first ones:
HEIC, JPG, PNG, TIFF and BMP images.
